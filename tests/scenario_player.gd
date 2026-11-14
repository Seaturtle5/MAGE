class_name ScenarioPlayer
extends RefCounted
## Plays a scenario against the engine and returns a transcript.
##
## Used by the command-line driver (tests/play_scenario.gd) and by the
## scenario tests, which compare transcripts with recorded .expected.txt
## files. See play_scenario.gd for the step syntax.


## Plays `scenario` (the text of a scenario file). Returns the transcript.
static func play(scenario: String, seed_value: int = 42, start: String = "shelter", packs: Array = ["res://tests/packs"]) -> String:
	for line in scenario.split("\n"):
		if line.begins_with("# packs: "):
			packs = Array(line.substr(9).split(","))
		elif line.begins_with("# start: "):
			start = line.substr(9).strip_edges()
		elif line.begins_with("# seed: "):
			seed_value = int(line.substr(8))
	var out: PackedStringArray = []
	var db := ContentDB.new()
	db.load_folders(packs)
	for d in db.diagnostics:
		if d.severity == "error":
			out.append("[error] %s:%d %s" % [str(d.path).get_file(), d.line, d.message])
	if not db.errors().is_empty():
		out.append("Content has errors; not playing.")
		return "\n".join(out) + "\n"
	var game := Game.new(db, seed_value)
	out.append("# seed: %d, start: %s" % [seed_value, start])
	game.start(start)
	_print(game.take_output(), out)
	var steps := scenario.split("\n")
	for n in steps.size():
		var line := steps[n].strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		out.append(">>> " + line)
		if not _step(game, line):
			out.append("!!! step not possible here: %s (line %d, status %s)" % [line, n + 1, game.runner.status])
			_print(game.take_output(), out)
			break
		_print(game.take_output(), out)
	for w in game.warnings:
		out.append("[warning] " + w)
	game.dispose()
	return "\n".join(out) + "\n"


static func _step(game: Game, line: String) -> bool:
	var parts := line.split(" ", false, 1)
	var cmd := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	match cmd:
		"event":
			if game.runner.status != "idle" or not game.content.has(arg, "event"):
				return false
			game.runner.start_event(arg)
			return true
		"new":
			return game.start_scenario(arg)
		"filter":
			var f := arg.split(" ", false)
			return f.size() == 2 and game.set_filter(f[0], f[1])
		"level":
			var l := arg.split(" ", false)
			return l.size() == 2 and game.set_level(l[0], l[1])
		"combat":
			return game.runner.combat_action(arg)
		"choose":
			return game.runner.choose(int(arg) - 1)
		"continue":
			return game.runner.proceed()
		"go", "talk", "use", "take", "explore", "rest", "observe", "travel", "hunt", "wait", "scavenge", "shop", "actions", "sex", "smell", "look", "summon", "dismiss":
			return game.runner.act(cmd, arg)
		"save":
			var f := FileAccess.open(arg, FileAccess.WRITE)
			f.store_string(JSON.stringify(game.save_dict(), "  "))
			return true
		"load":
			var data = JSON.parse_string(FileAccess.get_file_as_string(arg))
			if not game.load_dict(data):
				return false
			game.runner.show_location()
			return true
	return false


static func _print(events: Array, out: PackedStringArray) -> void:
	for e in events:
		match e.type:
			"paragraph":
				out.append(TextTemplate.plain(e.spans))
			"title":
				out.append("[title] " + e.text)
			"notice":
				out.append("[notice] " + e.text)
			"roll":
				out.append("[roll] " + e.text)
			"combat":
				out.append("[combat] %s HP: %d/%d Libido: %d/100 Round: %d" % [e.name, e.hp, e.maxhp, e.lust, e.round])
			"image":
				out.append("[image %s]" % e.image)
			"page_break":
				out.append("{continue}")
			"choices":
				if e.get("title", "") != "":
					out.append(e.title)
				var k := 1
				for o in e.options:
					var text: String = o.text
					if o.description != "":
						text += " -- " + o.description
					out.append("  {%d:%s}%s" % [k, text, "" if o.enabled else " (unavailable)"])
					k += 1
			"location":
				out.append("[location] %s (%s)" % [e.name, e.region])
				for p in e.description:
					out.append(TextTemplate.plain(p))
				var people: Array = e.people.map(func(p): return p.name)
				var items: Array = e.items.map(func(it): return it.name)
				var exits: Array = e.exits.map(func(x): return "%s: %s" % [x.direction, x.name])
				var actions: Array = e.actions.map(func(a): return a.label)
				if people: out.append("  people: " + ", ".join(people))
				if items: out.append("  items: " + ", ".join(items))
				out.append("  exits: " + ", ".join(exits))
				if actions: out.append("  actions: " + ", ".join(actions))
			"scene_end":
				pass
			"ending":
				out.append("[ending] " + e.ending)
