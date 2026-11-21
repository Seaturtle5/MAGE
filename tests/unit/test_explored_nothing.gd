extends GutTest
## The hunting rules' `explored nothing:`: what exploring says when it finds
## nothing and the zone has no ambient lines of its own.

const ROOT := "user://explored_nothing_test_packs"

const WORLD := """== zone fields
name: Fields

== zone grove
name: Grove
ambient:
    Leaves rustle.

== location meadow
name: Meadow
description: Grass.
zone: fields
exits:
    north: copse

== location copse
name: Copse
description: Trees.
zone: grove
exits:
    south: meadow
"""

const RULES := """
== hunt_rules test
explored nothing:
    if here.zone = "fields":
        You find only grass in the [name of here].
    else:
        You find nothing.
"""

var game: Game


func _start(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "c.fsc": text}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("meadow")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func test_the_rules_say_what_exploring_finds_when_nothing() -> void:
	_start(WORLD + RULES)
	assert_true(game.runner.act("explore"))
	assert_string_contains(_text(), "You find only grass in the Meadow.", "[name of here] names the place")


func test_a_zone_with_ambient_lines_keeps_them() -> void:
	_start(WORLD + RULES)
	game.apply(Effect.compile("go to copse"))
	game.take_output()
	assert_true(game.runner.act("explore"))
	var text := _text()
	assert_string_contains(text, "Leaves rustle.")
	assert_false(text.contains("You find nothing."))


func test_without_rules_the_plain_line() -> void:
	_start(WORLD)
	assert_true(game.runner.act("explore"))
	assert_string_contains(_text(), "find nothing of interest")
