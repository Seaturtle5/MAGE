class_name CombatSystem
extends RefCounted
## The player's side of combat: weapons, worn gear bonuses and armor.
## Formula sources: Core Mechanics/Alt Combat.i7x:119-141, 334-640, 786-847,
## 974-1083, 1404-1488 and 1923-1950 at baseline 6d4920e. Feat effects
## (Weaponsmaster, Martial Artist ...) come with the feats package.

## Built-in special behaviours a creature's `special:` can name, with a chance
## where the original had one (Alt Combat.i7x, Table of Critter Combat).
const SPECIALS := ["grapple", "hump", "pounce", "firebreath"]
## Fight-local numbers scripts can read and change as `enemy.<name>`.
const ENEMY_NUMBERS := ["damage", "level", "hit_bonus", "dodge_bonus", "mind_bonus", "damage_low", "strength", "dexterity", "stamina",
	"perception", "intelligence", "charisma"]
## The player's own bonuses for this fight, read by the engine's rolls (the
## original's plhitbonus, pldodgebonus, pldamagebonus, plfleebonus, plmindbonus,
## plseducebonus): scripts change them as `fight.hit_bonus` and so on.
const PLAYER_BONUSES := ["hit_bonus", "dodge_bonus", "damage_bonus", "flee_bonus", "mind_bonus", "seduce_bonus"]
## Starting values of enemy numbers that are not 0 (`enemy.damage_low`: the low end of a blow's roll).
const ENEMY_DEFAULTS := {"damage_low": 80}


## One of the player's fight bonuses (`fight.<name>`), 0 when unset.
static func bonus_of(game, name: String) -> int:
	var c: Dictionary = game.state.combat
	return 0 if c.is_empty() else int(c.get("vars", {}).get(name, 0))
const ATTRIBUTES := ["strength", "dexterity", "stamina", "perception", "intelligence", "charisma"]


## A combat number of the creature: a change made during this fight
## (`~ enemy.damage + 2`), else a lasting one (`~ creature X damage + 2`),
## else the creature's (or its variant's) field.
static func number(game, id: String, field: String, default: int) -> int:
	var c: Dictionary = game.state.combat
	var key := field.replace(" ", "_")
	if not c.is_empty() and c.creature == id and c.get("overrides", {}).has(key):
		return int(c.overrides[key])
	return int(game.creature_field(id, field, str(default)))


static func stat(game, id: String, key: String) -> int:
	var c: Dictionary = game.state.combat
	if not c.is_empty() and c.creature == id and c.get("overrides", {}).has(key):
		return int(c.overrides[key])
	var lasting = game.state.values.get("creature.%s.%s" % [id, key])
	if lasting != null:
		return int(lasting)
	for entry in game.creature_field(id, "stats").split(","):
		var parts: PackedStringArray = entry.strip_edges().split(" ", false)
		if parts.size() == 2 and parts[0] == key:
			return int(parts[1])
	return 12


static func begin(game, id: String) -> void:
	if id not in game.state.encountered:
		game.state.encountered.append(id)
	game.state.combat = {"creature": id, "hp": number(game, id, "hp", 12),
		"maxhp": number(game, id, "hp", 12), "libido": number(game, id, "libido", 0),
		"penalty": 0, "round": 1, "grappled": false, "result": "", "overrides": {}, "vars": {}}
	if int(game.value("player.hp")) <= 0:
		game.state.combat.result = "lost"
		return
	if int(game.state.combat.libido) >= 100:
		game.state.combat.result = "won by seduction"
		return
	_weapon_values(game)
	BodySystem.remember_strain(game, game.creature_field(id, "form", id))
	# The rules' `fight starts`: the fight's bonuses (the original's start-of-fight
	# plhitbonus, pldodgebonus ...) and numbers that follow the game's mode (Hard
	# Mode's level boost); `fight.no_surprise` stops a first strike. Then the
	# creature's own `fight starts` (the original's PrepCombat): its numbers for
	# this fight, which may replace the rules' changes.
	var rules := rules_id(game)
	if rules != "":
		_play(game, game.content.program("combat_rules:%s#fight starts" % rules))
	_play(game, game.content.program(id + "#fight starts", "creature"))
	if game.state.combat.result != "":
		return
	# Fighting.i7x:73-88: an alert, agile creature can strike first.
	var surprise: int = (int(game.value("player.perception")) - 10) / 2 - (stat(game, id, "dexterity") - 10) / 2
	if bonus_of(game, "no_surprise") == 0 and surprise + game.rng.range_int(1, 20) < 6:
		game.notice("The creature gets the drop on you!", false)
		_retaliate(game)
	if game.state.combat.result == "":
		FightActionSystem.turn_starts(game)  # hooks `on: player's turn`
	if game.state.combat.result == "":
		show(game)


