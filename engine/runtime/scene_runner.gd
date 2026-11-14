class_name SceneRunner
extends RefCounted
## Plays scenes, menus and events, and offers actions when the player is idle.
##
## The runner's position is a stack of frames, each plain data:
##   {"kind": "script", "pid": program id, "pc": instruction index, ...}
##   {"kind": "menu", "id": menu id, "then_leave": bool}
## so it can stop at any input, be saved and continue later. It stops when
## it needs input: `status` is then "choice" (pick an option) or "continue"
## (a page break). With no frames left it is "idle" at a location.

var game  # Game (untyped to avoid a cyclic class reference)
var frames: Array = []
var status := "idle"
var pending: Array = []  ## for "choice": [{"to": pc} or {"menu": index} or {"leave": true}]
var _dispatching_action := false


func _init(g) -> void:
	game = g


# --- Starting things --------------------------------------------------------

## Starts a scene, a script field ("id#field") or a menu.
func start(target: String, extra: Dictionary = {}) -> void:
	_push(target, extra)
	run()


## Runs a program right away (for effects that trigger scenes during a turn).
func play_now(pid: String) -> void:
	_push(pid, {})
	if status == "idle":
		# Content run between actions (hooks, meters): if it says nothing, the player's
		# view stays as it was instead of the location being shown again.
		var before: int = game.output.size()
		run()
		if status == "idle" and game.output.slice(before).all(func(e): return e.type in ["scene_end", "location"]):
			game.output.resize(before)


## Starts an event. `preface` holds output events (text, rolls) that led to
## it; they are shown under the event's title instead of on a page before it.
func start_event(event_id: String, preface: Array = []) -> void:
	game._event(event_id).last_turn = game.state.turn
	var repeat: String = game.content.field_value(event_id, "repeat", "once")
	if repeat == "once":
		game._event(event_id).resolved = true
	emit_title(game.content.field_value(event_id, "name", event_id))
	for e in preface:
		game.emit(e)
	start("%s#play" % event_id, {"event": event_id})


func emit_title(text: String, character: String = "", image: String = "") -> void:
	game.emit({"type": "title", "text": text, "character": character,
		"image": image if image != "" else game.content.typed_value("character", character, "image")})


func _push(target: String, extra: Dictionary) -> void:
	if game.content.menus.has(target):
		frames.append({"kind": "menu", "id": target, "then_leave": false, "fresh": true})
		return
	var prog: Program = game.content.program(target)
	if prog == null:
		game.warn("Nothing to play: '%s'" % target)
		game.emit({"type": "notice", "text": "[missing scene '%s']" % target})
		return
	var f := {"kind": "script", "pid": target, "pc": 0}
	f.merge(extra)
	frames.append(f)


## Plays a creature's encounter field as a scene, if it has one.
func _push_encounter(creature: String) -> void:
	game.fight_cancelled = false  # only the encounter that is about to play can call off its fight
	if game.content.program(creature + "#encounter") != null:
		frames.append({"kind": "script", "pid": creature + "#encounter", "pc": 0})


func current_event() -> String:
	for i in range(frames.size() - 1, -1, -1):
		if frames[i].has("event"):
			return frames[i].event
	return ""


# --- Running ----------------------------------------------------------------

