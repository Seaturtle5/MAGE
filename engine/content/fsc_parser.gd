class_name FscParser
extends RefCounted
## Parses content files (.fsc) into definitions.
##
## The parser is generic: it splits a file into definitions (`== type id`),
## reads fields (`key: value` with indented children) and parses scripts
## (prose, choices, conditions, effects ...) into a syntax tree of
## Dictionaries. Which fields hold scripts is decided later by the content
## loader, through `parse_script()` on a field's raw lines.
##
## Every node records its line, so errors point to the file and line.

const SCRIPT_TYPES := ["scene", "text"]
const SCENE_METADATA := ["source", "tags"]
const TAB_WIDTH := 4

static var _header_re := RegEx.create_from_string("^==\\s+(?:(extend|replace)\\s+)?(\\w+)\\s+([a-z0-9_.\\-]+)\\s*$")
static var _field_re := RegEx.create_from_string("^([A-Za-z][A-Za-z0-9 _]*?)\\s*:(?:\\s+(.*))?$")
static var _choice_suffix_re := RegEx.create_from_string("\\s*\\[(if [^\\[\\]]+|then leave|always shown|not yet implemented|number -?\\d+ to -?\\d+)\\]\\s*$")
## "fight wolf:", "fight goblin (female):", and fights in a row: "fight leopardman 2 times:",
## "fight pink_gel, blue_gel, purple_gel:" (until one is lost or fled); "fight wolf away from
## home:" meets the creature away from its usual place (`fight is away from home` in its texts).
static var _fight_re := RegEx.create_from_string("^fight\\s+([a-z0-9_.]+(?:\\s*,\\s*[a-z0-9_]+)*)(?:\\s*\\(([^)]*)\\))?(?:\\s+(\\S+)\\s+times)?(\\s+away from home)?\\s*:$")
static var _outcome_re := RegEx.create_from_string("^(won|lost|fled|won by seduction|lost by submitting|ended)\\s*:$")
## "fight random in zoo, campus:" (a random creature of one of those zones, or of the zone a
## text value holds), optionally "N times".
static var _fight_zone_re := RegEx.create_from_string("^fight random in ([a-z0-9_.]+(?:\\s*,\\s*[a-z0-9_.]+)*)(?:\\s+(\\S+)\\s+times)?\\s*:$")


## One physical line of a file.
class Line:
	var number: int
	var indent: int  ## -1 for blank lines
	var text: String

	func _init(n: int, i: int, t: String) -> void:
		number = n
		indent = i
		text = t

	func is_blank() -> bool:
		return indent < 0


## A field of a definition: `key: value` and its indented lines.
class Field:
	var name: String
	var value: String
	var line: int
	var children: Array[Line] = []

	func has_children() -> bool:
		for l in children:
			if not l.is_blank():
				return true
		return false


## A definition: `== type id` and its body.
class Definition:
	var type: String
	var id: String
	var mode := "define"  ## "define", "extend" or "replace"
	var path: String
	var line: int
	var fields: Dictionary = {}  ## name -> Field (first occurrence)
	var field_order: Array[String] = []
	var options: Array = []  ## `*` lines at field level (menus, observe ...)
	var nodes: Array = []  ## parsed script, for script types
	var body: Array[Line] = []
	## The exits its scripts make in play, found once by MapLayout; null until then.
	var changed_exits: Variant = null


## Result of parsing one file.
class Result:
	var path: String
	var definitions: Array[Definition] = []
	var diagnostics: Array[Dictionary] = []

	func error(line: int, message: String) -> void:
		diagnostics.append({"severity": "error", "path": path, "line": line, "message": message})

	func ok() -> bool:
		for d in diagnostics:
			if d.severity == "error":
				return false
		return true


