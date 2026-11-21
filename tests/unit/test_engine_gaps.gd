extends GutTest
## Smaller engine gaps found while porting: a creature's attack scripts that give
## items and break the page; a warning for choices in scenes played for each
## companion; characters placed nowhere; fight values changed by a creature's
## description (in `fight starts:`, never in its encounter); weapon numbers
## changed with limits.

const ROOT := "user://engine_gaps_packs"

const PACK := """== zone plains
name: Plains

== text marks_line
Old scars.

== extend text marks_line
A fresh bite.

== scene greet
Hello.

== extend scene greet
Welcome back.

== location field
name: Field
zone: plains
description: Tall grass.

== values tally
values:
    blows: number 0

== item fruit
name: fruit
description: A fruit.

== creature tree
name: Tree
found in: nowhere
hp: 60
level: 10
damage: 3
stats: strength 10, dexterity 200, stamina 10, perception 10, intelligence 10, charisma 10
fight starts:
    ~ fight.no_surprise = 1
attack: -> tree_attack

== scene tree_attack
if tally.blows = 2:
    A branch falls.
    ~ give fruit
    ---
    You wake up.
    ~ enemy strike for 1
    ~ cancel blow
    ~ end fight
else:
    You trip.
    ~ tally.blows + 1 quietly
    ~ enemy.hp = 60

== creature dozer
name: Dozer
found in: nowhere
hp: 60
level: 10
damage: 3
stats: strength 10, dexterity 200, stamina 10, perception 10, intelligence 10, charisma 10
fight starts:
    ~ fight.no_surprise = 1
attack:
    It yawns.
    ---
    It shoves you.

== character fang
name: Fang
lives at: field

== character ghost
name: Ghost

== item club
name: club
description: A club.
weapon:
    damage: 5

== values twins
values:
    lead_hp: number

== creature twin
name: Twin
found in: nowhere
hp: 40
level: 1
damage: 3
stats: strength 10, dexterity 10, stamina 10, perception 10, intelligence 10, charisma 10
fight starts:
    ~ twins.lead_hp = enemy.hp quietly
    play twin_desc

== scene twin_desc
The twins pick a leader.
~ enemy.hp = 25 quietly
~ enemy.dexterity + 4 quietly

== scene meet_twin
fight twin:
    won:
        Won.

== scene meet_tree
fight tree:
    won:
        Felled.
    ended:
        The tree is gone.
After the tree.

== scene meet_dozer
fight dozer:
    won:
        Done.
"""

var game: Game


