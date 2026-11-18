class_name HuntSystem
extends RefCounted
## Hunting a creature, after the original's hunt command (Hunting and
## Exploration.i7x). Without `== hunt_rules` the hunted creature is always met.
## With them, it is one entry in a pool the hunt draws from:
##
##   == hunt_rules my_hunting
##   target weight: 2                          (an expression; entries of the target)
##   target weight modifiers:
##       player has feat tracker: + 2          ("condition: amount" lines)
##   others when: not player has feat loner    (whether the zone's other creatures join)
##   other skipped when: chance 1 in 3         (tested for each other creature)
##   kindred when: player has feat herdmate    (creatures of the player's own strain join too:
##   kindred chance: 1 in 2                    once for each body part of that strain, by chance)
##   not found:
##       You find no trace of it.              (played when the pool is empty)
##
## Hooks `on: hunting` run before the draw and may put creatures in with
## `~ hunt may meet <creature> [N times]` (something that hunts the player).
##
## The other creatures are those random meetings could bring (bans and wards
## apply); the hunt then meets whoever is drawn.
##
## With `by name: yes` the player may also type what they hunt for: a place, an
## event or a creature (the original's `hunt <name>`). The name is tried as the
## whole name of a place, an event, a creature, then as a part of the name of a
## place not known yet, a creature, an event. A place or an event is found
## with a search, a visible roll:
##
##   by name: yes
##   events listed when: player has feat pathfinder   (the zone's events are offered too)
##   tracks: You saw some [hunt.name] tracks...       (before a creature is met)
##   searching: It should be somewhere...             (before a place or event is searched for)
##   search bonus: (player.perception - 10) / 2       (without a `search target`, always found)
##   search bonus modifiers:
##       player has feat curious: + 2
##   search target: 15
##   search label: Perception
##   search certain when: player has feat pathfinder  (found without a roll)
##   place found: You find your way towards [hunt.name]!
##   event found: You find your way to **[hunt.name]**!
##   place not found: You fail to find it.            (the roll failed; then the answer `search failed`)
##   event not found: You fail to find it.
##   search fight: Setting out, you meet someone.     (a creature may come up on the way)
##
## and a line for each way a hunt by name ends without a meeting (ANSWERS).


static func rules(game) -> String:
	var defs: Dictionary = game.content.all_of("hunt_rules")
	return "" if defs.is_empty() else str(defs.keys()[0])


static func _field(game, field: String, fallback: String = "") -> String:
	var id := rules(game)
	return fallback if id == "" else game.content.typed_value("hunt_rules", id, field, fallback)


static func _holds(game, field: String, fallback: bool) -> bool:
	var text := _field(game, field)
	if text == "":
		return fallback
	return Condition.evaluate(Condition.compile(text), game)


## Whether hunting is possible now (`hunt when`; true without it).
static func allowed(game) -> bool:
	return _holds(game, "hunt when", true)


## The target's entries in the pool: `target weight` plus its modifiers.
static func target_weight(game) -> int:
	var e := Expr.parse(_field(game, "target weight", "1"))
	var n: int = 1 if e.has("error") else int(Expr._num(Expr.evaluate(e, game)))
	var d: FscParser.Definition = game.content.get_def("hunt_rules", rules(game))
	if d != null and d.fields.has("target weight modifiers"):
		for l: FscParser.Line in d.fields["target weight modifiers"].children:
			if l.is_blank() or not ":" in l.text:
				continue
			var p := l.text.rsplit(":", true, 1)
			if Condition.evaluate(Condition.compile(p[0].strip_edges()), game):
				var amount := Expr.parse(CompanionSystem.amount_text(p[1]))
				if not amount.has("error"):
					n += int(Expr._num(Expr.evaluate(amount, game)))
	return maxi(0, n)


## The creature a hunt for `target` in `zone` meets, or "" when nothing is found.
static func pick(game, target: String, zone: String) -> String:
	var joined := extras(game)  # what the hooks `on: hunting` put in (`~ hunt may meet <creature>`)
	game.state.values.erase(EXTRAS)
	if rules(game) == "":
		return target
	var pool: Array = []
	for _i in target_weight(game):
		pool.append(target)
	if _holds(game, "others when", true):
		for id: String in game.runner.encounter_pool(zone):
			if id != target and not _holds(game, "other skipped when", false):
				pool.append(id)
	# Kindred: a creature of the zone whose strain a part of the player's body has
	# may join once for each such part (`kindred when`, `kindred chance: 1 in 2`).
	if _holds(game, "kindred when", false):
		var chance := _field(game, "kindred chance", "1 in 1").split(" in ")
		for id: String in game.runner.encounter_pool(zone, true):
			for _part in CombatSystem.kindred(game, id):
				if chance.size() != 2 or game.rng.chance(int(chance[0]), int(chance[1])):
					pool.append(id)
	pool.append_array(joined)
	if pool.is_empty():
		return ""
	return str(pool[game.rng.range_int(0, pool.size() - 1)])


