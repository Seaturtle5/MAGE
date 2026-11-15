extends GutTest
## The new-game screen: steps built from the content, cards that change the
## character sheet, rolled values shown as such, and Begin handing the choices on.

const ROOT := "user://new_game_screen_test_packs"

const PACK := """== values start
values:
    body: plain, fancy

== location home
name: Home
description: A small home.

== creation_rules test_game
choices: pick_stat, pick_body
feats:
    basic: steady
before:
    ~ player.strength = 10 quietly
    ~ player.dexterity = 10 quietly
    ~ player.intelligence = 10 quietly
after:
    ~ player.maxhp = player.strength * 2 quietly

== menu pick_stat
title: Main stat
* Strong -- More strength.
    ~ player.strength + 5 quietly
* Quick -- More dexterity.
    ~ player.dexterity + 5 quietly
* Clever -- More intelligence.
    ~ player.intelligence + 5 quietly
* Lucky -- Strength rolled at the start.
    ~ player.strength = random 1 to 1000 quietly

== menu pick_body
title: Body
* Plain -- An ordinary body.
    ~ start.body = plain quietly
* Fancy -- A fancy body.
    ~ start.body = fancy quietly

== feat steady
name: Steady
group: basic

== feat nimble
name: Nimble
group: basic

== game_mode tough
name: Tough Mode
description: Harder fights.

== scenario home_start
name: Home
start: home

== scenario lab_start
name: Lab
start: home
"""

var db: ContentDB
var game: Game
var screen: NewGameScreen


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "c.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	db = ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 4)
	screen = NewGameScreen.new(game, func(): return VBoxContainer.new(), func(): return "", func(_id): return null)
	add_child_autofree(screen)


func after_each() -> void:
	game.dispose()


func _titles() -> Array:
	return screen._steps.map(func(s): return s.title)


## The numbers on the sheet: each attribute block's abbreviation and value.
func _sheet_numbers() -> Dictionary:
	var out := {}
	for block in screen._sheet.find_children("*", "PanelContainer", true, false):
		var labels: Array = block.find_children("*", "Label", true, false)
		if labels.size() == 2:
			out[labels[0].text.to_lower()] = labels[1].text
	return out


func test_steps_come_from_the_content() -> void:
	# Two scenarios make an origin step; the four-answer question gets its own step,
	# the two-answer one goes to Details; feats and Challenge follow.
	assert_eq(_titles(), ["Origin", "Who you are", "Main stat", "Details", "Feats", "Challenge"])


func test_picking_a_card_changes_the_sheet() -> void:
	screen.go_to_step(2)
	assert_eq(_sheet_numbers().get("str"), "15", "the first answer is chosen at first")
	screen.handle_key(KEY_2)
	assert_eq(screen._answers.pick_stat, 1)
	var numbers := _sheet_numbers()
	assert_eq(numbers.get("str"), "10")
	assert_eq(numbers.get("dex"), "15")


func test_values_that_change_between_tries_are_shown_as_rolled() -> void:
	screen.go_to_step(2)
	screen.handle_key(KEY_4)
	var numbers := _sheet_numbers()
	assert_eq(numbers.get("str"), "?", "strength is rolled at the start")
	assert_eq(numbers.get("dex"), "10", "dexterity is not")


func test_begin_hands_on_every_choice() -> void:
	watch_signals(screen)
	screen.go_to_step(0)
	screen.handle_key(KEY_2)  # the Lab
	screen._name = "Ash"
	screen._pronoun = 2
	screen.go_to_step(2)
	screen.handle_key(KEY_3)  # Clever
	screen._modes.append("tough")
	screen.go_to_step(screen._steps.size() - 1)
	screen.handle_key(KEY_ENTER)
	assert_signal_emitted(screen, "begin")
	var args: Array = get_signal_parameters(screen, "begin")
	assert_eq(args[0], "lab_start")
	assert_eq(args[1], "Ash")
	assert_eq(args[2], "they")
	assert_eq(args[3].pick_stat, 2)
	assert_eq(args[3]["feat basic"], "steady")
	assert_eq(args[4], ["tough"])
	game.settings.mode = args[4]
	game.start_scenario(args[0], args[1], args[2], args[3])
	assert_eq(int(game.value("player.intelligence")), 15, "the game starts with the chosen answer")
