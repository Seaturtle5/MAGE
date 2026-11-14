class_name ContentDB
extends RefCounted
## All loaded content: definitions by type and ID, declared values, menus
## and compiled programs. Loads packs from folders, applies `extend`
## blocks and reports problems with file and line.

## Field kinds: text (one line or a long text with markup), script (a scene
## inside a field), fields (nested fields), list (comma separated), menu
## (options), values (value declarations), stages (quest stages), meta.
const SCHEMA := {
	"rest_rules": {"condition": "text", "duration": "text", "fresh below": "text", "fresh fatigue": "text",
		"exhausted recovery": "text", "hammock fresh fatigue": "text", "hammock recovery": "text",
		"collapse at": "text", "collapse fatigue": "text", "collapse turns": "text",
		"statuses": "fields", "warnings": "fields", "refreshed": "script", "collapse": "script", "wake": "script", "source": "meta"},
	"pack": {"name": "text", "version": "text", "authors": "text", "requires": "list", "license": "text",
		"title": "text", "subtitle": "text", "logo": "text", "background": "text", "about": "text",
		"menu icons": "list"},
	"survival_rules": {"hunger warnings": "fields", "thirst warnings": "fields", "starving hint at": "text",
		"starving hint": "text", "hunger death": "text", "thirst death": "text", "morale normalized": "text",
		"humanity loss": "text", "journal hint below": "text", "journal hint": "text", "humanity descriptions": "fields",
		"lust descriptions": "fields", "humanity ending": "text", "rescue ending": "text", "anticipation within": "text",
		"rescue anticipation": "text", "source": "meta"},
	"scenario": {"name": "text", "description": "text", "start": "text", "intro": "script", "setup": "script", "source": "meta"},
	"feat": {"name": "text", "description": "text", "exploration bonus": "text", "encounter bonus": "text",
		"scavenge bonus": "text", "loot bonus": "text", "body text": "text", "group": "text", "available when": "text",
		"gained": "script", "source": "meta"},
	"level_rules": {"xp needed": "text", "xp needed modifiers": "fields", "levels when": "text", "level up": "script",
		"source": "meta"},
	"interest": {"name": "text", "description": "text", "default": "text", "group": "text", "source": "meta"},
	"combat_rules": {"unarmed attack": "text", "unarmed damage": "text", "player hits": "text", "flee": "text",
		"flee fails": "text", "won": "script", "lost": "script", "source": "meta"},
	"scavenge_rules": {"generic": "text", "generic chance": "text", "target": "text", "start": "text", "found": "text",
		"failure": "text", "only at": "text", "source": "meta"},
	"creature": {"name": "text", "vore": "script", "vore when": "text", "hard vore": "script", "hard vore when": "text", "unbirth": "script", "unbirth when": "text", "species": "text", "image": "text", "found in": "list", "active": "text",
		"level": "text", "hp": "text", "damage": "text", "stats": "text", "libido": "text", "form": "text",
		"gender": "text", "special": "text", "seduction immune": "text", "tags": "list", "source": "meta",
		"title": "text", "personal name": "text", "unique": "text", "group": "text", "infectious": "text",
		"cross infection": "text", "research bypass": "text", "magic": "text", "loot": "text",
		"hit bonus": "text", "dodge bonus": "text", "variants": "fields", "pick variant": "text",
		"encounter": "script", "attack": "script", "grapple": "script", "escape": "script", "struggle": "script", "defeated": "script", "victory": "script",
		"strike with": "text", "attacks": "menu", "each round": "script", "before attack": "script", "after attack": "script",
		"miss": "script", "hump": "script", "pounce": "script", "breath warning": "script", "breath direct": "script",
		"breath partial": "script", "breath miss": "script"},
	"form": {"name": "text", "sex": "text", "scale": "text", "body type": "text", "descriptor": "text",
		"stats": "text", "libido": "text", "tags": "list", "source": "meta", "head": "fields", "torso": "fields",
		"milk item": "text", "cum item": "text", "each turn": "script", "sex by preference": "text", "heat": "text", "offspring gender": "text",
		"back": "fields", "arms": "fields", "legs": "fields", "ass": "fields", "tail": "fields", "cock": "fields",
		"cunt": "fields", "skin": "fields", "breasts": "fields", "balls": "fields"},
	"character": {"name": "text", "pronouns": "text", "image": "text", "scent": "script", "description": "script",
		"lives at": "text", "presence": "script", "body": "fields", "stats": "fields", "relationship": "fields",
		"values": "values", "talk": "script", "sex": "script", "impregnation": "script", "actions": "menu", "companion": "fields", "summon": "script", "dismiss": "script",
		"companion attack": "script", "tags": "list", "source": "meta"},
	"menu": {"title": "text", "leave": "text", "leave text": "script", "pause after each": "text", "sort": "text",
		"intro": "script", "source": "meta"},
	"scene": {"source": "meta", "tags": "list"},
	"text": {},
	"quest": {"name": "text", "region": "text", "stages": "stages", "done at": "text", "source": "meta"},
	"event": {"name": "text", "found by": "text", "repeat": "text", "outcomes": "list", "values": "values", "tags": "list",
		"source": "meta", "play": "script", "level": "text", "min score": "text", "requires": "text", "chance": "text",
		"priority": "text", "cooldown": "text", "active": "text", "blocks": "text", "replaces trip": "text"},
	"location": {"name": "text", "region": "text", "zone": "text", "map": "text", "flags": "list", "image": "text",
		"items": "list", "source": "meta", "exits": "fields", "description": "script", "scent": "script", "observe": "menu",
		"actions": "menu", "rest": "text", "rest text": "text", "microwave": "text", "instead of": "fields", "presence": "script", "enter": "script"},
	"door": {"name": "text", "description": "script", "shown in room": "script", "locked": "text", "locked text": "script",
		"leads to zone": "text", "source": "meta"},
	"region": {"name": "text", "travel order": "text", "map grid": "text", "image": "text", "source": "meta"},
	"zone": {"name": "text", "ambient": "script", "source": "meta"},
	"item": {"name": "text", "icon": "text", "plural": "text", "description": "script", "image": "text", "scent": "script", "weight": "text", "category": "text",
		"use": "script", "consumed": "text", "trades for": "text", "purified": "text", "infectious": "text", "aliases": "list",
		"rest": "text", "carried rest text": "text", "ground rest text": "text", "keep": "text", "use action": "text",
		"in combat": "text", "purify refusal": "text",
		"equipment": "fields", "weapon": "fields", "on wear": "script", "on remove": "script", "worn each turn": "script",
		"tags": "list", "source": "meta"},
	"values": {"values": "values", "source": "meta"},
	"meter": {"name": "text", "value": "text", "decay": "text", "stages": "fields", "limit": "text", "at limit": "script",
		"source": "meta"},
	"condition": {"name": "text", "shows": "text", "while active": "effects", "each turn": "script", "ends": "script",
		"enters": "script", "still": "script", "each update": "script",
		"blocks rest": "text", "rest refusal": "script",
		"source": "meta"},
	## Heat: one strain's cycle (Needy Heat), and the one active policy.
	"heat": {"name": "text", "cycle": "text", "duration": "text", "female": "text", "mpreg": "text",
		"description": "text", "trigger": "script", "mpreg trigger": "script", "start": "script",
		"each turn": "script", "end": "script", "source": "meta"},
	## Pregnancy (PregnancySystem): who can carry, odds, gestation, litters, children.
	"pregnancy_rules": {"female when": "text", "male when": "text", "blocked when": "text", "odds": "text",
		"self odds": "text", "odds modifiers": "fields", "ask when": "text", "fathers": "fields", "gestation": "text",
		"quickens": "fields", "extra children": "text", "extra child bonus": "fields", "most children": "text",
		"single child when": "text", "child like father when": "text", "child like mother when": "text",
		"child like mother at birth when": "text", "feral when": "text", "child genders": "fields",
		"personalities": "list", "albino": "text", "melanism": "text", "sire when": "text", "sire odds": "text",
		"sire odds modifiers": "fields", "sire anal tag": "text", "sire turns": "text",
		"ask": "script", "conceived": "script", "each turn": "script", "birth": "script", "child": "script",
		"after birth": "script", "sired": "script", "sired birth": "script", "source": "meta"},
	"vore_rules": {"can vore when": "text", "can unbirth when": "text", "vore when": "text", "unbirth when": "text",
		"vore chance": "text", "vore chance modifiers": "fields", "vore chance out of": "text", "vore always when": "text",
		"unbirth chance": "text", "unbirth chance modifiers": "fields", "unbirth chance out of": "text",
		"vore automatic when": "text", "unbirth automatic when": "text", "hard vore when": "text", "unbirth gestation": "text",
		"vore label": "text", "unbirth label": "text", "suppress label": "text", "give in label": "text", "hold back label": "text",
		"vore urge": "script", "vore urge automatic": "script", "unbirth urge": "script", "unbirth urge automatic": "script",
		"both urge": "script", "both urge automatic": "script", "hunger wins": "script", "womb wins": "script",
		"vore": "script", "hard vore": "script", "unbirth": "script", "own scene when": "text", "absorb above": "text",
		"after vore": "script", "after unbirth": "script", "source": "meta"},
	"companion_rules": {"party size": "text", "party size modifiers": "fields", "companion xp": "text",
		"companion xp modifiers": "fields", "player xp cost": "text", "player xp cost modifiers": "fields",
		"player xp cost when": "text", "level up at": "text", "level up at modifiers": "fields", "levels while": "text",
		"damage every": "text", "dexterity every": "text", "hit bonus": "text", "hit bonus modifiers": "fields",
		"dismissed": "text", "leveled": "script", "party too big": "script", "source": "meta"},
	"heat_rules": {"default": "text", "female when": "text", "mpreg when": "text", "off when": "text",
		"intense when": "text", "intense lengthens": "text", "intense quickens": "text",
		"vulnerable": "script", "not vulnerable": "script", "switches": "script", "ends": "script", "source": "meta"},
	## Captivity: rounds of Struggle / Oblige / Endure while the player is held (bound states).
	"captivity": {"name": "text", "escape at": "text", "climax at": "text", "obliging when": "text",
		"pause after each": "text", "status": "text", "struggle label": "text", "oblige label": "text",
		"abide label": "text", "endure label": "text", "recover label": "text", "start": "script",
		"each round": "script", "climax": "script", "situation": "script", "struggle": "script",
		"escape": "script", "oblige": "script", "abide": "script", "endure": "script", "recover": "script",
		"lost": "script", "actions": "menu", "source": "meta"},
	## A hook: content that runs at a moment of play instead of an every-turn rule.
	"hook": {"on": "text", "when": "text", "while incapacitated": "text", "do": "script", "source": "meta"},
	"image": {"artist": "text", "link": "text", "tags": "list", "description": "text", "source": "meta"},
	"filter": {"name": "text", "group": "text", "description": "text", "genders": "list", "from": "text", "source": "meta"},
	"level": {"name": "text", "description": "text", "default": "text", "options": "fields", "from": "text", "source": "meta"},
	"tag": {"name": "text", "group": "text", "description": "text", "from": "text", "source": "meta"},
	"ending": {"name": "text", "type": "text", "priority": "text", "when": "text", "play": "script", "source": "meta"},
	"status_bar": {"meters": "list", "currency": "text", "currency names": "list", "source": "meta"},
	"shop": {"name": "text", "at": "list", "run by": "text", "open when": "text", "closed": "script", "intro": "script",
		"currency": "text", "currency names": "list", "stock": "fields", "buys": "fields", "trades": "text", "bought": "script", "sold": "script",
		"trade bonus when": "text", "trade bonus chance": "text", "source": "meta"},
}
## Types the format defines but the engine does not run yet. They load with a warning.
const PENDING_TYPES := ["epilogue"]
## When several types share an ID (a creature and its form, an item and its
## condition, a location and its image), lookups by ID alone return the type
## that comes first here.
const LOOKUP_PRIORITY := ["location", "character", "item", "event", "quest", "scene", "menu", "text", "creature",
	"region", "zone", "door", "values", "pack", "shop", "feat", "ending", "epilogue", "filter", "level", "form",
	"condition", "meter", "image", "hook", "scenario", "rest_rules", "survival_rules", "scavenge_rules", "tag",
	"heat", "heat_rules", "captivity", "pregnancy_rules", "status_bar", "companion_rules", "level_rules", "combat_rules", "vore_rules",
	"interest"]

