extends GutTest
## Pregnancy: who can carry, the impregnation roll, gestation, birth and the
## children, MPreg, the Selective Mother question, and creatures the player sires on.

const ROOT := "user://pregnancy_test_packs"

const PACK := """== values log
values:
    conceived: number
    turns: number
    births: number
    children: number
    afters: number
    sired: number
    sired_births: number

== location room
name: Room
description: A room.

== feat mpreg
name: MPreg

== feat sterile
name: Sterile

== feat storybirth
name: Story birth

== hook story_birth
on: instead of birth
when: player has feat storybirth
do:
    STORY BIRTH

== hook story_child
on: instead of child
when: player has feat storybirth
do:
    STORY CHILD [child.number]

== hook after_the_birth
on: after birth
do:
    HOOK AFTER

== feat fertile
name: Fertile

== feat selective_mother
name: Selective Mother

== feat breeding_true
name: Breeding True

== feat wild_womb
name: Wild Womb

== tag mpreg
name: MPreg

== form wolf
name: Wolf
sex: male
offspring gender: male 1 in 1
head:
    description: a wolf's head
    change: your head turns lupine
torso:
    description: furred
    change: you grow fur
tail:
    description: a bushy tail
    change: a tail grows

== form doe
name: Doe
sex: female
scale: 3
torso:
    description: sleek
    change: you turn sleek
cunt:
    description: a slit
    change: your sex changes
    count: 1

== creature wolf
name: Wolf
level: 1
hp: 10
form: wolf
gender: male

== creature doe
name: Doe
level: 1
hp: 10
form: doe
gender: female
tags: mpreg

== creature alpha
name: Alpha
level: 1
hp: 10
form: wolf
gender: male
unique: yes

== pregnancy_rules test
female when: player is female and player does not have feat sterile
male when: player has feat mpreg and player does not have feat sterile
odds: 1 in 1
odds modifiers:
    player has feat fertile: -0
ask when: player has feat selective_mother
gestation: 6
quickens:
    player has feat fertile: 1 in 1
extra children: 0, 0
extra child bonus:
    player has feat fertile: +100
most children: 2
child like father when: player has feat breeding_true
feral when: player has feat wild_womb
child genders:
    female: 1
personalities: calm
albino: 0 in 100
melanism: 0 in 100
sire when: player does not have feat sterile
sire odds: 10 in 10
sire turns: 3
ask:
    ASK [pregnancy.father_name]
    * Yes
        ~ accept pregnancy
    * No
        ~ end pregnancy
conceived:
    CONCEIVED [pregnancy.kind]
    ~ log.conceived + 1 quietly
each turn:
    ~ log.turns + 1 quietly
birth:
    BIRTH [pregnancy.kind] of [pregnancy.litter]
    ~ log.births + 1 quietly
child:
    CHILD [child.number] [child.gender] [child.head] [child.torso] [child.personality][if child.feral] FERAL[end if]
    ~ child.home = bunker
    ~ log.children + 1 quietly
    ~ record child
after birth:
    AFTER [pregnancy.litter]
    ~ log.afters + 1 quietly
sired:
    ~ log.sired + 1 quietly
sired birth:
    SIRED BIRTH [pregnancy.sired_name]
    ~ log.sired_births + 1 quietly

== scene roll
~ impregnation chance by wolf
Done.

== scene sure_self
~ impregnate self
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "preg.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 5)
	game.start("room")
	game.take_output()


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
		out += _text() + "\n"
	return out


func _v(path: String) -> Variant:
	return game.value(path)


func test_who_can_carry() -> void:
	assert_true(_v("pregnancy.fpreg_ok"), "a female body")
	assert_true(_v("pregnancy.fpreg_able"))
	assert_false(_v("pregnancy.mpreg_ok"), "no MPreg feat")
	game.apply(Effect.compile("feat + sterile"))
	assert_false(_v("pregnancy.impreg_ok"), "sterile")
	game.apply(Effect.compile("feat - sterile"))
	game.set_value("pregnancy.hijack", true)
	assert_false(_v("pregnancy.fpreg_able"), "a hijacked womb")
	assert_false(_v("pregnancy.fem_vacant"))
	assert_true(_v("pregnancy.fpreg_ok"))


func test_a_roll_conceives_with_the_father_and_the_kind() -> void:
	game.runner.start("roll")
	var text := _text()
	assert_string_contains(text, "CONCEIVED female")
	assert_string_contains(text, "Done.")
	assert_eq(int(_v("pregnancy.gestation")), 6)
	assert_true(_v("pregnancy.fpreg_now"))
	assert_true(_v("pregnancy.impreg_now"))
	assert_false(_v("pregnancy.fpreg_able"), "already carrying")
	assert_true(game.adjective("player", "pregnant"))
	assert_eq(str(_v("pregnancy.father")), "wolf")
	assert_eq(str(_v("pregnancy.father_name")), "wolf")
	game.runner.start("roll")
	assert_eq(int(_v("log.conceived")), 1, "no second pregnancy while carrying")


func test_gestation_birth_and_the_child() -> void:
	game.apply(Effect.compile("feat + breeding_true"))
	game.runner.start("roll")
	_text()
	var out := _turns(5)
	assert_eq(int(_v("log.turns")), 5, "each turn runs while pregnant")
	assert_false(out.contains("BIRTH"))
	out = _turns(1)
	assert_string_contains(out, "BIRTH female of 1")
	assert_string_contains(out, "CHILD 1 male wolf wolf calm", "the wolf's offspring are male; breeding true: the father's parts")
	assert_string_contains(out, "AFTER 1")
	assert_eq(int(_v("pregnancy.gestation")), 0)
	assert_false(game.adjective("player", "pregnant"))
	assert_eq(int(_v("pregnancy.births")), 1)
	var kids: Array = _v("pregnancy.offspring")
	assert_eq(kids.size(), 1)
	assert_eq(kids[0].home, "bunker")
	assert_eq(kids[0].head_form, "wolf")
	assert_true(out.find("BIRTH") < out.find("CHILD") and out.find("CHILD") < out.find("AFTER"), "birth, child, after birth in order")


func test_fertility_quickens_and_brings_twins() -> void:
	game.apply(Effect.compile("feat + fertile"))
	game.runner.start("roll")
	_text()
	var out := _turns(3)
	assert_string_contains(out, "BIRTH female of 2", "two turns of progress each turn; litter bonus +100")
	assert_string_contains(out, "CHILD 1")
	assert_string_contains(out, "CHILD 2")
	assert_eq(int(_v("log.afters")), 1)


func test_mpreg_and_self_impregnation() -> void:
	game.set_value("player.cunts", 0)
	game.set_value("player.cocks", 1)
	assert_false(_v("pregnancy.impreg_able"))
	game.apply(Effect.compile("feat + mpreg"))
	assert_true(_v("pregnancy.mpreg_able"))
	game.runner.start("sure_self")
	assert_string_contains(_text(), "CONCEIVED male")
	assert_true(_v("pregnancy.mpreg_now"))
	assert_true(_v("pregnancy.self"))
	assert_false(_v("pregnancy.male_vacant"))
	_turns(6)
	assert_eq(int(_v("pregnancy.mpreg_count")), 1, "male births count")
	assert_eq(str(game.state.values.get("pregnancy.offspring")[0].torso_form), "human", "a self-made child is like the mother")


func test_birth_waits_while_the_body_cannot_carry() -> void:
	game.runner.start("roll")
	_text()
	_turns(5)
	game.apply(Effect.compile("feat + sterile"))
	assert_false(_turns(3).contains("BIRTH"))
	assert_eq(int(_v("pregnancy.gestation")), 1)
	game.apply(Effect.compile("feat - sterile"))
	assert_string_contains(_turns(1), "BIRTH")


func test_selective_mother_is_asked() -> void:
	game.apply(Effect.compile("feat + selective_mother"))
	game.runner.start("roll")
	assert_string_contains(_text(), "ASK wolf")
	game.runner.choose(1)
	_text()
	assert_false(game.adjective("player", "pregnant"), "refused")
	game.runner.start("roll")
	_text()
	game.runner.choose(0)
	assert_string_contains(_text(), "CONCEIVED")
	assert_true(game.adjective("player", "pregnant"))


func test_effects_end_and_give_birth() -> void:
	game.runner.start("roll")
	_text()
	game.apply(Effect.compile("end pregnancy"))
	assert_false(game.adjective("player", "pregnant"))
	game.runner.start("roll")
	_text()
	game.apply(Effect.compile("pregnancy faster by 10"))
	assert_eq(int(_v("pregnancy.gestation")), 1, "faster, but never past the last turn")
	game.apply(Effect.compile("give birth"))
	assert_string_contains(_text(), "CHILD 1")
	game.apply(Effect.compile("feat + wild_womb"))
	game.apply(Effect.compile("pregnancy.gestation = 1"))
	game.set_value("pregnancy.kind", "female")
	assert_string_contains(_turns(1), "FERAL")
	assert_eq(int(_v("pregnancy.feral_births")), 1)


func test_the_player_sires_young_on_creatures() -> void:
	game.set_value("player.cocks", 1)
	game.apply(Effect.compile("sex alpha receives vaginal from player"))
	assert_eq(int(_v("log.sired")), 0, "unique creatures are not")
	game.apply(Effect.compile("sex wolf receives anal from player"))
	assert_eq(int(_v("log.sired")), 0, "anal needs the mpreg tag")
	game.apply(Effect.compile("sex doe receives anal from player"))
	assert_eq(int(_v("log.sired")), 1)
	game.apply(Effect.compile("sex doe receives vaginal from player"))
	assert_eq(int(_v("log.sired")), 1, "one at a time")
	var out := _turns(3)
	assert_string_contains(out, "SIRED BIRTH doe")
	assert_eq(int(_v("pregnancy.feral_births")), 1)


func test_heat_waits_while_pregnant() -> void:
	assert_true(_v("pregnancy.fpreg_able"))
	game.runner.start("roll")
	_text()
	assert_false(Condition.evaluate(Condition.compile("player is female and pregnancy.fpreg_able"), game),
		"the heat rules' condition fails while carrying")


func test_pregnancy_rules_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := """== pregnancy_rules r
female when: player is grumpy
odds: often
gestation: soon
extra children: 1, lots
odds modifiers:
    player has feat fertile: minus three
child genders:
    robot: 1
fathers:
    nobody: player is female

== form f
name: F
offspring gender: mostly male

== scene s
~ impregnate by nobody
~ pregnancy.impreg_ok = yes
"""
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	for part in ["grumpy", "Odds is a chance", "Gestation is a number", "Extra children", "whole number such as", "robot", "nobody", "Offspring gender", "cannot be set"]:
		assert_string_contains(text, part)


func test_hooks_take_the_place_of_a_birth_and_follow_it() -> void:
	game.apply(Effect.compile("feat + storybirth"))
	game.runner.start("roll")
	_text()
	_turns(5)
	var out := _turns(1)
	assert_string_contains(out, "STORY BIRTH")
	assert_false(out.contains("BIRTH female"), "the rules' birth script does not play")
	assert_string_contains(out, "STORY CHILD 1")
	assert_false(out.contains("CHILD 1 "), "nor the rules' child script")
	assert_string_contains(out, "AFTER 1")
	assert_true(out.find("AFTER 1") < out.find("HOOK AFTER"), "after birth hooks follow the rules' own")
