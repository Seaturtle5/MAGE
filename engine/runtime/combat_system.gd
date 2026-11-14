class_name CombatSystem
extends RefCounted
## The player's side of combat: weapons, worn gear bonuses and armor.
## Formula sources: Core Mechanics/Alt Combat.i7x:119-141, 334-640, 786-847,
## 974-1083, 1404-1488 and 1923-1950 at baseline 6d4920e. Feat effects
## (Weaponsmaster, Martial Artist ...) come with the feats package.

static func number(game, id: String, field: String, default: int) -> int:
	return int(game.content.typed_value("creature", id, field, str(default)))


static func stat(game, id: String, key: String) -> int:
	for entry in game.content.typed_value("creature", id, "stats").split(","):
		var parts: PackedStringArray = entry.strip_edges().split(" ", false)
		if parts.size() == 2 and parts[0] == key:
			return int(parts[1])
	return 12


static func begin(game, id: String) -> void:
	if id not in game.state.encountered:
		game.state.encountered.append(id)
	game.state.combat = {"creature": id, "hp": number(game, id, "hp", 12),
		"maxhp": number(game, id, "hp", 12), "libido": number(game, id, "libido", 0),
		"penalty": 0, "round": 1, "grappled": false, "result": ""}
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
		"name": game.content.typed_value("creature", c.creature, "name", c.creature),
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
					var name: String = game.content.typed_value("creature", id, "name", id).to_lower()
					game.notice("%sYou %s %s, hitting the %s for %d damage!" % ["Filled with sudden motivation, your attack scores particularly well! " if motivated else "",
						verb, weapon_text, name, damage], false)
					if int(c.hp) <= 0:
						c.result = "won"
			"seduce":
				var immune: bool = game.content.typed_value("creature", id, "seduction immune", "no") == "yes"
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
					var name: String = game.content.typed_value("creature", id, "name", id).to_lower()
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


static func _retaliate(game) -> void:
	var c: Dictionary = game.state.combat
	var id: String = c.creature
	# Alt Combat.i7x:984: the creature's hit bonus (monhitbonus) adds to its attack.
	var bonus := stat(game, id, "dexterity") + number(game, id, "level", 1) * 2 + number(game, id, "hit bonus", 0)
	bonus -= int(game.value("player.dexterity")) + int(game.value("player.level")) * 2 + ItemSystem.bonus(game, "dodge bonus")
	if not _roll(game, "Enemy attack", bonus, true):
		game.notice("The enemy misses.", false)
		return
	var special: String = game.content.typed_value("creature", id, "special")
	if special.begins_with("grapple ") and game.rng.chance(int(special.get_slice(" ", 1).trim_suffix("%")), 100):
		c.grappled = true
		for spans in game.runner.render_paragraphs(game.content.program(id + "#grapple"), 0, true):
			game.emit({"type": "paragraph", "spans": spans})
		_grapple_damage(game)
		return
	for spans in game.runner.render_paragraphs(game.content.program(id + "#attack"), 0, true):
		game.emit({"type": "paragraph", "spans": spans})
	var damage: int = number(game, id, "damage", 3) * game.rng.range_int(80, 120) / 100
	if "hard" in game.settings.mode and game.rng.chance(1, 10):
		damage = damage * 150 / 100
	_hurt(game, damage)


static func _grapple_damage(game) -> void:
	var id: String = game.state.combat.creature
	var damage: int = number(game, id, "damage", 3) * game.rng.range_int(80, 120) / 125
	_hurt(game, damage)


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


static func _hurt(game, damage: int) -> void:
	# Natural armor is 100; worn armor adds to it (normal absorbancy).
	var result := ItemSystem.absorb(game, damage)
	game.set_value("player.hp", int(game.value("player.hp")) - int(result.taken))
	game.notice("You take %d damage!" % damage, false)
	if int(result.prevented) > 0:
		game.notice("You prevent %d damage!" % int(result.prevented), false)
	if int(game.value("player.hp")) <= 0:
		game.state.combat.result = "lost"


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
	elif result.begins_with("lost"):
		# Alt Combat.i7x:1448-1489: one infection with the creature's form, or
		# its cross infection unless that is banned; none for non-infectious ones.
		# A scene of this fight may name another creature to infect as (the
		# original's setmonster in a loss scene).
		id = str(game.state.combat.get("infects_as", id))
		# "this fight does not infect" names no creature.
		var infectious: bool = id != "" and game.creature_field(id, "infectious", "yes") != "no"
		var form: String = game.content.typed_value("creature", id, "form")
		var cross: String = game.content.typed_value("creature", id, "cross infection")
		if cross != "" and game.filter_block(game.content.form_tags(cross), true) == "":
			form = cross
		if infectious and form != "":
			BodySystem.infect(game, form)
		game.set_value("player.hp", maxi(1, int(game.value("player.hp"))))
		game.set_value("player.xp", int(game.value("player.xp")) + level / 2)
		game.set_value("player.score", int(game.value("player.score")) - 1)
		game.set_value("player.morale", int(game.value("player.morale")) - 3)
		var creature_libido := int(game.content.typed_value("creature", id, "libido", "0"))
		var rise := 4 if infectious and int(game.value("player.libido")) < creature_libido else 1
		game.set_value("player.libido", int(game.value("player.libido")) + rise)