var _form_tags: Dictionary = {}  # form id -> tags (form_tags)
var definitions: Dictionary = {}  ## type -> {id -> FscParser.Definition}
var by_id: Dictionary = {}  ## id -> first definition with that ID (any type), for lookups by ID alone
var packs: Array = []  ## {id, path, version, requires}
var diagnostics: Array = []
var values: Dictionary = {}  ## "owner.name" -> {"kind", "states", "default", "line", "path"}
var quests: Dictionary = {}  ## id -> {"stages": [names], "journal": {name: text}}
var menus: Dictionary = {}  ## menu id -> {"def", "options": [option nodes], "settings": {}}
var extra_scripts: Dictionary = {}  ## "type:id#field" -> [node lists added by extend]
var line_paths: Dictionary = {}  ## Line -> path, for lines another file added by extend (exits)
## Content levels: id -> {"options": [ids], "text": {option: description},
## "bans": {option: [filters]}, "allows": {option: [filters]}, "default", "lines": {option: line}}
var levels: Dictionary = {}
var _programs: Dictionary = {}
var _parse_results: Array = []


func error(path: String, line: int, message: String) -> void:
	diagnostics.append({"severity": "error", "path": path, "line": line, "message": message})


func warning(path: String, line: int, message: String) -> void:
	diagnostics.append({"severity": "warning", "path": path, "line": line, "message": message})


