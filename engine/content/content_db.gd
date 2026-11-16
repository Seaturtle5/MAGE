class_name ContentDB
extends RefCounted
## All loaded content: definitions by type and ID, declared values, menus
## and compiled programs. Loads packs from folders, applies `extend`
## blocks and reports problems with file and line.

## Field kinds: text (one line or a long text with markup), script (a scene
## inside a field), fields (nested fields), list (comma separated), menu
## (options), values (value declarations), stages (quest stages), meta.
const SCHEMA := {
	"rest_rules": {"off when": "text", "interruption when": "text", "interruption chance": "text", "interruption chance modifiers": "fields", "interrupted": "script", "undisturbed": "script", "condition": "text", "duration": "text", "fresh below": "text", "fresh fatigue": "text",
		"exhausted recovery": "text", "hammock fresh fatigue": "text", "hammock recovery": "text",
		"collapse at": "text", "collapse fatigue": "text", "collapse turns": "text",
		"statuses": "fields", "warnings": "fields", "refreshed": "script", "collapse": "script", "wake": "script", "source": "meta"},
	"pack": {"name": "text", "version": "text", "authors": "text", "requires": "list", "license": "text",
		"title": "text", "subtitle": "text", "logo": "text", "background": "text", "about": "text",
		"menu icons": "list", "loading": "text", "loading frames": "text", "art": "text"},
	"hunt_rules": {"hunt when": "text", "target weight": "text", "target weight modifiers": "fields", "others when": "text",
		"other skipped when": "text", "not found": "script", "source": "meta"},
	"survival_rules": {"natural healing when": "text", "sanity floor when": "text", "hunger warnings": "fields", "thirst warnings": "fields", "starving hint at": "text",
		"starving hint": "text", "hunger death": "text", "thirst death": "text", "morale normalized": "text",
		"humanity loss": "text", "journal hint below": "text", "journal hint": "text", "humanity descriptions": "fields",
		"lust descriptions": "fields", "humanity ending": "text", "rescue ending": "text", "anticipation within": "text",
		"rescue anticipation": "text", "rescue after": "text", "healing": "script", "hunger rises": "script", "thirst rises": "script", "source": "meta"},
	"scenario": {"name": "text", "description": "text", "start": "text", "intro": "script", "setup": "script", "source": "meta"},
	# Character creation (CreationSystem): the new-game choices and the scripts around them.
	"creation_rules": {"choices": "list", "feats": "fields", "before": "script", "after": "script", "source": "meta"},
	"command": {"name": "text", "description": "text", "when": "text", "play": "script", "source": "meta"},
	# Smelling (SmellSystem), the player's own notes (NotesSystem) and the help topics (HelpSystem).
	"smell_rules": {"smelling": "script", "smelling person": "script", "no scent": "script", "no place scent": "script",
		"yourself": "script", "source": "meta"},
	"notes_rules": {"when": "text", "missing": "text", "write": "text", "browse": "text", "none": "text", "date": "text",
		"crossed out": "text", "torn out": "text", "write label": "text", "cross out label": "text", "tear out label": "text",
		"longest": "text", "source": "meta"},
	"help": {"title": "text", "text": "script", "order": "text", "source": "meta"},
	"game_mode": {"name": "text", "description": "text", "exploration bonus": "text", "encounter bonus": "text", "scavenge bonus": "text", "carry bonus": "text", "loot bonus": "text", "source": "meta"},
	"feat": {"name": "text", "description": "text", "exploration bonus": "text", "encounter bonus": "text",
		"scavenge bonus": "text", "loot bonus": "text", "carry bonus": "text", "body text": "text", "group": "text", "available when": "text",
		"gained": "script", "source": "meta"},
	"level_rules": {"xp needed": "text", "xp needed modifiers": "fields", "levels when": "text", "level up": "script",
		"source": "meta"},
	"interest": {"name": "text", "description": "text", "default": "text", "group": "text", "source": "meta"},
	# How infection treats the body (BodySystem.rule): conditions, chances, caps.
	"infection_rules": {"blocked when": "text", "resists when": "text", "resist chance": "text", "changes twice when": "text",
		"twice chance": "text", "stats follow when": "text", "stats keep when": "text",
		"prefers male when": "text", "prefers female when": "text", "prefers herm when": "text",
		"single sex when": "text", "keeps cock when": "text", "keeps cunt when": "text", "modest when": "text",
		"modest cock length": "text", "modest ball size": "text", "modest cunt depth": "text",
		"modest cunt tightness": "text", "one way when": "text", "just one when": "text", "keeps extras when": "text",
		"nipples stay when": "text", "nipples keep when": "text", "breasts grow when": "text",
		"male breasts when": "text", "male flat when": "text", "flat chest when": "text",
		"food infection blocked when": "text", "source": "meta"},
	"combat_rules": {"harder rolls when": "text", "level limit": "text", "level limit off when": "text", "unarmed attack": "text", "unarmed damage": "text", "player hits": "text", "flee": "text", "hump lust": "text",
		"flee fails": "text", "won": "script", "lost": "script", "each round": "script", "before flee": "script",
		"fight starts": "script", "player damage": "script", "avoid": "script", "enemy damage": "script",
		"before random fight": "script", "creature chance": "text", "creature chance modifiers": "fields",
		"second fight when": "text", "second fight": "script", "auto action": "text",
		"trophy prompt": "text", "no trophy": "text", "no trophy label": "text", "source": "meta"},
	"scavenge_rules": {"generic": "text", "generic chance": "text", "target": "text", "start": "text", "found": "text",
		"failure": "text", "only at": "text", "source": "meta"},
	"creature": {"name": "text", "vore": "script", "vore when": "text", "hard vore": "script", "hard vore when": "text", "unbirth": "script", "unbirth when": "text", "species": "text", "image": "text", "found in": "list", "active": "text",
		"level": "text", "hp": "text", "damage": "text", "stats": "text", "libido": "text", "form": "text",
		"gender": "text", "special": "text", "seduction immune": "text", "tags": "list", "source": "meta",
		"title": "text", "personal name": "text", "name known": "text", "unique": "text", "group": "text", "infectious": "text",
		"cross infection": "text", "research bypass": "text", "magic": "text", "loot": "text",
		"hit bonus": "text", "dodge bonus": "text", "mind bonus": "text", "variants": "fields", "pick variant": "text",
		"encounter": "script", "attack": "script", "grapple": "script", "escape": "script", "struggle": "script", "defeated": "script", "victory": "script",
		"strike with": "text", "attacks": "menu", "each round": "script", "before attack": "script", "after attack": "script",
		"fight starts": "script", "trophies": "text", "miss": "script", "hump": "script", "pounce": "script", "breath warning": "script", "breath direct": "script",
		"breath partial": "script", "breath miss": "script"},
	"form": {"name": "text", "sex": "text", "scale": "text", "body type": "text", "descriptor": "text",
		"stats": "text", "libido": "text", "tags": "list", "source": "meta", "head": "fields", "torso": "fields",
		"milk item": "text", "cum item": "text", "each turn": "script", "sex by preference": "text", "heat": "text", "offspring gender": "text",
		"back": "fields", "arms": "fields", "legs": "fields", "ass": "fields", "tail": "fields", "cock": "fields",
		"cunt": "fields", "skin": "fields", "breasts": "fields", "balls": "fields"},
	"character": {"name": "text", "pronouns": "text", "image": "text", "scent": "script", "description": "script",
		"lives at": "text", "presence": "script", "body": "fields", "stats": "fields", "relationship": "fields",
		"values": "values", "talk": "script", "sex": "script", "impregnation": "script", "actions": "menu", "companion": "fields", "summon": "script", "dismiss": "script",
		"companion attack": "script", "tags": "list", "source": "meta",
		"gift": "script", "gift tags": "list", "gift when": "text", "gift prompt": "text"},
	"menu": {"title": "text", "leave": "text", "leave text": "script", "pause after each": "text", "sort": "text",
		"intro": "script", "source": "meta"},
	"scene": {"source": "meta", "tags": "list"},
	"text": {},
	"quest": {"name": "text", "region": "text", "stages": "stages", "done at": "text", "journal": "script", "source": "meta"},
	"event": {"name": "text", "found by": "text", "repeat": "text", "outcomes": "list", "values": "values", "tags": "list",
		"source": "meta", "play": "script", "level": "text", "min score": "text", "requires": "text", "chance": "text",
		"priority": "text", "cooldown": "text", "active": "text", "blocks": "text", "replaces trip": "text",
		"arrival requires": "text", "exploring requires": "text"},
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
	"status_bar": {"meters": "list", "currency": "text", "currency names": "list", "sheet": "list", "details": "fields", "start date": "text", "source": "meta"},
	"shop": {"name": "text", "at": "list", "run by": "text", "open when": "text", "closed": "script", "intro": "script",
		"currency": "text", "currency names": "list", "stock": "fields", "buys": "fields", "trades": "text", "bought": "script", "sold": "script",
		"trade bonus when": "text", "trade bonus chance": "text", "source": "meta"},
}
## Types the format defines but the engine does not run yet. They load with a warning.
const PENDING_TYPES := ["epilogue"]
## When several types share an ID (a creature and its form, an item and its
## condition, a location and its image), lookups by ID alone return the type
## that comes first here.
const LOOKUP_PRIORITY := ["creation_rules", "game_mode", "location", "character", "item", "event", "quest", "scene", "menu", "text", "creature",
	"region", "zone", "door", "values", "pack", "shop", "feat", "ending", "epilogue", "filter", "level", "form",
	"condition", "meter", "image", "hook", "scenario", "rest_rules", "survival_rules", "scavenge_rules", "tag",
	"heat", "heat_rules", "captivity", "pregnancy_rules", "status_bar", "companion_rules", "level_rules", "combat_rules", "infection_rules", "vore_rules",
	"interest", "hunt_rules", "smell_rules", "notes_rules", "help"]

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
var _map_layout: MapLayout = null
## Art packs (a pack with `art: replaces` or `art: fallback`): their `image:`
## extensions, "type:id" -> [{"pack", "image", "replaces"}] in load order.
var art_images: Dictionary = {}
## Art packs the player switched off: their pictures and image files are not used.
var art_off: Array = []
var _folder_of: Dictionary = {}  ## pack path -> index of the folder it was found in
## event -> {outcome: resolution number} (`outcomes: fed = 1`, or an outcome named outcome_N)
var outcome_numbers: Dictionary = {}


