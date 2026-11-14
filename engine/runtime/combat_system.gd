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
const ENEMY_NUMBERS := ["damage", "level", "hit_bonus", "dodge_bonus", "strength", "dexterity", "stamina",
	"perception", "intelligence", "charisma"]
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
	# Fighting.i7x:73-88: an alert, agile creature can strike first.
	var surprise: int = (int(game.value("player.perception")) - 10) / 2 - (stat(game, id, "dexterity") - 10) / 2
	if surprise + game.rng.range_int(1, 20) < 6:
		game.notice("The creature gets the drop on you!", false)
		_retaliate(game)
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
		"text": "Round %d" % int(c.round)})


## `penalty` is subtracted after capping, as the weapon size penalty is.
static func _roll(game, label: String, bonus: int, enemy: bool = false, flee: bool = false, penalty: int = 0) -> bool:
	var hard: bool = "hard" in game.settings.mode
	var lower := -22 if hard == enemy else -25
	var upper := 19 if hard == enemy else 16
	bonus = maxi(lower, bonus) if flee else clampi(bonus, lower, upper)
	bonus -= penalty
	var roll: int = game.rng.range_int(1, 50)
	game.emit({"type": "roll", "text": "%s: 1d50(%d) %+d = %d vs >20" % [label, roll, bonus, roll + bonus]})
	return roll + bonus > 20


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
		var dex := int(game.value("player.dexterity"))
		var enemy_dex := stat(game, id, "dexterity")
		match action:
			"submit", "throw":
				c.result = "lost by submitting" if action == "submit" else "lost"
			"attack":
				var w := ItemSystem.weapon(game)
				# Alt Combat.i7x:342: the creature's dodge bonus (mondodgebonus) adds to its defense.
				if _roll(game, "Attack", dex + level * 2 + int(w.hit) - enemy_dex - enemy_level * 2 - number(game, id, "dodge bonus", 0), false, false, int(w.penalty)):
					var damage: int = int(w.damage) * game.rng.range_int(80, 120 + level) / 100
					var stat := "perception" if w.type == "ranged" else "strength"
					damage += (int(game.value("player." + stat)) - 10) / 2 + ItemSystem.bonus(game, "damage bonus")
					var motivated: bool = game.rng.chance(int(game.value("player.morale")), 200)
					if motivated:
						damage *= 2
					c.hp = int(c.hp) - maxi(0, damage)
					c.penalty = int(c.penalty) + 20
					var verb: String = ["strike with", "attack with", "use", "abuse with"][game.variation("combat.attack_verb", 4, "at random")]
					var weapon_text: String = TextTemplate.plain(game.render(TextTemplate.compile(str(w.text), "weapon:" + str(w.id))))
					var name: String = game.creature_field(id, "name", id).to_lower()
					game.notice("%sYou %s %s, hitting the %s for %d damage!" % ["Filled with sudden motivation, your attack scores particularly well! " if motivated else "",
						verb, weapon_text, name, damage], false)
					if int(c.hp) <= 0:
						c.result = "won"
			"seduce":
				var immune: bool = game.creature_field(id, "seduction immune", "no") == "yes"
				var defense := 20 - int(c.libido) / 3 + enemy_level * 2
				var hit := _roll(game, "Seduce", int(game.value("player.perception")) + level * 2 - defense - int(c.penalty))
				if hit and not immune:
					var gain: int = (int(game.value("player.charisma")) / 3) * game.rng.range_int(70, 130) / 100
					if game.rng.chance(int(game.value("player.morale")), 200):
						gain *= 2
					c.libido = int(c.libido) + gain
					game.notice("Enemy lust +%d." % gain, false)
					if int(c.libido) - int(c.penalty) >= 100:
						c.result = "won by seduction"
				elif immune:
					game.notice("This creature is immune to seduction.", false)
			"flee":
				# Alt Combat.i7x:807: the creature's hit bonus also works against fleeing.
				var bonus := dex + int(game.value("player.intelligence")) + level * 2 + ItemSystem.bonus(game, "flee bonus") - enemy_dex - enemy_level * 2 - 10 - number(game, id, "hit bonus", 0)
				if _roll(game, "Flee", bonus, false, true):
					c.result = "fled"
					var name: String = game.creature_field(id, "name", id).to_lower()
					game.notice("You manage to evade the %s and slip back into the city." % name, false)
				else:
					game.notice("You fail to get away.", false)
			"pass":
				pass
			_:
				return false
		if c.result == "":
			_retaliate(game)
	c.round = int(c.round) + 1
	if c.result == "":
		show(game)
	return true