func run() -> void:
	status = "running"
	var guard := 0
	while not frames.is_empty():
		guard += 1
		if guard > 100000:
			game.warn("Scene runner stopped: too many steps (a loop in content?)")
			break
		var f: Dictionary = frames[-1]
		if f.kind in ["travel", "discover"]:
			frames.pop_back()
			if f.kind == "discover":
				game.notice("Following movement, you end up at %s." % game.content.typed_value("location", f.place, "name", f.place), false)
			game.go_to(f.place)
			continue
		if f.kind == "turn":
			frames.pop_back()
			for _i in int(f.turns):
				game.pass_turn()
			continue
		if f.kind == "fight_chance":
			frames.pop_back()
			_fight_chance(f)
			continue
		if f.kind == "pause":
			# Let the player read what happened before the next page replaces it.
			frames.pop_back()
			game.emit({"type": "page_break"})
			status = "continue"
			return
		if f.kind == "encounter":
			# Steps: 0 shows the title and plays the creature's encounter as a scene
			# (it may set values and flags, show pictures and break pages); 2 starts
			# the fight; 1 is after the fight.
			if f.pc == 0:
				f.pc = 2
				if f.get("title", false):
					emit_title("Encounter: " + game.content.typed_value("creature", f.creature, "name", f.creature), "",
						game.content.typed_value("creature", f.creature, "image"))
				_push_encounter(f.creature)
				continue
			if f.pc == 2:
				f.pc = 1
				if game.fight_cancelled:
					game.fight_cancelled = false
					_pop()
					continue
				f["fight"] = {"creature": f.creature, "outcomes": {}, "after": 1}
				CombatSystem.begin(game, f.creature)
				if game.state.combat.result != "":
					_finish_fight()
					continue
				status = "combat"
				return
			_pop()
			continue
		if f.kind == "item_infect":
			frames.pop_back()
			# Iron Stomach protects against infected food and drink.
			if not f.get("skip", false) and "iron_stomach" not in game.state.feats:
				BodySystem.infect(game, f.form)
			continue
		if f.kind == "combat_item_end":
			frames.pop_back()
			CombatSystem.after_item(game)
			if game.state.combat.result != "":
				_finish_fight()
				continue
			CombatSystem.show(game)
			status = "combat"
			return
		if f.kind == "combat_end":
			CombatSystem.aftermath(game, f.creature, f.result)
			game.state.combat = {}
			frames.pop_back()
			continue
		if f.kind == "menu":
			if _menu_step(f):
				return
			continue
		var prog: Program = game.content.program(f.pid)
		if prog == null or f.pc >= prog.code.size():
			_pop()
			continue
		var ins: Dictionary = prog.code[f.pc]
		f.pc += 1
		match ins.op:
			"text":
				if not ins.text.has("error"):
					game.emit({"type": "paragraph", "spans": game.render(ins.text)})
			"page":
				game.emit({"type": "page_break"})
				status = "continue"
				return
			"effect":
				if not ins.effect.has("error"):
					game.apply(ins.effect)
			"show":
				game.emit({"type": "image", "image": ins.image})
			"jump":
				f.pc = ins.to
			"unless":
				if ins.cond.has("error") or not Condition.evaluate(ins.cond, game):
					f.pc = ins.to
			"choices":
				if _offer_choices(f, ins):
					return
			"goto":
				_goto(ins.target)
			"play":
				_push(ins.target, {})
			"fight":
				if f.has("encountering"):
					# Second pass, after the creature's encounter scene: start the fight.
					ins = f.encountering
					f.erase("encountering")
					if game.fight_cancelled:
						game.fight_cancelled = false
						f.pc = ins.after
						continue
					f["fight"] = ins
					CombatSystem.begin(game, ins.creature)
					if game.state.combat.result != "":
						_finish_fight()
						continue
					status = "combat"
					return
				if ins.creature == "random":
					# The original's plain Fight: a random creature of this zone.
					var zone: String = game.content.typed_value("location", game.state.location, "zone")
					var pool := encounter_pool("outside" if zone in ["", "none"] else zone)
					if pool.is_empty():
						f.pc = ins.after
						continue
					ins = ins.duplicate()
					ins.creature = pool[game.rng.range_int(0, pool.size() - 1)]
					emit_title("Encounter: " + game.content.typed_value("creature", ins.creature, "name", ins.creature), "",
						game.content.typed_value("creature", ins.creature, "image"))
				# The creature's encounter plays first, then this instruction runs again.
				f["encountering"] = ins
				f.pc -= 1
				_push_encounter(ins.creature)
				continue
			"return":
				_pop()
	if _queue_scheduled_scenes():
		run()
		return
	status = "idle"
	game.emit({"type": "scene_end"})
	show_location()


