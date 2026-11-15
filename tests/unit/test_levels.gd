extends GutTest
## The player's levels (level_rules), feats offered on a level, interests,
## and the game's own combat wording and rewards (combat_rules).

const ROOT := "user://level_test_packs"

const PACK := """== feat fast_learner
name: Fast Learner

== feat hardy
name: Hardy
description: More health.
group: basic
gained:
    ~ player.maxhp + 8 quietly

== feat lucky
name: Lucky
description: Things go your way.
group: fun

== feat unlucky
name: Unlucky
description: Things go wrong.
group: fun
available when: player does not have feat lucky

== feat hidden
name: Hidden
description: Never offered.
group: fun
available when: player.level > 99

== level_rules standard
xp needed: (player.level + 1) * 10
xp needed modifiers:
    player has feat fast_learner: - (player.level + 1) * 2
levels when: player.humanity > 0
level up:
    You reached level [player.level]!
    if player.level % 2 = 0:
        play pick_stat
    ~ player.maxhp + 2 quietly
    if player.level % 5 = 0:
        ~ choose feat fun

== scene pick_stat
Pick a stat.
* Strength
    ~ player.strength + 1
* Perception
    ~ player.perception + 1

== interest males
name: Males
default: yes

== interest females
name: Females
default: no

== combat_rules plain
unarmed attack: a wooden spoon
unarmed damage: 6
player hits: You whack [the enemy] with [fight.weapon] ([fight.dealt]).
flee: You run from [the enemy].
won:
    ~ player.coins + enemy.level quietly
    You find [enemy.level] coins.

== meter coins
name: Coins
value: player.coins

== status_bar bar
meters: coins
currency: coins
currency names: coin, coins

== item apple
name: apple
description: An apple.

== location market
name: Market
description: A market.

== shop stall
name: Stall
at: market
stock:
    apple: 1
bought:
    You bought [shop.item_name].

== creature rat
name: Rat
found in: nowhere
level: 3
hp: 400
damage: 1
stats: strength 10, dexterity 1, stamina 10, perception 10, intelligence 10, charisma 10
libido: 0

== scene brawl
fight rat:
    won:
        The rat flees.
    lost:
        The rat wins.
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "l.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 5)
	game.start("market")
	game.set_value("player.humanity", 100)
	game.set_value("player.hp", 100)
	game.set_value("player.dexterity", 40)
	game.set_value("player.level", 1)
	game.take_output()


func after_each() -> void:
	game.dispose()


func _do(effect: String) -> void:
	game.apply(Effect.compile(effect))


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type in ["paragraph", "notice"]:
			out.append(TextTemplate.plain(e.spans) if e.has("spans") else str(e.get("text", "")))
	return "\n".join(out)


func _win() -> String:
	game.runner.start("brawl")
	game.state.combat.hp = 1
	game.runner.combat_action("attack")
	var text := ""
	for _i in 10:
		text += _text()
		if game.runner.status != "continue":
			break
		game.runner.proceed()
	return text + _text()


func test_enough_experience_levels_up_after_a_fight() -> void:
	game.set_value("player.xp", 19)
	var text := _win()
	# The rat is level 3: +6 xp makes 25 of the 20 needed at level 1.
	assert_eq(int(game.value("player.level")), 2)
	assert_eq(int(game.value("player.xp")), 5, "the cost is taken from the experience")
	assert_string_contains(text, "You reached level 2!")
	assert_eq(game.runner.status, "choice", "an even level offers a stat")
	var before := int(game.value("player.perception"))
	game.runner.choose(1)
	assert_eq(int(game.value("player.perception")), before + 1)


func test_not_enough_experience_and_the_gate() -> void:
	game.set_value("player.xp", 5)
	_win()
	assert_eq(int(game.value("player.level")), 1)
	game.set_value("player.xp", 100)
	game.set_value("player.humanity", 0)
	_do("check level")
	assert_eq(int(game.value("player.level")), 1, "levels when holds the level back")
	game.set_value("player.humanity", 50)
	_do("check level")
	assert_eq(int(game.value("player.level")), 2)


func test_fast_learner_needs_less() -> void:
	assert_eq(LevelSystem.needed(game), 20)
	_do("feat + fast_learner")
	assert_eq(LevelSystem.needed(game), 16)


func test_level_up_player_forces_a_level() -> void:
	game.set_value("player.xp", 0)
	_do("level up player")
	assert_eq(int(game.value("player.level")), 2)
	assert_eq(int(game.value("player.xp")), -20, "as the original, the cost is taken anyway")


func test_feats_are_offered_every_fifth_level() -> void:
	game.set_value("player.level", 4)
	_do("level up player")
	assert_eq(game.runner.status, "choice")
	var labels: Array = game.take_output().filter(func(e): return e.type == "choices")[-1].options.map(func(o): return o.text)
	assert_eq(labels, ["Lucky", "Unlucky", "Skip"], "available when hides the others; sorted by name")
	game.runner.choose(0)
	assert_true("lucky" in game.state.feats)
	assert_eq(LevelSystem.offered_feats(game, "fun"), [], "Unlucky is no longer available, Hidden never was")


func test_skipping_a_feat_and_gained_scripts() -> void:
	game.set_value("player.level", 14)
	_do("level up player")
	game.runner.choose(2)  # level 15: odd, so the feat choice comes straight away
	assert_false("lucky" in game.state.feats or "unlucky" in game.state.feats)
	var hp := int(game.value("player.maxhp"))
	_do("choose feat basic")
	assert_eq(game.runner.status, "choice")
	game.runner.choose(0)
	assert_true("hardy" in game.state.feats)
	assert_eq(int(game.value("player.maxhp")), hp + 8, "the feat's gained: script ran")


func test_interests_default_set_and_pansexual() -> void:
	assert_true(Condition.evaluate(Condition.compile("player is interested in males"), game))
	assert_false(Condition.evaluate(Condition.compile("player is interested in females"), game))
	assert_false(Condition.evaluate(Condition.compile("player is pansexual"), game))
	assert_true(game.set_interest("females", true))
	assert_true(Condition.evaluate(Condition.compile("player is pansexual"), game))
	assert_false(game.set_interest("robots", true), "only declared interests")
	var view: Array = game.content_settings().interests
	assert_eq(view.map(func(i): return i.id), ["males", "females"])
	# Interests are saved with the game.
	var saved := game.save_dict()
	var other := Game.new(game.content, 1)
	other.load_dict(JSON.parse_string(JSON.stringify(saved)))
	assert_true(other.interest("females"))
	other.dispose()


func test_combat_rules_words_reward_and_unarmed_attack() -> void:
	var w := ItemSystem.weapon(game)
	assert_eq(int(w.damage), 6)
	assert_eq(str(w.text), "a wooden spoon")
	var text := _win()
	assert_string_contains(text, "You whack the rat with a wooden spoon")
	assert_string_contains(text, "You find 3 coins.")
	assert_eq(int(game.value("player.coins")), 3)
	assert_false(text.contains("freecred"), "the engine adds no money of its own")


func test_shop_names_the_item_and_counts_the_currency() -> void:
	game.set_value("player.coins", 1)
	var cur := ShopSystem.currency(game, "stall")
	assert_eq(ShopSystem.amount(cur, 1), "1 coin")
	assert_eq(ShopSystem.amount(cur, 3), "3 coins")
	var opts := ShopSystem.options(game, "stall")
	assert_string_contains(str(opts[0].text), "1 coin")
	game.runner.act("shop", "stall")
	game.take_output()
	game.runner.choose(0)
	var text := _text()
	assert_string_contains(text, "You bought apple.")
	assert_string_contains(text, "for 1 coin")


func test_new_definitions_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := """== level_rules r
xp needed: 10 +
levels when: player is grumpy

== feat f
name: F
group: two words
available when: player is grumpy

== interest i
name: I
default: maybe

== combat_rules c
unarmed damage: lots

== scene s
~ choose feat nothing
"""
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	for part in ["Xp needed", "grumpy", "feat group", "Default must be yes or no", "Unarmed damage", "No feat has group"]:
		assert_string_contains(text, part)
