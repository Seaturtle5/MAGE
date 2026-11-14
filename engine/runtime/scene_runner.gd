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


## Programs started while the runner waits on the player (a choice, a page
## break, a fight): they play when the current scene ends.
var _deferred: Array = []


## Runs a program right away (for effects that trigger scenes during a turn).
func play_now(pid: String) -> void:
	if status in ["choice", "continue", "combat", "input"]:
		_deferred.append(pid)  # not on top of the frame that waits for the player
		return
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
	if game.content.has(target, "captivity") and not game.content.has(target, "scene"):
		frames.append({"kind": "captivity", "id": target, "step": "start"})
		return
	var prog: Program = game.content.program(target)
	if prog == null:
		game.warn("Nothing to play: '%s'" % target)
		game.emit({"type": "notice", "text": "[missing scene '%s']" % target})
		return
	var f := {"kind": "script", "pid": target, "pc": 0}
	f.merge(extra)
	frames.append(f)


func _push_if(pid: String) -> void:
	if game.content.program(pid) != null:
		frames.append({"kind": "script", "pid": pid, "pc": 0})


## A shop's steps: its title and intro, then its menu until the player leaves.
func _shop_step(f: Dictionary) -> bool:
	if f.step == "start":
		f.step = "menu"
		emit_title(ShopSystem.field(game, f.id, "name", f.id))
		_push_if("shop:%s#intro" % f.id)
		return false
	var opts := ShopSystem.options(game, f.id)
	var cur := ShopSystem.currency(game, f.id)
	game.emit({"type": "paragraph", "spans": [{"text": "You have %s." % ShopSystem.amount(cur, ShopSystem.money(game, cur)),
		"bold": false, "italic": true, "class": ""}]})
	pending = opts.map(func(o): return o)
	game.emit({"type": "choices", "options": opts.map(func(o): return {"text": o.text, "description": "", "enabled": o.enabled})})
	status = "choice"
	return true


## `~ use X` in a scene (the original's "process X"): the item's use text plays
## now, one is used up if it is carried and used up by use, and an infectious
## item infects after its text, as using it from the inventory would.
func use_item_now(id: String) -> void:
	var db: ContentDB = game.content
	if not db.has(id, "item"):
		return
	if db.typed_value("item", id, "consumed", "yes") != "no" and int(game.state.inventory.get(id, 0)) > 0:
		game.apply({"op": "take", "item": id, "amount": {"value": {"op": "num", "v": 1}}, "quiet": true})
	var strain := str(game.state.values.get("item.%s.infectious" % id, db.typed_value("item", id, "infectious")))
	if strain != "" and strain != "nothing":
		frames.append({"kind": "item_infect", "form": strain})
	_push_if(id + "#use")
	if status == "idle" and not frames.is_empty():
		run()


## A birth: its steps run as a frame (see PregnancySystem.birth).
func start_birth(litter: int) -> void:
	frames.append({"kind": "birth", "step": "birth", "n": 0, "litter": litter})
	if status == "idle":
		var before: int = game.output.size()
		run()
		if status == "idle" and game.output.slice(before).all(func(e): return e.type in ["scene_end", "location"]):
			game.output.resize(before)


## Plays a creature's encounter field as a scene, if it has one.
func _push_encounter(creature: String) -> void:
	game.fight_cancelled = false  # only the encounter that is about to play can call off its fight
	if game.content.program(creature + "#encounter") != null:
		frames.append({"kind": "script", "pid": creature + "#encounter", "pc": 0})


## The creature whose meeting is under way (its encounter scene or fight), or "".
func meeting() -> String:
	for i in range(frames.size() - 1, -1, -1):
		var f: Dictionary = frames[i]
		if f.kind == "encounter":
			return str(f.creature)
		if f.has("encountering"):
			return str(f.encountering.creature)
	return ""


func current_event() -> String:
	for i in range(frames.size() - 1, -1, -1):
		if frames[i].has("event"):
			return frames[i].event
	return ""


# --- Running ----------------------------------------------------------------

## The game has ended: whatever was playing stops and the epilogue plays
## (EndingSystem). Called by Game.end_game, also from inside a running scene.
func begin_epilogue() -> void:
	frames.clear()
	pending = []
	_deferred.clear()
	frames.append({"kind": "epilogue", "step": "start", "pc": 0})
	if status != "running":
		run()


