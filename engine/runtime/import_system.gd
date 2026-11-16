class_name ImportSystem
extends RefCounted
## Brings a player's progress over from an Inform game's export files (read by
## OriginalExport): the rules for each file come from content.
##
##   == save_import possessions
##   name: Items                                    (shown in the report)
##   file: FSPossessionSave                         (the file, without .glkdata)
##   columns: Name, CarriedNumber, StoredNumber, EquippedStatus, CurseStatus
##   rows: items                                    (what a row is; the first column is its name)
##   map:
##       CarriedNumber: carried
##       StoredNumber: stored in storage_locker
##       EquippedStatus: worn
##       CurseStatus: skip
##
## A character row's column with no `map:` line and no `from:` goes to the
## character's own value of the same name in snake_case ("HP of Adam" to adam.hp).
## Values say where they come from with `from:` under their declaration:
## `from: AlexTalk` (a loose variable) or `from: Energy of Adam` (a column of a
## character's row), optionally `= 0, 1, 2` (the original's number for each
## state). Rows name things by the original's name: a definition's
## `original name:`, else its `name:`, else its ID in snake_case.
## Everything that is not imported is reported with the reason; entries that
## are 0, empty or no are counted. Hooks `on: after import` play afterwards.

## The row kinds, in the order they are applied.
const KINDS := ["places", "ground items", "events", "items", "characters", "traits", "player", "lists", "notes", "named values"]
## Types whose definitions a row can name, and that may carry `original name:`.
const NAMED_TYPES := ["character", "event", "location", "item", "creature", "feat", "quest", "filter", "form"]
const FIELD := "original name"
## The engine's own yes/no values (not declared by content): a number from the original becomes yes or no.
const ENGINE_FLAGS := ["virgin", "oral_virgin", "anal_virgin", "penile_virgin", "experienced", "sterile", "heat_paused"]
const MOMENT := "after import"
## Fixed target words per row kind (patterns such as `stored in X` are checked in target()).
const WORDS := {
	"characters": ["location", "skip"], "player": ["location", "skip"], "items": ["carried", "worn", "skip"],
	"ground items": [], "events": ["resolution", "skip"], "places": ["skip"], "traits": ["tamed", "in party", "skip"],
	"lists": ["feats", "quests open", "quests done", "creatures met", "filters banned", "filters warded", "skip"],
	"notes": ["day", "text", "skip"], "named values": ["skip", "clock"],
}
static var _path_re := RegEx.create_from_string("^[a-z0-9_]+(\\.[a-z0-9_]+)*$")
static var _stamps_re := RegEx.create_from_string("^(-?\\d+) counting (down|up)$")
static var _of_re := RegEx.create_from_string("(?i)^(.+?) of (.+)$")


## Whether `original name:` (or another import field) may be written on a definition of `type`.
static func allows_field(type: String, field: String) -> bool:
	return field == FIELD and type in NAMED_TYPES


# --- Reading the content's rules ----------------------------------------------

## The rules of one save_import definition, read into plain data.
static func spec(content: ContentDB, id: String) -> Dictionary:
	var d: FscParser.Definition = content.get_def("save_import", id)
	var s := {"id": id, "path": d.path, "line": d.line, "file": _field(d, "file"), "rows": _field(d, "rows"),
		"columns": content._list(d, "columns"), "map": {}, "player": {}, "player_row": _field(d, "player row"),
		"nowhere": content._list(d, "nowhere"), "ignore": content._list(d, "ignore"), "when_missing": content._list(d, "when missing"),
		"stamps": {}, "problems": [], "like": _field(d, "map like")}
	s["name"] = _field(d, "name") if d.fields.has("name") else str(s.file)
	var like := str(s.like)
	if like != "" and like != id and content.has(like, "save_import") and _field(content.get_def("save_import", like), "map like") == "":
		# `map like: characters`: the other file's lines, for an older layout of the same table;
		# lines of this one replace them, and lines for columns this file lacks are passed over.
		var other := spec(content, like)
		for which in ["map", "player"]:
			for key: String in other[which]:
				var t: Dictionary = other[which][key].duplicate()
				t["inherited"] = true
				s[which][key] = t
		if s.player_row == "":
			s.player_row = other.player_row
		if (s.nowhere as Array).is_empty():
			s.nowhere = other.nowhere
	for which in ["map", "player"]:
		if not d.fields.has(which):
			continue
		for l: FscParser.Line in d.fields[which].children:
			if l.is_blank():
				continue
			var at := l.text.rfind(":")
			if at < 0:
				s.problems.append([l.number, "A %s line is written '<source>: <target>', for example 'CarriedNumber: carried'." % which])
				continue
			var key := l.text.substr(0, at).strip_edges()
			var t := target(str(s.rows), l.text.substr(at + 1).strip_edges(), which == "player")
			t["line"] = l.number
			s[which][key.to_lower()] = t
			t["key"] = key
	if d.fields.has("turn stamps"):
		var m := _stamps_re.search(_field(d, "turn stamps"))
		if m == null:
			s.problems.append([d.fields["turn stamps"].line, "'turn stamps:' is written '<start> counting down' or '<start> counting up', for example '240 counting down'."])
		else:
			s.stamps = {"start": int(m.get_string(1)), "down": m.get_string(2) == "down"}
	return s