## After an item was used in a fight, the enemy gets its turn
## (Alt Combat.i7x:739-759): the item use spent the player's round.
static func after_item(game) -> void:
	var c: Dictionary = game.state.combat
	if c.is_empty() or c.result != "":
		return
	if int(game.value("player.hp")) <= 0:
		c.result = "lost"
		return
	_retaliate(game)
	c.round = int(c.round) + 1


## The creature's turn (Alt Combat.i7x, retaliate and the Table of Critter
## Combat): its `each round` script, then one of its `attacks` whose condition
## holds (that option is the whole turn), else a built-in special, else the
## standard attack: `before attack`, the hit roll (`strike with` names another
## attribute, as the original's altstrike), the attack or `miss`, `after attack`.
static func _retaliate(game) -> void:
	var c: Dictionary = game.state.combat
	var id: String = c.creature
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
		if game.content.program(id + "#miss") != null:
			_script(game, id, "miss")
		else:
			game.notice("The enemy misses.", false)
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
		var damage: int = number(game, id, "damage", 3) * (game.rng.range_int(80, 120) + 30 + 2 * level) / 100
		_text(game, id, "hump", "You are grabbed by your opponent, who grinds against your body. The scent momentarily entices your infected body, and your drive to keep resisting wanes. You take %d damage!" % damage)
		var lust: int = game.rng.range_int(2, 6) + (1 if "horny_bastard" in game.state.feats else 0) - (1 if "cold_fish" in game.state.feats else 0)
		game.set_value("player.libido", int(game.value("player.libido")) + lust)
		strike(game, damage, "normal", false)
		return
	# Alt Combat.i7x, ftaurpounce rule: double damage, no shield.
	var pounce := _special_chance(game, id, "pounce")
	if pounce > 0 and game.rng.chance(pounce, 100):
		var damage: int = number(game, id, "damage", 3) * game.rng.range_int(80, 120) / 50
		_text(game, id, "pounce", "Your opponent pounces atop you, knocking you down and clawing at you before you push it away.")
		strike(game, damage, "no shield")
		return
	_script(game, id, "attack")
	strike(game, roll_damage(game, id, 100))


## The creature's to-hit roll: its attribute and level against the player's
## (dexterity: dodging; any other: the original's intstrike, against the same
## attribute of the player).
static func hit_roll(game, attribute: String = "dexterity") -> bool:
	var id: String = game.state.combat.creature
	var bonus: int
	if attribute == "dexterity":
		# Alt Combat.i7x:984: the creature's hit bonus (monhitbonus) adds to its attack.
		bonus = stat(game, id, "dexterity") + number(game, id, "level", 1) * 2 + number(game, id, "hit bonus", 0)
		bonus -= int(game.value("player.dexterity")) + int(game.value("player.level")) * 2 + ItemSystem.bonus(game, "dodge bonus")
	else:
		bonus = stat(game, id, attribute) + number(game, id, "level", 1) * 2 - 10
		bonus -= int(game.value("player." + attribute)) + int(game.value("player.level")) * 2 - 10
	return _roll(game, "Enemy attack", bonus, true)


## The creature's damage for one blow: its damage x 80-120%, scaled by `percent`,
## with the Hard mode critical hit.
static func roll_damage(game, id: String, percent: int) -> int:
	var damage: int = number(game, id, "damage", 3) * game.rng.range_int(80, 120) / 100 * percent / 100
	if "hard" in game.settings.mode and game.rng.chance(1, 10):
		damage = damage * 150 / 100
	return damage


