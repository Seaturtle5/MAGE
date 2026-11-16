class_name VoreSystem
extends RefCounted
## The player as predator: consuming (vore) or unbirthing a beaten creature,
## after the original's Alt Vore (Core Mechanics/Alt Vore.i7x) and the offer in
## its win rule (Alt Combat.i7x:1270-1360).
##
## One `== vore_rules` definition (pack data) says who can vore or unbirth
## (`can vore when`, `can unbirth when`), when a win offers it (`vore when`,
## `unbirth when`, the odds `vore chance` / `unbirth chance` out of
## `... chance out of`, `vore always when`), whether the player's choice is
## automatic (`vore automatic when`, `unbirth automatic when`), when a vore is a
## hard vore (`hard vore when`), and the texts and scripts (`vore urge`,
## `both urge`, `vore`, `hard vore`, `unbirth` ...). The engine offers it after a
## fight won by fighting outside events, never for unique creatures or creatures
## (or their forms) tagged `no_vore`; `no_hard_vore` rules out the hard vore and
## `no_unbirth` the unbirthing. The scripts do the rest with effects such as
## `~ absorb enemy stat`, `~ infect enemy` and `~ unbirth pregnancy`.

const SCRIPTS := ["vore urge", "vore urge automatic", "unbirth urge", "unbirth urge automatic", "both urge",
	"both urge automatic", "hunger wins", "womb wins", "vore", "hard vore", "unbirth"]


static func rules(game) -> String:
	var defs: Dictionary = game.content.all_of("vore_rules")
	return "" if defs.is_empty() else str(defs.keys()[0])


static func rule(game, field: String, fallback: String = "") -> String:
	var id := rules(game)
	return fallback if id == "" else game.content.typed_value("vore_rules", id, field, fallback)


## A condition field; `empty` is its value when the field is not written.
static func holds(game, field: String, empty: bool) -> bool:
	var text := rule(game, field)
	if text == "":
		return empty
	var c := Condition.compile(text)
	return not c.has("error") and Condition.evaluate(c, game)


## A number field (an expression) plus its `<field> modifiers` lines that hold.
static func number(game, field: String, fallback: int) -> int:
	var e := Expr.parse(rule(game, field, str(fallback)))
	var n: int = fallback if e.has("error") else Expr._num(Expr.evaluate(e, game))
	var id := rules(game)
	var d: FscParser.Definition = game.content.get_def("vore_rules", id) if id != "" else null
	if d == null or not d.fields.has(field + " modifiers"):
		return n
	for l: FscParser.Line in d.fields[field + " modifiers"].children:
		if l.is_blank() or not ":" in l.text:
			continue
		var p := l.text.rsplit(":", true, 1)
		var c := Condition.compile(p[0].strip_edges())
		if c.has("error") or not Condition.evaluate(c, game):
			continue
		var amount := Expr.parse(CompanionSystem.amount_text(p[1]))
		if not amount.has("error"):
			n += Expr._num(Expr.evaluate(amount, game))
	return n


## The original's "Player can vore" / "Player can UB".
static func can(game, kind: String) -> bool:
	return rules(game) != "" and holds(game, "can %s when" % kind, false)


## A creature that is never consumed this way: unique ones, and those whose own
## or whose form's tags hold `no_vore` (or `no_<kind>` for hard vore, unbirth).
static func excluded(game, creature: String, kind: String) -> bool:
	if creature == "" or not game.content.has(creature, "creature"):
		return true
	if game.creature_field(creature, "unique", "no") == "yes":
		return true
	var tags := tags_of(game, creature)
	if "no_vore" in tags:
		return true
	return kind != "vore" and ("no_" + kind.replace(" ", "_")) in tags


## A creature's own tags and those written on its form (not the tags of other
## creatures that share the form).
static func tags_of(game, creature: String) -> Array:
	if creature == "" or not game.content.has(creature, "creature"):
		return []
	# With the tags added or removed in play (CreatureChangeSystem).
	var tags: Array = CreatureChangeSystem.creature_tags(game, creature)
	return tags + CreatureChangeSystem.own_tags(game, "form", game.creature_field(creature, "form", creature))


