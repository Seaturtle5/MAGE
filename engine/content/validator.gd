class_name Validator
extends RefCounted
## Checks loaded content for broken references before play.
##
## Every script is compiled and walked: go-to and play targets, fights,
## images, effects, conditions and text substitutions must refer to things
## that exist. The world is checked too: exits, regions, zones, homes,
## quests and events. Problems are added to the content database's
## diagnostics with file, line and a plain message, with a "did you mean"
## suggestion where a close match exists.

const DESCRIPTORS := ["name", "sir", "s", "es", "he", "him", "his", "hers", "He", "Him", "His", "Hers",
	"cock", "cock size", "cup size", "strip crotch", "strip chest", "humanity description", "species", "random encountered creature", "head species", "torso species", "skin species", "cock species", "cunt species", "tail species", "body type", "skin",
	"picked creature", "enemy name", "the enemy", "Enemy name", "The enemy", "enemy body type", "bracket", "close bracket", "ghe", "ghis", "ghim", "ghishers", "gche", "gchis", "gchim", "gchishers", "gdragon", "gmasculine",
	"body descriptor", "head description", "face description", "torso description", "body description",
	"back description", "arms description", "legs description", "ass description", "tail description",
	"cock description", "cunt description", "skin description", "upper breast curve", "second breast curve",
	"lower breast curve", "marks", "gear description", "companions description"]
const PLAYER_VALUES := ["hp", "maxhp", "xp", "level", "score", "strength", "dexterity", "stamina",
	"charisma", "intelligence", "perception", "hunger", "thirst",
	"cocks", "cunts", "nipples", "name", "heat", "pregnancy", "balls", "cock", "cunt", "sterile", "fatigue",
	"capacity", "carried_weight", "scale", "gender_look", "style", "breasts", "pronouns",
	"heat_turns", "heat_paused", "heat_starts_in", "heat_ends_in", "heat_cycle", "heat_duration",
	"sex", "last_partner", "last_sex", "experienced", "virgin", "oral_virgin", "anal_virgin", "penile_virgin",
	"first_anal_partner", "first_vaginal_partner", "first_oral_partner", "first_penile_partner",
	"weight", "definition", "androgyny", "body_hair", "ass", "mouth", "clit"]
const SPECIAL_TARGETS := ["back", "end"]
const LOCATION_FLAGS := ["fast travel", "private", "safe rest", "known at start", "collected"]
const CREATURE_GENDERS := ["neuter", "male neuter", "female neuter", "male", "female", "herm", "shemale", "male herm", "cuntboy", "variable"]
## The kinds of sex the original records (CreatureSexAftermath / NPCSexAftermath).
const SEX_ACTS := ["anal", "anal_toy", "vaginal", "vaginal_toy", "oral_cock", "oral_pussy", "oral_toy", "stroking",
	"titfuck", "facial", "grinding", "oral_grinding", "frottage", "spanking", "nursing", "other"]

var db: ContentDB
var _images: Dictionary = {}
var _path := ""


static func run(content: ContentDB) -> void:
	var v := Validator.new()
	v.db = content
	v._collect_images()
	v._check_images()
	v._check_slice_types()
	v._check_items()
	v._check_rest_rules()
	v._check_survival_rules()
	v._check_creation_rules()
	v._check_heat()
	v._check_pregnancy()
	v._check_captivity()
	v._check_endings()
	v._check_status_bar()
	v._check_companions()
	v._check_levels()
	v._check_vore()
	v._check_scavenge_rules()
	v._check_world()
	v._check_filters()
	v._check_conditions()
	v._check_programs()


func _err(line: int, message: String) -> void:
	db.error(_path, line, message)


func _warn(line: int, message: String) -> void:
	db.warning(_path, line, message)


func _suggest(name: String, candidates: Array) -> String:
	var best := ""
	var best_score := 0.0
	for c in candidates:
		var score := name.similarity(str(c))
		if score > best_score:
			best_score = score
			best = str(c)
	return " Did you mean '%s'?" % best if best_score >= 0.6 else ""


func _ids(type: String) -> Array:
	return db.all_of(type).keys()


func _collect_images() -> void:
	for p in db.packs:
		var dir := DirAccess.open(str(p.path).path_join("images"))
		if dir == null:
			continue
		for f in dir.get_files():
			if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
				_images[f.get_basename()] = true


# --- World ------------------------------------------------------------------

func _check_images() -> void:
	for type in db.definitions:
		for d: FscParser.Definition in db.all_of(type).values():
			for key in (["logo", "background"] if type == "pack" else ["image"]):
				if not d.fields.has(key):
					continue
				var field: FscParser.Field = d.fields[key]
				if field.value != "" and not _images.has(field.value):
					_path = d.path
					_warn(field.line, "Image '%s' was not found in any pack's images folder; a placeholder is shown." % field.value)


func _check_slice_types() -> void:
	for id in db.all_of("feat"):
		var d := db.get_def("feat", id)
		_path = d.path
		for field in ["exploration bonus", "encounter bonus", "scavenge bonus"]:
			if d.fields.has(field) and not d.fields[field].value.is_valid_int():
				_err(d.fields[field].line, "%s must be a whole number." % field.capitalize())
	for id in db.all_of("filter"):
		var d := db.get_def("filter", id)
		_path = d.path
		for g in db._list(d, "genders"):
			if g not in CREATURE_GENDERS:
				_err(d.fields.genders.line, "Unknown gender '%s'. Genders: %s." % [g, ", ".join(CREATURE_GENDERS)])
	for id in db.all_of("scenario"):
		var d := db.get_def("scenario", id)
		_path = d.path
		_need(db.typed_value("scenario", id, "start"), "location", d.fields.get("start", d).line)
	for id in db.all_of("creature"):
		var d := db.get_def("creature", id)
		_path = d.path
		for field in ["hp", "level", "damage", "libido"]:
			if d.fields.has(field):
				var value: String = d.fields[field].value
				if not value.is_valid_int() or int(value) < (1 if field == "hp" else 0):
					_err(d.fields[field].line, "%s must be %s." % [field.capitalize(), "a positive whole number" if field == "hp" else "a non-negative whole number"])
		for field in ["hit bonus", "dodge bonus", "mind bonus"]:
			if d.fields.has(field) and not d.fields[field].value.is_valid_int():
				_err(d.fields[field].line, "%s must be a whole number." % field.capitalize())
		for zone in db._list(d, "found in"):
			if zone != "nowhere":
				_need(zone, "zone", d.fields["found in"].line)
		for flag in ["unique", "name known", "group", "infectious", "research bypass", "magic", "seduction immune"]:
			if d.fields.has(flag) and d.fields[flag].value not in ["yes", "no"]:
				_err(d.fields[flag].line, "%s must be yes or no." % flag.capitalize())
		if d.fields.has("gender") and d.fields.gender.value not in CREATURE_GENDERS:
			_err(d.fields.gender.line, "Unknown gender '%s'." % d.fields.gender.value)
		_check_variants(id, d)
		if d.fields.has("cross infection"):
			_need(d.fields["cross infection"].value, "form", d.fields["cross infection"].line)
		if d.fields.has("loot"):
			var loot: PackedStringArray = d.fields.loot.value.split(" ", false)
			if loot.size() != 2 or not loot[1].ends_with("%") or not loot[1].trim_suffix("%").is_valid_int():
				_err(d.fields.loot.line, "Loot is written 'item_id N%'.")
			else:
				_need(loot[0], "item", d.fields.loot.line)
		if d.fields.has("trophies"):
			for entry in d.fields.trophies.value.split(",", false):
				var trophy: PackedStringArray = entry.strip_edges().split(" ", false)
				if trophy.size() != 2 or not trophy[1].ends_with("%") or not trophy[1].trim_suffix("%").is_valid_int():
					_err(d.fields.trophies.line, "Trophies are written 'item_id N%%, item_id N%%' ('%s' is not)." % entry.strip_edges())
				else:
					_need(trophy[0], "item", d.fields.trophies.line)
		if d.fields.has("form"):
			_need(d.fields.form.value, "form", d.fields.form.line)
		if d.fields.has("active") and d.fields.active.value not in ["always", "day", "night"]:
			_err(d.fields.active.line, "Active must be always, day or night.")
		if d.fields.has("special"):
			var problem := _special_problem(d.fields.special.value)
			if problem != "":
				_err(d.fields.special.line, problem)
		if d.fields.has("strike with") and d.fields["strike with"].value not in CombatSystem.ATTRIBUTES:
			_err(d.fields["strike with"].line, "Strike with names an attribute: %s." % ", ".join(CombatSystem.ATTRIBUTES))
		_check_stats(d)
	for id in db.all_of("form"):
		var d := db.get_def("form", id)
		_path = d.path
		_check_stats(d)
		if d.fields.has("libido") and not d.fields.libido.value.is_valid_int():
			_err(d.fields.libido.line, "Libido must be a whole number.")
		for f in ["milk item", "cum item"]:
			if d.fields.has(f):
				_need(d.fields[f].value, "item", d.fields[f].line)
		for part in BodySystem.PARTS + ["breasts", "balls"]:
			if not d.fields.has(part):
				continue
			for line in d.fields[part].children:
				if line.is_blank():
					continue
				var pair: PackedStringArray = line.text.split(":", true, 1)
				if pair.size() != 2 or pair[0].strip_edges() not in ["description", "change", "color", "covering", "adjective", "count", "size", "length", "girth", "depth", "tightness", "nipples", "male size"]:
					_err(line.number, "Unknown body-part field; use description, change, attributes or numeric dimensions.")
				elif pair[0].strip_edges() in ["count", "size", "length", "girth", "depth", "tightness", "nipples", "male size"] and not pair[1].strip_edges().is_valid_int():
					_err(line.number, "Body dimensions must be whole numbers.")
				elif pair[0].strip_edges() in ["description", "change"]:
					var template := TextTemplate.compile(pair[1].strip_edges())
					if template.has("error"):
						_err(line.number, template.error)
					else:
						_check_template(template, line.number, id)


## Item numbers, flags, and the nested `equipment:` and `weapon:` fields.
func _check_items() -> void:
	for id in db.all_of("meter"):
		var m := db.get_def("meter", id)
		_path = m.path
		if not m.fields.has("value") or not "." in m.fields.value.value:
			_err(m.line, "A meter needs a value, such as 'value: player.alcohol'.")
		for f in ["decay", "limit"]:
			if m.fields.has(f) and not m.fields[f].value.is_valid_int():
				_err(m.fields[f].line, "%s must be a whole number." % f.capitalize())
		if m.fields.has("stages"):
			for l in m.fields.stages.children:
				if l.is_blank():
					continue
				var pair: PackedStringArray = l.text.split(":", true, 1)
				if pair.size() != 2 or not pair[0].strip_edges().is_valid_int():
					_err(l.number, "Stages are written 'N: condition_id'.")
				else:
					_need(pair[1].strip_edges(), "condition", l.number)
	for id in db.all_of("location"):
		var loc := db.get_def("location", id)
		if loc.fields.has("microwave") and loc.fields.microwave.value not in ["yes", "no"]:
			_path = loc.path
			_check_condition_text(loc.fields.microwave.value, loc.fields.microwave.line, id)
	for id in db.all_of("item"):
		var d := db.get_def("item", id)
		_path = d.path
		if d.fields.has("weight") and not d.fields.weight.value.is_valid_int():
			_err(d.fields.weight.line, "Weight must be a whole number of pounds.")
		if d.fields.has("use action") and d.fields["use action"].value not in ["rest", "wait", "explore", "scavenge"]:
			_err(d.fields["use action"].line, "Use action must be rest, wait, explore or scavenge.")
		if d.fields.has("use action") and d.fields.has("use"):
			_err(d.fields["use action"].line, "An item has either a use scene or a use action, not both.")
		if d.fields.has("infectious"):
			_need(d.fields.infectious.value, "form", d.fields.infectious.line)
		if d.fields.has("purified"):
			_need(d.fields.purified.value, "item", d.fields.purified.line)
		for flag in ["consumed", "keep", "in combat", "plural"]:
			if d.fields.has(flag) and d.fields[flag].value not in ["yes", "no"]:
				_err(d.fields[flag].line, "%s must be yes or no." % flag.capitalize())
		for nested in [["equipment", ItemSystem.EQUIPMENT_KEYS], ["weapon", ItemSystem.WEAPON_KEYS]]:
			if not d.fields.has(nested[0]):
				continue
			var f: FscParser.Field = d.fields[nested[0]]
			var keys: Dictionary = nested[1]
			var seen := {}
			for line in f.children:
				if line.is_blank():
					continue
				var pair: PackedStringArray = line.text.split(":", true, 1)
				var key := pair[0].strip_edges()
				var value := pair[1].strip_edges() if pair.size() == 2 else ""
				if pair.size() != 2 or not keys.has(key):
					_err(line.number, "Unknown %s field '%s'. Use: %s." % [nested[0], key, ", ".join(keys.keys())])
					continue
				seen[key] = true
				match str(keys[key]):
					"number":
						if not value.is_valid_int():
							_err(line.number, "%s must be a whole number." % key.capitalize())
					"yes/no":
						if value not in ["yes", "no"]:
							_err(line.number, "%s must be yes or no." % key.capitalize())
					"slot":
						if value not in ItemSystem.SLOTS:
							_err(line.number, "Unknown slot '%s'. Slots: %s.%s" % [value, ", ".join(ItemSystem.SLOTS), _suggest(value, ItemSystem.SLOTS)])
					"placement":
						if value not in ItemSystem.PLACEMENTS:
							_err(line.number, "Unknown placement '%s'. Placements: %s." % [value, ", ".join(ItemSystem.PLACEMENTS)])
					"melee/ranged":
						if value not in ["melee", "ranged"]:
							_err(line.number, "Weapon type must be melee or ranged.")
					"list":
						for st in value.split(","):
							if st.strip_edges() not in ItemSystem.STYLES:
								_err(line.number, "Unknown style '%s'. Styles: %s." % [st.strip_edges(), ", ".join(ItemSystem.STYLES)])
					"text":
						var template := TextTemplate.compile(value)
						if template.has("error"):
							_err(line.number, template.error)
						else:
							_check_template(template, line.number, id)
			if nested[0] == "equipment" and not seen.has("slot"):
				_err(f.line, "Equipment needs a slot (use 'slot: none' for gear that takes no slot).")
			if nested[0] == "weapon" and not seen.has("damage"):
				_err(f.line, "A weapon needs its damage.")