static func show(game) -> void:
	var c: Dictionary = game.state.combat
	var items: Array = []
	for id in game.state.inventory:
		if game.content.typed_value("item", id, "in combat", "no") == "yes":
			items.append({"id": id, "name": game.content.typed_value("item", id, "name", id), "count": int(game.state.inventory[id])})
	items.sort_custom(func(a, b): return a.name < b.name)
	game.emit({"type": "combat", "creature": c.creature, "items": items,
		"name": game.creature_field(c.creature, "name", c.creature),
		"hp": int(c.hp), "maxhp": int(c.maxhp), "lust": maxi(0, int(c.libido) - int(c.penalty)),
		"round": int(c.round), "grappled": c.grappled,
		"actions": ["struggle"] if c.grappled else ["attack", "seduce", "flee", "submit", "pass", "throw"],
		"fight_actions": FightActionSystem.offered(game),  # the player's extra choices (`fight actions:`)
		"text": "Round %d" % int(c.round)})


## `penalty` is subtracted after capping, as the weapon size penalty is.
static func _roll(game, label: String, bonus: int, enemy: bool = false, flee: bool = false, penalty: int = 0) -> bool:
	# `harder rolls when` (combat rules): the player's roll caps drop and the enemy's rise.
	var hard: bool = holds(game, "harder rolls when")
	var lower := -22 if hard == enemy else -25
	var upper := 19 if hard == enemy else 16
	bonus = maxi(lower, bonus) if flee else clampi(bonus, lower, upper)
	bonus -= penalty
	var roll: int = game.rng.range_int(1, 50)
	game.emit({"type": "roll", "text": "%s: 1d50(%d) %+d = %d vs >20" % [label, roll, bonus, roll + bonus]})
	return roll + bonus > 20


## The automatic action the combat rules name (`auto action: player.auto_combat`,
## the original's Instinctive Combat): attack, seduce, pass, flee or submit; "".
static func auto_action(game) -> String:
	var id := rules_id(game)
	if id == "":
		return ""
	var path: String = game.content.typed_value("combat_rules", id, "auto action", "")
	if path == "":
		return ""
	var v = game.value(path)
	var action := str(v) if v != null else ""
	return action if action in ["attack", "seduce", "pass", "flee", "submit"] else ""


## Plays the fight with the automatic action until it ends (struggling when
## grappled). Returns true when the fight ended.
static func auto_fight(game) -> bool:
	var action := auto_action(game)
	if action == "":
		return false
	for _i in 200:
		var c: Dictionary = game.state.combat
		if c.is_empty() or c.result != "":
			break
		act(game, "struggle" if c.grappled else action)
	return game.state.combat.is_empty() or game.state.combat.result != ""


static func act(game, action: String) -> bool:
	var c: Dictionary = game.state.combat
	if c.is_empty() or c.result != "":
		return false
	if c.grappled:
		if action != "struggle":
			return false
		_grapple(game)
	else:
		var id: String = c.creature
		var level := int(game.value("player.level"))
		var enemy_level := number(game, id, "level", 1)
		match action:
			"submit", "throw":
				c.result = "lost by submitting" if action == "submit" else "lost"
			"attack":
				player_attack(game)
			"seduce":
				var immune: bool = game.creature_field(id, "seduction immune", "no") == "yes"
				var defense := 20 - int(c.libido) / 3 + enemy_level * 2
				var hit := _roll(game, "Seduce", int(game.value("player.perception")) + level * 2 + bonus_of(game, "seduce_bonus") - defense - int(c.penalty))
				if hit and not immune:
					var gain: int = (int(game.value("player.charisma")) / 3) * game.rng.range_int(70, 130) / 100
					if game.rng.chance(game.role_number("morale"), 200):
						gain *= 2
					c.libido = int(c.libido) + gain
					game.notice("Enemy lust +%d." % gain, false)
					if int(c.libido) - int(c.penalty) >= 100:
						c.result = "won by seduction"
				elif immune:
					game.notice("This creature is immune to seduction.", false)
			"flee":
				player_flee(game)
			"pass":
				pass
			_:
				return false
		if action in ["attack", "seduce"] and c.result == "":
			CompanionSystem.act_in_fight(game, id)
		FightActionSystem.check_below(game)  # hooks `on: enemy below N%`
		if c.result == "":
			player_round_end(game)
		if c.result == "":
			_retaliate(game)
	c.round = int(c.round) + 1
	FightActionSystem.turn_starts(game)  # hooks `on: player's turn`
	if c.result == "":
		show(game)
	return true


