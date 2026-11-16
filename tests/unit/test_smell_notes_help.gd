extends GutTest
## Smelling things (SmellSystem), the player's own notes (NotesSystem), help
## topics (HelpSystem), the calendar, moments of a game's own (`~ moment`) and
## hooks after picking an item up.

const ROOT := "user://smell_notes_help_packs"

const PACK := """== smell_rules smells
smelling: You sniff the [name of smell.thing].
smelling person: You sniff [name of smell.thing].
no scent: It smells pretty normal for [if smell.kind is character][name of smell.thing][else][a name of smell.thing][end if].
no place scent: This place smells as you'd expect.
yourself:
    You smell like yourself[if player is in heat], musky[end if].

== notes_rules notes
when: player has notebook
missing: You have nothing to write in.
write: You open your notebook and write...
browse: Your notes:
none: You have no notes.
date: [note.month]/[note.day]/[note.year]
crossed out: You cross it out.
torn out: You tear out every page.
longest: 20

== status_bar bar
meters: hp
start date: 2008-04-28

== help basics
title: Basics
order: 10
text:
    Welcome to [story title]!

== help later
title: Later
text:
    -> help_later_text

== help first
title: First
order: 5
text:
    [if notes.count > 0]You have notes.[else]No notes yet.[end if]

== scene help_later_text
Some more help.

== values tally
values:
    heard: number 0
    picked: number 0

== location room
name: Room
description: A room.
scent: Dust and old paper.
items: rose, notebook, rock

== location hall
name: Hall
description: A hall.
exits:
    north: room

== character bob
name: Bob
lives at: room
description: Bob.
scent: Bob smells of soap.

== character ann
name: Ann
lives at: room
description: Ann.

== item rose
name: rose
description: A rose.
scent: Sweet.

== item rock
name: rock
description: A rock.

== item notebook
name: notebook
description: A notebook.
use:
    You leaf through it.
    ~ moment leafing
    You close it.
consumed: no

== hook leafing_hook
on: leafing
do:
    A pressed flower falls out.
    ~ tally.heard + 1 quietly

== hook rock_taken
on: after picking up rock
do:
    It is heavier than it looks.
    ~ tally.picked + 1 quietly
"""

var game: Game