func _pop() -> void:
	var f: Dictionary = frames.pop_back()
	if f.has("refund") and game.use_cancelled:
		game.state.inventory[f.refund] = int(game.state.inventory.get(f.refund, 0)) + 1
		game.use_cancelled = false
		if not frames.is_empty() and frames[-1].kind == "item_infect":
			frames[-1]["skip"] = true
	if not frames.is_empty() and frames[-1].kind == "menu":
		var m: Dictionary = frames[-1]
		var settings: Dictionary = game.content.menus[m.id].settings
		if m.then_leave:
			frames.pop_back()
		elif settings.get("pause after each", "no") == "yes":
			m["pause"] = true


func _goto(target: String) -> void:
	match target:
		"end":
			frames.clear()
		"back":
			while not frames.is_empty() and frames[-1].kind != "menu":
				frames.pop_back()
		_:
			var extra := {}
			if not frames.is_empty() and frames[-1].kind == "script":
				var f: Dictionary = frames.pop_back()
				for k in ["event", "refund"]:
					if f.has(k):
						extra[k] = f[k]
			_push(target, extra)


func _offer_choices(f: Dictionary, ins: Dictionary) -> bool:
	var shown: Array = []
	pending = []
	for o in ins.options:
		var ok: bool = o.cond.is_empty() or (not o.cond.has("error") and Condition.evaluate(o.cond, game))
		if ok or o.always_shown:
			shown.append({"text": TextTemplate.plain(game.render(o.label)), "description": o.description, "enabled": ok})
			pending.append({"to": o.to, "enabled": ok})
	if shown.is_empty():
		f.pc = ins.after
		return false
	game.emit({"type": "choices", "options": shown})
	status = "choice"
	return true


func _menu_step(m: Dictionary) -> bool:
	var menu: Dictionary = game.content.menus[m.id]
	if m.get("pause", false):
		m.erase("pause")
		game.emit({"type": "page_break"})
		status = "continue"
		return true
	var shown: Array = []
	pending = []
	for i in menu.options.size():
		var o: Dictionary = menu.options[i]
		var ok := true
		if o.condition != "":
			var c := Condition.compile(o.condition)
			ok = not c.has("error") and Condition.evaluate(c, game)
		if ok or o.always_shown:
			shown.append({"text": o.label, "description": o.description, "enabled": ok})
			pending.append({"menu": i, "enabled": ok})
	shown.append({"text": menu.settings.get("leave", "Leave"), "description": "", "enabled": true, "leave": true})
	pending.append({"leave": true, "enabled": true})
	if m.get("fresh", false):
		m.erase("fresh")
		var intro: Program = game.content.program("%s#intro" % m.id)
		if intro != null:
			frames.append({"kind": "script", "pid": intro.id, "pc": 0})
			return false
	game.emit({"type": "choices", "title": menu.settings.get("title", ""), "options": shown, "menu": m.id})
	status = "choice"
	return true


# --- Input ------------------------------------------------------------------

## Picks option `index` (0-based) of the current choice list.
func choose(index: int) -> bool:
	if status != "choice" or index < 0 or index >= pending.size() or not pending[index].enabled:
		return false
	var p: Dictionary = pending[index]
	pending = []
	var f: Dictionary = frames[-1]
	if p.has("to"):
		f.pc = p.to
	elif p.has("leave"):
		frames.pop_back()
		var leave: Program = game.content.program("%s#leave text" % f.id)
		if leave != null:
			frames.append({"kind": "script", "pid": leave.id, "pc": 0})
	else:
		var o: Dictionary = game.content.menus[f.id].options[p.menu]
		f.then_leave = o.then_leave
		frames.append({"kind": "script", "pid": "%s@%d" % [f.id, p.menu], "pc": 0})
	run()
	return true


func proceed() -> bool:
	if status != "continue":
		return false
	run()
	return true


func combat_action(action: String) -> bool:
	if status == "combat" and action.begins_with("use "):
		return _combat_item(action.substr(4))
	if status != "combat" or not CombatSystem.act(game, action):
		return false
	var result: String = game.state.combat.result
	if result == "":
		return true
	_finish_fight()
	run()
	return true


