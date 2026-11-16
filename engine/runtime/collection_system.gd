class_name CollectionSystem
extends RefCounted
## Collections: things the player owns that are not carried items, counted by
## name, such as samples of a creature's strain or recordings. Each entry is
## a creature's ID (`of: creature`, named by the creature) or a free text
## (`of: text`), with how many the player has.
##
##   == collection samples
##   name: Samples
##   of: creature                    (or text, the default)
##   title: Your samples:            (heading of the list)
##   empty: You have no samples.     (said when it is opened while empty)
##   label: [collection.name] x[collection.count]   (an entry's line; default its name)
##   leave: Done
##   gained: You bottle a sample of [collection.name].   (after `~ collect`, unless quietly)
##   lost: You lose [collection.amount] [collection.name] sample.  (after `~ discard`)
##   entry:                          (a menu shown for the entry the player picks)
##       * Drink it [then leave]
##           ~ infect collection.entry
##   options:                        (more options under the entries)
##       * Throw them all out [then leave]
##           ~ discard everything from samples
##
## A scene opens the list with `-> samples` or `play samples`; it shows the
## entries sorted by name, then the options, then Leave, and shows again after
## each choice until the player leaves (or the collection is emptied).
## Values: `collection.entry` (the entry's ID or text), `collection.name`,
## `collection.count` (how many now), `collection.amount` and `collection.had`
## (the last change and the count before it), `collection.id`; and for any
## collection `collection.<id>.<entry>`, `collection.<id>.entry` (the current
## entry's count in it), `collection.<id>.kinds`, `collection.<id>.total`.

const TEXTS := ["title", "empty", "label", "leave", "gained", "lost", "name"]
const CONTEXT := ["entry", "name", "count", "amount", "had", "id"]
const READINGS := ["entry", "kinds", "total"]


static func field(game, id: String, name: String, fallback: String = "") -> String:
	return game.content.typed_value("collection", id, name, fallback)


## Entry -> count of a collection.
static func contents(game, id: String) -> Dictionary:
	if not game.state.collections.has(id):
		game.state.collections[id] = {}
	return game.state.collections[id]


static func count(game, id: String, key: String) -> int:
	return int(game.state.collections.get(id, {}).get(key, 0))


## How an entry is named: a creature's name, or the text itself.
static func entry_name(game, id: String, key: String) -> String:
	if field(game, id, "of", "text") == "creature" and game.content.has(key, "creature"):
		return game.content.typed_value("creature", key, "name", key)
	return key


## `collection.*` values (see the header).
static func value(game, rest: String) -> Variant:
	if rest in CONTEXT:
		var v = game.state.values.get("collection." + rest)
		return v if v != null else (0 if rest in ["count", "amount", "had"] else "")
	var cid := rest.get_slice(".", 0)
	var key := rest.substr(cid.length() + 1)
	match key:
		"entry":
			return count(game, cid, str(game.state.values.get("collection.entry", "")))
		"kinds":
			return game.state.collections.get(cid, {}).size()
		"total":
			var n := 0
			for k in game.state.collections.get(cid, {}):
				n += int(game.state.collections[cid][k])
			return n
	return count(game, cid, key)


static func _context(game, id: String, key: String) -> void:
	game.state.values["collection.id"] = id
	game.state.values["collection.entry"] = key
	game.state.values["collection.name"] = entry_name(game, id, key)
	game.state.values["collection.count"] = count(game, id, key)


## Adds `n` of an entry (Infection Vials.i7x:14-36, VialGain).
static func gain(game, id: String, key: String, n: int, quiet: bool = false) -> void:
	if key == "" or n <= 0:
		return
	if field(game, id, "of", "text") == "creature" and not game.content.has(key, "creature"):
		game.warn("'%s' is not a creature to collect in %s." % [key, id])
		return
	var held := contents(game, id)
	var had := int(held.get(key, 0))
	held[key] = had + n
	_context(game, id, key)
	game.state.values["collection.amount"] = n
	game.state.values["collection.had"] = had
	if not quiet:
		_say(game, field(game, id, "gained"))


## Takes `n` of an entry away (all of it when n < 0), with the `lost` text
## (Infection Vials.i7x:38-80, VialLoss). Returns how many went.
static func lose(game, id: String, key: String, n: int, quiet: bool = false) -> int:
	var held := contents(game, id)
	var had := int(held.get(key, 0))
	if had <= 0:
		return 0
	var gone := had if n < 0 else mini(n, had)
	if gone <= 0:
		return 0
	held[key] = had - gone
	if int(held[key]) <= 0:
		held.erase(key)
	_context(game, id, key)
	game.state.values["collection.amount"] = gone
	game.state.values["collection.had"] = had
	if not quiet:
		_say(game, field(game, id, "lost"))
	return gone


## Empties a collection, silently (the original's "blank out the whole table").
static func clear(game, id: String) -> void:
	contents(game, id).clear()


static func _say(game, text: String) -> void:
	if text != "":
		game.emit({"type": "paragraph", "spans": game.render(TextTemplate.compile(text))})


## The key an effect names: {"text": ...} or {"path": ...} (a value holding it).
static func resolve_key(game, key: Dictionary) -> String:
	if key.has("path"):
		var v = game.value(key.path)
		return "" if v == null else str(v)
	return str(key.get("text", ""))


