extends GutTest
## Endings: the epilogue that plays when the game ends, in priority order, with
## conditions, excluded types, deaths that stop it, marks made during play,
## the top bar from content, meters at their limit and plural pick-up words.

const ROOT := "user://ending_test_packs"

const PACK := """== values player
values:
    cold: number

== location camp
name: Camp
description: A cold camp.
items: berries

== item berries
name: wild berries
plural: yes

== item coat
name: coat

== form wolf
name: Wolf
torso:
    description: a wolf's body
    change: you turn into a wolf

== ending summary
type: summary
priority: -10
play:
    SUMMARY

== ending eaten
type: bad_end
priority: 5
when: ending eaten is triggered
play:
    You were eaten.
    ~ player dies

== ending wolf_infection
type: infection
priority: 1000
when: player body is wolf
play:
    WOLF LIFE

== ending human_life
type: epilogue
priority: 50
when: player.humanity >= 10
play:
    HUMAN LIFE [if ending flag famous is set]FAMOUS[end if] [if the game ended by rescue]RESCUED[end if]

== meter cold
name: Chill
value: player.cold
limit: 3
at limit:
    FROZEN.

== status_bar test
meters: hp, cold
currency: score

== scene ask
Pick one.
* Shiver
    ~ meter cold + 5
    You shiver.
* Wait
    You wait.
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "e.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 4)
	game.start("camp")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _all() -> Array:
	return game.take_output()


func _text(events: Array) -> String:
	var out: PackedStringArray = []
	for e in events:
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func test_an_ending_ends_the_game_and_the_epilogue_plays_in_order() -> void:
	game.apply(Effect.compile("ending flag famous"))
	game.apply(Effect.compile("ending rescue_came"))
	var events := _all()
	var text := _text(events)
	assert_eq(game.runner.status, "ended")
	assert_true(text.find("SUMMARY") < text.find("HUMAN LIFE"), "lowest priority first")
	assert_string_contains(text, "FAMOUS")
	assert_false(text.contains("WOLF LIFE"), "endings whose condition fails are left out")
	assert_false(text.contains("eaten"))
	assert_true(events.any(func(e): return e.type == "game_over"))
	assert_false(game.runner.act("wait"), "nothing more happens")
	assert_true(Condition.evaluate(Condition.compile("the game ended by rescue_came"), game))
	assert_true(Condition.evaluate(Condition.compile("ending human_life is triggered"), game), "played endings are marked")


func test_a_death_stops_the_later_endings() -> void:
	game.apply(Effect.compile("transform into wolf"))
	game.apply(Effect.compile("trigger ending eaten"))
	assert_true(Condition.evaluate(Condition.compile("ending eaten is triggered"), game))
	assert_eq(game.state.ending, "", "marking an ending does not end the game")
	game.apply(Effect.compile("ending eaten"))
	var text := _text(_all())
	assert_string_contains(text, "You were eaten.")
	assert_false(text.contains("HUMAN LIFE"), "after a death no further endings play")
	assert_false(text.contains("WOLF LIFE"))
	assert_true(game.adjective("player", "dead"))


func test_excluded_types_are_left_out() -> void:
	game.apply(Effect.compile("transform into wolf"))
	game.apply(Effect.compile("exclude infection endings"))
	assert_true(Condition.evaluate(Condition.compile("infection endings are excluded"), game))
	game.apply(Effect.compile("ending done"))
	assert_false(_text(_all()).contains("WOLF LIFE"))


func test_the_rescue_ends_the_game_with_its_sentence() -> void:
	game.end_game("rescue", "You survived until the rescue came.")
	var events := _all()
	assert_true(events.any(func(e): return e.type == "ending" and e.ending == "You survived until the rescue came."))
	assert_string_contains(_text(events), "RESCUED")


func test_an_ending_in_the_middle_of_a_scene_stops_the_scene() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_mid/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "m.fsc": "== location room\nname: Room\ndescription: R.\n\n== scene trap\nThe floor gives way.\n~ ending fell\nAFTER\n"}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_mid/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_mid"])
	var g := Game.new(db, 1)
	g.start("room")
	g.take_output()
	g.runner.start("trap")
	var text := _text(g.take_output())
	assert_string_contains(text, "The floor gives way.")
	assert_false(text.contains("AFTER"))
	assert_eq(g.runner.status, "ended")
	g.dispose()


func test_the_status_bar_comes_from_content() -> void:
	game.set_value("player.cold", 2)
	game.set_value("player.score", 7)
	var bar := game.status_bar()
	assert_eq(bar.meters.map(func(m): return m.key), ["hp", "cold"])
	assert_eq(bar.meters[1].label, "Chill", "a meter's own name")
	assert_eq(bar.meters[1].max, 3, "a meter's limit")
	assert_eq(bar.meters[1].value, 2)
	assert_eq(bar.currency, "score")
	assert_eq(bar.money, 7)


func test_a_meter_limit_reached_during_a_choice_plays_after_the_scene() -> void:
	game.runner.start("ask")
	_all()
	game.runner.play_now("meter:cold#at limit")
	assert_eq(game.runner.status, "choice", "the choice still waits")
	game.runner.choose(1)
	var text := _text(_all())
	assert_string_contains(text, "You wait.")
	assert_string_contains(text, "FROZEN.", "then the waiting scene plays")


func test_plural_items_are_picked_up_as_them() -> void:
	game.runner.act("take", "berries")
	var notes := " ".join(_all().map(func(e): return str(e.get("text", "")) + _text([e])))
	assert_string_contains(notes, "tuck them in your backpack")


func test_endings_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := "== ending e\npriority: soon\ntype: bad end\nwhen: player is grumpy\n\n== scene s\n~ trigger ending nothing_here\nif ending nowhere is triggered:\n    Hm.\n\n== status_bar b\nmeters: hp, sparkle\n"
	var files := {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	for part in ["Priority must", "ending type", "grumpy", "nothing_here", "nowhere", "sparkle"]:
		assert_string_contains(text, part)