func _check_stats(d: FscParser.Definition) -> void:
	if not d.fields.has("stats"):
		return
	for entry in d.fields.stats.value.split(","):
		var pair: PackedStringArray = entry.strip_edges().split(" ", false)
		if pair.size() != 2 or pair[0] not in ["strength", "dexterity", "stamina", "perception", "intelligence", "charisma"] or not pair[1].is_valid_int():
			_err(d.fields.stats.line, "Stats use 'strength 12, dexterity 12, ...' with the six named stats and whole numbers.")


func _check_world() -> void:
	var locations := db.all_of("location")
	for id in locations:
		var d: FscParser.Definition = locations[id]
		_path = d.path
		for key in ["region", "zone"]:
			if d.fields.has(key):
				var v: String = d.fields[key].value
				if v != "" and v != "none" and not db.has(v, key):
					_err(d.fields[key].line, "%s '%s' does not exist.%s" % [key.capitalize(), v, _suggest(v, _ids(key))])
		for it in db.list_field(id, "items"):
			if not db.has(it, "item"):
				_err(d.fields["items"].line, "Item '%s' does not exist.%s" % [it, _suggest(it, _ids("item"))])
		var exits: FscParser.Field = d.fields.get("exits", null)
		if exits == null:
			continue
		for l in exits.children:
			if l.is_blank():
				continue
			var parts := l.text.split(":", true, 1)
			if parts.size() < 2:
				_err(l.number, "An exit is written as 'direction: location', for example 'north: plaza'.")
				continue
			_path = db.line_paths.get(l, d.path)  # exits another pack added with extend
			var opts := parts[1].split(",")
			var target := opts[0].strip_edges()
			var door := ""
			for option in opts.slice(0 if target.begins_with("door ") else 1):
				var value: String = option.strip_edges()
				if value.begins_with("door "):
					door = value.substr(5).strip_edges()
					_need(door, "door", l.number)
				elif value != "one way":
					_err(l.number, "Unknown exit option '%s'; use 'door ID' or 'one way'." % value)
			if target.begins_with("door "):
				# A door alone: a dangerous door that explores a zone.
				if db.has(door, "door") and db.typed_value("door", door, "leads to zone") == "":
					_err(l.number, "An exit with a door and no place needs a dangerous door (one with 'leads to zone:').")
				continue
			if door != "" and db.typed_value("door", door, "leads to zone") != "":
				continue  # going through a dangerous door explores; the place is only where it would lead
			if not db.has(target, "location"):
				_err(l.number, "Exit %s leads to '%s', which is not a location.%s" % [parts[0].strip_edges(), target, _suggest(target, locations.keys())])
				continue
			if "one way" in parts[1]:
				continue
			if not _has_exit_to(target, id):
				_warn(l.number, "Exit %s leads to %s, but %s has no exit back. Add one, or mark this exit 'one way'." % [parts[0].strip_edges(), target, target])
	_check_map_positions()
	for id in db.all_of("door"):
		var d := db.get_def("door", id)
		_path = d.path
		if d.fields.has("leads to zone"):
			_need(d.fields["leads to zone"].value, "zone", d.fields["leads to zone"].line)
		if d.fields.has("locked") and d.fields.locked.value not in ["yes", "no"]:
			_check_condition_text(d.fields.locked.value, d.fields.locked.line, id)
	for id in db.all_of("character"):
		var d: FscParser.Definition = db.get_def("character", id)
		_path = d.path
		if d.fields.has("lives at"):
			var home: String = d.fields["lives at"].value
			if not db.has(home, "location"):
				_err(d.fields["lives at"].line, "Home '%s' is not a location.%s" % [home, _suggest(home, locations.keys())])
		_check_character_fields(d)
	for id in db.quests:
		var d: FscParser.Definition = db.get_def("quest", id)
		_path = d.path
		var done := db.field_value(id, "done at")
		if done != "" and done not in db.quests[id].stages:
			_err(d.fields["done at"].line, "'done at: %s' is not a stage of quest %s." % [done, id])
		var region := db.field_value(id, "region")
		if region != "" and not db.has(region, "region"):
			_err(d.fields["region"].line, "Region '%s' does not exist.%s" % [region, _suggest(region, _ids("region"))])
	for id in db.all_of("event"):
		var d: FscParser.Definition = db.get_def("event", id)
		_path = d.path
		var found := ContentDB.found_by(db.typed_value("event", id, "found by"))
		var found_line: int = d.fields["found by"].line if d.fields.has("found by") else d.line
		match found.form:
			"zones":
				for zone in found.zones:
					if not db.has(zone, "zone"):
						_err(found_line, "Zone '%s' does not exist.%s" % [zone, _suggest(zone, _ids("zone"))])
			"arrival":
				for place in found.walking + found.travelling:
					_need(place, "location", found_line)
				for place in found.travelling:
					if "fast travel" not in db.list_field(place, "flags"):
						_warn(found_line, "'%s' is not a fast-travel point, so nobody travels to it; use 'walking into'." % place)
				if d.fields.has("chance") and not RegEx.create_from_string("^\\d+%?$").search(d.fields.chance.value):
					_err(d.fields.chance.line, "An arrival event's chance is a percentage, such as 40%.")
				for f in ["priority", "cooldown"]:
					if d.fields.has(f) and not d.fields[f].value.is_valid_int():
						_err(d.fields[f].line, "%s must be a whole number." % f.capitalize())
			"leaving":
				for pair in found.leaving:
					_need(pair[0], "location", found_line)
					if pair[1] not in ["north", "south", "east", "west", "northeast", "northwest", "southeast", "southwest", "up", "down", "inside", "outside"]:
						_err(found_line, "'%s' is not a direction." % pair[1])
			"pending":
				_warn(found_line, "'found by: %s' is part of the format but not run by the engine yet; the event is only started by other content." % db.typed_value("event", id, "found by"))
			"unknown":
				_err(found_line, "Unknown 'found by'. Use 'exploring in <zones>', 'scavenging in <zones>', 'exploring or scavenging in <zones>', 'walking into <places>', 'travelling to <places>', 'arriving at <places>', 'leaving <place> <direction>' or 'nowhere', separated by ';'.")
		if d.fields.has("requires"):
			_check_condition_text(d.fields["requires"].value, d.fields["requires"].line, id)
		if d.fields.has("replaces trip"):
			if d.fields["replaces trip"].value not in ["yes", "no"]:
				_err(d.fields["replaces trip"].line, "Replaces trip must be yes or no.")
			elif d.fields["replaces trip"].value == "yes" and found.travelling.is_empty():
				_err(d.fields["replaces trip"].line, "'replaces trip: yes' needs 'found by: travelling to <places>'.")
	_check_shops()
	_check_value_texts()
	for id in db.all_of("hook"):
		var d: FscParser.Definition = db.get_def("hook", id)
		_path = d.path
		var on := db.typed_value("hook", id, "on")
		var about := ""  # the character of "instead of talking to adam"
		for prefix: String in Game.HOOK_CHARACTER_MOMENTS:
			if on.begins_with(prefix):
				about = on.substr(prefix.length()).strip_edges()
		if about != "":
			_need(about, "character", d.fields["on"].line)
		elif on not in Game.HOOK_MOMENTS:
			_err(d.fields["on"].line if d.fields.has("on") else d.line, "A hook needs 'on:' with one of: %s, or %s." % [", ".join(Game.HOOK_MOMENTS),
				" or ".join(Game.HOOK_CHARACTER_MOMENTS.map(func(m): return "'%s<character>'" % m))])
		if d.fields.has("when"):
			_check_condition_text(d.fields["when"].value, d.fields["when"].line, id)
		var inc := db.typed_value("hook", id, "while incapacitated", "run")
		if inc not in ["run", "skip"]:
			_err(d.fields["while incapacitated"].line, "'while incapacitated' is 'skip' or 'run'.")
		if not d.fields.has("do"):
			_err(d.line, "A hook needs a 'do:' script.")


## A value's own change texts (`when raised:` / `when lowered:` under its declaration).
func _check_value_texts() -> void:
	var seen := {}  # values every character has: their copies are checked once
	for path: String in db.values:
		var decl: Dictionary = db.values[path]
		var key := "%s:%s" % [decl.get("path", ""), decl.get("line", 0)]
		if not (decl.has("raised") or decl.has("lowered")) or seen.has(key):
			continue
		seen[key] = true
		_path = str(decl.get("path", ""))
		for k in ["raised", "lowered"]:
			if not decl.has(k):
				continue
			var line := int(decl.get(k + "_line", decl.get("line", 0)))
			if decl.get("kind", "") != "number":
				_err(line, "Only a number value has 'when %s:' texts." % k)
				continue
			var t := TextTemplate.compile(str(decl[k]))
			if t.has("error"):
				_err(line, str(t.error))
			else:
				_check_template(t, line, "")


## Shops (ShopSystem): places, keeper, currency, stock and trade settings.
func _check_shops() -> void:
	for id in db.all_of("shop"):
		var d: FscParser.Definition = db.get_def("shop", id)
		_path = d.path
		if not d.fields.has("at"):
			_err(d.line, "A shop needs 'at:' with the places it is in.")
		for place in db.list_field(id, "at"):
			_need(place, "location", d.fields["at"].line)
		if d.fields.has("run by"):
			_need(d.fields["run by"].value, "character", d.fields["run by"].line)
		for f in ["open when", "trade bonus when"]:
			if d.fields.has(f):
				_check_condition_text(d.fields[f].value, d.fields[f].line, id)
		if d.fields.has("trade bonus chance") and not RegEx.create_from_string("^\\d+ in \\d+$").search(d.fields["trade bonus chance"].value):
			_err(d.fields["trade bonus chance"].line, "Trade bonus chance is written 'N in M', such as 1 in 3.")
		if d.fields.has("trades") and d.fields.trades.value not in ["yes", "no"]:
			_err(d.fields.trades.line, "Trades must be yes or no.")
		var cur := db.typed_value("shop", id, "currency")
		if cur == "":
			var bars: Array = db.all_of("status_bar").keys()
			if bars.is_empty() or db.typed_value("status_bar", bars[0], "currency") == "":
				_err(d.line, "A shop needs 'currency:' (a player value such as coins, or 'item <id>') when the game's status bar has none.")
		elif cur.begins_with("item "):
			_need(cur.substr(5).strip_edges(), "item", d.fields.currency.line)
		else:
			_check_path("player." + cur, d.fields.currency.line)
		if not d.fields.has("stock") and not d.fields.has("buys") and db.typed_value("shop", id, "trades", "no") != "yes":
			_warn(d.line, "Shop %s sells nothing, buys nothing and does not trade." % id)
		for name in ["stock", "buys"]:
			if not d.fields.has(name):
				continue
			var re := RegEx.create_from_string("^(\\w+)\\s*:\\s*(\\d+)(?:\\s*\\[if (.+)\\])?$")
			for l: FscParser.Line in d.fields[name].children:
				if l.is_blank():
					continue
				var m := re.search(l.text.strip_edges())
				if m == null:
					_err(l.number, "A %s line is 'item_id: price', optionally followed by [if condition]." % name)
					continue
				_need(m.get_string(1), "item", l.number)
				if m.get_string(3) != "":
					_check_condition_text(m.get_string(3), l.number, id)


