extends GutTest
## Fights steered from content and creatures changed in play (FightControlSystem,
## CreatureChangeSystem): `~ end fight` and the `ended:` block, `~ no second
## fight`, `fight random in <zones>:`, `player is hunting`, tags of creatures and
## forms changed in play, a creature's attack text replaced, its loot chance
## raised, `~ cancel blow`, `~ this fight counts as ...` and a form's infection
## sex changed from a fight script.

const ROOT := "user://fight_control_test_packs"

const PACK := """== zone plains
name: Plains

== zone dunes
name: Dunes

== location arena
name: Arena
zone: plains
description: Sand and old blood.

== values arena_values
values:
    zone: text

== tag canine
== tag latex
== tag no_vore
== tag fire

== item bone
name: bone
description: A bone.

== form wolf
name: Wolf
torso:
    description: furry
    change: you grow fur

== creature wolf
name: Wolf
found in: plains
hp: 50
level: 1
damage: 5
stats: strength 10, dexterity 60, stamina 10, perception 10, intelligence 10, charisma 10
tags: canine
form: wolf
loot: bone 30%
encounter:
    if player is hunting:
        Hunted down.
    else:
        Met by chance.
attack:
    The wolf bites.

== scene wolf_soft_bite
The wolf only nibbles.

== creature camel
name: Camel
found in: dunes
hp: 50
level: 1
damage: 5

== creature lizard
name: Lizard
found in: nowhere
hp: 500
level: 1
damage: 5
stats: strength 10, dexterity 60, stamina 10, perception 10, intelligence 10, charisma 10
attack:
    The lizard rakes you.
    if player.hp < 11:
        ~ cancel blow
        The lizard draws away from the fight and paces off.
        ~ end fight

== creature siamese
name: Siamese
found in: nowhere
hp: 50
level: 1
damage: 5
form: wolf
after attack:
    ~ form wolf sex male

== creature tamed_one
name: Tamed One
found in: nowhere
hp: 50
level: 1
damage: 5
defeated:
    You tame it.
    ~ no second fight

== creature charmer
name: Charmer
found in: nowhere
hp: 50
level: 1
damage: 5
defeated:
    It purrs.
    ~ this fight counts as won by seduction

== scene meet_lizard
fight lizard:
    won:
        Won.
    ended:
        It walked off.
    fled:
        Fled.
After the lizard.

== scene meet_lizard_old
fight lizard:
    won:
        Won.
    fled:
        Gone, one way or another.

== scene meet_charmer
fight charmer:
    won:
        Won plainly.
    won by seduction:
        Won by charm.

== scene dune_fight
fight random in dunes:
    won:
        Dunes won.

== combat_rules basic
second fight when: chance 1 in 1
second fight:
    Another one comes.
"""

var game: Game


func _db(text: String, folder: String) -> ContentDB:
	DirAccess.make_dir_recursive_absolute(folder + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "c.fsc": text}
	for name: String in files:
		var fa := FileAccess.open(folder + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([folder])
	return db


func before_each() -> void:
	var db := _db(PACK, ROOT)
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 5)
	game.start("arena")
	game.set_value("player.maxhp", 1000)
	game.set_value("player.hp", 1000)
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type in ["paragraph", "notice"]:
			out.append(TextTemplate.plain(e.spans) if e.type == "paragraph" else str(e.text))
	return "\n".join(out)


## Ends the fight going on as a win by fighting.
func _win() -> void:
	assert_eq(game.runner.status, "combat")
	game.state.combat.result = "won"
	game.runner._finish_fight()
	game.runner.run()


func test_end_fight_stops_it_with_no_winner() -> void:
	game.runner.start("meet_lizard")
	assert_eq(game.runner.status, "combat")
	game.set_value("player.hp", 5)
	var xp := int(game.value("player.xp"))
	for _i in 30:
		if game.runner.status != "combat":
			break
		game.runner.combat_action("pass")
	var text := _text()
	assert_eq(game.runner.status, "idle", "the fight is over")
	assert_string_contains(text, "paces off.")
	assert_string_contains(text, "It walked off.", "the ended: block plays")
	assert_false(text.contains("Won."))
	assert_false(text.contains("Fled."))
	assert_string_contains(text, "After the lizard.")
	assert_eq(game.last_fight, "ended")
	assert_eq(int(game.value("player.hp")), 5, "the blow that ended it did no damage")
	assert_eq(int(game.value("player.xp")), xp, "no winner: no experience")
	assert_false(Condition.evaluate(Condition.compile("won"), game))
	assert_false(Condition.evaluate(Condition.compile("lost"), game))


