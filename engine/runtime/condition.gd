class_name Condition
extends RefCounted
## Compiles and evaluates conditions written in content.
##
## A condition is a short sentence such as `player is male and
## player.libido > 49` or `quest camp_bravo reached access`. It is compiled
## once into a tree of Dictionaries and evaluated against a context object
## (the running game), which answers questions such as value(path) or
## has_item(who, item, n). Unknown sentence forms are compile errors, so
## typos are reported when content loads instead of silently being false.

const PARTS := ["head", "torso", "back", "arms", "legs", "ass", "tail", "cock", "cunt", "skin", "body", "face", "balls", "breasts"]
const COMPARATORS := [">=", "<=", "!=", ">", "<", "="]

static var _cache: Dictionary = {}

# Sentence forms, tried in order. Each regex matches the whole predicate.
static var _rules: Array = [
	["chance", RegEx.create_from_string("^chance (\\d+) in (\\d+)$")],
	["percent", RegEx.create_from_string("^chance (\\d+)%$")],
	["chance_expr", RegEx.create_from_string("^chance (.+) in (.+)$")],
	["check", RegEx.create_from_string("^check (\\w+) vs (\\d+)$")],
	["check_expr", RegEx.create_from_string("^check (.+) vs (.+)$")],
	["quest", RegEx.create_from_string("^quest (\\w+) (is not|is|reached|has not reached|is before) (\\w+)$")],
	["outcome", RegEx.create_from_string("^(\\w+) outcome is (not )?(\\w+)$")],
	["time", RegEx.create_from_string("^time is (not )?(\\w+(?: \\w+)?)$")],
	["filter", RegEx.create_from_string("^filter (\\w+) is (not )?(allowed|banned|warded)$")],
	["level", RegEx.create_from_string("^level (\\w+) is (not |at least |at most )?(\\w+)$")],
	["mode", RegEx.create_from_string("^mode (\\w+)$")],
	["scenario", RegEx.create_from_string("^scenario is (not )?(\\w+)$")],
	["fight_result", RegEx.create_from_string("^(won by seduction|won by fighting|won by vore|won by unbirth|lost by submitting|lost by injury|lost by lust|won|lost|fled)$")],
	["can_vore", RegEx.create_from_string("^player (can|cannot) (vore|unbirth)$")],
	["enemy_tagged", RegEx.create_from_string("^(?:the )?enemy is (not )?tagged (\\w+)$")],
	# Lists: "3 is listed in x.list", "\"Bob\" is not listed in x.names", "x.list is empty".
	["listed", RegEx.create_from_string("^(.+?) is (not )?listed in ([a-z0-9_]+\\.[a-z0-9_.]+)$")],
	["empty", RegEx.create_from_string("^([a-z0-9_]+\\.[a-z0-9_.]+) is (not )?empty$")],
	# "gift.item is tagged milky": the item (or creature) a value holds carries the tag.
	["value_tagged", RegEx.create_from_string("^([a-z0-9_]+\\.[a-z0-9_.]+) is (not )?tagged (\\w+)$")],
	["since", RegEx.create_from_string("^since ([a-z0-9_.]+) (>=|<=|>|<|=) (\\d+) turns?$")],
	["has_condition", RegEx.create_from_string("^player (has|does not have) condition (\\w+)$")],
	["feat", RegEx.create_from_string("^(\\w+) (has|does not have) feat (\\w+)$")],
	["trait", RegEx.create_from_string("^(\\w+) (has|does not have) trait (\\w+)$")],
	["had_sex", RegEx.create_from_string("^(\\w+) (has had|has not had) sex$")],
	["picked", RegEx.create_from_string("^(a|no) creature is picked$")],
	# Endings (EndingSystem): marked endings, flags, excluded types and what ended the game.
	["ending_triggered", RegEx.create_from_string("^ending (\\w+) is (not )?triggered$")],
	["ending_flag", RegEx.create_from_string("^ending flag (\\w+) is (not )?set$")],
	["endings_excluded", RegEx.create_from_string("^(\\w+) endings are (not )?excluded$")],
	["ended_by", RegEx.create_from_string("^the game (ended|did not end) by (\\w+)$")],
	# The creature's to-hit roll in a fight, shown like other rolls ("enemy hits using intelligence").
	["enemy_hits", RegEx.create_from_string("^(?:the )?enemy (hits|misses)(?: using (strength|dexterity|stamina|perception|intelligence|charisma))?$")],
	["arrived", RegEx.create_from_string("^player (did not arrive|arrived) by (walking|travelling)$")],
	["has_part", RegEx.create_from_string("^(\\w+) (has|does not have) (head|torso|back|arms|legs|ass|tail|cock|cunt|balls|breasts)$")],
	["wears", RegEx.create_from_string("^(\\w+) (wears|does not wear|wields|does not wield) (\\w+)$")],
	# "player has an item tagged milky": any carried item with that tag.
	["has_tagged", RegEx.create_from_string("^player (has|does not have) (?:an? |any )item tagged (\\w+)$")],
	["has_item", RegEx.create_from_string("^(\\w+) (has|does not have) (\\w+)(?: (\\d+))?$")],
	["lives_at", RegEx.create_from_string("^(\\w+) (lives|does not live) at (\\w+)$")],
	["is_at", RegEx.create_from_string("^(\\w+) is (not )?at (\\w+)$")],
	["in_heat", RegEx.create_from_string("^(\\w+) is (not )?in heat$")],
	["in", RegEx.create_from_string("^player is (not )?in (\\w+)$")],
	["knows", RegEx.create_from_string("^player (knows|does not know) (\\w+)$")],
	["visited", RegEx.create_from_string("^player (has visited|has not visited) (\\w+)$")],
	# "fang is at a place flagged library": the character's place carries that flag.
	["at_flagged", RegEx.create_from_string("^(\\w+) is (not )?at a place flagged ([a-z][a-z ]*)$")],
	# "player parts are all human, herm_human": every body part has one of these forms.
	["parts_all", RegEx.create_from_string("^(\\w+) parts are (not )?all (\\w+(?:, ?\\w+)*)$")],
	# "player torso species is not player head species": two parts' strains have the same name.
	["species_same", RegEx.create_from_string("^(\\w+) (head|torso|back|arms|legs|ass|tail|cock|cunt|skin|body|face) species is (not )?(\\w+) (head|torso|back|arms|legs|ass|tail|cock|cunt|skin|body|face) species$")],
	# "player tail species contains wolf": the name of the part's strain contains the text.
	["species_contains", RegEx.create_from_string("^(\\w+) (head|torso|back|arms|legs|ass|tail|cock|cunt|skin|body|face) species (contains|does not contain) ([a-z][a-z ]*)$")],
	["part_tagged", RegEx.create_from_string("^(\\w+) (head|torso|back|arms|legs|ass|tail|cock|cunt|skin|body|face) is (not )?tagged (\\w+)$")],
	["part_is", RegEx.create_from_string("^(\\w+) (head|torso|back|arms|legs|ass|tail|cock|cunt|skin|body|face) is (not )?(\\w+)$")],
	["parity", RegEx.create_from_string("^([a-z0-9_.]+) is (not )?(odd|even)$")],
	["at_least", RegEx.create_from_string("^([a-z0-9_.]+) is (at least|at most) (\\w+)$")],
	# "wyvern name is known": the player knows a unique creature's own name (the original's enemy type 2).
	["name_known", RegEx.create_from_string("^(\\w+) name is (not )?known$")],
	["is", RegEx.create_from_string("^(\\w+) is (not )?([a-z][a-z0-9_ ]*)$")],
	["value_is", RegEx.create_from_string("^([a-z0-9_]+\\.[a-z0-9_.]+) is (not )?(.+)$")],
]