## Filters, levels and the tags content carries.
##
## Every tag must be declared, as a `tag` (a description such as a creature
## family) or a `filter` (a category players can ban or ward). The engine
## applies filters to creatures and events; on other content a filter tag
## would be ignored, so it is reported instead.
const FILTERED_TYPES := ["creature", "event", "character"]


func _check_filters() -> void:
	for type in ["filter", "level"]:
		for id in db.all_of(type):
			var d: FscParser.Definition = db.get_def(type, id)
			_path = d.path
			if not d.fields.has("name") or d.fields.name.value == "":
				_err(d.line, "%s %s needs a name, shown on the settings screen." % [type.capitalize(), id])
	for id in db.levels:
		var d: FscParser.Definition = db.get_def("level", id)
		_path = d.path
		var lv: Dictionary = db.levels[id]
		for key in ["bans", "allows"]:
			for option in lv[key]:
				for f in lv[key][option]:
					if not db.has(f, "filter"):
						_err(lv.lines[option], "'%s' under option %s is not a filter.%s" % [f, option, _suggest(f, _ids("filter"))])
	var known: Array = _ids("filter") + _ids("tag")
	for type in db.definitions:
		for d: FscParser.Definition in db.all_of(type).values():
			if not d.fields.has("tags"):
				continue
			_path = d.path
			var line: int = d.fields.tags.line
			for t in db._list(d, "tags"):
				if not db.has(t, "filter") and not db.has(t, "tag"):
					_err(line, "Tag '%s' is not declared. Declare it as a tag, or as a filter if players can ban it.%s" % [t, _suggest(t, known)])
				elif db.has(t, "filter") and type not in FILTERED_TYPES:
					_warn(line, "Filter '%s' on a %s is not applied yet; only creatures, events and characters are filtered. Check the setting in the scene instead, for example 'if filter %s is allowed'." % [t, type, t])


func _check_conditions() -> void:
	for id in db.all_of("condition"):
		var d: FscParser.Definition = db.get_def("condition", id)
		_path = d.path
		if d.fields.has("blocks rest") and d.fields["blocks rest"].value not in ["yes", "no"]:
			_err(d.fields["blocks rest"].line, "Blocks rest must be yes or no.")
		if not d.fields.has("while active"):
			continue
		for l in d.fields["while active"].children:
			if l.is_blank():
				continue
			var e := Effect.compile(l.text)
			if e.has("error"):
				_err(l.number, e.error)
			elif e.op not in ["feat", "set", "change"]:
				_err(l.number, "'while active' can only change feats or values (so they can be undone); found '%s'." % l.text)
			elif e.op == "set":
				_check_path(e.path, l.number)
			elif e.op == "change":
				_check_effect(e, l.number, id)
				if e.path not in Game.ATTRIBUTES.map(func(stat): return "player." + stat):
					_err(l.number, "Relative 'while active' modifiers currently support the six player attributes only.")


func _check_scavenge_rules() -> void:
	var definitions := db.all_of("scavenge_rules")
	for id in definitions:
		var d := db.get_def("scavenge_rules", id)
		_path = d.path
		if definitions.size() > 1:
			_err(d.line, "Only one scavenge_rules definition may be active across loaded packs.")
		var generic := db.typed_value("scavenge_rules", id, "generic")
		_need(generic, "event", d.fields.get("generic", d).line)
		if db.has(generic, "event") and not ContentDB.found_by(db.typed_value("event", generic, "found by")).scavenging:
			_err(d.fields.generic.line, "The generic find %s must be found by scavenging." % generic)
		if d.fields.has("target") and not d.fields.target.value.is_valid_int():
			_err(d.fields.target.line, "Target must be a whole number.")
		if d.fields.has("generic chance"):
			var parts: PackedStringArray = d.fields["generic chance"].value.split(" in ")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or int(parts[1]) < 1:
				_err(d.fields["generic chance"].line, "Generic chance is written 'N in M', for example '3 in 4'.")
		for field in ["start", "found", "failure", "only at"]:
			if d.fields.has(field):
				_check_text_field(d.fields[field].value, d.fields[field].line, id)


## The top bar (`== status_bar`): its meters and currency are player values.
func _check_status_bar() -> void:
	var defs: Dictionary = db.all_of("status_bar")
	if defs.size() > 1:
		var later: FscParser.Definition = db.get_def("status_bar", defs.keys()[1])
		_path = later.path
		_warn(later.line, "Only one status bar is shown: %s's." % defs.keys()[0])
	for id in defs:
		var d: FscParser.Definition = db.get_def("status_bar", id)
		_path = d.path
		for k in db._list(d, "meters"):
			_check_path("player." + str(k), d.fields.meters.line)
		if d.fields.has("currency"):
			_check_path("player." + d.fields.currency.value, d.fields.currency.line)
		for k in db._list(d, "sheet"):
			_check_path("player." + str(k), d.fields.sheet.line)


## Character creation (CreationSystem): its questions are menus, its free feats exist.
func _check_creation_rules() -> void:
	var definitions := db.all_of("creation_rules")
	for id in definitions:
		var d := db.get_def("creation_rules", id)
		_path = d.path
		if definitions.size() > 1:
			_err(d.line, "Only one creation_rules definition may be active across loaded packs.")
		for menu in db._list(d, "choices"):
			if not db.menus.has(menu):
				_err(d.fields.choices.line, "Choice '%s' is not a menu. Each choice is a '== menu' whose options are the answers." % menu)
		if d.fields.has("feats"):
			for line: FscParser.Line in d.fields.feats.children:
				if line.is_blank():
					continue
				var p := line.text.split(":", true, 1)
				if p.size() != 2:
					_err(line.number, "A free feat is written 'group: default_feat'.")
					continue
				var group := p[0].strip_edges()
				if not db.all_of("feat").keys().any(func(f): return db.typed_value("feat", f, "group") == group):
					_err(line.number, "No feat has group '%s'." % group)
				var feat := p[1].strip_edges()
				if feat != "":
					_need(feat, "feat", line.number)


func _check_survival_rules() -> void:
	var definitions := db.all_of("survival_rules")
	for id in definitions:
		var d := db.get_def("survival_rules", id)
		_path = d.path
		if definitions.size() > 1:
			_err(d.line, "Only one survival_rules definition may be active across loaded packs.")
		for field in ["starving hint at", "journal hint below", "anticipation within"]:
			if d.fields.has(field) and not d.fields[field].value.is_valid_int():
				_err(d.fields[field].line, "%s must be a whole number." % field.capitalize())
		if d.fields.has("natural healing when"):
			_check_condition_text(d.fields["natural healing when"].value, d.fields["natural healing when"].line, "survival_rules:" + id)
		if d.fields.has("sanity floor when"):
			_check_condition_text(d.fields["sanity floor when"].value, d.fields["sanity floor when"].line, "survival_rules:" + id)
		for field in ["starving hint", "morale normalized", "humanity loss", "journal hint", "rescue anticipation",
				"hunger death", "thirst death", "humanity ending", "rescue ending"]:
			if d.fields.has(field):
				_check_text_field(d.fields[field].value, d.fields[field].line, id)
		for field in ["hunger warnings", "thirst warnings", "humanity descriptions", "lust descriptions"]:
			if not d.fields.has(field):
				continue
			for line in d.fields[field].children:
				if line.is_blank():
					continue
				var pair: PackedStringArray = line.text.split(":", true, 1)
				if pair.size() != 2 or not pair[0].strip_edges().is_valid_int() or pair[1].strip_edges() == "":
					_err(line.number, "Use a whole-number threshold followed by text, for example '30: You're famished.'")
				else:
					_check_text_field(pair[1].strip_edges(), line.number, id)


## Captivities: numbers, conditions and texts of their fields.
func _check_captivity() -> void:
	for id in db.all_of("captivity"):
		var d := db.get_def("captivity", id)
		_path = d.path
		if d.fields.has("escape at"):
			var e := Expr.parse(d.fields["escape at"].value)
			if e.has("error"):
				_err(d.fields["escape at"].line, "Escape at: %s" % e.error)
			else:
				for p in Expr.paths(e):
					_check_path(p, d.fields["escape at"].line)
		if d.fields.has("climax at") and not d.fields["climax at"].value.is_valid_int():
			_err(d.fields["climax at"].line, "Climax at must be a whole number.")
		if d.fields.has("obliging when"):
			_check_condition_text(d.fields["obliging when"].value, d.fields["obliging when"].line, id)
		if d.fields.has("pause after each") and d.fields["pause after each"].value not in ["yes", "no"]:
			_err(d.fields["pause after each"].line, "Pause after each must be yes or no.")
		for field in ["status", "struggle label", "oblige label", "abide label", "endure label", "recover label"]:
			if d.fields.has(field):
				_check_text_field(d.fields[field].value, d.fields[field].line, id)
		if not d.fields.has("struggle"):
			_err(d.line, "A captivity needs at least 'struggle:'.")
		if d.fields.has("escape at") and not d.fields.has("escape"):
			_err(d.fields["escape at"].line, "With 'escape at', write 'escape:' for when the player breaks free.")
		if db.has(id, "scene"):
			_err(d.line, "A scene is also called '%s'; give the captivity its own ID so 'play %s' is not ambiguous." % [id, id])


## Heat definitions, the one heat policy, and forms' `heat:` fields.
## Companions (CompanionSystem): each character's companion: block and the rules.
func _check_companions() -> void:
	for id in db.all_of("character"):
		var d := db.get_def("character", id)
		if not d.fields.has("companion"):
			for f in ["summon", "dismiss", "companion attack"]:
				if d.fields.has(f):
					_path = d.path
					_err(d.fields[f].line, "%s: '%s' needs a companion: block." % [id, f])
			continue
		_path = d.path
		for p in CharacterSystem.pairs(d, "companion"):
			match p.key:
				"attacks with":
					if p.value not in ["fighting", "seduction"]:
						_err(p.line, "Attacks with is fighting or seduction.")
				"hit bonus":
					if not p.value.is_valid_int():
						_err(p.line, "Hit bonus must be a whole number.")
				"tamed":
					if p.value not in ["yes", "no"]:
						_err(p.line, "Tamed must be yes or no.")
				"stays when":
					_check_condition_text(p.value, p.line, "character:" + id)
				_:
					_err(p.line, "Unknown companion field '%s'. Allowed: attacks with, hit bonus, stays when, tamed." % p.key)
	var rules: Dictionary = db.all_of("companion_rules")
	if rules.size() > 1:
		for id in rules.keys().slice(1):
			var d := db.get_def("companion_rules", id)
			_path = d.path
			_warn(d.line, "Only one companion_rules is used (%s); this one is ignored." % rules.keys()[0])
	for id in rules:
		var d := db.get_def("companion_rules", id)
		_path = d.path
		for f in ["party size", "companion xp", "player xp cost", "level up at", "damage every", "dexterity every", "hit bonus"]:
			if d.fields.has(f):
				var e := Expr.parse(d.fields[f].value)
				if e.has("error"):
					_err(d.fields[f].line, "%s: %s." % [f.left(1).to_upper() + f.substr(1), e.error])
				else:
					for p in Expr.paths(e):
						_check_path(p, d.fields[f].line)
			if d.fields.has(f + " modifiers"):
				for l: FscParser.Line in d.fields[f + " modifiers"].children:
					if l.is_blank():
						continue
					if not ":" in l.text:
						_err(l.number, "A modifier is written 'condition: amount'.")
						continue
					var parts := l.text.rsplit(":", true, 1)
					_check_condition_text(parts[0].strip_edges(), l.number, "companion_rules:" + id)
					var amount := Expr.parse(CompanionSystem.amount_text(parts[1]))
					if amount.has("error"):
						_err(l.number, "Modifier amount: %s." % amount.error)
		for f in ["player xp cost when", "levels while"]:
			if d.fields.has(f):
				_check_condition_text(d.fields[f].value, d.fields[f].line, "companion_rules:" + id)


