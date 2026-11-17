class_name WorldSystem
extends RefCounted
## Small features of the world, its items and characters that scenes use:
##
## - events moved in play: `~ event scopaesthesia found in red` (the zones its exploring
##   or scavenging uses from now on; `nowhere` takes it out) and `~ event scopaesthesia
##   level = 9` (also + and -): the original's `now sarea of X is "Red"`, `now level of X is 9`;
## - a pick-up a script can refuse: hooks `on: before picking up <item>` play before the
##   item is taken from the ground, and `~ cancel pick up` leaves it lying (the original's
##   `check grabbing X`);
## - cursed gear: the Remove action refuses it and plays the item's `cursed text:`, while a
##   scene's `~ remove X` takes it off (the original's `now X is not equipped`);
## - arriving somewhere: hooks `on: arriving` play whenever the player arrives at another
##   place, with `arrival.from` the place they came from (the original's every-turn rules
##   that notice the player moved);
## - choosing and taking on a creature: `creature named <text>`, `~ ask x as creature met:`,
##   `strength of x` ... `libido of x`, `~ shift into x` (the original's shift command),
##   `~ transform into x.value`;
## - `creature catgirl is banned` (the original's BannedStatus);
## - dangerous doors: `here.door_zone` (the original's marea of a visible dangerous door)
##   and a door's `going text:`, said when the player goes through it;
## - `random carried item used up by use` and `player has an item used up by use` (the
##   original's temporary grab objects);
## - characters changed in play: `~ character doctor_matt name "..."`, `~ character
##   doctor_matt presence -> X`, `~ character doctor_matt description -> X`, and a
##   companion's own name (`name:` in its `companion:` block);
## - extended play: the survival rules' `no rescue when:` (the original's playon).

## The frame that picks items up after their `before picking up` hooks.
const FRAME := "world_pick_up"
## The item a `before picking up` hook is about, and whether a hook refused it.
const PICKING := "picking.item"
const CANCELLED := "picking.cancelled"
## A creature's numbers a script can read: `strength of x.critter`.
const READINGS := ["strength", "dexterity", "stamina", "perception", "intelligence", "charisma", "libido", "level", "zones"]
## Value paths this system answers.
const PATHS := ["here.door_zone", "arrival.from", PICKING]
## The parts the shift changes with their change texts, in the original's order
## (skin, face, ass and tail), before the breasts and the body.
const SHIFT_FIRST := ["skin", "head", "ass", "tail", "back", "arms", "legs"]


# --- Effects ---------------------------------------------------------------------

## Compiles one of this system's effect rules ("world:<name>").
static func compile_effect(rule: String, m: RegExMatch) -> Dictionary:
	match rule:
		"world:event_zones":
			var zones: Array = []
			for z in m.get_string(2).split(","):
				if z.strip_edges() != "" and z.strip_edges() != "nowhere":
					zones.append(z.strip_edges())
			return {"op": "world_event_zones", "event": m.get_string(1), "zones": zones}
		"world:event_level":
			var amt := Effect.amount(m.get_string(3))
			if amt.has("error"):
				return {"error": amt.error}
			return {"op": "world_event_level", "event": m.get_string(1), "how": m.get_string(2), "amount": amt}
		"world:cancel_pick_up":
			return {"op": "world_cancel_pick_up"}
		"world:shift":
			return {"op": "world_shift", "form": m.get_string(1)}
		"world:transform_held":
			return {"op": "world_transform", "form": m.get_string(1)}
		"world:ask_creature":
			var prompt := TextTemplate.compile(m.get_string(2))
			if prompt.has("error"):
				return {"error": prompt.error}
			return {"op": "world_ask_creature", "path": m.get_string(1), "prompt": prompt}
		"world:character_name":
			var text := m.get_string(2)
			return {"op": "world_character_name", "who": m.get_string(1),
				"name": "" if text == "default" else text.substr(1, text.length() - 2)}
		"world:character_text":
			return {"op": "world_character_text", "who": m.get_string(1), "field": m.get_string(2), "target": m.get_string(3)}
	return {"error": "unknown effect"}


