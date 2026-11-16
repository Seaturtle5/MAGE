class_name TextTemplate
extends RefCounted
## Compiles and renders text with markup.
##
## Markup:
##   [if cond]...[else if cond]...[else]...[end if]   conditional text
##   [one of]a[or]b[at random | cycling | stopping | sticky]   variation
##   [roll]...[/roll], [warning]...[/warning]         semantic styles
##   **bold**, *italic*
##   [anything else]   a descriptor, value or snippet, resolved by the game
##
## compile() returns {"parts": [...]} or {"error": message}. render() returns
## an Array of spans: {"text": String, "bold": bool, "italic": bool,
## "class": String}. Variation state (cycling, stopping, sticky) is kept by
## the game under a key made from `key` and the variation's position.

## Inform's orders: "at random" never repeats the previous choice, "purely at
## random" may; "in random order" goes through a shuffled list before
## repeating; "as decreasingly likely outcomes" favours earlier options.
const ORDERS := ["at random", "cycling", "stopping", "sticky", "sticky random", "purely at random",
	"in random order", "as decreasingly likely outcomes"]
const STYLES := ["roll", "warning"]

static var _cache: Dictionary = {}


static func compile(text: String, key: String = "") -> Dictionary:
	var cache_key := key + "\u0001" + text
	if _cache.has(cache_key):
		return _cache[cache_key]
	var tokens := _tokenize(text)
	var p := _P.new()
	p.t = tokens
	p.key = key
	var parts := p.sequence([])
	var result: Dictionary
	if p.err != "":
		result = {"error": p.err}
	elif p.i < tokens.size():
		result = {"error": "unexpected [%s]" % tokens[p.i].v}
	else:
		result = {"parts": parts}
	_cache[cache_key] = result
	return result


## Tokens: {"k": "lit"|"tag"|"em", "v": String}
static func _tokenize(text: String) -> Array:
	var out: Array = []
	var buf := ""
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == "[":
			var close := text.find("]", i)
			if close > i:
				if buf != "":
					out.append({"k": "lit", "v": buf})
					buf = ""
				out.append({"k": "tag", "v": text.substr(i + 1, close - i - 1).strip_edges()})
				i = close + 1
				continue
		if c == "*":
			if buf != "":
				out.append({"k": "lit", "v": buf})
				buf = ""
			if i + 1 < text.length() and text[i + 1] == "*":
				out.append({"k": "em", "v": "bold"})
				i += 2
			else:
				out.append({"k": "em", "v": "italic"})
				i += 1
			continue
		buf += c
		i += 1
	if buf != "":
		out.append({"k": "lit", "v": buf})
	return out


