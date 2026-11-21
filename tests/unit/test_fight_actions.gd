extends GutTest
## The player's own fight actions (`fight actions:` on creatures, characters,
## items, feats and the combat rules), the hooks `on: player's turn` and
## `on: enemy below N%`, and `~ enemy becomes X` (FightActionSystem).

const ROOT := "user://fight_action_test_packs"

const PACK := """== location arena
name: Arena
description: Sand and old blood.

== tag fire

== item water_bottle
name: water bottle
description: Water.
fight actions:
    * Douse it with water -- Throw the water at it. [if enemy is tagged fire]
        ~ take water_bottle
        The flames hiss and shrink.
        ~ enemy.hp - 15

== feat diplomat
name: Diplomat
fight actions:
    * Talk her down
        Do you really try?
        * Yes
            You talk softly until she lowers her claws.
            ~ win fight by seduction
        * No
            You think better of it.

== creature imp
name: Imp
hp: 100
level: 1
damage: 1
stats: strength 10, dexterity 1, stamina 10, perception 10, intelligence 10, charisma 10
tags: fire
fight actions:
    * Grab its tail
        You grab the imp's tail.
        ~ enemy.damage - 1
defeated:
    The imp flees, singed.

== creature dragon
name: Dragon
hp: 100
level: 1
damage: 1
stats: strength 10, dexterity 1, stamina 10, perception 10, intelligence 10, charisma 10
defeated:
    The first dragon falls.

== creature dragon_two
name: Enraged Dragon
hp: 300
level: 2
damage: 1
stats: strength 10, dexterity 1, stamina 10, perception 10, intelligence 10, charisma 10
fight starts:
    The dragon roars in fury.
defeated:
    The enraged dragon falls at last.

== combat_rules basic
fight actions:
    * Pray [always shown] [if player.morale > 50]
        Nothing answers.

== hook taunt
on: player's turn
when: enemy.round = 2
do:
    The imp taunts you.

== hook yield
on: enemy below 50%
when: enemy.id = "imp"
do:
    The imp yields.
    ~ win fight

== hook phase_two
on: enemy below 50%
when: enemy.id = "dragon"
do:
    The dragon's eyes burn red.
    ~ enemy becomes dragon_two

== scene meet_imp
fight imp:
    won:
        Done with the imp.

== scene meet_held
fight picked.creature:
    won:
        Done with whatever it was.
After the fight.

== scene meet_dragon
fight dragon:
    won:
        Done with dragons.
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
	game.set_value("player.perception", 30)  # no first strike
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type in ["paragraph", "notice"]:
			out.append(TextTemplate.plain(e.spans) if e.type == "paragraph" else str(e.text))
	return "\n".join(out)


## The fight actions of the last combat event shown.
func _shown() -> Array:
	var out: Array = []
	for e in game.take_output():
		if e.type == "combat":
			out = e.fight_actions
	return out


func test_actions_are_offered_by_their_sources() -> void:
	game.runner.start("meet_imp")
	var shown := _shown()
	var labels: Array = shown.map(func(a: Dictionary) -> String: return a.label)
	assert_eq(labels, ["Grab its tail", "Pray"], "the creature's own, then the rules' (always shown)")
	assert_false(shown[1].enabled, "greyed out while its condition does not hold")
	game.apply(Effect.compile("give water_bottle"))
	game.apply(Effect.compile("feat + diplomat"))
	labels = FightActionSystem.offered(game).map(func(a: Dictionary) -> String: return a.label)
	assert_eq(labels, ["Grab its tail", "Douse it with water", "Talk her down", "Pray"], "creature, items, feats, rules")
	assert_eq(FightActionSystem.offered(game)[1].description, "Throw the water at it.")
	game.state.combat.grappled = true
	assert_eq(FightActionSystem.offered(game), [], "none while held")


func test_an_item_action_uses_the_turn() -> void:
	game.apply(Effect.compile("give water_bottle"))
	game.runner.start("meet_imp")
	game.take_output()
	assert_eq(int(game.state.combat.round), 1)
	assert_true(game.runner.combat_action("do water_bottle.fight actions@0"))
	assert_string_contains(_text(), "The flames hiss and shrink.")
	assert_eq(int(game.state.combat.hp), 85)
	assert_eq(int(game.state.inventory.get("water_bottle", 0)), 0, "the bottle was used")
	assert_eq(int(game.state.combat.round), 2, "the enemy took its turn")
	assert_eq(game.runner.status, "combat")
	assert_false(game.runner.combat_action("do water_bottle.fight actions@0"), "no longer offered without the bottle")
	assert_false(game.runner.combat_action("do combat_rules.nothing@3"), "an unknown key does nothing")


func test_a_disabled_action_cannot_be_chosen() -> void:
	game.runner.start("meet_imp")
	assert_false(game.runner.combat_action("do basic.fight actions@0"))
	game.set_value("player.morale", 80)
	assert_true(game.runner.combat_action("do basic.fight actions@0"))
	assert_string_contains(_text(), "Nothing answers.")


func test_an_action_with_choices_can_win_the_fight() -> void:
	game.apply(Effect.compile("feat + diplomat"))
	game.runner.start("meet_imp")
	assert_true(game.runner.combat_action("do diplomat.fight actions@0"))
	assert_eq(game.runner.status, "choice")
	assert_string_contains(_text(), "Do you really try?")
	game.runner.choose(0)
	var text := _text()
	assert_string_contains(text, "lowers her claws.")
	assert_string_contains(text, "The imp flees, singed.", "the creature's defeated scene")
	assert_string_contains(text, "Done with the imp.")
	assert_eq(game.last_fight, "won by seduction")
	assert_eq(game.runner.status, "idle")


func test_hooks_on_the_players_turn_and_low_health() -> void:
	game.runner.start("meet_imp")
	game.take_output()
	game.runner.combat_action("pass")
	assert_string_contains(_text(), "The imp taunts you.", "round 2 begins")
	game.runner.combat_action("pass")
	assert_false(_text().contains("taunts"), "only while its condition holds")
	game.state.combat.hp = 49
	game.runner.combat_action("pass")
	var text := _text()
	assert_string_contains(text, "The imp yields.")
	assert_string_contains(text, "Done with the imp.")
	assert_eq(game.last_fight, "won")


func test_a_second_stage() -> void:
	game.runner.start("meet_dragon")
	game.state.combat.hp = 40
	game.runner.combat_action("pass")
	var text := _text()
	assert_string_contains(text, "The dragon's eyes burn red.")
	assert_string_contains(text, "The dragon roars in fury.", "the new creature's fight starts")
	assert_eq(game.state.combat.creature, "dragon_two")
	assert_eq(int(game.state.combat.hp), 300)
	assert_eq(int(game.state.combat.maxhp), 300)
	assert_eq(game.runner.status, "combat")
	game.state.combat.hp = 200
	game.runner.combat_action("pass")
	assert_eq(game.state.combat.creature, "dragon_two", "the hook fired once (and not for this creature)")
	game.state.combat.result = "won"
	game.runner._finish_fight()
	game.runner.run()
	text = _text()
	assert_string_contains(text, "The enraged dragon falls at last.", "the aftermath follows the second stage")
	assert_false(text.contains("The first dragon falls."))
	assert_string_contains(text, "Done with dragons.")


func test_fight_actions_are_validated() -> void:
	var bad := """== creature imp