func test_without_an_ended_block_the_fled_block_plays() -> void:
	game.runner.start("meet_lizard_old")
	game.set_value("player.hp", 5)
	for _i in 30:
		if game.runner.status != "combat":
			break
		game.runner.combat_action("pass")
	assert_string_contains(_text(), "Gone, one way or another.", "as the original's untouched outcome counts as fled")


func test_cancel_blow_spares_the_player() -> void:
	game.set_value("player.hp", 10)
	CombatSystem.begin(game, "lizard")
	CombatSystem._retaliate(game)
	for _i in 20:
		if game.state.combat.result != "":
			break
		CombatSystem._retaliate(game)
	assert_eq(int(game.value("player.hp")), 10, "every blow is cancelled")
	assert_eq(game.state.combat.result, "ended")
	# A creature without it hurts as usual, and a cancelled blow is not carried over.
	game.state.combat = {}
	game.set_value("player.hp", 1000)
	CombatSystem.begin(game, "wolf")
	game.state.combat.vars["blow_cancelled"] = true
	for _i in 10:
		CombatSystem._retaliate(game)
	assert_lt(int(game.value("player.hp")), 1000, "the wolf's blows land")


func _queue_and_meet(creature: String) -> void:
	game.runner._queue_second_fight(["wolf"])
	game.runner.start_encounter(creature)
	_win()


func test_a_scene_calls_off_the_second_fight() -> void:
	_queue_and_meet("wolf")
	assert_string_contains(_text(), "Another one comes.", "the rules' second fight follows")
	assert_eq(game.runner.status, "combat")
	assert_eq(game.state.combat.creature, "wolf")
	game.state.combat = {}
	game.runner.frames.clear()
	game.runner.status = "idle"
	_queue_and_meet("tamed_one")
	var text := _text()
	assert_string_contains(text, "You tame it.")
	assert_false(text.contains("Another one comes."), "~ no second fight calls it off")
	assert_eq(game.runner.status, "idle")


func test_a_random_fight_in_a_named_zone() -> void:
	game.runner.start("dune_fight")
	assert_eq(game.runner.status, "combat")
	assert_eq(game.state.combat.creature, "camel", "a creature of the dunes, not of the player's plains")
	var prog: Program = game.content.program("dune_fight")
	var fight: Dictionary = prog.code.filter(func(i: Dictionary) -> bool: return i.op == "fight")[0]
	assert_eq(fight.zones, ["dunes"])
	assert_eq(FightControlSystem.random_zone(game, {"zones": ["a", "a", "b"]}).length(), 1)
	assert_eq(FightControlSystem.random_zone(game, {}), "plains", "plain fight random: the player's zone")
	game.set_value("arena_values.zone", "dunes")
	assert_eq(FightControlSystem.random_zone(game, {"zones": ["arena_values.zone"]}), "dunes", "the zone a value holds")
	game.set_value("arena_values.zone", "")
	assert_eq(FightControlSystem.random_zone(game, {"zones": ["arena_values.zone"]}), "plains", "none held: the player's zone")


func test_player_is_hunting() -> void:
	assert_true(game.runner.act("hunt", "wolf"))
	assert_string_contains(_text(), "Hunted down.")
	assert_true(Condition.evaluate(Condition.compile("player is hunting"), game), "through the fight")
	_win()
	assert_false(Condition.evaluate(Condition.compile("player is hunting"), game), "not after the meeting")
	game.runner.start_encounter("wolf")
	assert_string_contains(_text(), "Met by chance.")
	assert_true(Condition.evaluate(Condition.compile("player is not hunting"), game))


func test_tags_change_in_play_and_are_saved() -> void:
	game.apply(Effect.compile("transform into wolf"))
	assert_true(Condition.evaluate(Condition.compile("player body is tagged canine"), game), "the creature's tag counts for its form")
	assert_false(Condition.evaluate(Condition.compile("player body is tagged latex"), game))
	game.apply(Effect.compile("form wolf tags + latex, fire"))
	game.apply(Effect.compile("form wolf tag - canine"))
	game.apply(Effect.compile("creature wolf tag + no_vore"))
	assert_true(Condition.evaluate(Condition.compile("player body is tagged latex"), game))
	assert_true(Condition.evaluate(Condition.compile("player body is tagged fire"), game))
	assert_false(Condition.evaluate(Condition.compile("player body is tagged canine"), game), "removed from the form")
	assert_true("no_vore" in VoreSystem.tags_of(game, "wolf"))
	assert_true("canine" in CreatureChangeSystem.creature_tags(game, "wolf"), "the creature itself keeps it")
	game.apply(Effect.compile("creature wolf tag - canine"))
	assert_false("canine" in CreatureChangeSystem.creature_tags(game, "wolf"))
	var saved := JSON.parse_string(JSON.stringify(game.save_dict())) as Dictionary
	var other := Game.new(game.content, 1)
	assert_true(other.load_dict(saved))
	assert_true("no_vore" in VoreSystem.tags_of(other, "wolf"), "saved with the game")
	assert_true("latex" in CreatureChangeSystem.form_tags(other, "wolf"))
	other.dispose()