func _load(text: String, folder: String) -> ContentDB:
	DirAccess.make_dir_recursive_absolute(folder + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\ntitle: Test Game\n", "player_values.fsc": TestPlayerValues.TEXT, "content.fsc": text}
	for name: String in files:
		var fa := FileAccess.open(folder + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([folder])
	return db


func before_each() -> void:
	var db := _load(PACK, ROOT)
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 1)
	game.start("room")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _said() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
		elif e.type in ["notice", "title"]:
			out.append(str(e.text))
	return "\n".join(out)


func _view() -> Dictionary:
	game.runner.show_location()
	return game.take_output().filter(func(e): return e.type == "location")[-1]


func test_characters_places_items_and_the_player_can_be_smelled() -> void:
	var view := _view()
	assert_true(view.people.all(func(p): return p.smell), "with a fallback every character can be smelled")
	assert_true(view.smell, "the place offers Smell")
	assert_true(game.runner.act("smell", "bob"))
	var said := _said()
	assert_string_contains(said, "You sniff Bob.")
	assert_string_contains(said, "Bob smells of soap.")
	assert_true(game.runner.act("smell", "ann"))
	assert_string_contains(_said(), "It smells pretty normal for Ann.")
	assert_true(game.runner.act("smell_place", ""))
	said = _said()
	assert_string_contains(said, "You sniff the Room.")
	assert_string_contains(said, "Dust and old paper.")
	assert_false(game.runner.act("smell_item", "rose"), "only carried items")
	game.apply(Effect.compile("give rose"))
	game.apply(Effect.compile("give rock"))
	game.take_output()
	assert_true(game.runner.act("smell_item", "rose"))
	said = _said()
	assert_string_contains(said, "You sniff the rose.")
	assert_string_contains(said, "Sweet.")
	assert_true(game.runner.act("smell_item", "rock"))
	assert_string_contains(_said(), "It smells pretty normal for a rock.")
	assert_true(game.runner.act("smell_self", ""))
	said = _said()
	assert_string_contains(said, "You smell like yourself.")
	assert_false(said.contains("You sniff"), "nothing is said before the player's own smell")
	game.go_to("hall")
	game.take_output()
	assert_true(game.runner.act("smell_place", ""))
	assert_string_contains(_said(), "This place smells as you'd expect.")
	assert_false(game.runner.act("smell", "bob"), "Bob is not here")


func test_without_smell_rules_only_things_with_a_scent() -> void:
	var db := _load(PACK.substr(PACK.find("== notes_rules")), ROOT + "_plain")
	var g := Game.new(db, 1)
	g.start("room")
	g.take_output()
	g.runner.show_location()
	var view: Dictionary = g.take_output().filter(func(e): return e.type == "location")[-1]
	assert_true(view.people.filter(func(p): return p.id == "bob")[0].smell)
	assert_false(view.people.filter(func(p): return p.id == "ann")[0].smell)
	assert_false(SmellSystem.can_smell(g, "player"))
	assert_true(SmellSystem.can_smell(g, "location"))
	g.dispose()


func test_notes_are_written_listed_by_date_crossed_out_and_torn_out() -> void:
	assert_true(NotesSystem.enabled(game))
	assert_false(NotesSystem.available(game), "without the notebook")
	assert_false(NotesSystem.write(game, "nothing to write in"))
	assert_eq(NotesSystem.text(game, "missing"), "You have nothing to write in.")
	game.apply(Effect.compile("give notebook"))
	assert_true(NotesSystem.write(game, "  Bob owes me soap.  "))
	assert_false(NotesSystem.write(game, "   "), "an empty note is not written")
	for _i in 9:
		game.pass_turn()
	assert_true(NotesSystem.write(game, "The rose is in the room, and this is long"))
	var notes := NotesSystem.entries(game)
	assert_eq(notes.size(), 2)
	assert_eq(notes[0].text, "Bob owes me soap.", "trimmed")
	assert_eq(notes[0].date, "4/28/2008", "the first day")
	assert_eq(notes[1].date, "4/29/2008", "the second day")
	assert_eq(notes[1].text.length(), 20, "cut to the longest a note may be")
	assert_eq(int(game.value("notes.count")), 2)
	assert_eq([int(game.value("date.year")), int(game.value("date.month")), int(game.value("date.day"))], [2008, 4, 29])
	assert_eq(game.value("note.day"), null, "the note values are gone after listing")
	# Saved with the game.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game.save_dict()))
	var other := Game.new(game.content, 1)
	assert_true(other.load_dict(saved))
	assert_eq(NotesSystem.entries(other).map(func(n): return n.text), notes.map(func(n): return n.text))
	other.dispose()
	assert_eq(NotesSystem.cross_out(game, 3), "", "no such note")
	assert_eq(NotesSystem.cross_out(game, 1), "You cross it out.")
	assert_eq(NotesSystem.entries(game).size(), 1)
	assert_eq(NotesSystem.tear_out(game), "You tear out every page.")
	assert_eq(NotesSystem.count(game), 0)
	assert_eq(NotesSystem.tear_out(game), "", "nothing left to tear out")


func test_the_calendar_runs_across_months() -> void:
	for _i in 8 * 3:
		game.pass_turn()
	assert_eq(game.date_of(game.state.turn), [2008, 5, 1])
	assert_eq(game.date_of(8 * 365), [2009, 4, 28], "2008 is a leap year, but its February is behind")
	assert_eq(Game._month_days(2008, 2), 29)
	assert_eq(Game._month_days(1900, 2), 28)


func test_help_topics_are_ordered_and_worked_out_when_shown() -> void:
	var topics := HelpSystem.topics(game)
	assert_eq(topics.map(func(t): return t.id), ["first", "basics", "later"], "by order, then without one last")
	assert_eq(topics[1].title, "Basics")
	var text := func(id: String) -> String:
		return "\n".join(HelpSystem.text(game, id).map(func(p): return TextTemplate.plain(p)))
	assert_eq(text.call("basics"), "Welcome to Test Game!")
	assert_eq(text.call("later"), "Some more help.")
	assert_eq(text.call("first"), "No notes yet.")


func test_a_moment_of_the_games_own_plays_its_hooks_in_place() -> void:
	game.apply(Effect.compile("give notebook"))
	game.take_output()
	assert_true(game.runner.act("use", "notebook"))
	var said := _said()
	assert_true(said.find("You leaf through it.") < said.find("A pressed flower falls out.") and said.find("A pressed flower falls out.") < said.find("You close it."), said)
	assert_eq(int(game.value("tally.heard")), 1)


func test_hooks_after_picking_an_item_up() -> void:
	assert_true(game.runner.act("take", "rose"))
	assert_eq(int(game.value("tally.picked")), 0)
	assert_true(game.runner.act("take_all", ""))
	assert_string_contains(_said(), "It is heavier than it looks.")
	assert_eq(int(game.value("tally.picked")), 1)
	assert_eq(int(game.state.inventory.get("rock", 0)), 1)


func test_new_fields_are_validated() -> void:
	var bad := """== notes_rules n
when: player has nothing_at_all
date: [note.nonsense]
longest: many

== status_bar b
meters: hp
start date: 2008-13-01

== help h
order: first

== hook h2
on: dancing
do:
    Hi.

== hook h3
on: after picking up nothing_here
do:
    Hi.
"""
	var db := _load(bad, ROOT + "_bad")
	var text := "\n".join(db.errors().map(func(e): return str(e.message)))
	assert_string_contains(text, "nothing_at_all")
	assert_string_contains(text, "note.nonsense")
	assert_string_contains(text, "'longest'")
	assert_string_contains(text, "'start date'")
	assert_string_contains(text, "needs a 'title:'")
	assert_string_contains(text, "'order' is a whole number")
	assert_string_contains(text, "no scene raises 'dancing'")
	assert_string_contains(text, "nothing_here")