func errors() -> Array:
	return diagnostics.filter(func(d): return d.severity == "error")


## Loads every pack found directly inside the given folders, each after the
## packs it requires. A pack whose requirement is missing still loads, with
## a warning; packs that require each other load in name order.
func load_folders(folders: Array) -> void:
	_form_tags.clear()
	var found := {}  ## pack id -> {"path", "requires"}
	for folder in folders:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		var subs := Array(dir.get_directories())
		subs.sort()
		for sub in subs:
			var pack_path: String = folder.path_join(sub)
			var manifest := pack_path.path_join("pack.fsc")
			if not FileAccess.file_exists(manifest):
				continue
			var info := _manifest(manifest)
			var id: String = info.get("id", sub)
			if found.has(id):
				error(manifest, 1, "Pack '%s' is also at %s; pack IDs must be unique." % [id, found[id].path])
				continue
			found[id] = {"path": pack_path, "requires": info.get("requires", []), "manifest": manifest}
	for id in _load_order(found):
		load_pack(found[id].path)
	_finish()
	Validator.run(self)


## The pack ID and requirements from a pack.fsc, read before loading.
func _manifest(path: String) -> Dictionary:
	var r := FscParser.parse(FileAccess.get_file_as_string(path), path)
	for d in r.definitions:
		if d.type == "pack":
			return {"id": d.id, "requires": _list(d, "requires")}
	return {}


