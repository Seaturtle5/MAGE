class_name CompanionSystem
extends RefCounted
## Companions: characters who can follow the player and fight beside them,
## after the original's pets (Core Mechanics/Pets.i7x, Alt Combat.i7x and
## Fighting.i7x).
##
## A character becomes a possible companion with a `companion:` block; its
## fighting numbers are its `stats:` (level, damage, dexterity, charisma, xp).
##
##   == character korvin
##   stats:
##       level: 1
##       damage: 15
##       dexterity: 10
##   companion:
##       attacks with: fighting       (or seduction: raises the enemy's lust)
##       hit bonus: 0
##       stays when: <condition>      (not sent home when the party is too big)
##       tamed: yes                   (can be summoned from the start)
##   summon:
##       Korvin trots up beside you.  (~ cancel summon: he does not come)
##   dismiss:
##       Korvin heads home.           (~ cancel dismiss: he stays)
##   companion attack:
##       [one of]Korvin bites![or]Korvin lunges![at random]
##
## The party is the list of companions following now (state.companions). A
## tamed companion (`x.tamed`) can be summoned; `~ summon x` and `~ dismiss x`
## play the character's texts, `~ companion + x` and `~ companion - x` add or
## remove without them. Party members are where the player is.
##
## The rules are pack data, one `== companion_rules` definition: party size,
## experience, levels and the texts the engine says (see `rule`).

const DEFAULTS := {"level": 1, "xp": 0, "damage": 4, "dexterity": 10, "charisma": 10}


static func rules(game) -> String:
	var defs: Dictionary = game.content.all_of("companion_rules")
	return "" if defs.is_empty() else str(defs.keys()[0])


static func rule(game, field: String, fallback: String = "") -> String:
	var id := rules(game)
	return fallback if id == "" else game.content.typed_value("companion_rules", id, field, fallback)


## A number rule: its expression, plus every line of `<field> modifiers`
## ("condition: amount") whose condition holds.
static func number_rule(game, field: String, fallback: int) -> int:
	var text := rule(game, field, str(fallback))
	var e := Expr.parse(text)
	var n: int = fallback if e.has("error") else Expr._num(Expr.evaluate(e, game))
	for m in modifiers(game, field + " modifiers"):
		if Condition.evaluate(Condition.compile(m.cond), game):
			var amount := Expr.parse(m.amount)
			if not amount.has("error"):
				n += Expr._num(Expr.evaluate(amount, game))
	return n


## "condition: amount" lines of a rules field.
static func modifiers(game, field: String) -> Array:
	var out: Array = []
	var id := rules(game)
	if id == "":
		return out
	var d: FscParser.Definition = game.content.get_def("companion_rules", id)
	if d == null or not d.fields.has(field):
		return out
	for l: FscParser.Line in d.fields[field].children:
		if l.is_blank() or not ":" in l.text:
			continue
		var p := l.text.rsplit(":", true, 1)
		out.append({"cond": p[0].strip_edges(), "amount": amount_text(p[1]), "line": l.number})
	return out


## A modifier's amount as an expression: "+2" -> "2", "- level * 4" -> "0 - level * 4".
static func amount_text(text: String) -> String:
	var t := text.strip_edges().trim_prefix("+").strip_edges()
	return "0 " + t if t.begins_with("-") else t


static func is_companion(game, id: String) -> bool:
	var d: FscParser.Definition = game.content.get_def("character", id)
	return d != null and d.fields.has("companion")


static func field(game, id: String, key: String, fallback: String = "") -> String:
	var d: FscParser.Definition = game.content.get_def("character", id)
	if d == null:
		return fallback
	for p in CharacterSystem.pairs(d, "companion"):
		if p.key == key:
			return str(p.value)
	return fallback


static func num(game, id: String, key: String) -> int:
	var v = game.value("%s.%s" % [id, key])
	return int(v) if v != null else int(DEFAULTS.get(key, 0))


static func party(game) -> Array:
	return game.state.companions


static func limit(game) -> int:
	return maxi(0, number_rule(game, "party size", 1))


static func tamed(game) -> Array:
	var out: Array = []
	for id in game.content.all_of("character"):
		if is_companion(game, id) and Condition._truthy(game.value("%s.tamed" % id)):
			out.append(id)
	out.sort()
	return out


## Values a script about one companion can read: companion.id, name, level, xp,
## damage, dexterity, charisma.
static func _with(game, id: String) -> void:
	var v: Dictionary = game.state.values
	v["companion.id"] = id
	v["companion.name"] = WorldSystem.companion_name(game, id)
	for k in DEFAULTS:
		v["companion." + k] = num(game, id, k)