## Where the creatures hooks add to the hunt going on are kept until the draw.
const EXTRAS := "hunt.extras"


## Starts a hunt's draw: the hooks `on: hunting` run and may add creatures.
static func gather_extras(game) -> void:
	game.state.values[EXTRAS] = []
	if game.has_hook("hunting"):
		game.run_hooks("hunting")


## `~ hunt may meet <creature> N times`: the creature joins the draw (not a banned one).
static func add_extra(game, creature: String, times: int) -> void:
	if not game.content.has(creature, "creature") or not game.state.values.has(EXTRAS):
		return
	if game.filter_block(CreatureChangeSystem.creature_tags(game, creature), true) != "":
		return
	for _i in maxi(0, times):
		(game.state.values[EXTRAS] as Array).append(creature)


static func extras(game) -> Array:
	var kept: Variant = game.state.values.get(EXTRAS, [])
	return (kept as Array).duplicate() if kept is Array else []


# --- Hunting by name ----------------------------------------------------------

## The ways a hunt by name ends with nothing met; each is a text field of the rules.
const ANSWERS: Array = ["nothing found", "wrong time", "wrong area", "creature banned",
	"place hidden", "place unreachable", "search failed", "event elsewhere", "event too hard",
	"event resolved", "event not ready", "event inactive"]

## What the engine says when the rules have no line of their own.
const _PLAIN: Dictionary = {
	"nothing found": "Nothing by that name can be found here.",
	"wrong time": "None of them are around at this time of day.",
	"wrong area": "That creature does not roam this area.",
	"creature banned": "That creature is banned by your settings.",
	"place hidden": "There is no way there that you could find alone.",
	"place unreachable": "That place cannot be travelled to.",
	"search failed": "You search for a while but do not find it.",
	"event elsewhere": "That is not to be found in this area.",
	"event too hard": "You are not ready to find that yet.",
	"event resolved": "That is already done.",
	"event not ready": "Something else has to happen first.",
	"event inactive": "That cannot be found right now.",
}


## Whether the player may type what they hunt for (`by name: yes`).
static func by_name(game) -> bool:
	return _field(game, "by name") == "yes"


## Says one of the rules' texts about `name` ("[hunt.name]" in it); for an
## answer without a line, the engine's plain one.
static func say(game, field: String, name: String = "") -> void:
	game.state.values["hunt.name"] = name
	var template := _field(game, field, str(_PLAIN.get(field, "")))
	if template.strip_edges() == "":
		return
	var compiled := TextTemplate.compile(template)
	if not compiled.has("error"):
		game.emit({"type": "paragraph", "spans": game.render(compiled)})


## The search for a place or an event: true when it is found. Without a
## `search target` it always is; `search certain when` finds it without a roll.
static func search(game) -> bool:
	var target_text := _field(game, "search target")
	if target_text == "" or _holds(game, "search certain when", false):
		return true
	var bonus := _number(game, _field(game, "search bonus", "0"))
	var d: FscParser.Definition = game.content.get_def("hunt_rules", rules(game))
	if d != null and d.fields.has("search bonus modifiers"):
		for l: FscParser.Line in d.fields["search bonus modifiers"].children:
			if l.is_blank() or not ":" in l.text:
				continue
			var p := l.text.rsplit(":", true, 1)
			if Condition.evaluate(Condition.compile(p[0].strip_edges()), game):
				bonus += _number(game, CompanionSystem.amount_text(p[1]))
	var label := _field(game, "search label")
	return game.roll_check(label, bonus, _number(game, target_text), label.to_lower().replace(" ", "_"))


static func _number(game, text: String) -> int:
	var e := Expr.parse(text)
	return 0 if e.has("error") else int(Expr._num(Expr.evaluate(e, game)))


## A name as it is compared: lower case, single spaces.
static func plain(text: String) -> String:
	return " ".join(text.to_lower().split(" ", false)).strip_edges()


## The names a thing answers to when hunted: its `name` and `original name`s
## (a creature also its `title` and `personal name`).
static func names_of(game, type: String, id: String) -> Array:
	var out: Array = []
	var fields: Array = ["name", "title", "personal name"] if type == "creature" else ["name"]
	for f: String in fields:
		var n := plain(game.creature_field(id, f) if type == "creature" else game.content.typed_value(type, id, f))
		if n != "" and n not in out:
			out.append(n)
	for n: String in game.content.typed_value(type, id, "original name").split(",", false):
		if plain(n) != "" and plain(n) not in out:
			out.append(plain(n))
	return out


## The things of a type whose name is `want` (or, with `part`, holds it), sorted by ID.
static func _named(game, type: String, want: String, part: bool) -> Array:
	var out: Array = []
	for id: String in game.content.all_of(type):
		for n: String in names_of(game, type, id):
			if n == want or (part and want in n):
				out.append(id)
				break
	out.sort()
	return out


