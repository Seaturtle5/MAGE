class_name StorySystem
extends RefCounted
## Small story features scenes and events use:
##
## - fights away from a creature's usual place: `fight wolf away from home:`, and in
##   the creature's texts `[if fight is away from home]...` (the original's showlocale);
## - a scripted rest: `~ rest` heals and refreshes as the Rest action, without its time;
## - a random event of a kind: `~ pick random event tagged dream`, `an event is picked`,
##   `play picked event` (the original's "a random dreamable dreamevent");
## - arrival events for a whole area: `found by: walking into any place in junkyard`;
## - an item given to any character: the item's `given:` script (the original's typed
##   commands such as "libpill <person>"), with `gift.to.<value>` for the receiver's values;
## - many places or events at once: `~ discover every place flagged city_map`,
##   `~ resolve every event tagged city_map`;
## - every companion: `~ for each tamed companion play X`, `~ for all companions play X`;
## - `instead of using <item>` hooks, which replace an item's use text.

## The key of the away-from-home flag among the game's values (saved with a mid-scene save).
const AWAY := "encounter.away_from_home"
## Effects this system applies (Game.apply hands them over).
const OPS := ["rest", "pick_event", "discover_flagged", "resolve_tagged", "each_companion_of"]


# --- Fights away from home ------------------------------------------------------

## Marks the creature about to be met as away from its usual place (or not).
static func set_away(game, away: bool) -> void:
	if away:
		game.state.values[AWAY] = true
	else:
		game.state.values.erase(AWAY)


## `fight is away from home`: the fight a scene started with `away from home`, from
## the creature's encounter text to the end of its victory or defeat text.
static func away(game) -> bool:
	return bool(game.state.values.get(AWAY, false))


# --- Effects ---------------------------------------------------------------------

## Applies one of OPS; false for any other effect.
static func apply(game, e: Dictionary) -> bool:
	match str(e.op):
		"rest":
			# The original's Rest phrase: the Rest action's healing and sleep, no time passing.
			RestSystem.recover(game, RestSystem.bedding(game).quality)
		"pick_event":
			game.state.values["picked.event"] = pick_event(game, str(e.tag))
		"discover_flagged":
			var found: Array = []
			for id: String in places_flagged(game, str(e.flag)):
				if not game.state.known.has(id):
					game.state.known[id] = true
					found.append(game.content.field_value(id, "name", id))
			if not found.is_empty():
				game.notice("Discovered: %s" % ", ".join(found), e.get("quiet", false))
		"resolve_tagged":
			for id: String in events_tagged(game, str(e.tag)):
				game._event(id).resolved = true
		"each_companion_of":
			# Every tamed companion, or every character that can follow the player at all
			# (the original's "repeat with z running through pets"), followed or not.
			var who: Array = CompanionSystem.tamed(game) if e.scope == "tamed" else companions(game)
			for c: String in who:
				CompanionSystem._with(game, c)
				CompanionSystem._play(game, str(e.scene))
		_:
			return false
	return true


## Every character that can follow the player (it has a `companion:` block), sorted.
static func companions(game) -> Array:
	var out: Array = game.content.all_of("character").keys().filter(func(id: String) -> bool:
		return CompanionSystem.is_companion(game, id))
	out.sort()
	return out


## The places carrying a flag, sorted.
static func places_flagged(game, flag: String) -> Array:
	var out: Array = game.content.all_of("location").keys().filter(func(id: String) -> bool:
		return flag in game.content.list_field(id, "flags"))
	out.sort()
	return out


## The events carrying a tag, sorted.
static func events_tagged(game, tag: String) -> Array:
	var out: Array = game.content.all_of("event").keys().filter(func(id: String) -> bool:
		return tag in game.content.list_field(id, "tags"))
	out.sort()
	return out


# --- A random event of a kind ------------------------------------------------------

## An event with the tag that could be found now, picked at random ("" when none):
## active, not resolved, its `requires` holding, not banned, and within the level
## and score exploring allows (the original's "a random dreamable dreamevent").
static func pick_event(game, tag: String) -> String:
	var pool: Array = []
	for ev: String in events_tagged(game, tag):
		var st: Dictionary = game._event(ev)
		if st.resolved or not st.active:
			continue
		if game.filter_block(game.content.list_field(ev, "tags"), true) != "":
			continue
		if WorldSystem.event_level(game, ev) >= int(game.value("player.level")) + 2:
			continue
		if int(game.value("player.score")) < int(game.content.typed_value("event", ev, "min score", "-2147483648")):
			continue
		if not game.runner._event_requires(ev, "requires"):
			continue
		pool.append(ev)
	return "" if pool.is_empty() else str(pool[game.rng.range_int(0, pool.size() - 1)])


## `play picked event`: the event `~ pick random event` chose plays here as if found
## (its title, `repeat: once` resolving it), then the scene goes on.
static func play_picked(runner) -> void:
	var ev := str(runner.game.state.values.get("picked.event", ""))
	if ev != "" and runner.game.content.has(ev, "event"):
		runner._queue_event(ev)


# --- Arrival in a whole area -----------------------------------------------------------

## The areas named in an arrival way: "any place in junkyard" -> "junkyard", else "".
static func area_of(entry: String) -> String:
	return entry.substr(13).strip_edges() if entry.begins_with("any place in ") else ""


## Whether a place lies in an area: its zone (its own `zone:`) or its region (as on the map).
static func in_area(game, place: String, area: String) -> bool:
	return game.content.typed_value("location", place, "zone") == area or game.map_group(place) == area