## Applies one of this system's effects.
static func apply(game, e: Dictionary) -> void:
	match str(e.op):
		"world_event_zones":
			game.state.values["event.%s.found in" % e.event] = (e.zones as Array).duplicate()
		"world_event_level":
			var cur := event_level(game, e.event)
			var amount: int = Effect.resolve_amount(e.amount, game, cur)
			var nv: int = amount if e.how == "=" else cur + (amount if e.how == "+" else -amount)
			if e.amount.has("limit") and e.how != "=":
				var lim: int = e.amount.limit_value
				nv = mini(nv, maxi(cur, lim)) if e.amount.limit == "up" else maxi(nv, mini(cur, lim))
			game.state.values["event.%s.level" % e.event] = nv
		"world_cancel_pick_up":
			game.state.values[CANCELLED] = true
		"world_shift":
			var form := held_form(game, str(e.form))
			if form != "":
				shift(game, form)
		"world_transform":
			var form := held_form(game, str(e.form))
			if form != "":
				BodySystem.infect(game, form, true)
		"world_ask_creature":
			var ids: Array = (game.state.encountered as Array).filter(func(id: String) -> bool: return game.content.has(id, "creature"))
			ids.sort_custom(func(a: String, b: String) -> bool: return creature_name(game, a).naturalnocasecmp_to(creature_name(game, b)) < 0)
			game.runner.frames.append({"kind": "item_choice", "path": e.path, "ids": ids, "type": "creature", "prompt": e.prompt, "shown": false})
			if game.runner.status == "idle":
				game.runner.run()
		"world_character_name":
			var key := "character.%s.name" % e.who
			if e.name == "":
				game.state.values.erase(key)
			else:
				game.state.values[key] = e.name
		"world_character_text":
			var key := "character.%s.%s" % [e.who, e.field]
			if e.target == "default":
				game.state.values.erase(key)
			else:
				game.state.values[key] = e.target


## A form for a creature or form named, or held by a value ("" when there is none).
static func held_form(game, what: String) -> String:
	var id := what
	if "." in what:
		var v: Variant = game.value(what)
		id = str(v) if v != null else ""
	if id == "":
		return ""
	if game.content.has(id, "form"):
		return id
	if game.content.has(id, "creature"):
		return game.creature_field(id, "form", id)
	game.warn("'%s' is neither a creature nor a form." % id)
	return ""


# --- Events moved in play --------------------------------------------------------------

## How an event is found now (ContentDB.found_by), with the zones a scene moved it to.
static func event_found(game, ev: String) -> Dictionary:
	var found := ContentDB.found_by(game.content.typed_value("event", ev, "found by"))
	var zones: Variant = game.state.values.get("event.%s.found in" % ev)
	if zones is Array:
		found.zones = (zones as Array).duplicate()
		if not found.exploring and not found.scavenging:
			found.exploring = true  # an event found nowhere before is now found by exploring there
	return found


## An event's level now: as a scene set it, else its own `level:`.
static func event_level(game, ev: String) -> int:
	var lv: Variant = game.state.values.get("event.%s.level" % ev)
	return int(lv) if lv != null else int(game.content.typed_value("event", ev, "level", "0"))


# --- Picking up -------------------------------------------------------------------------

## Takes an item ("take") or everything ("take_all") from the ground, with the
## `before picking up <item>` hooks first. False when no such hook applies, so the
## runner picks up as usual.
static func take(runner, action: String, arg: String) -> bool:
	var game = runner.game
	var here: Dictionary = ItemSystem.ground(game, game.state.location)
	var items: Array = ([arg] if action == "take" else here.keys()).filter(func(it: String) -> bool: return int(here.get(it, 0)) > 0)
	if not items.any(func(it: String) -> bool: return not game.hooks_for("before picking up " + it).is_empty()):
		return false
	runner.frames.append({"kind": FRAME, "items": items, "at": 0, "asked": false, "all": action == "take_all", "taken": []})
	runner.run()
	return true