func _finish_fight() -> void:
	var result: String = game.state.combat.result
	var f: Dictionary = frames[-1]
	var ins: Dictionary = f.fight
	game.last_fight = result
	var fallback := "won" if result.begins_with("won") else "lost" if result.begins_with("lost") else "fled"
	f.pc = ins.outcomes.get(result, ins.outcomes.get(fallback, ins.after))
	f.erase("fight")
	frames.append({"kind": "combat_end", "creature": ins.creature, "result": result})
	var field := "defeated" if fallback == "won" else "victory" if fallback == "lost" else ""
	if field != "" and game.content.program(ins.creature + "#" + field) != null:
		_push(ins.creature + "#" + field, {})


# --- Idle actions -----------------------------------------------------------

## Uses an item marked `in combat: yes` during a fight. Its use scene runs
## (it can check `player is fighting`), then the enemy takes its turn.
func _combat_item(id: String) -> bool:
	var db: ContentDB = game.content
	if int(game.state.inventory.get(id, 0)) <= 0 or db.typed_value("item", id, "in combat", "no") != "yes" \
			or db.program(id + "#use", "item") == null:
		return false
	game.use_cancelled = false
	frames.append({"kind": "combat_item_end"})
	var extra := {}
	if db.typed_value("item", id, "consumed", "yes") != "no":
		game.apply({"op": "take", "item": id, "amount": {"value": {"op": "num", "v": 1}}, "quiet": true})
		extra["refund"] = id
	_push("item:%s#use" % id, extra)
	run()
	return true


## Builds the location view: what the player sees and can do.
func show_location() -> void:
	var loc: String = game.state.location
	if loc == "" or not frames.is_empty():
		return
	var db: ContentDB = game.content
	var view := {"type": "location", "id": loc, "name": db.field_value(loc, "name", loc),
		"region": db.field_value(loc, "region"), "image": db.field_value(loc, "image"), "description": [], "exits": [],
		"people": [], "items": [], "actions": []}
	for key in ["description", "presence"]:
		var prog: Program = db.program("%s#%s" % [loc, key])
		if prog != null:
			view.description.append_array(render_paragraphs(prog))
	var exits: FscParser.Field = db.get_def("location", loc).fields.get("exits", null)
	var shown_doors: Array = []
	if exits != null:
		for l in exits.children:
			if l.is_blank():
				continue
			var parts := l.text.split(":", true, 1)
			var target := parts[1].split(",")[0].strip_edges() if parts.size() > 1 else ""
			var door := _exit_door(parts[1]) if parts.size() > 1 else ""
			view.exits.append({"direction": parts[0].strip_edges(), "to": target, "name": db.field_value(target, "name", target),
				"enabled": not _door_locked(door)})
			if door != "" and door not in shown_doors:
				view.description.append_array(render_paragraphs(db.program(door + "#shown in room")))
				shown_doors.append(door)
	for c in db.all_of("character"):
		if game.where(c) == loc:
			view.people.append({"id": c, "name": db.typed_value("character", c, "name", c),
				"image": db.typed_value("character", c, "image"), "talk": db.get_def("character", c).fields.has("talk")})
	var here := ItemSystem.ground(game, loc)
	for it in ItemSystem.ground_ids(game, loc):
		view.items.append({"id": it, "name": db.typed_value("item", it, "name", it), "count": int(here[it])})
	if db.field_value(loc, "zone") not in ["", "none"]:
		view.actions.append({"id": "explore", "label": "Explore"})
		if not encounter_pool(db.field_value(loc, "zone"), true).is_empty():
			view.actions.append({"id": "hunt", "label": "Hunt"})
	if "fast travel" in db.list_field(loc, "flags") and not db.all_of("scavenge_rules").is_empty():
		view.actions.append({"id": "scavenge", "label": "Scavenge"})
	if can_rest():
		view.actions.append({"id": "rest", "label": "Rest"})
	view.actions.append({"id": "wait", "label": "Wait"})
	if db.menus.has("%s.observe" % loc):
		view.actions.append({"id": "observe", "label": "Observe"})
	game.emit(view)