func error(path: String, line: int, message: String) -> void:
	diagnostics.append({"severity": "error", "path": path, "line": line, "message": message})


func warning(path: String, line: int, message: String) -> void:
	diagnostics.append({"severity": "warning", "path": path, "line": line, "message": message})


func errors() -> Array:
	return diagnostics.filter(func(d): return d.severity == "error")


## Loads every pack found directly inside the given folders, each after the
## packs it requires. A pack whose requirement is missing still loads, with
## a warning; packs that require each other load in name order.
var _progress_lock := Mutex.new()
var _progress := {"step": "", "pack": "", "done": 0, "total": 0}


## How far load_folders has come, for a loading screen on another thread:
## {"step": what it does now, "pack": the pack being read, "done", "total" packs}.
func progress() -> Dictionary:
	_progress_lock.lock()
	var p := _progress.duplicate()
	_progress_lock.unlock()
	return p


func _set_progress(step: String, pack: String, done: int, total: int) -> void:
	_progress_lock.lock()
	_progress = {"step": step, "pack": pack, "done": done, "total": total}
	_progress_lock.unlock()


func load_folders(folders: Array) -> void:
	_set_progress("Finding packs", "", 0, 0)
	_form_tags.clear()
	var found := {}  ## pack id -> {"path", "requires"}
	for folder in folders:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		# A folder of packs, or one pack's own folder (it holds a pack.fsc).
		var single := FileAccess.file_exists(str(folder).path_join("pack.fsc"))
		var subs := [""] if single else Array(dir.get_directories())
		subs.sort()
		for sub in subs:
			var pack_path: String = str(folder).path_join(sub) if not single else str(folder).trim_suffix("/")
			var manifest := pack_path.path_join("pack.fsc")
			if not FileAccess.file_exists(manifest):
				continue
			var info := _manifest(manifest)
			var id: String = info.get("id", sub)
			if found.has(id):
				error(manifest, 1, "Pack '%s' is also at %s; pack IDs must be unique." % [id, found[id].path])
				continue
			found[id] = {"path": pack_path, "requires": info.get("requires", []), "manifest": manifest, "name": info.get("name", id)}
			_folder_of[pack_path] = folders.find(folder)
	var order := _load_order(found)
	for i in order.size():
		_set_progress("Loading packs", str(found[order[i]].name), i, order.size())
		load_pack(found[order[i]].path)
	_set_progress("Linking content", "", order.size(), order.size())
	_finish()
	_set_progress("Checking content", "", order.size(), order.size())
	Validator.run(self)
	_set_progress("Done", "", order.size(), order.size())