func _epilogue_step(f: Dictionary) -> bool:
	match f.step:
		"start":
			f.step = "endings"
			f["list"] = EndingSystem.ordered(game)
			f["i"] = 0
			emit_title("The end")
		"endings":
			if f.i >= f.list.size() or EndingSystem.stopped(game):
				f.step = "done"
				return true
			var id: String = f.list[f.i]
			f.i += 1
			if EndingSystem.applies(game, id):
				EndingSystem.trigger(game, id)
				if game.content.program("%s#play" % id, "ending") != null:
					frames.append({"kind": "script", "pid": "%s#play" % id, "pc": 0})
		"done":
			frames.pop_back()
			status = "ended"
			game.emit({"type": "game_over"})
			return false
	return true


func run() -> void:
	status = "running"
	var guard := 0
	while not frames.is_empty():
		guard += 1
		if guard > 100000:
			game.warn("Scene runner stopped: too many steps (a loop in content?)")
			break
		var f: Dictionary = frames[-1]
		if f.kind == "epilogue":
			if not _epilogue_step(f):
				return
			continue
		if f.kind == "move_on":
			# After a leaving event: the move happens only if the event said "~ continue moving".
			frames.pop_back()
			if game.continue_moving:
				game.continue_moving = false
				_walk(f.dir)
			continue
		if f.kind == "arrival":
			# After arriving (and the place's own enter scene): an arrival event, if one comes up.
			frames.pop_back()
			var ev := arrival_event(f.mode)
			if ev != "":
				_queue_event(ev)
			continue
		if f.kind in ["travel", "discover"]:
			frames.pop_back()
			if f.kind == "travel":
				frames.append({"kind": "arrival", "mode": "travel"})
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
				VariantSystem.pick(game, f.creature, f.get("hunted", false))
				if f.get("title", false):
					_encounter_title(f.creature)
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
			# The frame goes first, so scenes the aftermath starts (a level up) play next.
			frames.pop_back()
			CombatSystem.aftermath(game, f.creature, f.result)
			game.state.combat = {}
			continue
		if f.kind == "vore_offer":
			if _vore_step(f):
				return
			continue
		if f.kind == "feat_choice":
			if _feat_choice_step(f):
				return
			continue
		if f.kind == "ask":
			if not f.shown:
				f.shown = true
				game.emit({"type": "input", "prompt": TextTemplate.plain(game.render(f.prompt)),
					"value": str(game.value(f.path)) if game.value(f.path) != null else "", "max": f.max})
				status = "input"
				return
			frames.erase(f)
			continue
		if f.kind == "menu":
			if _menu_step(f):
				return
			continue
		if f.kind == "captivity":
			if _captivity_step(f):
				return
			continue
		if f.kind == "shop":
			if _shop_step(f):
				return
			continue
		if f.kind == "birth":
			# A birth (PregnancySystem): `birth`, then each child's script, then `after birth`.
			var rid := PregnancySystem.rules(game)
			if f.step == "birth":
				f.step = "child"
				_push_if("pregnancy_rules:%s#birth" % rid)
			elif f.step == "child" and int(f.n) < int(f.litter):
				f.n = int(f.n) + 1
				PregnancySystem.make_child(game, int(f.n))
				_push_if("pregnancy_rules:%s#child" % rid)
			elif f.step == "child":
				f.step = "done"
				PregnancySystem.after_children(game)
				_push_if("pregnancy_rules:%s#after birth" % rid)
			else:
				frames.pop_back()
				PregnancySystem.finish_birth(game)
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
				var target: String = ins.target
				if target.begins_with("@picked#"):
					# "play picked creature victory": that field of the creature a scene picked.
					var picked := str(game.state.values.get("picked.creature", ""))
					if picked == "" or game.content.program(picked + target.substr(7)) == null:
						continue
					target = picked + target.substr(7)
				for _i in (Effect.resolve_amount(ins.times, game) if ins.has("times") else 1):
					_push(target, {})
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
					var zone: String = game.zone_here()
					var pool := encounter_pool("outside" if zone in ["", "none"] else zone)
					if pool.is_empty():
						f.pc = ins.after
						continue
					ins = ins.duplicate()
					ins.creature = pool[game.rng.range_int(0, pool.size() - 1)]
					VariantSystem.pick(game, ins.creature)
					_encounter_title(ins.creature)
				else:
					# `fight goblin (female):` meets that variant; otherwise one is picked.
					VariantSystem.pick(game, ins.creature, false, ins.variant)
				# The creature's encounter plays first, then this instruction runs again.
				f["encountering"] = ins
				f.pc -= 1
				_push_encounter(ins.creature)
				continue
			"return":
				_pop()
	if game.state.ending != "":
		status = "ended"  # the epilogue has played; nothing more happens
		return
	if not _deferred.is_empty():
		for pid in _deferred:
			_push(pid, {})
		_deferred.clear()
		run()
		return
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