## One step of the pick-up frame: each item's hooks, then the item unless refused,
## then the `after picking up` hooks of what was taken. True when the runner waits.
static func step(runner, f: Dictionary) -> bool:
	var game = runner.game
	var items: Array = f.items
	if int(f.at) >= items.size():
		runner.frames.erase(f)
		game.state.values.erase(PICKING)
		game.state.values.erase(CANCELLED)
		var scripts: Array = []
		for it: String in f.taken:
			scripts.append_array(game.hooks_for("after picking up " + it))
		if scripts.is_empty():
			if runner.frames.is_empty():
				runner.show_location()
		else:
			scripts.reverse()
			for pid: String in scripts:
				runner._push(pid, {})
		return false
	var item: String = items[int(f.at)]
	if not f.asked:
		f.asked = true
		game.state.values[PICKING] = item
		game.state.values.erase(CANCELLED)
		var hooks: Array = game.hooks_for("before picking up " + item)
		hooks.reverse()
		for pid: String in hooks:
			runner._push(pid, {})
		return false
	f.asked = false
	f.at = int(f.at) + 1
	if game.state.values.get(CANCELLED, false):
		return false
	var count: int = ItemSystem.on_ground(game, game.state.location, item) if f.all else 1
	var took := false
	for _i in count:
		took = ItemSystem.pick_up(game, item) or took
	if took:
		f.taken.append(item)
	return false


# --- Cursed gear ------------------------------------------------------------------------

## Whether worn gear is cursed (the Remove action cannot take it off).
static func cursed(game, id: String) -> bool:
	return ItemSystem.gear(game, id, "cursed", "no") == "yes"


## The Remove action: cursed gear stays on and plays its `cursed text:` (true when it
## has one); anything else comes off as usual.
static func try_remove(runner, id: String) -> bool:
	var game = runner.game
	if id in game.state.equipped and cursed(game, id):
		var pid := "item:%s#cursed text" % id
		if game.content.program(pid) == null:
			return false
		runner.start(pid)
		return true
	return ItemSystem.remove(game, id)


## Whether the Take off button of worn cursed gear does something (its `cursed text:`).
static func has_cursed_text(game, id: String) -> bool:
	return game.content.program("item:%s#cursed text" % id) != null


# --- Arriving ---------------------------------------------------------------------------

## After the player moved from `from` to another place: the `arriving` hooks.
static func arrived(game, from: String, place: String) -> void:
	if from == "" or from == place or not game.has_hook("arriving"):
		return
	game.state.values["arrival.from"] = from
	game.run_hooks("arriving")


# --- Creatures --------------------------------------------------------------------------

## A creature's name as the player knows it.
static func creature_name(game, id: String) -> String:
	return game.creature_field(id, "name", id)


## `creature named <text>`: the creature whose name is the text (any case), else the
## first whose name contains it (the original's shift command), else one with that ID;
## "" when none.
static func creature_named(game, text: String) -> String:
	var wanted := text.strip_edges().to_lower()
	if wanted == "":
		return ""
	var ids: Array = game.content.all_of("creature").keys()
	for id: String in ids:
		if creature_name(game, id).to_lower() == wanted:
			return id
	for id: String in ids:
		if creature_name(game, id).to_lower().contains(wanted):
			return id
	return wanted if game.content.has(wanted, "creature") else ""


## `strength of x` ... `libido of x`, `level of x`: a creature's numbers now (for a form, those of the
## first creature that infects with it, else the form's own `stats:` and `libido:`).
static func read_of(game, what: String, v: Variant) -> Variant:
	var id := str(v) if v != null else ""
	if what == "creature named":
		return creature_named(game, id)
	if id == "":
		return "" if what == "zones" else 0
	if what == "zones":
		# `zones of x`: the names of the zones a creature is found in now ("" for nowhere).
		var names: Array = []
		for z: String in game.creature_field(id, "found in", "nowhere").split(","):
			z = z.strip_edges()
			if z != "" and z != "nowhere":
				names.append(game.content.typed_value("zone", z, "name", z))
		return ", ".join(names)
	if not game.content.has(id, "creature") and game.content.has(id, "form"):
		for c: String in game.content.all_of("creature"):
			if game.creature_field(c, "form", c) == id:
				id = c
				break
	if game.content.has(id, "creature"):
		if what in ["libido", "level"]:
			return CombatSystem.number(game, id, what, 0)
		return CombatSystem.stat(game, id, what)
	if game.content.has(id, "form"):
		if what == "level":
			return 0  # a form with no creature has no level
		if what == "libido":
			return int(game.content.typed_value("form", id, "libido", "0"))
		for entry in game.content.typed_value("form", id, "stats").split(","):
			var parts: PackedStringArray = entry.strip_edges().split(" ", false)
			if parts.size() == 2 and parts[0] == what:
				return int(parts[1])
	return 0


