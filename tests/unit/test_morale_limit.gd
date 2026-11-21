extends GutTest
## The survival rules' morale limit: morale above the limit plus the player's
## level (plus `morale reset modifiers`) falls back to the limit, which is
## charisma plus perception unless `morale limit` says otherwise, raised by
## `morale limit modifiers`.

const ROOT := "user://morale_limit_test_packs"

const PACK := """== location room
name: Room
description: A room.

== feat perky
name: Perky

== survival_rules test
morale normalized: CALMER
morale limit modifiers:
    player has feat perky: (player.charisma + player.perception) / 5
morale reset modifiers:
    player has feat perky: player.level / 5
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
	game = Game.new(db, 2)
	game.start("room")
	game.set_value("player.charisma", 10)
	game.set_value("player.perception", 10)
	game.set_value("player.level", 0)
	game.take_output()


func after_each() -> void:
	game.dispose()


func _turns(n: int) -> void:
	for _i in n:
		game.pass_turn()


func test_morale_above_the_limit_falls_back() -> void:
	game.set_value("player.morale", 30)
	_turns(3)
	assert_eq(int(game.value("player.morale")), 20, "charisma plus perception")


func test_a_modifier_raises_the_limit() -> void:
	game.apply(Effect.compile("feat + perky"))
	game.set_value("player.morale", 23)
	_turns(3)
	assert_eq(int(game.value("player.morale")), 23, "within the raised limit (24)")
	game.set_value("player.morale", 40)
	_turns(3)
	assert_eq(int(game.value("player.morale")), 24)