static func _field(d: FscParser.Definition, name: String) -> String:
	return str(d.fields[name].value).strip_edges() if d.fields.has(name) else ""


## A map line's target for a row kind: {"op", ...} or {"error": message}.
static func target(kind: String, text: String, player: bool = false) -> Dictionary:
	var t := text.strip_edges()
	var words: Array = WORDS.get(kind, [])
	if t in words:
		return {"op": t}
	match kind:
		"characters", "player":
			if t.begins_with("form of "):
				var part := t.substr(8).strip_edges()
				part = BodySystem.ALIASES.get(part, part)
				if part not in BodySystem.PARTS:
					return {"error": "'%s' is not a body part. Parts: %s." % [part, ", ".join(BodySystem.PARTS)]}
				return {"op": "form", "part": part}
			if _path_re.search(t) != null:
				if player or kind == "player":
					return {"op": "value", "path": t if t.begins_with("player.") else "player." + t}
				return {"op": "value", "name": t}
		"items":
			if t.begins_with("stored in "):
				return {"op": "stored", "storage": t.substr(10).strip_edges()}
		"events", "places":
			var m := RegEx.create_from_string("^(resolved|active|known) if (.+)$").search(t)
			if m != null and (m.get_string(1) == "known") == (kind == "places"):
				return {"op": m.get_string(1), "text": m.get_string(2).strip_edges()}
		"lists":
			if t.begins_with("list ") and _path_re.search(t.substr(5).strip_edges()) != null:
				return {"op": "list", "path": t.substr(5).strip_edges()}
			if t.begins_with("collection "):
				return {"op": "collection", "collection": t.substr(11).strip_edges()}
		"named values":
			if _path_re.search(t) != null and "." in t:
				return {"op": "value", "path": t}
	var allowed: Array = words.duplicate()
	match kind:
		"characters":
			allowed.append_array(["<value of the character>", "form of <part> (player row)"])
		"player":
			allowed.append_array(["<player value>", "form of <part>"])
		"items":
			allowed.append("stored in <storage>")
		"events":
			allowed.append_array(["resolved if <text>", "active if <text>"])
		"places":
			allowed.append("known if <text>")
		"lists":
			allowed.append_array(["list <value>", "collection <id>"])
		"named values":
			allowed.append("<owner.value>")
	return {"error": "'%s' is not something a row of %s can set. Use: %s." % [t, kind if kind != "" else "this file", ", ".join(allowed)]}


## The values whose `from:` names where they come from:
## {"plain": {name -> [entry]}, "column": {"column|row" -> [entry]}}; an entry is
## {"path", "numbers": [the original's number for each state] or [], "line", "file"}.
static func from_index(content: ContentDB) -> Dictionary:
	var out := {"plain": {}, "column": {}}
	for type: String in content.definitions:
		if type == "_extend" or not ContentDB.SCHEMA.get(type, {}).has("values"):
			continue
		for d: FscParser.Definition in content.definitions[type].values():
			if not d.fields.has("values") or d.id == "character":
				continue
			var lines: Array = d.fields["values"].children
			var top := ContentDB._min_indent(lines)
			var last := ""
			for l: FscParser.Line in lines:
				if l.is_blank():
					continue
				var text := l.text.strip_edges()
				if l.indent <= top:
					last = text.split(":", true, 1)[0].strip_edges() if ":" in text else ""
					continue
				if last == "" or not text.begins_with("from:"):
					continue
				var source := parse_from(text.substr(5))
				if source.is_empty():
					continue
				var entry := {"path": "%s.%s" % [d.id, last], "numbers": source.numbers, "line": l.number, "file": d.path}
				var bucket: Dictionary = out[source.kind]
				if not bucket.has(source.key):
					bucket[source.key] = []
				bucket[source.key].append(entry)
	return out


## A `from:` text as an import source: {"kind": "plain"|"column", "key", "numbers"},
## or {} when it is not one (free porting notes stay notes).
static func parse_from(text: String) -> Dictionary:
	var t := text.strip_edges()
	for cut in [" (", ";"]:
		var at := t.find(cut)
		if at >= 0:
			t = t.substr(0, at)
	var numbers: Array = []
	var eq := t.find("=")
	if eq >= 0:
		for n in t.substr(eq + 1).split(","):
			if not n.strip_edges().is_valid_int():
				return {}
			numbers.append(int(n.strip_edges()))
		t = t.substr(0, eq)
	t = t.strip_edges()
	if t == "" or "\"" in t or "," in t:
		return {}
	var m := _of_re.search(t)
	if m != null:
		return {"kind": "column", "key": "%s|%s" % [m.get_string(1).strip_edges().to_lower(), m.get_string(2).strip_edges().to_lower()], "numbers": numbers}
	if " is " in t or t.begins_with("the "):
		return {}
	return {"kind": "plain", "key": t.to_lower(), "numbers": numbers}