## One step of a captivity (CaptivitySystem). Each round: the climax when lust
## is full, `each round`, the loss at humanity 0, else `situation` and the
## menu. Scripts run as frames above this one; it resumes at the next step.
## Returns true when the player must act (a choice or a page break).
func _captivity_step(f: Dictionary) -> bool:
	var id: String = f.id
	var v: Dictionary = game.state.values
	if game.captivity_exit != "" and f.step not in ["start", "pause"]:
		_end_captivity(game.captivity_exit == "escape")
		return false
	match f.step:
		"start":
			CaptivitySystem.begin(game, id)
			var title := CaptivitySystem.field(game, id, "name")
			if title != "":
				emit_title(title)
			f.step = "round"
			_push_field(id, "start")
			game.run_hooks("captivity starts")
		"round":
			v["captivity.round"] = CaptivitySystem.number(game, "round") + 1
			# Once obliging, the player stays so for the rest of this captivity, as in the original.
			var cond := Condition.compile(CaptivitySystem.field(game, id, "obliging when", CaptivitySystem.DEFAULT_OBLIGING))
			if not cond.has("error") and Condition.evaluate(cond, game):
				v["captivity.obliging"] = true
			CaptivitySystem.roll_recover(game)
			f.step = "each"
			if game.content.program("captivity:%s#climax" % id) != null \
					and CaptivitySystem.number(game, "lust") >= int(CaptivitySystem.field(game, id, "climax at", "100")):
				f.step = "climaxed"
				_push_field(id, "climax")
		"climaxed":
			v["captivity.lust"] = int(game.value("player.libido"))  # lust starts over from libido
			f.step = "each"
		"each":
			f.step = "check"
			_push_field(id, "each round")
			game.run_hooks("captivity round")
		"check":
			if int(game.value("player.humanity")) < 1:
				f.step = "done"
				_push_field(id, "lost")
			else:
				f.step = "menu"
				_push_field(id, "situation")
		"menu":
			v["captivity.enduring"] = false
			game.emit({"type": "paragraph", "spans": [{"text": CaptivitySystem.status_line(game, id)}]})
			var shown: Array = []
			pending = []
			for c in CaptivitySystem.choices(game, id):
				shown.append({"text": c.text, "description": "", "enabled": true})
				pending.append({"captivity": c.action, "enabled": true})
			var menu_id := id + ".actions"
			if game.content.menus.has(menu_id):
				var options: Array = game.content.menus[menu_id].options
				for i in options.size():
					var o: Dictionary = options[i]
					var c := Condition.compile(o.condition) if o.condition != "" else {}
					if c.is_empty() or (not c.has("error") and Condition.evaluate(c, game)):
						shown.append({"text": o.label, "description": o.description, "enabled": true})
						pending.append({"captivity": "action", "index": i, "enabled": true})
			game.emit({"type": "choices", "title": CaptivitySystem.field(game, id, "name"), "options": shown})
			status = "choice"
			return true
		"pause":
			f.step = "round"
			if game.captivity_exit != "":
				return false
			game.emit({"type": "page_break"})
			status = "continue"
			return true
		"escaped":
			_end_captivity(true)
		"done":
			_end_captivity(false)
	return false


## A captivity choice: struggle, oblige (or abide), endure (or recover), or one of its actions.
func _captivity_choice(f: Dictionary, p: Dictionary) -> void:
	var id: String = f.id
	var v: Dictionary = game.state.values
	f.step = "pause" if CaptivitySystem.field(game, id, "pause after each", "yes") != "no" else "round"
	match p.captivity:
		"struggle":
			# With `escape at`, the engine counts struggles and frees the player at that many;
			# without it, the struggle script decides (with ~ escape captivity).
			if CaptivitySystem.field(game, id, "escape at") == "":
				_push_field(id, "struggle")
				return
			v["captivity.struggle"] = CaptivitySystem.number(game, "struggle") + 1
			if CaptivitySystem.number(game, "struggle") >= CaptivitySystem.escape_at(game, id):
				f.step = "escaped"
				_push_field(id, "escape")
			else:
				_push_field(id, "struggle")
		"oblige":
			var obliging := CaptivitySystem.flag(game, "obliging")
			if obliging or game.content.program("captivity:%s#abide" % id) == null:
				_push_field(id, "oblige")
			else:
				_push_field(id, "abide")
		"endure":
			v["captivity.enduring"] = true
			if CaptivitySystem.flag(game, "recover") and game.content.program("captivity:%s#recover" % id) != null:
				v["captivity.recover"] = false
				_push_field(id, "recover")
			else:
				_push_field(id, "endure")
		"action":
			frames.append({"kind": "script", "pid": "%s.actions@%d" % [id, p.index], "pc": 0})


