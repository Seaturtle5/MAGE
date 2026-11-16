class_name FightActionSystem
extends RefCounted
## The player's own choices in a fight beyond Attack, Seduce and the rest, the
## fight's hooks on the player's turn and at low enemy health, and a creature
## that turns into another mid-fight.
##
##   == item water_bottle
##   fight actions:
##       * Douse it with water -- Throw the water at it. [if enemy is tagged fire]
##           ~ take water_bottle
##           The flames hiss and shrink.
##           ~ enemy.hp - 15
##
## `fight actions:` is a menu field of creatures (while fighting it), characters
## (while they follow the player), items (while carried), feats (while the
## player has them) and the combat rules (always). Each option shown is a button
## of the fight; it plays as a scene (text, choices, effects such as
## `~ enemy.hp - 10`, `~ heal 10`, `~ enemy.damage - 2`, `~ win fight`,
## `~ end fight`, `~ attack enemy`) and uses the player's turn, as an item used
## in a fight does: the enemy acts next. `[if ...]` hides an option while the
## condition does not hold, `[always shown]` shows it greyed out instead.
##
## Hooks: `on: player's turn` plays at the start of each of the player's turns
## (before the choice; `enemy.round` is the round), `on: enemy below 50%` once a
## fight when the enemy's health drops below that share of its most, after the
## player's action (a surrender, a boss's next phase). Both are fight scripts:
## text, conditions, value and fight effects, `play` of such scenes.
##
## `~ enemy becomes dragon_enraged`: the fight goes on against another creature
## (a second stage) with its own numbers, texts, `fight starts` and aftermath.

const FIELD := "fight actions"
## Where fight actions come from, in the order their buttons are shown.
const SOURCES := ["creature", "character", "item", "feat", "combat_rules"]
const TURN_MOMENT := "player's turn"
const BELOW_MOMENT := "enemy below "


## The definitions whose fight actions apply now, as [type, id] pairs.
static func _owners(game) -> Array:
	var c: Dictionary = game.state.combat
	var out: Array = [["creature", str(c.creature)]]
	for who: String in game.state.companions:
		out.append(["character", who])
	var carried: Array = game.state.inventory.keys().filter(func(id: String) -> bool: return int(game.state.inventory[id]) > 0)
	carried.sort()
	for id: String in carried:
		out.append(["item", id])
	for feat: String in game.state.feats:
		out.append(["feat", feat])
	var rules := CombatSystem.rules_id(game)
	if rules != "":
		out.append(["combat_rules", rules])
	return out


## The fight actions offered now: {key, label, description, enabled}, in the
## order of SOURCES; none while the player is held (only Struggle helps then).
static func offered(game) -> Array:
	var c: Dictionary = game.state.combat
	var out: Array = []
	if c.is_empty() or str(c.get("result", "")) != "" or c.get("grappled", false):
		return out
	for pair: Array in _owners(game):
		# The menu "<id>.fight actions", from the definition or an extension of it.
		var menu_id := "%s.%s" % [pair[1], FIELD]
		if not game.content.menus.has(menu_id) or not game.content.has(pair[1], pair[0]):
			continue
		var menu: Dictionary = game.content.menus[menu_id]
		var options: Array = menu.get("options", [])
		for i in options.size():
			var o: Dictionary = options[i]
			var ok := true
			if str(o.condition) != "":
				var cond := Condition.compile(o.condition)
				ok = not cond.has("error") and Condition.evaluate(cond, game)
			if not ok and not o.always_shown:
				continue
			var key := "%s@%d" % [menu_id, i]
			var label := TextTemplate.compile(str(o.label), "fight_action:" + key)
			out.append({"key": key, "enabled": ok, "description": str(o.description),
				"label": TextTemplate.plain(game.render(label)) if not label.has("error") else str(o.label)})
	return out


## Plays a fight action chosen by the player (its key from offered()): the
## option's scene, then the enemy's turn (SceneRunner's combat_item_end step).
static func start(runner, key: String) -> bool:
	var game = runner.game
	var chosen := false
	for a: Dictionary in offered(game):
		if a.key == key and a.enabled:
			chosen = true
	if not chosen:
		return false
	runner.frames.append({"kind": "combat_item_end"})
	runner._push(key, {})
	runner.run()
	return true


## At the start of each of the player's turns: the low-health hooks, then the
## hooks `on: player's turn`. Either may end the fight.
static func turn_starts(game) -> void:
	var c: Dictionary = game.state.combat
	if c.is_empty() or str(c.get("result", "")) != "":
		return
	check_below(game)
	if c.result != "":
		return
	var played := false
	for hid: String in game.content.all_of("hook"):
		if game.content.typed_value("hook", hid, "on") != TURN_MOMENT:
			continue
		var when: String = game.content.typed_value("hook", hid, "when")
		if when != "" and not Condition.evaluate(Condition.compile(when), game):
			continue
		played = true
		CombatSystem._play(game, game.content.program("%s#do" % hid, "hook"))
		if c.result != "":
			return
	if played:
		CombatSystem._check_end(game)  # a hook may have brought someone to 0 health


