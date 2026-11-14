class_name Effect
extends RefCounted
## Compiles effects (`~ ...` lines) into Dictionaries the runtime applies.
##
## Every effect has "op" and "quiet" (true when the line ends in `quietly`).
## Amounts are compiled with amount(): a number, a range (`25 to 40`), a
## percentage (`10%`) or arithmetic (`player.thirst / 3`), with an optional
## limit (`up to 0`, `down to 5`).

const SURVIVAL := ["drink", "eat", "heal", "hurt"]
const PLAYER_STATS := ["humanity", "libido", "morale", "xp", "score", "freecred", "hp", "hunger", "thirst",
	"strength", "dexterity", "stamina", "charisma", "intelligence", "perception"]

static var _cache: Dictionary = {}
static var _rules: Array = [
	["cancel_use", RegEx.create_from_string("^cancel use$")],
	# In a creature's encounter: the meeting ends without a fight (the original's combat abort).
	["no_fight", RegEx.create_from_string("^no fight$")],
	["resolve", RegEx.create_from_string("^resolve(?: (\\w+))?$")],
	["end_pregnancy", RegEx.create_from_string("^end pregnancy$")],
	["end_heat", RegEx.create_from_string("^end heat$")],
	["reset_human", RegEx.create_from_string("^reset to human$")],
	["outcome_of", RegEx.create_from_string("^outcome (\\w+) of (\\w+)$")],
	["outcome", RegEx.create_from_string("^outcome (\\w+)$")],
	["activate", RegEx.create_from_string("^(activate|deactivate) (\\w+)$")],
	["quest", RegEx.create_from_string("^quest (\\w+) = (\\w+)$")],
	["feat", RegEx.create_from_string("^feat ([+-]) (\\w+)$")],
	["trait", RegEx.create_from_string("^(\\w+) trait ([+-]) (\\w+)$")],
	["companion", RegEx.create_from_string("^companion ([+-]) (\\w+)$")],
	["condition", RegEx.create_from_string("^condition (\\w+) for (\\d+) (hours?|turns?)$")],
	["spend", RegEx.create_from_string("^spend (\\d+) turns?$")],
	["schedule", RegEx.create_from_string("^schedule ([a-z0-9_.]+) after (\\d+) actions?$")],
	["give_one", RegEx.create_from_string("^give one of ([a-z0-9_, ]+)$")],
	["give", RegEx.create_from_string("^give ([a-z0-9_]+(?:\\.[a-z0-9_.]+)?)(?: (.+))?$")],
	["gear", RegEx.create_from_string("^(wear|remove|wield) (\\w+)$")],
	["unwield", RegEx.create_from_string("^unwield$")],
	["resize", RegEx.create_from_string("^resize to ([1-5])$")],
	["meter", RegEx.create_from_string("^meter (\\w+) ([+-]) (.+)$")],
	["take_all", RegEx.create_from_string("^take all (\\w+)$")],
	["take", RegEx.create_from_string("^take (\\w+)(?: (.+))?$")],
	["move", RegEx.create_from_string("^move (\\w+) to (\\w+)$")],
	# A creature's zones or infection change in play: "creature centaur found in plains",
	# "creature centaur found in nowhere", "creature centaur infectious yes", "creature rabbit gender female".
	["creature_change", RegEx.create_from_string("^creature (\\w+) (found in|infectious|gender) ([a-z0-9_, ]+)$")],
	["lives_at", RegEx.create_from_string("^(\\w+) lives at (\\w+)$")],
	["discover", RegEx.create_from_string("^discover (\\w+)$")],
	["go", RegEx.create_from_string("^go to (\\w+)$")],
	["infect_part", RegEx.create_from_string("^infect with player (head|torso|body|skin|tail|cock|cunt|face)$")],
	["infect", RegEx.create_from_string("^infect (\\w+)(?: (.+?) times?)?( keeping sex)?$")],
	["transform", RegEx.create_from_string("^transform into (\\w+)$")],
	["sex", RegEx.create_from_string("^sex (\\w+) receives (\\w+) from (\\w+)$")],
	["infects_as", RegEx.create_from_string("^this fight infects as (\\w+)$")],
	["no_infection", RegEx.create_from_string("^this fight does not infect$")],
	["ending", RegEx.create_from_string("^ending (\\w+)$")],
	["pregnancy_faster", RegEx.create_from_string("^pregnancy faster by (\\d+)$")],
	["extend_heat", RegEx.create_from_string("^extend heat by (\\d+) turns?$")],
	["survival", RegEx.create_from_string("^(drink|eat|heal|hurt) (.+)$")],
	["stat", RegEx.create_from_string("^(humanity|libido|morale|hunger|thirst|xp|score|freecred) ([+-]) (.+)$")],
	["set", RegEx.create_from_string("^([a-z0-9_]+\\.[a-z0-9_.]+) = (.+)$")],
	["change", RegEx.create_from_string("^([a-z0-9_]+\\.[a-z0-9_.]+) ([+-]) (.+)$")],
]
static var _limit_re := RegEx.create_from_string("^(.*?) (up to|down to) (-?\\d+)$")
static var _range_re := RegEx.create_from_string("^(-?\\d+) to (-?\\d+)$")
static var _percent_re := RegEx.create_from_string("^(\\d+)%$")


