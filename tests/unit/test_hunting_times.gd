extends GutTest
## Species names, time stamps set in the past, the rescue's time, people at
## flagged places, hunting rules, avoiding random fights, the exploring chance,
## a second fight and an automatic combat action.

const ROOT := "user://hunting_test_packs"

const PACK := """== zone woods
name: Woods

== location camp
name: Camp
description: A camp.
zone: woods
flags: refuge

== location hall
name: Hall
description: A hall.
zone: none
flags: refuge

== tag uncounted
name: Uncounted

== form wolf
name: Grey Wolf
tail:
    description: a wolf's tail
    change: a tail grows

== character ann
name: Ann
lives at: camp

== character bob
name: Bob
lives at: hall

== character book
name: Book
lives at: hall
tags: uncounted

== values log
values:
    met_at: time
    auto: off, attack, flee, submit

== feat tracker
name: Tracker

== feat loner
name: Loner

== feat scout
name: Scout

== creature fox
name: Fox
found in: woods
level: 1
hp: 5
damage: 1

== creature hare
name: Hare
found in: woods
level: 1
hp: 5
damage: 1

== combat_rules test
creature chance: 0 in 20
creature chance modifiers:
    player has feat tracker: + 20
second fight when: player has feat loner
second fight:
    ANOTHER ONE
before random fight:
    if player has feat scout:
        ESCAPE
        ~ no fight
auto action: log.auto

== hunt_rules test
target weight: 0
target weight modifiers:
    player has feat tracker: + 3
others when: player does not have feat loner
other skipped when: player has feat scout
not found:
    NOTHING HERE

== survival_rules test
rescue after: 1000
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	for name: String in {"pack.fsc": "== pack p\nname: Test\n", "woods.fsc": PACK}:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string({"pack.fsc": "== pack p\nname: Test\n", "woods.fsc": PACK}[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("camp")
	game.set_value("player.hp", 100)
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func _holds(text: String) -> bool:
	return Condition.evaluate(Condition.compile(text), game)


func test_a_species_name_can_be_searched() -> void:
	assert_true(_holds("player tail species contains human"), "an untouched part is human")
	game.set_value("player.body.tail", "wolf")
	assert_true(_holds("player tail species contains wolf"), "Grey Wolf contains wolf, in any case")
	assert_true(_holds("player tail species does not contain cat"))


func test_all_parts_of_some_forms() -> void:
	assert_true(_holds("player parts are all human"), "the original's purehuman")
	game.set_value("player.body.tail", "wolf")
	assert_false(_holds("player parts are all human"))
	assert_true(_holds("player parts are all human, wolf"))
	assert_true(_holds("player parts are not all human"))


func test_people_at_flagged_places() -> void:
	assert_eq(int(game.value("people.refuge")), 2, "Ann and Bob; the uncounted Book is left out")
	assert_true(_holds("ann is at a place flagged refuge"))
	assert_true(_holds("player is at a place flagged refuge"))
	game.apply(Effect.compile("move ann to hall"))
	assert_eq(int(game.value("people.refuge")), 2)


func test_a_time_can_be_set_in_the_past_or_future() -> void:
	for _i in 10:
		game.pass_turn()
	game.apply(Effect.compile("log.met_at = 8 turns ago"))
	assert_true(_holds("since log.met_at >= 8 turns"))
	assert_false(_holds("since log.met_at > 8 turns"))
	game.apply(Effect.compile("log.met_at = in 2 turns"))
	assert_eq(game.turns_since("log.met_at"), -2)
	assert_true(Effect.compile("player.hp = 3 turns ago").has("op"), "compiles; the validator rejects non-time values")


func test_the_rescue_time_is_content_and_can_be_extended() -> void:
	assert_eq(SurvivalSystem.rescue_turn(game), 1000)
	game.apply(Effect.compile("extend game by 5 turns"))
	assert_eq(SurvivalSystem.rescue_turn(game), 1005)


func test_hunting_draws_from_a_pool() -> void:
	# Weight 0 and others left out: nothing to find.
	game.apply(Effect.compile("feat + loner"))
	assert_eq(HuntSystem.pick(game, "fox", "woods"), "")
	game.runner.act("hunt", "fox")
	assert_string_contains(_text(), "NOTHING HERE")
	# The target three times, the others still left out: always the fox.
	game.apply(Effect.compile("feat + tracker"))
	for _i in 10:
		assert_eq(HuntSystem.pick(game, "fox", "woods"), "fox")
	# Others join unless skipped.
	game.apply(Effect.compile("feat - loner"))
	var seen := {}
	for _i in 60:
		seen[HuntSystem.pick(game, "fox", "woods")] = true
	assert_true(seen.has("hare"), "another creature of the zone can be met")
	game.apply(Effect.compile("feat + scout"))
	for _i in 20:
		assert_eq(HuntSystem.pick(game, "fox", "woods"), "fox", "every other creature skipped")


func test_exploring_uses_the_rules_creature_chance() -> void:
	for _i in 20:
		game.runner.act("explore")
		game.runner.frames.clear()
		assert_ne(game.runner.status, "combat", "0 in 20: never a creature")
		game.take_output()
	game.apply(Effect.compile("feat + tracker"))
	game.runner.act("explore")
	assert_eq(game.runner.status, "combat", "+ 20: always")


func test_a_random_fight_can_be_avoided() -> void:
	game.apply(Effect.compile("feat + tracker"))
	game.apply(Effect.compile("feat + scout"))
	game.runner.act("explore")
	assert_string_contains(_text(), "ESCAPE")
	assert_ne(game.runner.status, "combat")
	assert_true(game.state.combat.is_empty() or game.state.combat.get("result", "") != "")


func test_hunting_is_not_a_random_fight() -> void:
	game.apply(Effect.compile("feat + tracker"))
	game.apply(Effect.compile("feat + scout"))
	game.runner.act("hunt", "fox")
	assert_false(_text().contains("ESCAPE"))
	assert_eq(game.runner.status, "combat")


func test_a_second_fight_follows() -> void:
	game.apply(Effect.compile("feat + tracker"))
	game.apply(Effect.compile("feat + loner"))
	game.runner.act("explore")
	var encounters := game.runner.frames.filter(func(f): return f.kind == "encounter")
	assert_eq(encounters.size(), 2, "the second meeting waits under the first")
	game.state.combat.result = "won"
	game.runner._finish_fight()
	game.runner.run()
	for _i in 5:
		if game.runner.status == "continue":
			game.runner.proceed()
	assert_string_contains(_text(), "ANOTHER ONE")


func test_an_automatic_action_plays_the_fight() -> void:
	game.apply(Effect.compile("feat + tracker"))
	game.apply(Effect.compile("log.auto = submit"))
	game.runner.act("explore")
	assert_ne(game.runner.status, "combat", "the fight played itself")
	assert_eq(game.last_fight, "lost by submitting")


func test_the_new_rules_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := """== hunt_rules h
target weight: 3 +
others when: player is grumpy

== combat_rules c
creature chance: often
auto action: nothing.here

== scene s
if player is at a place flagged nowhere:
    Hi.
if player parts are all unicorn:
    Hi.
~ player.hp = 3 turns ago
"""
	for name: String in {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad}:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string({"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad}[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	for part in ["Target weight", "grumpy", "Creature chance", "nothing.here", "nowhere", "unicorn", "not a time value"]:
		assert_string_contains(text, part)
