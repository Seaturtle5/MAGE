class_name Program
extends RefCounted
## Compiles a script's syntax tree into a flat list of instructions.
##
## Flat instructions make the scene runner resumable: its position is just
## (program id, instruction index), which can be saved and restored. Each
## instruction is a Dictionary with "op" and "line":
##
##   text      {"text": compiled template}
##   page      {}
##   effect    {"effect": compiled effect}
##   show      {"image": id}
##   goto      {"target": id}            also "back" and "end"
##   play      {"target": id}
##   jump      {"to": index}
##   unless    {"cond": compiled, "to": index}   jump when the condition is false
##   choices   {"options": [{"label", "description", "cond", "then_leave",
##              "always_shown", "to": index}], "after": index}
##   fight     {"creature", "variant", "outcomes": {name: index}, "after": index}
##             fights in a row add "creatures" (a list) or "times" (an expression),
##             and "each": index of the block played before each fight (-1 for none)
##   return    {}                          end of the program
##
## Compile errors are collected in `errors` as {"line", "message"}.

var id: String
var path: String
var code: Array = []
var errors: Array = []


static func compile(program_id: String, nodes: Array, source_path: String = "") -> Program:
	var p := Program.new()
	p.id = program_id
	p.path = source_path
	p._block(nodes)
	p._emit({"op": "return", "line": 0})
	return p


func _emit(instr: Dictionary) -> int:
	code.append(instr)
	return code.size() - 1


func _error(line: int, message: String) -> void:
	errors.append({"line": line, "message": message})


func _block(nodes: Array) -> void:
	for n in nodes:
		match n.kind:
			"text":
				if n.text.is_empty():
					continue
				var t := TextTemplate.compile(n.text, "%s:%d" % [id, n.line])
				if t.has("error"):
					_error(n.line, t.error)
				_emit({"op": "text", "line": n.line, "text": t})
			"page_break":
				_emit({"op": "page", "line": n.line})
			"effect":
				var e := Effect.compile(n.text)
				if e.has("error"):
					_error(n.line, e.error)
				_emit({"op": "effect", "line": n.line, "effect": e})
			"show":
				_emit({"op": "show", "line": n.line, "image": n.image})
			"goto":
				_emit({"op": "goto", "line": n.line, "target": n.target})
			"play":
				var target: String = n.target
				var times := {}
				# "play rampage_round 3 to 10 times": the scene again and again, a set number of times.
				var tm := RegEx.create_from_string("^(\\S+(?: creature \\w+)?) (.+) times?$").search(target)
				if tm != null:
					target = tm.get_string(1)
					times = Effect.amount(tm.get_string(2))
					if times.has("error"):
						_error(n.line, times.error)
						times = {}
				var pm := RegEx.create_from_string("^picked creature (victory|defeated|encounter)$").search(target)
				if pm != null:
					target = "@picked#" + pm.get_string(1)
				var ins := {"op": "play", "line": n.line, "target": target}
				if not times.is_empty():
					ins["times"] = times
				_emit(ins)
			"if":
				_if(n)
			"choices":
				_choices(n)
			"fight":
				_fight(n)


func _cond(text: String, line: int) -> Dictionary:
	var c := Condition.compile(text)
	if c.has("error"):
		_error(line, c.error)
	return c


func _if(n: Dictionary) -> void:
	var exits: Array[int] = []
	for b in n.branches:
		var test := _emit({"op": "unless", "line": b.line, "cond": _cond(b.condition, b.line), "to": -1})
		_block(b.body)
		exits.append(_emit({"op": "jump", "line": b.line, "to": -1}))
		code[test].to = code.size()
	if n["else"] != null:
		_block(n["else"])
	for e in exits:
		code[e].to = code.size()


func _choices(n: Dictionary) -> void:
	var options: Array = []
	var instr := {"op": "choices", "line": n.line, "options": options, "after": -1}
	_emit(instr)
	var exits: Array[int] = []
	for o in n.options:
		var label := TextTemplate.compile(o.label, "%s:%d:label" % [id, o.line])
		if label.has("error"):
			_error(o.line, label.error)
		var opt := {"label": label, "description": o.description, "then_leave": o.then_leave,
			"always_shown": o.always_shown, "line": o.line, "cond": {}, "to": code.size()}
		if o.condition != "":
			opt.cond = _cond(o.condition, o.line)
		options.append(opt)
		_block(o.body)
		exits.append(_emit({"op": "jump", "line": o.line, "to": -1}))
	instr.after = code.size()
	for e in exits:
		code[e].to = code.size()


func _fight(n: Dictionary) -> void:
	var instr := {"op": "fight", "line": n.line, "creature": n.creature, "variant": n.variant, "outcomes": {}, "after": -1}
	var at := _emit(instr)
	if n.has("creatures"):
		instr["creatures"] = n.creatures
	if n.has("times"):
		var times := Expr.parse(n.times)
		if times.has("error"):
			errors.append({"line": n.line, "message": "cannot read how many fights '%s': %s" % [n.times, times.error]})
		instr["times"] = times
	if n.has("creatures") or n.has("times"):
		# The `each:` block runs before every fight of the row, then goes back to the fight.
		instr["each"] = -1
		var skip := _emit({"op": "jump", "line": n.line, "to": -1})
		if n.has("each"):
			instr["each"] = code.size()
			_block(n.each)
			_emit({"op": "jump", "line": n.line, "to": at})
		code[skip].to = code.size()
	var exits: Array[int] = []
	for outcome in n.outcomes:
		instr.outcomes[outcome] = code.size()
		_block(n.outcomes[outcome])
		exits.append(_emit({"op": "jump", "line": n.line, "to": -1}))
	instr.after = code.size()
	for e in exits:
		code[e].to = code.size()