## Vore rules (VoreSystem): one per game; conditions, numbers with modifiers,
## the unbirth gestation as "A to B".
func _check_vore() -> void:
	var defs: Dictionary = db.all_of("vore_rules")
	for id in defs.keys().slice(1):
		var d := db.get_def("vore_rules", id)
		_path = d.path
		_warn(d.line, "Only one vore_rules is used (%s); this one is ignored." % defs.keys()[0])
	for id in defs:
		var d := db.get_def("vore_rules", id)
		_path = d.path
		for f in ["can vore when", "can unbirth when", "vore when", "unbirth when", "vore always when",
				"vore automatic when", "unbirth automatic when", "hard vore when"]:
			if d.fields.has(f):
				_check_condition_text(d.fields[f].value, d.fields[f].line, "vore_rules:" + id)
		for f in ["vore chance", "vore chance out of", "unbirth chance", "unbirth chance out of", "absorb above"]:
			if d.fields.has(f):
				var e := Expr.parse(d.fields[f].value)
				if e.has("error"):
					_err(d.fields[f].line, "%s: %s." % [f.left(1).to_upper() + f.substr(1), e.error])
				else:
					for p in Expr.paths(e):
						_check_path(p, d.fields[f].line)
		for f in ["vore chance modifiers", "unbirth chance modifiers"]:
			if not d.fields.has(f):
				continue
			for l: FscParser.Line in d.fields[f].children:
				if l.is_blank():
					continue
				if not ":" in l.text:
					_err(l.number, "A modifier is written 'condition: amount'.")
					continue
				var parts := l.text.rsplit(":", true, 1)
				_check_condition_text(parts[0].strip_edges(), l.number, "vore_rules:" + id)
				var amount := Expr.parse(CompanionSystem.amount_text(parts[1]))
				if amount.has("error"):
					_err(l.number, "Modifier amount: %s." % amount.error)
		if d.fields.has("unbirth gestation") and not RegEx.create_from_string("^\\d+( to \\d+)?$").search(d.fields["unbirth gestation"].value):
			_err(d.fields["unbirth gestation"].line, "Unbirth gestation is a number of turns or a range such as '8 to 16'.")
		if not d.fields.has("can vore when") and not d.fields.has("can unbirth when"):
			_warn(d.line, "Without 'can vore when' or 'can unbirth when' nobody can vore or unbirth.")
		if d.fields.has("own scene when"):
			_check_condition_text(d.fields["own scene when"].value, d.fields["own scene when"].line, "vore_rules:" + id)
	for id in db.all_of("creature"):
		var d := db.get_def("creature", id)
		_path = d.path
		for f in ["vore when", "hard vore when", "unbirth when"]:
			if d.fields.has(f):
				_check_condition_text(d.fields[f].value, d.fields[f].line, "creature:" + id)
				if not d.fields.has(f.trim_suffix(" when")):
					_warn(d.fields[f].line, "%s only matters with the creature's own '%s:' scene." % [f.capitalize(), f.trim_suffix(" when")])


## Level rules, feats offered on levels, interests and combat rules.
func _check_levels() -> void:
	for type in ["level_rules", "combat_rules", "hunt_rules", "infection_rules"]:
		var defs: Dictionary = db.all_of(type)
		for id in defs.keys().slice(1):
			var d := db.get_def(type, id)
			_path = d.path
			_warn(d.line, "Only one %s is used (%s); this one is ignored." % [type, defs.keys()[0]])
	# Infection rules: conditions, "N in M" chances and whole-number caps.
	for id in db.all_of("infection_rules"):
		var d := db.get_def("infection_rules", id)
		_path = d.path
		for name in d.field_order:
			var f: FscParser.Field = d.fields[name]
			if name == "source":
				continue
			if name.ends_with(" when"):
				_check_condition_text(f.value, f.line, "infection_rules:" + id)
			elif name.ends_with(" chance"):
				if not RegEx.create_from_string("^\\d+ in \\d+$").search(f.value):
					_err(f.line, "%s is written 'N in M'." % name.capitalize())
			elif not f.value.is_valid_int():
				_err(f.line, "%s must be a whole number." % name.capitalize())
	for id in db.all_of("combat_rules"):
		var d := db.get_def("combat_rules", id)
		_path = d.path
		if d.fields.has("creature chance") and not RegEx.create_from_string("^\\d+ in \\d+$").search(d.fields["creature chance"].value):
			_err(d.fields["creature chance"].line, "Creature chance is written 'N in M', such as 4 in 20.")
		if d.fields.has("creature chance modifiers"):
			for l: FscParser.Line in d.fields["creature chance modifiers"].children:
				if l.is_blank():
					continue
				var parts := l.text.rsplit(":", true, 1)
				if parts.size() != 2:
					_err(l.number, "Creature chance modifiers are 'condition: amount' lines.")
					continue
				_check_condition_text(parts[0].strip_edges(), l.number, "combat_rules:" + id)
		if d.fields.has("auto action"):
			_check_path(d.fields["auto action"].value, d.fields["auto action"].line)
		if d.fields.has("second fight when"):
			_check_condition_text(d.fields["second fight when"].value, d.fields["second fight when"].line, "combat_rules:" + id)
	for id in db.all_of("hunt_rules"):
		var d := db.get_def("hunt_rules", id)
		_path = d.path
		if d.fields.has("target weight"):
			var e := Expr.parse(d.fields["target weight"].value)
			if e.has("error"):
				_err(d.fields["target weight"].line, "Target weight: %s." % e.error)
			else:
				for p in Expr.paths(e):
					_check_path(p, d.fields["target weight"].line)
		if d.fields.has("target weight modifiers"):
			for l: FscParser.Line in d.fields["target weight modifiers"].children:
				if l.is_blank():
					continue
				var parts := l.text.rsplit(":", true, 1)
				if parts.size() != 2:
					_err(l.number, "Target weight modifiers are 'condition: amount' lines.")
					continue
				_check_condition_text(parts[0].strip_edges(), l.number, "hunt_rules:" + id)
				var amount := Expr.parse(CompanionSystem.amount_text(parts[1]))
				if amount.has("error"):
					_err(l.number, "Target weight modifier: %s." % amount.error)
		for f in ["others when", "other skipped when", "hunt when"]:
			if d.fields.has(f):
				_check_condition_text(d.fields[f].value, d.fields[f].line, "hunt_rules:" + id)
	for id in db.all_of("command"):
		var cd := db.get_def("command", id)
		_path = cd.path
		if not cd.fields.has("play"):
			_err(cd.line, "A command needs 'play:', the scene it runs.")
		if cd.fields.has("when"):
			_check_condition_text(cd.fields.when.value, cd.fields.when.line, "command:" + id)
	for id in db.all_of("game_mode"):
		var gm := db.get_def("game_mode", id)
		_path = gm.path
		for f in ["exploration bonus", "encounter bonus", "scavenge bonus", "carry bonus", "loot bonus"]:
			if gm.fields.has(f) and not gm.fields[f].value.is_valid_int():
				_err(gm.fields[f].line, "%s must be a whole number." % f.capitalize())
	for id in db.all_of("level_rules"):
		var d := db.get_def("level_rules", id)
		_path = d.path
		if not d.fields.has("xp needed"):
			_err(d.line, "Level rules need 'xp needed:', the experience the next level costs (an expression such as (player.level + 1) * 10).")
		else:
			var e := Expr.parse(d.fields["xp needed"].value)
			if e.has("error"):
				_err(d.fields["xp needed"].line, "Xp needed: %s." % e.error)
			else:
				for p in Expr.paths(e):
					_check_path(p, d.fields["xp needed"].line)
		if d.fields.has("xp needed modifiers"):
			for l: FscParser.Line in d.fields["xp needed modifiers"].children:
				if l.is_blank():
					continue
				if not ":" in l.text:
					_err(l.number, "A modifier is written 'condition: amount'.")
					continue
				var parts := l.text.rsplit(":", true, 1)
				_check_condition_text(parts[0].strip_edges(), l.number, "level_rules:" + id)
				var amount := Expr.parse(CompanionSystem.amount_text(parts[1]))
				if amount.has("error"):
					_err(l.number, "Modifier amount: %s." % amount.error)
		if d.fields.has("levels when"):
			_check_condition_text(d.fields["levels when"].value, d.fields["levels when"].line, "level_rules:" + id)
	for id in db.all_of("feat"):
		var d := db.get_def("feat", id)
		_path = d.path
		if d.fields.has("available when"):
			_check_condition_text(d.fields["available when"].value, d.fields["available when"].line, "feat:" + id)
			if not d.fields.has("group"):
				_warn(d.fields["available when"].line, "Available when only matters for a feat with a group that levels offer.")
		if d.fields.has("group") and not d.fields.group.value.is_valid_identifier():
			_err(d.fields.group.line, "A feat group is one word, such as fun.")
	for id in db.all_of("interest"):
		var d := db.get_def("interest", id)
		_path = d.path
		if d.fields.has("default") and d.fields.default.value not in ["yes", "no"]:
			_err(d.fields.default.line, "Default must be yes or no.")
	for id in db.all_of("combat_rules"):
		var d := db.get_def("combat_rules", id)
		_path = d.path
		for f in ["harder rolls when", "level limit off when"]:
			if d.fields.has(f):
				_check_condition_text(d.fields[f].value, d.fields[f].line, "combat_rules:" + id)
		if d.fields.has("level limit"):
			var le := Expr.parse(d.fields["level limit"].value)
			if le.has("error"):
				_err(d.fields["level limit"].line, "Level limit: %s." % le.error)
			else:
				for p in Expr.paths(le):
					_check_path(p, d.fields["level limit"].line)
		if d.fields.has("unarmed damage") and (not d.fields["unarmed damage"].value.is_valid_int() or int(d.fields["unarmed damage"].value) < 0):
			_err(d.fields["unarmed damage"].line, "Unarmed damage must be a whole number of 0 or more.")
		for f in ["unarmed attack", "player hits", "flee", "flee fails"]:
			if d.fields.has(f):
				var t := TextTemplate.compile(d.fields[f].value)
				if t.has("error"):
					_err(d.fields[f].line, "%s: %s" % [f.capitalize(), t.error])
				else:
					_check_template(t, d.fields[f].line, "combat_rules:" + id)


func _check_heat() -> void:
	for id in db.all_of("heat"):
		var d := db.get_def("heat", id)
		_path = d.path
		for field in ["cycle", "duration"]:
			if d.fields.has(field) and (not d.fields[field].value.is_valid_int() or int(d.fields[field].value) < 1):
				_err(d.fields[field].line, "%s is a positive whole number of days." % field.capitalize())
		if int(db.typed_value("heat", id, "duration", "1")) > int(db.typed_value("heat", id, "cycle", "7")):
			_err(d.line, "A heat cannot last longer than its cycle (the same number means always in heat).")
		for field in ["female", "mpreg"]:
			if d.fields.has(field) and d.fields[field].value not in ["yes", "no"]:
				_err(d.fields[field].line, "%s must be yes or no." % field.capitalize())
	var policies := db.all_of("heat_rules")
	for id in policies:
		var d := db.get_def("heat_rules", id)
		_path = d.path
		if policies.size() > 1:
			_err(d.line, "Only one heat_rules definition may be active across loaded packs.")
		if d.fields.has("default"):
			_need(d.fields.default.value, "heat", d.fields.default.line)
		for field in ["female when", "mpreg when", "off when", "intense when"]:
			if d.fields.has(field):
				_check_condition_text(d.fields[field].value, d.fields[field].line, id)
		for field in ["intense lengthens", "intense quickens"]:
			if d.fields.has(field) and RegEx.create_from_string("^\\d+ in [1-9]\\d*$").search(d.fields[field].value) == null:
				_err(d.fields[field].line, "%s is a chance written 'N in M'." % field.capitalize())
	for id in db.all_of("form"):
		var d := db.get_def("form", id)
		if d.fields.has("heat") and d.fields.heat.value != "none":
			_path = d.path
			_need(d.fields.heat.value, "heat", d.fields.heat.line)


const _CHANCE := "^\\d+ in [1-9]\\d*$"