## The player's attack (the Attack button, or `~ attack enemy` from a fight's
## item scene): the hit roll, the damage and the words for it.
static func player_attack(game) -> void:
	var c: Dictionary = game.state.combat
	if c.is_empty() or c.result != "":
		return
	var id: String = c.creature
	var level := int(game.value("player.level"))
	var w := ItemSystem.weapon(game)
	# Alt Combat.i7x:342: the creature's dodge bonus (mondodgebonus) adds to its defense.
	var bonus: int = int(game.value("player.dexterity")) + level * 2 + int(w.hit) + bonus_of(game, "hit_bonus") \
		- stat(game, id, "dexterity") - number(game, id, "level", 1) * 2 - number(game, id, "dodge bonus", 0)
	if not _roll(game, "Attack", bonus, false, false, int(w.penalty)):
		return
	var damage: int = int(w.damage) * game.rng.range_int(80, 120 + level) / 100
	# The rules' `player damage`: feats and weapons change `fight.damage` before
	# the attribute bonus (the original's Martial Artist, Powerful, Weaponsmaster ...).
	var rules := rules_id(game)
	if rules != "" and game.content.program("combat_rules:%s#player damage" % rules) != null:
		_weapon_values(game)
		c.vars["damage"] = damage
		_play(game, game.content.program("combat_rules:%s#player damage" % rules))
		damage = int(c.vars.get("damage", damage))
	var stat_name := "perception" if w.type == "ranged" else "strength"
	damage += (int(game.value("player." + stat_name)) - 10) / 2 + ItemSystem.bonus(game, "damage bonus") + bonus_of(game, "damage_bonus")

	var motivated: bool = game.rng.chance(game.role_number("morale"), 200)
	if motivated:
		damage *= 2
	c.hp = int(c.hp) - maxi(0, damage)
	c.penalty = int(c.penalty) + 20
	var weapon_text: String = TextTemplate.plain(game.render(TextTemplate.compile(str(w.text), "weapon:" + str(w.id))))
	game.set_value("fight.weapon", weapon_text)
	game.set_value("fight.dealt", damage)
	game.set_value("fight.motivated", motivated)
	game.notice(rule_text(game, "player hits",
		"You hit [the enemy] with [fight.weapon] for [fight.dealt] damage."), false)
	if int(c.hp) <= 0:
		c.result = "won"
	else:
		# Hooks `on: player hits` (the original's helping children, Alt Combat.i7x:488-500).
		hooks(game, "player hits")
		if int(c.hp) <= 0 and c.result == "":
			c.result = "won"


## The player's attempt to get away (the Flee button, or `~ try to flee`):
## the rules' `before flee` script, then the roll.
static func player_flee(game) -> void:
	var c: Dictionary = game.state.combat
	if c.is_empty() or c.result != "":
		return
	var id: String = c.creature
	var rules := rules_id(game)
	if rules != "":
		_play(game, game.content.program("combat_rules:%s#before flee" % rules))
	if c.result != "":
		return
	var level := int(game.value("player.level"))
	# `fight.flee_now`: a bonus for this attempt only (a cover cloud), then cleared.
	var once := bonus_of(game, "flee_now")
	c.vars.erase("flee_now")
	# Alt Combat.i7x:807: the creature's hit bonus also works against fleeing.
	var bonus := int(game.value("player.dexterity")) + int(game.value("player.intelligence")) + level * 2 \
		+ ItemSystem.bonus(game, "flee bonus") + bonus_of(game, "flee_bonus") + once \
		- stat(game, id, "dexterity") - number(game, id, "level", 1) * 2 - 10 - number(game, id, "hit bonus", 0)
	if _roll(game, "Flee", bonus, false, true):
		c.result = "fled"
		game.notice(rule_text(game, "flee", "You get away from [the enemy]."), false)
	else:
		game.notice(rule_text(game, "flee fails", "You fail to get away."), false)


## After the player's action and before the creature's turn: the rules'
## `each round` script (lasting effects such as the original's poison).
static func player_round_end(game) -> void:
	var rules := rules_id(game)
	if rules == "":
		return
	_play(game, game.content.program("combat_rules:%s#each round" % rules))
	_check_end(game)