## Compiles a condition. Returns the tree, or {"error": message}.
static func compile(text: String) -> Dictionary:
	var key := text.strip_edges()
	if _cache.has(key):
		return _cache[key]
	var tokens := _words(key)
	var node: Dictionary
	if tokens.is_empty():
		node = {"error": "empty condition"}
	else:
		var p := _Parser.new()
		p.t = tokens
		node = p.or_expr()
		if p.err != "":
			node = {"error": p.err}
		elif p.i < tokens.size():
			node = {"error": "unexpected '%s'" % tokens[p.i]}
	_cache[key] = node
	return node


static func _words(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var re := RegEx.create_from_string("\"[^\"]*\"|>=|<=|!=|[()<>=!]|[^\\s()<>=!]+")
	for m in re.search_all(text):
		out.append(m.get_string())
	return out


class _Parser:
	var t: PackedStringArray
	var i := 0
	var err := ""

	func or_expr() -> Dictionary:
		var a := and_expr()
		while err == "" and i < t.size() and t[i] == "or":
			i += 1
			a = {"op": "or", "a": a, "b": and_expr()}
		return a

	func and_expr() -> Dictionary:
		var a := not_expr()
		while err == "" and i < t.size() and t[i] == "and":
			i += 1
			a = {"op": "and", "a": a, "b": not_expr()}
		return a

	func not_expr() -> Dictionary:
		if i < t.size() and t[i] == "not":
			i += 1
			return {"op": "not", "a": not_expr()}
		if i < t.size() and t[i] == "(":
			# A bracketed condition, unless it is the start of arithmetic.
			var close := _matching(i)
			if close > 0 and (close + 1 >= t.size() or t[close + 1] in ["and", "or", ")"]):
				i += 1
				var inner := or_expr()
				if i >= t.size() or t[i] != ")":
					err = "missing ')'"
					return {}
				i += 1
				return inner
		return predicate()

	func _matching(open: int) -> int:
		var depth := 0
		for k in range(open, t.size()):
			if t[k] == "(":
				depth += 1
			elif t[k] == ")":
				depth -= 1
				if depth == 0:
					return k
		return -1

	func predicate() -> Dictionary:
		var start := i
		var depth := 0
		while i < t.size():
			if t[i] == "(":
				depth += 1
			elif t[i] == ")":
				if depth == 0:
					break
				depth -= 1
			elif depth == 0 and (t[i] == "and" or t[i] == "or"):
				break
			i += 1
		if i == start:
			err = "missing condition"
			return {}
		var words := t.slice(start, i)
		var node := Condition._predicate(words)
		if node.has("error"):
			err = node.error
		return node


static func _predicate(words: PackedStringArray) -> Dictionary:
	# Comparisons with an operator: split at the operator ("since" has its own form).
	for k in (words.size() if words[0] != "since" else 0):
		if words[k] in COMPARATORS:
			var left := Expr.parse(" ".join(words.slice(0, k)))
			var right := Expr.parse(" ".join(words.slice(k + 1)))
			if left.has("error") or right.has("error"):
				return {"error": "cannot read comparison '%s': %s" % [" ".join(words), left.get("error", right.get("error", ""))]}
			return {"op": "cmp", "cmp": words[k], "left": left, "right": right}
	var s := " ".join(words)
	for rule in _rules:
		var m: RegExMatch = rule[1].search(s)
		if m == null:
			continue
		match rule[0]:
			"chance":
				return {"op": "chance", "n": int(m.get_string(1)), "d": int(m.get_string(2))}
			"percent":
				return {"op": "chance", "n": int(m.get_string(1)), "d": 100}
			"chance_expr":
				# "chance tt + 16 in player.humanity": computed odds.
				var n := Expr.parse(m.get_string(1))
				var d := Expr.parse(m.get_string(2))
				if n.has("error") or d.has("error"):
					return {"error": "cannot read chance '%s'" % s}
				return {"op": "chance_expr", "n": n, "d": d}
			"check":
				return {"op": "check", "stat": m.get_string(1), "target": int(m.get_string(2))}
			"enemy_hits":
				var node := {"op": "enemy_hits", "stat": m.get_string(2) if m.get_string(2) != "" else "dexterity"}
				return {"op": "not", "a": node} if m.get_string(1) == "misses" else node
			"check_expr":
				# "check <bonus> vs <target>": a d20 roll plus a computed bonus.
				var bonus := Expr.parse(m.get_string(1))
				var target := Expr.parse(m.get_string(2))
				if bonus.has("error") or target.has("error"):
					return {"error": "cannot read check '%s'" % s}
				return {"op": "check_expr", "bonus": bonus, "target": target}
			"quest":
				var rel := m.get_string(2)
				return {"op": "quest", "quest": m.get_string(1), "rel": rel.replace(" not", "").replace("has ", ""), "neg": "not" in rel, "stage": m.get_string(3)}
			"outcome":
				return {"op": "outcome", "event": m.get_string(1), "outcome": m.get_string(3), "neg": m.get_string(2) != ""}
			"time":
				return {"op": "time", "slot": m.get_string(2), "neg": m.get_string(1) != ""}
			"filter":
				return {"op": "filter", "filter": m.get_string(1), "state": m.get_string(3), "neg": m.get_string(2) != ""}
			"level":
				var rel := m.get_string(2).strip_edges()
				return {"op": "level", "category": m.get_string(1), "option": m.get_string(3), "neg": rel == "not",
					"rel": rel if rel in ["at least", "at most"] else "is"}
			"mode":
				return {"op": "mode", "mode": m.get_string(1)}
			"scenario":
				return {"op": "scenario", "scenario": m.get_string(2), "neg": m.get_string(1) != ""}
			"fight_result":
				return {"op": "fight_result", "result": m.get_string(1)}
			"can_vore":
				return {"op": "can_vore", "kind": m.get_string(2), "neg": m.get_string(1) == "cannot"}
			"enemy_tagged":
				return {"op": "enemy_tagged", "tag": m.get_string(2), "neg": m.get_string(1) != ""}
			"listed":
				var item := Expr.parse(m.get_string(1))
				if item.has("error"):
					return {"error": "cannot read '%s': %s" % [m.get_string(1), item.error]}
				return {"op": "listed", "item": item, "path": m.get_string(3), "neg": m.get_string(2) != ""}
			"empty":
				return {"op": "empty", "path": m.get_string(1), "neg": m.get_string(2) != ""}
			"value_tagged":
				return {"op": "value_tagged", "path": m.get_string(1), "tag": m.get_string(3), "neg": m.get_string(2) != ""}
			"since":
				return {"op": "since", "path": m.get_string(1), "cmp": m.get_string(2), "n": int(m.get_string(3))}
			"has_condition":
				return {"op": "has_condition", "id": m.get_string(2), "neg": m.get_string(1) != "has"}
			"feat", "trait":
				return {"op": rule[0], "who": m.get_string(1), "id": m.get_string(3), "neg": m.get_string(2) != "has"}
			"had_sex":
				return {"op": "had_sex", "who": m.get_string(1), "neg": m.get_string(2) != "has had"}
			"arrived":
				return {"op": "is", "who": "player", "adjective": "arrived by " + m.get_string(2), "neg": m.get_string(1) != "arrived"}
			"picked":
				return {"op": "is", "who": "player", "adjective": "creature picked", "neg": m.get_string(1) == "no"}
			"ending_triggered", "ending_flag", "endings_excluded":
				return {"op": "ending", "kind": rule[0], "id": m.get_string(1), "neg": m.get_string(2) != ""}
			"ended_by":
				return {"op": "ending", "kind": "ended_by", "id": m.get_string(2), "neg": m.get_string(1) != "ended"}
			"has_part":
				return {"op": "has_part", "who": m.get_string(1), "part": m.get_string(3), "neg": m.get_string(2) != "has"}
			"name_known":
				return {"op": "name_known", "creature": m.get_string(1), "neg": m.get_string(2) != ""}
			"has_tagged":
				return {"op": "has_tagged", "tag": m.get_string(2), "neg": m.get_string(1) != "has"}
			"has_item":
				return {"op": "has_item", "who": m.get_string(1), "item": m.get_string(3), "n": int(m.get_string(4)) if m.get_string(4) != "" else 1, "neg": m.get_string(2) != "has"}
			"wears":
				var verb := m.get_string(2)
				if m.get_string(1) != "player":
					return {"error": "only the player wears or wields items: '%s'" % s}
				return {"op": "wields" if "wield" in verb else "wears", "item": m.get_string(3), "neg": verb.begins_with("does not")}
			"lives_at":
				return {"op": "lives_at", "who": m.get_string(1), "place": m.get_string(3), "neg": m.get_string(2) != "lives"}
			"is_at":
				return {"op": "is_at", "who": m.get_string(1), "place": m.get_string(3), "neg": m.get_string(2) != ""}
			"in_heat":
				return {"op": "is", "who": m.get_string(1), "adjective": "in heat", "neg": m.get_string(2) != ""}
			"in":
				return {"op": "is_at", "who": "player", "place": m.get_string(2), "neg": m.get_string(1) != ""}
			"knows":
				return {"op": "knows", "place": m.get_string(2), "neg": m.get_string(1) != "knows"}
			"visited":
				return {"op": "visited", "place": m.get_string(2), "neg": m.get_string(1) != "has visited"}
			"at_flagged":
				return {"op": "at_flagged", "who": m.get_string(1), "flag": m.get_string(3).strip_edges(), "neg": m.get_string(2) != ""}
			"parts_all":
				return {"op": "parts_all", "who": m.get_string(1), "forms": Array(m.get_string(3).split(",")).map(func(x): return x.strip_edges()), "neg": m.get_string(2) != ""}
			"species_same":
				return {"op": "species_same", "who": m.get_string(1), "part": m.get_string(2), "neg": m.get_string(3) != "",
					"other": m.get_string(4), "other_part": m.get_string(5)}
			"species_contains":
				return {"op": "species_contains", "who": m.get_string(1), "part": m.get_string(2), "text": m.get_string(4).strip_edges(), "neg": m.get_string(3) != "contains"}
			"part_tagged":
				return {"op": "part_tagged", "who": m.get_string(1), "part": m.get_string(2), "tag": m.get_string(4), "neg": m.get_string(3) != ""}
			"part_is":
				return {"op": "part_is", "who": m.get_string(1), "part": m.get_string(2), "form": m.get_string(4), "neg": m.get_string(3) != ""}
			"parity":
				return {"op": "parity", "value": {"op": "path", "v": m.get_string(1)}, "even": m.get_string(3) == "even", "neg": m.get_string(2) != ""}
			"at_least":
				return {"op": "order", "path": m.get_string(1), "rel": m.get_string(2), "state": m.get_string(3)}
			"is":
				return {"op": "is", "who": m.get_string(1), "adjective": m.get_string(3).strip_edges(), "neg": m.get_string(2) != ""}
			"value_is":
				var right := Expr.parse(m.get_string(3))
				if right.has("error"):
					return {"error": "cannot read '%s'" % m.get_string(3)}
				return {"op": "cmp", "cmp": "!=" if m.get_string(2) != "" else "=", "left": {"op": "path", "v": m.get_string(1)}, "right": right}
	# A bare value path is true when the value is set (flags, yes/no values).
	if words.size() == 1 and "." in words[0]:
		return {"op": "truthy", "path": words[0]}
	return {"error": "unknown condition '%s'" % s}


## Evaluates a compiled condition against the running game.
static func evaluate(node: Dictionary, ctx) -> bool:
	match node.get("op", ""):
		"and":
			return evaluate(node.a, ctx) and evaluate(node.b, ctx)
		"or":
			return evaluate(node.a, ctx) or evaluate(node.b, ctx)
		"not":
			return not evaluate(node.a, ctx)
		"cmp":
			return compare(Expr.evaluate(node.left, ctx), node.cmp, Expr.evaluate(node.right, ctx), node.left, ctx)
		"ending":
			var yes := false
			match node.kind:
				"ending_triggered":
					yes = EndingSystem.triggered(ctx, node.id)
				"ending_flag":
					yes = EndingSystem.has_flag(ctx, node.id)
				"endings_excluded":
					yes = EndingSystem.excluded(ctx, node.id)
				"ended_by":
					yes = str(ctx.state.values.get("end.cause", "")) == node.id
			return yes != node.neg
		"truthy":
			return _truthy(ctx.value(node.path))
		"enemy_hits":
			return not ctx.state.combat.is_empty() and CombatSystem.hit_roll(ctx, node.stat)
		"order":
			var idx: int = ctx.state_index(node.path, ctx.value(node.path))
			var target: int = ctx.state_index(node.path, node.state)
			return idx >= target if node.rel == "at least" else idx <= target
		"since":
			return compare(ctx.turns_since(node.path), node.cmp, node.n, {}, ctx)
		"listed":
			var list = ctx.value(node.path)
			return (list is Array and list_has(list, Expr.evaluate(node.item, ctx))) != node.neg
		"value_tagged":
			var held := str(ctx.value(node.path)) if ctx.value(node.path) != null else ""
			var db: ContentDB = ctx.content
			var tags: Array = []
			if db.has(held, "item"):
				tags = db.list_field(held, "tags")
			elif db.has(held, "creature"):
				tags = VoreSystem.tags_of(ctx, held)
			return (node.tag in tags) != node.neg
		"empty":
			# A list with no entries, or a text with nothing in it (or a state named empty).
			var v = ctx.value(node.path)
			var empty: bool = v.is_empty() if v is Array else v == null or str(v) in ["", "empty"]
			return empty != node.neg
		"chance_expr":
			return ctx.ask({"op": "chance", "n": int(Expr._num(Expr.evaluate(node.n, ctx))), "d": int(Expr._num(Expr.evaluate(node.d, ctx)))})
		"parity":
			var even := posmod(int(Expr._num(Expr.evaluate(node.value, ctx))), 2) == 0
			return (even == node.even) != node.neg
		_:
			var result: bool = ctx.ask(node)
			return not result if node.get("neg", false) else result
	return false


static func compare(a: Variant, cmp: String, b: Variant, left: Dictionary, ctx) -> bool:
	# A word on the right side of a state value is a state name: compare by name.
	if cmp in ["=", "!="]:
		var equal: bool = str(a) == str(b) if (a is String or b is String) else a == b
		return equal if cmp == "=" else not equal
	var x := Expr._num(a)
	var y := Expr._num(b)
	match cmp:
		">":
			return x > y
		"<":
			return x < y
		">=":
			return x >= y
		"<=":
			return x <= y
	return false


## Whether a list holds a value (a number and its text count as the same).
static func list_has(list: Array, v: Variant) -> bool:
	return list.any(func(x): return compare(x, "=", v, {}, null))


static func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return str(v) != "" and str(v) != "none"
