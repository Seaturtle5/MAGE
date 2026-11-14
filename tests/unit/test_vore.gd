extends GutTest
## The player as predator (VoreSystem): the offer after a win, the choice or the
## automatic act, exclusions by tag and uniqueness, hard vore, a creature's own
## scene, unbirthing into a pregnancy, and the effects the rules' scripts use.

const ROOT := "user://vore_test_packs"

const PACK := """== location den
name: Den
description: A quiet den.

== tag no_vore
name: Never consumed

== tag no_hard_vore
name: Never torn apart

== level vore_choice
name: Vore choice
default: ask
options:
    ask: Ask.
    always: Always.
    never: Never.

== values vore
values:
    count: number
    ubcount: number

== vore_rules test
can vore when: player has feat predator
can unbirth when: player has feat womb_predator
vore when: player.scale >= enemy.scale and level vore_choice is not never
vore chance: 100
vore chance out of: 100
unbirth when: player is female
unbirth chance: 100
unbirth chance out of: 100
vore automatic when: level vore_choice is always
hard vore when: player has feat gory
own scene when: player has feat picky
absorb above: 12
unbirth gestation: 5 to 6
vore urge:
    URGE TO EAT
vore urge automatic:
    HUNGER TAKES OVER
both urge:
    TWIN HUNGERS
vore:
    SWALLOWED [the enemy] WHOLE
hard vore:
    TORE INTO [the enemy]
unbirth:
    TOOK [the enemy] IN
after vore:
    ~ absorb enemy stat
    ~ infect enemy
    ~ vore.count + 1 quietly
after unbirth:
    ~ unbirth pregnancy
    ~ vore.ubcount + 1 quietly

== pregnancy_rules plain
gestation: 30 to 40

== form wolf
name: Wolf
scale: 3
body type: lupine
tail:
    description: A wolf tail.
    change: a wolf tail grows

== creature wolf
name: wolf
form: wolf
level: 1
hp: 10
gender: female
stats: strength 20, dexterity 10, stamina 10, perception 10, intelligence 10, charisma 10
defeated:
    THE WOLF RUNS OFF
vore:
    THE WOLF'S OWN MEAL

== creature plush
name: plush
form: wolf
level: 1
hp: 10
tags: no_hard_vore
defeated:
    THE PLUSH FLOPS

== creature ghost
name: ghost
form: wolf
level: 1
hp: 10
tags: no_vore
defeated:
    THE GHOST FADES

== creature boss
name: Boss
form: wolf
level: 1
hp: 10
unique: yes
defeated:
    THE BOSS FLEES

== creature giant
name: giant
form: giant
level: 1
hp: 10
defeated:
    THE GIANT STUMBLES

== form giant
name: Giant
scale: 5

== event ambush
name: Ambush
play:
    fight wolf:
        won:
            AMBUSH WON
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "vore.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("den")
	game.set_value("player.humanity", 100)
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type in ["paragraph", "notice"]:
			out.append(TextTemplate.plain(e.spans) if e.has("spans") else str(e.get("text", "")))
	return "\n".join(out)


func _choices() -> Array:
	return game.runner.pending


## Meets the creature and wins the fight by fighting (or as `result` says).
func _win(id: String, result: String = "won") -> String:
	game.runner.start_encounter(id)
	game.take_output()
	game.state.combat.result = result
	game.runner._finish_fight()
	game.runner.run()
	return _text()


func test_a_win_offers_the_meal_and_giving_in_plays_it() -> void:
	game.apply(Effect.compile("feat + predator"))
	var strength := int(game.value("player.strength"))
	var text := _win("wolf")
	assert_string_contains(text, "URGE TO EAT")
	assert_eq(game.runner.status, "choice")
	assert_eq(_choices().size(), 2, "give in or hold back")
	game.runner.choose(0)
	text = _text()
	assert_string_contains(text, "SWALLOWED the wolf WHOLE")
	assert_false(text.contains("THE WOLF RUNS OFF"), "the meal replaces the defeated scene")
	assert_eq(int(game.value("vore.count")), 1, "after vore ran")
	assert_eq(int(game.value("player.strength")), strength + 1, "the stat the creature has more of (20, above 12) rises")
	assert_eq(game.part_form("player", "tail"), "wolf", "infected with the creature eaten")
	assert_true(Condition.evaluate(Condition.compile("won by vore"), game))


func test_holding_back_plays_the_defeated_scene() -> void:
	game.apply(Effect.compile("feat + predator"))
	_win("wolf")
	game.runner.choose(1)
	var text := _text()
	assert_string_contains(text, "THE WOLF RUNS OFF")
	assert_eq(int(game.value("vore.count")), 0)


func test_automatic_choice_and_never() -> void:
	game.apply(Effect.compile("feat + predator"))
	game.set_level("vore_choice", "always")
	var text := _win("wolf")
	assert_string_contains(text, "HUNGER TAKES OVER")
	assert_string_contains(text, "SWALLOWED")
	assert_eq(int(game.value("vore.count")), 1)
	game.set_level("vore_choice", "never")
	text = _win("wolf")
	assert_false(text.contains("HUNGER"), "never: no offer")
	assert_string_contains(text, "THE WOLF RUNS OFF")


func test_no_offer_without_the_ability_or_for_excluded_creatures() -> void:
	assert_string_contains(_win("wolf"), "THE WOLF RUNS OFF", "no feat, no offer")
	game.apply(Effect.compile("feat + predator"))
	assert_string_contains(_win("ghost"), "THE GHOST FADES", "tagged no_vore")
	assert_string_contains(_win("boss"), "THE BOSS FLEES", "unique creatures are never eaten")
	assert_string_contains(_win("giant"), "THE GIANT STUMBLES", "bigger than the player: the rules' condition")
	assert_string_contains(_win("wolf", "won by seduction"), "THE WOLF RUNS OFF", "only a win by fighting")


func test_no_offer_in_an_event_fight() -> void:
	game.apply(Effect.compile("feat + predator"))
	game.runner.start_event("ambush")
	game.take_output()
	game.state.combat.result = "won"
	game.runner._finish_fight()
	game.runner.run()
	var text := _text()
	assert_false(text.contains("URGE"), "inside an event the meal is never offered")
	assert_string_contains(text, "AMBUSH WON")


func test_hard_vore_and_its_exclusion() -> void:
	game.apply(Effect.compile("feat + predator"))
	game.apply(Effect.compile("feat + gory"))
	game.set_level("vore_choice", "always")
	assert_string_contains(_win("wolf"), "TORE INTO the wolf")
	var text := _win("plush")
	assert_string_contains(text, "SWALLOWED the plush WHOLE", "no_hard_vore: swallowed whole")


func test_a_creatures_own_scene() -> void:
	game.apply(Effect.compile("feat + predator"))
	game.set_level("vore_choice", "always")
	game.apply(Effect.compile("feat + picky"))
	var text := _win("wolf")
	assert_string_contains(text, "THE WOLF'S OWN MEAL")
	assert_false(text.contains("SWALLOWED"))
	assert_eq(int(game.value("vore.count")), 1, "after vore still runs")


func test_unbirth_starts_a_pregnancy_of_the_creature() -> void:
	game.apply(Effect.compile("feat + predator"))
	game.apply(Effect.compile("feat + womb_predator"))
	game.set_value("player.cunts", 1)
	var text := _win("wolf")
	assert_string_contains(text, "TWIN HUNGERS")
	assert_eq(_choices().size(), 3, "consume, unbirth or suppress")
	game.runner.choose(1)
	text = _text()
	assert_string_contains(text, "TOOK the wolf IN")
	assert_eq(str(game.value("pregnancy.unbirth")), "wolf")
	var g := int(game.value("pregnancy.gestation"))
	assert_true(g >= 5 and g <= 6, "the rules' unbirth gestation")
	assert_eq(str(game.value("pregnancy.child_tail")), "wolf", "the child is the creature's strain")
	assert_eq(int(game.value("vore.ubcount")), 1)
	assert_true(Condition.evaluate(Condition.compile("won by unbirth"), game))


func test_conditions_and_values() -> void:
	assert_false(Condition.evaluate(Condition.compile("player can vore"), game))
	game.apply(Effect.compile("feat + predator"))
	assert_true(Condition.evaluate(Condition.compile("player can vore"), game))
	assert_true(Condition.evaluate(Condition.compile("player cannot unbirth"), game))
	game.runner.start_encounter("plush")
	game.take_output()
	assert_true(Condition.evaluate(Condition.compile("enemy is tagged no_hard_vore"), game))
	assert_true(Condition.evaluate(Condition.compile("enemy is plush"), game))
	assert_false(Condition.evaluate(Condition.compile("enemy is wolf"), game))
	assert_eq(int(game.value("enemy.scale")), 3)
	assert_eq(game.describe("enemy body type"), "lupine")


func test_vore_rules_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := "== vore_rules r\nvore when: player is grumpy\nvore chance: 3 +\nunbirth gestation: soon\nvore chance modifiers:\n    nonsense\n\n== creature c\nname: C\nhp: 3\nvore when: player is sleepy\n\n== scene s\nif enemy is tagged nosuch:\n    Hm.\n~ vore enemy\n"
	var files := {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	for part in ["grumpy", "Vore chance", "Unbirth gestation", "condition: amount", "sleepy", "nosuch"]:
		assert_string_contains(text, part)