## Pack IDs in load order: every pack after the packs it requires.
func _load_order(found: Dictionary) -> Array:
	var order: Array = []
	var state := {}  ## id -> "visiting" | "done"
	var ids: Array = found.keys()
	ids.sort()
	for id in ids:
		_visit(id, found, state, order)
	return order


func _visit(id: String, found: Dictionary, state: Dictionary, order: Array) -> void:
	if state.get(id, "") == "done":
		return
	if state.get(id, "") == "visiting":
		if not found[id].get("circle", false):
			found[id]["circle"] = true
			warning(found[id].manifest, 1, "Pack '%s' is part of a circle of packs that require each other; they load in name order." % id)
		return
	state[id] = "visiting"
	for req: String in found[id].requires:
		if found.has(req):
			_visit(req, found, state, order)
		else:
			warning(found[id].manifest, 1, "Pack '%s' requires pack '%s', which is not installed." % [id, req])
	state[id] = "done"
	order.append(id)


## Title, subtitle, logo, background and about text for the title and
## credits screens: from the last loaded pack that sets a title.
func branding() -> Dictionary:
	var out := {}
	for p: Dictionary in packs:
		var d: FscParser.Definition = p.def
		if d.fields.has("title"):
			out = {"pack": p.id, "path": p.path}
			for key in ["title", "subtitle", "logo", "background", "about"]:
				out[key] = d.fields[key].value if d.fields.has(key) else ""
			out["menu icons"] = _list(d, "menu icons")  # pictures shown beside a hovered menu entry
	return out


## Loads one pack folder (all .fsc files below it).
func load_pack(pack_path: String) -> void:
	var files: Array = []
	_collect_files(pack_path, files)
	files.sort()
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		_check_unconverted(text, f)
		var r := FscParser.parse(text, f)
		diagnostics.append_array(r.diagnostics)
		_parse_results.append(r)
		for d in r.definitions:
			if d.type == "pack":
				packs.append({"id": d.id, "path": pack_path, "def": d})
			_add(d, r)


## Drafts from a conversion tool mark every line it could not convert
## with "// UNCONVERTED:". A pack with such a marker never loads.
func _check_unconverted(text: String, path: String) -> void:
	var n := 0
	for line in text.split("\n"):
		n += 1
		if line.strip_edges().begins_with("// UNCONVERTED:"):
			error(path, n, "Line left unconverted by the conversion assistant: rewrite it in the content format, then remove the marker.")


func _collect_files(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".fsc"):
			out.append(path.path_join(f))
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_collect_files(path.path_join(sub), out)