name: Imp
fight actions:
    * Leave
        -> end
    * Call a friend
        fight imp:
            won:
                Hm.
== character bob
name: Bob
fight actions:
    * Help
        Bob helps.
== item bob
name: bob doll
description: A doll.
fight actions:
    * Squeeze
        Squeak.
== hook h
on: enemy below 150%
do:
    Hm.
== hook t
on: player's turn
do:
    ~ end fight
"""
	var db := _db(bad, ROOT + "_bad")
	var text := str(db.errors())
	for part in ["-> end", "cannot start another fight", "both have fight actions", "from 1% to 99%"]:
		assert_string_contains(text, part)
	var warnings := str(db.diagnostics.filter(func(d: Dictionary) -> bool: return d.severity == "warning"))
	assert_string_contains(warnings, "no companion: block")
	assert_false(warnings.contains("only works during a fight"), "a turn hook may end the fight")


func test_fight_the_creature_a_value_holds() -> void:
	game.state.values["picked.creature"] = "imp"
	game.runner.start("meet_held")
	assert_eq(game.runner.status, "combat")
	assert_eq(str(game.state.combat.creature), "imp", "fight picked.creature: meets the creature it holds")


func test_fight_a_value_holding_nothing_goes_on() -> void:
	game.state.values.erase("picked.creature")
	game.runner.start("meet_held")
	assert_ne(game.runner.status, "combat")
	assert_string_contains(_text(), "After the fight.")
