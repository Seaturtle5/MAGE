extends GutTest
## The combat rules' hook points for the player's extras: `fight starts`,
## `player damage`, `avoid` and `enemy damage`, with `fight.unarmed`,
## `fight.weapon_id`, `fight.dodge_now`, `fight.no_surprise`, `enemy.form` and
## `player.<part>.strain_damage`.

const ROOT := "user://combat_extras_test_packs"

const PACK := """== location arena
name: Arena
description: Sand and old blood.

== form lizard
name: Lizard
tail:
    description: a scaly tail
    change: a scaly tail grows
torso:
    description: scaly
    change: you grow scales

== creature lizard
name: Lizard
hp: 500
level: 1
damage: 10
stats: strength 10, dexterity 60, stamina 10, perception 10, intelligence 10, charisma 10
form: lizard

== creature sloth
name: Sloth
hp: 500
level: 1
damage: 10
stats: strength 10, dexterity 1, stamina 10, perception 10, intelligence 10, charisma 10

== item stick
name: stick
description: A stick.
category: weapon
weapon:
    damage: 3
    type: melee

== combat_rules basic
fight starts:
    if player torso is lizard and player.body.torso = enemy.form:
        ~ fight.hit_bonus + 50 quietly
        Know your own kind.
    if player has feat watchful:
        ~ fight.no_surprise = yes quietly
player damage:
    if fight.unarmed:
        ~ fight.damage = 100 quietly
    else if fight.weapon_id = "stick":
        ~ fight.damage = 40 quietly
avoid:
    if player has feat slippery:
        You slip away.
        ~ fight.avoided = yes quietly
    if player has feat shiny:
        ~ fight.dodge_now + 500 quietly
enemy damage:
    if player has feat stone_skin:
        ~ fight.incoming = 0 quietly

== feat watchful
name: Watchful

== feat slippery
name: Slippery

== feat shiny
name: Shiny

== feat stone_skin
name: Stone Skin
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "c.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 5)
	game.start("arena")
	game.set_value("player.maxhp", 100000)
	game.set_value("player.hp", 100000)
	game.set_value("player.dexterity", 10)
	game.set_value("player.strength", 10)
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type in ["paragraph", "notice"]:
			out.append(TextTemplate.plain(e.spans) if e.type == "paragraph" else str(e.text))
	return "\n".join(out)


func test_player_damage_reads_the_weapon() -> void:
	CombatSystem.begin(game, "sloth")
	var hp0 := int(game.state.combat.hp)
	var hit := false
	for _i in 20:
		CombatSystem.player_attack(game)
		if int(game.state.combat.hp) < hp0:
			hit = true
			break
	assert_true(hit)
	# 100 from the rules, plus (strength - 10) / 2 = 0.
	assert_eq(hp0 - int(game.state.combat.hp), 100, "unarmed: the rules set the damage")
	game.apply(Effect.compile("give stick"))
	game.apply(Effect.compile("wield stick"))
	CombatSystem.begin(game, "sloth")
	hp0 = int(game.state.combat.hp)
	for _i in 20:
		CombatSystem.player_attack(game)
		if int(game.state.combat.hp) < hp0:
			break
	assert_eq(hp0 - int(game.state.combat.hp), 40, "armed with the stick: fight.weapon_id")
	assert_eq(game.value("fight.weapon_id"), "stick")
	assert_false(Condition._truthy(game.value("fight.unarmed")))


func test_avoid_escapes_every_blow() -> void:
	game.apply(Effect.compile("feat + slippery"))
	CombatSystem.begin(game, "lizard")
	var hp0 := int(game.value("player.hp"))
	for _i in 10:
		CombatSystem._retaliate(game)
	assert_eq(int(game.value("player.hp")), hp0, "every blow is avoided")
	assert_string_contains(_text(), "You slip away.")


func _hits(rounds: int) -> int:
	var hits := 0
	CombatSystem.begin(game, "lizard")
	for _i in rounds:
		var hp0 := int(game.value("player.hp"))
		CombatSystem._retaliate(game)
		if int(game.value("player.hp")) < hp0:
			hits += 1
	return hits


func test_dodge_now_helps_one_roll_at_a_time() -> void:
	var without := _hits(60)
	game.apply(Effect.compile("feat + shiny"))
	var with_bonus := _hits(60)
	assert_lt(with_bonus, without, "the one-roll dodge makes blows land less often (capped like any bonus)")
	assert_eq(CombatSystem.bonus_of(game, "dodge_now"), 0, "cleared after the roll")


func test_enemy_damage_can_be_changed() -> void:
	game.apply(Effect.compile("feat + stone_skin"))
	CombatSystem.begin(game, "lizard")
	var hp0 := int(game.value("player.hp"))
	for _i in 10:
		CombatSystem._retaliate(game)
	assert_eq(int(game.value("player.hp")), hp0, "every blow's damage is set to 0")


func test_no_built_in_critical_hit_without_rules() -> void:
	game.settings.mode.append("hard")
	var hits: Array = []
	for _i in 200:
		game.state.combat = {"creature": "sloth", "vars": {}, "overrides": {}}
		hits.append(CombatSystem.roll_damage(game, "sloth", 100))
	assert_true(hits.max() <= 12, "no critical hit from the engine itself: " + str(hits.max()))


func test_fight_starts_and_strain_values() -> void:
	game.apply(Effect.compile("transform into lizard"))
	assert_eq(int(game.value("player.tail.strain_damage")), 10, "the lizard creature's damage")
	assert_eq(int(game.value("player.head.strain_damage")), 0, "a human part has none")
	game.apply(Effect.compile("feat + watchful"))
	CombatSystem.begin(game, "lizard")
	assert_eq(game.value("enemy.form"), "lizard")
	assert_eq(CombatSystem.bonus_of(game, "hit_bonus"), 50, "the strain comparison holds")
	assert_string_contains(_text(), "Know your own kind.")
	assert_false(_text().contains("gets the drop"), "no first strike")


func test_new_paths_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := "== scene s\nif player.wing.strain_damage > 1:\n    Hm.\nif enemy.colour = 1:\n    Hm.\n"
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	assert_string_contains(text, "is not a body part")
	assert_string_contains(text, "colour")