## Hooks `on: enemy below N%`, each once a fight, when the enemy's health is
## below that share of its most (and its `when:` holds).
static func check_below(game) -> void:
	var c: Dictionary = game.state.combat
	if c.is_empty() or str(c.get("result", "")) != "" or int(c.get("maxhp", 0)) <= 0 or not c.has("vars"):
		return
	var fired: Array = c.vars.get("below_fired", [])
	var played := false
	for hid: String in game.content.all_of("hook"):
		var on: String = game.content.typed_value("hook", hid, "on")
		if not on.begins_with(BELOW_MOMENT) or hid in fired:
			continue
		var share := int(on.substr(BELOW_MOMENT.length()).trim_suffix("%"))
		if int(c.hp) * 100 >= share * int(c.maxhp):
			continue
		var when: String = game.content.typed_value("hook", hid, "when")
		if when != "" and not Condition.evaluate(Condition.compile(when), game):
			continue
		fired.append(hid)
		c.vars["below_fired"] = fired
		played = true
		CombatSystem._play(game, game.content.program("%s#do" % hid, "hook"))
		if c.result != "":
			return
	if played:
		CombatSystem._check_end(game)


## `~ enemy becomes X`: the fight goes on against creature X, with its own
## health, numbers and texts (a second stage); its `fight starts` plays, and its
## `defeated` or `victory` follows the fight.
static func become(game, id: String) -> void:
	var c: Dictionary = game.state.combat
	if not game.content.has(id, "creature"):
		game.warn("There is no creature '%s' to become." % id)
		return
	VariantSystem.pick(game, id)
	c.creature = id
	c.overrides = {}
	c.hp = CombatSystem.number(game, id, "hp", 12)
	c.maxhp = c.hp
	c.libido = CombatSystem.number(game, id, "libido", 0)
	c.penalty = 0
	c.grappled = false
	c.vars.erase("below_fired")
	if id not in game.state.encountered:
		game.state.encountered.append(id)
	BodySystem.remember_strain(game, game.creature_field(id, "form", id))
	# The fight's aftermath follows the creature fought now.
	var frames: Array = game.runner.frames
	for i in range(frames.size() - 1, -1, -1):
		if frames[i].has("fight"):
			var fight: Dictionary = (frames[i].fight as Dictionary).duplicate()
			fight.creature = id
			frames[i].fight = fight
			break
	var image: String = game.creature_field(id, "image")
	if image != "":
		game.emit({"type": "image", "image": image})
	CombatSystem._play(game, game.content.program(id + "#fight starts", "creature"))


# --- Validation ---------------------------------------------------------------

## Fight actions (written on a definition or added by an extension) and the fight hooks.
static func check(v) -> void:
	for menu_id: String in v.db.menus:
		if not menu_id.ends_with("." + FIELD):
			continue
		var menu: Dictionary = v.db.menus[menu_id]
		var def: FscParser.Definition = menu.def
		v._path = def.path
		var id := menu_id.trim_suffix("." + FIELD)
		var types: Array = SOURCES.filter(func(t: String) -> bool: return v.db.has(id, t))
		if types.size() > 1:
			v._err(def.line, "%s and %s %s both have fight actions under one ID; give one of them another ID." % [
				" and ".join(types.slice(0, -1).map(func(t: String) -> String: return "%s %s" % [t, id])), types[-1], id])
		elif types.is_empty():
			continue  # a menu of another kind that happens to end so
		if types.has("character") and not v.db.get_def("character", id).fields.has("companion"):
			v._warn(def.line, "%s has no companion: block, so it never follows the player and its fight actions are never offered." % id)
		var options: Array = menu.get("options", [])
		if options.is_empty():
			v._err(def.line, "'fight actions:' needs options: '* Label' with what happens indented below.")
		for i in options.size():
			var prog: Program = v.db.program("%s@%d" % [menu_id, i])
			if prog == null:
				continue
			v._path = prog.path
			for ins: Dictionary in prog.code:
				if ins.op == "fight":
					v._err(ins.line, "A fight action plays inside a fight; it cannot start another fight.")
				elif ins.op == "goto" and str(ins.target) in ["end", "back"]:
					v._err(ins.line, "A fight action cannot use '-> %s': the fight goes on after it (end the fight with ~ win fight, ~ lose fight or ~ end fight)." % ins.target)
	for hid: String in v.db.all_of("hook"):
		var on: String = v.db.typed_value("hook", hid, "on")
		if on.begins_with(BELOW_MOMENT):
			var d: FscParser.Definition = v.db.get_def("hook", hid)
			v._path = d.path
			var share := on.substr(BELOW_MOMENT.length())
			if not share.ends_with("%") or not share.trim_suffix("%").is_valid_int() \
					or int(share.trim_suffix("%")) < 1 or int(share.trim_suffix("%")) > 99:
				v._err(d.fields["on"].line, "'on: enemy below N%' needs a share from 1% to 99%, such as 'enemy below 25%'.")