## The pack ID and requirements from a pack.fsc, read before loading.
func _manifest(path: String) -> Dictionary:
	var r := FscParser.parse(FileAccess.get_file_as_string(path), path)
	for d in r.definitions:
		if d.type == "pack":
			return {"id": d.id, "requires": _list(d, "requires"), "name": str(d.fields["name"].value) if d.fields.has("name") else d.id}
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


## The loading animation of the game pack (the one with a `title:`), read from
## the pack manifests alone so it can show while everything else loads:
## {"image": path of the sprite sheet, "frames": how many frames side by side}.
## `loading:` may name several sheets; each start shows one of them at random.
## Empty when no pack has one.
static func peek_loading(folders: Array) -> Dictionary:
	var out := {}
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
			for d in FscParser.parse(FileAccess.get_file_as_string(manifest), manifest).definitions:
				if d.type != "pack" or not d.fields.has("title") or not d.fields.has("loading"):
					continue
				var sheets: Array = []
				for id in str(d.fields["loading"].value).split(",", false):
					for ext in ["png", "webp", "jpg", "jpeg"]:
						var path := pack_path.path_join("images/%s.%s" % [id.strip_edges(), ext])
						if FileAccess.file_exists(path):
							sheets.append(path)
							break
				if not sheets.is_empty():
					var frames := int(str(d.fields["loading frames"].value)) if d.fields.has("loading frames") else 1
					out = {"image": sheets[randi() % sheets.size()], "frames": maxi(frames, 1)}  # one of them, at random
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
				packs.append({"id": d.id, "path": pack_path, "def": d, "folder": int(_folder_of.get(pack_path, 0)),
					"art": d.fields["art"].value if d.fields.has("art") else ""})
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
	if existing != null and d.type == "values" and d.mode != "replace":
		# Several packs may declare values for one owner (a game's own player values,
		# a story pack's additions): each adds its values; a value declared twice is an error.
		_check_fields(d)
		for name in _declared_names(d):
			if values.has("%s.%s" % [d.id, name]):
				error(d.path, d.line, "Value %s.%s is already declared at %s:%d." % [d.id, name, values["%s.%s" % [d.id, name]].path, values["%s.%s" % [d.id, name]].line])
				return
		definitions[d.type]["%s#%d" % [d.id, definitions[d.type].size()]] = d
		_index(d, r)
		return
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