## Definitions by the original's name: type -> {"original": {name -> id}, "name": {name -> id}}.
static func name_index(content: ContentDB) -> Dictionary:
	var out := {}
	for type: String in NAMED_TYPES:
		var orig := {}
		var named := {}
		for id: String in content.all_of(type):
			var d: FscParser.Definition = content.get_def(type, id)
			if d.fields.has(FIELD):
				for n in str(d.fields[FIELD].value).split(","):
					if n.strip_edges() != "" and not orig.has(n.strip_edges().to_lower()):
						orig[n.strip_edges().to_lower()] = id
			if d.fields.has("name"):
				var n := str(d.fields["name"].value).strip_edges().to_lower()
				if n != "" and not named.has(n):
					named[n] = id
			if type == "filter" and d.fields.has("from"):
				# A filter's `from: FemaleList, "Females"`: the name the ban and ward lists use.
				var q := str(d.fields["from"].value)
				var a := q.find("\"")
				var b := q.rfind("\"")
				if a >= 0 and b > a and not orig.has(q.substr(a + 1, b - a - 1).to_lower()):
					orig[q.substr(a + 1, b - a - 1).to_lower()] = id
		out[type] = {"original": orig, "name": named}
	return out


## The ID of the definition of `type` the original calls `name`, or "".
static func find(content: ContentDB, index: Dictionary, type: String, name: String) -> String:
	var key := name.strip_edges().to_lower()
	if key == "":
		return ""
	var by: Dictionary = index.get(type, {})
	if by.get("original", {}).has(key):
		return str(by.original[key])
	if by.get("name", {}).has(key):
		return str(by.name[key])
	var id := snake(name)
	return id if content.has(id, type) else ""


## A form for a body part, from a creature's or a form's original name.
static func find_form(content: ContentDB, index: Dictionary, name: String) -> String:
	var creature := find(content, index, "creature", name)
	if creature != "":
		var f := content.typed_value("creature", creature, "form", creature)
		if content.has(f, "form"):
			return f
	return find(content, index, "form", name)


## "Connected Hellfire Corridor" -> "connected_hellfire_corridor" (IDs from the original's names).
static func snake(name: String) -> String:
	var out := ""
	var gap := false
	for c in name.strip_edges():
		var code := c.unicode_at(0)
		if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			if gap and out != "":
				out += "_"
			out += c.to_lower()
			gap = false
		else:
			gap = true
	return out if out != "" else "unnamed"


# --- Importing ------------------------------------------------------------------

## Reads the export files in `folder` and brings them into the game. Returns the report.
static func run(game: Game, folder: String) -> Dictionary:
	var report := apply(game, OriginalExport.read_folder(folder))
	report["folder"] = folder
	return report


## Which declared files a folder holds: {"found": [names], "total": declared files}.
static func recognised(content: ContentDB, folder: String) -> Dictionary:
	var files := OriginalExport.read_folder(folder)
	var found: Array = []
	var total := 0
	for id: String in content.all_of("save_import"):
		var d: FscParser.Definition = content.get_def("save_import", id)
		var file := _field(d, "file")
		if not d.fields.has("when missing"):
			total += 1  # older layouts read in place of a newer file are not counted
		if files.has(file.to_lower()):
			found.append(file)
	return {"found": found, "total": total, "files": files.size()}


## Brings parsed export files (OriginalExport.read_folder) into the game, then
## plays the `after import` hooks. Returns the report:
## {"files": [{"file", "name", "rows", "imported", "at_start", "unread_columns"}],
##  "not_imported": [{"file", "entry", "why"}], "unread": [{"file", "rows"}],
##  "missing": [file names], "problems": [{"file", "message"}], "imported": n, "at_start": n}
static func apply(game: Game, files: Dictionary) -> Dictionary:
	var run := _Run.new(game, files)
	run.go()
	game.run_hooks(MOMENT)
	return run.report


## The report as plain text (for the player's copy and for tests).
static func report_text(report: Dictionary) -> String:
	var out := PackedStringArray()
	if report.has("folder"):
		out.append("Imported from %s" % report.folder)
	out.append("%d entries imported; %d were 0, empty or no and needed nothing; %d were left out by the rules (skip); %d not imported." % [
		int(report.imported), int(report.at_start), int(report.get("skipped", 0)), report.not_imported.size()])
	out.append("")
	for f: Dictionary in report.files:
		var line := "%s (%s): %d rows, %d imported" % [f.name, f.file, int(f.rows), int(f.imported)]
		if not f.unread_columns.is_empty():
			line += "; columns not read: " + ", ".join(f.unread_columns)
		out.append(line)
	for f: String in report.missing:
		out.append("%s: not in the folder" % f)
	for u: Dictionary in report.unread:
		out.append("%s: %d rows, no pack reads this file" % [u.file, u.rows])
	for p: Dictionary in report.problems:
		out.append("%s: %s" % [p.file, p.message])
	if not report.not_imported.is_empty():
		out.append("")
		out.append("Not imported:")
		for n: Dictionary in report.not_imported:
			out.append("- %s: %s (%s)" % [n.file, n.entry, n.why])
	return "\n".join(out)