static func parse(text: String, path: String = "") -> Result:
	var result := Result.new()
	result.path = path
	var lines := _split_lines(text, result)
	var current: Definition = null
	for l in lines:
		if not l.is_blank() and l.indent == 0 and l.text.begins_with("=="):
			var m := _header_re.search(l.text)
			if m == null:
				result.error(l.number, "A definition header must look like '== type id', '== extend type id' or '== replace type id' (id in lowercase letters, digits, '_', '.', '-').")
				current = null
				continue
			current = Definition.new()
			if not m.get_string(1).is_empty():
				current.mode = m.get_string(1)
			current.type = m.get_string(2)
			current.id = m.get_string(3)
			current.path = path
			current.line = l.number
			result.definitions.append(current)
		elif current != null:
			current.body.append(l)
		elif not l.is_blank():
			result.error(l.number, "Text outside a definition. Start a definition with '== type id'.")
	for d in result.definitions:
		_read_body(d, result)
	return result


static func _split_lines(text: String, result: Result) -> Array[Line]:
	var out: Array[Line] = []
	var raw := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	for i in raw.size():
		var s: String = raw[i]
		var stripped := s.strip_edges()
		if stripped.is_empty():
			out.append(Line.new(i + 1, -1, ""))
			continue
		if stripped.begins_with("//"):
			continue
		# Indentation: a space counts 1, a tab TAB_WIDTH.
		var rest := s.lstrip(" \t")
		var j := s.length() - rest.length()
		var indent := j + s.left(j).count("\t") * (TAB_WIDTH - 1)
		out.append(Line.new(i + 1, indent, rest.strip_edges(false, true)))
	return out


static func _read_body(d: Definition, result: Result) -> void:
	if d.type in SCRIPT_TYPES:
		var start := 0
		# Leading metadata lines (source:, tags:) before the first prose.
		while start < d.body.size():
			var l: Line = d.body[start]
			if l.is_blank():
				start += 1
				continue
			var m := _field_re.search(l.text)
			if l.indent == 0 and m != null and m.get_string(1) in SCENE_METADATA:
				var f := Field.new()
				f.name = m.get_string(1)
				f.value = m.get_string(2)
				f.line = l.number
				d.fields[f.name] = f
				d.field_order.append(f.name)
				start += 1
			else:
				break
		var rest: Array[Line] = []
		rest.assign(d.body.slice(start))
		d.nodes = parse_script(rest, result)
		return
	_read_fields(d, result)


static func _read_fields(d: Definition, result: Result) -> void:
	var i := 0
	var body := d.body
	var base := _min_indent(body)
	while i < body.size():
		var l: Line = body[i]
		if l.is_blank():
			i += 1
			continue
		if l.indent > base:
			result.error(l.number, "Unexpected indentation. Indented lines belong under a field ending in ':'.")
			i += 1
			continue
		if l.text.begins_with("*"):
			# An option list at field level (menus): collect the option and its block.
			var block: Array[Line] = [l]
			i += 1
			while i < body.size() and (body[i].is_blank() or body[i].indent > l.indent):
				block.append(body[i])
				i += 1
			for node in parse_script(block, result):
				if node.kind == "choices":
					d.options.append_array(node.options)
			continue
		var m := _field_re.search(l.text)
		if m == null:
			result.error(l.number, "Expected a field ('name: value') here, found: %s" % l.text.left(60))
			i += 1
			continue
		var f := Field.new()
		f.name = m.get_string(1).strip_edges()
		f.value = m.get_string(2).strip_edges()
		f.line = l.number
		i += 1
		while i < body.size() and (body[i].is_blank() or body[i].indent > l.indent):
			f.children.append(body[i])
			i += 1
		while not f.children.is_empty() and f.children[-1].is_blank():
			f.children.pop_back()
		if d.fields.has(f.name):
			result.error(f.line, "Field '%s' appears twice in %s %s (first on line %d)." % [f.name, d.type, d.id, d.fields[f.name].line])
		else:
			d.fields[f.name] = f
			d.field_order.append(f.name)


## Reads the indented children of a field as nested fields.
static func parse_fields(lines: Array[Line], result: Result) -> Dictionary:
	var tmp := Definition.new()
	tmp.body = lines
	_read_fields(tmp, result)
	return tmp.fields