## Renders a text-only program into paragraphs of spans (descriptions).
## The text of a text field (and the scenes it hands over to). With `run_effects`
## its effects run as it is shown (a creature's attack landing).
func render_paragraphs(prog: Program, depth: int = 0, run_effects: bool = false) -> Array:
	var paras: Array = []
	if prog == null or depth > 8:
		return paras
	var pc := 0
	var steps := 0
	while pc < prog.code.size() and steps < 10000:
		steps += 1
		var ins: Dictionary = prog.code[pc]
		pc += 1
		match ins.op:
			"text":
				if not ins.text.has("error"):
					paras.append(game.render(ins.text))
			"jump":
				pc = ins.to
			"unless":
				if ins.cond.has("error") or not Condition.evaluate(ins.cond, game):
					pc = ins.to
			"effect":
				if run_effects and not ins.effect.has("error"):
					game.apply(ins.effect)
			"goto":
				# A text field may hand over to a scene of text and conditions ("attack: -> wolf_attacks").
				paras += render_paragraphs(game.content.program(ins.target), depth + 1, run_effects)
				break
			"return":
				break
	return paras


func render_inline(prog: Program) -> String:
	var out: PackedStringArray = []
	for p in render_paragraphs(prog):
		out.append(TextTemplate.plain(p))
	return " ".join(out)


## Performs an idle action. Returns false if it is not available.
func act(action: String, arg: String = "") -> bool:
	if status != "idle" or game.state.ending != "":
		return false
	if action not in ["go", "talk", "use", "take", "take_all", "observe", "explore", "hunt", "travel", "rest", "wait",
			"scavenge", "wear", "remove", "wield", "unwield", "drop", "drop_all", "drop_everything", "junk", "junk_all", "purify"]:
		return false
	game.state.action_pending = true
	_dispatching_action = true
	var accepted := _act(action, arg)
	_dispatching_action = false
	# A failed in-world attempt also advances Inform's command-turn timers.
	# Simple actions don't enter run(); scene actions finish there instead.
	if game.state.action_pending and status == "idle" and _queue_scheduled_scenes():
		run()
	return accepted


func _queue_scheduled_scenes() -> bool:
	# Turn hooks can run scenes while rest/travel is still applying its effects.
	if _dispatching_action:
		return false
	var ready := ActionScheduler.complete(game)
	ready.reverse()
	for scene in ready:
		_push(scene, {})
	return not ready.is_empty()