func _load(text: String, folder: String) -> ContentDB:
	DirAccess.make_dir_recursive_absolute(folder + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "content.fsc": text}
	for name: String in files:
		var fa := FileAccess.open(folder + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([folder])
	return db


func before_each() -> void:
	var db := _load(PACK, ROOT)
	assert_eq(db.errors().map(func(d): return "%d %s" % [d.line, d.message]), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("field")
	game.set_value("player.maxhp", 1000)
	game.set_value("player.hp", 1000)
	game.take_output()


func after_each() -> void:
	game.dispose()


func _said() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
		elif e.type in ["notice", "title"]:
			out.append(str(e.text))
		elif e.type == "page_break":
			out.append("{continue}")
	return "\n".join(out)


func _diagnostics(text: String, folder: String) -> Array:
	var db := _load(text, folder)
	return db.diagnostics.map(func(d): return "%s %d %s" % [d.severity, d.line, d.message])


# --- 1. Attack scripts that give items and break the page --------------------

func test_an_attack_gives_items_and_breaks_the_page_before_ending_the_fight() -> void:
	game.runner.start("meet_tree")
	assert_eq(game.runner.status, "combat")
	game.take_output()
	var said := ""
	for _i in 60:
		if game.runner.status != "combat":
			break
		game.runner.combat_action("pass")
		said = _said()
	assert_eq(game.runner.status, "continue", "the attack's page break waits for Continue")
	assert_string_contains(said, "A branch falls.")
	assert_string_contains(said, "Gained: fruit")
	assert_true(said.ends_with("{continue}"), "nothing after the break is shown yet: " + said)
	assert_false(said.contains("You wake up."))
	assert_eq(int(game.state.inventory.get("fruit", 0)), 1, "the attack gave the item")
	var hp := int(game.value("player.hp"))
	assert_true(game.runner.proceed())
	said = _said()
	assert_string_contains(said, "You wake up.")
	assert_string_contains(said, "You take 1 damage!")
	assert_string_contains(said, "The tree is gone.", "the fight ended with no winner")
	assert_string_contains(said, "After the tree.")
	assert_eq(int(game.value("player.hp")), hp, "the blow had already landed for 1, once")
	assert_eq(game.last_fight, "ended")
	assert_eq(game.runner.status, "idle")


func test_after_an_attack_page_break_the_fight_goes_on() -> void:
	game.runner.start("meet_dozer")
	game.take_output()
	var said := ""
	for _i in 60:
		game.runner.combat_action("pass")
		said = _said()
		if said.contains("It yawns."):
			break
	assert_eq(game.runner.status, "continue")
	assert_false(said.contains("It shoves you."))
	assert_true(game.runner.proceed())
	var events: Array = game.output.duplicate()
	said = _said()
	assert_string_contains(said, "It shoves you.")
	assert_true(events.any(func(e): return e.type == "combat"), "the fight is shown again")
	assert_eq(game.runner.status, "combat", "and goes on")
	# Saved while waiting, the page is still waiting when loaded.
	game.runner.combat_action("pass")
	if game.runner.status == "continue":
		var frames := game.runner.save_frames()
		game.runner.load_frames(frames)
		assert_eq(game.runner.status, "continue")


func test_the_validator_lets_fight_scripts_give_items_and_break_pages() -> void:
	var all := _diagnostics(PACK, ROOT + "_ok")
	assert_eq(all.filter(func(m: String) -> bool: return m.begins_with("error")), [])
	var bad := """== creature brute
name: Brute
found in: nowhere
attack: -> brute_attack

== scene brute_attack
Choose.
* One
    One.
* Two
    Two.
"""
	all = _diagnostics(bad, ROOT + "_bad1")
	assert_true(all.any(func(m: String) -> bool: return "can only hand over to scenes" in m), str(all))


# --- 3. Choices in a scene played for each companion -------------------------

func test_the_validator_warns_of_choices_in_scenes_played_for_each_companion() -> void:
	var text := """== character ann
name: Ann
companion:
    name: Ann

== scene ask_pet
Do you pet [companion.name]?
* Yes
    You do.
* No
    You don't.

== scene pet_chat
[companion.name] wags.
play ask_pet

== scene pet_fight
fight wolf:
    won:
        Won.

== scene pet_plain
[companion.name] wags.

== creature wolf
name: Wolf
found in: nowhere

== scene loops
~ for each companion play pet_chat
~ for all companions play ask_pet
~ for each tamed companion play pet_fight
~ for each child play ask_pet
~ for each companion play pet_plain
"""
	var all := _diagnostics(text, ROOT + "_loops")
	var warned: Array = all.filter(func(m: String) -> bool: return "without stopping for the player" in m)
	assert_eq(warned.size(), 4, str(all))
	assert_true(warned.any(func(m: String) -> bool: return "for each companion play pet_chat" in m and "'ask_pet' would play their first option" in m), str(warned))
	assert_true(warned.any(func(m: String) -> bool: return "for all companions play ask_pet" in m), str(warned))
	assert_true(warned.any(func(m: String) -> bool: return "for each tamed companion play pet_fight" in m and "would not start" in m), str(warned))
	assert_true(warned.any(func(m: String) -> bool: return "for each child play ask_pet" in m), str(warned))
	assert_true(warned.all(func(m: String) -> bool: return m.begins_with("warning")), str(warned))


# --- 4. Placed nowhere ----------------------------------------------------------

func _holds(condition: String) -> bool:
	var c := Condition.compile(condition)
	assert_false(c.has("error"), "%s: %s" % [condition, c.get("error", "")])
	return Condition.evaluate(c, game)


func test_a_character_taken_out_of_play_is_at_nowhere() -> void:
	assert_false(_holds("fang is at nowhere"), "Fang lives in the field")
	assert_true(_holds("fang is not at nowhere"))
	assert_true(_holds("ghost is at nowhere"), "never placed: off-stage, as in the original")
	game.apply(Effect.compile("move fang to nowhere"))
	assert_true(_holds("fang is at nowhere"))
	assert_false(_holds("fang is at field"))
	game.apply(Effect.compile("move fang to field"))
	assert_false(_holds("fang is at nowhere"))
	assert_true(_holds("fang is at field"))
	assert_false(_holds("player is at nowhere"), "the player is always somewhere")
	var text := """== location yard
name: Yard
description: A yard.

== character rex
name: Rex
lives at: yard

== scene s
if rex is at nowhere:
    Gone.
if rex is not at nowhere:
    Here.
if rex is at nowhre:
    Typo.
if player is at nowhere:
    Never.
"""
	var all := _diagnostics(text, ROOT + "_nowhere")
	var errors: Array = all.filter(func(m: String) -> bool: return m.begins_with("error"))
	assert_eq(errors.size(), 2, str(all))
	assert_true(errors.any(func(m: String) -> bool: return "nowhre" in m), str(errors))
	assert_true(errors.any(func(m: String) -> bool: return "The player is always somewhere" in m), str(errors))


# --- 5. A creature's description changes the fight's numbers ------------------

func test_fight_starts_plays_a_description_that_changes_the_fight() -> void:
	game.runner.start("meet_twin")
	assert_eq(game.runner.status, "combat")
	assert_string_contains(_said(), "The twins pick a leader.")
	assert_eq(int(game.value("twins.lead_hp")), 40, "the health it had when the fight started")
	assert_eq(int(game.state.combat.hp), 25)
	assert_eq(int(game.value("enemy.dexterity")), 14)
	assert_eq(game.warnings, [], "no value changed outside the fight")
	var text := """== creature cat
name: Cat
found in: nowhere
encounter: -> cat_desc

== scene cat_desc
Two cats.
play cat_swap

== scene cat_swap
~ enemy.hp = 10
~ fight.lead = 1

== creature dog
name: Dog
found in: nowhere
encounter:
    ~ enemy strike
"""
	var all := _diagnostics(text, ROOT + "_encounter")
	var warned: Array = all.filter(func(m: String) -> bool: return "an encounter plays before the fight starts" in m)
	assert_eq(warned.size(), 3, str(all))
	assert_true(warned.any(func(m: String) -> bool: return "enemy.hp cannot change in 'cat_swap', played by the encounter of cat" in m), str(warned))
	assert_true(warned.any(func(m: String) -> bool: return "fight.lead" in m), str(warned))
	assert_true(warned.any(func(m: String) -> bool: return "'enemy strike' does nothing in the encounter of dog" in m), str(warned))


# --- 6. Weapon numbers changed in play honour their limits --------------------

func test_a_weapons_damage_change_honours_up_to_and_down_to() -> void:
	game.apply(Effect.compile("item club damage + 10 up to 12"))
	assert_eq(GearSystem.number(game, "club", "damage"), 12, "raised, but not past 12")
	game.apply(Effect.compile("item club damage + 5 up to 12"))
	assert_eq(GearSystem.number(game, "club", "damage"), 12)
	game.apply(Effect.compile("item club damage - 20 down to 3"))
	assert_eq(GearSystem.number(game, "club", "damage"), 3, "lowered, but not below 3")
	game.apply(Effect.compile("item club damage + 1"))
	assert_eq(GearSystem.number(game, "club", "damage"), 4)
	game.apply(Effect.compile("item club hit bonus = 2"))
	assert_eq(GearSystem.number(game, "club", "hit bonus"), 2)
	assert_eq(int(ItemSystem.arm(game, "club", "damage")), 4, "the fight reads the same number")
	assert_eq(Effect.compile("item club damage + 1").op, "gear_number", "one rule for every form")
	var text := """== item rock
name: rock
description: A rock.

== scene s
~ item rock damage + 1
~ item nosuch damage + 1 up to 9
"""
	var all := _diagnostics(text, ROOT + "_gear")
	assert_true(all.any(func(m: String) -> bool: return "'rock' has no weapon field, so it is not a weapon" in m), str(all))
	assert_true(all.any(func(m: String) -> bool: return "Unknown item 'nosuch'" in m), str(all))


func test_an_extension_adds_lines_to_a_text_and_a_scene() -> void:
	var text := str(game.rendered_text("[marks_line]"))
	assert_string_contains(text, "Old scars.")
	assert_string_contains(text, "A fresh bite.", "the extension's line follows")
	game.take_output()
	game.runner.start("greet")
	var out: Array = game.take_output().filter(func(e): return e.type == "paragraph").map(func(e): return TextTemplate.plain(e.spans))
	assert_eq(out, ["Hello.", "Welcome back."])