## Plays a companion text at once, in order (text, conditions and effects), so a
## `~ cancel summon` in it is known before the companion joins.
static func _play(game, pid: String) -> void:
	var prog: Program = game.content.program(pid)
	if prog != null:
		CombatSystem._play(game, prog)


# --- Joining and leaving --------------------------------------------------------

## `~ tame x`: x can be summoned from now on.
static func tame(game, id: String, yes: bool) -> void:
	game.state.values["%s.tamed" % id] = yes
	if not yes:
		leave(game, id)


## `~ summon x` (the original's "ally x"): plays the summon text unless the
## companion is not tamed, already follows or the party is full.
static func summon(game, id: String) -> bool:
	if not Condition._truthy(game.value("%s.tamed" % id)):
		game.notice("You have no ally called %s!" % WorldSystem.companion_name(game, id), false)
		return false
	if id in party(game):
		game.notice("%s is already following you!" % WorldSystem.companion_name(game, id), false)
		return false
	if party(game).size() >= limit(game):
		game.notice("You cannot have any more allies following you right now! If you want to choose %s, you'll have to send someone else away!" % WorldSystem.companion_name(game, id), false)
		return false
	game.cancel_companion = false
	_with(game, id)
	_play(game, "character:%s#summon" % id)
	if game.cancel_companion:
		game.cancel_companion = false
		return false
	join(game, id)
	return true


## `~ dismiss x`: plays the dismiss text ("You send your ally away.").
static func dismiss(game, id: String) -> bool:
	if id not in party(game):
		game.notice("%s is not following you!" % WorldSystem.companion_name(game, id), false)
		return false
	game.cancel_companion = false
	_with(game, id)
	if game.content.program("character:%s#dismiss" % id) != null:
		_play(game, "character:%s#dismiss" % id)
	else:
		game.notice(rule(game, "dismissed", "You send your ally away."), false)
	if game.cancel_companion:
		game.cancel_companion = false
		return false
	leave(game, id)
	return true


static func join(game, id: String) -> void:
	if id not in party(game):
		party(game).append(id)
	if is_companion(game, id):
		game.state.values["%s.tamed" % id] = true


static func leave(game, id: String) -> void:
	party(game).erase(id)


## Every turn: a party larger than allowed sends a companion home (the first
## one whose `stays when` does not hold), with the rules' `party too big` text.
static func tick(game) -> void:
	if party(game).size() <= limit(game):
		return
	for id: String in party(game).duplicate():
		var stays := field(game, id, "stays when")
		if stays != "" and Condition.evaluate(Condition.compile(stays), game):
			continue
		_with(game, id)
		_play(game, "companion_rules:%s#party too big" % rules(game))
		dismiss(game, id)
		return


# --- Fighting -------------------------------------------------------------------

## After the player's attack or seduction (Alt Combat.i7x:503-555): each party
## member attacks, or with `attacks with: seduction` raises the enemy's lust.
static func act_in_fight(game, creature: String) -> void:
	var c: Dictionary = game.state.combat
	for id: String in party(game).duplicate():
		if c.result != "" or int(c.hp) <= 0:
			return
		_with(game, id)
		var name: String = WorldSystem.companion_name(game, id)
		var level := num(game, id, "level")
		var hit_bonus := int(field(game, id, "hit bonus", "0")) + number_rule(game, "hit bonus", 0)
		var enemy_level := CombatSystem.number(game, creature, "level", 1)
		var immune: bool = game.creature_field(creature, "seduction immune", "no") == "yes"
		if field(game, id, "attacks with", "fighting") == "seduction" and not immune:
			var bonus := num(game, id, "charisma") + level * 2 + hit_bonus - 10
			bonus -= (20 - int(c.libido) / 3) + enemy_level * 2 - 10
			if CombatSystem._roll(game, name, bonus):
				var gain: int = (num(game, id, "charisma") / 3) * game.rng.range_int(70, 130) / 100
				c.libido = int(c.libido) + gain
				_attack_text(game, id)
				game.notice("%s raises the enemy's lust by %d!" % [name, gain], false)
				game.notice("Getting a little bit of a breather, and a nice show at the same time, gives you a chance to collect yourself. You gain 1 HP!", false)
				game.set_value("player.hp", int(game.value("player.hp")) + 1)
				if int(c.libido) - int(c.penalty) >= 100:
					c.result = "won by seduction"
			else:
				game.notice("%s's seduction attempt fails!" % name, false)
			continue
		var attack := num(game, id, "dexterity") + level * 2 + hit_bonus - 10
		var defense := CombatSystem.stat(game, creature, "dexterity") + enemy_level * 2 + CombatSystem.number(game, creature, "dodge bonus", 0) - 10
		if CombatSystem._roll(game, name, attack - defense):
			var damage: int = num(game, id, "damage") * game.rng.range_int(80, 120) / 100
			game.set_value("fight.damage", damage)
			_attack_text(game, id)
			game.notice("%d damage inflicted!" % damage, false)
			c.hp = int(c.hp) - damage
			c.penalty = int(c.penalty) + 10
			if int(c.hp) <= 0:
				c.result = "won"
		else:
			game.notice("%s misses!" % name, false)


