class_name LevelSystem
extends RefCounted
## The player's levels, after the original's Leveling.i7x and the level check
## after every fight (Fighting.i7x).
##
## The rules are pack data, one `== level_rules` definition:
##
##   == level_rules player_levels
##   xp needed: player.level * 20 + 20        (an expression; required)
##   xp needed modifiers:
##       player has feat quick_study: - 5
##   levels when: player.hp > 0               (a condition)
##   level up:
##       You have gained level [player.level]!
##       ...                                  (stat choices, health, feats)
##
## After a fight, experience at or above `xp needed` raises the level by one
## and takes that much experience; then `level up` plays (it can offer
## choices). `~ check level` does the same from a scene, `~ level up player`
## raises the level whatever the experience (it can go below 0, as in the
## original). Without level rules the player never levels.
##
## Feats offered on a level (the original's FunFeatget): `~ choose feat <group>`
## lists the feats with that `group:` whose `available when:` holds and that
## the player lacks, plus a choice to skip. A chosen feat plays its `gained:`.


static func rules(game) -> String:
	var defs: Dictionary = game.content.all_of("level_rules")
	return "" if defs.is_empty() else str(defs.keys()[0])


static func rule(game, field: String, fallback: String = "") -> String:
	var id := rules(game)
	return fallback if id == "" else game.content.typed_value("level_rules", id, field, fallback)


## The experience the next level needs: `xp needed` plus its modifiers.
static func needed(game) -> int:
	# `xp needed` is required (the validator says so); the numbers are the game's own.
	var e := Expr.parse(rule(game, "xp needed", ""))
	if e.has("error"):
		return 1 << 30  # no usable rule: no level is ever reached
	var n: int = Expr._num(Expr.evaluate(e, game))
	var id := rules(game)
	if id != "":
		var d: FscParser.Definition = game.content.get_def("level_rules", id)
		if d != null and d.fields.has("xp needed modifiers"):
			for l: FscParser.Line in d.fields["xp needed modifiers"].children:
				if l.is_blank() or not ":" in l.text:
					continue
				var p := l.text.rsplit(":", true, 1)
				if Condition.evaluate(Condition.compile(p[0].strip_edges()), game):
					var amount := Expr.parse(CompanionSystem.amount_text(p[1]))
					if not amount.has("error"):
						n += Expr._num(Expr.evaluate(amount, game))
	return maxi(1, n)


## Levels up when the experience is enough (after a fight, or `~ check level`).
static func check(game) -> bool:
	if rules(game) == "":
		return false
	var cost := needed(game)
	if int(game.value("player.xp")) < cost:
		return false
	var gate := rule(game, "levels when")
	if gate != "" and not Condition.evaluate(Condition.compile(gate), game):
		return false
	level_up(game, cost)
	return true


## One level: the number and the experience change now (companions check
## against the new level right after a fight), then `level up` plays.
static func level_up(game, cost: int = -1) -> void:
	if cost < 0:
		cost = needed(game)
	game.set_value("player.level", int(game.value("player.level")) + 1)
	game.set_value("player.xp", int(game.value("player.xp")) - cost)
	# A notice of its own, so a level gained at the end of a long page of fight text is not missed.
	game.notice("Level %d" % int(game.value("player.level")), false)
	var pid := "level_rules:%s#level up" % rules(game)
	if rules(game) != "" and game.content.program(pid) != null:
		game.runner.play_now(pid)


## Feats of `group` the player can take now.
static func offered_feats(game, group: String) -> Array:
	var out: Array = []
	for id: String in game.content.all_of("feat"):
		if id in game.state.feats or game.content.typed_value("feat", id, "group") != group:
			continue
		var when: String = game.content.typed_value("feat", id, "available when")
		if when != "" and not Condition.evaluate(Condition.compile(when), game):
			continue
		out.append(id)
	out.sort_custom(func(a, b): return game.content.typed_value("feat", a, "name", a).naturalnocasecmp_to(
		game.content.typed_value("feat", b, "name", b)) < 0)
	return out


## The player takes a feat: it is added, then its `gained:` plays.
static func take_feat(game, id: String) -> void:
	game.apply(Effect.compile("feat + %s" % id))
	var pid := "feat:%s#gained" % id
	if game.content.program(pid) != null:
		game.runner.play_now(pid)