## What a won fight offers: {"vore": bool, "unbirth": bool}. Only a win by
## fighting outside an event (the original's fightoutcome 10, inasituation false).
static func offers(game, creature: String, result: String) -> Dictionary:
	var out := {"vore": false, "unbirth": false}
	if rules(game) == "" or result not in ["won", "won by fighting"] or game.runner.current_event() != "":
		return out
	if can(game, "vore") and not excluded(game, creature, "vore") and holds(game, "vore when", true):
		var chance := number(game, "vore chance", 0)
		var out_of := maxi(1, number(game, "vore chance out of", 100))
		out.vore = game.rng.chance(chance, out_of) or holds(game, "vore always when", false)
	if can(game, "unbirth") and not excluded(game, creature, "unbirth") and holds(game, "unbirth when", true):
		var chance := number(game, "unbirth chance", 0)
		out.unbirth = game.rng.chance(chance, maxi(1, number(game, "unbirth chance out of", 100)))
	return out


static func automatic(game, kind: String) -> bool:
	return holds(game, "%s automatic when" % kind, false)


static func program(game, field: String) -> Program:
	var id := rules(game)
	return null if id == "" else game.content.program("vore_rules:%s#%s" % [id, field])


## Consumes or unbirths the creature being fought now: the fight counts as won
## that way, and the rules' `vore` (or `hard vore`) or `unbirth` script plays.
static func perform(game, kind: String) -> void:
	var creature: String = game.current_creature()
	if rules(game) == "" or creature == "":
		game.warn("Nothing to %s." % kind)
		return
	game.last_fight = "won by vore" if kind == "vore" else "won by unbirth"
	if not game.state.combat.is_empty():
		game.state.combat.result = game.last_fight
	var field := kind
	if kind == "vore" and not excluded(game, creature, "hard vore") and holds(game, "hard vore when", false) \
			and (program(game, "hard vore") != null or game.content.program(creature + "#hard vore", "creature") != null):
		field = "hard vore"
	# The consequences play after the scene, whichever scene it is.
	var after := program(game, "after unbirth" if kind == "unbirth" else "after vore")
	if after != null:
		game.runner.frames.append({"kind": "script", "pid": after.id, "pc": 0})
	# The creature's own scene (`vore:`, `hard vore:`, `unbirth:` on the creature,
	# with its `... when` condition) when the rules' `own scene when` holds; else the rules'.
	var own: Program = game.content.program(creature + "#" + field, "creature")
	var own_when: String = game.creature_field(creature, field + " when")
	if own != null and holds(game, "own scene when", true) \
			and (own_when == "" or Condition.evaluate(Condition.compile(own_when), game)):
		game.runner.frames.append({"kind": "script", "pid": own.id, "pc": 0})
		return
	var prog := program(game, field)
	if prog != null:
		game.runner.frames.append({"kind": "script", "pid": prog.id, "pc": 0})


## Stat absorption (the original's, Alt Vore.i7x:160-188): one attribute the
## creature has more of than the player, and at least the rules' `absorb above`
## (an expression), rises by 1.
static func absorb_stat(game, quiet: bool) -> void:
	var creature: String = game.current_creature()
	if creature == "":
		return
	var floor_value := number(game, "absorb above", 0)
	var pool: Array = []
	for stat in CombatSystem.ATTRIBUTES:
		var theirs := CombatSystem.stat(game, creature, stat)
		if int(game.value("player." + stat)) < theirs and theirs >= floor_value:
			pool.append(stat)
	if pool.is_empty():
		return
	var stat: String = pool[game.rng.range_int(0, pool.size() - 1)]
	game.change_value("player." + stat, 1)
	game.notice("%s +1" % stat.capitalize(), quiet)


## Infection with the creature being fought now (its form, or its cross infection).
static func infect_enemy(game) -> void:
	var creature: String = game.current_creature()
	var form: String = game.creature_field(creature, "form", "") if creature != "" else ""
	if form != "" and game.creature_field(creature, "infectious", "yes") != "no":
		BodySystem.infect(game, form)


## The creature's size: its form's `scale` (3, human size, when not written).
static func scale_of(game, creature: String) -> int:
	if creature == "":
		return 0
	var form: String = game.creature_field(creature, "form", creature)
	return BodySystem.form_scale(game, form)