## Compiles one effect line (without the leading `~`).
static func compile(text: String) -> Dictionary:
	var key := text.strip_edges()
	if _cache.has(key):
		return _cache[key]
	var s := key
	var quiet := false
	if s.ends_with(" quietly"):
		quiet = true
		s = s.substr(0, s.length() - 8).strip_edges()
	var node := _match(s)
	node["quiet"] = quiet
	_cache[key] = node
	return node


static func _match(s: String) -> Dictionary:
	for rule in _rules:
		var m: RegExMatch = rule[1].search(s)
		if m == null:
			continue
		match rule[0]:
			"resolve":
				# "resolve" ends this event; "resolve other_event" ends another one.
				return {"op": "resolve", "event": m.get_string(1)}
			"cancel_use", "no_fight", "end_pregnancy", "end_heat", "reset_human":
				return {"op": rule[0]}
			"outcome":
				return {"op": "outcome", "outcome": m.get_string(1)}
			"outcome_of":
				# Another event's outcome ("~ outcome defeated of dullahan_knight").
				return {"op": "outcome", "outcome": m.get_string(1), "event": m.get_string(2)}
			"activate":
				return {"op": m.get_string(1), "event": m.get_string(2)}
			"quest":
				return {"op": "quest", "quest": m.get_string(1), "stage": m.get_string(2)}
			"feat":
				return {"op": "feat", "add": m.get_string(1) == "+", "feat": m.get_string(2)}
			"trait":
				return {"op": "trait", "who": m.get_string(1), "add": m.get_string(2) == "+", "trait": m.get_string(3)}
			"companion":
				return {"op": "companion", "add": m.get_string(1) == "+", "who": m.get_string(2)}
			"condition":
				var n := int(m.get_string(2))
				var turns := n if m.get_string(3).begins_with("turn") else int(ceil(n / 3.0))
				return {"op": "condition", "condition": m.get_string(1), "turns": turns}
			"spend":
				return {"op": "spend", "turns": int(m.get_string(1))}
			"schedule":
				if int(m.get_string(2)) < 1:
					return {"error": "Schedule delay must be at least 1 action."}
				return {"op": "schedule", "scene": m.get_string(1), "actions": int(m.get_string(2))}
			"give", "take":
				var amt := amount(m.get_string(2)) if m.get_string(2) != "" else {"value": {"op": "num", "v": 1}}
				if amt.has("error"):
					return {"error": amt.error}
				# "give food" names an item; "give event.item" gives the item a value holds.
				var item := m.get_string(1)
				if "." in item:
					return {"op": rule[0], "item": "", "item_path": item, "amount": amt}
				return {"op": rule[0], "item": item, "amount": amt}
			"take_all":
				return {"op": "take_all", "item": m.get_string(1)}
			"give_one":
				var items: Array = []
				for it in m.get_string(1).split(","):
					if it.strip_edges() != "":
						items.append(it.strip_edges())
				return {"op": "give_one", "items": items}
			"gear":
				return {"op": m.get_string(1), "item": m.get_string(2)}
			"unwield":
				return {"op": "unwield"}
			"resize":
				return {"op": "resize", "to": int(m.get_string(1))}
			"meter":
				var amt := amount(m.get_string(3))
				if amt.has("error"):
					return {"error": amt.error}
				return {"op": "meter", "meter": m.get_string(1), "sign": 1 if m.get_string(2) == "+" else -1, "amount": amt}
			"move":
				return {"op": "move", "who": m.get_string(1), "place": m.get_string(2)}
			"creature_change":
				return {"op": "creature_change", "creature": m.get_string(1), "field": m.get_string(2), "value": m.get_string(3).strip_edges()}
			"lives_at":
				return {"op": "lives_at", "who": m.get_string(1), "place": m.get_string(2)}
			"discover":
				return {"op": "discover", "place": m.get_string(1)}
			"go":
				return {"op": "go", "place": m.get_string(1)}
			"infect_part":
				# The strain the player's part already has (the original's "infect BodyName of Player").
				return {"op": "infect", "part": {"body": "torso", "face": "head"}.get(m.get_string(1), m.get_string(1)), "form": "", "times": {"value": {"op": "num", "v": 1}}, "keep_sex": false}
			"infect":
				var times := amount(m.get_string(2)) if m.get_string(2) != "" else {"value": {"op": "num", "v": 1}}
				if times.has("error"):
					return {"error": times.error}
				return {"op": "infect", "form": m.get_string(1), "times": times, "keep_sex": m.get_string(3) != ""}
			"transform":
				return {"op": "transform", "form": m.get_string(1)}
			"sex":
				return {"op": "sex", "taker": m.get_string(1), "act": m.get_string(2), "giver": m.get_string(3)}
			"infects_as":
				return {"op": "infects_as", "creature": m.get_string(1)}
			"no_infection":
				return {"op": "infects_as", "creature": ""}
			"ending":
				return {"op": "ending", "ending": m.get_string(1)}
			"pregnancy_faster":
				return {"op": "pregnancy_faster", "by": int(m.get_string(1))}
			"extend_heat":
				return {"op": "extend_heat", "turns": int(m.get_string(1))}
			"survival":
				var amt := amount(m.get_string(2))
				if amt.has("error"):
					return {"error": amt.error}
				return {"op": "survival", "kind": m.get_string(1), "amount": amt}
			"stat":
				var amt := amount(m.get_string(3))
				if amt.has("error"):
					return {"error": amt.error}
				return {"op": "change", "path": "player." + m.get_string(1), "sign": 1 if m.get_string(2) == "+" else -1, "amount": amt}
			"set":
				# "~ x = 6 to 16" or "~ x = 1 to player.charisma" picks a whole number in the range.
				var bounds := m.get_string(2).split(" to ")
				if bounds.size() == 2:
					var low := Expr.parse(bounds[0])
					var high := Expr.parse(bounds[1])
					if not low.has("error") and not high.has("error"):
						return {"op": "set", "path": m.get_string(1), "value": {"op": "num", "v": 0}, "range": [low, high]}
					# Otherwise the "to" belongs to an expression such as "10 + (random 1 to 50)".
				var value := Expr.parse(m.get_string(2))
				if value.has("error"):
					return {"error": "cannot read value '%s': %s" % [m.get_string(2), value.error]}
				return {"op": "set", "path": m.get_string(1), "value": value}
			"change":
				var amt := amount(m.get_string(3))
				if amt.has("error"):
					return {"error": amt.error}
				return {"op": "change", "path": m.get_string(1), "sign": 1 if m.get_string(2) == "+" else -1, "amount": amt}
	return {"error": "unknown effect '%s'" % s}