## After an item was used in a fight, the enemy gets its turn
## (Alt Combat.i7x:739-759): the item use spent the player's round.
static func after_item(game) -> void:
	var c: Dictionary = game.state.combat
	if c.is_empty() or c.result != "":
		return
	if int(game.value("player.hp")) <= 0:
		c.result = "lost"
		return
	FightActionSystem.check_below(game)
	if c.result == "":
		player_round_end(game)
	if c.result == "":
		_retaliate(game)
	c.round = int(c.round) + 1
	FightActionSystem.turn_starts(game)


## The creature's turn (Alt Combat.i7x, retaliate and the Table of Critter
## Combat): its `each round` script, then one of its `attacks` whose condition
## holds (that option is the whole turn), else a built-in special, else the
## standard attack: `before attack`, the hit roll (`strike with` names another
## attribute, as the original's altstrike), the attack or `miss`, `after attack`.
static func _retaliate(game) -> void:
	var c: Dictionary = game.state.combat
	var id: String = c.creature
	c.get("vars", {}).erase("blow_cancelled")  # `~ cancel blow` counts for this turn's blow only
	_script(game, id, "each round")
	if c.result == "" and not _check_end(game):
		var option := _pick_attack(game, id)
		if option >= 0:
			_play(game, game.content.program("%s.attacks@%d" % [id, option]))
		elif _has_special(game, id, "firebreath"):
			_firebreath(game, id)
		else:
			_standard_turn(game, id)
		if c.result == "":
			_script(game, id, "after attack")
	_check_end(game)


static func _standard_turn(game, id: String) -> void:
	var c: Dictionary = game.state.combat
	_script(game, id, "before attack")
	if c.result != "":
		return
	if not hit_roll(game, game.creature_field(id, "strike with", "dexterity")):
		if CreatureChangeSystem.combat_script(game, id, "miss") != null:
			_script(game, id, "miss")
		else:
			game.notice(TextTemplate.plain(game.render(TextTemplate.compile("[The enemy] misses."))), false)
		return
	var grapple := _special_chance(game, id, "grapple")
	if grapple > 0 and game.rng.chance(grapple, 100):
		c.grappled = true
		_script(game, id, "grapple")
		_grapple_damage(game)
		return
	# Alt Combat.i7x, humping rule: in the creature's own body, a lewd grind.
	var hump := _special_chance(game, id, "hump")
	if hump > 0 and game.part_form("player", "torso") == game.creature_field(id, "form", id) and game.rng.chance(hump, 100):
		var level := number(game, id, "level", 1)
		var damage: int = number(game, id, "damage", 3) * (spread(game, id) + 30 + 2 * level) / 100
		_text(game, id, "hump", "You are grabbed by your opponent, who grinds against your body. The scent momentarily entices your infected body, and your drive to keep resisting wanes. You take %d damage!" % damage)
		# The rules' `hump lust` (an expression) raises the value playing arousal.
		var lust_expr := Expr.parse(rule(game, "hump lust", "0"))
		var lust: int = 0 if lust_expr.has("error") else Expr._num(Expr.evaluate(lust_expr, game))
		if game.role("arousal") != "":
			game.set_value(game.role("arousal"), game.role_number("arousal") + lust)
		strike(game, damage, "normal", false)
		return
	# Alt Combat.i7x, ftaurpounce rule: double damage, no shield.
	var pounce := _special_chance(game, id, "pounce")
	if pounce > 0 and game.rng.chance(pounce, 100):
		var damage: int = number(game, id, "damage", 3) * spread(game, id) / 50
		_text(game, id, "pounce", "Your opponent pounces atop you, knocking you down and clawing at you before you push it away.")
		strike(game, damage, "no shield")
		return
	_script(game, id, "attack")
	strike(game, roll_damage(game, id, 100))