func _add(d: FscParser.Definition, r: FscParser.Result) -> void:
	if not SCHEMA.has(d.type) and d.type not in PENDING_TYPES:
		error(d.path, d.line, "Unknown type '%s'. Known types: %s." % [d.type, ", ".join(SCHEMA.keys() + PENDING_TYPES)])
		return
	if d.type in PENDING_TYPES:
		warning(d.path, d.line, "Type '%s' is part of the format but not run by the engine yet; %s is loaded but unused." % [d.type, d.id])
	if d.mode == "extend":
		_extend(d, r)
		return
	var existing: FscParser.Definition = definitions.get(d.type, {}).get(d.id, null)
	if existing != null and d.mode != "replace":
		error(d.path, d.line, "%s '%s' is already defined at %s:%d. IDs must be unique within a type." % [d.type, d.id, existing.path, existing.line])
		return
	if d.mode == "replace":
		warning(d.path, d.line, "%s %s replaces an earlier definition." % [d.type, d.id])
	_check_fields(d)
	if not by_id.has(d.id) or d.mode == "replace" or _priority(d.type) < _priority(by_id[d.id].type):
		by_id[d.id] = d
	if not definitions.has(d.type):
		definitions[d.type] = {}
	definitions[d.type][d.id] = d
	_index(d, r)


static func _priority(type: String) -> int:
	var i := LOOKUP_PRIORITY.find(type)
	return i if i >= 0 else LOOKUP_PRIORITY.size()


func _check_fields(d: FscParser.Definition) -> void:
	var schema: Dictionary = SCHEMA.get(d.type, {})
	if d.type in PENDING_TYPES:
		return
	for name in d.field_order:
		if not schema.has(name):
			var f: FscParser.Field = d.fields[name]
			error(d.path, f.line, "Unknown field '%s' for %s. Allowed: %s." % [name, d.type, ", ".join(schema.keys())])
	if not d.options.is_empty() and d.type != "menu":
		error(d.path, d.line, "Options ('* ...') are only allowed in a menu or in a menu field such as 'observe:'.")


func _index(d: FscParser.Definition, r: FscParser.Result) -> void:
	match d.type:
		"menu":
			menus[d.id] = {"def": d, "options": d.options.duplicate(), "settings": _menu_settings(d)}
		"quest":
			_index_quest(d)
		"level":
			_index_level(d)
		"event":
			var outs: Array = ["none"] + _list(d, "outcomes")
			values["%s.outcome" % d.id] = {"kind": "states", "states": outs, "default": "none", "path": d.path, "line": d.line}
			# A counter per event (the original's Resolution of X used as a number).
			values["%s.resolution" % d.id] = {"kind": "number", "default": 0, "path": d.path, "line": d.line}
	if d.fields.has("values"):
		_index_values(d, d.fields["values"], r)
	if d.type == "character":
		# body:, stats: and relationship: become the character's values (CharacterSystem).
		var decls := CharacterSystem.declarations(d)
		for name in decls:
			var path := "%s.%s" % [d.id, name]
			if not values.has(path):
				values[path] = decls[name]
	# Inline menus in fields (observe:, actions:) become menus "<id>.<field>".
	var schema: Dictionary = SCHEMA.get(d.type, {})
	for name in d.field_order:
		if schema.get(name, "") == "menu":
			var f: FscParser.Field = d.fields[name]
			var inner := FscParser.Definition.new()
			inner.type = "menu"
			inner.id = "%s.%s" % [d.id, name]
			inner.path = d.path
			inner.line = f.line
			inner.body = f.children
			FscParser._read_fields(inner, r)
			menus[inner.id] = {"def": inner, "options": inner.options.duplicate(), "settings": _menu_settings(inner)}


func _menu_settings(d: FscParser.Definition) -> Dictionary:
	var s := {}
	for k in ["title", "leave", "pause after each", "sort"]:
		if d.fields.has(k):
			s[k] = d.fields[k].value
	return s


func _index_quest(d: FscParser.Definition) -> void:
	var q := {"stages": [], "journal": {}}
	if d.fields.has("stages"):
		for l in d.fields["stages"].children:
			if l.is_blank():
				continue
			var parts: PackedStringArray = l.text.split(":", true, 1)
			var stage: String = parts[0].strip_edges()
			q.stages.append(stage)
			if parts.size() > 1:
				q.journal[stage] = parts[1].strip_edges()
	if q.stages.is_empty():
		error(d.path, d.line, "Quest %s has no stages." % d.id)
	quests[d.id] = q
	values["quest.%s" % d.id] = {"kind": "states", "states": q.stages, "default": q.stages[0] if q.stages.size() else "", "path": d.path, "line": d.line}


