extends GutTest
## `[not yet implemented]` on a choice or menu option: shown greyed out with
## "Not yet implemented" under it, never chosen; its condition still hides it.

const ROOT := "user://not_implemented_test_packs"

const PACK := """== location yard
name: Yard
description: A yard.

== character wren
name: Wren
lives at: yard
talk:
    What about?
    * The weather
        It looks like rain.
    * Her past -- She looks away. [not yet implemented]
        Never written.
    * Her secret [if player.charisma > 50] [not yet implemented]
        Never written either.
actions:
    * Whittle -- Carve something [not yet implemented]
        Never written.
    * Wave
        She waves back.
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "c.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 1)
	game.start("yard")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _choices() -> Array:
	var shown: Array = game.take_output().filter(func(e): return e.type == "choices")
	return shown[-1].options if not shown.is_empty() else []


func test_a_choice_is_greyed_out_with_the_note() -> void:
	assert_true(game.runner.act("talk", "wren"))
	var options := _choices()
	assert_eq(options.map(func(o): return o.text), ["The weather", "Her past"], "a failing condition still hides it")
	assert_true(options[0].enabled)
	assert_false(options[1].enabled)
	assert_eq(str(options[1].description), "Not yet implemented", "the note replaces the description")
	assert_false(game.runner.choose(1), "it cannot be chosen")


func test_a_menu_action_is_greyed_out_with_the_note() -> void:
	assert_true(game.runner.act("actions", "wren"))
	var options := _choices()
	assert_eq(options[0].text, "Whittle")
	assert_false(options[0].enabled)
	assert_eq(str(options[0].description), "Not yet implemented")
	assert_false(game.runner.choose(0))
	assert_true(game.runner.choose(1))
