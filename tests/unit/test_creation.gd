extends GutTest
## Character creation: questions, free feats, modes, and the hooks a start can use
## (blocked infection with a bypass, a sanity floor, picking any creature).

const ROOT := "user://creation_test_packs"

const PACK := """== values start
values:
    body: plain, fancy

== values player
values:
    sanity: number 100 (0 to 100)
        role: sanity

== values tally
values:
    hooks: number

== location home
name: Home
description: A small home.
zone: woods

== zone woods
name: Woods

== creation_rules test_game
choices: pick_stat, pick_body
feats:
    basic: steady
before:
    ~ player.strength = 10 quietly
after:
    ~ player.maxhp = player.strength * 2 quietly

== menu pick_stat
title: Main stat
* Strong -- More strength.
    ~ player.strength + 5 quietly
* Clever -- More intelligence.
    ~ player.intelligence + 5 quietly
* Hidden -- Never offered. [if player.level > 50]
    ~ player.charisma + 5 quietly

== menu pick_body
title: Body
* Plain -- An ordinary body.
    ~ start.body = plain quietly
* Fancy -- A fancy body.
    ~ start.body = fancy quietly

== feat steady
name: Steady
group: basic
gained:
    ~ player.maxhp + 8 quietly

== feat nimble
name: Nimble
group: basic

== game_mode tough
name: Tough Mode
description: Harder fights.

== scenario home_start
name: Home
start: home
setup:
    ~ give pebble quietly

== scenario lab_start
name: Lab
start: home

== item pebble
name: pebble
description: A pebble.

== form slime
name: Slime
tail:
    description: a slime tail
    change: a slime tail grows

== creature slime
name: Slime
found in: woods
form: slime

== creature ghost
name: Ghost
found in: nowhere
form: slime

== form mote
name: Mote
tail:
    description: a glowing tail
    change: a glowing tail grows

== creature mote
name: Mote
found in: woods
form: mote
research bypass: yes

== infection_rules test_rules
blocked when: scenario is lab_start and not infection.bypass

== values infection
values:
    bypass: flag

== survival_rules test_survival
sanity floor when: scenario is lab_start
humanity descriptions:
    0: gone
lust descriptions:
    0: calm
hunger warnings:
    50: hungry
thirst warnings:
    50: thirsty
"""

var db: ContentDB
var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "c.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	db = ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 4)


func after_each() -> void:
	game.dispose()


func test_questions_feats_and_modes_come_from_the_content() -> void:
	var qs := CreationSystem.questions(game)
	assert_eq(qs.map(func(q): return q.id), ["pick_stat", "pick_body"])
	assert_eq(qs[0].title, "Main stat")
	assert_eq(qs[0].options.map(func(o): return o.enabled), [true, true, false], "conditions disable answers")
	var feats := CreationSystem.feat_choices(game)
	assert_eq(feats[0].group, "basic")
	assert_eq(feats[0].default, "steady")
	assert_eq(feats[0].feats.map(func(f): return f.id), ["nimble", "steady"], "sorted by name")
	assert_eq(CreationSystem.modes(game)[0].name, "Tough Mode")


func test_a_new_game_runs_before_the_answers_after_and_the_free_feat() -> void:
	assert_true(game.start_scenario("home_start", "Ada", "she", {"pick_stat": 1, "pick_body": 1}))
	assert_eq(int(game.value("player.strength")), 10, "before")
	assert_eq(int(game.value("player.intelligence")), 17, "the second answer of the first question")
	assert_eq(str(game.value("start.body")), "fancy")
	assert_true("steady" in game.state.feats, "the default free feat")
	assert_eq(int(game.value("player.maxhp")), 28, "after (20), then the feat's gained (+8)")
	assert_eq(game.state.inventory.get("pebble", 0), 1, "then the scenario's setup")
	assert_eq(str(game.value("player.name")), "Ada")


func test_a_chosen_feat_and_a_disabled_answer() -> void:
	game.start_scenario("home_start", "Bo", "he", {"pick_stat": 2, "feat basic": "nimble"})
	assert_eq(int(game.value("player.strength")), 15, "a disabled answer falls back to the default")
	assert_true("nimble" in game.state.feats)
	assert_false("steady" in game.state.feats)


func test_modes_are_the_settings_chosen_before_the_start() -> void:
	game.settings.mode = ["tough"]
	game.start_scenario("home_start")
	assert_true(Condition.evaluate(Condition.compile("mode tough"), game))
	assert_true(Condition.evaluate(Condition.compile("scenario is home_start"), game))


func test_infection_can_be_blocked_except_for_bypassing_creatures() -> void:
	game.start_scenario("lab_start")
	game.apply(Effect.compile("infect slime"))
	assert_eq(game.part_form("player", "tail"), "human", "blocked in the lab")
	game.apply(Effect.compile("infect mote"))
	assert_eq(game.part_form("player", "tail"), "mote", "a creature with research bypass gets through")
	var other := Game.new(db, 4)
	other.start_scenario("home_start")
	other.apply(Effect.compile("infect slime"))
	assert_eq(other.part_form("player", "tail"), "slime", "not blocked elsewhere")
	other.dispose()


func test_the_sanity_floor_keeps_the_mind() -> void:
	game.start_scenario("lab_start")
	game.set_value("player.sanity", 0)
	game.pass_turn()
	assert_eq(int(game.value("player.sanity")), 1)
	assert_eq(game.state.ending, "", "the game goes on")


func test_pick_any_creature_skips_those_found_nowhere() -> void:
	game.start_scenario("home_start")
	for _i in 20:
		game.apply(Effect.compile("pick random creature anywhere"))
		assert_true(str(game.value("picked.creature")) in ["slime", "mote"], "never the ghost")


func test_creation_rules_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := "== creation_rules r\nchoices: nothing_here\nfeats:\n    nogroup: missing_feat\n"
	var files := {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var bad_db := ContentDB.new()
	bad_db.load_folders([ROOT + "_bad"])
	var text := str(bad_db.errors())
	assert_string_contains(text, "nothing_here")
	assert_string_contains(text, "nogroup")
	assert_string_contains(text, "missing_feat")