## Pregnancy (PregnancySystem): one policy, its conditions, odds and lists.
func _check_pregnancy() -> void:
	var policies := db.all_of("pregnancy_rules")
	for id in policies:
		var d := db.get_def("pregnancy_rules", id)
		_path = d.path
		if policies.size() > 1:
			_err(d.line, "Only one pregnancy_rules definition may be active across loaded packs.")
		for field in ["female when", "male when", "blocked when", "ask when", "single child when", "child like father when",
				"child like mother when", "child like mother at birth when", "feral when", "sire when"]:
			if d.fields.has(field):
				_check_condition_text(d.fields[field].value, d.fields[field].line, id)
		for field in ["odds", "self odds", "sire odds", "albino", "melanism"]:
			if d.fields.has(field) and RegEx.create_from_string(_CHANCE).search(d.fields[field].value) == null:
				_err(d.fields[field].line, "%s is a chance written 'N in M'." % field.capitalize())
		for field in ["gestation", "sire turns"]:
			if d.fields.has(field) and RegEx.create_from_string("^[1-9]\\d*(?: to [1-9]\\d*)?$").search(d.fields[field].value) == null:
				_err(d.fields[field].line, "%s is a number of turns, or a range such as '24 to 48'." % field.capitalize())
		if d.fields.has("extra children"):
			for c in d.fields["extra children"].value.split(",", false):
				if not c.strip_edges().is_valid_int() or int(c) < 0 or int(c) > 100:
					_err(d.fields["extra children"].line, "Extra children lists percent chances (0 to 100), one per extra child: '1, 3, 5'.")
					break
		if d.fields.has("most children") and (not d.fields["most children"].value.is_valid_int() or int(d.fields["most children"].value) < 1):
			_err(d.fields["most children"].line, "Most children is a positive whole number.")
		if d.fields.has("sire anal tag"):
			_need(d.fields["sire anal tag"].value, "tag", d.fields["sire anal tag"].line)
		for field in ["odds modifiers", "extra child bonus", "sire odds modifiers", "quickens", "fathers", "child genders"]:
			if not d.fields.has(field):
				continue
			for line: FscParser.Line in d.fields[field].children:
				var t := line.text.strip_edges()
				if t == "":
					continue
				var k := t.rfind(":")
				if k < 0:
					_err(line.number, "%s: write 'condition: value' on each line." % field.capitalize())
					continue
				var left := t.substr(0, k).strip_edges()
				var right := t.substr(k + 1).strip_edges()
				match field:
					"quickens":
						_check_condition_text(left, line.number, id)
						if RegEx.create_from_string(_CHANCE).search(right) == null:
							_err(line.number, "Quickens: the chance after ':' is written 'N in M'.")
					"fathers":
						if not db.has(left, "form") and not db.has(left, "creature"):
							_err(line.number, "Fathers: '%s' is neither a form nor a creature." % left)
						_check_condition_text(right, line.number, id)
					"child genders":
						if left not in CREATURE_GENDERS and left not in ["trans male", "trans female"]:
							_err(line.number, "Child genders: unknown gender '%s'." % left)
						var m := RegEx.create_from_string("^(\\d+)(?: if (.+))?$").search(right)
						if m == null:
							_err(line.number, "Child genders: write 'gender: weight' or 'gender: weight if condition'.")
						elif m.get_string(2) != "":
							_check_condition_text(m.get_string(2), line.number, id)
					_:
						_check_condition_text(left, line.number, id)
						if not right.trim_prefix("+").is_valid_int():
							_err(line.number, "%s: the number after ':' is a whole number such as -3 or +1." % field.capitalize())
	for id in db.all_of("form"):
		var d := db.get_def("form", id)
		if d.fields.has("offspring gender"):
			_path = d.path
			var m := RegEx.create_from_string("^(\\w+(?: \\w+)?) (\\d+) in ([1-9]\\d*)$").search(d.fields["offspring gender"].value)
			if m == null or (m.get_string(1) not in CREATURE_GENDERS and m.get_string(1) not in ["trans male", "trans female"]):
				_err(d.fields["offspring gender"].line, "Offspring gender is a gender and a chance, such as 'male 9 in 10'.")


func _check_text_field(text: String, line: int, owner: String) -> void:
	var template := TextTemplate.compile(text)
	if template.has("error"):
		_err(line, template.error)
	else:
		_check_template(template, line, owner)


func _check_rest_rules() -> void:
	var definitions := db.all_of("rest_rules")
	for id in definitions:
		var d := db.get_def("rest_rules", id)
		_path = d.path
		if definitions.size() > 1:
			_err(d.line, "Only one rest_rules definition may be active across loaded packs.")
		_need(db.typed_value("rest_rules", id, "condition"), "condition", d.fields.get("condition", d).line)
		if d.fields.has("off when"):
			_check_condition_text(d.fields["off when"].value, d.fields["off when"].line, "rest_rules:" + id)
		if d.fields.has("interruption when"):
			_check_condition_text(d.fields["interruption when"].value, d.fields["interruption when"].line, "rest_rules:" + id)
		if d.fields.has("interruption chance") and not RegEx.create_from_string("^\\d+ in \\d+$").search(d.fields["interruption chance"].value):
			_err(d.fields["interruption chance"].line, "Interruption chance is written 'N in M'.")
		if d.fields.has("interruption chance modifiers"):
			for l: FscParser.Line in d.fields["interruption chance modifiers"].children:
				if l.is_blank():
					continue
				var mp := l.text.rsplit(":", true, 1)
				if mp.size() != 2 or not mp[1].replace(" ", "").is_valid_int():
					_err(l.number, "Interruption chance modifiers are 'condition: + n' lines.")
				else:
					_check_condition_text(mp[0].strip_edges(), l.number, "rest_rules:" + id)
		for field in ["duration", "fresh below", "fresh fatigue", "exhausted recovery", "hammock fresh fatigue", "hammock recovery", "collapse at", "collapse fatigue", "collapse turns"]:
			if d.fields.has(field):
				var f: FscParser.Field = d.fields[field]
				if not f.value.is_valid_int():
					_err(f.line, "%s must be a whole number." % field.capitalize())
				elif field not in ["fresh fatigue", "hammock fresh fatigue", "collapse fatigue"] and int(f.value) < 1:
					_err(f.line, "%s must be positive." % field.capitalize())
		if int(db.typed_value("rest_rules", id, "collapse fatigue", "3")) + int(db.typed_value("rest_rules", id, "collapse turns", "2")) >= int(db.typed_value("rest_rules", id, "collapse at", "12")):
			_err(d.line, "Collapse fatigue plus forced turns must stay below the collapse threshold to avoid repeated collapses.")
		for field in ["statuses", "warnings"]:
			var seen: Array = []
			if not d.fields.has(field):
				continue
			for line in d.fields[field].children:
				if line.is_blank():
					continue
				var pair: PackedStringArray = line.text.split(":", true, 1)
				if pair.size() != 2 or not pair[0].strip_edges().is_valid_int() or pair[1].strip_edges() == "":
					_err(line.number, "Use a numeric fatigue threshold followed by text, for example '5: Spent'.")
					continue
				var threshold := int(pair[0].strip_edges())
				if threshold in seen:
					_err(line.number, "This fatigue threshold is already defined.")
				seen.append(threshold)
				if field == "warnings":
					var template := TextTemplate.compile(pair[1].strip_edges())
					if template.has("error"):
						_err(line.number, template.error)
					else:
						_check_template(template, line.number, id)
	for type in ["item", "location"]:
		for d: FscParser.Definition in db.all_of(type).values():
			_path = d.path
			if d.fields.has("rest") and not RestSystem.QUALITY.has(d.fields.rest.value):
				_err(d.fields.rest.line, "Rest quality must be none, rough, bed, cot or hammock.")
			for field in ["carried rest text", "ground rest text", "rest text"]:
				if d.fields.has(field):
					var template := TextTemplate.compile(d.fields[field].value)
					if template.has("error"):
						_err(d.fields[field].line, template.error)
					else:
						_check_template(template, d.fields[field].line, d.id)


## Map positions: "x, y" in whole numbers, inside the region's map grid,
## and not on top of another place in the same region.
func _check_map_positions() -> void:
	var grid_re := RegEx.create_from_string("^(\\d+) x (\\d+)$")
	var grids := {}
	for id in db.all_of("region"):
		var d: FscParser.Definition = db.get_def("region", id)
		if d.fields.has("map grid"):
			var m := grid_re.search(d.fields["map grid"].value)
			if m == null:
				_path = d.path
				_err(d.fields["map grid"].line, "A map grid is written 'width x height', for example 'map grid: 12 x 12'.")
			else:
				grids[id] = Vector2i(int(m.get_string(1)), int(m.get_string(2)))
	var taken := {}  ## "region:x,y" -> location id
	for id in db.all_of("location"):
		var d: FscParser.Definition = db.get_def("location", id)
		if not d.fields.has("map"):
			continue
		_path = d.path
		var line: int = d.fields.map.line
		var parts: PackedStringArray = d.fields.map.value.split(",")
		if parts.size() != 2 or not parts[0].strip_edges().is_valid_int() or not parts[1].strip_edges().is_valid_int():
			_err(line, "A map position is written 'x, y' in whole numbers, for example 'map: 5, 7'.")
			continue
		var region := db.typed_value("location", id, "region")
		if region == "":
			_err(line, "%s has a map position but no region; the map shows one region at a time." % id)
			continue
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		if grids.has(region) and (pos.x < 0 or pos.y < 0 or pos.x >= grids[region].x or pos.y >= grids[region].y):
			_warn(line, "Map position %d, %d is outside the %d x %d grid of region %s." % [pos.x, pos.y, grids[region].x, grids[region].y, region])
		var key := "%s:%d,%d" % [region, pos.x, pos.y]
		if taken.has(key):
			_warn(line, "%s is drawn on top of %s at map position %d, %d." % [id, taken[key], pos.x, pos.y])
		else:
			taken[key] = id


func _has_exit_to(from: String, to: String) -> bool:
	var d := db.get_def("location", from)
	var exits: FscParser.Field = d.fields.get("exits", null) if d != null else null
	if exits == null:
		return false
	for l in exits.children:
		if not l.is_blank() and ":" in l.text and l.text.split(":", true, 1)[1].split(",")[0].strip_edges() == to:
			return true
	return false


# --- Scripts ----------------------------------------------------------------

func _check_programs() -> void:
	var pids: Array = []
	for type in ["scene", "text"]:
		pids.append_array(_ids(type))
	for type in db.SCHEMA:
		var schema: Dictionary = db.SCHEMA[type]
		for id in db.all_of(type):
			var d: FscParser.Definition = db.get_def(type, id)
			for name in d.field_order:
				if schema.get(name, "") == "script":
					pids.append("%s:%s#%s" % [type, id, name])
	for key in db.extra_scripts:
		if key not in pids:
			pids.append(key)
	for menu_id in db.menus:
		var menu: Dictionary = db.menus[menu_id]
		for i in menu.options.size():
			pids.append("%s@%d" % [menu_id, i])
			var o: Dictionary = menu.options[i]
			if o.condition != "":
				_path = menu.def.path
				_check_condition_text(o.condition, o.line, menu_id)
	for pid in pids:
		var prog := db.program(pid)
		if prog == null:
			continue
		_path = prog.path
		var unqualified: String = pid.get_slice(":", 1) if ":" in pid else pid
		var owner: String = unqualified.split("#")[0].split("@")[0]
		for ins in prog.code:
			_check_instruction(ins, owner)
			var type: String = pid.get_slice(":", 0) if ":" in pid else db.type_of(owner)
			var field := str(pid).get_slice("#", 1)
			# A creature's combat scripts, and the options of its `attacks:` menu.
			var combat_script: bool = (type == "creature" and field in COMBAT_SCRIPTS) or (type == "character" and field == "companion attack") or \
				(str(pid).contains(".attacks@") and db.has(str(pid).get_slice(".attacks@", 0), "creature"))
			if (type == "location" and field in ["description", "presence", "scent"]) or (type == "quest" and field == "journal") or combat_script or (type == "condition" and field == "rest refusal") or type in ["door", "rest_rules"]:
				# A creature's combat scripts may also change values as they land (a roll, lust, a blow).
				var effects_ok: bool = combat_script and field not in ["escape", "struggle"]
				if ins.op == "goto":
					# A text field may hand over to a scene made of text and conditions only.
					var target := db.program(ins.target)
					if target != null:
						for t_ins in target.code:
							if t_ins.op not in ["text", "return", "jump", "unless"] and not (effects_ok and _simple_effect(t_ins)):
								_err(ins.line, "This description hands over to '%s', which must contain text and conditions only (line %d does more)." % [ins.target, t_ins.line])
								break
				elif effects_ok and (_simple_effect(ins) or _combat_effect(ins)):
					pass
				elif effects_ok and ins.op == "play":
					# A combat script may play a scene made of what it may hold itself.
					var bad := _combat_unsafe(str(ins.target), 0)
					if bad != "":
						_err(ins.line, "A fight's script can only play scenes of text, conditions and value or fight effects ('%s' %s)." % [ins.target, bad])
				elif ins.op not in ["text", "return", "jump", "unless"]:
					_err(ins.line, "This description can contain text and conditions only; move actions and choices into a scene.")
			# A text snippet is said inside other text: text, conditions and simple effects only.
			if type == "text" and ins.op not in ["text", "return", "jump", "unless"] and not _simple_effect(ins):
				_err(ins.line, "A text snippet can contain text, conditions and value changes only; make it a scene to do more.")
			# A creature's encounter plays as a scene before its fight: anything but another fight.
			if type == "creature" and field == "encounter" and ins.op == "fight":
				_err(ins.line, "An encounter plays just before its fight; it cannot start another fight.")


## A creature's scripts that run during its turn in a fight.
const COMBAT_SCRIPTS := ["attack", "grapple", "escape", "struggle", "each round", "before attack", "after attack", "miss",
	"hump", "pounce", "breath warning", "breath direct", "breath partial", "breath miss", "fight starts"]


