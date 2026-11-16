class_name FightControlSystem
extends RefCounted
## Fights steered from content, and the effects that change fights and creatures
## in play (the original's combat abort, battleground, ishunting, `now dam is 0`,
## `now fightoutcome is 11`, lootchance and attack entries changed in play).
##
##   ~ end fight                  the fight stops with no winner (combat abort);
##                                `ended:` after the fight, else `fled:`
##   ~ no second fight            the Hard Mode / Bad Luck second fight queued after
##                                this meeting does not come (battleground "void")
##   ~ cancel blow                in a creature's attack text: this blow does no damage
##   ~ this fight counts as won by seduction
##                                after a fight: the way it was won (or lost) changes
##   ~ enemy becomes dragon_two   a second stage (FightActionSystem.become)
##   ~ creature wolf tag + no_vore, ~ form husky tag - bipedal   (CreatureChangeSystem)
##   ~ creature husky attack -> hunter_attack (or -> default)    (CreatureChangeSystem)
##   ~ creature reindeer loot chance + 3 to 10 up to 80          (CreatureChangeSystem)
##
## `fight random in zoo, campus:` meets a random creature of one of those zones,
## and the condition `player is hunting` holds while the meeting came from a hunt
## for that creature.

## The effects compiled here (Effect rules named "fight:...").
const OPS := ["end_fight", "no_second_fight", "cancel_blow", "fight_counts_as", "enemy_becomes", "tag_change",
	"creature_script", "loot_chance"]
## The ways of winning or losing a fight can be changed to afterwards.
const COUNTS_AS := ["won by fighting", "won by seduction", "lost by injury", "lost by lust", "lost by submitting"]


## Compiles one of the effects above from its rule and match.
static func compile_effect(rule: String, m: RegExMatch) -> Dictionary:
	match rule:
		"fight:end":
			return {"op": "end_fight"}
		"fight:no_second":
			return {"op": "no_second_fight"}
		"fight:cancel_blow":
			return {"op": "cancel_blow"}
		"fight:counts_as":
			# "won by fighting" and "lost by injury" are the plain results.
			var result := m.get_string(1)
			return {"op": "fight_counts_as", "result": {"won by fighting": "won", "lost by injury": "lost"}.get(result, result)}
		"fight:becomes":
			return {"op": "enemy_becomes", "creature": m.get_string(1)}
		"fight:tag":
			var tags: Array = []
			for t in m.get_string(4).split(",", false):
				if t.strip_edges() != "":
					tags.append(t.strip_edges())
			return {"op": "tag_change", "type": m.get_string(1), "id": m.get_string(2), "add": m.get_string(3) == "+", "tags": tags}
		"fight:script":
			return {"op": "creature_script", "creature": m.get_string(1), "field": m.get_string(2), "target": m.get_string(3)}
		"fight:loot":
			var amt := Effect.amount(m.get_string(3))
			if amt.has("error"):
				return {"error": amt.error}
			return {"op": "loot_chance", "creature": m.get_string(1), "how": m.get_string(2), "amount": amt}
	return {"error": "unknown fight effect"}


static func apply(game, e: Dictionary) -> void:
	match e.op:
		"tag_change":
			CreatureChangeSystem.change_tags(game, e.type, e.id, e.add, e.tags)
			return
		"creature_script":
			CreatureChangeSystem.replace_script(game, e.creature, e.field, e.target)
			return
		"loot_chance":
			CreatureChangeSystem.change_loot_chance(game, e)
			return
		"no_second_fight":
			# The second fight and its words wait below the first meeting (SceneRunner._queue_second_fight).
			game.runner.frames = game.runner.frames.filter(func(f: Dictionary) -> bool: return not f.get("second", false))
			return
		"fight_counts_as":
			counts_as(game, e.result)
			return
	var c: Dictionary = game.state.combat
	if c.is_empty() or c.result != "":
		if c.is_empty():
			game.warn("'%s' only works during a fight." % e.op.replace("_", " "))
		return
	match e.op:
		"end_fight":
			c.result = "ended"
		"cancel_blow":
			c.vars["blow_cancelled"] = true
		"enemy_becomes":
			FightActionSystem.become(game, e.creature)


## A blow cancelled by its attack text (`~ cancel blow`): true once, then cleared.
static func take_cancelled_blow(game) -> bool:
	var c: Dictionary = game.state.combat
	if c.is_empty() or not c.get("vars", {}).get("blow_cancelled", false):
		return false
	c.vars.erase("blow_cancelled")
	return true