## `creature catgirl is banned`: the content filters keep the creature out entirely
## (a banned filter on it, or on every variant it has; wards do not count).
static func banned(game, id: String) -> bool:
	if not game.content.has(id, "creature"):
		return false
	var skip := VariantSystem.all_filters(game.content, id)
	if game.filter_block(CreatureChangeSystem.creature_tags(game, id).filter(func(t: String) -> bool: return t not in skip), true) != "":
		return true
	if not VariantSystem.has_variants(game.content, id):
		return false
	return VariantSystem.variants(game.content, id).keys().all(func(variant: String) -> bool:
		return game.filter_block(VariantSystem.filters_of(game.content, id, variant), true) != "")


## The original's shift (Hellerhound/Shifting.i7x:118-201): every part that differs
## takes the form with its change text (skin, face, ass, tail and the rest), then the
## breasts, the body with its size, the sex change twice and the cock. Attributes and
## libido are left to the scene, which says how they grow.
static func shift(game, form: String) -> void:
	BodySystem.remember_strain(game, form)
	for part: String in SHIFT_FIRST:
		if game.part_form("player", part) != form and not BodySystem.fields(game, form, part).is_empty():
			BodySystem._change_part(game, form, part)
	BodySystem._breasts(game, form)
	if game.part_form("player", "torso") != form and not BodySystem.fields(game, form, "torso").is_empty():
		BodySystem._change_part(game, form, "torso")
		BodySystem._attributes(game, form)
	BodySystem._sex(game, form, true)
	BodySystem._sex(game, form, true)
	for part: String in ["cock", "cunt"]:
		if game.part_form("player", part) != form and not BodySystem.fields(game, form, part).is_empty():
			BodySystem._change_part(game, form, part, part == "cock" and game.adjective("player", "male"))


# --- Conditions -------------------------------------------------------------------------

## Compiles one of this system's condition rules ("world_<name>").
static func compile_condition(rule: String, m: RegExMatch) -> Dictionary:
	match rule:
		"world_banned":
			return {"op": "world_banned", "creature": m.get_string(1), "neg": m.get_string(2) != ""}
		"world_has_used_up":
			return {"op": "world_has_used_up", "neg": m.get_string(1) != "has"}
	return {"error": "unknown condition"}


## Evaluates one of this system's conditions (without its `neg`).
static func ask(game, node: Dictionary) -> bool:
	match str(node.op):
		"world_banned":
			var id: String = node.creature
			if "." in id:
				var v: Variant = game.value(id)
				id = str(v) if v != null else ""
			return banned(game, id)
		"world_has_used_up":
			return random_item(game, "", true, false) != ""
	return false


# --- Items ------------------------------------------------------------------------------

## Whether an item is used up by use (the original's temporary grab objects): not gear,
## not a weapon, and not `consumed: no`.
static func used_up_by_use(game, id: String) -> bool:
	var d: FscParser.Definition = game.content.get_def("item", id)
	if d == null or d.fields.has("equipment") or d.fields.has("weapon"):
		return false
	return game.content.typed_value("item", id, "consumed", "yes") != "no"


## `random carried item`, `... tagged x`, `... used up by use`: a carried item picked at
## random among those that fit ("" when none). `roll`: false only checks there is one.
static func random_item(game, tag: String, used_up: bool, roll: bool = true) -> String:
	var ids: Array = []
	for id: String in game.state.inventory.keys():
		if int(game.state.inventory[id]) <= 0 or not game.content.has(id, "item"):
			continue
		if tag != "" and tag not in game.content.list_field(id, "tags"):
			continue
		if used_up and not used_up_by_use(game, id):
			continue
		ids.append(id)
	if ids.is_empty():
		return ""
	ids.sort()
	return str(ids[game.rng.range_int(0, ids.size() - 1)]) if roll else str(ids[0])