static func _attack_text(game, id: String) -> void:
	var prog: Program = game.content.program("character:%s#companion attack" % id)
	if prog != null:
		CombatSystem._play(game, prog)


## After a fight (Alt Combat.i7x:1416-1422, 1480-1482; Fighting.i7x:109-116):
## party members note the fight; after a win they gain `companion xp` and the
## player gives up `player xp cost` each (unless `player xp cost when` fails);
## then any companion with enough experience gains a level.
static func after_fight(game, creature: String, won: bool) -> void:
	if party(game).is_empty():
		LevelSystem.check(game)  # the player's level (Fighting.i7x: after every fight)
		return
	if not game.state.combat.is_empty():
		game.set_value("fight.level", CombatSystem.number(game, creature, "level", 1))
	for id: String in party(game):
		game.state.stamps["%s.last_fight" % id] = game.state.turn  # a time value: `since x.last_fight`
		if not won:
			continue
		_with(game, id)
		game.set_value("%s.xp" % id, num(game, id, "xp") + number_rule(game, "companion xp", 0))
		var cost_when := rule(game, "player xp cost when")
		if cost_when == "" or Condition.evaluate(Condition.compile(cost_when), game):
			game.set_value("player.xp", int(game.value("player.xp")) - number_rule(game, "player xp cost", 0))
	LevelSystem.check(game)  # the player first: companions may not outgrow the player
	for id: String in party(game):
		check_level(game, id)


## A companion gains a level when its experience reaches `level up at` and
## `levels while` holds (the original: below the player's level).
static func check_level(game, id: String) -> void:
	_with(game, id)
	var needed := number_rule(game, "level up at", num(game, id, "level") * 10)
	var gate := rule(game, "levels while")
	if num(game, id, "xp") < needed or (gate != "" and not Condition.evaluate(Condition.compile(gate), game)):
		return
	level_up(game, id, needed)


## Pets.i7x:236: one level up; damage and dexterity grow every few levels.
static func level_up(game, id: String, cost: int = -1) -> void:
	_with(game, id)
	if cost < 0:
		cost = number_rule(game, "level up at", num(game, id, "level") * 10)
	var level := num(game, id, "level") + 1
	game.set_value("%s.level" % id, level)
	game.set_value("%s.xp" % id, num(game, id, "xp") - cost)
	var every_damage := int(rule(game, "damage every", "3"))
	var every_dex := int(rule(game, "dexterity every", "5"))
	if every_damage > 0 and level % every_damage == 0:
		game.set_value("%s.damage" % id, num(game, id, "damage") + 1)
	if every_dex > 0 and level % every_dex == 0:
		game.set_value("%s.dexterity" % id, num(game, id, "dexterity") + 1)
	_with(game, id)
	var pid := "companion_rules:%s#leveled" % rules(game)
	if game.content.program(pid) != null:
		_play(game, pid)
	else:
		game.notice("%s has gained level %d! Congratulations!" % [WorldSystem.companion_name(game, id), level], false)


# --- Offspring --------------------------------------------------------------------

## Children on record by where they live (`child.home`: with_you, bunker, roaming).
static func offspring(game, home: String) -> int:
	var n := 0
	for child in Array(game.state.values.get("pregnancy.offspring", [])):
		if child is Dictionary and (home == "total" or str(child.get("home", "")) == home):
			n += 1
	return n


## `~ send children from A to B`: moves every child living at A to B.
static func move_children(game, from: String, to: String) -> int:
	var list: Array = Array(game.state.values.get("pregnancy.offspring", [])).duplicate(true)
	var moved := 0
	for child in list:
		if child is Dictionary and (from == "any" or str(child.get("home", "")) == from):
			child["home"] = to
			moved += 1
	game.state.values["pregnancy.offspring"] = list
	return moved