## The names a values definition declares (first-level lines of its `values:`).
func _declared_names(d: FscParser.Definition) -> Array:
	var out: Array = []
	if not d.fields.has("values"):
		return out
	var f: FscParser.Field = d.fields["values"]
	for l in f.children:
		if not l.is_blank() and l.indent <= _min_indent(f.children) and ":" in l.text:
			out.append(l.text.split(":", true, 1)[0].strip_edges())
	return out


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
			# "outcomes: fed = 1, chased_off = 2": names, each with an optional resolution
			# number (an outcome named outcome_3 has the number 3 without one written).
			var outs: Array = ["none"]
			var numbers := {}
			for entry: String in _list(d, "outcomes"):
				var parts := entry.split("=", true, 1)
				var name := parts[0].strip_edges()
				outs.append(name)
				if parts.size() == 2 and parts[1].strip_edges().is_valid_int():
					numbers[name] = int(parts[1].strip_edges())
				elif name.begins_with("outcome_") and name.substr(8).is_valid_int():
					numbers[name] = int(name.substr(8))
			if not numbers.is_empty():
				outcome_numbers[d.id] = numbers
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


static var _when_re := RegEx.create_from_string("^when (raised|lowered): *(.+)$")
static var _role_re := RegEx.create_from_string("^role: *(\\w+)$")
static var _number_re := RegEx.create_from_string("^number(?: (-?\\d+))?(?: \\((-?\\d+) to (-?\\d+)(?:, up to (-?\\d+) in fights)?\\))?$")
## Engine roles a pack gives its values (`role: sanity` under a value): the
## engine systems read the value playing a role, and skip what no value plays.
const ROLES := ["sanity", "arousal", "morale"]
var roles: Dictionary = {}  ## role -> value path ("sanity" -> "player.humanity")