## Whether arriving at `place` matches one of an arrival way's entries (places or areas).
static func arrives(game, place: String, entries: Array) -> bool:
	for entry: String in entries:
		if entry == place:
			return true
		var area := area_of(entry)
		if area != "" and in_area(game, place, area):
			return true
	return false


# --- Giving an item to any character --------------------------------------------------

## Carried items that can be given to any character (they have a `given:` script), sorted.
static func items_for_anyone(game) -> Array:
	var out: Array = []
	for id: String in game.state.inventory.keys():
		if int(game.state.inventory[id]) > 0 and game.content.program("item:%s#given" % id) != null:
			out.append(id)
	out.sort()
	return out


## The items offered when giving to a character: those its own `gift:` takes (when it
## has one and its `gift when:` holds) and those any character can be given.
static func gift_choices(runner, who: String) -> Array:
	var game = runner.game
	var out: Array = items_for_anyone(game)
	if own_gift_open(game, who):
		for id: String in runner.gift_items(who):
			if id not in out:
				out.append(id)
	out.sort()
	return out


## The character has a `gift:` script and its `gift when:` holds.
static func own_gift_open(game, who: String) -> bool:
	var d: FscParser.Definition = game.content.get_def("character", who)
	if d == null or not d.fields.has("gift"):
		return false
	var when: String = game.content.typed_value("character", who, "gift when")
	return when == "" or Condition.evaluate(Condition.compile(when), game)


## The script that decides about a given item: the item's own `given:` (an item any
## character can be given), else the character's `gift:`.
static func gift_script(game, who: String, item: String) -> String:
	if game.content.program("item:%s#given" % item) != null:
		return "item:%s#given" % item
	return "%s#gift" % who


## `gift.to.last_sex`: a value of the character an item is being given to.
static func resolve_path(game, path: String) -> String:
	if path.begins_with("gift.to.") and path.count(".") >= 2:
		var who := str(game.state.values.get("gift.to", ""))
		if who != "":
			return who + path.substr(7)
	return path


# --- Using items --------------------------------------------------------------------

## The script a use of the item plays: the first `instead of using <item>` hook whose
## `when:` holds, else the item's own `use:` ("" when it has neither).
static func use_script(game, item: String) -> String:
	var instead: String = game.hook_instead("instead of using " + item)
	if instead != "":
		return instead
	return "item:%s#use" % item if game.content.program("item:%s#use" % item) != null else ""


# --- Validation -----------------------------------------------------------------------

## Checks one of OPS.
static func check_effect(v, e: Dictionary, line: int) -> void:
	match str(e.op):
		"rest":
			if v.db.all_of("rest_rules").is_empty():
				v._warn(line, "~ rest heals as the Rest action, but no rest_rules are loaded, so fatigue does not change.")
		"pick_event":
			if events_tagged_db(v.db, str(e.tag)).is_empty():
				v._err(line, "No event has the tag '%s', so ~ pick random event tagged %s never picks one." % [e.tag, e.tag])
		"discover_flagged":
			if not v.db.all_of("location").keys().any(func(id: String) -> bool: return str(e.flag) in v.db.list_field(id, "flags")):
				v._err(line, "No place has the flag '%s'. Flags in use: %s." % [e.flag, ", ".join(v._location_flags())])
		"resolve_tagged":
			if events_tagged_db(v.db, str(e.tag)).is_empty():
				v._err(line, "No event has the tag '%s', so ~ resolve every event tagged %s resolves nothing." % [e.tag, e.tag])
		"each_companion_of":
			v._check_target(str(e.scene), line)
			v.warn_played_at_once(str(e.scene), line, "for each tamed companion play" if e.scope == "tamed" else "for all companions play")


static func events_tagged_db(db: ContentDB, tag: String) -> Array:
	return db.all_of("event").keys().filter(func(id: String) -> bool: return tag in db.list_field(id, "tags"))


## Value paths this system adds: `picked.event`, and `gift.to.<value>` (a value every
## character has, or one some character declares). True when the path is one of them.
static func check_path(v, path: String, line: int) -> bool:
	if path == "picked.event" or path == AWAY:
		return true
	if path.begins_with("gift.to.") and path.count(".") == 2:
		var name := path.substr(8)
		if name in ["met", "romanced", "friended", "controlled", "had_sex", "virgin", "oral_virgin", "anal_virgin", "penile_virgin",
				"trust", "last_sex", "last_partner", "first_anal_partner", "first_vaginal_partner", "first_oral_partner", "first_penile_partner"]:
			return true
		for key: String in v.db.values:
			var owner := key.get_slice(".", 0)
			if key.count(".") == 1 and key.get_slice(".", 1) == name and (owner == "character" or v.db.has(owner, "character")):
				return true
		v._err(line, "'%s': no character has a value '%s'." % [path, name])
		return true
	return false


## `gift.to.last_sex` (every character's), or a time value some character declares.
static func time_path(v, path: String) -> bool:
	if not path.begins_with("gift.to.") or path.count(".") != 2:
		return false
	var name := path.substr(8)
	return name == "last_sex" or v.db.values.keys().any(func(key: String) -> bool:
		return key.get_slice(".", 1) == name and key.count(".") == 1 and v.db.values[key].get("kind", "") == "time" \
			and (key.get_slice(".", 0) == "character" or v.db.has(key.get_slice(".", 0), "character")))


## An area in `walking into any place in <area>`: a zone or a region.
static func check_area(v, area: String, line: int) -> void:
	if not v.db.has(area, "zone") and not v.db.has(area, "region"):
		var names: Array = v._ids("zone") + v._ids("region")
		v._err(line, "'%s' is neither a zone nor a region.%s" % [area, v._suggest(area, names)])