## The creature's to-hit roll: its attribute and level against the player's
## (dexterity: dodging; any other: the original's intstrike, against the same
## attribute of the player).
static func hit_roll(game, attribute: String = "dexterity") -> bool:
	var c: Dictionary = game.state.combat
	var id: String = c.creature
	# The rules' `avoid`: the player may escape the blow before it is rolled
	# (`~ fight.avoided = yes`: the original's Dazzle, bo staff block, Black Belt).
	var rules := rules_id(game)
	if rules != "" and game.content.program("combat_rules:%s#avoid" % rules) != null:
		c.vars.erase("avoided")
		_play(game, game.content.program("combat_rules:%s#avoid" % rules))
		if Condition._truthy(c.vars.get("avoided", false)):
			c.vars.erase("avoided")
			return false
	var bonus: int
	if attribute == "dexterity":
		# Alt Combat.i7x:984: the creature's hit bonus (monhitbonus) adds to its attack.
		bonus = stat(game, id, "dexterity") + number(game, id, "level", 1) * 2 + number(game, id, "hit bonus", 0)
		bonus -= int(game.value("player.dexterity")) + int(game.value("player.level")) * 2 + ItemSystem.bonus(game, "dodge bonus") + bonus_of(game, "dodge_bonus")
		# `fight.dodge_now`: a bonus for this one roll (the original's Flash), then cleared.
		bonus -= bonus_of(game, "dodge_now")
		c.vars.erase("dodge_now")
	else:
		# A mental attack (the original's intstrike): its mind bonus against the player's.
		bonus = stat(game, id, attribute) + number(game, id, "level", 1) * 2 + number(game, id, "mind bonus", 0) - 10
		bonus -= int(game.value("player." + attribute)) + int(game.value("player.level")) * 2 + bonus_of(game, "mind_bonus") - 10
	return _roll(game, "Enemy attack", bonus, true)


## The random part of a creature's blow, in percent: from its `damage low`
## (80 unless a fight changes `enemy.damage_low`, as the original's pepper spray) to 120.
static func spread(game, id: String) -> int:
	var low := clampi(number(game, id, "damage low", 80), 0, 120)
	return game.rng.range_int(low, 120)


## The creature's damage for one blow: its damage x 80-120%, scaled by `percent`,
## with the Hard mode critical hit.
static func roll_damage(game, id: String, percent: int) -> int:
	var damage: int = number(game, id, "damage", 3) * spread(game, id) / 100 * percent / 100
	# The rules' `enemy damage`: content changes `fight.incoming` (the original's
	# Hard Mode critical hit and Toughened live in the game's rules, not here).
	var rules := rules_id(game)
	if rules != "" and game.content.program("combat_rules:%s#enemy damage" % rules) != null:
		var c: Dictionary = game.state.combat
		c.vars["incoming"] = damage
		_play(game, game.content.program("combat_rules:%s#enemy damage" % rules))
		damage = maxi(0, int(c.vars.get("incoming", damage)))
	return damage


## Damage to the player from the creature. `armor`: "normal", "no shield"
## (pinned: the shield can't help), "no armor" or "area" (armor counts half).
static func strike(game, damage: int, armor: String = "normal", say: bool = true) -> void:
	if FightControlSystem.take_cancelled_blow(game):
		return  # the attack text said `~ cancel blow`
	var result := ItemSystem.absorb(game, damage, 100, armor != "no shield")
	var taken := int(result.taken)
	if armor == "no armor":
		taken = damage
	elif armor == "area":
		taken = damage - (int(result.prevented) + 1) / 2
	game.state.combat.vars["damage"] = damage
	game.set_value("player.hp", int(game.value("player.hp")) - taken)
	if say:
		game.notice("You take %d damage!" % damage, false)
	if damage - taken > 0:
		game.notice("You prevent %d damage!" % (damage - taken), false)
	if int(game.value("player.hp")) <= 0 and game.state.combat.result == "":
		game.state.combat.result = "lost"


## Alt Combat.i7x, firebreath rule: the creature draws breath (a growing
## chance), then next turn breathes for +75% (direct) or +11% (partial)
## damage, which armor halves, on an opposed roll; otherwise it fights normally.
static func _firebreath(game, id: String) -> void:
	var v: Dictionary = game.state.combat.vars
	if v.get("breath_ready", false):
		v["breath_ready"] = false
		v["breath_count"] = 0
		var player: int = game.rng.range_int(1, maxi(1, 10 + int(game.value("player.dexterity")) + int(game.value("player.level")) + ItemSystem.bonus(game, "dodge bonus")))
		var enemy: int = game.rng.range_int(1, maxi(1, 10 + stat(game, id, "perception") + number(game, id, "level", 1) + number(game, id, "hit bonus", 0)))
		game.emit({"type": "roll", "text": "Breath: %d vs %d" % [player, enemy]})
		var damage := 0
		if player * 2 < enemy:
			damage = number(game, id, "damage", 3) * spread(game, id) / 57
			v["damage"] = damage
			_text(game, id, "breath direct", "Your enemy unleashes a blast of fire at you. The flames wash over you, burning you badly. You take %d damage!" % damage)
		elif player < enemy:
			damage = number(game, id, "damage", 3) * spread(game, id) / 90
			v["damage"] = damage
			_text(game, id, "breath partial", "Your enemy unleashes a blast of fire at you. You try to evade, but are still partially caught in the flames, taking %d damage!" % damage)
		else:
			_text(game, id, "breath miss", "Your enemy unleashes a blast of fire at you. The flames come close, but you manage to get out of the way barely in time!")
		if damage > 0:
			strike(game, damage, "area", false)
		return
	if game.rng.chance(int(v.get("breath_count", 0)), 100):
		_text(game, id, "breath warning", "Your opponent takes a deep breath and its insides rumble distressingly as it continues its assault.")
		v["breath_ready"] = true
	elif int(v.get("breath_count", 0)) == 0:
		v["breath_count"] = 20
	else:
		v["breath_count"] = mini(40, int(v.breath_count) + game.rng.range_int(2, 6))
	_standard_turn(game, id)