func _index_values(d: FscParser.Definition, f: FscParser.Field, r: FscParser.Result) -> void:
	var owner := d.id
	var last := ""  # the value the following metadata lines belong to
	var top := _min_indent(f.children)
	for l in f.children:
		if l.is_blank():
			continue
		# Only lines at the first level declare values; deeper lines are metadata (from:, role:).
		if l.indent > top:
			# "when raised: <text>" / "when lowered: <text>": said when a change raises or lowers it.
			var wm := _when_re.search(l.text.strip_edges())
			if wm != null and last != "":
				values[last][wm.get_string(1)] = wm.get_string(2)
				values[last][wm.get_string(1) + "_line"] = l.number
				continue
			var rm := _role_re.search(l.text.strip_edges())
			if rm != null and last != "":
				var role := rm.get_string(1)
				if role not in ROLES:
					error(d.path, l.number, "Unknown role '%s'. Roles: %s." % [role, ", ".join(ROLES)])
				elif roles.has(role) and roles[role] != last:
					error(d.path, l.number, "Role '%s' is already played by %s." % [role, roles[role]])
				else:
					roles[role] = last
					values[last].role = role
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
			if nm.get_string(2) != "":
				# "number 100 (0 to 100)": kept within its bounds; "up to 110 in fights" raises the top during a fight.
				decl.min = int(nm.get_string(2))
				decl.max = int(nm.get_string(3))
				if nm.get_string(4) != "":
					decl.fight_max = int(nm.get_string(4))
		elif spec == "flag":
			decl.kind = "flag"
			decl.default = false
		elif spec == "time":
			decl.kind = "time"
			decl.default = null
		elif spec == "list" or spec.begins_with("list "):
			# "list" (empty at the start) or "list 1, 2, 3": numbers or texts, in order.
			decl.kind = "list"
			decl.default = []
			for entry in spec.substr(4).split(",", false):
				var e := entry.strip_edges()
				if e.is_valid_int():
					decl.default.append(int(e))
				elif e != "":
					decl.default.append(e.trim_prefix("\"").trim_suffix("\""))
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
		last = "%s.%s" % [owner, name]


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
	# `== values character`: values every character has, unless it declares its own.
	for path: String in values.keys():
		if path.begins_with("character.") and path.count(".") == 1:
			for c: String in definitions.get("character", {}):
				var own := "%s.%s" % [c, path.substr(10)]
				if not values.has(own):
					values[own] = values[path].duplicate()
	for pair in definitions.get("_extend", []):
		var d: FscParser.Definition = pair[0]
		var r: FscParser.Result = pair[1]
		var target: FscParser.Definition = definitions.get(d.type, {}).get(d.id, null)
		var art := pack_of(d.path)
		if str(art.get("art", "")) == "":
			art = {}
		if target == null:
			if not art.is_empty():
				# An art pack never stops the game from loading: a picture for something gone is skipped.
				warning(d.path, d.line, "Cannot extend %s %s: it does not exist, so its picture is not used." % [d.type, d.id])
				continue
			error(d.path, d.line, "Cannot extend %s %s: it does not exist." % [d.type, d.id])
			continue
		var schema: Dictionary = SCHEMA.get(d.type, {})
		for name in d.field_order:
			var f: FscParser.Field = d.fields[name]
			var kind: String = schema.get(name, "")
			if name == "source":
				continue
			if name == "image" and not art.is_empty():
				# An art pack's picture: chosen when shown (see image_of), so it can be switched off.
				var key := "%s:%s" % [d.type, d.id]
				if not art_images.has(key):
					art_images[key] = []
				art_images[key].append({"pack": art.id, "image": f.value, "replaces": art.art == "replaces",
					"path": d.path, "line": f.line})
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
					# The place has no such menu yet (scenery another pack puts there): the extension makes it.
					inner.type = "menu"
					inner.id = menu_id
					inner.path = d.path
					inner.line = f.line
					menus[menu_id] = {"def": inner, "options": inner.options.duplicate(), "settings": _menu_settings(inner)}
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
			elif not target.fields.has(name):
				# A field the definition does not have yet (an art pack's `image:` for a place without one).
				target.fields[name] = f
				target.field_order.append(name)
			elif name == "image":
				pass  # the definition's own picture wins: an art pack's picture is only a fallback
			else:
				error(d.path, f.line, "Field '%s' cannot be extended; use '== replace %s %s' to change it." % [name, d.type, d.id])
		for o in d.options:
			if menus.has(d.id):
				menus[d.id].options.append(o)
		if d.type == "character" and (d.fields.has("stats") or d.fields.has("body") or d.fields.has("relationship") or d.fields.has("companion")):
			# body:, stats: and the like added by an extension declare their values too.
			var decls := CharacterSystem.declarations(target)
			for name in decls:
				var path := "%s.%s" % [d.id, name]
				if not values.has(path):
					values[path] = decls[name]
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


