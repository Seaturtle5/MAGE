extends GutTest
## The player's fight bonuses, the enemy's mind bonus and damage spread, the
## combat rules' `each round` and `before flee` scripts, the player's moves from
## a scene, scenes played from attack scripts, multi-word time slots, the
## capitalized enemy name, filters in tag conditions and content-declared player
## values.

const ROOT := "user://combat_modifier_test_packs"

const PACK := """== location arena
name: Arena
description: Sand and old blood.

== filter spooky
name: Spooky

== form ghost
name: Ghost
tags: spooky
skin:
    description: pale mist
    change: you turn to mist

== creature ghost
name: Ghost
hp: 200
level: 1
damage: 10
stats: strength 10, dexterity 10, stamina 10, perception 10, intelligence 30, charisma 10
form: ghost
tags: spooky
strike with: intelligence
mind bonus: 4

== creature hydra
name: Hydra
hp: 500
level: 1
damage: 10
stats: strength 10, dexterity 60, stamina 10, perception 10, intelligence 10, charisma 10
attacks:
    * Heads [if chance 1 in 1]
        ~ fight.volley = 0 quietly
        play hydra_head fight.heads times
        ~ enemy strike for fight.volley quietly

== scene hydra_head
if enemy hits:
    ~ fight.volley + 3 quietly

== values player
values:
    coins: number 0

== status_bar main
meters: hp
currency: coins
sheet: morale

== combat_rules basic
each round:
    if fight.poison > 0:
        ~ player.hp - fight.poison quietly
        ~ fight.poison - 1 quietly
        Poison burns.
before flee:
    ~ fight.flee_now + 100 quietly

== item spray
name: spray
description: A spray can.
category: weapon
consumed: no
in combat: yes
use:
    ~ enemy.hit_bonus - 5 quietly
    ~ attack enemy
    ~ attack enemy

== item smoke
name: smoke bomb
description: Smoke.
category: other
in combat: yes
use:
    ~ try to flee

== scene timed
if time is early night:
    Early night.
if time is not pre dawn:
    Not pre dawn.
[The enemy] stares. [Enemy name] waits.
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
	game = Game.new(db, 3)
	game.start("arena")
	game.set_value("player.maxhp", 100000)
	game.set_value("player.hp", 100000)
	game.set_value("player.perception", 60)
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type in ["paragraph", "notice"]:
			out.append(TextTemplate.plain(e.spans) if e.has("spans") else str(e.get("text", "")))
	return "\n".join(out)


func _fight(id: String) -> void:
	game.runner.start_encounter(id)
	game.take_output()


func test_time_slots_of_two_words_and_the_capitalized_enemy() -> void:
	while game.time_slot() != "early night":
		game.pass_turn()
	game.state.encountered.append("ghost")
	game.runner.start("timed")
	var text := _text()
	assert_string_contains(text, "Early night.")
	assert_string_contains(text, "Not pre dawn.")
	assert_string_contains(text, "The ghost stares. Ghost waits.")


func test_mind_bonuses_on_both_sides() -> void:
	_fight("ghost")
	game.set_value("player.intelligence", 10)
	var hits := 0
	for _i in 200:
		hits += 1 if CombatSystem.hit_roll(game, "intelligence") else 0
	game.set_value("fight.mind_bonus", 40)
	var guarded := 0
	for _i in 200:
		guarded += 1 if CombatSystem.hit_roll(game, "intelligence") else 0
	assert_true(hits > guarded + 40, "the player's mind bonus resists mental attacks (%d vs %d)" % [hits, guarded])
	game.set_value("enemy.mind_bonus", 60)
	var boosted := 0
	for _i in 200:
		boosted += 1 if CombatSystem.hit_roll(game, "intelligence") else 0
	assert_true(boosted > guarded + 40, "the enemy's mind bonus strengthens them (%d vs %d)" % [boosted, guarded])


func test_damage_spread_can_be_lowered() -> void:
	_fight("ghost")
	var low := 1000
	for _i in 200:
		low = mini(low, CombatSystem.roll_damage(game, "ghost", 100))
	assert_eq(low, 8, "80% of 10 at the lowest")
	assert_eq(int(game.value("enemy.damage_low")), 80, "the usual low end")
	game.apply(Effect.compile("enemy.damage_low - 60 quietly"))
	assert_eq(int(game.value("enemy.damage_low")), 20, "changed from the usual 80")
	low = 1000
	for _i in 200:
		low = mini(low, CombatSystem.roll_damage(game, "ghost", 100))
	assert_true(low < 5, "a lowered spread can roll far less")


func test_player_bonuses_change_the_rolls() -> void:
	_fight("ghost")
	game.set_value("player.dexterity", 10)
	var hits := func(n: int) -> int:
		var count := 0
		for _i in n:
			var before := int(game.value("enemy.hp"))
			CombatSystem.player_attack(game)
			count += 1 if int(game.value("enemy.hp")) < before else 0
			game.set_value("enemy.hp", 200)
		return count
	game.set_value("fight.hit_bonus", -200)
	var poor: int = hits.call(100)
	game.set_value("fight.hit_bonus", 0)
	var plain: int = hits.call(100)
	assert_true(poor < plain, "a hit penalty lowers the chance to hit (%d vs %d; the original caps it)" % [poor, plain])
	var hp: int = int(game.value("enemy.hp"))
	game.set_value("fight.hit_bonus", 200)
	game.set_value("fight.damage_bonus", 50)
	CombatSystem.player_attack(game)
	assert_true(int(game.value("enemy.hp")) <= hp - 50, "the damage bonus adds to the blow")


func test_each_round_and_before_flee_of_the_combat_rules() -> void:
	_fight("ghost")
	game.set_value("fight.poison", 3)
	var hp: int = int(game.value("player.hp"))
	game.runner.combat_action("pass")
	var text := _text()
	assert_string_contains(text, "Poison burns.")
	assert_eq(int(game.value("fight.poison")), 2)
	assert_true(int(game.value("player.hp")) <= hp - 3, "poison hurt before the enemy's turn")
	game.runner.combat_action("flee")
	assert_eq(str(game.last_fight), "fled", "before flee's one-time bonus makes the escape certain")


func test_moves_from_an_item_scene() -> void:
	game.state.inventory["spray"] = 1
	game.state.inventory["smoke"] = 1
	_fight("ghost")
	game.set_value("player.dexterity", 60)
	var hp: int = int(game.value("enemy.hp"))
	game.runner.combat_action("use spray")
	_text()
	assert_true(int(game.value("enemy.hp")) < hp, "the spray's scene attacked")
	assert_eq(int(game.value("enemy.hit_bonus")), -5, "the scene changed the enemy for this fight")
	game.set_value("player.dexterity", 200)
	game.runner.combat_action("use smoke")
	assert_eq(str(game.last_fight), "fled", "a scene can try to flee")


func test_attack_scripts_can_play_scenes_many_times() -> void:
	_fight("hydra")
	game.set_value("fight.heads", 4)
	var hp: int = int(game.value("player.hp"))
	game.runner.combat_action("pass")
	assert_true(int(game.value("player.hp")) < hp, "the heads bit")
	assert_true(int(game.value("fight.volley")) % 3 == 0 and int(game.value("fight.volley")) <= 12, "each head added its bite")


func test_values_the_game_declares_and_the_sheet() -> void:
	assert_eq(game.value("player.coins"), 0)
	game.set_value("player.coins", 7)
	var bar := game.status_bar()
	assert_eq(bar.currency, "coins")
	assert_eq(int(bar.money), 7)
	assert_eq(bar.sheet.map(func(v): return v.key), ["morale"])
	assert_false(Game.PLAYER_DEFAULTS.has("freecred"), "the engine names no game's money")


func test_tag_conditions_accept_filters_and_bad_times_are_caught() -> void:
	game.set_value("player.body.skin", "ghost")
	assert_true(Condition.evaluate(Condition.compile("player skin is tagged spooky"), game), "a filter carried by the form's creature")
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := """== scene s
if time is teatime:
    Tea.
if player skin is tagged nothing_like_this:
    No.
~ player.freecred + 5
== scene fight_scene
Nothing.
== scene bad_play
~ start event nowhere
== creature c
name: C
hp: 5
mind bonus: lots
attacks:
    * Odd
        play bad_play
"""
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	assert_string_contains(text, "Unknown time")
	assert_string_contains(text, "teatime")
	assert_string_contains(text, "nothing_like_this")
	assert_string_contains(text, "player.freecred")
	assert_string_contains(text, "Mind Bonus must be a whole number")
	assert_string_contains(text, "bad_play", "a fight's script may not play a scene that does more")
