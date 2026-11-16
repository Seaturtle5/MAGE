class_name NotesSystem
extends RefCounted
## The player's own notes, kept in the journal: written in a text box, listed
## by date, crossed out one by one or torn out all at once. A game's
## `== notes_rules` says when notes can be kept and what is said:
##
##   == notes_rules my_notes
##   when: player has journal                       (notes can be written and read while this holds)
##   missing: You have nothing to write in.         (shown instead while it does not)
##   write: You open your journal and write...      (above the text box)
##   browse: You page through your notes:           (above the list)
##   none: You have no notes yet.                   (instead of an empty list)
##   date: [note.month]/[note.day]/[note.year]      (each note's date; also note.number, the place in the list)
##   crossed out: You cross out the note.           (after crossing one out)
##   torn out: You tear out every note.             (after tearing them all out)
##   write label: Write, cross out label: Cross out, tear out label: Tear out all   (the buttons)
##   longest: 500                                   (most letters in a note; default 500)
##
## Without notes rules there are no notes. The notes are saved with the game
## (`notes.list`: the turn each was written and its text); `notes.count` is how
## many there are. Dates come from the calendar (`start date:` of the status
## bar, see Game.date_of); without one, `note.day` is the game's day number.

const LIST := "notes.list"


static func rules(game) -> String:
	var defs: Dictionary = game.content.all_of("notes_rules")
	return "" if defs.is_empty() else str(defs.keys()[0])


static func field(game, name: String, fallback: String = "") -> String:
	var id := rules(game)
	return fallback if id == "" else game.content.typed_value("notes_rules", id, name, fallback)


## A notes rules text with its markup worked out ("" when the game has none).
static func text(game, name: String) -> String:
	var raw := field(game, name)
	if raw == "":
		return ""
	var t := TextTemplate.compile(raw)
	return raw if t.has("error") else TextTemplate.plain(game.render(t))


## Whether the game keeps notes at all.
static func enabled(game) -> bool:
	return rules(game) != ""


## Whether the player can write and read notes now (`when:`).
static func available(game) -> bool:
	if not enabled(game):
		return false
	var when := field(game, "when")
	return when == "" or Condition.evaluate(Condition.compile(when), game)


static func longest(game) -> int:
	var n := field(game, "longest", "500")
	return int(n) if n.is_valid_int() and int(n) > 0 else 500


## The notes as stored, sorted by when they were written (the original sorts
## its table by date; notes of the same day keep the order they were written in).
static func _sorted(game) -> Array:
	var list: Array = Array(game.state.values.get(LIST, [])).duplicate(true)
	var days: Array = list.map(func(n: Dictionary) -> int: return game.day_of(int(n.get("turn", 0))))
	var order: Array = range(list.size())
	order.sort_custom(func(a: int, b: int) -> bool: return days[a] < days[b] or (days[a] == days[b] and a < b))
	return order.map(func(i: int) -> Dictionary: return list[i])


static func count(game) -> int:
	return Array(game.state.values.get(LIST, [])).size()


## The notes for the journal, in order: {"number", "date", "text"}.
static func entries(game) -> Array:
	var out: Array = []
	var notes := _sorted(game)
	var saved := {}
	for key in ["note.day", "note.month", "note.year", "note.number"]:
		if game.state.values.has(key):
			saved[key] = game.state.values[key]
	for i in notes.size():
		var n: Dictionary = notes[i]
		var date: Array = game.date_of(int(n.get("turn", 0)))
		game.state.values["note.year"] = date[0]
		game.state.values["note.month"] = date[1]
		game.state.values["note.day"] = date[2]
		game.state.values["note.number"] = i + 1
		out.append({"number": i + 1, "date": text(game, "date"), "text": str(n.get("text", ""))})
	for key in ["note.day", "note.month", "note.year", "note.number"]:
		game.state.values.erase(key)
		if saved.has(key):
			game.state.values[key] = saved[key]
	return out


## Writes a note (the text as typed, trimmed and cut to `longest`); an empty
## text writes nothing. Returns whether a note was written.
static func write(game, note: String) -> bool:
	if not available(game):
		return false
	note = note.strip_edges().left(longest(game))
	if note == "":
		return false
	var list: Array = Array(game.state.values.get(LIST, [])).duplicate(true)
	list.append({"turn": game.state.turn, "text": note})
	game.state.values[LIST] = list
	return true


## Crosses out note `number` (as listed, from 1). Returns what is said, or "" if there is no such note.
static func cross_out(game, number: int) -> String:
	if not available(game) or number < 1 or number > count(game):
		return ""
	var notes := _sorted(game)
	notes.remove_at(number - 1)
	game.state.values[LIST] = notes
	return text(game, "crossed out")


## Tears out every note. Returns what is said, or "" if there were none.
static func tear_out(game) -> String:
	if not available(game) or count(game) == 0:
		return ""
	game.state.values.erase(LIST)
	return text(game, "torn out")
