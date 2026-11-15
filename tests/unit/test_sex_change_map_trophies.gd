extends GutTest
## The infection's sex and breast change run again (`~ sex change`, `~ breast
## change`), a form's targets changed in play (`~ form X cock length = 10`), ways
## out changed in play (`~ change north exit of X to Y`), the combat rules' and a
## creature's own `fight starts` (Hard Mode's level boost), trophies after a win,
## and a hold broken with a chosen attribute (`grapple 20% with strength`).

const ROOT := "user://sex_change_map_trophies_test_packs"

const PACK := """== region town
name: Town

== location arena
name: Arena
description: Sand.
region: town
map: 0,0
exits:
    north: hall

== location hall
name: Hall
description: A hall.
region: town
map: 0,1
exits:
    south: arena

== location garden
name: Garden
description: A garden.
region: town
map: 1,0

== form vixen
name: Vixen
sex: female
torso:
    description: furry
    change: you grow fur
cunt:
    count: 1
    depth: 6
    tightness: 4
breasts:
    size: 4
    nipples: 2

== form buck
name: Buck
sex: male
cock:
    count: 1
    length: 8
balls:
    size: 3

== creature vixen
name: Vixen
hp: 50
level: 2
damage: 6
stats: strength 10, dexterity 10, stamina 10, perception 10, intelligence 10, charisma 10
form: vixen

== creature ram
name: Ram
hp: 50
level: 2
damage: 6
stats: strength 10, dexterity 10, stamina 10, perception 10, intelligence 10, charisma 10
form: buck
fight starts:
    if mode hard:
        ~ enemy.max_hp = 99 quietly
        ~ enemy.hp = enemy.max_hp quietly
        The ram squares up.

== creature wolf
name: Wolf
hp: 5
level: 1
damage: 1
stats: strength 10, dexterity 1, stamina 10, perception 10, intelligence 10, charisma 10
loot: gem 100%
trophies: fur 100%, food 100%, bone 0%
defeated:
    The wolf limps off.

== creature bear
name: Bear
hp: 500
level: 1
damage: 10
stats: strength 1, dexterity 1000, stamina 10, perception 10, intelligence 10, charisma 10
special: grapple 100% with strength ignoring armor
escape: Free of the hug.
struggle: Still crushed.

== creature octopus
name: Octopus
hp: 500
level: 1
damage: 10
stats: strength 1, dexterity 1000, stamina 10, perception 10, intelligence 10, charisma 10
special: grapple 100%
escape: Slipped out.
struggle: Still held.

== item fur
name: fur
description: Fur.

== item food
name: food
description: Food.

== item bone
name: bone
description: A bone.

== item gem
name: gem
description: A gem.

== game_mode hard
name: Hard

== combat_rules basic
fight starts:
    if mode hard and enemy.level < player.level:
        ~ fight.debit = player.level - enemy.level quietly
        ~ enemy.level + fight.debit quietly
        ~ enemy.max_hp + fight.debit * 4 quietly
        ~ enemy.hp + fight.debit * 4 quietly
        ~ enemy.damage + fight.debit / 3 quietly
        ~ enemy.dexterity + fight.debit / 5 quietly
    ~ fight.no_surprise = yes quietly
trophy prompt: Snatch a trophy:
no trophy label: Nevermind
no trophy: You take nothing.

== scene change_map
~ change east exit of arena to garden
~ change north exit of arena to nothing
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "main.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 5)
	game.start("arena")
	game.set_value("player.maxhp", 100000)
	game.set_value("player.hp", 100000)
	for path in ["player.cocks", "player.cock.length", "player.balls.size", "player.cunts", "player.cunt.depth",
			"player.cunt.tightness", "player.breasts.size", "player.nipples"]:
		game.set_value(path, 0)
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type in ["paragraph", "notice"]:
			out.append(TextTemplate.plain(e.spans) if e.type == "paragraph" else str(e.text))
	return "\n".join(out)


func test_sex_change_runs_again_toward_a_named_strain() -> void:
	game.apply(Effect.compile("sex change toward vixen"))
	assert_eq(int(game.value("player.cunts")), 1, "a neuter player gains the vixen's sex")
	assert_eq(int(game.value("player.cunt.depth")), 3)
	game.apply(Effect.compile("sex change toward vixen"))
	assert_eq(int(game.value("player.cunt.depth")), 4, "each run moves once more toward the target")
	game.apply(Effect.compile("sex change toward ram"))
	assert_eq(int(game.value("player.cocks")), 1, "a creature stands for its form (the ram's buck)")


func test_sex_change_follows_the_strain_met_last() -> void:
	CombatSystem.begin(game, "vixen")
	game.state.combat = {}
	game.apply(Effect.compile("sex change"))
	assert_eq(int(game.value("player.cunts")), 1, "the creature fought last")
	game.apply(Effect.compile("transform into buck"))
	game.apply(Effect.compile("sex change"))
	assert_eq(BodySystem.strain(game), "buck", "a transformation comes later than the fight")


func test_breast_change_and_changed_form_targets() -> void:
	game.apply(Effect.compile("breast change toward vixen"))
	assert_eq(int(game.value("player.nipples")), 2)
	assert_eq(int(game.value("player.breasts.size")), 2)
	game.set_value("player.cunts", 1)
	game.set_value("player.cunt.depth", 4)
	game.set_value("player.cunt.tightness", 4)
	game.apply(Effect.compile("form vixen cunt depth = 30"))
	assert_eq(BodySystem.fields(game, "vixen", "cunt").depth, "30", "the changed target")
	game.apply(Effect.compile("sex change toward vixen"))
	assert_eq(int(game.value("player.cunt.depth")), 13, "moves toward the changed target")
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(game.state.to_dict())))
	assert_eq(int(saved.values["form.vixen.cunt.depth"]), 30, "kept in a save")


func test_ways_out_change_in_play_and_are_saved() -> void:
	game.runner.start("change_map")
	game.take_output()
	var ways: Array = game.exits_of("arena")
	assert_eq(ways, [["east", "garden"]], "north removed, east added")
	assert_eq(game.exits_of("hall"), [["south", "arena"]], "other places keep theirs")
	var arena: Dictionary = {}
	for place: Dictionary in game.map_data("town").places:
		if place.id == "arena":
			arena = place
	assert_eq(arena.exits, ["garden"], "the map draws the new way")
	assert_false(game.runner.act("go", "north"), "the removed way is gone")
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(game.state.to_dict())))
	assert_eq(saved.exits.get("arena", {}).get("east", ""), "garden", "kept in a save")
	assert_true(game.runner.act("go", "east"))
	assert_eq(game.state.location, "garden")


func test_hard_mode_boost_and_a_creatures_own_preparation() -> void:
	game.set_value("player.level", 8)
	CombatSystem.begin(game, "vixen")
	assert_eq(int(game.value("enemy.level")), 2, "no boost outside Hard Mode")
	game.state.combat = {}
	game.settings.mode = ["hard"]
	CombatSystem.begin(game, "vixen")
	assert_eq(int(game.value("enemy.level")), 8, "the creature rises to the player's level")
	assert_eq(int(game.value("enemy.max_hp")), 74)
	assert_eq(int(game.value("enemy.hp")), 74)
	assert_eq(int(game.value("enemy.damage")), 8)
	assert_eq(int(game.value("enemy.dexterity")), 11)
	game.state.combat = {}
	game.take_output()
	CombatSystem.begin(game, "ram")
	assert_eq(int(game.value("enemy.level")), 8, "the rules' boost first")
	assert_eq(int(game.value("enemy.max_hp")), 99, "then the creature's own numbers")
	assert_string_contains(_text(), "The ram squares up.")


func test_trophies_offer_one_pick_instead_of_loot() -> void:
	game.runner.start_encounter("wolf")
	game.take_output()
	game.set_value("enemy.hp", -100)
	game.runner.combat_action("pass")
	var choices: Dictionary = {}
	for e in game.take_output():
		if e.type == "choices":
			choices = e
	assert_eq(choices.get("title", ""), "Snatch a trophy:")
	assert_eq(choices.options.map(func(o): return o.text), ["fur", "food", "Nevermind"], "the 0% bone never comes up")
	assert_true(game.runner.choose(0))
	assert_eq(int(game.value("player.carried.fur")), 1)
	assert_eq(int(game.value("player.carried.food")), 0, "only one trophy")
	assert_eq(int(game.value("player.carried.gem")), 0, "no loot beside trophies")
	assert_string_contains(_text(), "The wolf limps off.")


func test_taking_no_trophy() -> void:
	game.runner.start_encounter("wolf")
	game.set_value("enemy.hp", -100)
	game.runner.combat_action("pass")
	game.take_output()
	assert_true(game.runner.choose(2))
	assert_string_contains(_text(), "You take nothing.")
	assert_eq(int(game.value("player.carried.fur")), 0)


func test_a_hold_is_broken_with_its_attribute() -> void:
	assert_eq(CombatSystem.hold_attribute(game, "bear"), "strength")
	assert_eq(CombatSystem.hold_attribute(game, "octopus"), "dexterity", "dexterity by default")
	assert_eq(CombatSystem._hold_armor(game, "bear"), "no armor")
	assert_eq(CombatSystem._hold_armor(game, "octopus"), "normal")
	game.set_value("player.strength", 1000)
	game.set_value("player.dexterity", 1)
	for id in ["bear", "octopus"]:
		CombatSystem.begin(game, id)
		game.state.combat.grappled = true
		game.take_output()
		CombatSystem.act(game, "struggle")
		var text := _text()
		if id == "bear":
			assert_string_contains(text, "Free of the hug.", "strength breaks the bear hug")
		else:
			assert_string_contains(text, "Still held.", "dexterity is too low to slip the octopus")
		game.state.combat = {}


func test_new_syntax_is_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := """== location yard
name: Yard
description: A yard.

== creature imp
name: Imp
trophies: fur, horn 50%

== creature snake
name: Snake
special: grapple 20% with wisdom

== creature eel
name: Eel
special: grapple 20% sideways

== scene s
~ change north exit of nowhere_place to yard
~ change north exit of yard to nothing
~ sex change toward nobody
~ breast change
~ form no_form cock length = 3
"""
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	assert_string_contains(text, "Trophies are written")
	assert_string_contains(text, "horn")
	assert_string_contains(text, "nowhere_place")
	assert_string_contains(text, "nobody")
	assert_string_contains(text, "no_form")
	assert_string_contains(text, "A hold is broken with an attribute")
	assert_string_contains(text, "optionally followed by")
	assert_false(text.contains("unknown effect"), "every new effect is recognized")