func _act(action: String, arg: String) -> bool:
	var db: ContentDB = game.content
	var loc: String = game.state.location
	match action:
		"wait":
			frames.append({"kind": "turn", "turns": 1})
			run()
			return true
		"go":
			var exits: FscParser.Field = db.get_def("location", loc).fields.get("exits", null)
			if exits == null:
				return false
			if ItemSystem.overburdened(game):
				# Inventory.i7x:308-309; fast travel is not blocked.
				game.notice("You are too overburdened to move. Drop some of that junk!", false)
				return false
			for l in exits.children:
				if l.is_blank():
					continue
				var parts := l.text.split(":", true, 1)
				if parts[0].strip_edges() == arg and parts.size() > 1:
					var door := _exit_door(parts[1])
					if _door_locked(door):
						var text: String = render_inline(db.program(door + "#locked text")) if db.program(door + "#locked text") != null else "The door is locked."
						game.notice(text, false)
						return false
					if door != "":
						var key := "door_state.%s.open" % door
						if not game.state.values.get(key, false):
							game.state.values[key] = true
							game.notice("(first opening the %s)" % db.typed_value("door", door, "name", door).to_lower(), false)
					game.go_to(parts[1].split(",")[0].strip_edges())
					return true
			return false
		"talk":
			if game.where(arg) != loc or not db.get_def("character", arg).fields.has("talk"):
				return false
			game.set_value("%s.met" % arg, true)
			emit_title("Talking with %s" % db.typed_value("character", arg, "name", arg), arg)
			start("%s#talk" % arg)
			return true
		"use":
			if int(game.state.inventory.get(arg, 0)) <= 0:
				return false
			# Bedding and similar items run an action, such as resting, when used.
			var use_action := db.typed_value("item", arg, "use action")
			if use_action != "":
				return _act(use_action, "")
			if db.program(arg + "#use") == null:
				return false
			game.use_cancelled = false
			var extra := {}
			if db.typed_value("item", arg, "consumed", "yes") != "no":
				game.apply({"op": "take", "item": arg, "amount": {"value": {"op": "num", "v": 1}}, "quiet": true})
				extra["refund"] = arg
			# Infectious items infect after their use text (Game Objects.i7x:165-172).
			var strain := db.typed_value("item", arg, "infectious")
			if strain != "":
				frames.append({"kind": "item_infect", "form": strain})
			start("%s#use" % arg, extra)
			return true
		"take", "take_all":
			var ok := ItemSystem.pick_up(game, arg) if action == "take" else ItemSystem.pick_up_all(game)
			if ok:
				show_location()
			return ok
		"wear", "remove", "wield", "unwield", "drop", "drop_all", "drop_everything", "junk", "junk_all", "purify":
			var ok := false
			match action:
				"purify":
					ok = ItemSystem.purify(game, arg)
				"wear":
					ok = ItemSystem.wear(game, arg)
				"remove":
					ok = ItemSystem.remove(game, arg)
				"wield":
					ok = ItemSystem.wield(game, arg)
				"unwield":
					ok = ItemSystem.unwield(game)
				"drop", "drop_all":
					ok = ItemSystem.drop(game, arg, action == "drop_all")
				"drop_everything":
					ok = ItemSystem.drop_everything(game)
				"junk", "junk_all":
					ok = ItemSystem.junk(game, arg, action == "junk_all")
			if ok and status == "idle" and frames.is_empty():
				show_location()
			return ok
		"observe":
			if not db.menus.has("%s.observe" % loc):
				return false
			start("%s.observe" % loc)
			return true
		"explore":
			return _explore(loc)
		"scavenge":
			return _scavenge(loc)
		"hunt":
			if arg not in encounter_pool(db.field_value(loc, "zone"), true):
				return false
			frames.append({"kind": "turn", "turns": 1})
			start_encounter(arg)
			return true
		"travel":
			# Fast travel between known fast-travel points; spends a turn.
			var flags_here := db.list_field(loc, "flags")
			if arg == loc or not game.state.known.has(arg) or "fast travel" not in flags_here \
					or "fast travel" not in db.list_field(arg, "flags"):
				return false
			game.pass_turn()
			game.emit({"type": "paragraph", "spans": [{"text": "You travel to %s, keeping to the shadows." % db.field_value(arg, "name", arg), "bold": false, "italic": false, "class": ""}]})
			frames.append({"kind": "travel", "place": arg})
			var pool := encounter_pool("outside")
			var bonus: int = (int(game.value("player.perception")) - 10) / 2
			if not pool.is_empty() and game.rng.range_int(1, 20) < 10 - bonus:
				start_encounter(pool[game.rng.range_int(0, pool.size() - 1)])
			else:
				run()
			return true
		"rest":
			var blocker := RestSystem.blocking_condition(game)
			if blocker != "":
				var refusal: Program = db.program(blocker + "#rest refusal", "condition")
				if refusal == null:
					game.notice("You cannot rest while %s is active." % db.typed_value("condition", blocker, "name", blocker), false)
				else:
					for spans in render_paragraphs(refusal):
						game.emit({"type": "paragraph", "spans": spans})
				return false
			if not can_rest():
				return false
			var pool := encounter_pool(db.typed_value("location", loc, "zone"))
			if "safe rest" not in db.list_field(loc, "flags") and not pool.is_empty() and game.rng.chance(3, 20):
				game.notice("...but your nap is interrupted by the arrival of a creature.", false)
				start_encounter(pool[game.rng.range_int(0, pool.size() - 1)])
				return true
			var bedding := RestSystem.bedding(game)
			game.emit({"type": "paragraph", "spans": game.render(TextTemplate.compile(bedding.text))})
			RestSystem.recover(game, bedding.quality)
			game.pass_turn()
			game.pass_turn()
			show_location()
			return true
	return false


func can_rest() -> bool:
	return RestSystem.blocking_condition(game) == "" and RestSystem.bedding(game).quality != "none"