## Why a scene played from a fight's script cannot run there, or "" when it can.
func _combat_unsafe(pid: String, depth: int) -> String:
	var prog := db.program(pid)
	if prog == null or depth > 8:
		return ""
	for ins in prog.code:
		if ins.op in ["text", "return", "jump", "unless"] or _simple_effect(ins) or _combat_effect(ins):
			continue
		if ins.op in ["play", "goto"] and str(ins.target) not in ["back", "end"]:
			var inner := _combat_unsafe(str(ins.target), depth + 1)
			if inner != "":
				return inner
			continue
		return "does more at line %d" % ins.line
	return ""


## Effects only a fight's scripts can run: the creature's blows and the result.
func _combat_effect(ins: Dictionary) -> bool:
	return ins.op == "effect" and not ins.effect.has("error") and ins.effect.op in [
		"enemy_attack", "enemy_strike", "fight_result", "player_move", "creature_number", "creature_change", "sex"]


## Effects a text can run while it is shown (an attack landing): values, survival
## numbers, feats and conditions; nothing that moves the player or starts a scene.
func _simple_effect(ins: Dictionary) -> bool:
	return ins.op == "effect" and not ins.effect.has("error") and ins.effect.op in [
		"set", "set_time", "change", "survival", "feat", "condition", "meter", "infect",
		"list_add", "list_remove", "list_remove_entry", "list_clear", "list_sort", "child_random", "new_child"]


func _check_instruction(ins: Dictionary, owner: String) -> void:
	match ins.op:
		"goto", "play":
			_check_target(ins.target, ins.line)
		"fight":
			if ins.creature != "random" and not db.has(ins.creature, "creature"):
				_err(ins.line, "Creature '%s' does not exist.%s" % [ins.creature, _suggest(ins.creature, _ids("creature"))])
			elif ins.variant != "" and ins.variant not in VariantSystem.variants(db, ins.creature):
				_err(ins.line, "%s has no variant '%s'.%s" % [ins.creature, ins.variant, _variant_list(ins.creature)])
			for c: String in ins.get("creatures", []).slice(1):
				if c != "random" and not db.has(c, "creature"):
					_err(ins.line, "Creature '%s' does not exist.%s" % [c, _suggest(c, _ids("creature"))])
			if ins.has("times"):
				_check_expr(ins.times, ins.line)
		"show":
			if not _images.has(ins.image):
				_warn(ins.line, "Image '%s' was not found in any pack's images folder." % ins.image)
		"effect":
			if not ins.effect.has("error"):
				_check_effect(ins.effect, ins.line, owner)
		"text":
			if not ins.text.has("error"):
				_check_template(ins.text, ins.line, owner)
		"unless":
			if not ins.cond.has("error"):
				_check_condition(ins.cond, ins.line, owner)
		"choices":
			for o in ins.options:
				if not o.cond.is_empty() and not o.cond.has("error"):
					_check_condition(o.cond, o.line, owner)
				if not o.label.has("error"):
					_check_template(o.label, o.line, owner)


func _check_target(target: String, line: int) -> void:
	if target.begins_with("@picked#") or db.has(target, "captivity"):
		return
	if target in SPECIAL_TARGETS or db.menus.has(target) or db.has(target, "scene") or db.has(target, "text"):
		return
	if "#" in target and db.program(target) != null:
		return
	var known: Array = _ids("scene") + db.menus.keys()
	_err(line, "There is no scene or menu called '%s'.%s" % [target, _suggest(target, known)])


func _check_effect(e: Dictionary, line: int, owner: String) -> void:
	if e.op not in ["set", "set_time", "extend_game", "change", "survival", "give", "take", "take_all", "feat", "trait", "companion", "quest",
			"outcome", "resolve", "activate", "deactivate", "move", "lives_at", "discover", "forget", "use_item", "go", "spend", "sex",
			"condition", "cancel_use", "ending", "infect", "transform", "reset_human", "schedule", "wear", "remove",
			"wield", "unwield", "resize", "give_one", "meter", "infects_as", "creature_change", "no_fight",
			"end_heat", "extend_heat", "drive_heat", "reset_heat", "set_level", "pick", "end_captivity", "form_sex", "grow", "continue_moving",
			"impregnate", "accept_pregnancy", "give_birth", "record_child", "each_child", "end_pregnancy", "pregnancy_faster",
			"creature_number", "enemy_attack", "enemy_strike", "fight_result", "player_move", "put", "remove_from", "item_strain",
			"trigger_ending", "end_state", "ending_reason", "ending_flag", "exclude_endings",
			"tame", "summon", "dismiss", "cancel_companion", "companion_level", "send_children", "check_level", "choose_feat", "ask",
			"vore", "absorb_enemy_stat", "infect_enemy", "unbirth_pregnancy", "sex_change", "form_number", "change_exit",
			"unresolve", "character_image", "character_pronouns", "new_child", "child_random", "list_add", "list_remove", "list_remove_entry", "list_clear", "list_sort", "lock"]:
		_err(line, "Effect '%s' is recognized by the format but is not implemented yet." % e.op)
		return
	match e.op:
		"ask" when e.get("number", false):
			_check_path(e.path, line)
			var kind: String = db.values.get(e.path, {}).get("kind", "")
			if kind != "number" and not (kind == "" and e.path.begins_with("player.")):
				_err(line, "~ ask ... as number stores a number: '%s' must be a number value." % e.path)
			for bound in ["low", "high"]:
				if e.has(bound):
					_check_expr(e[bound], line)
			_check_template(e.prompt, line, "")
		"ask":
			_check_path(e.path, line)
			if e.path.begins_with("player.") and not db.values.has(e.path):
				_err(line, "~ ask stores text: give it a declared text value, not the player value '%s'." % e.path)
			_check_template(e.prompt, line, "")
		"list_add", "list_remove", "list_remove_entry", "list_clear", "list_sort":
			_check_list(e.path, line)
			for item: Dictionary in e.get("items", []):
				_check_expr(item, line)
		"lock":
			_need(e.door, "door", line)
		"unbirth_pregnancy" when e.get("creature", "") != "":
			if not db.has(e.creature, "creature") and not db.has(e.creature, "form"):
				_err(line, "'%s' is neither a creature nor a form to carry.%s" % [e.creature, _suggest(e.creature, _ids("creature"))])
		"character_pronouns":
			_need(e.who, "character", line)
		"character_image":
			_need(e.who, "character", line)
			if e.image != "default" and not _images.has(e.image):
				_warn(line, "Image '%s' was not found in any pack's images folder; a placeholder is shown." % e.image)
		"choose_feat":
			if not db.all_of("feat").keys().any(func(f): return db.typed_value("feat", f, "group") == e.group):
				_err(line, "No feat has group '%s'." % e.group)
		"companion_level" when e.who == "player":
			pass
		"tame", "summon", "dismiss", "companion_level":
			_need(e.who, "character", line)
			if db.has(e.who, "character") and not db.get_def("character", e.who).fields.has("companion"):
				_err(line, "%s has no companion: block, so it cannot follow the player." % e.who)
		"trigger_ending":
			_need(e.ending, "ending", line)
		"impregnate":
			if e.father not in ["", "random"] and not db.has(e.father, "creature") and not db.has(e.father, "form"):
				_err(line, "'%s' is neither a creature nor a form to father a child." % e.father)
			if e.kind == "self" and e.father != "":
				_err(line, "A self-impregnation has no father: leave out 'by %s'." % e.father)
		"each_child":
			_need(e.scene, "scene", line)
		"form_sex":
			_need(e.form, "form", line)
		"form_number":
			_need(e.form, "form", line)
			for p in Expr.paths(e.value):
				_check_path(p, line)
		"sex_change":
			if e.form != "" and not db.has(e.form, "creature") and not db.has(e.form, "form"):
				_err(line, "'%s' is neither a creature nor a form for the %s change to follow.%s" % [e.form, e.what, _suggest(e.form, _ids("form"))])
		"change_exit":
			_need(e.place, "location", line)
			if e.to != "":
				_need(e.to, "location", line)
		"pick":
			if e.tag != "":
				_need(e.tag, "tag", line)
			if e.zone != "" and e.zone != "anywhere":
				_need(e.zone, "zone", line)
			for c in e.favoring:
				_need(c, "creature", line)
		"set_level":
			if not db.levels.has(e.level):
				_err(line, "Level '%s' does not exist.%s" % [e.level, _suggest(e.level, db.levels.keys())])
			elif e.option not in db.levels[e.level].options:
				_err(line, "'%s' is not an option of level %s. Options: %s." % [e.option, e.level, ", ".join(db.levels[e.level].options)])
		"creature_number":
			_need(e.creature, "creature", line)
		"put", "remove_from":
			_need(e.item, "item", line)
			if e.place != "here":
				_need(e.place, "location", line)
		"item_strain":
			_need(e.item, "item", line)
			if e.form != "nothing":
				_need(e.form, "form", line)
		"enemy_attack", "enemy_strike", "fight_result":
			if not db.has(owner, "creature") and not (owner.ends_with(".attacks") and db.has(owner.trim_suffix(".attacks"), "creature")):
				_warn(line, "'%s' only works during a fight (a creature's combat scripts or attacks)." % e.op.replace("_", " "))
		"creature_change":
			_need(e.creature, "creature", line)
			if e.field == "loot" and e.value != "none":
				var loot: PackedStringArray = e.value.split(" ", false)
				if loot.size() != 2 or not loot[1].ends_with("%") or not loot[1].trim_suffix("%").is_valid_int():
					_err(line, "Loot is written 'item_id N%' or 'none'.")
				else:
					_need(loot[0], "item", line)
			elif e.field == "special":
				var problem := _special_problem(e.value)
				if problem != "":
					_err(line, problem)
			elif e.field == "strike with" and e.value not in CombatSystem.ATTRIBUTES:
				_err(line, "Strike with names an attribute: %s." % ", ".join(CombatSystem.ATTRIBUTES))
			elif e.field == "infectious" and e.value not in ["yes", "no"]:
				_err(line, "A creature is infectious yes or no.")
			elif e.field == "name known" and e.value not in ["yes", "no"]:
				_err(line, "A creature's name is known yes or no.")
			elif e.field == "name known" and db.typed_value("creature", e.creature, "personal name") == "":
				_err(line, "%s has no 'personal name:' to be known by." % e.creature)
			elif e.field == "variant" and e.value not in VariantSystem.variants(db, e.creature):
				_err(line, "%s has no variant '%s'.%s" % [e.creature, e.value, _variant_list(e.creature)])
			elif e.field == "gender" and e.value not in CREATURE_GENDERS:
				_err(line, "A creature's gender is one of: %s." % ", ".join(CREATURE_GENDERS))
			elif e.field == "found in" and e.value != "nowhere":
				for zone in e.value.split(","):
					_need(zone.strip_edges(), "zone", line)
		"infects_as":
			if e.creature != "":
				_need(e.creature, "creature", line)
		"sex":
			if e.act not in SEX_ACTS:
				_err(line, "Unknown sex act '%s'. Acts: %s." % [e.act, ", ".join(SEX_ACTS)])
		"schedule":
			_need(e.scene, "scene", line)
		"meter":
			_need(e.meter, "meter", line)
		"give_one":
			for it in e.items:
				_need(it, "item", line)
		"wear", "remove":
			_need(e.item, "item", line)
			if db.has(e.item, "item") and not db.get_def("item", e.item).fields.has("equipment"):
				_err(line, "'%s' can't be worn: it has no equipment field." % e.item)
		"wield":
			_need(e.item, "item", line)
			if db.has(e.item, "item") and not db.get_def("item", e.item).fields.has("weapon"):
				_err(line, "'%s' can't be wielded: it has no weapon field." % e.item)
		"give", "take", "take_all":
			if e.get("item_path", "") != "":
				# The value must be a state list whose states are all items.
				_check_path(e.item_path, line)
				var decl: Dictionary = db.values.get(e.item_path, {})
				if decl.get("kind", "") != "states":
					_err(line, "%s must be declared with item names as its states, for example 'item: food, water_bottle'." % e.item_path)
				else:
					for st in decl.states:
						if not db.has(st, "item"):
							_err(line, "State '%s' of %s is not an item." % [st, e.item_path])
			else:
				_need(e.item, "item", line)
		"quest":
			if not db.quests.has(e.quest):
				_err(line, "Quest '%s' does not exist.%s" % [e.quest, _suggest(e.quest, db.quests.keys())])
			elif e.stage not in db.quests[e.quest].stages:
				_err(line, "'%s' is not a stage of quest %s. Stages: %s." % [e.stage, e.quest, ", ".join(db.quests[e.quest].stages)])
		"outcome":
			# A scene named after an event ("pure_pool.play") belongs to that event.
			var event: String = e.get("event", "")
			if event == "":
				event = owner if db.has(owner, "event") else owner.split(".")[0]
			elif not db.has(event, "event"):
				_err(line, "Event '%s' does not exist.%s" % [event, _suggest(event, _ids("event"))])
				return
			var outs: Array = db.values.get("%s.outcome" % event, {}).get("states", [])
			owner = event
			if outs.is_empty():
				_warn(line, "'outcome %s' is used outside an event's own scene; it is recorded only when an event is running." % e.outcome)
			elif e.outcome not in outs:
				_err(line, "'%s' is not an outcome of event %s. Outcomes: %s." % [e.outcome, owner, ", ".join(outs.slice(1))])
		"move", "lives_at":
			if e.who != "player":
				_need(e.who, "character", line)
			if not (e.op == "move" and e.who != "player" and e.place == "nowhere"):
				_need(e.place, "location", line)
		"infect", "transform":
			if e.get("part", "") == "" and e.form != "@picked":
				_need(e.form, "form", line)
		"discover", "go", "forget":
			_need(e.place, "location", line)
		"use_item":
			_need(e.item, "item", line)
		"companion":
			_need(e.who, "character", line)
		"condition":
			_need(e.condition, "condition", line)
		"activate", "deactivate", "unresolve":
			_need(e.event, "event", line)
		"resolve":
			if e.event != "":
				_need(e.event, "event", line)
		"extend_game":
			for p in Expr.paths(e.by):
				_check_path(p, line)
		"set_time":
			_check_path(e.path, line)
			if db.values.get(e.path, {}).get("kind", "") != "time":
				_err(line, "'%s' is not a time value; only time values can be set to some turns ago or in some turns." % e.path)
			for p in Expr.paths(e.by):
				_check_path(p, line)
		"set", "change":
			_check_path(e.path, line)
			if db.values.get(e.path, {}).get("kind", "") == "list":
				_err(line, "%s is a list: change it with ~ add, ~ remove, ~ clear or ~ sort." % e.path)
			if e.op == "set":
				_check_set_value(e.path, e.value, line)
				_check_expr(e.value, line)
				for bound in e.get("range", []):
					_check_expr(bound, line)
			elif e.amount.has("value"):
				_check_expr(e.amount.value, line)
		"survival":
			if e.amount.has("value"):
				for p in Expr.paths(e.amount.value):
					_check_path(p, line)