## One import: the indexes, the report and the steps per row kind.
class _Run:
	extends RefCounted
	var game: Game
	var content: ContentDB
	var files: Dictionary
	var names: Dictionary
	var froms: Dictionary
	var stamps: Dictionary = {}
	var ignore: Array = []
	var report := {"files": [], "not_imported": [], "unread": [], "missing": [], "problems": [], "imported": 0, "at_start": 0, "skipped": 0}
	var _file := {}  # the report line of the file being read
	var _spec := {}

	func _init(g: Game, f: Dictionary) -> void:
		game = g
		content = g.content
		files = f
		names = ImportSystem.name_index(content)
		froms = ImportSystem.from_index(content)

	func go() -> void:
		var specs: Array = []
		var read := {}
		for id: String in content.all_of("save_import"):
			var s := ImportSystem.spec(content, id)
			if not s.stamps.is_empty() and stamps.is_empty():
				stamps = s.stamps
			for i: String in s.ignore:
				ignore.append(i.to_lower())
			specs.append(s)
		for kind: String in ImportSystem.KINDS:
			for s: Dictionary in specs:
				if s.rows != kind:
					continue
				var key := str(s.file).to_lower()
				read[key] = true
				if (s.when_missing as Array).any(func(w): return files.has(str(w).to_lower())):
					continue
				if not files.has(key):
					if (s.when_missing as Array).is_empty():
						report.missing.append(s.file)  # an older layout's absence is the usual case
					continue
				_read_file(s, files[key])
		var keys := files.keys()
		keys.sort()
		for key: String in keys:
			if not read.has(key):
				report.unread.append({"file": files[key].name, "rows": files[key].rows.size()})

	func _read_file(s: Dictionary, f: Dictionary) -> void:
		_spec = s
		_file = {"file": s.file, "name": s.name, "rows": f.rows.size(), "imported": 0, "at_start": 0, "unread_columns": []}
		report.files.append(_file)
		for p: String in f.problems:
			report.problems.append({"file": s.file, "message": p})
		var cols: Array = s.columns
		for row: Array in f.rows:
			if row.size() != cols.size():
				report.problems.append({"file": s.file, "message": "Rows have %d cells, but the import names %d columns; the file is not read." % [row.size(), cols.size()]})
				return
		if s.rows not in ["named values", "lists", "traits", "ground items", "notes"]:
			for j in range(0 if s.rows == "player" else 1, cols.size()):
				var used: bool = s.map.has(str(cols[j]).to_lower()) or s.player.has(str(cols[j]).to_lower())
				if not used and s.rows != "characters":
					_file.unread_columns.append(cols[j])
		call("_" + str(s.rows).replace(" ", "_"), f.rows)

	# --- Report helpers ---

	func _miss(entry: String, why: String) -> void:
		report.not_imported.append({"file": _spec.file, "name": _spec.name, "entry": entry, "why": why})

	func _done(n: int = 1) -> void:
		_file.imported += n
		report.imported += n

	func _at_start(n: int = 1) -> void:
		_file.at_start += n
		report.at_start += n

	## A cell the rules leave out on purpose (`skip`, or a value the port does not keep there).
	func _skip(raw: Variant) -> void:
		if _empty(raw):
			_at_start()
		else:
			report.skipped += 1

	static func _empty(v: Variant) -> bool:
		return v == null or (v is int and v == 0) or (v is float and v == 0.0) or (v is String and (v == "" or v == "0"))

	func _row_empty(row: Array) -> bool:
		for j in range(1, row.size()):
			if not _empty(row[j]):
				return false
		return true

	func _col(row: Array, name: String) -> Variant:
		var i := (_spec.columns as Array).map(func(c): return str(c).to_lower()).find(name.to_lower())
		return row[i] if i >= 0 else null

	func _show(v: Variant) -> String:
		if v is String:
			return "\"%s\"" % (v if v.length() <= 60 else v.left(57) + "...")
		return str(v)

	# --- Values and conversions ---

	## Sets a value from an export cell; "" when done, else why not.
	func _assign(path: String, raw: Variant, numbers: Array = [], source: String = "") -> String:
		var decl: Dictionary = content.values.get(path, {})
		var kind := str(decl.get("kind", ""))
		var v: Variant = raw
		match kind:
			"number":
				if raw is String and not raw.is_valid_int():
					return "%s is a number, the original's is the text %s" % [path, _show(raw)]
				v = int(raw)
			"flag":
				if raw is String:
					return "%s is a yes/no flag, the original's is the text %s" % [path, _show(raw)]
				v = int(raw) != 0
			"text":
				v = str(raw)
			"states":
				var states: Array = decl.get("states", [])
				if not numbers.is_empty():
					if raw is String or int(raw) not in numbers:
						return "%s has no state for %s = %s (from: lists %s)" % [path, source, _show(raw), ", ".join(numbers.map(func(n): return str(n)))]
					var at := numbers.find(int(raw))
					if at >= states.size():
						return "from: of %s lists more numbers than it has states" % path
					v = states[at]
				elif raw is String and raw == "":
					v = states[0]  # an empty text: nothing chosen yet, the starting state
				elif raw is String and ImportSystem.snake(raw) in states:
					v = ImportSystem.snake(raw)
				elif raw is String and raw in states:
					v = raw
				else:
					return "%s is a list of states; its from: needs the original's number for each (from: %s = ...)" % [path, source]
			"time":
				if raw is String or stamps.is_empty():
					return "%s is a time; the import needs 'turn stamps:' to convert the original's turn numbers" % path
				if int(raw) == 0:
					game.state.stamps.erase(path)  # 0 is the original's "never" for its turn stamps
					return ""
				var turn: int = int(stamps.start) - int(raw) if stamps.down else int(raw) - int(stamps.start)
				game.state.stamps[path] = turn
				return ""
			"list":
				v = raw if raw is Array else [raw]
			"":
				if not _known_path(path):
					return "%s is not a value of the loaded content" % path
				if raw is float:
					v = int(raw)
				if path.get_slice(".", path.get_slice_count(".") - 1) in ENGINE_FLAGS and raw is int:
					v = raw != 0  # the engine's own yes/no values (player.virgin ...)
		game.set_value(path, v)
		return ""

	func _known_path(path: String) -> bool:
		if content.values.has(path):
			return true
		var parts := path.split(".")
		if parts[0] == "player":
			return parts.size() >= 2 and (parts[1] in Validator.PLAYER_VALUES or Game.PLAYER_DEFAULTS.has(path.substr(7)))
		for m in content.all_of("meter"):
			if content.typed_value("meter", m, "value") == path:
				return true
		return false

	# --- Row kinds ---

	func _named_values(rows: Array) -> void:
		var order: Array = []
		var groups := {}
		for row: Array in rows:
			var key := str(row[0]).to_lower()
			if not groups.has(key):
				groups[key] = {"name": str(row[0]), "values": []}
				order.append(key)
			if row.size() > 1 and row[1] != null:
				groups[key].values.append(row[1])
		for key: String in order:
			var g: Dictionary = groups[key]
			var targets: Array = []
			for e: Dictionary in froms.plain.get(key, []):
				targets.append(e)
			var t: Dictionary = _spec.map.get(key, {})
			if t.get("op", "") == "skip":
				for v in g.values:
					_skip(v)
				continue
			if t.get("op", "") == "clock":
				# The original's own turn counter: the game's clock goes on from it, so turn stamps keep their age.
				if stamps.is_empty() or g.values.is_empty() or g.values[0] is String:
					_miss("%s = %s" % [g.name, ", ".join(g.values.map(func(v): return _show(v)))], "the clock needs 'turn stamps:'")
				else:
					game.state.turn = int(stamps.start) - int(g.values[0]) if stamps.down else int(g.values[0]) - int(stamps.start)
					_done()
				continue
			if t.get("op", "") == "value":
				targets.append({"path": t.path, "numbers": []})
			var values: Array = g.values
			if targets.is_empty():
				if values.all(func(v): return _empty(v)):
					_at_start()
				else:
					_miss(g.name + " = " + ", ".join(values.map(func(v): return _show(v))), "nothing in the loaded content keeps it")
				continue
			for e: Dictionary in targets:
				var path: String = e.path
				var is_list := str(content.values.get(path, {}).get("kind", "")) == "list"
				if values.is_empty() and not is_list:
					continue
				var why := _assign(path, values.duplicate() if is_list else values[0], e.numbers, g.name)
				if why == "":
					_done()
				else:
					_miss("%s = %s" % [g.name, ", ".join(values.map(func(v): return _show(v)))], why)

	func _characters(rows: Array) -> void:
		var cols: Array = _spec.columns
		var player_row := str(_spec.player_row).to_lower()
		for row: Array in rows:
			var key := str(row[0])
			if key.to_lower() == player_row and player_row != "":
				_apply_columns(row, _spec.player, "player", key)
				continue
			var id := ImportSystem.find(content, names, "character", key)
			var used_any := false
			for j in range(1, cols.size()):
				var col := str(cols[j])
				var raw: Variant = row[j]
				if raw == null:
					continue
				var used := false
				for e: Dictionary in froms.column.get("%s|%s" % [col.to_lower(), key.to_lower()], []):
					used = true
					var why := _assign(e.path, raw, e.numbers, "%s of %s" % [col, key])
					if why == "":
						_done()
					else:
						_miss("%s of %s = %s" % [col, key, _show(raw)], why)
				var t: Dictionary = _spec.map.get(col.to_lower(), {})
				if id != "" and not t.is_empty():
					used = true
					match str(t.op):
						"skip":
							if e_none(col, key):
								_skip(raw)
						"location":
							_move(id, key, str(raw))
						"value":
							var path := "%s.%s" % [id, t.name]
							if content.values.has(path):
								var why := _assign(path, raw, [], "%s of %s" % [col, key])
								if why == "":
									_done()
								else:
									_miss("%s of %s = %s" % [col, key, _show(raw)], why)
							elif e_none(col, key):
								_skip(raw)  # the port keeps no such value for this character
				var own := "%s.%s" % [id, ImportSystem.snake(col)]
				if not used and id != "" and content.values.has(own):
					# A column with no line of its own goes to the character's value of the
					# same name ("HP of Adam" to adam.hp), as the converter names them.
					used = true
					var why := _assign(own, raw, [], "%s of %s" % [col, key])
					if why == "":
						_done()
					else:
						_miss("%s of %s = %s" % [col, key, _show(raw)], why)
				used_any = used_any or used
				if not used and id != "" and not _empty(raw):
					_miss("%s of %s = %s" % [col, key, _show(raw)], "nothing in the loaded content keeps it")
			if id == "" and not used_any:
				if _row_empty(row):
					_at_start()
				else:
					_miss(key, "no character called %s in the loaded content" % key)

	## No value's `from:` names this column of this row (so a skipped cell really is left out).
	func e_none(col: String, key: String) -> bool:
		return not froms.column.has("%s|%s" % [col.to_lower(), key.to_lower()])

	func _move(id: String, who: String, place: String) -> void:
		var to := "nowhere" if place.to_lower() in (_spec.nowhere as Array).map(func(n): return str(n).to_lower()) else ImportSystem.find(content, names, "location", place)
		if to == "":
			_miss("%s at %s" % [who, place], "no place called %s in the loaded content" % place)
			return
		if id == "player":
			game.state.location = to
			game.state.known[to] = true
			game.state.visited[to] = true
		elif game.where(id) != to:
			game.state.char_location[id] = to
		_done()

	## The player's columns (`player:` of a characters file, or a player file's `map:`).
	func _apply_columns(row: Array, map: Dictionary, who: String, key: String) -> void:
		var cols: Array = _spec.columns
		for j in range(0 if _spec.rows == "player" else 1, cols.size()):
			var col := str(cols[j])
			var raw: Variant = row[j]
			if raw == null:
				continue
			var t: Dictionary = map.get(col.to_lower(), {})
			match str(t.get("op", "")):
				"skip":
					_skip(raw)
				"location":
					_move("player", key, str(raw))
				"value":
					var why := _assign(str(t.path), raw, [], col)
					if why == "":
						_done()
					else:
						_miss("%s = %s" % [col, _show(raw)], why)
				"form":
					if _empty(raw):
						_at_start()
						continue
					var form := ImportSystem.find_form(content, names, str(raw))
					if form == "":
						_miss("%s = %s" % [col, _show(raw)], "no creature or form called %s in the loaded content" % raw)
					else:
						game.set_value("player.body.%s" % t.part, form)
						_done()
				_:
					if who == "player" and _spec.rows == "characters" and not _empty(raw):
						_miss("%s of %s = %s" % [col, key, _show(raw)], "nothing in the loaded content keeps it")

	func _player(rows: Array) -> void:
		if rows.is_empty():
			return
		_apply_columns(rows[0], _spec.map, "player", "player")

	func _items(rows: Array) -> void:
		game.state.inventory.clear()
		game.state.equipped.clear()
		game.state.wielded = ""
		for t: Dictionary in _spec.map.values():
			if t.op == "stored":
				game.state.storage.erase(t.storage)
		for row: Array in rows:
			var key := str(row[0])
			var id := ImportSystem.find(content, names, "item", key)
			if id == "":
				if _row_empty(row):
					_at_start()
				else:
					_miss(key, "no item called %s in the loaded content" % key)
				continue
			var worn := false
			for t: Dictionary in _spec.map.values():
				var raw: Variant = _col(row, t.key)
				if raw == null:
					continue
				match str(t.op):
					"carried":
						ItemSystem.gain(game, id, int(raw))
					"stored":
						if int(raw) > 0:
							var held: Dictionary = game.state.storage.get(t.storage, {})
							held[id] = int(held.get(id, 0)) + int(raw)
							game.state.storage[t.storage] = held
					"worn":
						worn = int(raw) != 0
					"skip":
						_skip(raw)
			if worn and ItemSystem.count(game, id) > 0:
				if ItemSystem.is_weapon(game, id):
					game.state.wielded = id
				elif ItemSystem.is_wearable(game, id) and id not in game.state.equipped:
					game.state.equipped.append(id)
			_done()

	func _ground_items(rows: Array) -> void:
		for loc: String in content.all_of("location"):
			if game.state.ground.has(loc) or not content.list_field(loc, "items").is_empty():
				game.state.ground[loc] = {}
		for row: Array in rows:
			if row.size() < 2:
				continue
			var loc := ImportSystem.find(content, names, "location", str(row[0]))
			var item := ImportSystem.find(content, names, "item", str(row[1]))
			if loc == "" or item == "":
				_miss("%s at %s" % [row[1], row[0]], ("no place called %s" % row[0]) if loc == "" else ("no item called %s" % row[1]))
				continue
			var here: Dictionary = game.state.ground.get(loc, {})
			here[item] = int(here.get(item, 0)) + 1
			game.state.ground[loc] = here
			_done()

	func _events(rows: Array) -> void:
		for row: Array in rows:
			var key := str(row[0])
			var id := ImportSystem.find(content, names, "event", key)
			if id == "":
				_miss(key, "no event called %s in the loaded content" % key)
				continue
			var ev: Dictionary = game._event(id)
			for t: Dictionary in _spec.map.values():
				var raw: Variant = _col(row, t.key)
				if raw == null:
					continue
				match str(t.op):
					"resolved":
						ev.resolved = str(raw) == str(t.text)
					"active":
						ev.active = str(raw) == str(t.text)
					"skip":
						_skip(raw)
					"resolution":
						game.set_value("%s.resolution" % id, int(raw))
						var numbers: Dictionary = content.outcome_numbers.get(id, {})
						for outcome: String in numbers:
							if int(numbers[outcome]) == int(raw):
								game.set_value("%s.outcome" % id, outcome)
			_done()

	func _places(rows: Array) -> void:
		for row: Array in rows:
			var key := str(row[0])
			var id := ImportSystem.find(content, names, "location", key)
			if id == "":
				_miss(key, "no place called %s in the loaded content" % key)
				continue
			for t: Dictionary in _spec.map.values():
				var raw: Variant = _col(row, t.key)
				if raw != null and t.op == "skip":
					_skip(raw)
				elif raw != null and t.op == "known":
					if str(raw) == str(t.text):
						game.state.known[id] = true
					else:
						game.state.known.erase(id)
			_done()

	func _traits(rows: Array) -> void:
		var party: bool = _spec.map.values().any(func(t): return t.op == "in party")
		game.state.traits.clear()
		if party:
			game.state.companions.clear()
		for row: Array in rows:
			if row.size() < 2 or row[1] == null:
				continue
			var owner := str(row[0])
			var text := str(row[1])
			var id := ImportSystem.find(content, names, "character", owner)
			if id == "":
				_miss("%s of %s" % [text, owner], "no character called %s in the loaded content" % owner)
				continue
			var op := str(_spec.map.get(text.to_lower(), {}).get("op", ""))
			if op == "skip":
				_skip(text)
				continue
			if op in ["tamed", "in party"]:
				# A companion is tamed or follows the player; for anyone else "tamed" stays a trait, as in the original.
				if CompanionSystem.is_companion(game, id):
					if op == "tamed":
						CompanionSystem.tame(game, id, true)
					else:
						CompanionSystem.join(game, id)
					_done()
					continue
				if op == "in party":
					_miss("%s of %s" % [text, owner], "%s is not a companion in the loaded content" % id)
					continue
			var list: Array = game.state.traits.get(id, [])
			var trait_id := ImportSystem.snake(text)
			if trait_id not in list:
				list.append(trait_id)
			game.state.traits[id] = list
			_done()

	func _lists(rows: Array) -> void:
		var cleared := {}
		for row: Array in rows:
			if row.size() < 2 or row[1] == null:
				continue
			var list_name := str(row[0])
			var entry := str(row[1])
			if entry.to_lower() in ignore:
				continue
			var t: Dictionary = _spec.map.get(list_name.to_lower(), {})
			var op := str(t.get("op", ""))
			if op == "":
				_miss("%s: %s" % [list_name, entry], "nothing in the loaded content keeps the list %s" % list_name)
				continue
			if op == "skip":
				_skip(entry)
				continue
			var mark := op + str(t.get("path", "")) + str(t.get("collection", ""))
			if not cleared.has(mark):
				cleared[mark] = true
				_clear(t)
			var why := _list_entry(t, entry)
			if why == "":
				_done()
			else:
				_miss("%s: %s" % [list_name, entry], why)

	func _clear(t: Dictionary) -> void:
		match str(t.op):
			"feats":
				game.state.feats.clear()
			"creatures met":
				game.state.encountered.clear()
			"list":
				game.set_value(str(t.path), [])
			"collection":
				if content.has(str(t.collection), "collection"):
					CollectionSystem.clear(game, str(t.collection))

	func _list_entry(t: Dictionary, entry: String) -> String:
		match str(t.op):
			"feats":
				var id := ImportSystem.find(content, names, "feat", entry)
				if id == "":
					return "no feat called %s in the loaded content" % entry
				if id not in game.state.feats:
					game.state.feats.append(id)
			"quests open", "quests done":
				var id := ImportSystem.find(content, names, "quest", entry)
				if id == "":
					return "no quest called %s in the loaded content" % entry
				var stages: Array = content.quests.get(id, {}).get("stages", [])
				if stages.size() < 2:
					return "quest %s has no stage after its start" % id
				var path := "quest.%s" % id
				if t.op == "quests done":
					var done := content.typed_value("quest", id, "done at", str(stages[-1]))
					game.set_value(path, done)
				elif stages.find(str(game.value(path))) <= 0:
					game.set_value(path, stages[1])
			"creatures met":
				var id := ImportSystem.find(content, names, "creature", entry)
				if id == "":
					return "no creature called %s in the loaded content" % entry
				if id not in game.state.encountered:
					game.state.encountered.append(id)
			"filters banned", "filters warded":
				var id := ImportSystem.find(content, names, "filter", entry)
				if id == "":
					return "no content filter called %s in the loaded content" % entry
				var which := "banned" if t.op == "filters banned" else "warded"
				if game.filter_state(id) == "normal":
					game.settings[which].append(id)
			"list":
				var path := str(t.path)
				var list: Array = Array(game.value(path) if game.value(path) is Array else []).duplicate()
				var v: Variant = int(entry) if entry.is_valid_int() else entry
				if v not in list:
					list.append(v)
				game.set_value(path, list)
			"collection":
				var c := str(t.collection)
				if not content.has(c, "collection"):
					return "no collection %s in the loaded content" % c
				var key := entry
				if CollectionSystem.field(game, c, "of", "text") == "creature":
					key = ImportSystem.find(content, names, "creature", entry)
					if key == "":
						return "no creature called %s in the loaded content" % entry
				CollectionSystem.gain(game, c, key, 1, true)
		return ""

	func _notes(rows: Array) -> void:
		var list: Array = []
		var day_col := ""
		var text_col := ""
		for t: Dictionary in _spec.map.values():
			if t.op == "day":
				day_col = t.key
			elif t.op == "text":
				text_col = t.key
		for row: Array in rows:
			var text: Variant = _col(row, text_col) if text_col != "" else null
			if text == null or str(text) == "":
				continue
			var day: Variant = _col(row, day_col) if day_col != "" else null
			list.append({"turn": (maxi(int(day), 1) - 1) * 8 if day != null else game.state.turn, "text": str(text)})
			_done()
		game.state.values[NotesSystem.LIST] = list