## The first of the creature's `attacks:` whose condition holds, or -1.
static func _pick_attack(game, id: String) -> int:
	var menu: Dictionary = game.content.menus.get(id + ".attacks", {})
	var options: Array = menu.get("options", [])
	for i in options.size():
		var text := str(options[i].get("condition", ""))
		if text == "" or Condition.evaluate(Condition.compile(text), game):
			return i
	return -1


static func _special_chance(game, id: String, name: String) -> int:
	for part in game.creature_field(id, "special").split(","):
		var words: PackedStringArray = part.strip_edges().split(" ", false)
		if words.size() >= 1 and words[0] == name:
			return int(words[1].trim_suffix("%")) if words.size() > 1 else 100
	return 0


static func _has_special(game, id: String, name: String) -> bool:
	return _special_chance(game, id, name) > 0


## The words after a special's chance ("grapple 20% with strength ignoring armor"
## gives "with strength ignoring armor"), "" when it has none.
static func _special_options(game, id: String, name: String) -> String:
	for part in game.creature_field(id, "special").split(","):
		var words: PackedStringArray = part.strip_edges().split(" ", false)
		if words.size() >= 1 and words[0] == name:
			return " ".join(words.slice(2))
	return ""


## The attribute a hold is broken with (`grapple N% with strength`; dexterity by
## default), rolled with level on both sides, and whether its squeeze ignores armor.
static func hold_attribute(game, id: String) -> String:
	var m := RegEx.create_from_string("\\bwith (\\w+)").search(_special_options(game, id, "grapple"))
	return m.get_string(1) if m != null else "dexterity"


static func _hold_armor(game, id: String) -> String:
	return "no armor" if "ignoring armor" in _special_options(game, id, "grapple") else "normal"


## Plays one of the creature's combat scripts, if it has it.
static func _script(game, id: String, field: String) -> void:
	_play(game, CreatureChangeSystem.combat_script(game, id, field))  # its own, or one put in its place in play


## Runs a combat script in order: each paragraph is shown as it is reached and
## its effects report as usual (`quietly` keeps them silent), so "~ enemy strike"
## before a line lets the line say [fight.damage].
static func _play(game, prog: Program, depth: int = 0) -> void:
	if prog == null or depth > 8:
		return
	var pc := 0
	var steps := 0
	while pc < prog.code.size() and steps < 10000:
		steps += 1
		var ins: Dictionary = prog.code[pc]
		pc += 1
		match ins.op:
			"text":
				if not ins.text.has("error"):
					game.emit({"type": "paragraph", "spans": game.render(ins.text)})
			"jump":
				pc = ins.to
			"unless":
				if ins.cond.has("error") or not Condition.evaluate(ins.cond, game):
					pc = ins.to
			"effect":
				if not ins.effect.has("error"):
					game.apply(ins.effect)
			"goto":
				_play(game, game.content.program(ins.target), depth + 1)
				return
			"play":
				var times: int = Effect.resolve_amount(ins.times, game) if ins.has("times") else 1
				for i in times:
					if ins.has("times"):
						game.play_loops.append([i + 1, times])
					_play(game, game.content.program(ins.target), depth + 1)
					if ins.has("times"):
						game.play_loops.pop_back()
			"return":
				return


## Runs the hooks for a moment that happens inside a fight, in order.
static func hooks(game, moment: String) -> void:
	for hid: String in game.content.all_of("hook"):
		if game.content.typed_value("hook", hid, "on") != moment:
			continue
		var when: String = game.content.typed_value("hook", hid, "when")
		if when != "" and not Condition.evaluate(Condition.compile(when), game):
			continue
		_play(game, game.content.program("%s#do" % hid, "hook"))