## Applies `~ collect ...` and `~ discard ...` (see Effect).
static func apply(game, e: Dictionary) -> void:
	var quiet: bool = e.get("quiet", false)
	if e.get("everything", false):
		clear(game, e.collection)
		return
	var key := resolve_key(game, e.key)
	var n := 1 if e.amount.is_empty() else Effect.resolve_amount(e.amount, game)
	if e.op == "collect":
		gain(game, e.collection, key, n, quiet)
	else:
		lose(game, e.collection, key, -1 if e.get("all", false) else n, quiet)


# --- The list, played by the scene runner --------------------------------------

## One step of an open collection: the entries, the options and Leave as a
## choice list. An empty collection says its `empty` text the first time and
## closes. Returns true when the runner waits for the player.
static func step(runner, f: Dictionary) -> bool:
	var game = runner.game
	var id: String = f.id
	var held := contents(game, id)
	if held.is_empty():
		runner.frames.erase(f)
		if not f.get("shown", false):
			_say(game, field(game, id, "empty"))
		return false
	f["shown"] = true
	var keys: Array = held.keys()
	keys.sort_custom(func(a, b): return entry_name(game, id, a).to_lower() < entry_name(game, id, b).to_lower())
	var shown: Array = []
	runner.pending = []
	var label := field(game, id, "label")
	for key: String in keys:
		_context(game, id, key)
		var text := entry_name(game, id, key) if label == "" else TextTemplate.plain(game.render(TextTemplate.compile(label)))
		shown.append({"text": text, "description": "", "enabled": true})
		runner.pending.append({"collection": "entry", "key": key, "enabled": true})
	var menu_id := id + ".options"
	if game.content.menus.has(menu_id):
		var options: Array = game.content.menus[menu_id].options
		for i in options.size():
			var o: Dictionary = options[i]
			var ok := true
			if o.condition != "":
				var c := Condition.compile(o.condition)
				ok = not c.has("error") and Condition.evaluate(c, game)
			if ok or o.always_shown:
				shown.append({"text": o.label, "description": o.description, "enabled": ok})
				runner.pending.append({"collection": "option", "index": i, "enabled": ok})
	shown.append({"text": field(game, id, "leave", "Leave"), "description": "", "enabled": true, "leave": true})
	runner.pending.append({"collection": "leave", "enabled": true})
	game.emit({"type": "choices", "title": TextTemplate.plain(game.render(TextTemplate.compile(field(game, id, "title")))),
		"options": shown, "collection": id})
	runner.status = "choice"
	return true


## The player's pick in an open collection's list.
static func choose(runner, f: Dictionary, p: Dictionary) -> void:
	var game = runner.game
	match str(p.collection):
		"leave":
			runner.frames.erase(f)
		"entry":
			_context(game, f.id, str(p.key))
			if game.content.menus.has(str(f.id) + ".entry"):
				runner.frames.append({"kind": "menu", "id": str(f.id) + ".entry", "then_leave": false, "fresh": true})
		"option":
			var o: Dictionary = game.content.menus[str(f.id) + ".options"].options[int(p.index)]
			if o.then_leave:
				runner.frames.erase(f)
			runner.frames.append({"kind": "script", "pid": "%s.options@%d" % [f.id, int(p.index)], "pc": 0})


# --- Validation ------------------------------------------------------------------

static func check(v) -> void:
	for id in v.db.all_of("collection"):
		var d: FscParser.Definition = v.db.get_def("collection", id)
		v._path = d.path
		if id in CONTEXT:
			v._err(d.line, "A collection can't be called '%s': collection.%s is the entry a scene is about." % [id, id])
		if v.db.typed_value("collection", id, "of", "text") not in ["creature", "text"]:
			v._err(d.fields["of"].line, "'of:' is creature (entries are creatures) or text.")
		for name: String in TEXTS:
			if d.fields.has(name):
				v._check_text_field(d.fields[name].value, d.fields[name].line, id)


## Checks `~ collect` and `~ discard` effects.
static func check_effect(v, e: Dictionary, line: int) -> void:
	if not v.db.has(e.collection, "collection"):
		v._err(line, "Collection '%s' does not exist.%s" % [e.collection, v._suggest(e.collection, v._ids("collection"))])
		return
	if e.get("everything", false):
		return
	if e.key.has("path"):
		v._check_path(e.key.path, line)
	elif v.db.typed_value("collection", e.collection, "of", "text") == "creature":
		v._need(str(e.key.text), "creature", line)
	if not e.amount.is_empty() and e.amount.has("value"):
		v._check_expr(e.amount.value, line)


## Checks a `collection.*` value path; returns false when it is not one.
static func check_path(v, parts: PackedStringArray, line: int) -> bool:
	if parts[0] != "collection" or parts.size() < 2:
		return false
	if parts.size() == 2:
		if parts[1] not in CONTEXT:
			if v.db.has(parts[1], "collection"):
				v._err(line, "Read an entry of collection %s as collection.%s.<entry>." % [parts[1], parts[1]])
			else:
				v._err(line, "'collection.%s' is not a collection value. Known: %s." % [parts[1], ", ".join(CONTEXT)])
		return true
	if not v.db.has(parts[1], "collection"):
		v._err(line, "Collection '%s' does not exist.%s" % [parts[1], v._suggest(parts[1], v._ids("collection"))])
	elif parts.size() == 3 and parts[2] not in READINGS and v.db.typed_value("collection", parts[1], "of", "text") == "creature":
		v._need(parts[2], "creature", line)
	return true