## After a fight, while its scenes play (the creature's `defeated` or `victory`):
## the fight counts as won or lost another way (the original's "now fightoutcome
## is 11"). The outcome block of `fight X:` follows the new way when it has one.
static func counts_as(game, result: String) -> void:
	var frames: Array = game.runner.frames
	var at := -1
	for i in range(frames.size() - 1, -1, -1):
		if frames[i].kind == "combat_end":
			at = i
			break
	var before: String = str(frames[at].result) if at >= 0 else game.last_fight
	if before == "" or before.get_slice(" ", 0) != result.get_slice(" ", 0):
		game.warn("'this fight counts as %s' only changes how a fight just %s was %s." % [result, "won" if result.begins_with("won") else "lost", result.get_slice(" ", 0)])
		return
	game.last_fight = result
	if not game.state.combat.is_empty():
		game.state.combat.result = result
	if at < 0:
		return
	var end: Dictionary = frames[at]
	end.result = result
	# The scene that started the fight goes on with the block for the new way, if
	# it still stands at the block chosen for the old one.
	if at > 0 and end.has("outcomes"):
		var owner: Dictionary = frames[at - 1]
		var outcomes: Dictionary = end.outcomes
		var category := result.get_slice(" ", 0)
		var old_pc := int(outcomes.get(before, outcomes.get(category, end.after)))
		if int(owner.get("pc", -1)) == old_pc:
			owner.pc = int(outcomes.get(result, outcomes.get(category, end.after)))


## The zone a `fight random in a, b, c:` fight draws from (one of them at random,
## a zone named twice twice as likely; `x.zone` is the zone a text value holds),
## or the player's zone for `fight random:` (also when the value holds none).
static func random_zone(game, ins: Dictionary) -> String:
	var zones: Array = ins.get("zones", [])
	if zones.is_empty():
		return game.zone_here()
	var zone := str(zones[game.rng.range_int(0, zones.size() - 1)])
	if "." in zone:
		zone = str(game.value(zone)) if game.value(zone) != null else ""
		if zone == "":
			return game.zone_here()
	return zone


## `player is hunting`: the meeting going on came from a hunt for that creature
## (the original's ishunting), through its encounter, fight and aftermath.
static func hunting(game) -> bool:
	return game.runner.frames.any(func(f: Dictionary) -> bool: return f.kind == "encounter" and f.get("hunted", false))


## Validator checks for the effects above.
static func check_effect(v, e: Dictionary, line: int, owner: String) -> void:
	match e.op:
		"tag_change":
			v._need(e.id, e.type, line)
			for t: String in e.tags:
				v._need(t, "tag", line)
		"creature_script":
			v._need(e.creature, "creature", line)
			if e.target != "default":
				if v.db.program(e.target) == null:
					v._err(line, "There is no scene or text called '%s' for %s's %s.%s" % [e.target, e.creature, e.field, v._suggest(e.target, v._ids("scene"))])
				else:
					var bad: String = v._combat_unsafe(e.target, 0)
					if bad != "":
						v._err(line, "A creature's %s can only be a scene of text, conditions and value or fight effects ('%s' %s)." % [e.field, e.target, bad])
		"loot_chance":
			v._need(e.creature, "creature", line)
			var d: FscParser.Definition = v.db.get_def("creature", e.creature)
			if d != null and not d.fields.has("loot") and not d.fields.has("variants"):
				v._err(line, "%s has no 'loot:' whose chance could change; give it one ('loot: item 20%%') or use ~ creature %s loot item N%%." % [e.creature, e.creature])
			if e.amount.has("value"):
				v._check_expr(e.amount.value, line)
		"enemy_becomes":
			v._need(e.creature, "creature", line)
	if e.op in ["end_fight", "cancel_blow", "enemy_becomes"] and not v.in_fight(owner):
		v._warn(line, "'%s' only works during a fight (a creature's combat scripts or attacks, a fight action or a fight hook)." % e.op.replace("_", " "))


## Whether a script of `owner` runs during a fight: a creature's scripts, its
## `attacks:` and `fight actions:`, any `fight actions:` option and the fight hooks.
static func fight_owner(db: ContentDB, owner: String) -> bool:
	if db.has(owner, "creature") or owner.ends_with(".fight actions"):
		return true
	if owner.ends_with(".attacks") and db.has(owner.trim_suffix(".attacks"), "creature"):
		return true
	if db.has(owner, "hook"):
		var on: String = db.typed_value("hook", owner, "on")
		return on in ["player hits", FightActionSystem.TURN_MOMENT] or on.begins_with(FightActionSystem.BELOW_MOMENT)
	return db.has(owner, "combat_rules")
