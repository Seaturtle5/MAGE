extends GutTest
## Player values a game declares: bounds, a higher top during fights, the engine
## roles they play, several declarations for one owner, the species comparison
## and the infection rules' checks.

const ROOT := "user://roles_test_packs"

const PACK := """== values player
values:
    humanity: number 100 (0 to 100)
        role: sanity
    libido: number 0 (0 to 100, up to 110 in fights)
        role: arousal

== values player
values:
    luck: number 3 (0 to 5)

== location yard
name: Yard
description: A yard.

== creature brute
name: Brute
level: 1
hp: 50
damage: 1

== form wolf
name: Wolf
head:
    description: a wolf's head
    change: your head turns lupine
torso:
    description: a wolf's body
    change: your body turns lupine

== form wolf_kin
name: Wolf
torso:
    description: another wolf's body
    change: your body turns lupine
"""

var game: Game


func _write(dir: String, files: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for name: String in files:
		var fa := FileAccess.open(dir + "/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()


func before_each() -> void:
	_write(ROOT + "/p", {"pack.fsc": "== pack p\nname: Test\n", "v.fsc": PACK})
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 5)
	game.start("yard")


func after_each() -> void:
	game.dispose()


func test_bounds_and_roles() -> void:
	assert_eq(game.role("sanity"), "player.humanity")
	assert_eq(game.role("morale"), "", "no value plays morale")
	game.set_value("player.humanity", 140)
	assert_eq(int(game.value("player.humanity")), 100, "kept within its bounds")
	game.set_value("player.luck", -2)
	assert_eq(int(game.value("player.luck")), 0, "a second declaration for the player adds its own values")
	game.apply(Effect.compile("humanity - 30"))
	assert_eq(int(game.value("player.humanity")), 70, "the short form changes a declared player value")


func test_arousal_climbs_in_fights_loses_at_its_top_and_settles_after() -> void:
	game.set_value("player.libido", 120)
	assert_eq(int(game.value("player.libido")), 100, "outside a fight the top is 100")
	CombatSystem.begin(game, "brute")
	game.set_value("player.libido", 120)
	assert_eq(int(game.value("player.libido")), 110, "in a fight it may climb to 110")
	assert_true(CombatSystem._check_end(game))
	assert_eq(game.state.combat.result, "lost by lust", "at its in-fight top the player loses by lust")
	game.settle_fight_values()
	assert_eq(int(game.value("player.libido")), 100, "after the fight it returns within its bounds")


func test_species_comparison() -> void:
	game.set_value("player.body.head", "wolf")
	game.set_value("player.body.torso", "wolf_kin")
	assert_true(Condition.evaluate(Condition.compile("player torso species is player head species"), game), "same strain name")
	game.set_value("player.body.torso", "human")
	assert_true(Condition.evaluate(Condition.compile("player torso species is not player head species"), game))


func test_declarations_and_infection_rules_are_checked() -> void:
	var bad := """== values player
values:
    humanity: number 100
        role: sanity
    mood: number 0
        role: sanity
    grit: number 0
        role: courage

== values player
values:
    humanity: number 5

== infection_rules r
resist chance: often
modest cock length: big
modest when: player is grumpy
"""
	_write(ROOT + "_bad/p", {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad})
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	for part in ["already played", "courage", "already declared", "N in M", "whole number", "grumpy"]:
		assert_string_contains(text, part)
