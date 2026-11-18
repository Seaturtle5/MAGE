class_name DebugSystem
extends RefCounted
## What a debug window does, for someone who makes content and wants to try
## it: run commands and single lines of story script, and look up and change
## the game's values.
##
## Commands are the game's `== command` definitions. One marked `debug: yes`
## is a debug command: it is not offered among a place's actions, only here:
##
##   == command skip_to_the_feast
##   name: Skip to the feast
##   description: Sets the harvest story to its last chapter.
##   debug: yes
##   play:
##       ~ harvest.stage = 9
##       ~ go to great_hall
##
## A typed line is a command's ID or name, or a line of story script as it is
## written in content: an action (`~ give rope 2`, `~ unresolve old_debt`,
## `~ go to great_hall`, `~ wolf.met = 3`), `play <scene>`, `-> <scene>`,
## `fight <creature>`; or `event <id>`, which plays an event as if found. A
## line is checked like content before it runs. Commands and stories start
## only while nothing else plays; actions alone run at any time.
##
## Values are those content declares (`== values`, quests, event outcomes),
## plus each event's `event.<id>.resolved` and `event.<id>.active`.

## The program a typed line is compiled into.
const LINE_ID := "debug window line"

## Lines offered when nothing is typed yet: what to type, and what it does.
const TEMPLATES: Array = [
	["~ give ", "an item, and how many"],
	["~ take ", "an item, and how many"],
	["~ go to ", "a place: the player goes there"],
	["~ discover ", "a place: it becomes known"],
	["~ resolve ", "an event: it counts as done"],
	["~ unresolve ", "an event: it can be found again"],
	["~ activate ", "an event: it can be found"],
	["~ deactivate ", "an event: it cannot be found"],
	["~ feat + ", "a feat the player gains (feat - takes it)"],
	["~ quest ", "a quest = one of its stages"],
	["~ infect ", "a creature whose strain infects the player"],
	["~ move ", "a character to a place"],
	["event ", "an event: it plays as if found"],
	["play ", "a scene: it plays"],
	["fight ", "a creature: a fight with it"],
]

## The word before an ID says what kind of thing the ID is.
const _KINDS: Dictionary = {
	"give": "item", "take": "item", "use": "item", "wear": "item", "wield": "item", "put": "item",
	"resolve": "event", "unresolve": "event", "activate": "event", "deactivate": "event", "event": "event",
	"to": "location", "discover": "location", "forget": "location", "in": "location", "at": "location",
	"+": "feat", "-": "feat",
	"fight": "creature", "infect": "creature", "creature": "creature",
	"play": "scene", "->": "scene",
	"move": "character", "tame": "character", "summon": "character", "dismiss": "character",
	"quest": "quest",
}


# --- Commands -------------------------------------------------------------------

## Whether a command is a debug command (`debug: yes`).
static func is_debug(content: ContentDB, id: String) -> bool:
	return content.typed_value("command", id, "debug") == "yes"