func _exit_door(exit: String) -> String:
	for option in exit.split(",").slice(1):
		var value: String = option.strip_edges()
		if value.begins_with("door "):
			return value.substr(5).strip_edges()
	return ""


func _door_locked(id: String) -> bool:
	var locked: String = game.content.typed_value("door", id, "locked", "no")
	if locked in ["yes", "no"]:
		return locked == "yes"
	return Condition.evaluate(Condition.compile(locked), game)


func _explore(loc: String) -> bool:
	var db: ContentDB = game.content
	var zone := db.field_value(loc, "zone")
	if zone in ["", "none"]:
		return false
	# Exploring spends its turn after the event or combat, as in the original.
	frames.append({"kind": "turn", "turns": 1})
	var room_first: bool = not game.rng.chance(2, 5)
	var bonus: int = (int(game.value("player.perception")) - 10) / 2 + game.feat_bonus("exploration bonus")
	var pool := encounter_pool(zone)
	if not pool.is_empty() and game.rng.chance(4, 20):
		start_encounter(pool[game.rng.range_int(0, pool.size() - 1)])
		return true
	if room_first and _explore_location(zone, bonus):
		return true
	var candidates := explore_events(zone)
	if not candidates.is_empty() and game.rng.range_int(1, 20) < bonus + 8:
		start_event(candidates[game.rng.range_int(0, candidates.size() - 1)])
		return true
	if not room_first and _explore_location(zone, bonus):
		return true
	var ambient: Program = db.program("%s#ambient" % zone)
	if ambient != null:
		var paras := render_paragraphs(ambient)
		if not paras.is_empty():
			game.emit({"type": "paragraph", "spans": paras[game.rng.range_int(0, paras.size() - 1)]})
	else:
		game.emit({"type": "paragraph", "spans": [{"text": "You wander around for a while but find nothing of interest.", "bold": false, "italic": false, "class": ""}]})
	run()
	return true


## Events that exploring in a zone can find now, sorted by ID.
func explore_events(zone: String) -> Array:
	return _events_found(zone, "exploring")


## Events that scavenging in a zone can find now, sorted by ID.
func scavenge_events(zone: String) -> Array:
	return _events_found(zone, "scavenging")


func _events_found(zone: String, way: String) -> Array:
	var db: ContentDB = game.content
	var candidates: Array = []
	for ev in db.all_of("event"):
		var found := ContentDB.found_by(db.typed_value("event", ev, "found by"))
		if not found[way] or zone not in found.zones:
			continue
		var st: Dictionary = game._event(ev)
		if st.resolved or not st.active:
			continue
		# Banned events are never found. Wards don't affect events, as in the original.
		if game.filter_block(db._list(db.get_def("event", ev), "tags"), true) != "":
			continue
		if int(db.typed_value("event", ev, "level", "0")) >= int(game.value("player.level")) + 2:
			continue
		if int(game.value("player.score")) < int(db.typed_value("event", ev, "min score", "-2147483648")):
			continue
		var req := db.typed_value("event", ev, "requires")
		if req != "":
			var c := Condition.compile(req)
			if c.has("error") or not Condition.evaluate(c, game):
				continue
		candidates.append(ev)
	candidates.sort()
	return candidates


## Scavenging at a fast-travel point (Core Mechanics/Scavenging.i7x): a
## perception check, then usually the generic find, otherwise one of the
## zone's scavenging events; afterwards a chance of a fight, then a turn.
func _scavenge(loc: String) -> bool:
	var db: ContentDB = game.content
	if ScavengeRules.rules(game) == null:
		return false
	if "fast travel" not in db.list_field(loc, "flags"):
		game.notice(ScavengeRules.text(game, "only at", "You can only scavenge from quick travel points."), false)
		return false
	var zone := db.typed_value("location", loc, "zone")
	if zone in ["", "none"]:
		zone = "outside"
	frames.append({"kind": "turn", "turns": 1})
	frames.append({"kind": "fight_chance", "zone": zone})
	var first: int = game.output.size()
	ScavengeRules.say(game, ScavengeRules.text(game, "start"))
	var bonus: int = (int(game.value("player.perception")) - 10) / 2 + game.feat_bonus("scavenge bonus")
	if not game.roll_check("Perception", bonus, int(ScavengeRules.text(game, "target", "10")), "perception"):
		ScavengeRules.say(game, ScavengeRules.text(game, "failure"))
		run()
		return true
	var generic := ScavengeRules.text(game, "generic")
	var others := scavenge_events(zone)
	others.erase(generic)
	var chance := ScavengeRules.chance(game)
	var ev := generic
	if not others.is_empty() and not game.rng.chance(chance[0], chance[1]):
		ev = others[game.rng.range_int(0, others.size() - 1)]
		ScavengeRules.say(game, ScavengeRules.text(game, "found") + " " + db.typed_value("event", ev, "name", ev) + ".")
	# The search and its roll belong on the event's page.
	var preface: Array = game.output.slice(first)
	game.output.resize(first)
	start_event(ev, preface)
	return true