## Damage to the player from the creature. `armor`: "normal", "no shield"
## (pinned: the shield can't help), "no armor" or "area" (armor counts half).
static func strike(game, damage: int, armor: String = "normal", say: bool = true) -> void:
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
			damage = number(game, id, "damage", 3) * game.rng.range_int(80, 120) / 57
			v["damage"] = damage
			_text(game, id, "breath direct", "Your enemy unleashes a blast of fire at you. The flames wash over you, burning you badly. You take %d damage!" % damage)
		elif player < enemy:
			damage = number(game, id, "damage", 3) * game.rng.range_int(80, 120) / 90
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


## Plays one of the creature's combat scripts, if it has it.
static func _script(game, id: String, field: String) -> void:
	_play(game, game.content.program("%s#%s" % [id, field], "creature"))


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
			"return":
				return


## A creature's text for a special, or the original's general line.
static func _text(game, id: String, field: String, fallback: String) -> void:
	if game.content.program("%s#%s" % [id, field], "creature") != null:
		_script(game, id, field)
	else:
		game.notice(fallback, false)


## After the creature's turn (Alt Combat.i7x, retaliate): the player loses at
## 0 HP or at libido 110 and above; a creature brought to 0 HP by a script loses.
static func _check_end(game) -> bool:
	var c: Dictionary = game.state.combat
	if c.result != "":
		return true
	if int(game.value("player.hp")) <= 0:
		c.result = "lost"
	elif int(game.value("player.libido")) >= 110:
		c.result = "lost by lust"
	elif int(c.hp) <= 0:
		c.result = "won"
	return c.result != ""


static func _grapple_damage(game) -> void:
	var id: String = game.state.combat.creature
	var damage: int = number(game, id, "damage", 3) * game.rng.range_int(80, 120) / 125
	strike(game, damage)


static func _grapple(game) -> void:
	var c: Dictionary = game.state.combat
	var dex := int(game.value("player.dexterity")) + int(game.value("player.level"))
	var enemy := stat(game, c.creature, "dexterity") + number(game, c.creature, "level", 1)
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


static func aftermath(game, id: String, result: String) -> void:
	var level := number(game, id, "level", 1)
	if result.begins_with("won"):
		game.set_value("player.xp", int(game.value("player.xp")) + level * 2)
		game.set_value("player.morale", int(game.value("player.morale")) + 1)
		var reward := level * 2
		if level > 2:
			reward += 1
		if level > 4:
			reward += level / 4
		if level > 8:
			reward += level / 3
		reward = mini(50, reward)
		game.set_value("player.freecred", int(game.value("player.freecred")) + reward)
		game.notice("A soft chime informs you that you have received %d freecred, and now have %d creds." % [reward, int(game.value("player.freecred"))], false)
		if int(game.value("player.libido")) > 25:
			game.set_value("player.libido", int(game.value("player.libido")) - 4)
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
		if cross != "" and game.filter_block(game.content.form_tags(cross), true) == "":
			form = cross
		if infectious and form != "":
			BodySystem.infect(game, form)
		game.set_value("player.hp", maxi(1, int(game.value("player.hp"))))
		game.set_value("player.xp", int(game.value("player.xp")) + level / 2)
		game.set_value("player.score", int(game.value("player.score")) - 1)
		game.set_value("player.morale", int(game.value("player.morale")) - 3)
		var creature_libido := int(game.creature_field(id, "libido", "0"))
		var rise := 4 if infectious and int(game.value("player.libido")) < creature_libido else 1
		game.set_value("player.libido", int(game.value("player.libido")) + rise)


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
	var bonus: int = game.feat_bonus("loot bonus") + mini(10, (int(game.value("player.perception")) - 10) / 2)
	if chance > 99 or game.rng.chance(chance + bonus, 100):
		game.apply(Effect.compile("give " + loot[0]))