## The value paths in an expression exist, and those read as lists (`entry 1 of x.list`) are lists.
func _check_expr(node: Dictionary, line: int) -> void:
	for p in Expr.paths(node):
		_check_path(p, line)
	for p in Expr.list_paths(node):
		_check_list(p, line)


## A value declared as a list (`name: list`).
func _check_list(path: String, line: int) -> void:
	_check_path(path, line)
	if db.values.has(path) and db.values[path].get("kind", "") != "list":
		_err(line, "%s is not a list. Declare it as 'name: list' to add entries to it." % path)


func _need(id: String, type: String, line: int) -> void:
	if not db.has(id, type):
		_err(line, "%s '%s' does not exist.%s" % [type.capitalize(), id, _suggest(id, _ids(type))])


func _check_path(path: String, line: int) -> void:
	if db.values.has(path) or path == "game.turn":
		return
	for m in db.all_of("meter"):
		if db.typed_value("meter", m, "value") == path:
			return
	var parts := path.split(".")
	if parts[0] == "captivity" and parts.size() == 2 and parts[1] in CaptivitySystem.VALUES:
		return
	if parts[0] == "fight" and parts.size() == 2 and parts[1].is_valid_identifier():
		return  # a fight's own scratch numbers
	if path == "play.index" or path == "play.count":
		return  # the repetition of `play X N times` running
	if parts[0] == "enemy" and parts.size() == 2:
		if not (Game.ENEMY_STATE.has(parts[1]) or parts[1] in CombatSystem.ENEMY_NUMBERS or parts[1] in ["scale", "libido", "form"]):
			_err(line, "Unknown enemy value '%s'. Known: %s." % [parts[1], ", ".join(Game.ENEMY_STATE.keys() + CombatSystem.ENEMY_NUMBERS + ["scale", "libido", "form"])])
		return
	if parts[0] == "player" and parts.size() == 3 and parts[2] == "strain_damage":
		if parts[1] not in BodySystem.PARTS and not BodySystem.ALIASES.has(parts[1]):
			_err(line, "'%s' is not a body part. Parts: %s." % [parts[1], ", ".join(BodySystem.PARTS)])
		return
	if parts[0] == "fights" and parts.size() == 2 and parts[1] in ["number", "won", "total"]:
		return  # fights in a row: the one now (from 1), how many were won, how many there are
	if parts[0] == "change" and parts.size() == 2 and parts[1] in ["owner", "amount", "value"]:
		return  # a value's own change text ("when raised:"): whose value, by how much, now
	if parts[0] == "sex" and parts.size() == 2 and parts[1] in ["taker", "giver", "act", "with"]:
		return  # the last sex record (SexSystem), for `after sex` hooks
	if db.has(parts[0], "character") and parts.size() == 2 and parts[1] in ["last_partner", "last_sex", "first_anal_partner",
			"first_vaginal_partner", "first_oral_partner", "first_penile_partner"]:
		return
	if parts[0] == "pregnancy" and parts.size() == 2 and (parts[1] in PregnancySystem.STORED or parts[1] in PregnancySystem.COMPUTED):
		return
	if parts[0] == "child" and parts.size() == 2 and (parts[1] in PregnancySystem.CHILD_VALUES or parts[1] in ["age_turns", "age_days", "turn"]):
		return
	if parts[0] == "people" and parts.size() == 2:
		if parts[1].replace("_", " ") not in _location_flags():
			_err(line, "'%s' counts people at places flagged '%s', but no place has that flag." % [path, parts[1].replace("_", " ")])
		return
	if path in ["shop.item", "shop.item_name", "shop.price", "party.size", "party.limit", "party.tamed",
			"offspring.with_you", "offspring.bunker", "offspring.roaming", "offspring.total"]:
		return
	if parts[0] == "companion" and parts.size() == 2 and (parts[1] in ["id", "name"] or CompanionSystem.DEFAULTS.has(parts[1])):
		return  # the companion a companion rule or text is about
	if parts[0] == "feat" and parts.size() == 2:
		if not db.has(parts[1], "feat"):
			_err(line, "Unknown feat '%s'.%s" % [parts[1], _suggest(parts[1], _ids("feat"))])
		return
	if parts[0] == "level" and parts.size() == 2:
		if not db.levels.has(parts[1]):
			_err(line, "Unknown content level '%s'." % parts[1])
		return
	if parts[0] == "player":
		if parts.size() == 3 and parts[1] == "body":
			if parts[2] not in BodySystem.PARTS and not BodySystem.ALIASES.has(parts[2]):
				_err(line, "Unknown body part '%s'." % parts[2])
			return
		if parts.size() == 3 and parts[1] == "carried":
			if not db.has(parts[2], "item"):
				_err(line, "Unknown item '%s'." % parts[2])
			return
		if parts.size() >= 2 and parts[1] in PLAYER_VALUES:
			return
		_err(line, "'%s' is not a player value.%s" % [path, _suggest(parts[1] if parts.size() > 1 else "", PLAYER_VALUES)])
		return
	# Relationship values on characters (met, had_sex, virgin ...) are built in.
	if db.has(parts[0], "creature") and parts.size() == 2 and parts[1] == "met":
		return
	if db.has(parts[0], "character") and parts.size() == 2 and parts[1] in ["met", "romanced", "friended", "controlled", "had_sex", "virgin", "oral_virgin", "anal_virgin", "penile_virgin", "trust"]:
		return
	var owners_values: Array = db.values.keys().filter(func(k): return k.begins_with(parts[0] + "."))
	_err(line, "'%s' is not a declared value.%s Declare it under 'values:' of %s." % [path, _suggest(path, owners_values if not owners_values.is_empty() else db.values.keys()), parts[0]])


func _check_set_value(path: String, value: Dictionary, line: int) -> void:
	if path.begins_with("pregnancy.") and path.substr(10) in PregnancySystem.COMPUTED:
		_err(line, "%s is worked out by the pregnancy rules and cannot be set." % path)
	var decl: Dictionary = db.values.get(path, {})
	if decl.get("kind", "") == "states" and value.get("op", "") == "word" and value.v not in decl.states:
		_err(line, "'%s' is not a state of %s. States: %s." % [value.v, path, ", ".join(decl.states)])


func _check_condition_text(text: String, line: int, owner: String) -> void:
	var c := Condition.compile(text)
	if c.has("error"):
		_err(line, c.error)
	else:
		_check_condition(c, line, owner)


var _flags_cache: Array = []


## The engine's location flags plus every flag a place in the content uses
## (content may flag places for its own counts and tests: `bunker`, `library`).
func _location_flags() -> Array:
	if _flags_cache.is_empty():
		_flags_cache = LOCATION_FLAGS.duplicate()
		for id in db.all_of("location"):
			for f in db.list_field(id, "flags"):
				if f not in _flags_cache:
					_flags_cache.append(f)
	return _flags_cache


func _check_condition(c: Dictionary, line: int, owner: String) -> void:
	match c.get("op", ""):
		"and", "or":
			_check_condition(c.a, line, owner)
			_check_condition(c.b, line, owner)
		"not":
			_check_condition(c.a, line, owner)
		"time":
			if c.slot not in Game.TIME_SLOTS + ["day", "night"]:
				_err(line, "Unknown time '%s'. Times: day, %s." % [c.slot, ", ".join(Game.TIME_SLOTS)])
		"cmp":
			_check_expr(c.left, line)
			_check_expr(c.right, line)
			# A state name compared with a state value must be one of its states.
			if c.left.get("op", "") == "path" and c.right.get("op", "") == "word":
				var decl: Dictionary = db.values.get(c.left.v, {})
				if decl.get("kind", "") == "states" and c.right.v not in decl.states:
					_err(line, "'%s' is not a state of %s. States: %s." % [c.right.v, c.left.v, ", ".join(decl.states)])
		"truthy":
			_check_path(c.path, line)
		"listed":
			_check_list(c.path, line)
			_check_expr(c.item, line)
		"empty":
			_check_path(c.path, line)
			var decl: Dictionary = db.values.get(c.path, {})
			if decl.get("kind", "") == "states" and "empty" not in decl.states:
				_err(line, "'%s is empty' tests a list or a text; %s is a list of states without 'empty'." % [c.path, c.path])
			elif decl.get("kind", "") in ["number", "flag", "time"]:
				_err(line, "'%s is empty' tests a list or a text, not a %s." % [c.path, decl.kind])
		"order":
			_check_path(c.path, line)
			var decl: Dictionary = db.values.get(c.path, {})
			if decl.get("kind", "") == "states" and c.state not in decl.states:
				_err(line, "'%s' is not a state of %s. States: %s." % [c.state, c.path, ", ".join(decl.states)])
		"quest":
			if not db.quests.has(c.quest):
				_err(line, "Quest '%s' does not exist.%s" % [c.quest, _suggest(c.quest, db.quests.keys())])
			elif c.stage not in db.quests[c.quest].stages:
				_err(line, "'%s' is not a stage of quest %s. Stages: %s." % [c.stage, c.quest, ", ".join(db.quests[c.quest].stages)])
		"outcome":
			var outs: Array = db.values.get("%s.outcome" % c.event, {}).get("states", [])
			if outs.is_empty():
				_err(line, "Event '%s' does not exist.%s" % [c.event, _suggest(c.event, _ids("event"))])
			elif c.outcome not in outs:
				_err(line, "'%s' is not an outcome of event %s." % [c.outcome, c.event])
		"has_item", "wears":
			_need(c.item, "item", line)
		"has_condition":
			_need(c.id, "condition", line)
		"ending":
			if c.kind == "ending_triggered":
				_need(c.id, "ending", line)
		"wields":
			if c.item != "anything":
				_need(c.item, "item", line)
		"filter":
			_need(c.filter, "filter", line)
		"level":
			if not db.levels.has(c.category):
				_err(line, "Level '%s' does not exist.%s" % [c.category, _suggest(c.category, db.levels.keys())])
			elif c.option not in db.levels[c.category].options:
				_err(line, "'%s' is not an option of level %s. Options: %s." % [c.option, c.category, ", ".join(db.levels[c.category].options)])
		"is":
			if c.who == "captivity":
				if c.adjective != "ending":
					_err(line, "Use 'captivity is ending' (after ~ end captivity or ~ escape captivity).")
				return
			if c.who == "enemy":
				if not (c.adjective in Game.CREATURE_SEXES or db.has(c.adjective, "creature")):
					_err(line, "Use 'enemy is male/female/herm/neuter', 'enemy is <creature>' or 'enemy is tagged <tag>'.")
				return  # the creature being fought: "enemy is female", "enemy is bald_eagle"
			if db.has(c.who, "creature") and (c.adjective in Game.CREATURE_SEXES or c.adjective.begins_with("variant ")):
				if c.adjective.begins_with("variant ") and c.adjective.substr(8) not in VariantSystem.variants(db, c.who):
					_err(line, "%s has no variant '%s'.%s" % [c.who, c.adjective.substr(8), _variant_list(c.who)])
				return
			if c.who == "player" and c.adjective.begins_with("interested in "):
				_need(c.adjective.substr(14).strip_edges(), "interest", line)
				return
			if c.who == "player" and c.adjective == "pansexual":
				return
			if c.who == "here":
				if c.adjective != "explorable" and not (c.adjective.begins_with("flagged ") and c.adjective.substr(8) in _location_flags()):
					_err(line, "Use 'here is explorable' or 'here is flagged <flag>' with one of: %s." % ", ".join(_location_flags()))
				return
			if db.has(c.who, "door") and not db.has(c.who, "character"):
				if c.adjective not in ["locked", "unlocked"]:
					_err(line, "A door is 'locked' or 'unlocked': '%s is %s'." % [c.who, c.adjective])
				return
			if c.adjective == "ready" and not db.has(c.who, "event"):
				_err(line, "'%s is ready' tests an event's requirements, but %s is not an event." % [c.who, c.who])
				return
			if c.adjective not in ["male", "female", "herm", "neuter", "resolved", "active", "ready", "companion", "lonely", "here", "virgin", "oral virgin", "anal virgin", "penile virgin", "collected",
					"naked", "barefoot", "barecrotch", "barechest", "overburdened", "fighting", "pregnant", "in heat", "in female heat", "in mpreg heat", "vulnerable to heat", "heat paused", "creature picked", "captive", "dead", "imprisoned", "gone", "arrived by walking", "arrived by travelling", "in an event", "pure", "male preferred", "female preferred", "herm preferred"]:
				_check_path("%s.%s" % [c.who, c.adjective.replace(" ", "_")], line)
		"lives_at", "is_at":
			if c.who != "player":
				_need(c.who, "character", line)
			_need(c.place, "location", line)
		"knows", "visited":
			_need(c.place, "location", line)
		"species_contains":
			if c.who != "player":
				_need(c.who, "character", line)
		"species_same":
			for w in [c.who, c.other]:
				if w != "player":
					_need(w, "character", line)
		"at_flagged":
			if c.who != "player":
				_need(c.who, "character", line)
			if c.flag not in _location_flags():
				_err(line, "No place has the flag '%s'. Flags in use: %s." % [c.flag, ", ".join(_location_flags())])
		"parts_all":
			if c.who != "player":
				_need(c.who, "character", line)
			for f in c.forms:
				if f != "human":
					_need(f, "form", line)
		"part_tagged", "enemy_tagged":
			# A declared tag, or a filter (forms carry their creatures' filter tags too).
			if not db.has(c.tag, "filter"):
				_need(c.tag, "tag", line)
		"check_expr":
			for p in Expr.paths(c.bonus) + Expr.paths(c.target):
				_check_path(p, line)
		"since":
			_check_path(c.path, line)
		"chance_expr":
			for p in Expr.paths(c.n) + Expr.paths(c.d):
				_check_path(p, line)
		"parity":
			for p in Expr.paths(c.value):
				_check_path(p, line)