## Every command of the game, the debug commands first, each by name:
## {id, name, description, debug, available (its `when` holds), pack}.
static func commands(game) -> Array:
	var db: ContentDB = game.content
	var out: Array = []
	for id: String in db.all_of("command"):
		var when: String = db.typed_value("command", id, "when")
		out.append({"id": id, "name": db.typed_value("command", id, "name", id),
			"description": db.typed_value("command", id, "description"), "debug": is_debug(db, id),
			"available": when == "" or Condition.evaluate(Condition.compile(when), game),
			"pack": _pack_name(db, db.get_def("command", id).path)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.debug != b.debug:
			return a.debug
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out


## The name of the pack a file belongs to ("" outside every pack).
static func _pack_name(db: ContentDB, path: String) -> String:
	var pack: Dictionary = db.pack_of(path)
	if pack.is_empty():
		return ""
	var d: FscParser.Definition = pack.def
	return d.fields["name"].value if d.fields.has("name") else str(pack.id)


## The command a line names: its ID, or its name in any case. "" when none.
static func command_named(game, line: String) -> String:
	var want := line.strip_edges().to_lower()
	if want == "":
		return ""
	if game.content.has(want, "command"):
		return want
	for id: String in game.content.all_of("command"):
		if game.content.typed_value("command", id, "name", id).to_lower() == want:
			return id
	return ""


# --- Suggestions ----------------------------------------------------------------

## What the line typed so far could become, best first: {text (the whole line),
## label (what is shown), note (a description or a name), tag (a word about
## it: what kind of thing an ID is, `debug`, `not offered now` for a command
## whose `when` does not hold), command (an ID, when the suggestion is one)}.
static func suggest(game, typed: String, limit: int = 12) -> Array:
	var out: Array = []
	var line := typed.strip_edges(true, false)
	var low := line.to_lower()
	if not _is_script(low):
		# Commands whose name or ID starts with what is typed, then those that hold it.
		for pass_: int in 2:
			for c: Dictionary in commands(game):
				var name := str(c.name).to_lower()
				var starts: bool = low == "" or name.begins_with(low) or str(c.id).begins_with(low)
				var holds: bool = low in name or low in str(c.id)
				if (pass_ == 0 and starts) or (pass_ == 1 and holds and not starts):
					out.append({"text": c.id, "label": c.name, "command": c.id, "note": c.description,
						"tag": "debug" if c.debug else ("" if c.available else "not offered now")})
	if low == "" or low == "~":
		for t: Array in TEMPLATES:
			out.append({"text": t[0], "label": t[0] + "…", "note": t[1], "command": "", "tag": ""})
		return out.slice(0, limit)
	for t: Array in TEMPLATES:
		if str(t[0]).begins_with(low) and low.length() < str(t[0]).length():
			out.append({"text": t[0], "label": t[0] + "…", "note": t[1], "command": "", "tag": ""})
	if _is_script(low):
		out.append_array(_ids_for(game, line))
	return out.slice(0, limit)


## Whether a line reads as story script and not as a command's name.
static func _is_script(low: String) -> bool:
	for start: String in ["~", "->", "play ", "fight ", "event "]:
		if low.begins_with(start):
			return true
	return false


## IDs that complete the last word of a script line, by the word before it.
static func _ids_for(game, line: String) -> Array:
	var db: ContentDB = game.content
	var cut: int = maxi(line.rfind(" "), 0)
	var head := line.left(cut + 1) if " " in line else ""
	var word := line.substr(head.length()).to_lower()
	var before: PackedStringArray = head.strip_edges().split(" ", false)
	var kind: String = ""
	if not before.is_empty():
		kind = str(_KINDS.get(before[-1], ""))
		# "~ quest harvest = ": the stages of that quest.
		if before.size() >= 3 and before[-1] == "=" and before[-3] == "quest" and db.quests.has(before[-2]):
			return _completions(head, word, db.quests[before[-2]].stages, "stage", Callable(), false)
		# "~ wolf.mood = ": the states of that value.
		if before[-1] == "=" and db.values.has(before[-2]) and db.values[before[-2]].get("kind", "") == "states":
			return _completions(head, word, db.values[before[-2]].states, "state", Callable(), false)
	if kind == "quest":
		return _completions(head, word, db.quests.keys(), "quest")
	if kind == "scene":
		return _completions(head, word, db.all_of("scene").keys(), "scene")
	if kind != "":
		return _completions(head, word, db.all_of(kind).keys(), kind, func(id: String) -> String:
			return db.typed_value(kind, id, "name"))
	if head.strip_edges() == "~" and word != "":
		return _completions(head, word, db.values.keys(), "value")
	return []


## The IDs that start with the word, then those that hold it (or whose name
## does); by ID, or in the order given (a quest's stages).
static func _completions(head: String, word: String, ids: Array, what: String, name_of: Callable = Callable(), sorted: bool = true) -> Array:
	var first: Array = []
	var rest: Array = []
	for id: String in ids:
		var name: String = str(name_of.call(id)) if name_of.is_valid() else ""
		var entry := {"text": head + id, "label": head + id, "note": name if name.to_lower() != id else "", "command": "", "tag": what}
		if id.begins_with(word):
			first.append(entry)
		elif word != "" and (word in id or word in name.to_lower()):
			rest.append(entry)
	if sorted:
		var by_text := func(a: Dictionary, b: Dictionary) -> bool: return str(a.text) < str(b.text)
		first.sort_custom(by_text)
		rest.sort_custom(by_text)
	return first + rest


# --- Running a line ---------------------------------------------------------------

## Runs a typed line. Returns {ok, message, said}: `said` holds what the game
## said while it ran (notices and text), for a window that covers the game.
static func run(game, typed: String) -> Dictionary:
	var line := typed.strip_edges()
	if line == "":
		return _result(false, "Nothing was typed.")
	if game.state.ending != "":
		return _result(false, "The game has ended.")
	var idle: bool = game.runner.status == "idle"
	var before: int = game.output.size()
	var command := command_named(game, line)
	if command != "":
		if not idle:
			return _result(false, "A command starts only while nothing else plays: finish what is on screen first.")
		var prog: Program = game.content.program("%s#play" % command, "command")
		if prog == null:
			return _result(false, "The command '%s' has nothing to play." % command)
		_note(game, command)
		game.runner.frames.append({"kind": "script", "pid": prog.id, "pc": 0})
		game.runner.run()
		if game.runner.status == "idle":
			game.runner.show_location()
		return _result(true, "Ran the command %s." % game.content.typed_value("command", command, "name", command), _said(game, before))
	if line.to_lower().begins_with("event "):
		var event := line.substr(6).strip_edges()
		if not game.content.has(event, "event"):
			return _result(false, "There is no event '%s'." % event)
		if not idle:
			return _result(false, "An event starts only while nothing else plays: finish what is on screen first.")
		_note(game, line)
		game.runner.start_event(event)
		return _result(true, "Played the event %s." % event, _said(game, before))
	var checked := compile(game.content, line)
	if checked.error != "":
		return _result(false, checked.error)
	var prog: Program = checked.program
	_note(game, line)
	if not idle:
		# While a scene, a choice or a fight is on screen only plain actions run.
		for ins: Dictionary in prog.code:
			if ins.op not in ["effect", "return"]:
				return _result(false, "While something plays only actions run (lines that start with ~): finish what is on screen first.")
		for ins: Dictionary in prog.code:
			if ins.op == "effect":
				game.apply(ins.effect)
		return _result(true, "Done.", _said(game, before))
	game.content.keep_program(LINE_ID, prog)
	game.runner.frames.append({"kind": "script", "pid": LINE_ID, "pc": 0})
	game.runner.run()
	if game.runner.status == "idle":
		game.runner.show_location()
	return _result(true, "Done.", _said(game, before))


## A typed script line compiled and checked like content: {program, error}.
static func compile(content: ContentDB, line: String) -> Dictionary:
	var parsed := FscParser.Result.new()
	if line.begins_with("fight ") and not line.ends_with(":"):
		line += ":"  # as content writes it; here the colon may be left out
	var lines: Array[FscParser.Line] = [FscParser.Line.new(1, 0, line)]
	var nodes: Array = FscParser.parse_script(lines, parsed)
	for d: Dictionary in parsed.diagnostics:
		if d.get("severity", "error") == "error":
			return {"program": null, "error": str(d.message)}
	if nodes.all(func(n: Dictionary) -> bool: return n.kind == "text"):
		return {"program": null, "error": "No command is called '%s'. An action starts with ~ (for example ~ give rope 2)." % line}
	var prog := Program.compile(LINE_ID, nodes, "the debug window")
	if not prog.errors.is_empty():
		return {"program": null, "error": str(prog.errors[0].message)}
	var problems: Array = Validator.check_program(content, prog)
	if not problems.is_empty():
		return {"program": null, "error": str(problems[0])}
	return {"program": prog, "error": ""}


static func _result(ok: bool, message: String, said: Array = []) -> Dictionary:
	return {"ok": ok, "message": message, "said": said}


## What was done here is among the player's last steps, so a bug report says
## that the game was changed by hand.
static func _note(game, what: String) -> void:
	game.feedback.note("debug: " + what)


## The notices and text the game put out since `from`, as plain lines.
static func _said(game, from: int) -> Array:
	var out: Array = []
	for e: Dictionary in game.output.slice(from):
		match e.type:
			"notice":
				out.append(str(e.text))
			"paragraph":
				out.append(TextTemplate.plain(e.spans))
			"title":
				out.append(str(e.text))
			"roll":
				out.append(str(e.get("text", "")))
	return out


# --- Values -----------------------------------------------------------------------

## The game's values whose path holds `search` (every word of it), by path:
## {path, kind (number, flag, text, states, time, list), value, shown, default,
## changed, states}. With `changed_only`, only those that differ from how they
## start. At most `limit`; `more` in the last entry's place says how many were left out.
static func values(game, search: String = "", changed_only: bool = false, limit: int = 200) -> Dictionary:
	var words: PackedStringArray = search.to_lower().split(" ", false)
	var paths: Array = game.content.values.keys()
	for id: String in game.content.all_of("event"):
		paths.append("event.%s.resolved" % id)
		paths.append("event.%s.active" % id)
	paths.sort()
	var rows: Array = []
	var matched := 0
	for path: String in paths:
		var fits := true
		for w: String in words:
			if w not in path:
				fits = false
				break
		if not fits:
			continue
		# A row is only worked out when it is shown, or to see whether it changed.
		if changed_only:
			var row := value_row(game, path)
			if not row.changed:
				continue
			matched += 1
			if rows.size() < limit:
				rows.append(row)
		else:
			matched += 1
			if rows.size() < limit:
				rows.append(value_row(game, path))
	return {"rows": rows, "matched": matched}


## One value as the window shows it.
static func value_row(game, path: String) -> Dictionary:
	if path.begins_with("event."):
		var id := path.trim_prefix("event.").get_slice(".", 0)
		var key := path.get_slice(".", path.count("."))
		var now: bool = game._event(id)[key]
		var start: bool = false if key == "resolved" else game.content.typed_value("event", id, "active", "yes") == "yes"
		return {"path": path, "kind": "flag", "value": now, "shown": "yes" if now else "no", "default": "yes" if start else "no",
			"changed": now != start, "states": []}
	var decl: Dictionary = game.content.values.get(path, {})
	var kind := str(decl.get("kind", "number"))
	var v: Variant = game.value(path)
	var shown := ""
	var start := ""
	var changed := false
	match kind:
		"time":
			shown = "never" if v == null else ("now" if int(v) == game.state.turn else "%d turns ago" % (game.state.turn - int(v)))
			start = "never"
			changed = v != null
		"flag":
			shown = "yes" if Condition._truthy(v) else "no"
			start = "yes" if Condition._truthy(decl.get("default", false)) else "no"
			changed = shown != start
		"list":
			shown = ", ".join((v as Array).map(func(x: Variant) -> String: return str(x))) if v is Array else str(v)
			var d: Variant = decl.get("default", [])
			start = ", ".join((d as Array).map(func(x: Variant) -> String: return str(x))) if d is Array else str(d)
			changed = shown != start
		_:
			shown = str(v) if v != null else ""
			start = str(decl.get("default", "")) if decl.get("default") != null else ""
			changed = shown != start
	return {"path": path, "kind": kind, "value": v, "shown": shown, "default": start, "changed": changed,
		"states": decl.get("states", [])}


## Sets a value from what was typed or picked: a whole number, yes or no, one
## of a value's states, any text; for a time `now`, `never` or how many turns
## ago. Returns {ok, message}.
static func set_value(game, path: String, typed: String) -> Dictionary:
	var text := typed.strip_edges()
	if path.begins_with("event."):
		var id := path.trim_prefix("event.").get_slice(".", 0)
		var key := path.get_slice(".", path.count("."))
		if not game.content.has(id, "event") or key not in ["resolved", "active"]:
			return _result(false, "There is no value '%s'." % path)
		if text.to_lower() not in ["yes", "no"]:
			return _result(false, "%s is yes or no." % path)
		game._event(id)[key] = text.to_lower() == "yes"
		_note(game, "%s = %s" % [path, text.to_lower()])
		return _result(true, "%s is %s." % [path, text.to_lower()])
	if not game.content.values.has(path):
		return _result(false, "There is no value '%s'." % path)
	var decl: Dictionary = game.content.values[path]
	match str(decl.get("kind", "number")):
		"number":
			if not text.is_valid_int():
				return _result(false, "%s takes a whole number." % path)
			game.set_value(path, int(text))
		"flag":
			if text.to_lower() not in ["yes", "no"]:
				return _result(false, "%s is yes or no." % path)
			game.set_value(path, text.to_lower() == "yes")
		"states":
			if text not in decl.get("states", []):
				return _result(false, "%s is one of: %s." % [path, ", ".join(decl.get("states", []))])
			game.set_value(path, text)
		"time":
			var low := text.to_lower()
			if low == "never":
				game.state.stamps.erase(path)
			elif low == "now":
				game.state.stamps[path] = game.state.turn
			elif low.trim_suffix(" turns ago").trim_suffix(" turn ago").is_valid_int():
				game.state.stamps[path] = game.state.turn - int(low.trim_suffix(" turns ago").trim_suffix(" turn ago"))
			else:
				return _result(false, "%s is a time: now, never, or how many turns ago (3)." % path)
		"list":
			return _result(false, "%s is a list; change it with an action (~ add 3 to %s)." % [path, path])
		_:
			game.set_value(path, text)
	_note(game, "%s = %s" % [path, text])
	return _result(true, "%s is %s." % [path, value_row(game, path).shown])