func test_a_ban_follows_a_tag_added_in_play() -> void:
	assert_true("camel" in game.runner.encounter_pool("dunes"))
	game.settings.banned = ["fire"]
	game.apply(Effect.compile("creature camel tag + fire"))
	assert_false("camel" in game.runner.encounter_pool("dunes"), "a creature tagged fire in play is banned with fire")


func test_attack_text_replaced_and_restored() -> void:
	game.apply(Effect.compile("creature wolf attack -> wolf_soft_bite"))
	CombatSystem.begin(game, "wolf")
	game.take_output()
	for _i in 10:
		CombatSystem._standard_turn(game, "wolf")
	var text := _text()
	assert_string_contains(text, "The wolf only nibbles.")
	assert_false(text.contains("The wolf bites."))
	game.apply(Effect.compile("creature wolf attack -> default"))
	for _i in 10:
		CombatSystem._standard_turn(game, "wolf")
	assert_string_contains(_text(), "The wolf bites.")


func test_loot_chance_raised_with_a_cap() -> void:
	game.apply(Effect.compile("creature wolf loot chance + 3 to 10 up to 35"))
	var chance := int(game.creature_field("wolf", "loot").split(" ")[1].trim_suffix("%"))
	assert_between(chance, 33, 35)
	for _i in 5:
		game.apply(Effect.compile("creature wolf loot chance + 3 to 10 up to 35"))
	assert_eq(game.creature_field("wolf", "loot"), "bone 35%", "never past the cap")
	game.apply(Effect.compile("creature wolf loot chance = 80"))
	assert_eq(game.creature_field("wolf", "loot"), "bone 80%")
	game.apply(Effect.compile("creature wolf loot chance - 100"))
	assert_eq(game.creature_field("wolf", "loot"), "bone 0%", "never below 0")


func test_a_fight_script_changes_a_forms_infection_sex() -> void:
	CombatSystem.begin(game, "siamese")
	CombatSystem._retaliate(game)
	assert_eq(game.state.values.get("form.wolf.sex"), "male")


func test_the_fight_counts_as_won_another_way() -> void:
	game.runner.start("meet_charmer")
	_win()
	var text := _text()
	assert_string_contains(text, "It purrs.")
	assert_string_contains(text, "Won by charm.", "the block for the new way plays")
	assert_false(text.contains("Won plainly."))
	assert_eq(game.last_fight, "won by seduction")
	assert_true(Condition.evaluate(Condition.compile("won by seduction"), game))
	assert_true(Condition.evaluate(Condition.compile("won"), game))


func test_won_by_fighting_and_lost_by_injury_are_the_plain_results() -> void:
	assert_eq(Effect.compile("win fight by fighting").result, "won")
	assert_eq(Effect.compile("lose fight by injury").result, "lost")
	assert_eq(Effect.compile("this fight counts as won by fighting").result, "won")


func test_the_new_effects_are_validated() -> void:
	var bad := """== creature wolf
name: Wolf
attack:
    ~ cancel blow
== tag canine
== scene s
~ creature wolf tag + nosuchtag
~ form nosuchform tag - canine
~ creature wolf attack -> nosuchscene
~ creature wolf loot chance + 5
~ enemy becomes nosuchbeast
~ end fight
fight random in nosuchzone:
    won:
        Hm.
== scene shout
~ go to nowhere_place
== scene uses_shout
~ creature wolf miss -> shout
"""
	var db := _db(bad, ROOT + "_bad")
	var text := str(db.errors())
	for part in ["nosuchtag", "nosuchform", "nosuchscene", "whose chance could change", "nosuchbeast", "nosuchzone", "does more at line 17"]:
		assert_string_contains(text, part)
	assert_string_contains(str(db.diagnostics.filter(func(d: Dictionary) -> bool: return d.severity == "warning")),
		"only works during a fight", "~ end fight in a plain scene")
	assert_false(text.contains("line 4"), "~ cancel blow in an attack text is fine")