## A creature's `special:` list: built-in behaviours, each with a chance where
## it takes one ("grapple 20%, firebreath").
func _special_problem(text: String) -> String:
	for part in text.split(","):
		var words: PackedStringArray = part.strip_edges().split(" ", false)
		if words.is_empty() or words[0] not in CombatSystem.SPECIALS:
			return "Unknown combat behaviour '%s'. Built in: grapple N%%, hump N%%, pounce N%%, firebreath; anything else goes in the creature's attacks." % part.strip_edges()
		var needs_chance: bool = words[0] != "firebreath"
		if words[0] == "grapple" and words.size() > 2:
			# A hold's options: the attribute that breaks it, and a squeeze that ignores armor.
			var rest := " ".join(words.slice(2))
			var m := RegEx.create_from_string("^(?:with (\\w+))? ?(ignoring armor)?$").search(rest)
			if m == null or rest == "":
				return "Write 'grapple N%', optionally followed by 'with <attribute>' and 'ignoring armor'."
			if m.get_string(1) != "" and m.get_string(1) not in CombatSystem.ATTRIBUTES:
				return "A hold is broken with an attribute: %s." % ", ".join(CombatSystem.ATTRIBUTES)
			words = words.slice(0, 2)
		if words.size() != (2 if needs_chance else 1):
			return "Write '%s'." % ("%s N%%" % words[0] if needs_chance else words[0])
		if needs_chance and (not words[1].ends_with("%") or not words[1].trim_suffix("%").is_valid_int() \
				or int(words[1].trim_suffix("%")) < 0 or int(words[1].trim_suffix("%")) > 100):
			return "Combat behaviour chance must be between 0% and 100%."
	return ""


## Endings (EndingSystem): a whole-number priority, a type word, a readable condition.
func _check_endings() -> void:
	for id in db.all_of("ending"):
		var d: FscParser.Definition = db.get_def("ending", id)
		_path = d.path
		if d.fields.has("priority") and not d.fields.priority.value.is_valid_int():
			_err(d.fields.priority.line, "Priority must be a whole number (lower plays first).")
		if d.fields.has("type") and not d.fields.type.value.is_valid_identifier():
			_err(d.fields.type.line, "An ending type is one word, such as infection or bad_end.")
		if d.fields.has("when"):
			_check_condition_text(d.fields.when.value, d.fields.when.line, "ending:" + id)
		if not d.fields.has("play"):
			_warn(d.line, "Ending %s has nothing to play." % id)


## A character's body:, stats: and relationship: keys and their values (CharacterSystem).
func _check_character_fields(d: FscParser.Definition) -> void:
	for p in CharacterSystem.pairs(d, "body"):
		if not CharacterSystem.BODY.has(p.key):
			_err(p.line, "Unknown body key '%s'. Known: %s." % [p.key, ", ".join(CharacterSystem.BODY.keys())])
			continue
		match CharacterSystem.BODY[p.key][1]:
			"number":
				if not p.value.is_valid_int() or int(p.value) < 0:
					_err(p.line, "Body %s must be a whole number of 0 or more." % p.key)
			"flag":
				if p.value not in ["yes", "no"]:
					_err(p.line, "Body %s must be yes or no." % p.key)
			"text":
				_need(p.value, "form", p.line)
	for p in CharacterSystem.pairs(d, "stats"):
		if p.key == "hp" or not RegEx.create_from_string("^[a-z][a-z ]*$").search(p.key):
			var hint := " A character's story stage is a value of its own; fighting health is 'max hp'." if p.key == "hp" else ""
			_err(p.line, "Stat '%s' can't be used: a stat is a lowercase word or words (the engine's own: %s).%s" % [p.key, ", ".join(CharacterSystem.STATS.keys()), hint])
		elif not p.value.is_valid_int():
			_err(p.line, "Stat %s must be a whole number." % p.key)
	for p in CharacterSystem.pairs(d, "relationship"):
		if not CharacterSystem.RELATIONSHIP.has(p.key):
			_err(p.line, "Unknown relationship key '%s'. Known: %s." % [p.key, ", ".join(CharacterSystem.RELATIONSHIP.keys())])
		elif p.value not in ["yes", "no"]:
			_err(p.line, "Relationship %s must be yes or no." % p.key)


func _variant_list(creature: String) -> String:
	var names: Array = VariantSystem.variants(db, creature).keys()
	return " It has no variants." if names.is_empty() else " Variants: %s." % ", ".join(names)


## Creature variants (VariantSystem): each one's fields, filters and condition.
func _check_variants(id: String, d: FscParser.Definition) -> void:
	if d.fields.has("pick variant") and d.fields["pick variant"].value not in ["random", "in order"]:
		_err(d.fields["pick variant"].line, "Pick variant is random or in order.")
	if not d.fields.has("variants"):
		return
	var all := VariantSystem.variants(db, id)
	if all.is_empty():
		_err(d.fields.variants.line, "Variants need at least one named variant, such as 'female:' with its fields indented below it.")
	for v: String in all:
		var fields: Dictionary = all[v]
		var line: int = fields._line
		if not v.is_valid_identifier():
			_err(line, "A variant name is one word of letters, digits and underscores: '%s'." % v)
		for name: String in fields:
			if name == "_line":
				continue
			var value := str(fields[name])
			if name not in VariantSystem.FIELDS:
				_err(line, "Variant %s: unknown field '%s'. Allowed: %s." % [v, name, ", ".join(VariantSystem.FIELDS)])
				continue
			match name:
				"gender":
					if value not in CREATURE_GENDERS:
						_err(line, "Variant %s: unknown gender '%s'." % [v, value])
				"filters":
					for f in value.split(",", false):
						_need(f.strip_edges(), "filter", line)
				"when":
					_check_condition_text(value, line, "creature:" + id)
				"chance", "level", "damage", "libido", "hit bonus", "dodge bonus", "mind bonus":
					if not value.is_valid_int() or (int(value) < 0 and name not in ["hit bonus", "dodge bonus", "mind bonus"]):
						_err(line, "Variant %s: %s must be a whole number." % [v, name])
				"hp":
					if not value.is_valid_int() or int(value) < 1:
						_err(line, "Variant %s: hp must be a positive whole number." % v)
				"infection sex":
					if value not in ["male", "female", "herm", "neuter"]:
						_err(line, "Variant %s: infection sex is male, female, herm or neuter." % v)
				"seduction immune":
					if value not in ["yes", "no"]:
						_err(line, "Variant %s: seduction immune must be yes or no." % v)
				"loot":
					var loot: PackedStringArray = value.split(" ", false)
					if loot.size() != 2 or not loot[1].ends_with("%") or not loot[1].trim_suffix("%").is_valid_int():
						_err(line, "Variant %s: loot is written 'item_id N%%'." % v)
					else:
						_need(loot[0], "item", line)
				"special":
					var problem := _special_problem(value)
					if problem != "":
						_err(line, "Variant %s: %s" % [v, problem])
				"image":
					if not _images.has(value):
						_warn(line, "Image '%s' was not found in any pack's images folder." % value)
		if not fields.has("gender") and not fields.has("filters"):
			_warn(line, "Variant %s has neither a gender nor filters, so bans and wards never keep it out." % v)


func _check_template(t: Dictionary, line: int, owner: String) -> void:
	for s in TextTemplate.substitutions(t.parts):
		var n := str(s).strip_edges()
		# "[a X]" puts an article before X; "[path in words]" writes a number out.
		if n.begins_with("a ") or n.begins_with("A "):
			n = n.substr(2)
		if n.ends_with(" in words"):
			n = n.trim_suffix(" in words")
		var calc := Expr.text_expression(n)
		if not calc.is_empty():
			# "[people.bunker + people.library]": arithmetic on values; "[entry 1 of x.list]".
			_check_expr(calc, line)
			continue
		if "." in n and not " " in n:
			_check_path(n, line)
			continue
		if n.begins_with("worn "):
			for slot in n.substr(5).split(","):
				if slot.strip_edges() not in ItemSystem.SLOTS:
					_err(line, "[%s]: '%s' is not a slot. Slots: %s." % [n, slot.strip_edges(), ", ".join(ItemSystem.SLOTS)])
			continue
		var cm := RegEx.create_from_string("^children at (\\w+) as (\\w+)$").search(n)
		if cm != null:
			# "[children at bunker as offspring_line]": a snippet once per child living there.
			if not db.has(cm.get_string(2), "text"):
				_err(line, "[%s]: '%s' is not a text snippet." % [n, cm.get_string(2)])
			continue
		var halves := n.split(" of ", true, 1)
		var what := halves[0]
		if what in DESCRIPTORS or db.has(n, "text"):
			continue
		if halves.size() == 2 and db.has(what, "text"):
			# "[cock_size_desc of francois]": a snippet about a character or creature.
			var who := halves[1].strip_edges()
			if who != "player" and not db.has(who, "character") and not db.has(who, "creature"):
				_err(line, "[%s]: '%s' is not a character." % [n, who])
			continue
		_err(line, "Unknown text substitution [%s].%s" % [n, _suggest(n, DESCRIPTORS + _ids("text"))])
	_walk_template_conditions(t.parts, line, owner)


func _walk_template_conditions(parts: Array, line: int, owner: String) -> void:
	for p in parts:
		match p.t:
			"if":
				for b in p.branches:
					_check_condition(b.cond, line, owner)
					_walk_template_conditions(b.parts, line, owner)
				_walk_template_conditions(p["else"], line, owner)
			"one_of":
				for o in p.options:
					_walk_template_conditions(o, line, owner)
