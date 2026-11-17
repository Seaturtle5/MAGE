extends GutTest
## Markup inside a text value or a choice's description is rendered when shown,
## as the original substitutes a text when it prints it.

const ROOT := "user://markup_in_values_packs"

const PACK := """== location field
name: Field
description: Tall grass.

== values mutt
values:
    color: text
    look: text

== scene start
~ mutt.color = "[one of]brown[or]brown[at random]"
~ mutt.look = "a well-muscled [mutt.color] dog"
You see [mutt.look].
* Pet the dog -- Scratch the [mutt.color] ears
    Good dog.
"""


var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "content.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors().map(func(d): return "%d %s" % [d.line, d.message]), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("field")
	game.take_output()


func after_each() -> void:
	game.dispose()


func test_a_text_value_with_markup_is_rendered_when_shown() -> void:
	game.runner.start("start")
	var said := ""
	var choices: Array = []
	for e in game.take_output():
		if e.type == "paragraph":
			said += TextTemplate.plain(e.spans) + "\n"
		elif e.type == "choices":
			choices = e.options
	assert_string_contains(said, "You see a well-muscled brown dog.")
	assert_false("[" in said, "no markup is shown")
	assert_eq(choices.size(), 1)
	assert_eq(choices[0].description, "Scratch the brown ears", "a choice's description is rendered too")


func test_plain_text_is_left_as_it_is() -> void:
	assert_eq(game.rendered_text("just words"), "just words")