## Compiles an amount: {"value": expr} | {"min": a, "max": b} | {"percent": n},
## each with optional "limit" ("up"/"down") and "limit_value".
static func amount(text: String) -> Dictionary:
	var s := text.strip_edges()
	var out := {}
	var lm := _limit_re.search(s)
	if lm != null:
		s = lm.get_string(1).strip_edges()
		out["limit"] = "up" if lm.get_string(2) == "up to" else "down"
		out["limit_value"] = int(lm.get_string(3))
	var rm := _range_re.search(s)
	if rm != null:
		out["min"] = int(rm.get_string(1))
		out["max"] = int(rm.get_string(2))
		return out
	var pm := _percent_re.search(s)
	if pm != null:
		out["percent"] = int(pm.get_string(1))
		return out
	var e := Expr.parse(s)
	if e.has("error"):
		return {"error": "cannot read amount '%s': %s" % [text, e.error]}
	out["value"] = e
	return out


## Resolves an amount to a number. `base` is the current value (for percent).
static func resolve_amount(a: Dictionary, ctx, base: int = 0) -> int:
	if a.has("min"):
		return ctx.rng.range_int(a.min, a.max)
	if a.has("percent"):
		return int(abs(base) * a.percent / 100)
	return Expr._num(Expr.evaluate(a.value, ctx))
