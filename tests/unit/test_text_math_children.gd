extends GutTest
## Arithmetic in text, the repetition counter of `play X N times`, scenery added
## to another pack's place, events that are ready, and story children with
## `~ for each child play`.

const ROOT := "user://text_math_test_packs"

const PACK := """== values log
values:
    a: number 3
    b: number 4
    heads: number 3
    seen: number

== zone wild
name: Wild

== location camp
name: Camp
description: A camp.
zone: wild
image: camp_photo

== image camp_photo
artist: Someone

== location hut
name: Hut
description: A hut.

== event clearing
name: A clearing
found by: exploring in wild
requires: log.a > 5
play:
    A quiet clearing.

== scene sums
Total [log.a + log.b], double [log.a * 2 in words], at least [max(log.a, 10)].

== scene maul
~ log.heads = 3 quietly
play bite log.heads times

== scene bite
Head [play.index] of [play.count].

== scene story_child
~ child.name = "Pip" quietly
~ child.home = "bunker" quietly
~ child.relationship = "wary" quietly
~ record child

== scene child_line
[child.name] waves from the [child.home].
~ child.relationship = "close" quietly
~ log.seen + 1 quietly
"""

const EXTRA := """== extend location hut
observe:
    * The old stove
        Cold iron, rusted shut.

== extend location hut
image: hut_art

== extend location camp
image: camp_art

== image hut_art
artist: ChatGPT (placeholder)

== image camp_art
artist: ChatGPT (placeholder)
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	DirAccess.make_dir_recursive_absolute(ROOT + "/q")
	var files := {"p/pack.fsc": "== pack p\nname: Test\n", "p/main.fsc": PACK, "p/values.fsc": TestPlayerValues.TEXT,
		"q/pack.fsc": "== pack q\nname: Extra\nrequires: p\n", "q/extra.fsc": EXTRA}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the packs load without errors")
	game = Game.new(db, 5)
	game.start("camp")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func test_text_can_do_arithmetic_on_values() -> void:
	game.runner.start("sums")
	assert_string_contains(_text(), "Total 7, double six, at least 10.")


func test_play_times_counts_its_repetitions_in_order() -> void:
	game.runner.start("maul")
	var text := _text()
	assert_string_contains(text, "Head 1 of 3.\nHead 2 of 3.\nHead 3 of 3.")
	assert_eq(int(game.value("play.index")), 0, "no repetition is running afterwards")


func test_play_times_counts_inside_a_fight_script() -> void:
	game.set_value("log.heads", 2)
	var prog: Program = game.content.program("bite")
	game.play_loops.append([2, 2])
	CombatSystem._play(game, prog)
	game.play_loops.pop_back()
	assert_string_contains(_text(), "Head 2 of 2.")


func test_another_pack_can_add_scenery_to_a_place_without_any() -> void:
	assert_true(game.content.menus.has("hut.observe"), "the extension makes the observe menu")
	assert_eq(game.content.menus["hut.observe"].options.size(), 1)


func test_an_art_pack_adds_pictures_only_where_there_are_none() -> void:
	assert_eq(game.content.typed_value("location", "hut", "image"), "hut_art", "a place without a picture gets the art pack's")
	assert_eq(game.content.typed_value("location", "camp", "image"), "camp_photo", "a place's own picture wins")


func test_an_event_is_ready_when_its_requirements_hold() -> void:
	var ready := Condition.compile("clearing is ready")
	assert_false(Condition.evaluate(ready, game))
	game.set_value("log.a", 6)
	assert_true(Condition.evaluate(ready, game))


func test_story_children_are_recorded_and_visited_one_by_one() -> void:
	game.runner.start("story_child")
	_text()
	var kids: Array = game.value("pregnancy.offspring")
	assert_eq(kids.size(), 1)
	assert_eq(kids[0].name, "Pip")
	game.apply(Effect.compile("for each child at bunker play child_line"))
	assert_string_contains(_text(), "Pip waves from the bunker.")
	assert_eq(int(game.value("log.seen")), 1)
	assert_eq(game.value("pregnancy.offspring")[0].relationship, "close", "changes are kept in the record")
	game.apply(Effect.compile("for each child at roaming play child_line"))
	assert_eq(int(game.value("log.seen")), 1, "only children at that home")


func test_new_forms_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := """== values log
values:
    a: number
== scene s
Count [log.missing + 1] and [dice + bonus].
if log is ready:
    Hm.
~ for each child play nowhere_scene
"""
	var files := {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad, "values.fsc": TestPlayerValues.TEXT}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	assert_string_contains(text, "log.missing")
	assert_string_contains(text, "dice + bonus")
	assert_string_contains(text, "is not an event")
	assert_string_contains(text, "nowhere_scene")