## The pack a content file belongs to ({} if none).
func pack_of(file: String) -> Dictionary:
	var best := {}
	for p: Dictionary in packs:
		var root := str(p.path).trim_suffix("/") + "/"
		if file.begins_with(root) and (best.is_empty() or root.length() > str(best.path).length()):
			best = p
	return best


## The picture of a definition: an art pack's `image:` that replaces wins (the
## last one loaded, the player's own packs last); else the definition's own
## `image:`; else an art pack's fallback. Switched-off art packs don't count.
func image_of(type: String, id: String) -> String:
	var replacing := art_image(type, id, true)
	if replacing != "":
		return replacing
	var own := typed_value(type, id, "image")
	return own if own != "" else art_image(type, id, false)


## The picture an enabled art pack gives a definition: the winning one that
## replaces (`replacing`), or the first fallback; "" if none.
func art_image(type: String, id: String, replacing: bool) -> String:
	var found := ""
	var rank := -1
	for e: Dictionary in art_images.get("%s:%s" % [type, id], []):
		if e.replaces != replacing or e.pack in art_off:
			continue
		var p := _pack(str(e.pack))
		var r := int(p.get("folder", 0)) * 100000 + packs.find(p)
		if not replacing:
			return e.image
		if r >= rank:
			rank = r
			found = e.image
	return found


