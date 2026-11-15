extends GutTest
## The creature's side of a fight: its scripts for each round, its special
## attacks (`attacks:` and the built-in specials), the values `enemy.*` and
## `fight.*`, lasting changes to a creature, loot, items placed in a location
## and an item's infection changed during play.

const ROOT := "user://combat_specials_test_packs"

const PACK := """== combat_rules test
hump lust: random 2 to 6

== location arena
name: Arena
description: Sand and old blood.
exits:
    east: yard

== location yard
name: Yard
description: A bare yard.
exits:
    west: arena

== item gem
name: gem
description: A glittering gem.
category: collectible

== item goo
name: goo
description: Sticky goo.
category: drink
infectious: brute
use:
    You drink the goo.

== form brute
name: Brute
torso:
    description: a brute's body
    change: your body bulks up

== form fox
name: Fox
skin:
    description: red fur
    change: red fur spreads over you

== creature brute
name: Brute
hp: 200
level: 1
damage: 4
stats: strength 10, dexterity 40, stamina 10, perception 10, intelligence 10, charisma 10
form: brute
special: hump 100%
hump:
    The brute grinds against you.

== creature cat
name: Cat
hp: 200
level: 1
damage: 4
stats: strength 10, dexterity 40, stamina 10, perception 10, intelligence 10, charisma 10
special: pounce 100%
pounce:
    ~ fight.pounces + 1 quietly
    The cat pounces on you.

== creature dragon
name: Dragon
hp: 200
level: 1
damage: 6
stats: strength 10, dexterity 10, stamina 10, perception 60, intelligence 10, charisma 10
special: firebreath
breath warning:
    The dragon draws a deep breath.
breath direct:
    Flames engulf you for [fight.damage] damage.
breath partial:
    Flames lick you for [fight.damage] damage.
breath miss:
    You dodge the flames.

== creature peacock
name: Peacock
hp: 200
level: 1
damage: 0
stats: strength 10, dexterity 10, stamina 10, perception 10, intelligence 60, charisma 10
strike with: intelligence
attacks:
    * Display
        if enemy hits using intelligence:
            The peacock's tail mesmerises you.
            ~ libido + 30 quietly
            if player.libido >= 80:
                ~ lose fight by lust
        else:
            The peacock fans its tail, but you look away.

== creature troll
name: Troll
hp: 20
level: 1
damage: 1
loot: gem 100%
each round:
    ~ enemy.hp + 5 quietly
    ~ fight.rounds + 1 quietly
after attack:
    if enemy.hp > 30:
        The troll laughs, its wounds closing.
miss:
    The troll swings wide.

== creature wisp
name: Wisp
hp: 50
level: 1
damage: 1
attacks:
    * Fade [if enemy.round >= 2]
        The wisp fades away.
        ~ win fight

== scene place_gem
~ put gem 2 in yard

== scene tidy_yard
~ remove gem from yard
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
	_strong()
	game.take_output()


func after_each() -> void:
	game.dispose()


func _strong() -> void:
	game.set_value("player.maxhp", 100000)
	game.set_value("player.hp", 100000)
	game.set_value("player.dexterity", 1)
	game.set_value("player.libido", 0)
	game.set_value("player.perception", 60)  # no surprise attacks: each test controls the rounds


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type in ["paragraph", "notice"]:
			out.append(TextTemplate.plain(e.spans) if e.has("spans") else str(e.get("text", "")))
	return "\n".join(out)


func _fight(id: String) -> void:
	game.runner.start_encounter(id)
	game.take_output()


func _rounds(n: int) -> String:
	var out := ""
	for _i in n:
		if game.state.combat.is_empty() or game.state.combat.result != "":
			break
		game.runner.combat_action("pass")
		out += _text() + "\n"
	return out


func test_enemy_values_and_each_round_scripts() -> void:
	_fight("troll")
	assert_eq(int(game.value("enemy.hp")), 20)
	assert_eq(int(game.value("enemy.max_hp")), 20)
	_rounds(3)
	assert_eq(int(game.value("fight.rounds")), 3, "each round ran three times")
	assert_eq(int(game.value("enemy.hp")), 35, "the troll heals itself by 5 each round")
	game.set_value("enemy.damage", 9)
	assert_eq(CombatSystem.number(game, "troll", "damage", 0), 9, "a change for this fight")
	game.set_value("enemy.hp", -5)
	game.runner.combat_action("pass")
	assert_eq(str(game.last_fight), "won", "a script that drops the enemy to 0 wins the fight")
	assert_eq(int(game.value("fight.rounds")), 0, "fight numbers are gone after the fight")
	assert_eq(CombatSystem.number(game, "troll", "damage", 0), 1, "fight changes don't last")


func test_lasting_changes_to_a_creature() -> void:
	game.apply(Effect.compile("creature troll damage + 3"))
	game.apply(Effect.compile("creature troll dexterity = 25"))
	game.apply(Effect.compile("creature troll loot none"))
	assert_eq(CombatSystem.number(game, "troll", "damage", 0), 4)
	assert_eq(CombatSystem.stat(game, "troll", "dexterity"), 25)
	_fight("troll")
	assert_eq(int(game.value("enemy.damage")), 4, "the change lasts into the next fight")
	assert_eq(int(game.value("enemy.dexterity")), 25)
	game.state.combat.hp = -100
	game.runner.combat_action("pass")
	assert_eq(int(game.value("player.carried.gem")), 0, "loot none drops nothing")


func test_loot_drops_with_its_chance() -> void:
	_fight("troll")
	game.set_value("enemy.hp", -100)
	game.runner.combat_action("pass")
	assert_eq(int(game.value("player.carried.gem")), 1, "loot gem 100% always drops")
	assert_true(Effect.compile("creature troll loot gem 30%").op == "creature_change")


func test_attacks_menu_with_an_intelligence_strike_and_a_lust_loss() -> void:
	_fight("peacock")
	var text := _rounds(10)
	assert_string_contains(text, "mesmerises you")
	assert_eq(str(game.last_fight), "lost by lust", "the peacock's display ends the fight by lust")


func test_an_attack_option_can_wait_for_its_condition() -> void:
	_fight("wisp")
	game.runner.combat_action("pass")
	assert_false(_text().contains("fades away"), "not in the first round")
	game.runner.combat_action("pass")
	assert_string_contains(_text(), "The wisp fades away.")
	assert_eq(str(game.last_fight), "won")


func test_hump_needs_the_creatures_body() -> void:
	_fight("brute")
	var text := _rounds(6)
	assert_false(text.contains("grinds against you"), "not while the player's body is human")
	game.state.combat = {}
	game.runner.frames.clear()
	_strong()
	game.set_value("player.body.torso", "brute")
	_fight("brute")
	text = _rounds(6)
	assert_string_contains(text, "grinds against you")
	assert_true(int(game.value("player.libido")) > 0, "humping raises libido")


func test_pounce_and_its_script() -> void:
	_fight("cat")
	_rounds(6)
	assert_true(int(game.value("fight.pounces")) > 0, "the cat pounced")


func test_firebreath_warns_then_breathes() -> void:
	_fight("dragon")
	game.set_value("fight.breath_count", 100)
	var text := _rounds(1)
	assert_string_contains(text, "draws a deep breath")
	assert_true(Condition._truthy(game.value("fight.breath_ready")))
	text = _rounds(1)
	assert_true(text.contains("Flames") or text.contains("dodge the flames"), text)
	assert_false(Condition._truthy(game.value("fight.breath_ready")), "the breath is spent")


func test_items_placed_in_a_location_and_an_items_infection() -> void:
	game.runner.start("place_gem")
	assert_eq(ItemSystem.on_ground(game, "yard", "gem"), 2)
	game.runner.start("tidy_yard")
	assert_eq(ItemSystem.on_ground(game, "yard", "gem"), 0)
	game.apply(Effect.compile("item goo infects as fox"))
	game.apply(Effect.compile("give goo"))
	game.take_output()
	game.runner.act("use", "goo")
	_text()
	assert_eq(game.part_form("player", "skin"), "fox", "the goo now infects as the fox")


func test_combat_content_is_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := """== creature c
name: C
hp: 5
special: grapple 20%, laser eyes
strike with: luck
attacks:
    * Zap
        ~ enemy.mana - 1

== creature d
name: D
hp: 5
special: firebreath 50%

== scene s
~ enemy strike 200%
~ put nothing_here in nowhere
~ item nothing_here infects as nobody
~ lose fight by seduction
"""
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors()) + str(db.diagnostics)
	for part in ["laser eyes", "Strike with", "mana", "firebreath", "only works during a fight", "nothing_here", "nobody", "won by seduction"]:
		assert_string_contains(text, part)
