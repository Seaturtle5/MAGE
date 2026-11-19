extends GutTest
## The combat rules' `before aftermath`: a script after a won fight's trophies and
## before the beaten creature's `defeated` scene, which `~ no aftermath` leaves out.

const ROOT := "user://aftermath_test_packs"

const PACK := """== location yard
name: Yard
description: A yard.

== feat chooser
name: Chooser

== creature rat
name: Rat
hp: 1
level: 1
damage: 1
defeated:
    THE RAT SCURRIES OFF

== combat_rules basic
before aftermath:
    if player has feat chooser:
        PLAY THE SCENE?
        * Yes
        * No
            ~ no aftermath

== scene meet_rat
fight rat:
    won:
        AFTER THE FIGHT
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "w.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("yard")
	game.set_value("player.hp", 100)
	game.set_value("player.strength", 90)
	game.set_value("player.dexterity", 90)
	game.take_output()


func after_each() -> void:
	game.dispose()


## Wins the fight with the rat; answers a question with `answer`. Returns what was said.
func _fight(answer: int = -1) -> String:
	var out: PackedStringArray = []
	game.runner.start("meet_rat")
	for _i in 60:
		for e in game.take_output():
			if e.type == "paragraph":
				out.append(TextTemplate.plain(e.spans))
		match game.runner.status:
			"combat":
				game.runner.combat_action("attack")
			"continue":
				game.runner.proceed()
			"choice":
				game.runner.choose(answer)
			_:
				break
	return "\n".join(out)


func test_without_the_question_the_creatures_scene_plays() -> void:
	var text := _fight()
	assert_eq(game.last_fight, "won")
	assert_string_contains(text, "THE RAT SCURRIES OFF")
	assert_false("PLAY THE SCENE?" in text)
	assert_string_contains(text, "AFTER THE FIGHT")


func test_yes_plays_the_creatures_scene() -> void:
	game.state.feats.append("chooser")
	var text := _fight(0)
	assert_string_contains(text, "PLAY THE SCENE?")
	assert_string_contains(text, "THE RAT SCURRIES OFF")
	assert_lt(text.find("PLAY THE SCENE?"), text.find("THE RAT SCURRIES OFF"), "the question comes first")
	assert_string_contains(text, "AFTER THE FIGHT")


func test_no_leaves_the_creatures_scene_out() -> void:
	game.state.feats.append("chooser")
	var text := _fight(1)
	assert_string_contains(text, "PLAY THE SCENE?")
	assert_false("THE RAT SCURRIES OFF" in text, "the scene is left out")
	assert_string_contains(text, "AFTER THE FIGHT", "the fight's own aftermath still plays")
