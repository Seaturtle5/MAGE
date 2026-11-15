class_name Effect
extends RefCounted
## Compiles effects (`~ ...` lines) into Dictionaries the runtime applies.
##
## Every effect has "op" and "quiet" (true when the line ends in `quietly`).
## Amounts are compiled with amount(): a number, a range (`25 to 40`), a
## percentage (`10%`) or arithmetic (`player.thirst / 3`), with an optional
## limit (`up to 0`, `down to 5`).

const SURVIVAL := ["drink", "eat", "heal", "hurt"]
const PLAYER_STATS := ["xp", "score", "hp", "hunger", "thirst",
	"strength", "dexterity", "stamina", "charisma", "intelligence", "perception"]

static var _cache: Dictionary = {}
static var _rules: Array = [
	["cancel_use", RegEx.create_from_string("^cancel use$")],
	# In a creature's encounter: the meeting ends without a fight (the original's combat abort).
	["no_fight", RegEx.create_from_string("^no fight$")],
	["resolve", RegEx.create_from_string("^resolve(?: (\\w+))?$")],
	# "~ unresolve other_event": it can be found again (the original's "now X is unresolved").
	["unresolve", RegEx.create_from_string("^unresolve (\\w+)$")],
	["end_pregnancy", RegEx.create_from_string("^end pregnancy$")],
	# Vore (VoreSystem): "~ vore enemy", "~ unbirth enemy", and what the vore scripts do.
	["vore", RegEx.create_from_string("^(vore|unbirth) enemy$")],
	["vore_step", RegEx.create_from_string("^(absorb enemy stat|infect enemy|unbirth pregnancy)$")],
	# Pregnancy (PregnancySystem): "~ impregnation chance", "~ impregnate female by wolf with eggs".
	["impregnate", RegEx.create_from_string("^(impregnation chance|impregnate)(?: (female|male|self))?(?: by (random creature|\\w+))?( with eggs?)?$")],
	["pregnancy_step", RegEx.create_from_string("^(accept pregnancy|give birth|record child)$")],
	["each_child", RegEx.create_from_string("^for each child(?: at (\\w+))? play (\\w[\\w.]*)$")],
	# A story child: "~ new child" clears the last child's values; "~ child.gender = random" and
	# "~ child.personality = random" draw them as a birth does (the pregnancy rules' lists).
	["new_child", RegEx.create_from_string("^new child$")],
	["child_random", RegEx.create_from_string("^child\\.(gender|personality) = random$")],
	# Lists (a value declared `list`): "~ add 1 to x.list", "~ add 1, 2 to x.list if absent",
	# "~ remove 3 from x.list", "~ remove entry 1 from x.list", "~ clear x.list",
	# "~ sort x.list", "~ sort x.list in random order" (or "in reverse order").
	["list_add", RegEx.create_from_string("^add (.+) to ([a-z0-9_]+\\.[a-z0-9_.]+)(,? if absent)?$")],
	["list_remove_entry", RegEx.create_from_string("^remove entry (.+) from ([a-z0-9_]+\\.[a-z0-9_.]+)$")],
	["list_remove", RegEx.create_from_string("^remove (.+) from ([a-z0-9_]+\\.[a-z0-9_.]+)$")],
	["list_clear", RegEx.create_from_string("^clear ([a-z0-9_]+\\.[a-z0-9_.]+)$")],
	["list_sort", RegEx.create_from_string("^sort ([a-z0-9_]+\\.[a-z0-9_.]+)(?: in (random|reverse) order)?$")],
	# Doors locked or unlocked in play (saved): "~ unlock cell_door", "~ lock cell_door".
	["lock", RegEx.create_from_string("^(lock|unlock) (\\w+)$")],
	["end_heat", RegEx.create_from_string("^end heat$")],
	["reset_heat", RegEx.create_from_string("^reset heat$")],
	["continue_moving", RegEx.create_from_string("^continue moving$")],
	["end_captivity", RegEx.create_from_string("^(end|escape) captivity$")],
	["drive_heat", RegEx.create_from_string("^drive heat( now)?$")],
	["set_level", RegEx.create_from_string("^level (\\w+) = (\\w+)$")],
	["reset_human", RegEx.create_from_string("^reset to human$")],
	["outcome_of", RegEx.create_from_string("^outcome (\\w+) of (\\w+)$")],
	["outcome", RegEx.create_from_string("^outcome (\\w+)$")],
	["activate", RegEx.create_from_string("^(activate|deactivate) (\\w+)$")],
	["quest", RegEx.create_from_string("^quest (\\w+) = (\\w+)$")],
	["feat", RegEx.create_from_string("^feat ([+-]) (\\w+)$")],
	["trait", RegEx.create_from_string("^(\\w+) trait ([+-]) (\\w+)$")],
	["companion", RegEx.create_from_string("^companion ([+-]) (\\w+)$")],
	# Companions (CompanionSystem): "~ tame korvin", "~ summon korvin", "~ dismiss korvin",
	# "~ cancel summon" in a summon text, "~ level up korvin", "~ send children from with_you to bunker".
	["tame", RegEx.create_from_string("^(tame|untame) (\\w+)$")],
	["summon", RegEx.create_from_string("^(summon|dismiss) (\\w+)$")],
	["cancel_companion", RegEx.create_from_string("^cancel (summon|dismiss)$")],
	["check_level", RegEx.create_from_string("^check level$")],
	["choose_feat", RegEx.create_from_string("^choose feat (\\w+)$")],
	# Typed text into a value: "~ ask child.name: Please name your child".
	# A typed number: "~ ask x.n as number from 0 to 13: How long?" (asked again until it fits).
	["ask_number", RegEx.create_from_string("^ask ([a-z_][a-z0-9_]*(?:\\.[a-z0-9_]+)+) as (?:a )?number(?: from (.+?) to (.+?))?:\\s*(.+)$")],
	["ask", RegEx.create_from_string("^ask ([a-z_][a-z0-9_]*(?:\\.[a-z0-9_]+)+)(?: up to (\\d+) letters)?:\\s*(.+)$")],
	["companion_level", RegEx.create_from_string("^level up (\\w+)$")],
	["send_children", RegEx.create_from_string("^send children from (\\w+) to (\\w+)$")],
	["condition", RegEx.create_from_string("^condition (\\w+) for (\\d+) (hours?|turns?)$")],
	["spend", RegEx.create_from_string("^spend (\\d+) turns?$")],
	["schedule", RegEx.create_from_string("^schedule ([a-z0-9_.]+) after (\\d+) actions?$")],
	["give_one", RegEx.create_from_string("^give one of ([a-z0-9_, ]+)$")],
	["give", RegEx.create_from_string("^give ([a-z0-9_]+(?:\\.[a-z0-9_.]+)?)(?: (.+))?$")],
	["gear", RegEx.create_from_string("^(wear|remove|wield) (\\w+)$")],
	["unwield", RegEx.create_from_string("^unwield$")],
	["resize", RegEx.create_from_string("^resize to ([1-5])$")],
	["meter", RegEx.create_from_string("^meter (\\w+) ([+-]) (.+)$")],
	# Fights (CombatSystem): the creature's blows and the end of a fight, from its scripts.
	["enemy_attack", RegEx.create_from_string("^enemy attack(?: (\\d+)%)?$")],
	["enemy_strike", RegEx.create_from_string("^enemy strike(?: (\\d+)%| for (.+?))?(?: (ignoring armor|through half armor|without shield))?$")],
	["fight_result", RegEx.create_from_string("^(lose|win) fight(?: by (lust|injury|submitting|seduction|fighting))?$")],
	# The player's own moves from a fight's scene (a pepper spray: spray, then attack twice or flee).
	["player_move", RegEx.create_from_string("^(attack enemy|try to flee)$")],
	# Items lying in a place, and an item's infection, changed during play.
	["put", RegEx.create_from_string("^put (\\w+)(?: (\\d+))? in (\\w+)$")],
	["remove_from", RegEx.create_from_string("^remove (\\w+) from (\\w+)$")],
	["item_strain", RegEx.create_from_string("^item (\\w+) infects as (\\w+)$")],
	["creature_number", RegEx.create_from_string("^creature (\\w+) (damage|level|hp|libido|hit bonus|dodge bonus|strength|dexterity|stamina|perception|intelligence|charisma) ([+=-]) (.+)$")],
	["take_all", RegEx.create_from_string("^take all (\\w+)$")],
	["take", RegEx.create_from_string("^take (\\w+)(?: (.+))?$")],
	["move", RegEx.create_from_string("^move (\\w+) to (\\w+)$")],
	# A creature's zones or infection change in play: "creature centaur found in plains",
	# "creature centaur found in nowhere", "creature centaur infectious yes", "creature rabbit gender female".
	["grow", RegEx.create_from_string("^grow (cock|balls|breasts) by (.+)$")],
	# The infection's sex or breast change run again ("follow the sex change rule"), toward
	# the strain met or infected with last, or a named creature or form.
	# "keeping cock": a cock that appears keeps the strain the player's cock had (the original's skipcockchange).
	["sex_change", RegEx.create_from_string("^(sex|breast) change(?: toward (\\w+))?( keeping cock)?$")],
	# A form's genital and breast targets changed in play ("now Cock Length entry is 10").
	["form_number", RegEx.create_from_string("^form (\\w+) (cock count|cock length|ball size|cunt count|cunt depth|cunt tightness|breast size|male breast size|nipple count) = (.+)$")],
	# The map changed in play: "~ change north exit of park_trail to picnic_area" (or "to nothing").
	["change_exit", RegEx.create_from_string("^change (\\w+) exit of (\\w+) to (\\w+)$")],
	["form_sex", RegEx.create_from_string("^form (\\w+) sex (male|female|herm|neuter|unchanged)$")],
	["creature_change", RegEx.create_from_string("^creature (\\w+) (found in|infectious|gender|variant|loot|special|image|title|strike with) ([a-z0-9_,% ]+)$")],
	["lives_at", RegEx.create_from_string("^(\\w+) lives at (\\w+)$")],
	["discover", RegEx.create_from_string("^discover (\\w+)$")],
	["forget", RegEx.create_from_string("^forget (\\w+)$")],
	["use_item", RegEx.create_from_string("^use (\\w+)$")],
	["go", RegEx.create_from_string("^go to (\\w+)$")],
	["infect_part", RegEx.create_from_string("^infect with player (head|torso|body|skin|tail|cock|cunt|face)$")],
	["infect_picked", RegEx.create_from_string("^infect picked creature( keeping sex)?$")],
	["pick", RegEx.create_from_string("^pick random creature(?: tagged (\\w+))?(?: (nearby or outside|nearby|anywhere|in \\w+))?(?: favoring ([a-z0-9_, ]+))?$")],
	["infect", RegEx.create_from_string("^infect (\\w+)(?: (.+?) times?)?( keeping sex)?$")],
	["transform", RegEx.create_from_string("^transform into (\\w+)$")],
	["transform_part", RegEx.create_from_string("^transform (head|face|torso|body|back|arms|legs|ass|tail|cock|cunt|skin) into (\\w+)$")],
	["sex", RegEx.create_from_string("^sex (\\w+) receives (\\w+) from (\\w+)$")],
	["infects_as", RegEx.create_from_string("^this fight infects as (\\w+)$")],
	["no_infection", RegEx.create_from_string("^this fight does not infect$")],
	["ending", RegEx.create_from_string("^ending (\\w+)$")],
	# Endings (EndingSystem): mark one, what happened to the player, details for later endings.
	["trigger_ending", RegEx.create_from_string("^trigger ending (\\w+)$")],
	["end_state", RegEx.create_from_string("^player (dies|is imprisoned|leaves)$")],
	["ending_reason", RegEx.create_from_string("^ending reason (.+)$")],
	["ending_flag", RegEx.create_from_string("^ending flag (\\w+)$")],
	["exclude_endings", RegEx.create_from_string("^exclude (\\w+) endings$")],
	["pregnancy_faster", RegEx.create_from_string("^pregnancy faster by (\\d+)$")],
	["extend_heat", RegEx.create_from_string("^extend heat by (\\d+) turns?$")],
	["survival", RegEx.create_from_string("^(drink|eat|heal|hurt) (.+)$")],
	# "~ hunger + 5", "~ humanity - 3": a player value by its short name (any the engine or a pack declares).
	["stat", RegEx.create_from_string("^([a-z_]+) ([+-]) (.+)$")],
	["extend_game", RegEx.create_from_string("^extend game by (.+?) turns?$")],
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
			"unresolve":
				return {"op": "unresolve", "event": m.get_string(1)}
			"cancel_use", "no_fight", "end_pregnancy", "end_heat", "reset_heat", "reset_human", "continue_moving":
				return {"op": rule[0]}
			"impregnate":
				return {"op": "impregnate", "sure": m.get_string(1) == "impregnate", "kind": m.get_string(2),
					"father": m.get_string(3).replace("random creature", "random"), "eggs": m.get_string(4) != ""}
			"pregnancy_step":
				return {"op": m.get_string(1).replace(" ", "_")}
			"each_child":
				return {"op": "each_child", "home": m.get_string(1), "scene": m.get_string(2)}
			"new_child":
				return {"op": "new_child"}
			"child_random":
				return {"op": "child_random", "what": m.get_string(1)}
			"list_add", "list_remove", "list_remove_entry":
				var items: Array = []
				for part in _split_top(m.get_string(1)):
					var item := Expr.parse(part)
					if item.has("error"):
						return {"error": "cannot read '%s': %s" % [part, item.error]}
					items.append(item)
				if rule[0] == "list_remove_entry" and items.size() != 1:
					return {"error": "Remove one entry at a time: ~ remove entry 1 from x.list"}
				var node := {"op": rule[0], "path": m.get_string(2), "items": items}
				if rule[0] == "list_add":
					node["if_absent"] = m.get_string(3) != ""
				return node
			"list_clear":
				return {"op": "list_clear", "path": m.get_string(1)}
			"list_sort":
				return {"op": "list_sort", "path": m.get_string(1), "order": m.get_string(2)}
			"lock":
				return {"op": "lock", "door": m.get_string(2), "locked": m.get_string(1) == "lock"}
			"ask_number":
				var prompt := TextTemplate.compile(m.get_string(4))
				if prompt.has("error"):
					return {"error": prompt.error}
				var node := {"op": "ask", "path": m.get_string(1), "prompt": prompt, "max": 12, "number": true}
				for k in [["low", 2], ["high", 3]]:
					if m.get_string(k[1]) != "":
						var bound := Expr.parse(m.get_string(k[1]))
						if bound.has("error"):
							return {"error": "cannot read the number '%s': %s" % [m.get_string(k[1]), bound.error]}
						node[k[0]] = bound
				return node
			"vore":
				return {"op": "vore", "kind": m.get_string(1)}
			"vore_step":
				return {"op": m.get_string(1).replace(" ", "_")}
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
			"tame":
				return {"op": "tame", "yes": m.get_string(1) == "tame", "who": m.get_string(2)}
			"summon":
				return {"op": m.get_string(1), "who": m.get_string(2)}
			"cancel_companion":
				return {"op": "cancel_companion", "what": m.get_string(1)}
			"check_level":
				return {"op": "check_level"}
			"choose_feat":
				return {"op": "choose_feat", "group": m.get_string(1)}
			"ask":
				var prompt := TextTemplate.compile(m.get_string(3))
				if prompt.has("error"):
					return {"error": prompt.error}
				return {"op": "ask", "path": m.get_string(1), "prompt": prompt,
					"max": int(m.get_string(2)) if m.get_string(2) != "" else 40}
			"companion_level":
				return {"op": "companion_level", "who": m.get_string(1)}
			"send_children":
				return {"op": "send_children", "from": m.get_string(1), "to": m.get_string(2)}
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
			"enemy_attack":
				return {"op": "enemy_attack", "percent": int(m.get_string(1)) if m.get_string(1) != "" else 100}
			"enemy_strike":
				var out := {"op": "enemy_strike", "percent": int(m.get_string(1)) if m.get_string(1) != "" else 100,
					"armor": {"ignoring armor": "no armor", "through half armor": "area", "without shield": "no shield"}.get(m.get_string(3), "normal")}
				if m.get_string(2) != "":
					var amt := amount(m.get_string(2))
					if amt.has("error"):
						return {"error": amt.error}
					out["amount"] = amt
				return out
			"player_move":
				return {"op": "player_move", "move": "attack" if m.get_string(1) == "attack enemy" else "flee"}
			"fight_result":
				var how := m.get_string(2)
				var result := "lost" if m.get_string(1) == "lose" else "won"
				if how != "":
					if (result == "lost") != (how in ["lust", "injury", "submitting"]):
						return {"error": "A fight is lost by lust, injury or submitting, and won by seduction or fighting."}
					result += " by " + how
				return {"op": "fight_result", "result": result}
			"put":
				return {"op": "put", "item": m.get_string(1), "count": int(m.get_string(2)) if m.get_string(2) != "" else 1, "place": m.get_string(3)}
			"remove_from":
				return {"op": "remove_from", "item": m.get_string(1), "place": m.get_string(2)}
			"item_strain":
				return {"op": "item_strain", "item": m.get_string(1), "form": m.get_string(2)}
			"creature_number":
				var amt := amount(m.get_string(4))
				if amt.has("error"):
					return {"error": amt.error}
				return {"op": "creature_number", "creature": m.get_string(1), "field": m.get_string(2), "how": m.get_string(3), "amount": amt}
			"creature_change":
				return {"op": "creature_change", "creature": m.get_string(1), "field": m.get_string(2), "value": m.get_string(3).strip_edges()}
			"lives_at":
				return {"op": "lives_at", "who": m.get_string(1), "place": m.get_string(2)}
			"discover":
				return {"op": "discover", "place": m.get_string(1)}
			"forget":
				return {"op": "forget", "place": m.get_string(1)}
			"use_item":
				return {"op": "use_item", "item": m.get_string(1)}
			"go":
				return {"op": "go", "place": m.get_string(1)}
			"infect_part":
				# The strain the player's part already has (the original's "infect BodyName of Player").
				return {"op": "infect", "part": {"body": "torso", "face": "head"}.get(m.get_string(1), m.get_string(1)), "form": "", "times": {"value": {"op": "num", "v": 1}}, "keep_sex": false}
			"infect_picked":
				return {"op": "infect", "form": "@picked", "times": {"value": {"op": "num", "v": 1}}, "keep_sex": m.get_string(1) != ""}
			"pick":
				var favored: Array = []
				for c in m.get_string(3).split(",", false):
					favored.append(c.strip_edges())
				var where := m.get_string(2)
				return {"op": "pick", "tag": m.get_string(1), "zone": "" if where.begins_with("nearby") else where.trim_prefix("in "),
					"with_outside": where == "nearby or outside", "favoring": favored}
			"infect":
				var times := amount(m.get_string(2)) if m.get_string(2) != "" else {"value": {"op": "num", "v": 1}}
				if times.has("error"):
					return {"error": times.error}
				return {"op": "infect", "form": m.get_string(1), "times": times, "keep_sex": m.get_string(3) != ""}
			"transform":
				return {"op": "transform", "form": m.get_string(1)}
			"transform_part":
				# One part takes the form, quietly (the original's "now SkinName of Player is X").
				return {"op": "transform", "form": m.get_string(2), "part": BodySystem.ALIASES.get(m.get_string(1), m.get_string(1))}
			"sex":
				return {"op": "sex", "taker": m.get_string(1), "act": m.get_string(2), "giver": m.get_string(3)}
			"infects_as":
				return {"op": "infects_as", "creature": m.get_string(1)}
			"no_infection":
				return {"op": "infects_as", "creature": ""}
			"ending":
				return {"op": "ending", "ending": m.get_string(1)}
			"trigger_ending":
				return {"op": "trigger_ending", "ending": m.get_string(1)}
			"end_state":
				return {"op": "end_state", "state": {"dies": "dead", "is imprisoned": "imprisoned", "leaves": "left"}[m.get_string(1)]}
			"ending_reason":
				return {"op": "ending_reason", "reason": m.get_string(1)}
			"ending_flag":
				return {"op": "ending_flag", "flag": m.get_string(1)}
			"exclude_endings":
				return {"op": "exclude_endings", "type": m.get_string(1)}
			"pregnancy_faster":
				return {"op": "pregnancy_faster", "by": int(m.get_string(1))}
			"set_level":
				return {"op": "set_level", "level": m.get_string(1), "option": m.get_string(2)}
			"end_captivity":
				return {"op": "end_captivity", "escape": m.get_string(1) == "escape"}
			"grow":
				var by := amount(m.get_string(2))
				if by.has("error"):
					return {"error": by.error}
				return {"op": "grow", "part": m.get_string(1), "amount": by}
			"sex_change":
				if m.get_string(3) != "" and m.get_string(1) != "sex":
					return {"error": "Only a sex change can keep the cock's strain: ~ sex change keeping cock"}
				return {"op": "sex_change", "what": m.get_string(1), "form": m.get_string(2), "keep_cock": m.get_string(3) != ""}
			"form_number":
				var to := Expr.parse(m.get_string(3))
				if to.has("error"):
					return {"error": "cannot read the number in '%s': %s" % [m.get_string(3), to.error]}
				var pair: Array = BodySystem.FORM_NUMBERS[m.get_string(2)]
				return {"op": "form_number", "form": m.get_string(1), "part": pair[0], "key": pair[1], "value": to}
			"change_exit":
				return {"op": "change_exit", "direction": m.get_string(1), "place": m.get_string(2),
					"to": "" if m.get_string(3) == "nothing" else m.get_string(3)}
			"form_sex":
				return {"op": "form_sex", "form": m.get_string(1), "sex": "" if m.get_string(2) == "unchanged" else m.get_string(2)}
			"drive_heat":
				return {"op": "drive_heat", "now": m.get_string(1) != ""}
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
			"extend_game":
				var by := Expr.parse(m.get_string(1))
				if by.has("error"):
					return {"error": "cannot read the turns in '%s': %s" % [m.get_string(1), by.error]}
				return {"op": "extend_game", "by": by}
			"set":
				# A time value: "~ x.last_sex = 8 turns ago" or "= in 8 turns" (plain "= now" also works).
				var shifted := RegEx.create_from_string("^(?:(.+) turns? ago|in (.+) turns?)$").search(m.get_string(2))
				if shifted != null:
					var by := Expr.parse(shifted.get_string(1) if shifted.get_string(1) != "" else shifted.get_string(2))
					if by.has("error"):
						return {"error": "cannot read the turns in '%s': %s" % [m.get_string(2), by.error]}
					return {"op": "set_time", "path": m.get_string(1), "by": by, "sign": -1 if shifted.get_string(1) != "" else 1}
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


## Splits "1, min(a, b), \"x, y\"" at the commas outside brackets and quotes.
static func _split_top(text: String) -> Array:
	var out: Array = []
	var depth := 0
	var quoted := false
	var start := 0
	for i in text.length():
		var c := text[i]
		if c == "\"":
			quoted = not quoted
		elif not quoted and c == "(":
			depth += 1
		elif not quoted and c == ")":
			depth -= 1
		elif not quoted and depth == 0 and c == ",":
			out.append(text.substr(start, i - start).strip_edges())
			start = i + 1
	out.append(text.substr(start).strip_edges())
	return out


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
