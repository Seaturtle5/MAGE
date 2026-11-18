extends GutTest
## Game modes through rules (level limit, healing, rest, hunting, mode bonuses),
## rest interruptions, player commands, sunrise and sunset hooks, and the
## children-at-a-home descriptor.

const ROOT := "user://modes_test_packs"

const PACK := """== values log
values:
    sunrise: number
    sunset: number
    commanded: number

== zone wild
name: Wild

== location camp
name: Camp
description: A camp.
zone: wild
rest: bed

== location hut
name: Hut
description: A safe hut.
flags: safe rest
rest: bed

== creature brute
name: Brute
found in: wild
level: 5
hp: 10

== creature pup
name: Pup
found in: wild
level: 1
hp: 5

== game_mode tough
name: Tough

== game_mode keen
name: Keen
exploration bonus: 3

== game_mode sleepless
name: Sleepless

== game_mode frail
name: Frail

== game_mode dark
name: Dark

== feat unlucky
name: Unlucky

== combat_rules rules
harder rolls when: mode tough
level limit: player.level + 1
level limit off when: mode tough

== survival_rules rules
natural healing when: not mode frail

== hunt_rules rules
hunt when: not mode dark

== condition rested
name: Rested

== rest_rules rules
off when: mode sleepless
condition: rested
interruption when: not here is flagged safe rest
interruption chance: 0 in 20
interruption chance modifiers:
    player has feat unlucky: + 20
interrupted:
    INTERRUPTED
undisturbed:
    PEACEFUL

== command shout
name: Shout
description: Shout into the night.
when: player.level >= 0
play:
    You shout.
    ~ log.commanded + 1 quietly

== command secret
name: Secret
when: player.level > 50
play:
    Hidden.

== hook sunrise
on: day starts
do:
    ~ log.sunrise + 1 quietly

== hook sunset
on: night starts
do:
    ~ log.sunset + 1 quietly

== text kid_line
[child.name] ([child.gender], [child.age_days] days)
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "modes.fsc": PACK, "values.fsc": TestPlayerValues.TEXT}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 4)
	game.start("camp")
	game.set_value("player.level", 0)
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func test_the_level_limit_and_harder_rolls_follow_a_mode() -> void:
	assert_eq(game.runner.encounter_pool("wild"), ["pup"], "the level limit keeps the brute away")
	assert_eq(game.runner.encounter_pool("wild", true), ["brute", "pup"], "but a creature of any level can be hunted for")
	assert_false(CombatSystem.holds(game, "harder rolls when"))
	game.settings.mode = ["tough"]
	assert_eq(game.runner.encounter_pool("wild"), ["brute", "pup"], "the mode lifts the limit")
	assert_true(CombatSystem.holds(game, "harder rolls when"))


func test_natural_healing_rest_and_hunting_follow_modes() -> void:
	game.set_value("player.hp", 1)
	game.pass_turn()
	assert_gt(int(game.value("player.hp")), 1, "healing every turn")
	game.settings.mode = ["frail"]
	game.set_value("player.hp", 1)
	game.pass_turn()
	assert_eq(int(game.value("player.hp")), 1, "no natural healing in the mode")
	assert_false(RestSystem.off(game))
	game.settings.mode = ["sleepless"]
	assert_true(RestSystem.off(game))
	assert_true(HuntSystem.allowed(game))
	game.settings.mode = ["dark"]
	assert_false(HuntSystem.allowed(game))
	assert_false(game.runner.act("hunt", "pup"), "hunting is refused in the mode")


func test_a_mode_carries_feat_style_bonuses() -> void:
	assert_eq(game.feat_bonus("exploration bonus"), 0)
	game.settings.mode = ["keen"]
	assert_eq(game.feat_bonus("exploration bonus"), 3)


func test_rest_interruptions_follow_the_rules() -> void:
	assert_true(game.runner.act("rest"))
	assert_string_contains(_text(), "PEACEFUL", "an exposed rest that is not interrupted")
	game.state.feats.append("unlucky")
	game.runner.act("rest")
	assert_string_contains(_text(), "INTERRUPTED")
	assert_eq(game.runner.status, "combat")


func test_a_safe_place_is_never_interrupted() -> void:
	game.go_to("hut")
	game.state.feats.append("unlucky")
	game.take_output()
	assert_true(game.runner.act("rest"))
	var text := _text()
	assert_false(text.contains("INTERRUPTED") or text.contains("PEACEFUL"))


func test_commands_show_while_available_and_run() -> void:
	assert_eq(game.runner.available_commands(), ["shout"])
	assert_true(game.runner.act("command", "shout"))
	assert_string_contains(_text(), "You shout.")
	assert_eq(int(game.value("log.commanded")), 1)
	assert_false(game.runner.act("command", "secret"), "a command whose condition fails")


func test_sunrise_and_sunset_hooks() -> void:
	for _i in 8:
		game.pass_turn()
	assert_eq(int(game.value("log.sunrise")), 1, "one sunrise a day")
	assert_eq(int(game.value("log.sunset")), 1, "one sunset a day")


func test_children_at_a_home_render_a_snippet_each() -> void:
	game.state.values["pregnancy.offspring"] = [
		{"turn": 0, "name": "Ash", "gender": "female", "home": "bunker"},
		{"turn": 0, "name": "Bo", "gender": "male", "home": "roaming"},
		{"turn": 0, "name": "Cy", "gender": "male", "home": "bunker"}]
	game.state.turn = 16
	game.state.values["child.name"] = "Newborn"
	var text := game.describe("children at bunker as kid_line")
	assert_string_contains(text, "Ash (female, 2 days)")
	assert_string_contains(text, "Cy (male, 2 days)")
	assert_false(text.contains("Bo"))
	assert_eq(game.state.values["child.name"], "Newborn", "the values in play are restored")
