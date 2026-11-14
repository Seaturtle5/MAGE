extends GutTest
## Creature variants: a creature met in different shapes, picked each meeting
## with bans and wards respected (the original's gender-rolling PrepCombat).

const ROOT := "user://variant_test_packs"

const PACK := """== filter male
name: Males
genders: male

== filter female
name: Females
genders: female

== filter herm
name: Herms
genders: herm, male herm

== zone junk
name: Junkyard

== location yard
name: Yard
description: Junk everywhere.
zone: junk

== values doctor
values:
    forced: number

== form goblin
name: Goblin
sex: male
sex by preference: yes
cock:
    description: green
    change: your cock turns green
    count: 1

== creature goblin
name: Goblin
found in: junk
level: 1
hp: 10
damage: 2
form: goblin
gender: male
tags: male, female
variants:
    female:
        gender: female
        image: goblin_f
        infection sex: female
        hp: 20
    male:
        gender: male
encounter:
    A goblin appears. [if goblin is female]She[else]He[end if] grins. [ghe].

== creature saur
name: Saur
found in: nowhere
level: 1
hp: 10
gender: male herm
pick variant: in order
variants:
    herm:
        gender: male herm
    male:
        gender: male

== creature doc
name: Doctor
found in: nowhere
level: 1
hp: 10
variants:
    male:
        gender: male
        when: doctor.forced is not 2
    female:
        gender: female
        when: doctor.forced is not 1

== feat female_preferred
name: Female Preferred

== scene meet_female
fight goblin (female):
    won:
        Won against the female.
    lost:
        Lost.
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "v.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors().filter(func(e): return "goblin_f" not in str(e)), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("yard")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _counts(id: String, n: int, hunted: bool = false) -> Dictionary:
	var out := {}
	for _i in n:
		var v := VariantSystem.pick(game, id, hunted)
		out[v] = out.get(v, 0) + 1
	return out


func test_both_variants_come_up_at_random() -> void:
	var c := _counts("goblin", 200)
	assert_true(c.get("female", 0) > 60 and c.get("male", 0) > 60, str(c))


func test_a_banned_gender_is_never_met_and_the_creature_still_is() -> void:
	game.settings.banned.append("male")
	assert_eq(_counts("goblin", 50), {"female": 50})
	assert_true("goblin" in game.runner.encounter_pool("junk"), "the creature's male tag is left to its variants")
	game.settings.banned.append("female")
	assert_false("goblin" in game.runner.encounter_pool("junk"), "no variant left: never met")
	assert_false("goblin" in game.runner.encounter_pool("junk", true))


func test_a_warded_gender_only_comes_up_when_hunting() -> void:
	game.settings.warded.append("female")
	assert_eq(_counts("goblin", 50), {"male": 50})
	var c := _counts("goblin", 300, true)
	# Hunting: 1 in 3 picks the unwarded one, otherwise a fair roll: about 1/3 female.
	assert_true(c.get("female", 0) > 60 and c.get("female", 0) < 150, str(c))
	game.settings.warded.append("male")
	assert_false("goblin" in game.runner.encounter_pool("junk"), "all variants warded: only met when hunted")
	assert_true("goblin" in game.runner.encounter_pool("junk", true))


func test_in_order_takes_the_first_allowed() -> void:
	assert_eq(_counts("saur", 20), {"herm": 20})
	game.settings.banned.append("herm")
	assert_eq(_counts("saur", 20), {"male": 20})


func test_when_conditions_force_a_variant() -> void:
	game.set_value("doctor.forced", 2)
	assert_eq(_counts("doc", 20), {"female": 20})
	game.set_value("doctor.forced", 1)
	assert_eq(_counts("doc", 20), {"male": 20})


func test_the_variant_changes_fields_text_and_pronouns() -> void:
	VariantSystem.pick(game, "goblin", false, "female")
	assert_eq(game.creature_field("goblin", "gender"), "female")
	assert_eq(game.creature_field("goblin", "image"), "goblin_f")
	assert_eq(CombatSystem.number(game, "goblin", "hp", 1), 20)
	assert_true(game.adjective("goblin", "female"))
	assert_true(game.adjective("goblin", "variant female"))
	assert_false(game.adjective("goblin", "male"))
	game.apply(Effect.compile("creature goblin variant male"))
	assert_true(game.adjective("goblin", "male"))
	assert_eq(CombatSystem.number(game, "goblin", "hp", 1), 10, "the creature's own field again")


func test_an_encounter_shows_the_variant() -> void:
	var seen := {}
	for _i in 30:
		game.runner.frames.clear()
		game.runner.start_encounter("goblin")
		var text := ""
		for e in game.take_output():
			if e.type == "paragraph":
				text += TextTemplate.plain(e.spans)
		var v := VariantSystem.current(game, "goblin")
		seen[v] = true
		assert_string_contains(text, "She grins. she." if v == "female" else "He grins. he.")
		game.state.combat = {}
	assert_eq(seen.size(), 2)


func test_a_fight_can_name_its_variant_and_the_variant_infects_as_its_sex() -> void:
	game.runner.start("meet_female")
	assert_eq(VariantSystem.current(game, "goblin"), "female")
	assert_eq(BodySystem.target_sex(game, "goblin"), "female", "the female variant moves the infection toward female")
	game.state.values["creature.goblin.variant"] = "male"
	assert_eq(BodySystem.target_sex(game, "goblin"), "male")
	game.apply(Effect.compile("feat + female_preferred"))
	assert_eq(BodySystem.target_sex(game, "goblin"), "female", "a preference comes first")


func test_variants_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := """== creature c
name: C
hp: 5
pick variant: sometimes
variants:
    big:
        gender: giant
        filters: nosuch
        colour: red
        when: player is grumpy
        hp: 0

== filter f
name: F
genders: robot

== scene s
fight c (small):
    won:
        Yes.
    lost:
        No.
if c is variant tiny:
    Hm.
~ creature c variant huge
"""
	var files := {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	for part in ["Pick variant", "giant", "nosuch", "colour", "grumpy", "hp must be", "robot", "small", "tiny", "huge"]:
		assert_string_contains(text, part)