# --- Dangerous doors --------------------------------------------------------------------

## `here.door_zone`: the zone a dangerous door out of the player's place leads to (one
## of them at random when there are several), "" when there is none.
static func door_zone(game) -> String:
	var zones: Array = []
	for door: String in game.runner.exit_doors(game.state.location):
		var z: String = game.content.typed_value("door", door, "leads to zone")
		if z != "":
			zones.append(z)
	if zones.is_empty():
		return ""
	return str(zones[0]) if zones.size() == 1 else str(zones[game.rng.range_int(0, zones.size() - 1)])


## Says a door's `going text:` (going through it), "" said when it has none. Returns
## how many output events it added.
static func say_going_text(runner, door: String) -> int:
	var prog: Program = runner.game.content.program("door:%s#going text" % door)
	if prog == null:
		return 0
	var before: int = runner.game.output.size()
	for spans: Array in runner.render_paragraphs(prog):
		runner.game.emit({"type": "paragraph", "spans": spans})
	return runner.game.output.size() - before


## Moves `count` output events starting at `first` to just after the next title (the
## page of what going through a door led to), so they are read on that page.
static func move_under_title(game, first: int, count: int) -> void:
	if count <= 0:
		return
	var moved: Array = game.output.slice(first, first + count)
	for k in range(first + count, game.output.size()):
		if game.output[k].type == "title":
			var rest: Array = game.output.slice(first + count, k + 1)
			var tail: Array = game.output.slice(k + 1)
			game.output.resize(first)
			game.output.append_array(rest + moved + tail)
			return


# --- Characters -------------------------------------------------------------------------

## A character's name now: as a scene renamed it, else its own `name:`.
static func character_name(game, id: String) -> String:
	if game.state.values.has("character.%s.name" % id):
		return str(game.state.values["character.%s.name" % id])
	return game.content.typed_value("character", id, "name", id)


## A companion's name: its own `name:` in its `companion:` block (the original's pet
## object, "Mouse" for DrMouse), else the character's name.
static func companion_name(game, id: String) -> String:
	var own: String = CompanionSystem.field(game, id, "name", "")
	return own if own != "" else character_name(game, id)


## A character's `presence` or `description` now: the scene or text a scene put in its
## place, else its own (a program ID, "" when it has none).
static func character_program(game, id: String, field: String) -> String:
	var key := "character.%s.%s" % [id, field]
	if game.state.values.has(key):
		return str(game.state.values[key])
	return "%s#%s" % [id, field] if game.content.program("%s#%s" % [id, field], "character") != null else ""


# --- Values -----------------------------------------------------------------------------

## The value paths of this system, or null for any other.
static func value(game, path: String) -> Variant:
	match path:
		"here.door_zone":
			return door_zone(game)
		"arrival.from", PICKING:
			return str(game.state.values.get(path, ""))
	return null


# --- Extended play ----------------------------------------------------------------------

## The survival rules' `no rescue when:` holds: the rescue never comes (the original's playon).
static func no_rescue(game) -> bool:
	var when: String = SurvivalSystem.text(game, "no rescue when", "")
	if when == "":
		return false
	var c := Condition.compile(when)
	return not c.has("error") and Condition.evaluate(c, game)


# --- Validation -------------------------------------------------------------------------