class _P:
	var t: Array
	var i := 0
	var err := ""
	var key := ""
	var variations := 0

	## Reads parts until one of the `stops` tags (not consumed).
	func sequence(stops: Array) -> Array:
		var parts: Array = []
		while i < t.size() and err == "":
			var tok: Dictionary = t[i]
			if tok.k == "lit":
				parts.append({"t": "lit", "v": tok.v})
				i += 1
			elif tok.k == "em":
				parts.append({"t": "em", "v": tok.v})
				i += 1
			else:
				var v: String = tok.v
				if _is_stop(v, stops):
					return parts
				if v.begins_with("if "):
					parts.append(conditional())
				elif v == "one of":
					parts.append(one_of())
				elif v in TextTemplate.STYLES:
					i += 1
					parts.append({"t": "style", "v": v, "on": true})
				elif v.begins_with("/") and v.substr(1) in TextTemplate.STYLES:
					i += 1
					parts.append({"t": "style", "v": v.substr(1), "on": false})
				elif v in ["else", "end if", "or"] or v.begins_with("else if ") or v in TextTemplate.ORDERS:
					err = "[%s] without a matching [if] or [one of]" % v
				else:
					i += 1
					parts.append({"t": "sub", "v": v})
		return parts

	func _is_stop(v: String, stops: Array) -> bool:
		for s in stops:
			if v == s or (s == "else if" and v.begins_with("else if ")):
				return true
		return false

	func conditional() -> Dictionary:
		var node := {"t": "if", "branches": [], "else": []}
		var cond_text: String = t[i].v.substr(3)
		i += 1
		while true:
			var c := Condition.compile(cond_text)
			if c.has("error"):
				err = "in [if %s]: %s" % [cond_text, c.error]
				return node
			node.branches.append({"cond": c, "parts": sequence(["else if", "else", "end if"])})
			if err != "" or i >= t.size():
				if err == "":
					err = "[if %s] has no [end if]" % cond_text
				return node
			var v: String = t[i].v
			i += 1
			if v.begins_with("else if "):
				cond_text = v.substr(8)
				continue
			if v == "else":
				node["else"] = sequence(["end if"])
				if i >= t.size():
					err = "[else] has no [end if]"
					return node
				i += 1
			return node
		return node

	func one_of() -> Dictionary:
		i += 1
		variations += 1
		var node := {"t": "one_of", "options": [], "order": "at random", "key": "%s#%d" % [key, variations]}
		while true:
			node.options.append(sequence(["or"] + TextTemplate.ORDERS))
			if err != "" or i >= t.size():
				if err == "":
					err = "[one of] has no ending such as [at random]"
				return node
			var v: String = t[i].v
			i += 1
			if v == "or":
				continue
			node.order = "sticky" if v == "sticky random" else v
			return node
		return node


## Renders compiled parts. `ctx` provides describe(name), condition checks
## through Condition.evaluate, rng and variation_state(key, count, order).
static func render(compiled: Dictionary, ctx) -> Array:
	var spans: Array = []
	var style := {"bold": false, "italic": false, "class": ""}
	_render_parts(compiled.get("parts", []), ctx, spans, style)
	return spans


static func _render_parts(parts: Array, ctx, spans: Array, style: Dictionary) -> void:
	for p in parts:
		match p.t:
			"lit":
				_emit(spans, p.v, style)
			"sub":
				_emit(spans, str(ctx.describe(p.v)), style)
			"em":
				style[p.v] = not style[p.v]
			"style":
				style["class"] = p.v if p.on else ""
			"if":
				var done := false
				for b in p.branches:
					if Condition.evaluate(b.cond, ctx):
						_render_parts(b.parts, ctx, spans, style)
						done = true
						break
				if not done:
					_render_parts(p["else"], ctx, spans, style)
			"one_of":
				var k: int = ctx.variation(p.key, p.options.size(), p.order)
				_render_parts(p.options[k], ctx, spans, style)


static func _emit(spans: Array, text: String, style: Dictionary) -> void:
	if text.is_empty():
		return
	if not spans.is_empty():
		var last: Dictionary = spans[-1]
		if last.bold == style.bold and last.italic == style.italic and last["class"] == style["class"]:
			last.text += text
			return
	spans.append({"text": text, "bold": style.bold, "italic": style.italic, "class": style["class"]})


## Plain text of rendered spans (for transcripts and tests).
## A prose line that starts with a punctuation mark (". Then she leaves.",
## ", he adds", ".'") goes on with the paragraph before it: the sentence was split
## by a condition. An ellipsis ("...") starts a paragraph of its own.
static func continues(spans: Array) -> bool:
	var s := plain(spans)
	return s != "" and ".,;:!?".contains(s[0]) and not s.begins_with("..")


static func plain(spans: Array) -> String:
	var s := ""
	for sp in spans:
		s += sp.text
	return s


## All substitution names used in compiled parts (for validation).
static func substitutions(parts: Array, out: Array = []) -> Array:
	for p in parts:
		match p.t:
			"sub":
				out.append(p.v)
			"if":
				for b in p.branches:
					substitutions(b.parts, out)
				substitutions(p["else"], out)
			"one_of":
				for o in p.options:
					substitutions(o, out)
	return out