## A creature's text for a special, or the original's general line.
static func _text(game, id: String, field: String, fallback: String) -> void:
	if game.content.program("%s#%s" % [id, field], "creature") != null:
		_script(game, id, field)
	else:
		game.notice(fallback, false)


## After the creature's turn (Alt Combat.i7x, retaliate): the player loses at
## 0 HP, or by lust when the value playing arousal reaches its in-fight top
## (`up to N in fights` in its declaration); a creature brought to 0 HP by a script loses.
static func _check_end(game) -> bool:
	var c: Dictionary = game.state.combat
	if c.result != "":
		return true
	if int(game.value("player.hp")) <= 0:
		c.result = "lost"
	elif _aroused_out(game):
		c.result = "lost by lust"
	elif int(c.hp) <= 0:
		c.result = "won"
	return c.result != ""


static func _grapple_damage(game) -> void:
	var id: String = game.state.combat.creature
	var damage: int = number(game, id, "damage", 3) * spread(game, id) / 125
	strike(game, damage, _hold_armor(game, id))


## Struggling in a hold: the player's attribute and level against the creature's
## (Alt Combat.i7x latexhug and bearhug rules: dexterity to slip free, strength to
## break a bear hug).
static func _grapple(game) -> void:
	var c: Dictionary = game.state.combat
	var attribute := hold_attribute(game, c.creature)
	var dex := int(game.value("player." + attribute)) + int(game.value("player.level"))
	var enemy := stat(game, c.creature, attribute) + number(game, c.creature, "level", 1)
	if game.rng.range_int(0, dex) > game.rng.range_int(1, enemy):
		c.grappled = false
		_grapple_text(game, c.creature, "escape", "You slip free.")
	else:
		_grapple_text(game, c.creature, "struggle", "You struggle but can't get free, and the effort weakens you.")
		_grapple_damage(game)


## A creature's escape or struggle text, or a plain line when it has none.
static func _grapple_text(game, id: String, field: String, fallback: String) -> void:
	var prog: Program = game.content.program("%s#%s" % [id, field], "creature")
	if prog == null:
		game.notice(fallback, false)
		return
	game.notice(game.runner.render_inline(prog), false)


## The value playing arousal has reached its in-fight top.
static func _aroused_out(game) -> bool:
	var path: String = game.role("arousal")
	if path == "" or not game.content.values[path].has("fight_max"):
		return false
	return game.role_number("arousal") >= int(game.content.values[path].fight_max)


static func aftermath(game, id: String, result: String) -> void:
	var level := number(game, id, "level", 1)
	if result.begins_with("won"):
		game.set_value("player.xp", int(game.value("player.xp")) + level * 2)
		# A creature with trophies offers them instead (SceneRunner, after the fight).
		if game.creature_field(id, "trophies") == "":
			drop_loot(game, id)
	elif result.begins_with("lost"):
		# Alt Combat.i7x:1448-1489: one infection with the creature's form, or
		# its cross infection unless that is banned; none for non-infectious ones.
		# A scene of this fight may name another creature to infect as (the
		# original's setmonster in a loss scene).
		id = str(game.state.combat.get("infects_as", id))
		# "this fight does not infect" names no creature.
		var infectious: bool = id != "" and game.creature_field(id, "infectious", "yes") != "no"
		var form: String = game.creature_field(id, "form")
		var cross: String = game.creature_field(id, "cross infection")
		if cross != "" and game.filter_block(CreatureChangeSystem.form_tags(game, cross), true) == "":
			form = cross
		if infectious and form != "":
			game.state.values["infection.bypass"] = game.creature_field(id, "research bypass", "no") == "yes"
			BodySystem.infect(game, form)
		game.set_value("player.hp", maxi(1, int(game.value("player.hp"))))
		game.set_value("player.xp", int(game.value("player.xp")) + level / 2)
		# For the rules' `lost:` script: whether this loss infected, and the libido of
		# the creature it infected as.
		game.state.combat.vars["infected"] = 1 if infectious else 0
		game.state.combat.vars["infection_libido"] = int(game.creature_field(id, "libido", "0"))
	# The game's own words and rewards after a fight (combat_rules `won:` / `lost:`,
	# such as a money reward).
	var rules := rules_id(game)
	if rules != "":
		var outcome := "won" if result.begins_with("won") else "lost" if result.begins_with("lost") else ""
		if outcome != "":
			_play(game, game.content.program("combat_rules:%s#%s" % [rules, outcome]))
	CompanionSystem.after_fight(game, id, result.begins_with("won"))