## After scavenging: a d20 below 10 plus the perception bonus meets a
## creature of the zone (Hunting and Exploration.i7x, randomfightchance).
func _fight_chance(f: Dictionary) -> void:
	var pool := encounter_pool(str(f.zone))
	var bonus: int = (int(game.value("player.perception")) - 10) / 2 + game.feat_bonus("encounter bonus")
	if pool.is_empty() or game.rng.range_int(1, 20) >= 10 + bonus:
		return
	var id: String = pool[game.rng.range_int(0, pool.size() - 1)]
	frames.append({"kind": "encounter", "creature": id, "pc": 0, "title": true})
	frames.append({"kind": "pause"})


func _explore_location(zone: String, bonus: int) -> bool:
	if game.rng.range_int(1, 20) >= bonus + 7 or zone != "outside":
		return false
	var candidates: Array = []
	for id in game.content.all_of("location"):
		var flags: Array = game.content.list_field(id, "flags")
		if not game.state.known.has(id) and "fast travel" in flags and "private" not in flags:
			candidates.append(id)
	if candidates.is_empty():
		return false
	candidates.sort()
	var id: String = candidates[game.rng.range_int(0, candidates.size() - 1)]
	frames.append({"kind": "discover", "place": id})
	var pool := encounter_pool(zone)
	var fight_bonus: int = (int(game.value("player.perception")) - 10) / 2
	fight_bonus += game.feat_bonus("encounter bonus")
	if not pool.is_empty() and game.rng.range_int(1, 20) < 10 + fight_bonus:
		start_encounter(pool[game.rng.range_int(0, pool.size() - 1)])
	else:
		run()
	return true


## Creatures that can be met in a zone. Banned creatures are never met;
## warded ones only when `hunted` (the player hunts for that creature).
func encounter_pool(zone: String, hunted: bool = false) -> Array:
	var out: Array = []
	for id in game.content.all_of("creature"):
		var d: FscParser.Definition = game.content.get_def("creature", id)
		if zone not in Array(game.creature_field(id, "found in").split(",")).map(func(z): return z.strip_edges()):
			continue
		if game.filter_block(game.content._list(d, "tags"), hunted) != "":
			continue
		var active: String = game.content.typed_value("creature", id, "active", "always")
		if (active == "day" and not game.is_day()) or (active == "night" and game.is_day()):
			continue
		if CombatSystem.number(game, id, "level", 1) > int(game.value("player.level")) + 1 and "hard" not in game.settings.mode:
			continue
		out.append(id)
	out.sort()
	return out


func start_encounter(id: String) -> void:
	emit_title("Encounter: " + game.content.typed_value("creature", id, "name", id), "",
			game.content.typed_value("creature", id, "image"))
	frames.append({"kind": "encounter", "creature": id, "pc": 0})
	run()


# --- Saving -----------------------------------------------------------------

func save_frames() -> Array:
	return frames.duplicate(true)


func load_frames(saved: Array) -> void:
	frames = saved.duplicate(true)
	status = "idle" if frames.is_empty() else "continue"
	for f in frames:
		f.pc = int(f.get("pc", 0))
	if not game.state.combat.is_empty() and game.state.combat.get("result", "") == "":
		status = "combat"