## A level's options, one per line ("less: description"), each optionally
## followed by indented "bans:" or "allows:" lines naming filters.
func _index_level(d: FscParser.Definition) -> void:
	var lv := {"options": [], "text": {}, "bans": {}, "allows": {}, "lines": {}, "default": ""}
	var f: FscParser.Field = d.fields.get("options", null)
	if f != null:
		var top := _min_indent(f.children)
		var current := ""
		for l in f.children:
			if l.is_blank():
				continue
			var parts: PackedStringArray = l.text.split(":", true, 1)
			var key: String = parts[0].strip_edges()
			var rest: String = parts[1].strip_edges() if parts.size() > 1 else ""
			if l.indent == top:
				if not key.is_valid_identifier() or key != key.to_lower():
					error(d.path, l.number, "A level option is written 'name: description', with a lower-case name such as 'less' or 'standard'.")
					current = ""
					continue
				if key in lv.options:
					error(d.path, l.number, "Option '%s' is listed twice in level %s." % [key, d.id])
					continue
				current = key
				lv.options.append(key)
				lv.text[key] = rest
				lv.lines[key] = l.number
			elif current != "" and key in ["bans", "allows"]:
				var ids: Array = []
				for s in rest.split(","):
					if s.strip_edges() != "":
						ids.append(s.strip_edges())
				lv[key][current] = lv[key].get(current, []) + ids
			else:
				error(d.path, l.number, "Under a level option, only 'bans:' and 'allows:' lines are allowed.")
	if lv.options.is_empty():
		error(d.path, d.line, "Level %s has no options. List them under 'options:'." % d.id)
	else:
		lv.default = d.fields["default"].value if d.fields.has("default") else lv.options[0]
		if lv.default not in lv.options:
			error(d.path, d.fields["default"].line, "Default '%s' is not an option of level %s. Options: %s." % [lv.default, d.id, ", ".join(lv.options)])
			lv.default = lv.options[0]
	levels[d.id] = lv


static var _number_re := RegEx.create_from_string("^number(?: (-?\\d+))?$")


func _index_values(d: FscParser.Definition, f: FscParser.Field, r: FscParser.Result) -> void:
	var owner := d.id
	for l in f.children:
		if l.is_blank():
			continue
		# Only lines at the first level declare values; deeper lines are metadata (from:).
		if l.indent > _min_indent(f.children):
			continue
		var parts: PackedStringArray = l.text.split(":", true, 1)
		if parts.size() < 2:
			error(d.path, l.number, "A value is declared as 'name: kind', for example 'trust: number 0' or 'mood: calm, angry'.")
			continue
		var name: String = parts[0].strip_edges()
		var spec: String = parts[1].strip_edges()
		var decl := {"path": d.path, "line": l.number}
		var nm := _number_re.search(spec)
		if nm != null:
			decl.kind = "number"
			decl.default = int(nm.get_string(1)) if nm.get_string(1) != "" else 0
		elif spec == "flag":
			decl.kind = "flag"
			decl.default = false
		elif spec == "time":
			decl.kind = "time"
			decl.default = null
		elif spec.begins_with("text"):
			decl.kind = "text"
			decl.default = spec.substr(4).strip_edges()
		else:
			var states: Array = []
			for s in spec.split(","):
				states.append(s.strip_edges())
			decl.kind = "states"
			decl.states = states
			decl.default = states[0]
		values["%s.%s" % [owner, name]] = decl


static func _min_indent(lines: Array) -> int:
	var m := -1
	for l in lines:
		if not l.is_blank() and (m < 0 or l.indent < m):
			m = l.indent
	return max(m, 0)


func _extend(d: FscParser.Definition, r: FscParser.Result) -> void:
	# Applied after all packs are loaded, in load order.
	if not definitions.has("_extend"):
		definitions["_extend"] = []
	definitions["_extend"].append([d, r])


