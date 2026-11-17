extends GutTest
## A character counts as met once the first talk (or sex scene, or a story's
## `play talk of X`) is over, so `if not X.met:` plays the first meeting.

const ROOT := "user://met_after_talk_packs"

const PACK := """== location field
name: Field
description: Tall grass.

== character ann
name: Ann
lives at: field
talk:
    if not ann.met:
        Nice to meet you.
    else:
        Hello again.
sex:
    if not ann.met:
        A first time.
    else:
        Again.

== character bob
name: Bob
lives at: field
talk:
    if not bob.met:
        Who are you?
    else:
        You again.

== scene introduce_bob
play talk of bob
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


func _said() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func test_the_first_talk_plays_the_first_meeting() -> void:
	assert_true(game.runner.act("talk", "ann"))
	assert_string_contains(_said(), "Nice to meet you.")
	assert_true(Condition._truthy(game.value("ann.met")), "met once the talk is over")
	assert_true(game.runner.act("talk", "ann"))
	assert_string_contains(_said(), "Hello again.")


func test_a_first_sex_scene_sees_the_character_unmet() -> void:
	assert_true(game.runner.act("sex", "ann"))
	assert_string_contains(_said(), "A first time.")
	assert_true(Condition._truthy(game.value("ann.met")))


func test_a_story_playing_a_talk_sees_the_first_meeting() -> void:
	game.runner.start("introduce_bob")
	assert_string_contains(_said(), "Who are you?")
	assert_true(Condition._truthy(game.value("bob.met")))