## What a typed name stands for here: `kind` ("place", "event", "creature" or
## "" when nothing is named so), its `id`, and `answer`: "" when the hunt goes
## ahead, else one of ANSWERS.
static func find(game, text: String, zone: String) -> Dictionary:
	var want := plain(text)
	var nothing := {"kind": "", "id": "", "answer": "nothing found"}
	if want == "":
		return nothing
	# The whole name: a place, then an event, then a creature.
	var places := _named(game, "location", want, false)
	if not places.is_empty():
		# Of places sharing a name, one that can be travelled to.
		var best: String = places[0]
		for id: String in places:
			if place_answer(game, id) == "":
				best = id
				break
		return {"kind": "place", "id": best, "answer": place_answer(game, best)}
	var found := _first_open(game, "event", _named(game, "event", want, false), zone)
	if not found.is_empty():
		return found
	found = _first_open(game, "creature", _named(game, "creature", want, false), zone)
	if not found.is_empty():
		return found
	# A part of the name: a place not known yet, then a creature, then an event.
	for id: String in _named(game, "location", want, true):
		if not game.state.known.has(id) and place_answer(game, id) == "":
			return {"kind": "place", "id": id, "answer": ""}
	var roaming: Array = _named(game, "creature", want, true).filter(func(id: String) -> bool:
		return game.creature_field(id, "found in", "nowhere") not in ["", "nowhere"])
	found = _first_open(game, "creature", roaming, zone)
	if found.is_empty() or found.answer != "":
		var open_events: Array = _named(game, "event", want, true).filter(func(id: String) -> bool:
			return not game._event(id).resolved)
		var event := _first_open(game, "event", open_events, zone)
		if not event.is_empty():
			found = event
	return nothing if found.is_empty() else found


## Of several things answering to a name: the first that can be hunted now,
## else the last one with the reason it cannot. Empty when there are none.
static func _first_open(game, kind: String, ids: Array, zone: String) -> Dictionary:
	var out := {}
	for id: String in ids:
		var answer := event_answer(game, id, zone) if kind == "event" else creature_answer(game, id, zone)
		out = {"kind": kind, "id": id, "answer": answer}
		if answer == "":
			break
	return out


## Why a place cannot be hunted for ("" when it can): only places that can be
## travelled to, and not the hidden ones (`flags: private`).
static func place_answer(game, id: String) -> String:
	var flags: Array = game.content.list_field(id, "flags")
	if "private" in flags:
		return "place hidden"
	return "" if "fast travel" in flags else "place unreachable"


## Why an event cannot be hunted for in a zone ("" when it can).
static func event_answer(game, id: String, zone: String) -> String:
	var db: ContentDB = game.content
	var st: Dictionary = game._event(id)
	if st.resolved:
		return "event resolved"
	if not st.active or game.filter_block(db._list(db.get_def("event", id), "tags"), true) != "":
		return "event inactive"
	var found := WorldSystem.event_found(game, id)
	if not found.exploring or zone not in found.zones:
		return "event elsewhere"
	if int(game.value("player.level")) < WorldSystem.event_level(game, id):
		return "event too hard"
	if int(game.value("player.score")) < int(db.typed_value("event", id, "min score", "-2147483648")) \
			or not game.runner._event_requires(id, "requires") or not game.runner._event_requires(id, "exploring requires"):
		return "event not ready"
	return ""


## Why a creature cannot be hunted in a zone ("" when it can).
static func creature_answer(game, id: String, zone: String) -> String:
	if id in game.runner.encounter_pool(zone, true):
		return ""
	var skip := VariantSystem.all_filters(game.content, id)
	if game.filter_block(CreatureChangeSystem.creature_tags(game, id).filter(func(t): return t not in skip), true) != "" \
			or not VariantSystem.meetable(game, id, true):
		return "creature banned"
	var active: String = game.content.typed_value("creature", id, "active", "always")
	if (active == "day" and not game.is_day()) or (active == "night" and game.is_day()):
		return "wrong time"
	return "nothing found" if roams(game, id, zone) else "wrong area"


## Whether a creature is one of a zone's (at any time of day, banned or not).
static func roams(game, id: String, zone: String) -> bool:
	return zone in Array(game.creature_field(id, "found in").split(",")).map(func(z: String) -> String: return z.strip_edges())


## The name a hunted creature's tracks are told by: its own name when the
## player knows it, else its title or name in lower case.
static func creature_name(game, id: String) -> String:
	if game.creature_field(id, "name known", "no") == "yes" and game.creature_field(id, "personal name") != "":
		return game.creature_field(id, "personal name")
	var title: String = game.creature_field(id, "title")
	return (title if title != "" else str(game.creature_field(id, "name", id))).to_lower()


## The zone's events offered by name in the hunt (`events listed when`), by name.
static func listed_events(game, zone: String) -> Array:
	if not by_name(game) or not _holds(game, "events listed when", false):
		return []
	var out: Array = []
	for id: String in game.content.all_of("event"):
		if game.content.typed_value("event", id, "name") != "" and event_answer(game, id, zone) == "":
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		return game.content.typed_value("event", a, "name").naturalnocasecmp_to(game.content.typed_value("event", b, "name")) < 0)
	return out