func _finish() -> void:
	for pair in definitions.get("_extend", []):
		var d: FscParser.Definition = pair[0]
		var r: FscParser.Result = pair[1]
		var target: FscParser.Definition = definitions.get(d.type, {}).get(d.id, null)
		if target == null:
			error(d.path, d.line, "Cannot extend %s %s: it does not exist." % [d.type, d.id])
			continue
		var schema: Dictionary = SCHEMA.get(d.type, {})
		for name in d.field_order:
			var f: FscParser.Field = d.fields[name]
			var kind: String = schema.get(name, "")
			if name == "source":
				continue
			if kind == "script":
				var key := "%s:%s#%s" % [d.type, d.id, name]
				if not extra_scripts.has(key):
					extra_scripts[key] = []
				extra_scripts[key].append({"field": f, "path": d.path})
			elif kind == "menu":
				var inner := FscParser.Definition.new()
				inner.body = f.children
				FscParser._read_fields(inner, r)
				var menu_id := "%s.%s" % [d.id, name]
				if not menus.has(menu_id):
					error(d.path, f.line, "%s has no %s menu to add to." % [d.id, name])
					continue
				menus[menu_id].options.append_array(inner.options)
			elif kind == "list":
				# Lists such as tags: append values.
				var tf: FscParser.Field = target.fields.get(name, null)
				if tf == null:
					target.fields[name] = f
					target.field_order.append(name)
				else:
					tf.value = tf.value + ", " + f.value
			elif kind == "fields" and d.type == "location" and name == "exits":
				# More ways out of another pack's place ("== extend location bunker" with "exits:").
				var tf: FscParser.Field = target.fields.get(name, null)
				if tf == null:
					target.fields[name] = f
					target.field_order.append(name)
					tf = f
				else:
					var taken: Array = []
					for l: FscParser.Line in tf.children:
						if not l.is_blank():
							taken.append(l.text.split(":", true, 1)[0].strip_edges())
					for l: FscParser.Line in f.children:
						if l.is_blank():
							continue
						if l.text.split(":", true, 1)[0].strip_edges() in taken:
							error(d.path, l.number, "%s already has an exit %s." % [d.id, l.text.split(":", true, 1)[0].strip_edges()])
							continue
						tf.children.append(l)
				for l: FscParser.Line in f.children:
					line_paths[l] = d.path
			else:
				error(d.path, f.line, "Field '%s' cannot be extended; use '== replace %s %s' to change it." % [name, d.type, d.id])
		for o in d.options:
			if menus.has(d.id):
				menus[d.id].options.append(o)
	definitions.erase("_extend")


## Credits for loaded content: the original authors named by `source:` lines
## (the first folder of the source path, as the original repository is
## organised by author) and the artists of pack images.
func credits() -> Dictionary:
	var writers: Dictionary = {}
	var art: Array = []
	for type in definitions:
		for d: FscParser.Definition in all_of(type).values():
			if d.fields.has("source"):
				var author: String = d.fields.source.value.split("/", true, 1)[0].strip_edges()
				if "/" in d.fields.source.value and author not in ["Core Mechanics", "Inform", "Figures"]:
					writers[author] = true
	for id in all_of("image"):
		var artist := typed_value("image", id, "artist")
		if artist != "":
			art.append({"image": id, "artist": artist, "link": typed_value("image", id, "link")})
	var names: Array = writers.keys()
	names.sort()
	art.sort_custom(func(a, b): return a.artist + a.image < b.artist + b.image)
	return {"writers": names, "art": art, "packs": packs.map(func(p): return {"id": p.id,
		"name": field_value(p.id, "name", p.id), "version": field_value(p.id, "version", ""), "authors": field_value(p.id, "authors", "")})}


## How an event is found: {"exploring", "scavenging", "zones", "form"}.
## "form" is "zones" for the forms the engine runs, "nowhere", "pending" for
## documented forms not run yet, or "unknown".
static func found_by(text: String) -> Dictionary:
	# Parts are separated by ";": "exploring in outside; walking into grey_abbey_library".
	var out := {"exploring": false, "scavenging": false, "zones": [], "form": "unknown", "walking": [], "travelling": [],
		"leaving": []}
	var forms: Array = []
	for part in text.split(";"):
		var t := part.strip_edges()
		var done := false
		for prefix in ["exploring or scavenging in ", "scavenging in ", "exploring in "]:
			if t.begins_with(prefix):
				out.exploring = out.exploring or prefix.begins_with("exploring")
				out.scavenging = out.scavenging or "scavenging" in prefix
				for z in t.substr(prefix.length()).split(","):
					if z.strip_edges() != "":
						out.zones.append(z.strip_edges())
				forms.append("zones")
				done = true
				break
		if done:
			continue
		# Arrival: walking in (the original's walk-in events), fast travel (nav-in) or either.
		for prefix in ["walking into ", "travelling to ", "arriving at "]:
			if t.begins_with(prefix):
				for p in t.substr(prefix.length()).split(","):
					var place := p.strip_edges()
					if place == "":
						continue
					if prefix != "travelling to ":
						out.walking.append(place)
					if prefix != "walking into ":
						out.travelling.append(place)
				forms.append("arrival")
				done = true
				break
		if done:
			continue
		# "leaving <place> <direction>": a scene instead of walking out that way.
		if t.begins_with("leaving "):
			var ok := true
			for p in t.substr(8).split(","):
				var w := p.strip_edges().split(" ", false)
				if w.size() == 2:
					out.leaving.append([w[0], w[1]])
				else:
					ok = false
			forms.append("leaving" if ok else "unknown")
			continue
		if t in ["", "nowhere"]:
			forms.append("nowhere")
		elif t == "hunting":
			forms.append("pending")
		else:
			forms.append("unknown")
	for f in ["unknown", "pending", "zones", "arrival", "leaving", "nowhere"]:
		if f in forms:
			out.form = f
			break
	return out


