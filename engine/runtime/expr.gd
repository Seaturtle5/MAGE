class_name Expr
extends RefCounted
## Small value expressions used by conditions and effects.
##
## An operand is a number, a quoted text, yes/no, a value path such as
## `player.libido` or `adam.talk_progress`, or a bare word (a state name or an
## ID). Arithmetic with + - * / and parentheses is supported for amounts,
## for example `(player.thirst - 15) / 3`. Division is integer division, as
## in the original game. `min(a, b)`, `max(a, b)` and `sqrt(a)` (whole number
## square root) help with capped formulas. Lists (a value declared `list`) are
## read with `entry 2 of x.list`, `count of x.list` and `random entry of x.list`.
##
## Compiled form (Dictionaries):
##   {"op": "num", "v": 3}            {"op": "text", "v": "Wyvern"}
##   {"op": "bool", "v": true}        {"op": "path", "v": "player.libido"}
##   {"op": "word", "v": "camp"}      {"op": "+", "a": ..., "b": ...}

static var _text_expr_re := RegEx.create_from_string("[-+*/%]|\\b(min|max|sqrt)\\s*\\(|^(entry|count of|random entry of) ")
static var _token_re := RegEx.create_from_string("\\s*(\"[^\"]*\"|-?\\d+(?:\\.\\d+)?|[A-Za-z_][A-Za-z0-9_.]*|[-+*/%(),])")


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

	## After "entry": an index, "of" and a value path follow ("entry 1 of x.list").
	func _list_follows() -> bool:
		var k := i
		if k < t.size() and t[k] == "(":
			var depth := 0
			while k < t.size():
				if t[k] == "(":
					depth += 1
				elif t[k] == ")":
					depth -= 1
					if depth == 0:
						break
				k += 1
		return k + 2 < t.size() and t[k + 1] == "of" and "." in t[k + 2]

	## The list a list reading names: a value path.
	func list_path() -> Dictionary:
		if i >= t.size() or not "." in t[i] or t[i].begins_with("\""):
			err = "a list is named by its value path, such as x.list"
			return {}
		i += 1
		return {"op": "path", "v": t[i - 1]}

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
		if tok == "entry" and _list_follows():
			# "entry 1 of x.list": the list's entry at that place (from 1).
			var index := atom()
			if err != "":
				return {}
			if i >= t.size() or t[i] != "of":
				err = "'entry' needs 'of': entry 1 of x.list"
				return {}
			i += 1
			return {"op": "entry", "a": index, "b": list_path()}
		if tok == "count" and i < t.size() and t[i] == "of":
			# "count of x.list": how many entries the list has.
			i += 1
			return {"op": "count", "a": list_path()}
		if tok == "random" and i + 1 < t.size() and t[i] == "entry" and t[i + 1] == "of":
			# "random entry of x.list": one of its entries, picked each time.
			i += 2
			return {"op": "random_entry", "a": list_path()}
		if tok == "random":
			# "random 1 to 20": a whole number rolled each time the expression is evaluated.
			var low := product()
			if i >= t.size() or t[i] != "to":
				err = "'random' needs 'to': random 1 to 20"
				return {}
			i += 1
			var high := product()
			return {"op": "random", "a": low, "b": high}
		if tok in ["min", "max", "sqrt"] and i < t.size() and t[i] == "(":
			# min(a, b), max(a, b), sqrt(a)
			i += 1
			var args: Array = [sum()]
			while err == "" and i < t.size() and t[i] == ",":
				i += 1
				args.append(sum())
			if err != "":
				return {}
			if i >= t.size() or t[i] != ")":
				err = "missing ')' after %s(" % tok
				return {}
			i += 1
			if args.size() != (1 if tok == "sqrt" else 2):
				err = "%s takes %s" % [tok, "one value" if tok == "sqrt" else "two values: %s(a, b)" % tok]
				return {}
			return {"op": tok, "a": args[0], "b": args[1] if args.size() > 1 else {"op": "num", "v": 0}}
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
		if tok in ["+", "-", "*", "/", "%", ")", ","]:
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
		"min":
			return mini(_num(evaluate(node.a, ctx)), _num(evaluate(node.b, ctx)))
		"max":
			return maxi(_num(evaluate(node.a, ctx)), _num(evaluate(node.b, ctx)))
		"sqrt":
			return int(sqrt(maxf(0.0, float(_num(evaluate(node.a, ctx))))))
		"entry":
			var list = ctx.value(node.b.v)
			var at := _num(evaluate(node.a, ctx))
			return list[at - 1] if list is Array and at >= 1 and at <= list.size() else null
		"count":
			var list = ctx.value(node.a.v)
			return list.size() if list is Array else 0
		"random_entry":
			var list = ctx.value(node.a.v)
			return list[ctx.rng.range_int(0, list.size() - 1)] if list is Array and not list.is_empty() else null
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


## Whether an expression uses a bare word (not a path, number or text).
static func has_words(node: Dictionary) -> bool:
	match node.get("op", ""):
		"word":
			return true
		"+", "-", "*", "/", "%", "random", "min", "max", "sqrt", "entry":
			return has_words(node.a) or (node.has("b") and has_words(node.b))
	return false


## A text substitution that is arithmetic ("[player.cunts * 2]", "[max(a.x, 3)]"):
## its compiled expression, or {} when the text is something else (a descriptor,
## a snippet, a plain path). All names in it must be value paths.
static func text_expression(text: String) -> Dictionary:
	if not _text_expr_re.search(text):
		return {}
	var e := parse(text)
	if e.has("error") or is_simple(e) or has_words(e):
		return {}
	return e


## All value paths an expression refers to (for validation).
static func paths(node: Dictionary, out: Array = []) -> Array:
	match node.get("op", ""):
		"path":
			out.append(node.v)
		"+", "-", "*", "/", "%", "random", "min", "max", "sqrt", "entry":
			paths(node.a, out)
			paths(node.b, out)
		"count", "random_entry":
			paths(node.a, out)
	return out


## The list paths an expression reads as lists (`entry 1 of x.list`), for validation.
static func list_paths(node: Dictionary, out: Array = []) -> Array:
	match node.get("op", ""):
		"entry":
			list_paths(node.a, out)
			out.append(node.b.v)
		"count", "random_entry":
			out.append(node.a.v)
		"+", "-", "*", "/", "%", "random", "min", "max", "sqrt":
			list_paths(node.a, out)
			list_paths(node.b, out)
	return out
