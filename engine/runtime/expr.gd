class_name Expr
extends RefCounted
## Small value expressions used by conditions and effects.
##
## An operand is a number, a quoted text, yes/no, a value path such as
## `player.libido` or `adam.talk_progress`, or a bare word (a state name or an
## ID). Arithmetic with + - * / and parentheses is supported for amounts,
## for example `(player.thirst - 15) / 3`. Division is integer division, as
## in the original game.
##
## Compiled form (Dictionaries):
##   {"op": "num", "v": 3}            {"op": "text", "v": "Wyvern"}
##   {"op": "bool", "v": true}        {"op": "path", "v": "player.libido"}
##   {"op": "word", "v": "camp"}      {"op": "+", "a": ..., "b": ...}

static var _token_re := RegEx.create_from_string("\\s*(\"[^\"]*\"|-?\\d+(?:\\.\\d+)?|[A-Za-z_][A-Za-z0-9_.]*|[-+*/%()])")


static func tokenize(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var pos := 0
	while pos < text.length():
		var m := _token_re.search(text, pos)
		if m == null or m.get_start() != pos:
			if text.substr(pos).strip_edges().is_empty():
				break
			return PackedStringArray(["<error>", text.substr(pos).strip_edges()])
		out.append(m.get_string(1))
		pos = m.get_end()
	return out


## Parses an arithmetic expression. Returns {} and sets `error` on failure.
static func parse(text: String) -> Dictionary:
	var tokens := tokenize(text)
	if tokens.size() > 0 and tokens[0] == "<error>":
		return {"error": "cannot read '%s'" % tokens[1]}
	if tokens.is_empty():
		return {"error": "missing value"}
	var p := _P.new()
	p.t = tokens
	var node := p.sum()
	if p.err != "":
		return {"error": p.err}
	if p.i < tokens.size():
		return {"error": "unexpected '%s'" % tokens[p.i]}
	return node


static func is_simple(node: Dictionary) -> bool:
	return node.get("op", "") in ["num", "text", "bool", "path", "word"]


class _P:
	var t: PackedStringArray
	var i := 0
	var err := ""

	func sum() -> Dictionary:
		var a := product()
		while err == "" and i < t.size() and (t[i] == "+" or t[i] == "-"):
			var op := t[i]
			i += 1
			a = {"op": op, "a": a, "b": product()}
		return a

	func product() -> Dictionary:
		var a := atom()
		while err == "" and i < t.size() and (t[i] == "*" or t[i] == "/" or t[i] == "%"):
			var op := t[i]
			i += 1
			a = {"op": op, "a": a, "b": atom()}
		return a

	func atom() -> Dictionary:
		if i >= t.size():
			err = "missing value"
			return {}
		var tok := t[i]
		i += 1
		if tok == "(":
			var inner := sum()
			if i >= t.size() or t[i] != ")":
				err = "missing ')'"
				return {}
			i += 1
			return inner
		if tok == "random":
			# "random 1 to 20": a whole number rolled each time the expression is evaluated.
			var low := product()
			if i >= t.size() or t[i] != "to":
				err = "'random' needs 'to': random 1 to 20"
				return {}
			i += 1
			var high := product()
			return {"op": "random", "a": low, "b": high}
		if tok.begins_with("\""):
			return {"op": "text", "v": tok.substr(1, tok.length() - 2)}
		if tok.is_valid_int():
			return {"op": "num", "v": int(tok)}
		if tok.is_valid_float():
			return {"op": "num", "v": float(tok)}
		if tok == "yes" or tok == "true":
			return {"op": "bool", "v": true}
		if tok == "no" or tok == "false":
			return {"op": "bool", "v": false}
		if tok in ["+", "-", "*", "/", "%", ")"]:
			err = "unexpected '%s'" % tok
			return {}
		if "." in tok:
			return {"op": "path", "v": tok}
		return {"op": "word", "v": tok}


## Evaluates a compiled expression. `ctx` must provide value(path).
static func evaluate(node: Dictionary, ctx) -> Variant:
	match node.get("op", ""):
		"num", "text", "bool", "word":
			return node.v
		"path":
			return ctx.value(node.v)
		"+":
			return _num(evaluate(node.a, ctx)) + _num(evaluate(node.b, ctx))
		"-":
			return _num(evaluate(node.a, ctx)) - _num(evaluate(node.b, ctx))
		"*":
			return _num(evaluate(node.a, ctx)) * _num(evaluate(node.b, ctx))
		"/":
			var d := _num(evaluate(node.b, ctx))
			return 0 if d == 0 else _num(evaluate(node.a, ctx)) / d
		"random":
			var lo := _num(evaluate(node.a, ctx))
			var hi := _num(evaluate(node.b, ctx))
			return ctx.rng.range_int(mini(lo, hi), maxi(lo, hi))
		"%":
			# The original's "the remainder after dividing a by b".
			var m := _num(evaluate(node.b, ctx))
			return 0 if m == 0 else posmod(_num(evaluate(node.a, ctx)), m)
	return null


static func _num(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is bool:
		return 1 if v else 0
	return 0


## All value paths an expression refers to (for validation).
static func paths(node: Dictionary, out: Array = []) -> Array:
	match node.get("op", ""):
		"path":
			out.append(node.v)
		"+", "-", "*", "/", "%", "random":
			paths(node.a, out)
			paths(node.b, out)
	return out
