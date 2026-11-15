class_name HuntSystem
extends RefCounted
## Hunting a creature, after the original's hunt command (Hunting and
## Exploration.i7x). Without `== hunt_rules` the hunted creature is always met.
## With them, it is one entry in a pool the hunt draws from:
##
##   == hunt_rules my_hunting
##   target weight: 2                          (an expression; entries of the target)
##   target weight modifiers:
##       player has feat tracker: + 2          ("condition: amount" lines)
##   others when: not player has feat loner    (whether the zone's other creatures join)
##   other skipped when: chance 1 in 3         (tested for each other creature)
##   not found:
##       You find no trace of it.              (played when the pool is empty)
##
## The other creatures are those random meetings could bring (bans and wards
## apply); the hunt then meets whoever is drawn.


static func rules(game) -> String:
	var defs: Dictionary = game.content.all_of("hunt_rules")
	return "" if defs.is_empty() else str(defs.keys()[0])


static func _field(game, field: String, fallback: String = "") -> String:
	var id := rules(game)
	return fallback if id == "" else game.content.typed_value("hunt_rules", id, field, fallback)


static func _holds(game, field: String, fallback: bool) -> bool:
	var text := _field(game, field)
	if text == "":
		return fallback
	return Condition.evaluate(Condition.compile(text), game)


## Whether hunting is possible now (`hunt when`; true without it).
static func allowed(game) -> bool:
	return _holds(game, "hunt when", true)


## The target's entries in the pool: `target weight` plus its modifiers.
static func target_weight(game) -> int:
	var e := Expr.parse(_field(game, "target weight", "1"))
	var n: int = 1 if e.has("error") else int(Expr._num(Expr.evaluate(e, game)))
	var d: FscParser.Definition = game.content.get_def("hunt_rules", rules(game))
	if d != null and d.fields.has("target weight modifiers"):
		for l: FscParser.Line in d.fields["target weight modifiers"].children:
			if l.is_blank() or not ":" in l.text:
				continue
			var p := l.text.rsplit(":", true, 1)
			if Condition.evaluate(Condition.compile(p[0].strip_edges()), game):
				var amount := Expr.parse(CompanionSystem.amount_text(p[1]))
				if not amount.has("error"):
					n += int(Expr._num(Expr.evaluate(amount, game)))
	return maxi(0, n)


## The creature a hunt for `target` in `zone` meets, or "" when nothing is found.
static func pick(game, target: String, zone: String) -> String:
	if rules(game) == "":
		return target
	var pool: Array = []
	for _i in target_weight(game):
		pool.append(target)
	if _holds(game, "others when", true):
		for id: String in game.runner.encounter_pool(zone):
			if id != target and not _holds(game, "other skipped when", false):
				pool.append(id)
	if pool.is_empty():
		return ""
	return str(pool[game.rng.range_int(0, pool.size() - 1)])