## The file of a picture by its image ID: from an enabled art pack that
## replaces (the last loaded wins), else the first other pack that has it,
## else an art pack's fallback; "" if no pack has it.
func image_file(image_id: String) -> String:
	if image_id == "":
		return ""
	var replacing := ""
	var rank := -1
	var normal := ""
	var fallback := ""
	for i in packs.size():
		var p: Dictionary = packs[i]
		var mode := str(p.get("art", ""))
		if mode != "" and p.id in art_off:
			continue
		for ext in ["png", "jpg", "jpeg", "webp"]:
			var path: String = str(p.path).path_join("images/%s.%s" % [image_id, ext])
			if not FileAccess.file_exists(path):
				continue
			var r := int(p.get("folder", 0)) * 100000 + i
			if mode == "replaces" and r >= rank:
				rank = r
				replacing = path
			elif mode == "" and normal == "":
				normal = path
			elif mode == "fallback" and fallback == "":
				fallback = path
			break
	return replacing if replacing != "" else normal if normal != "" else fallback


## The art packs, for switching them on and off: {"id", "name", "replaces", "on"}.
func art_packs() -> Array:
	var out: Array = []
	for p: Dictionary in packs:
		if str(p.get("art", "")) != "":
			out.append({"id": p.id, "name": field_value(p.id, "name", p.id), "replaces": p.art == "replaces",
				"on": p.id not in art_off, "path": p.path})
	return out


func _pack(id: String) -> Dictionary:
	for p: Dictionary in packs:
		if p.id == id:
			return p
	return {}


## Reads an art pack's files again after the player changed them in play
## (PlayerArt): its pictures and credits, adding the pack if it is new.
func reload_art_pack(pack_path: String) -> void:
	var files: Array = []
	_collect_files(pack_path, files)
	files.sort()
	var pack := {}
	var defs: Array = []
	for f in files:
		var r := FscParser.parse(FileAccess.get_file_as_string(f), f)
		for d: FscParser.Definition in r.definitions:
			if d.type == "pack":
				var old := _pack(d.id)
				if old.is_empty():
					old = {"id": d.id, "path": pack_path, "def": d, "folder": 1 << 10}
					packs.append(old)
				old.def = d
				old.art = d.fields["art"].value if d.fields.has("art") else ""
				if not definitions.has("pack"):
					definitions["pack"] = {}
				definitions["pack"][d.id] = d
				by_id[d.id] = d
				pack = old
			else:
				defs.append(d)
	if pack.is_empty():
		return
	for key: String in art_images.keys():
		art_images[key] = art_images[key].filter(func(e: Dictionary) -> bool: return e.pack != pack.id)
	var root := pack_path.trim_suffix("/") + "/"
	for id: String in definitions.get("image", {}).keys():
		if str(definitions.image[id].path).begins_with(root):
			definitions.image.erase(id)
	for d: FscParser.Definition in defs:
		if d.type == "image":
			if not definitions.has("image"):
				definitions["image"] = {}
			definitions["image"][d.id] = d
			if not by_id.has(d.id) or by_id[d.id].type == "image":
				by_id[d.id] = d
		elif d.mode == "extend" and d.fields.has("image") and get_def(d.type, d.id) != null:
			var key := "%s:%s" % [d.type, d.id]
			if not art_images.has(key):
				art_images[key] = []
			art_images[key].append({"pack": pack.id, "image": d.fields.image.value, "replaces": pack.art == "replaces",
				"path": d.path, "line": d.fields.image.line})


## Where every location sits on the map (worked out on first use, then kept).
func map_layout() -> MapLayout:
	if _map_layout == null:
		_map_layout = MapLayout.build(self)
	return _map_layout


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