## Validator checks for save_import definitions and `original name:` fields.
static func check(v) -> void:
	var files := {}
	var stamped := ""
	for id: String in v.db.all_of("save_import"):
		var d: FscParser.Definition = v.db.get_def("save_import", id)
		v._path = d.path
		var s := spec(v.db, id)
		for p: Array in s.problems:
			v._err(int(p[0]), str(p[1]))
		for field in ["file", "columns", "rows"]:
			if not d.fields.has(field):
				v._err(d.line, "save_import %s needs '%s:'." % [id, field])
		if not d.fields.has("rows"):
			continue
		if s.rows not in KINDS:
			v._err(d.fields["rows"].line, "'rows: %s' is not a kind of row. Kinds: %s." % [s.rows, ", ".join(KINDS)])
			continue
		var key := str(s.file).to_lower()
		if files.has(key):
			v._err(d.fields["file"].line, "File %s is already read by save_import %s; one save_import per file." % [s.file, files[key]])
		files[key] = id
		if not s.stamps.is_empty():
			if stamped != "":
				v._err(d.fields["turn stamps"].line, "'turn stamps:' is already given by save_import %s; give it once." % stamped)
			stamped = id
		var cols: Array = (s.columns as Array).map(func(c): return str(c).to_lower())
		var two := ["ground items", "traits", "lists", "named values"]
		if cols.size() < (2 if s.rows in two else 1):
			v._err(d.fields["columns"].line if d.fields.has("columns") else d.line, "Rows of %s need at least %d columns (the first is the row's name)." % [s.rows, 2 if s.rows in two else 1])
		if s.player_row != "" and s.rows != "characters":
			v._err(d.fields["player row"].line, "'player row:' is for rows: characters.")
		if d.fields.has("player") and s.player_row == "":
			v._err(d.fields["player"].line, "'player:' needs 'player row:' (the name of the row that is the player).")
		for which in ["map", "player"]:
			for t: Dictionary in s[which].values():
				if t.has("error"):
					v._err(int(t.line), str(t.error))
					continue
				if s.rows not in ["lists", "traits", "named values"] and str(t.key).to_lower() not in cols and not t.get("inherited", false):
					v._err(int(t.line), "'%s' is not one of the columns: %s." % [t.key, ", ".join(s.columns)])
				if s.rows != "characters" or which == "player":
					if t.op == "value" and t.has("path"):
						v._check_path(str(t.path), int(t.line))
				elif t.op == "form":
					v._err(int(t.line), "'form of' is for the player's columns (under 'player:').")
				if t.op == "stored" and not v.db.has(str(t.storage), "storage"):
					v._err(int(t.line), "Storage '%s' does not exist.%s" % [t.storage, v._suggest(str(t.storage), v._ids("storage"))])
				if t.op == "collection" and not v.db.has(str(t.collection), "collection"):
					v._err(int(t.line), "Collection '%s' does not exist.%s" % [t.collection, v._suggest(str(t.collection), v._ids("collection"))])
				if t.op == "list":
					v._check_path(str(t.path), int(t.line))
					if str(v.db.values.get(str(t.path), {}).get("kind", "")) != "list":
						v._err(int(t.line), "%s is not a list value." % t.path)
	for id: String in v.db.all_of("save_import"):
		var d: FscParser.Definition = v.db.get_def("save_import", id)
		v._path = d.path
		for when: String in v.db._list(d, "when missing"):
			if not files.has(when.to_lower()):
				v._err(d.fields["when missing"].line, "No save_import reads %s, so 'when missing: %s' never changes anything." % [when, when])
		var like := _field(d, "map like")
		if like == "":
			continue
		if not v.db.has(like, "save_import"):
			v._err(d.fields["map like"].line, "save_import '%s' does not exist.%s" % [like, v._suggest(like, v._ids("save_import"))])
		elif like == id or _field(v.db.get_def("save_import", like), "map like") != "":
			v._err(d.fields["map like"].line, "'map like:' names a save_import with its own lines, not one that borrows them.")
		elif _field(v.db.get_def("save_import", like), "rows") != _field(d, "rows"):
			v._err(d.fields["map like"].line, "save_import %s reads other rows (%s)." % [like, _field(v.db.get_def("save_import", like), "rows")])
