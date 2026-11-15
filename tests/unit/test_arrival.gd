extends GutTest
## Arrival events: walking into a place or travelling to it (the original's
## walk-in and nav-in events), with priority, cooldown, chance and conditions.

const ROOT := "user://arrival_test_packs"

const PACK := """== region city
name: City

== location street
name: Street
description: A street.
region: city
flags: fast travel, known at start
exits:
    north: plaza

== location plaza
name: Plaza
description: A plaza.
region: city
flags: fast travel, known at start
exits:
    south: street

== values log
values:
    count: number

== event pigeons
name: Pigeons
found by: walking into plaza
repeat: always
cooldown: 2
priority: 2
play:
    Pigeons scatter[if player arrived by walking] as you walk in[end if].
    ~ log.count + 1 quietly

== event courier
name: Courier
found by: travelling to plaza
priority: 1
play:
    A courier was waiting for you.

== event gate
found by: leaving plaza south
repeat: always
requires: log.count >= 10 and log.count < 13
play:
    A guard stops you at the gate.
    ~ log.count + 1 quietly
    if log.count = 12:
        He waves you through.
        ~ continue moving

== event ghost
name: Ghost
found by: arriving at plaza
requires: log.count > 5
priority: 0
play:
    A ghost appears.
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "city.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 1)
	game.start("street")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func _walk(dir: String) -> String:
	game.runner.act("go", dir)
	while game.runner.status == "continue":
		game.runner.proceed()
	return _text()


func test_walking_in_brings_the_walk_in_event_and_its_cooldown() -> void:
	assert_string_contains(_walk("north"), "Pigeons scatter as you walk in.")
	_walk("south")
	assert_false(_walk("north").contains("Pigeons"), "on cooldown for 2 turns (walking takes no time)")
	_walk("south")
	for _i in 3:
		game.pass_turn()
	assert_string_contains(_walk("north"), "Pigeons scatter")


func test_travelling_brings_the_nav_in_event_first_by_priority() -> void:
	game.runner.act("travel", "plaza")
	while game.runner.status == "continue":
		game.runner.proceed()
	while game.runner.status == "combat":
		game.runner.combat_action("submit")
	var text := _text()
	assert_string_contains(text, "A courier was waiting for you.")
	assert_false(text.contains("Pigeons"), "walk-ins do not come up when travelling")


func test_conditions_hold_back_an_event() -> void:
	game.set_value("log.count", 20)
	assert_string_contains(_walk("north"), "A ghost appears.", "priority 0 comes first once its condition holds")


func test_a_leaving_event_plays_instead_of_the_move() -> void:
	game.go_to("plaza")
	game.take_output()
	game.set_value("log.count", 10)
	assert_string_contains(_walk("south"), "A guard stops you at the gate.")
	assert_eq(game.state.location, "plaza", "the move did not happen")
	var text := _walk("south")
	assert_string_contains(text, "He waves you through.")
	assert_eq(game.state.location, "street", "~ continue moving lets the move go on")