## Ends the captivity frame; an escape lets a turn pass, as in the original.
func _end_captivity(escaped: bool) -> void:
	CaptivitySystem.reset(game)
	game.captivity_exit = ""
	frames.pop_back()
	if escaped:
		frames.append({"kind": "turn", "turns": 1})


## `~ choose feat <group>`: the feats of that group the player can take now.
## The vore offer after a won fight (VoreSystem; Alt Combat.i7x:1300-1360): the
## urge text, then the choice, or the automatic act when the rules say so.
func _vore_step(f: Dictionary) -> bool:
	var v: bool = f.vore
	var u: bool = f.unbirth
	var va := VoreSystem.automatic(game, "vore")
	var ua := VoreSystem.automatic(game, "unbirth")
	if f.step == "start":
		f.step = "decide"
		var urge := "vore urge" if not u else "unbirth urge" if not v else "both urge"
		if v and u:
			urge = "both urge automatic" if va and ua else "hunger wins" if va else "womb wins" if ua else "both urge"
		elif (v and va) or (u and ua):
			urge += " automatic"
		var prog := VoreSystem.program(game, urge)
		if prog != null:
			frames.append({"kind": "script", "pid": prog.id, "pc": 0})
		return false
	# Decide: act at once, or offer the choice.
	var act := ""
	if v and u:
		act = "" if va == ua else "vore" if va else "unbirth"
	elif (v and va) or (u and ua):
		act = "vore" if v else "unbirth"
	if act != "":
		frames.erase(f)
		_vore_do(f, act)
		return false
	var shown: Array = []
	pending = []
	var labels := {"vore": VoreSystem.rule(game, "vore label", "Consume them"),
		"unbirth": VoreSystem.rule(game, "unbirth label", "Unbirth them")}
	if v and u:
		for kind in ["vore", "unbirth"]:
			shown.append({"text": labels[kind], "enabled": true})
			pending.append({"vore": kind, "enabled": true})
		if not (va and ua):
			shown.append({"text": VoreSystem.rule(game, "suppress label", "Suppress the urge"), "enabled": true})
			pending.append({"vore": "suppress", "enabled": true})
	else:
		shown.append({"text": VoreSystem.rule(game, "give in label", "Give in"), "enabled": true})
		pending.append({"vore": "vore" if v else "unbirth", "enabled": true})
		shown.append({"text": VoreSystem.rule(game, "hold back label", "Hold back"), "enabled": true})
		pending.append({"vore": "suppress", "enabled": true})
	game.emit({"type": "choices", "options": shown})
	status = "choice"
	return true


func _vore_do(f: Dictionary, kind: String) -> void:
	if kind == "suppress":
		# Held back: the creature's own `defeated` scene plays as after any win.
		_push_if(str(f.creature) + "#defeated")
		return
	VoreSystem.perform(game, kind)


## `~ ask <value>: <prompt>`: the player types a short text into a value (the
## original's "get typed command": naming children and pets). The scene waits.
func ask_text(path: String, prompt: Dictionary, max_length: int = 40) -> void:
	frames.append({"kind": "ask", "path": path, "prompt": prompt, "max": max_length, "shown": false})
	if status == "idle":
		run()


## The player's typed answer: stored in the value, then the scene goes on.
func enter_text(text: String) -> bool:
	if status != "input" or frames.is_empty() or frames[-1].kind != "ask":
		return false
	var f: Dictionary = frames[-1]
	var clean := text.strip_edges().replace("\n", " ").replace("[", "(").replace("]", ")")
	game.set_value(str(f.path), clean.left(int(f.max)))
	frames.pop_back()
	run()
	return true


func choose_feat(group: String) -> void:
	frames.append({"kind": "feat_choice", "group": group, "shown": false})
	if status == "idle":
		run()


func _feat_choice_step(f: Dictionary) -> bool:
	if f.shown:
		frames.erase(f)
		return false
	f.shown = true
	var feats := LevelSystem.offered_feats(game, str(f.group))
	if feats.is_empty():
		frames.erase(f)
		return false
	var shown: Array = []
	pending = []
	for id: String in feats:
		shown.append({"text": game.content.typed_value("feat", id, "name", id),
			"description": game.content.typed_value("feat", id, "description"), "enabled": true})
		pending.append({"feat": id, "enabled": true})
	shown.append({"text": "Skip", "description": "Take no feat this time", "enabled": true, "leave": true})
	pending.append({"feat": "", "enabled": true})
	game.emit({"type": "choices", "title": "Choose a feat", "options": shown})
	status = "choice"
	return true


