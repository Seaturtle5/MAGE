extends GutTest
## Heat cycles: a strain's heat or the default, female and mpreg heat, the
## policy's conditions and texts, and the effects that drive or end heat.

const ROOT := "user://heat_test_packs"

const PACK := """== values log
values:
    starts: number
    turns: number
    ends: number

== location room
name: Room
description: A room.

== feat mpreg
name: MPreg

== level heat
name: Heat
default: normal
options:
    off: No heat.
    normal: Heat.
    intense: More heat.

== heat_rules policy
default: plain
female when: player is female
mpreg when: player is not female and player has feat mpreg
off when: level heat is off
intense when: level heat is intense
intense lengthens: 1 in 1
intense quickens: 1 in 1
vulnerable:
    VULNERABLE
not vulnerable:
    COOL
switches:
    SWITCH
ends:
    ENDS
    ~ player.libido = player.libido / 2 quietly

== heat plain
cycle: 2
duration: 1
trigger:
    PLAIN TRIGGER
mpreg trigger:
    PLAIN MPREG
each turn:
    ~ log.turns + 1 quietly

== heat vixen
cycle: 3
duration: 1
mpreg: no
trigger:
    VIXEN TRIGGER
start:
    ~ log.starts + 1 quietly
each turn:
    ~ libido + 5 quietly
end:
    ~ log.ends + 1 quietly

== form vixen
name: Vixen
sex: female
cunt:
    description: a vixen's slit
    change: your sex turns vulpine
    count: 1
torso:
    description: furred
    change: you grow fur

== form hound
name: Hound
sex: male
cock:
    description: a canine cock
    change: your cock turns canine
    count: 1
torso:
    description: furred
    change: you grow fur

== form statue
name: Statue
sex: female
heat: none
cunt:
    description: stone
    change: your sex turns to stone
    count: 1
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "heat.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 1)
	game.start("room")
	game.set_value("player.humanity", 100)


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func _turns(n: int) -> String:
	var out := ""
	for _i in n:
		game.pass_turn()
		out += _text()
	return out


func test_a_human_body_has_no_heat() -> void:
	assert_eq(HeatSystem.kind_now(game), "")
	_turns(30)
	assert_false(game.adjective("player", "in heat"))


func test_a_strain_with_its_own_heat_cycles_through_it() -> void:
	game.apply(Effect.compile("transform into vixen"))
	_text()
	assert_true(game.adjective("player", "vulnerable to heat"))
	var first := _turns(1)
	assert_string_contains(first, "VULNERABLE")
	# Cycle 3 days, 1 in heat: heat starts at turn 16 of 24.
	var out := _turns(15)
	assert_string_contains(out, "VIXEN TRIGGER")
	assert_true(game.adjective("player", "in female heat"))
	assert_eq(int(game.value("log.starts")), 1)
	assert_eq(int(game.value("player.heat_ends_in")), 8)
	game.set_value("player.libido", 40)
	_turns(8)
	assert_true(game.adjective("player", "in heat"), "still in heat through the end of the cycle")
	assert_eq(int(game.value("player.libido")), 80, "libido + 5 each heat turn")
	var end := _turns(1)
	assert_string_contains(end, "ENDS")
	assert_false(game.adjective("player", "in heat"))
	assert_eq(int(game.value("log.ends")), 1)
	assert_eq(int(game.value("player.libido")), 40, "the policy halves libido when heat ends")
	assert_eq(int(game.value("player.heat_starts_in")), 16, "the cycle starts over")


func _male_hound() -> void:
	game.apply(Effect.compile("transform into hound"))
	game.set_value("player.cunts", 0)


func test_a_form_can_have_no_heat() -> void:
	game.apply(Effect.compile("transform into statue"))
	assert_false(game.adjective("player", "vulnerable to heat"), "heat: none")


func test_other_strains_use_the_default_heat() -> void:
	_male_hound()
	assert_false(game.adjective("player", "vulnerable to heat"), "a male needs the mpreg feat")
	game.apply(Effect.compile("feat + mpreg"))
	assert_true(game.adjective("player", "vulnerable to heat"))
	var out := _turns(8)
	assert_string_contains(out, "PLAIN MPREG", "the default heat, mpreg kind")
	assert_true(game.adjective("player", "in mpreg heat"))


func test_a_heat_without_mpreg_falls_back_to_the_default() -> void:
	assert_eq(HeatSystem.heat_of(game, "vixen", "female"), "vixen")
	assert_eq(HeatSystem.heat_of(game, "vixen", "mpreg"), "plain")


func test_heat_switches_kind_when_the_body_changes() -> void:
	_male_hound()
	game.apply(Effect.compile("feat + mpreg"))
	_turns(8)
	assert_true(game.adjective("player", "in mpreg heat"))
	game.set_value("player.cunts", 1)
	game.set_value("player.body.cunt", "hound")
	var out := _turns(1)
	assert_string_contains(out, "SWITCH")
	assert_true(game.adjective("player", "in female heat"))


func test_losing_the_strain_ends_vulnerability() -> void:
	game.apply(Effect.compile("transform into vixen"))
	_turns(2)
	game.apply(Effect.compile("reset to human"))
	assert_string_contains(_turns(1), "COOL")
	assert_eq(int(game.value("player.heat_turns")), 0)


func test_the_level_turns_heat_off_or_makes_it_intense() -> void:
	game.apply(Effect.compile("transform into vixen"))
	game.set_level("heat", "off")
	_turns(30)
	assert_false(game.adjective("player", "in heat"))
	game.set_level("heat", "intense")
	# Quickens by one each turn before heat (1 in 1): heat starts after 9 turns, not 16.
	_turns(9)
	assert_true(game.adjective("player", "in heat"))


func test_drive_end_extend_and_reset() -> void:
	game.apply(Effect.compile("transform into vixen"))
	_turns(1)
	game.apply(Effect.compile("drive heat"))
	assert_eq(int(game.value("player.heat_turns")), 2, "brings heat a turn closer")
	game.apply(Effect.compile("player.heat_turns = 15"))
	game.apply(Effect.compile("drive heat now"))
	assert_true(game.adjective("player", "in heat"), "now: runs a heat turn at once")
	assert_eq(int(game.value("player.heat_ends_in")), 7)
	game.apply(Effect.compile("extend heat by 4 turns"))
	assert_eq(int(game.value("player.heat_ends_in")), 11)
	_turns(10)
	assert_true(game.adjective("player", "in heat"), "an extended heat holds its place")
	assert_eq(int(game.value("player.heat_ends_in")), 1)
	game.apply(Effect.compile("end heat"))
	assert_false(game.adjective("player", "in heat"))
	assert_eq(int(game.value("log.ends")), 1)
	game.apply(Effect.compile("extend heat by 3 turns"))
	assert_eq(int(game.value("player.heat_starts_in")), 19, "out of heat, the next one comes later")
	game.apply(Effect.compile("reset heat"))
	assert_eq(int(game.value("player.heat_turns")), 0)


func test_heat_is_paused_and_skipped_in_fights() -> void:
	game.apply(Effect.compile("transform into vixen"))
	game.apply(Effect.compile("player.heat_paused = yes"))
	_turns(20)
	assert_eq(int(game.value("player.heat_turns")), 0)


func test_heat_definitions_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := "== heat h\ncycle: 2\nduration: 5\nfemale: maybe\n\n== heat_rules r\ndefault: nothing\nintense lengthens: often\nfemale when: player is grumpy\n\n== form f\nname: F\nheat: missing\n"
	var files := {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	assert_string_contains(text, "longer than its cycle")
	assert_string_contains(text, "Female must be yes or no")
	assert_string_contains(text, "N in M")
	assert_string_contains(text, "nothing")
	assert_string_contains(text, "missing")
	assert_string_contains(text, "grumpy")


func test_a_scene_can_change_the_heat_level() -> void:
	game.apply(Effect.compile("level heat = intense"))
	assert_eq(game.level("heat"), "intense")
	assert_true(Condition.evaluate(Condition.compile("level heat is intense"), game))
	assert_true(Effect.compile("level heat = sometimes").op == "set_level", "the option is checked on load")
	assert_false(game.adjective("player", "heat paused"))
	game.apply(Effect.compile("player.heat_paused = yes"))
	assert_true(game.adjective("player", "heat paused"))