static func _min_indent(lines: Array[Line]) -> int:
	var m := -1
	for l in lines:
		if not l.is_blank() and (m < 0 or l.indent < m):
			m = l.indent
	return max(m, 0)


## Parses script lines into a list of nodes (Dictionaries with "kind" and "line").
static func parse_script(lines: Array[Line], result: Result) -> Array:
	var p := _ScriptParser.new()
	p.lines = lines
	p.result = result
	return p.block(_min_indent(lines))


class _ScriptParser:
	var lines: Array[Line]
	var result: Result
	var pos := 0

	func peek() -> Line:
		while pos < lines.size() and lines[pos].is_blank():
			pos += 1
		return lines[pos] if pos < lines.size() else null

	## Parses lines at exactly `indent` into nodes, stopping at a dedent.
	func block(indent: int) -> Array:
		var nodes: Array = []
		var paragraph: PackedStringArray = []
		var para_line := 0
		while pos < lines.size():
			var l: Line = lines[pos]
			if l.is_blank():
				_flush(nodes, paragraph, para_line)
				paragraph = []
				pos += 1
				continue
			if l.indent < indent:
				break
			if l.indent > indent:
				result.error(l.number, "Unexpected indentation. Indent only under a choice, 'if ...:', 'else:', 'fight ...:' or a field.")
				pos += 1
				continue
			var t := l.text
			if _is_statement(t):
				_flush(nodes, paragraph, para_line)
				paragraph = []
				nodes.append(statement(l, indent))
			else:
				if paragraph.is_empty():
					para_line = l.number
				paragraph.append(t)
				pos += 1
		_flush(nodes, paragraph, para_line)
		return nodes

	func _flush(nodes: Array, paragraph: PackedStringArray, line: int) -> void:
		if not paragraph.is_empty():
			nodes.append({"kind": "text", "line": line, "text": " ".join(paragraph)})

	func _is_statement(t: String) -> bool:
		return t == "---" or t.begins_with("~") or t.begins_with("* ") or t == "*" \
			or t.begins_with("->") or t.begins_with("play ") or t.begins_with("show ") \
			or (t.begins_with("if ") and t.ends_with(":")) or (t.begins_with("else if ") and t.ends_with(":")) \
			or t == "else:" or (t.begins_with("fight ") and t.ends_with(":"))

	func children(parent: Line) -> Array:
		var next := peek()
		if next == null or next.indent <= parent.indent:
			return []
		return block(next.indent)

	func statement(l: Line, indent: int) -> Dictionary:
		var t := l.text
		pos += 1
		if t == "---":
			return {"kind": "page_break", "line": l.number}
		if t.begins_with("~"):
			return {"kind": "effect", "line": l.number, "text": t.substr(1).strip_edges()}
		if t.begins_with("->"):
			return {"kind": "goto", "line": l.number, "target": t.substr(2).strip_edges()}
		if t.begins_with("play "):
			return {"kind": "play", "line": l.number, "target": t.substr(5).strip_edges()}
		if t.begins_with("show "):
			var shown := t.substr(5).strip_edges()
			return {"kind": "show", "line": l.number, "image": "" if shown == "nothing" else shown}  # "show nothing" clears the picture
		if t.begins_with("fight "):
			return fight(l)
		if t.begins_with("if "):
			return conditional(l, indent)
		if t.begins_with("else"):
			result.error(l.number, "'%s' without a matching 'if' just above it." % t)
			children(l)
			return {"kind": "text", "line": l.number, "text": ""}
		pos -= 1
		return choices(indent)

	func conditional(first: Line, indent: int) -> Dictionary:
		var node := {"kind": "if", "line": first.number, "branches": [], "else": null}
		node.branches.append({"condition": first.text.substr(3, first.text.length() - 4).strip_edges(), "line": first.number, "body": children(first)})
		while true:
			var l := peek()
			if l == null or l.indent != indent:
				break
			if l.text.begins_with("else if ") and l.text.ends_with(":"):
				pos += 1
				node.branches.append({"condition": l.text.substr(8, l.text.length() - 9).strip_edges(), "line": l.number, "body": children(l)})
			elif l.text == "else:":
				pos += 1
				node["else"] = children(l)
				break
			else:
				break
		return node

	func fight(l: Line) -> Dictionary:
		var m := FscParser._fight_re.search(l.text)
		var zm := FscParser._fight_zone_re.search(l.text)
		if zm != null:
			# The zones of "fight random in zoo, campus:" (FightControlSystem.random_zone).
			m = FscParser._fight_re.search("fight random%s:" % ((" %s times" % zm.get_string(2)) if zm.get_string(2) != "" else ""))
		if m == null:
			result.error(l.number, "A fight must look like 'fight creature_id:' or 'fight creature_id (variant):'.")
			children(l)
			return {"kind": "text", "line": l.number, "text": ""}
		var creatures: Array = Array(m.get_string(1).split(",")).map(func(c): return c.strip_edges())
		var node := {"kind": "fight", "line": l.number, "creature": creatures[0], "variant": m.get_string(2), "outcomes": {}}
		if zm != null:
			node["zones"] = Array(zm.get_string(1).split(",")).map(func(z): return z.strip_edges())
		if creatures.size() > 1 and m.get_string(3) != "":
			result.error(l.number, "Fights in a row name one creature with 'N times' or several creatures, not both.")
		if creatures.size() > 1:
			node["creatures"] = creatures
		elif m.get_string(3) != "":
			node["times"] = m.get_string(3)
		if m.get_string(4) != "":
			node["away"] = true
		var next := peek()
		if next == null or next.indent <= l.indent:
			return node
		var inner := next.indent
		while true:
			var o := peek()
			if o == null or o.indent != inner:
				break
			if o.text.strip_edges() == "each:" and (node.has("creatures") or node.has("times")):
				# Before each fight of a row: its words (fights.number is the fight about to start).
				pos += 1
				node["each"] = children(o)
				continue
			var om := FscParser._outcome_re.search(o.text)
			if om == null:
				result.error(o.number, "Inside a fight, use 'won:', 'lost:', 'fled:' or 'ended:' blocks.")
				pos += 1
				continue
			pos += 1
			node.outcomes[om.get_string(1)] = children(o)
		return node

	func choices(indent: int) -> Dictionary:
		var node := {"kind": "choices", "line": peek().number, "options": []}
		while true:
			var l := peek()
			if l == null or l.indent != indent or not (l.text.begins_with("* ") or l.text == "*"):
				break
			pos += 1
			node.options.append(option(l))
		return node

	func option(l: Line) -> Dictionary:
		var label := l.text.substr(1).strip_edges()
		var opt := {"line": l.number, "label": "", "description": "", "condition": "", "then_leave": false, "always_shown": false, "not_implemented": false, "number": null}
		while true:
			var m := FscParser._choice_suffix_re.search(label)
			if m == null:
				break
			var tag := m.get_string(1)
			label = label.substr(0, m.get_start()).strip_edges()
			if tag.begins_with("if "):
				opt.condition = tag.substr(3).strip_edges()
			elif tag == "then leave":
				opt.then_leave = true
			elif tag == "always shown":
				opt.always_shown = true
			elif tag == "not yet implemented":
				opt.not_implemented = true
			else:
				var parts := tag.split(" ")
				opt.number = [int(parts[1]), int(parts[3])]
		var dash := label.find(" -- ")
		if dash >= 0:
			opt.description = label.substr(dash + 4).strip_edges()
			label = label.substr(0, dash).strip_edges()
		opt.label = label
		if label.is_empty():
			result.error(l.number, "A choice needs a label after '*'.")
		# An action's typed command words ("command: take slide, use slide", the original's
		# parser commands): kept with the option, never said as text.
		var first := peek()
		if first != null and first.indent > l.indent and first.text.begins_with("command:"):
			opt["commands"] = Array(first.text.substr(8).split(",", false)).map(func(w: String) -> String: return w.strip_edges())
			pos += 1
		opt["body"] = children(l)
		return opt
