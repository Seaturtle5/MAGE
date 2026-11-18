extends GutTest
## The debug window's engine side: debug commands, suggestions while typing,
## running a typed line, and looking up and changing values.

const ROOT := "user://debug_system_test_packs"

const PACK := """== zone woods
name: Woods

== location camp
name: Camp
description: A camp.
zone: woods
flags: fast travel

== location great_hall
name: Great Hall
description: A hall.

== item rope
name: Rope
description: A rope.

== item rowan_staff
name: Rowan Staff
description: A staff.

== feat keen
name: Keen

== creature wolf
name: Wolf
found in: woods
level: 1
hp: 5
damage: 1

== values harvest
values:
    stage: number
    blessed: flag
    mood: calm, wild
    song: text
    last_feast: time
    guests: list

== quest feast
name: The Feast
stages:
    none
    invited
    held

== event old_debt
name: Old Debt
found by: exploring in woods
active: no
play:
    A DEBT IS CALLED IN

== scene bonfire
THE FIRE BURNS

== command skip_to_the_feast
name: Skip to the feast
description: Sets the harvest story to its last chapter.
debug: yes
play:
    ~ harvest.stage = 9
    SKIPPED AHEAD

== command whistle
name: Whistle
when: player has feat keen
play:
    YOU WHISTLE

== command hum
name: Hum
play:
    YOU HUM
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test Pack\n", "player_values.fsc": TestPlayerValues.TEXT, "world.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
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


func _texts(suggestions: Array) -> Array:
	return suggestions.map(func(s: Dictionary) -> String: return str(s.text))


func test_a_debug_command_is_not_among_the_place_s_actions() -> void:
	assert_eq(game.runner.available_commands(), ["hum"], "whistle needs a feat, the debug command is never offered")
	assert_false(game.runner.act("command", "skip_to_the_feast"), "nor can the player run it as an action")


func test_commands_are_listed_debug_ones_first() -> void:
	var list: Array = DebugSystem.commands(game)
	assert_eq(list.map(func(c: Dictionary) -> String: return str(c.id)), ["skip_to_the_feast", "hum", "whistle"])
	assert_true(list[0].debug)
	assert_eq(list[0].pack, "Test Pack")
	assert_eq(list[0].description, "Sets the harvest story to its last chapter.")
	assert_false(list[2].available, "whistle's `when` does not hold")
	assert_true(list[1].available)


func test_a_command_runs_by_its_id_or_its_name() -> void:
	var r: Dictionary = DebugSystem.run(game, "skip_to_the_feast")
	assert_true(r.ok, str(r.message))
	assert_eq(int(game.value("harvest.stage")), 9)
	assert_has(r.said, "SKIPPED AHEAD")
	game.runner.proceed()
	r = DebugSystem.run(game, "  Whistle ")
	assert_true(r.ok, "by name, in any case, even though the player is not offered it")
	assert_has(r.said, "YOU WHISTLE")


func test_an_action_line_runs_and_says_what_it_did() -> void:
	var r: Dictionary = DebugSystem.run(game, "~ give rope 2")
	assert_true(r.ok, str(r.message))
	assert_eq(int(game.state.inventory.get("rope", 0)), 2)
	assert_true(r.said.any(func(t: String) -> bool: return "Rope" in t), str(r.said))
	assert_true(DebugSystem.run(game, "~ go to great_hall").ok)
	assert_eq(game.state.location, "great_hall")
	assert_true(DebugSystem.run(game, "~ activate old_debt").ok)
	assert_true(game._event("old_debt").active)
	assert_true(DebugSystem.run(game, "~ harvest.mood = wild").ok)
	assert_eq(str(game.value("harvest.mood")), "wild")


func test_what_was_done_by_hand_is_among_the_steps_of_a_bug_report() -> void:
	assert_true(DebugSystem.run(game, "~ give rope 2").ok)
	assert_true(DebugSystem.set_value(game, "harvest.stage", "4").ok)
	assert_false(DebugSystem.run(game, "~ give ropee").ok)
	var steps: Array = game.feedback.steps.map(func(s: Dictionary) -> String: return str(s.text))
	assert_has(steps, "debug: ~ give rope 2")
	assert_has(steps, "debug: harvest.stage = 4")
	assert_false(steps.any(func(t: String) -> bool: return "ropee" in t), "a refused line is no step")


func test_stories_play_from_a_line() -> void:
	var r: Dictionary = DebugSystem.run(game, "play bonfire")
	assert_true(r.ok, str(r.message))
	assert_has(r.said, "THE FIRE BURNS")
	game.runner.proceed()
	r = DebugSystem.run(game, "event old_debt")
	assert_true(r.ok, str(r.message))
	assert_has(r.said, "A DEBT IS CALLED IN")
	game.runner.proceed()
	r = DebugSystem.run(game, "fight wolf")
	assert_true(r.ok, str(r.message))
	assert_eq(game.runner.status, "combat")


func test_a_line_is_checked_like_content_before_it_runs() -> void:
	var r: Dictionary = DebugSystem.run(game, "~ give ropee")
	assert_false(r.ok)
	assert_string_contains(r.message, "ropee")
	assert_eq(game.state.inventory.size(), 0, "nothing was given")
	assert_false(DebugSystem.run(game, "~ harvest.nothing = 3").ok, "an undeclared value")
	assert_false(DebugSystem.run(game, "play no_such_scene").ok)
	assert_false(DebugSystem.run(game, "event no_such_event").ok)
	assert_false(DebugSystem.run(game, "~ this is not an action").ok)
	r = DebugSystem.run(game, "whistel")
	assert_false(r.ok, "plain words are not shown as story text")
	assert_string_contains(r.message, "No command is called 'whistel'")
	assert_false(DebugSystem.run(game, "   ").ok)
	assert_eq(game.content.errors(), [], "the content's own problems are left as they were")


func test_while_something_plays_only_actions_run() -> void:
	assert_true(DebugSystem.run(game, "fight wolf").ok)
	assert_eq(game.runner.status, "combat")
	assert_false(DebugSystem.run(game, "hum").ok, "a command waits")
	assert_false(DebugSystem.run(game, "play bonfire").ok, "a scene waits")
	assert_false(DebugSystem.run(game, "event old_debt").ok)
	var r: Dictionary = DebugSystem.run(game, "~ give rope")
	assert_true(r.ok, str(r.message))
	assert_eq(int(game.state.inventory.get("rope", 0)), 1)
	assert_eq(game.runner.status, "combat", "the fight goes on")


func test_suggestions_while_typing() -> void:
	# Nothing typed: every command, then what else can be typed.
	var all: Array = DebugSystem.suggest(game, "", 100)
	assert_eq(_texts(all).slice(0, 3), ["skip_to_the_feast", "hum", "whistle"])
	assert_has(_texts(all), "~ give ")
	assert_has(_texts(all), "event ")
	# A part of a name: the commands that start with it first.
	assert_eq(_texts(DebugSystem.suggest(game, "wh")), ["whistle"])
	assert_eq(_texts(DebugSystem.suggest(game, "feast")), ["skip_to_the_feast"])
	assert_eq(DebugSystem.suggest(game, "sk")[0].command, "skip_to_the_feast")
	# An action being typed: the lines that start so, then the IDs that fit the word before.
	assert_has(_texts(DebugSystem.suggest(game, "~ gi")), "~ give ")
	assert_eq(_texts(DebugSystem.suggest(game, "~ give ro")), ["~ give rope", "~ give rowan_staff"])
	assert_eq(_texts(DebugSystem.suggest(game, "~ give staff")), ["~ give rowan_staff"], "by a part of the ID or the name")
	assert_eq(_texts(DebugSystem.suggest(game, "~ go to gr")), ["~ go to great_hall"])
	assert_eq(_texts(DebugSystem.suggest(game, "~ unresolve ")), ["~ unresolve old_debt"])
	assert_eq(_texts(DebugSystem.suggest(game, "~ feat + k")), ["~ feat + keen"])
	assert_eq(_texts(DebugSystem.suggest(game, "fight w")), ["fight wolf"])
	assert_eq(_texts(DebugSystem.suggest(game, "play bon")), ["play bonfire"])
	assert_eq(_texts(DebugSystem.suggest(game, "event old")), ["event old_debt"])
	assert_eq(_texts(DebugSystem.suggest(game, "~ quest fe")), ["~ quest feast"])
	assert_eq(_texts(DebugSystem.suggest(game, "~ quest feast = ")), ["~ quest feast = none", "~ quest feast = invited", "~ quest feast = held"])
	assert_eq(_texts(DebugSystem.suggest(game, "~ harvest.mood = ")), ["~ harvest.mood = calm", "~ harvest.mood = wild"])
	assert_has(_texts(DebugSystem.suggest(game, "~ harvest.st")), "~ harvest.stage")
	assert_eq(DebugSystem.suggest(game, "", 4).size(), 4, "no more than asked for")


func test_values_are_looked_up_by_words_of_their_path() -> void:
	var found: Dictionary = DebugSystem.values(game, "harvest")
	var paths: Array = found.rows.map(func(r: Dictionary) -> String: return str(r.path))
	assert_eq(paths, ["harvest.blessed", "harvest.guests", "harvest.last_feast", "harvest.mood", "harvest.song", "harvest.stage"])
	assert_eq(found.matched, 6)
	var by_path := {}
	for r: Dictionary in found.rows:
		by_path[r.path] = r
	assert_eq(by_path["harvest.blessed"].kind, "flag")
	assert_eq(by_path["harvest.blessed"].shown, "no")
	assert_eq(by_path["harvest.mood"].states, ["calm", "wild"])
	assert_eq(by_path["harvest.last_feast"].shown, "never")
	assert_false(by_path["harvest.stage"].changed)
	# Several words: all of them; events have their two flags; a quest is a value.
	assert_eq(DebugSystem.values(game, "great hall").matched, 0, "words are parts of a value's path")
	assert_eq(DebugSystem.values(game, "old_debt event").rows.map(func(r: Dictionary) -> String: return str(r.path)),
		["event.old_debt.active", "event.old_debt.resolved"])
	assert_eq(DebugSystem.values(game, "quest.feast").rows[0].shown, "none")
	assert_eq(DebugSystem.values(game, "", false, 3).rows.size(), 3, "no more rows than asked for")
	assert_gt(DebugSystem.values(game, "", false, 3).matched, 3, "but it says how many there are")


func test_values_are_changed_by_hand() -> void:
	assert_true(DebugSystem.set_value(game, "harvest.stage", "4").ok)
	assert_eq(int(game.value("harvest.stage")), 4)
	assert_false(DebugSystem.set_value(game, "harvest.stage", "four").ok)
	assert_true(DebugSystem.set_value(game, "harvest.blessed", "yes").ok)
	assert_true(Condition.evaluate(Condition.compile("harvest.blessed"), game))
	assert_false(DebugSystem.set_value(game, "harvest.blessed", "maybe").ok)
	assert_true(DebugSystem.set_value(game, "harvest.mood", "wild").ok)
	var r: Dictionary = DebugSystem.set_value(game, "harvest.mood", "sleepy")
	assert_false(r.ok)
	assert_string_contains(r.message, "calm, wild")
	assert_true(DebugSystem.set_value(game, "harvest.song", "an old tune").ok)
	assert_eq(str(game.value("harvest.song")), "an old tune")
	assert_true(DebugSystem.set_value(game, "quest.feast", "held").ok)
	assert_true(Condition.evaluate(Condition.compile("quest feast reached held"), game))
	# A time: now, never, or turns ago.
	assert_true(DebugSystem.set_value(game, "harvest.last_feast", "3").ok)
	assert_true(Condition.evaluate(Condition.compile("since harvest.last_feast > 2 turns"), game))
	assert_false(Condition.evaluate(Condition.compile("since harvest.last_feast > 3 turns"), game))
	assert_true(DebugSystem.set_value(game, "harvest.last_feast", "now").ok)
	assert_eq(DebugSystem.value_row(game, "harvest.last_feast").shown, "now")
	assert_true(DebugSystem.set_value(game, "harvest.last_feast", "never").ok)
	assert_eq(DebugSystem.value_row(game, "harvest.last_feast").shown, "never")
	assert_false(DebugSystem.set_value(game, "harvest.last_feast", "soon").ok)
	# An event's flags.
	assert_true(DebugSystem.set_value(game, "event.old_debt.active", "yes").ok)
	assert_true(game._event("old_debt").active)
	assert_true(DebugSystem.set_value(game, "event.old_debt.resolved", "yes").ok)
	assert_true(game._event("old_debt").resolved)
	assert_false(DebugSystem.set_value(game, "event.nothing.resolved", "yes").ok)
	assert_false(DebugSystem.set_value(game, "harvest.guests", "1").ok, "lists are changed with actions")
	assert_false(DebugSystem.set_value(game, "no.such", "1").ok)
	# Only what differs from its start.
	var changed: Array = DebugSystem.values(game, "", true).rows.map(func(row: Dictionary) -> String: return str(row.path))
	assert_has(changed, "harvest.stage")
	assert_has(changed, "event.old_debt.resolved")
	assert_does_not_have(changed, "harvest.last_feast")


func test_the_validator_checks_the_debug_line() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "-bad/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT,
		"c.fsc": "== command x\nname: X\ndebug: perhaps\nplay:\n    HELLO\n"}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "-bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "-bad"])
	assert_true(db.errors().any(func(d: Dictionary) -> bool: return "Debug is yes or no" in str(d.message)), str(db.errors()))