## The combat rules in use (one `== combat_rules` per game), or "".
## What the player fights with, for the rules' scripts: `fight.unarmed`,
## `fight.weapon_id` and `fight.weapon_type` (melee or ranged).
static func _weapon_values(game) -> void:
	var c: Dictionary = game.state.combat
	var w := ItemSystem.weapon(game)
	c.vars["unarmed"] = str(w.id) == ""
	c.vars["weapon_id"] = str(w.id)
	c.vars["weapon_type"] = str(w.type)


## The damage of the creature that infects with `form` (0 for none or human):
## natural weapons borrowed from a strain.
static func strain_damage(game, form: String) -> int:
	if form in ["", "human"]:
		return 0
	if game.content.has(form, "creature") and game.content.typed_value("creature", form, "form", form) == form:
		return number(game, form, "damage", 0)
	var ids: Array = game.content.all_of("creature").keys()
	ids.sort()
	for id in ids:
		if game.content.typed_value("creature", id, "form", id) == form:
			return number(game, id, "damage", 0)
	return 0


static func rules_id(game) -> String:
	var defs: Dictionary = game.content.all_of("combat_rules")
	return "" if defs.is_empty() else str(defs.keys()[0])


## Whether a combat rules condition holds (false without the field or the rules).
static func holds(game, field: String) -> bool:
	var text := rule(game, field, "")
	return text != "" and Condition.evaluate(Condition.compile(text), game)


## The highest creature level met at random, or -1 for no limit (`level limit`,
## lifted while `level limit off when` holds).
static func level_limit(game) -> int:
	var text := rule(game, "level limit", "")
	if text == "" or holds(game, "level limit off when"):
		return -1
	var e := Expr.parse(text)
	return -1 if e.has("error") else int(Expr._num(Expr.evaluate(e, game)))


static func rule(game, field: String, fallback: String) -> String:
	var id := rules_id(game)
	return fallback if id == "" else game.content.typed_value("combat_rules", id, field, fallback)


## A combat rules line rendered as plain text (the game's words for hits and fleeing).
static func rule_text(game, field: String, fallback: String) -> String:
	var t := TextTemplate.compile(rule(game, field, fallback))
	if t.has("error"):
		t = TextTemplate.compile(fallback)
	return TextTemplate.plain(game.render(t))


## Alt Combat.i7x:1544-1549: the creature's `loot` drops by its chance plus the
## loot bonus: the feats' `loot bonus` (Magpie Eyes, Mugger) and up to +10 from
## perception (RefreshLootBonus).
static func drop_loot(game, id: String) -> void:
	var loot: PackedStringArray = game.creature_field(id, "loot").split(" ", false)
	if loot.size() != 2 or loot[0] == "none" or not game.content.has(loot[0], "item"):
		return
	var chance := int(loot[1].trim_suffix("%"))
	if chance <= 0:
		return
	if chance > 99 or game.rng.chance(chance + loot_bonus(game), 100):
		game.apply(Effect.compile("give " + loot[0]))


## The loot bonus: the feats' `loot bonus` (Magpie Eyes, Mugger) and up to +10
## from perception (the original's RefreshLootBonus).
static func loot_bonus(game) -> int:
	return game.feat_bonus("loot bonus") + mini(10, (int(game.value("player.perception")) - 10) / 2)


## The creature's `trophies:` ("wolf_fur 80%, food 25%"): each item rolls its chance
## plus the loot bonus, and the ones that come up are offered after a win, the
## player taking one (Alt Combat.i7x:1501-1550, TrophyLootFunction). An entry
## with "if <condition>" ("police_whistle 100% if alexandra does not have trait
## whistle_taken") is offered only while the condition holds.
## The condition of one `trophies:` entry ("" for none).
static func trophy_condition(entry: String) -> String:
	var at := entry.find(" if ")
	return entry.substr(at + 4).strip_edges() if at >= 0 else ""


static func roll_trophies(game, id: String) -> Array:
	var out: Array = []
	for entry in game.creature_field(id, "trophies").split(",", false):
		var cond := trophy_condition(entry)
		if cond != "" and not Condition.evaluate(Condition.compile(cond), game):
			continue
		var parts: PackedStringArray = entry.split(" if ", true, 1)[0].strip_edges().split(" ", false)
		if parts.size() != 2 or not game.content.has(parts[0], "item") or parts[0] in out:
			continue
		var chance := int(parts[1].trim_suffix("%"))
		if chance > 99 or (chance > 0 and game.rng.chance(chance + loot_bonus(game), 100)):
			out.append(parts[0])
	return out
