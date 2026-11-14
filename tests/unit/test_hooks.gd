extends GutTest
## Hooks run content at a moment of play (`on: each turn`), and a form's
## `each turn` runs while the player has that body.

const ROOT := "user://hook_test_packs"

const PACK := """== values clock
values:
    ticks: number
    calls: number

== location room
name: Room
description: A room.

== hook ticking
on: each turn
when: clock.ticks < 2
do:
    ~ clock.ticks + 1 quietly

== hook broken
on: each turn
when: player is fighting
while incapacitated: skip
do:
    ~ clock.ticks + 100 quietly

== item pebble
name: pebble
description: A small pebble.

== meter buzz
value: player.buzz
decay: 1
stages:
    1: buzzed

== condition buzzed
name: Buzzed
blocks rest: yes

== form selkie
name: Selkie
sex: female
sex by preference: yes
torso:
    description: sleek
    change: you turn sleek

== form siren
name: Siren
torso:
    description: a siren's body
    change: your body turns sleek
each turn:
    You hear a song.
    ~ clock.calls + 1 quietly
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "hooks.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 1)
	game.start("room")


func after_each() -> void:
	game.dispose()


func test_a_hook_runs_each_turn_while_its_condition_holds() -> void:
	for _i in 4:
		game.pass_turn()
	assert_eq(int(game.value("clock.ticks")), 2, "runs twice, then 'when' stops it; the fight-only hook never runs")


func test_a_form_turn_hook_runs_while_the_player_has_that_body() -> void:
	game.pass_turn()
	assert_eq(int(game.value("clock.calls")), 0, "a human body has no turn hook")
	game.apply(Effect.compile("transform into siren"))
	game.pass_turn()
	game.pass_turn()
	assert_eq(int(game.value("clock.calls")), 2)


func test_hooks_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": "== hook h\non: sometimes\nwhen: nonsense here\n"}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	assert_string_contains(text, "with one of: each turn")
	assert_string_contains(text, "do:")


func test_infect_with_the_players_own_strain() -> void:
	game.apply(Effect.compile("transform into siren"))
	var e := Effect.compile("infect with player body")
	assert_eq(e.part, "torso")
	game.apply(e)
	assert_eq(game.part_form("player", "torso"), "siren", "infecting with the body's own strain keeps it")


func test_a_form_can_follow_the_players_preferred_sex() -> void:
	assert_eq(BodySystem.target_sex(game, "selkie"), "female", "no preference: the form's own sex")
	game.state.feats.append("male_preferred")
	assert_eq(BodySystem.target_sex(game, "selkie"), "male")
	assert_eq(BodySystem.target_sex(game, "siren"), "", "without the field the preference is not used")


func test_random_numbers_in_expressions() -> void:
	assert_true(Condition.evaluate(Condition.compile("random 5 to 5 = 5"), game))
	for _i in 20:
		var v := int(Expr.evaluate(Expr.parse("10 + random 1 to 3"), game))
		assert_true(v >= 11 and v <= 13, str(v))
	assert_true(Condition.evaluate(Condition.compile("random 5 to 80 > random 0 to clock.ticks + 1"), game), "a roll that is always higher")
	assert_true(Expr.parse("random 1").has("error"))


func test_how_many_items_the_player_carries() -> void:
	assert_eq(int(game.value("player.carried.pebble")), 0)
	game.apply(Effect.compile("give pebble 3"))
	game.apply(Effect.compile("clock.calls = player.carried.pebble * 2"))
	assert_eq(int(game.value("clock.calls")), 6)


func test_a_pack_meter_adds_a_player_value_whose_stage_can_block_rest() -> void:
	game.apply(Effect.compile("meter buzz + 2"))
	assert_eq(int(game.value("player.buzz")), 2)
	assert_eq(RestSystem.blocking_condition(game), "buzzed")
	game.pass_turn()
	game.pass_turn()
	assert_eq(int(game.value("player.buzz")), 0)
	assert_eq(RestSystem.blocking_condition(game), "", "the stage ends when the meter wears off")