## Checks one of this system's effects.
static func check_effect(v, e: Dictionary, line: int) -> void:
	match str(e.op):
		"world_event_zones", "world_event_level":
			if not v.db.has(e.event, "event"):
				v._err(line, "Event '%s' does not exist.%s" % [e.event, v._suggest(e.event, v._ids("event"))])
				return
			if e.op == "world_event_level":
				if e.amount.has("value"):
					v._check_expr(e.amount.value, line)
				return
			for z: String in e.zones:
				v._need(z, "zone", line)
			var found := ContentDB.found_by(v.db.typed_value("event", e.event, "found by"))
			if not found.walking.is_empty() or not found.travelling.is_empty() or not found.leaving.is_empty():
				v._warn(line, "%s is found by arriving or leaving somewhere; ~ event %s found in ... changes only the zones exploring and scavenging use." % [e.event, e.event])
		"world_shift", "world_transform":
			if "." in str(e.form):
				v._check_path(e.form, line)
			elif not v.db.has(e.form, "form") and not v.db.has(e.form, "creature"):
				v._err(line, "'%s' is neither a creature nor a form.%s" % [e.form, v._suggest(e.form, v._ids("creature"))])
		"world_ask_creature":
			v._check_path(e.path, line)
			var kind: String = v.db.values.get(e.path, {}).get("kind", "")
			if kind not in ["", "text"]:
				v._err(line, "~ ask ... as creature met stores a creature's ID: '%s' must be a text value." % e.path)
			v._check_template(e.prompt, line, "")
		"world_character_name", "world_character_text":
			if not v.db.has(e.who, "character"):
				v._err(line, "Character '%s' does not exist.%s" % [e.who, v._suggest(e.who, v._ids("character"))])
			if e.op == "world_character_text" and e.target != "default":
				v._check_target(e.target, line)


## Checks one of this system's conditions.
static func check_condition(v, c: Dictionary, line: int) -> void:
	if c.op == "world_banned":
		if "." in str(c.creature):
			v._check_path(c.creature, line)
		else:
			v._need(c.creature, "creature", line)


## Checks the readings of this system in an expression: `strength of wolf` names a
## creature or form; `creature named x` reads a text.
static func check_expr(v, node: Dictionary, line: int) -> void:
	match node.get("op", ""):
		"world_of":
			var inner: Dictionary = node.a
			if inner.get("op", "") == "word" and node.what != "creature named":
				if not v.db.has(inner.v, "creature") and not v.db.has(inner.v, "form"):
					v._err(line, "'%s of %s': '%s' is neither a creature nor a form.%s" % [node.what, inner.v, inner.v, v._suggest(inner.v, v._ids("creature"))])
			check_expr(v, inner, line)
		"world_random_item":
			if node.tag != "" and node.tag not in v._item_tags():
				v._warn(line, "No item has the tag '%s', so 'random carried item tagged %s' is always empty." % [node.tag, node.tag])
		"+", "-", "*", "/", "%", "random", "min", "max", "sqrt", "entry", "of":
			check_expr(v, node.a, line)
			if node.has("b"):
				check_expr(v, node.b, line)


## The value paths this system declares; true when `path` is one of them.
static func check_path(path: String) -> bool:
	return path in PATHS or path == CANCELLED


## Checks the fields this system reads: a companion's own name, a door's `going text`,
## an item's `cursed text` and the survival rules' `no rescue when`.
static func check(v) -> void:
	for id: String in v.db.all_of("item"):
		var d: FscParser.Definition = v.db.get_def("item", id)
		if d.fields.has("cursed text"):
			v._path = d.path
			if not d.fields.has("equipment"):
				v._err(d.fields["cursed text"].line, "%s: 'cursed text' is for gear that is cursed; it has no equipment: block." % id)
			elif not d.fields["equipment"].children.any(func(l: FscParser.Line) -> bool:
					return l.text.strip_edges().replace(" ", "") == "cursed:yes"):
				v._warn(d.fields["cursed text"].line, "%s is not cursed (cursed: yes under equipment:), so its 'cursed text' never plays." % id)
	for id: String in v.db.all_of("door"):
		var d: FscParser.Definition = v.db.get_def("door", id)
		if d.fields.has("going text") and v.db.typed_value("door", id, "leads to zone") == "":
			v._path = d.path
			v._warn(d.fields["going text"].line, "%s: 'going text' is said going through a dangerous door ('leads to zone:'); this door has none." % id)
	for id: String in v.db.all_of("survival_rules"):
		var d: FscParser.Definition = v.db.get_def("survival_rules", id)
		if d.fields.has("no rescue when"):
			v._path = d.path
			v._check_condition_text(d.fields["no rescue when"].value, d.fields["no rescue when"].line, "survival_rules:" + id)
