extends GutTest
## The survival rules' scripts: `healing` after a turn's healing, `hunger rises`
## and `thirst rises` after each increase (feats such as a slower appetite).

const ROOT := "user://survival_script_test_packs"

const PACK := """== location camp
name: Camp
description: A cold camp.

== values log
values:
    hungry: number
    thirsty: number

== survival_rules basic
healing:
    ~ player.hp + 7 quietly
hunger rises:
    ~ log.hungry + 1 quietly
    ~ hunger - 1 quietly
thirst rises:
    ~ log.thirsty + 1 quietly
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "s.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("camp")
	game.take_output()


func after_each() -> void:
	game.dispose()


func test_healing_and_rising_hunger_and_thirst_run_their_scripts() -> void:
	game.set_value("player.maxhp", 500)
	game.set_value("player.hp", 100)
	game.set_value("player.stamina", 10)
	game.set_value("player.hunger", 0)
	SurvivalSystem.tick(game)
	assert_eq(int(game.value("player.hp")), 100 + 5 + 7, "stamina / 2, then the rules' healing")
	for _i in 60:
		SurvivalSystem.tick(game)
	assert_gt(int(game.value("log.hungry")), 0, "hunger rose and the script ran")
	assert_gt(int(game.value("log.thirsty")), 0, "thirst rose and the script ran")
	assert_eq(int(game.value("player.hunger")), 0, "the script took each rise back")