func _push_field(id: String, field: String) -> void:
	var pid := "captivity:%s#%s" % [id, field]
	if game.content.program(pid) != null:
		frames.append({"kind": "script", "pid": pid, "pc": 0})


# --- Input ------------------------------------------------------------------

## Picks option `index` (0-based) of the current choice list.
func choose(index: int) -> bool:
	if status != "choice" or index < 0 or index >= pending.size() or not pending[index].enabled:
		return false
	var p: Dictionary = pending[index]
	pending = []
	var f: Dictionary = frames[-1]
	if p.has("feat"):
		frames.erase(f)
		if str(p.feat) != "":
			game.apply(Effect.compile("feat + %s" % p.feat))
			_push_if("feat:%s#gained" % p.feat)
	elif p.has("vore"):
		frames.erase(f)
		_vore_do(f, str(p.vore))
	elif p.has("shop"):
		if p.shop == "leave":
			frames.pop_back()
		else:
			_push_if(ShopSystem.act(game, f.id, p))
	elif p.has("captivity"):
		_captivity_choice(f, p)
	elif p.has("to"):
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
	if fallback == "won":
		# A beaten creature may be consumed or unbirthed instead (VoreSystem): the
		# offer comes before the creature's `defeated` scene, which it may replace.
		var offer := VoreSystem.offers(game, ins.creature, result)
		if offer.vore or offer.unbirth:
			frames.append({"kind": "vore_offer", "creature": ins.creature, "vore": offer.vore, "unbirth": offer.unbirth,
				"step": "start"})
			return
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
	if loc == "" or not frames.is_empty() or game.state.ending != "":
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
			var target := exit_target(parts[1]) if parts.size() > 1 else ""
			var door := _exit_door(parts[1]) if parts.size() > 1 else ""
			var danger := db.typed_value("door", door, "leads to zone") if door != "" else ""
			# A dangerous door shows as the door ("Skyscrapers"), explored rather than entered.
			var exit_name: String = db.field_value(door, "name", door) if danger != "" or target == "" else db.field_value(target, "name", target)
			view.exits.append({"direction": parts[0].strip_edges(), "to": "" if danger != "" else target, "name": exit_name,
				"explore": danger != "", "enabled": not _door_locked(door)})
			if door != "" and door not in shown_doors:
				view.description.append_array(render_paragraphs(db.program(door + "#shown in room")))
				shown_doors.append(door)
	for c in db.all_of("character"):
		if game.where(c) == loc:
			var fields: Dictionary = db.get_def("character", c).fields
			view.people.append({"id": c, "name": db.typed_value("character", c, "name", c),
				"image": db.typed_value("character", c, "image"), "talk": fields.has("talk"), "sex": fields.has("sex"),
				"smell": fields.has("scent"), "look": fields.has("description"), "actions": db.menus.has("%s.actions" % c),
				"companion": c in game.state.companions,
				"tamed": CompanionSystem.is_companion(game, c) and Condition._truthy(game.value("%s.tamed" % c))})
			# A character's presence line ("Wren is whittling by the lean-to.") joins the description.
			var presence: Program = db.program("%s#presence" % c, "character")
			if presence != null:
				view.description.append_array(render_paragraphs(presence))
	var here := ItemSystem.ground(game, loc)
	for it in ItemSystem.ground_ids(game, loc):
		view.items.append({"id": it, "name": db.typed_value("item", it, "name", it), "count": int(here[it])})
	if game.zone_here(loc) != "":
		view.actions.append({"id": "explore", "label": "Explore"})
		if not encounter_pool(game.zone_here(loc), true).is_empty():
			view.actions.append({"id": "hunt", "label": "Hunt"})
	if "fast travel" in db.list_field(loc, "flags") and not db.all_of("scavenge_rules").is_empty():
		view.actions.append({"id": "scavenge", "label": "Scavenge"})
	if can_rest():
		view.actions.append({"id": "rest", "label": "Rest"})
	view.actions.append({"id": "wait", "label": "Wait"})
	if db.menus.has("%s.observe" % loc):
		view.actions.append({"id": "observe", "label": "Observe"})
	if db.menus.has("%s.actions" % loc):
		var settings: Dictionary = db.menus["%s.actions" % loc].settings
		view.actions.append({"id": "actions", "label": str(settings.get("title", "Actions"))})
	for shop in ShopSystem.here(game):
		view.actions.append({"id": "shop", "arg": shop, "label": ShopSystem.field(game, shop, "name", shop)})
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
					var e: Dictionary = ins.effect.duplicate()
					e["quiet"] = true  # effects inside shown text never add notices of their own
					game.apply(e)
			"goto":
				# A text field may hand over to a scene of text and conditions ("attack: -> wolf_attacks").
				paras += render_paragraphs(game.content.program(ins.target), depth + 1, run_effects)
				break
			"return":
				break
	return paras


