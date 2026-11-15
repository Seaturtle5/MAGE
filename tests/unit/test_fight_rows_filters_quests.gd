extends GutTest
## Fights in a row (`fight leopard 2 times:`, `fight pink_gel, blue_gel:` with
## `each:`, until one is lost or fled), characters hidden by a banned filter, a
## quest's `journal:` text, and a unique creature whose name is known.

const ROOT := "user://fight_rows_test_packs"

const STATS := """hp: 30
level: 1
damage: 2
stats: strength 10, dexterity 10, stamina 10, perception 10, intelligence 10, charisma 10
"""

const PACK := """== values log
values:
    farm: number

== filter feral
name: Feral

== location room
name: Room
description: A room.

== character wolfgirl
name: Wolfgirl
lives at: room
tags: feral
talk:
    She growls.

== quest farm
name: Farm Quests
stages:
    not_started
    open
    completed
done at: completed
journal:
    if log.farm = 1:
        Wendy is home again.
    else:
        Anthony asked me to find Wendy.

== scene gang
fight leopard 2 times:
    each:
        Leopard [fights.number] of [fights.total] leaps in.
    won:
        All [fights.won] beaten.
    lost:
        Beaten after [fights.won].

== scene gels
fight pink_gel, blue_gel:
    won:
        Gels gone.

== scene meet_dwarf
fight dwarf:
    won:
        Done.

== creature leopard
name: Leopard
%s
== creature pink_gel
name: Pink Gel
%s
== creature blue_gel
name: Blue Gel
%s
== creature dwarf
name: Dwarf Male
title: Dwarf Scavenger
personal name: Yodgrak
unique: yes
%s""" % [STATS, STATS, STATS, STATS]

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "main.fsc": PACK, "values.fsc": TestPlayerValues.TEXT}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 4)
	game.start("room")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


## Ends the fight going on as a win.
func _win() -> void:
	assert_eq(game.runner.status, "combat")
	game.state.combat.result = "won"
	game.runner._finish_fight()
	game.runner.run()


func test_fights_in_a_row_until_all_are_won() -> void:
	game.runner.start("gang")
	assert_string_contains(_text(), "Leopard 1 of 2 leaps in.")
	_win()
	assert_string_contains(_text(), "Leopard 2 of 2 leaps in.", "the next fight follows")
	assert_eq(game.runner.status, "combat")
	_win()
	assert_string_contains(_text(), "All 2 beaten.")
	assert_eq(game.runner.status, "idle")


func test_fights_in_a_row_stop_at_a_loss() -> void:
	game.runner.start("gang")
	_win()
	_text()
	assert_true(game.runner.combat_action("submit"))
	var text := _text()
	assert_string_contains(text, "Beaten after 1.")
	assert_false(text.contains("Leopard 3"))


func test_fights_in_a_row_against_several_creatures() -> void:
	game.runner.start("gels")
	assert_eq(game.state.combat.creature, "pink_gel")
	_win()
	assert_eq(game.state.combat.creature, "blue_gel", "then the next creature")
	_win()
	assert_string_contains(_text(), "Gels gone.")


func test_a_banned_filter_hides_a_character() -> void:
	game.runner.show_location()
	var view: Dictionary = game.take_output().filter(func(e): return e.type == "location")[0]
	assert_eq(view.people.size(), 1)
	game.set_filter("feral", "banned")
	game.runner.show_location()
	view = game.take_output().filter(func(e): return e.type == "location")[0]
	assert_eq(view.people.size(), 0, "hidden from its place")
	assert_false(game.runner.act("talk", "wolfgirl"), "and its talk is not offered")
	game.set_filter("feral", "warded")
	assert_true(game.runner.act("talk", "wolfgirl"), "a ward does not hide a character")


func test_a_quest_journal_text_says_where_it_stands() -> void:
	assert_eq(game.quest_list(), [], "not started")
	game.apply(Effect.compile("quest farm = open quietly"))
	var q: Dictionary = game.quest_list()[0]
	assert_eq(q.journal, "Anthony asked me to find Wendy.")
	assert_false(q.done)
	game.set_value("log.farm", 1)
	game.apply(Effect.compile("quest farm = completed quietly"))
	q = game.quest_list()[0]
	assert_eq(q.journal, "Wendy is home again.", "worked out when the journal is shown")
	assert_true(q.done)
	assert_eq(q.history, [], "stages without lines leave no empty history")


func test_a_unique_creature_whose_name_is_known() -> void:
	game.runner.start("meet_dwarf")
	assert_eq(game.describe("the enemy"), "Dwarf Scavenger", "a unique creature: its title")
	game.apply(Effect.compile("creature dwarf name known yes"))
	assert_eq(game.describe("the enemy"), "Yodgrak", "the original's enemy type 2")
	assert_eq(game.describe("Enemy name"), "Yodgrak")


func test_the_new_forms_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := """== scene s
fight wolf, nobody_gel:
    won:
        Hm.
fight wolf log.missing times:
    each:
        Hm.
~ creature wolf name known yes
== creature wolf
name: Wolf
"""
	var files := {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad, "values.fsc": TestPlayerValues.TEXT}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	for part in ["nobody_gel", "log.missing", "to be known by"]:
		assert_string_contains(text, part)