## Lists the comma-separated values of a field.
## A form's tags: its own and those of the creatures that infect with it (the
## original's lists such as LatexList name creatures; the port keeps them there).
func form_tags(form: String) -> Array:
	if _form_tags.is_empty():
		for id in all_of("form"):
			_form_tags[id] = _list(get_def("form", id), "tags")
		for id in all_of("creature"):
			var f := typed_value("creature", id, "form")
			if _form_tags.has(f):
				for t in _list(get_def("creature", id), "tags"):
					if t not in _form_tags[f]:
						_form_tags[f].append(t)
	return _form_tags.get(form, [])


func _list(d: FscParser.Definition, name: String) -> Array:
	var out: Array = []
	if d.fields.has(name):
		for s in d.fields[name].value.split(","):
			var v: String = s.strip_edges()
			if v != "":
				out.append(v)
	return out


func list_field(id: String, name: String) -> Array:
	return _list(by_id[id], name) if by_id.has(id) else []


func field_value(id: String, name: String, default: String = "") -> String:
	if by_id.has(id) and by_id[id].fields.has(name):
		return by_id[id].fields[name].value
	return default


## A field of a definition of a given type (use when types may share an ID).
func typed_value(type: String, id: String, name: String, default: String = "") -> String:
	var d := get_def(type, id)
	if d != null and d.fields.has(name):
		return d.fields[name].value
	return default


func has(id: String, type: String = "") -> bool:
	return definitions.get(type, {}).has(id) if type != "" else by_id.has(id)


func get_def(type: String, id: String) -> FscParser.Definition:
	return definitions.get(type, {}).get(id, null)


func type_of(id: String) -> String:
	return by_id[id].type if by_id.has(id) else ""


func all_of(type: String) -> Dictionary:
	return definitions.get(type, {})


## Returns the compiled program for a scene ("adam.talk_himself"), a script
## field ("adam#talk") or a menu option ("adam.talk@2"). Null if none.
func program(pid: String, owner_type: String = "") -> Program:
	var field_def: FscParser.Definition = null
	var key := pid
	if "#" in pid:
		if ":" in pid:
			var qualified := pid.split(":", true, 1)
			owner_type = qualified[0]
			pid = qualified[1]
		var owner := pid.get_slice("#", 0)
		field_def = by_id.get(owner, null) if owner_type == "" else get_def(owner_type, owner)
		if field_def == null:
			return null
		key = "%s:%s" % [field_def.type, pid]
	if _programs.has(key):
		return _programs[key]
	var nodes: Array = []
	var path := ""
	if "@" in pid:
		var parts := pid.split("@")
		var menu: Dictionary = menus.get(parts[0], {})
		var idx := int(parts[1])
		if menu.is_empty() or idx >= menu.options.size():
			return null
		nodes = menu.options[idx].body
		path = menu.def.path
	elif "#" in pid:
		var parts := pid.split("#")
		var d: FscParser.Definition = field_def
		if d == null:
			return null
		var r := FscParser.Result.new()
		r.path = d.path
		path = d.path
		if d.fields.has(parts[1]):
			nodes = _field_nodes(d.fields[parts[1]], r)
		for extra in extra_scripts.get(key, []):
			nodes = nodes + _field_nodes(extra.field, r)
		diagnostics.append_array(r.diagnostics)
		if nodes.is_empty() and not d.fields.has(parts[1]):
			return null
	else:
		var d: FscParser.Definition = get_def("scene", pid)
		if d == null:
			d = get_def("text", pid)
		if d == null:
			return null
		nodes = d.nodes
		path = d.path
	var prog := Program.compile(key, nodes, path)
	for e in prog.errors:
		error(path, e.line, e.message)
	_programs[key] = prog
	return prog


## A script field's nodes: its value on the header line, then its indented lines.
func _field_nodes(f: FscParser.Field, r: FscParser.Result) -> Array:
	var nodes: Array = []
	if f.value != "":
		if f.value.begins_with("->"):
			nodes.append({"kind": "goto", "line": f.line, "target": f.value.substr(2).strip_edges()})
		else:
			nodes.append({"kind": "text", "line": f.line, "text": f.value})
	var lines: Array[FscParser.Line] = []
	lines.assign(f.children)
	if not lines.is_empty():
		nodes.append_array(FscParser.parse_script(lines, r))
	return nodes