## A text snippet said inside other text ("[pewtercharacterassess]"): its text,
## with its simple effects (scratch numbers, flags) applied as it is shown.
func render_inline(prog: Program) -> String:
	var out: PackedStringArray = []
	for p in render_paragraphs(prog, 0, true):
		out.append(TextTemplate.plain(p))
	return " ".join(out)


## Performs an idle action. Returns false if it is not available.
func act(action: String, arg: String = "") -> bool:
	if status != "idle" or game.state.ending != "":
		return false
	if action not in ["go", "talk", "sex", "smell", "look", "actions", "shop", "summon", "dismiss", "use", "take", "take_all", "observe", "explore", "hunt", "travel", "rest", "wait",
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
			# A leaving event for this way out plays instead of the move (the original's
			# "instead of going north from X"); "~ continue moving" lets the move go on after it.
			var leaving := leaving_event(loc, arg)
			if leaving != "":
				game.continue_moving = false
				frames.append({"kind": "move_on", "dir": arg})
				_queue_event(leaving)
				run()
				return true
			return _walk(arg)
		"talk":
			if game.where(arg) != loc or not db.get_def("character", arg).fields.has("talk"):
				return false
			game.set_value("%s.met" % arg, true)
			emit_title("Talking with %s" % db.typed_value("character", arg, "name", arg), arg)
			start("%s#talk" % arg)
			return true
		"sex", "smell", "look":
			# A character here: its sex scene, scent or description.
			var field: String = {"sex": "sex", "smell": "scent", "look": "description"}[action]
			if not db.has(arg, "character") or game.where(arg) != loc or db.program("%s#%s" % [arg, field], "character") == null:
				return false
			if action == "sex":
				game.set_value("%s.met" % arg, true)
				emit_title(db.typed_value("character", arg, "name", arg), arg)
			start("%s#%s" % [arg, field])
			return true
		"shop":
			# A shop here: its menu when open, else what it says about being closed.
			if arg not in ShopSystem.here(game):
				return false
			if not ShopSystem.is_open(game, arg):
				start("shop:%s#closed" % arg)
				return true
			frames.append({"kind": "shop", "id": arg, "step": "start"})
			run()
			return true
		"actions":
			# The place's actions menu, or a character's here ("actions:" fields).
			var owner := arg if arg != "" else loc
			if arg != "" and (not db.has(arg, "character") or game.where(arg) != loc):
				return false
			if not db.menus.has("%s.actions" % owner):
				return false
			start("%s.actions" % owner)
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
			var strain := str(game.state.values.get("item.%s.infectious" % arg, db.typed_value("item", arg, "infectious")))
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
		"summon", "dismiss":
			# A tamed companion joins the party, or one following is sent away.
			if not db.has(arg, "character") or not CompanionSystem.is_companion(game, arg):
				return false
			var joined := CompanionSystem.summon(game, arg) if action == "summon" else CompanionSystem.dismiss(game, arg)
			if status == "idle" and frames.is_empty():
				show_location()
			return joined
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
			if arg not in encounter_pool(game.zone_here(loc), true):
				return false
			frames.append({"kind": "turn", "turns": 1})
			start_encounter(arg, true)
			return true
		"travel":
			# Fast travel between known fast-travel points; spends a turn.
			var flags_here := db.list_field(loc, "flags")
			if arg == loc or not game.state.known.has(arg) or "fast travel" not in flags_here \
					or "fast travel" not in db.list_field(arg, "flags"):
				return false
			# An event that replaces the trip (the original's "instead of navigating X"):
			# it plays here, and the player only goes if the scene moves them.
			var instead := arrival_event("travel", arg, true)
			if instead != "":
				_queue_event(instead)
				run()
				return true
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
			var pool := encounter_pool(game.zone_here(loc))
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
	for option in exit.split(","):
		var value: String = option.strip_edges()
		if value.begins_with("door "):
			return value.substr(5).strip_edges()
	return ""


## Where an exit leads: its place, or "" for a door alone ("north: door skyscrapers").
static func exit_target(exit: String) -> String:
	var first := exit.split(",")[0].strip_edges()
	return "" if first.begins_with("door ") else first


## The doors on a place's exits.
func exit_doors(loc: String) -> Array:
	var out: Array = []
	var d: FscParser.Definition = game.content.get_def("location", loc)
	var exits: FscParser.Field = d.fields.get("exits", null) if d != null else null
	if exits == null:
		return out
	for l in exits.children:
		if not l.is_blank() and ":" in l.text:
			var door := _exit_door(l.text.split(":", true, 1)[1])
			if door != "" and door not in out:
				out.append(door)
	return out


func _door_locked(id: String) -> bool:
	var locked: String = game.content.typed_value("door", id, "locked", "no")
	if locked in ["yes", "no"]:
		return locked == "yes"
	return Condition.evaluate(Condition.compile(locked), game)


func _explore(loc: String, zone: String = "") -> bool:
	var db: ContentDB = game.content
	if zone == "":
		zone = game.zone_here(loc)
	if zone == "":
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


## Walks out of the current place by an exit (doors, carrying weight), then any arrival event.
func _walk(arg: String) -> bool:
	var db: ContentDB = game.content
	var loc: String = game.state.location
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
			var danger := db.typed_value("door", door, "leads to zone") if door != "" else ""
			if danger != "" and not _door_locked(door):
				# A dangerous door: going through explores its zone (Basic Locations.i7x:22-28).
				if int(game.value("player.hp")) < 1:
					game.notice("You are too injured to go far. You rest instead.", false)
					return _act("rest", "")
				return _explore(loc, danger)
			if _door_locked(door):
				var text: String = render_inline(db.program(door + "#locked text")) if db.program(door + "#locked text") != null else "The door is locked."
				game.notice(text, false)
				return false
			if door != "":
				var key := "door_state.%s.open" % door
				if not game.state.values.get(key, false):
					game.state.values[key] = true
					game.notice("(first opening the %s)" % db.typed_value("door", door, "name", door).to_lower(), false)
			if exit_target(parts[1]) == "":
				return false
			game.go_to(exit_target(parts[1]))
			if status == "idle":
				var ev := arrival_event("walk")
				if ev != "":
					start_event(ev)
			return true
	return false


## A leaving event for this way out of `loc` (`found by: leaving <place> <direction>`):
## available, its `requires` holding, the lowest `priority` first.
func leaving_event(loc: String, dir: String) -> String:
	var db: ContentDB = game.content
	var best := ""
	var best_priority := 1 << 30
	for ev in db.all_of("event"):
		var found := ContentDB.found_by(db.typed_value("event", ev, "found by"))
		if [loc, dir] not in found.leaving:
			continue
		var st: Dictionary = game._event(ev)
		if st.resolved or not st.active:
			continue
		var req := db.typed_value("event", ev, "requires")
		if req != "":
			var c := Condition.compile(req)
			if c.has("error") or not Condition.evaluate(c, game):
				continue
		var pr: int = int(db.typed_value("event", ev, "priority", "3"))
		if pr < best_priority:
			best = ev
			best_priority = pr
	return best


## The event that comes up when the player arrives here ("walk" or "travel"), as the
## original's WalkInEvent_Check and NavInEvent_Check: available events for this place,
## by `priority` (lowest first, ties in random order), past their `cooldown` turns,
## whose `requires` holds; each rolls its `chance` (default 100%) until one comes up.
func arrival_event(mode: String, place: String = "", replacing: bool = false) -> String:
	var db: ContentDB = game.content
	var loc: String = game.state.location if place == "" else place
	game.state.values["arrival.mode"] = mode
	var candidates: Array = []
	for ev in db.all_of("event"):
		var found := ContentDB.found_by(db.typed_value("event", ev, "found by"))
		if loc not in (found.walking if mode == "walk" else found.travelling):
			continue
		if (db.typed_value("event", ev, "replaces trip", "no") == "yes") != replacing:
			continue
		var st: Dictionary = game._event(ev)
		if st.resolved or not st.active:
			continue
		if game.filter_block(db._list(db.get_def("event", ev), "tags"), true) != "":
			continue
		if int(db.typed_value("event", ev, "level", "0")) > int(game.value("player.level")) + 1:
			continue
		if int(st.get("last_turn", -1)) >= 0 and game.state.turn - int(st.last_turn) <= int(db.typed_value("event", ev, "cooldown", "0")):
			continue
		var req := db.typed_value("event", ev, "requires")
		if req != "":
			var c := Condition.compile(req)
			if c.has("error") or not Condition.evaluate(c, game):
				continue
		candidates.append(ev)
	candidates.sort()
	# Shuffle, then a stable sort by priority (the original sorts randomly, then by priority).
	for k in range(candidates.size() - 1, 0, -1):
		var j: int = game.rng.range_int(0, k)
		var tmp = candidates[k]
		candidates[k] = candidates[j]
		candidates[j] = tmp
	var order := {}
	for k in candidates.size():
		order[candidates[k]] = k
	candidates.sort_custom(func(a, b):
		var pa: int = int(db.typed_value("event", a, "priority", "3"))
		var pb: int = int(db.typed_value("event", b, "priority", "3"))
		return pa < pb if pa != pb else order[a] < order[b])
	for ev in candidates:
		var chance: int = int(db.typed_value("event", ev, "chance", "100").trim_suffix("%"))
		if chance >= 100 or game.rng.chance(chance, 100):
			return ev
	return ""


## Starts an event on top of the frames that are running (no run of its own).
func _queue_event(event_id: String) -> void:
	game._event(event_id).last_turn = game.state.turn
	if game.content.field_value(event_id, "repeat", "once") == "once":
		game._event(event_id).resolved = true
	if game.content.typed_value("event", event_id, "name") != "":
		emit_title(game.content.field_value(event_id, "name", event_id))
	frames.append({"kind": "script", "pid": "%s#play" % event_id, "pc": 0, "event": event_id})


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
	var zone: String = game.zone_here(loc)
	if zone == "":
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


## "~ pick random creature tagged feline nearby": a creature of the player's zone
## (or the named one), with the tag if given (on the creature or its form), the
## favored ones counted twice. With none there, the scene falls back to the
## outside; "a creature is picked" is false when none can be found.
func pick_creature(tag: String, zone: String, favoring: Array, with_outside: bool = false) -> void:
	game.state.values.erase("picked.creature")
	var here: String = game.zone_here()
	var zones: Array = [zone] if zone != "" else [here if here != "" else "outside"]
	if zone == "" and zones[0] != "outside":
		zones.append("outside")
	# "nearby or outside": one pool from both.
	var groups: Array = [zones] if with_outside else zones.map(func(z): return [z])
	for group: Array in groups:
		var pool: Array = []
		var ids: Array = []
		for z: String in group:
			for id: String in encounter_pool(z):
				if id not in ids:
					ids.append(id)
		for id: String in ids:
			if tag != "" and tag not in game.content._list(game.content.get_def("creature", id), "tags") \
					and tag not in game.content.form_tags(game.content.typed_value("creature", id, "form", id)):
				continue
			pool.append(id)
			if id in favoring:
				pool.append(id)
		if not pool.is_empty():
			var picked: String = pool[game.rng.range_int(0, pool.size() - 1)]
			game.state.values["picked.creature"] = picked
			VariantSystem.pick(game, picked)
			return


## Creatures that can be met in a zone. Banned creatures are never met;
## warded ones only when `hunted` (the player hunts for that creature).
func encounter_pool(zone: String, hunted: bool = false) -> Array:
	var out: Array = []
	for id in game.content.all_of("creature"):
		var d: FscParser.Definition = game.content.get_def("creature", id)
		if zone not in Array(game.creature_field(id, "found in").split(",")).map(func(z): return z.strip_edges()):
			continue
		# Variants answer for their own filters (a goblin with banned males is met as a female).
		var skip := VariantSystem.all_filters(game.content, id)
		if game.filter_block(game.content._list(d, "tags").filter(func(t): return t not in skip), hunted) != "":
			continue
		if not VariantSystem.meetable(game, id, hunted):
			continue
		var active: String = game.content.typed_value("creature", id, "active", "always")
		if (active == "day" and not game.is_day()) or (active == "night" and game.is_day()):
			continue
		if CombatSystem.number(game, id, "level", 1) > int(game.value("player.level")) + 1 and "hard" not in game.settings.mode:
			continue
		out.append(id)
	out.sort()
	return out


func start_encounter(id: String, hunted: bool = false) -> void:
	frames.append({"kind": "encounter", "creature": id, "pc": 0, "title": true, "hunted": hunted})
	run()


func _encounter_title(id: String) -> void:
	emit_title("Encounter: " + game.creature_field(id, "name", id), "", game.creature_field(id, "image"))


# --- Saving -----------------------------------------------------------------

func save_frames() -> Array:
	return frames.duplicate(true)


func load_frames(saved: Array) -> void:
	frames = saved.duplicate(true)
	status = "idle" if frames.is_empty() else "continue"
	for f in frames:
		f.pc = int(f.get("pc", 0))
		if f.kind == "ask":
			f.shown = false  # asked again after loading
			f.max = int(f.get("max", 40))
	if not game.state.combat.is_empty() and game.state.combat.get("result", "") == "":
		status = "combat"
