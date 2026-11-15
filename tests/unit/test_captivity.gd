extends GutTest
## Captivity: rounds of Struggle, Oblige or Abide, Endure or Recover while the
## player is held, with climax, loss and escape (the original's bound states).

const ROOT := "user://captivity_test_packs"

const PACK := """== values goo_log
values:
    climaxes: number
    rounds: number

== location cave
name: Cave
description: A damp cave.

== hook goo_counter
on: captivity round
do:
    ~ goo_log.rounds + 1 quietly

== captivity goo
name: Inside the goo
escape at: 3
pause after each: no
start:
    The goo swallows you.
climax:
    You climax inside the goo.
    ~ goo_log.climaxes + 1 quietly
    ~ humanity - 10 quietly
each round:
    ~ thirst + 1 quietly
situation:
    You float in the goo[if captivity.struggle > 0], closer to the edge[end if].
struggle:
    You swim toward the edge.
    ~ captivity.lust + 7 quietly
escape:
    You burst out of the goo.
oblige:
    You give in to the goo.
    ~ captivity.lust + 60 quietly
abide:
    You put up with the goo.
    ~ captivity.lust + 60 quietly
endure:
    You hold on.
    ~ humanity - 30 quietly
recover:
    You find clarity.
lost:
    The goo keeps you forever.
    ~ ending goo_end
actions:
    * Call for help [if captivity.round > 1]
        Someone pulls you out.
        ~ end captivity

== captivity net
pause after each: no
status: Knots: [captivity.struggle]
situation:
    You hang in the net.
struggle:
    ~ captivity.struggle + 1 quietly
    if captivity.struggle >= 2 and chance 1 in 1:
        You cut yourself loose.
        ~ escape captivity
    if not captivity is ending:
        The net holds.

== scene netted
play net
You drop to the ground.

== scene caught
The goo looms.
play goo
You are free again.
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "goo.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 1)
	game.start("cave")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func _choices() -> Array:
	return game.runner.pending


func test_struggling_free_ends_the_captivity_and_the_scene_goes_on() -> void:
	game.runner.start("caught")
	var first := _text()
	assert_string_contains(first, "The goo swallows you.")
	assert_string_contains(first, "You float in the goo.")
	assert_string_contains(first, "Struggle: [--]", "the bar has escape at - 1 places")
	assert_eq(game.runner.status, "choice")
	var turn: int = game.state.turn
	game.runner.choose(0)
	var second := _text()
	assert_string_contains(second, "You swim toward the edge.")
	assert_string_contains(second, "closer to the edge")
	assert_string_contains(second, "Struggle: [-X]")
	game.runner.choose(0)
	game.runner.choose(0)
	var last := _text()
	assert_string_contains(last, "You burst out of the goo.")
	assert_string_contains(last, "You are free again.")
	assert_eq(game.state.turn, turn + 1, "a turn passes after escaping")
	assert_false(game.state.values.has("captivity.struggle"), "the numbers are reset")
	assert_eq(int(game.value("goo_log.rounds")), 3, "the captivity round hook ran each round")


func test_lust_brings_a_climax_and_starts_over_from_libido() -> void:
	game.set_value("player.libido", 30)
	game.runner.start("caught")
	_text()
	game.runner.choose(1)  # abide or oblige: + 60 lust (90)
	game.runner.choose(1)  # 150: climax next round
	var text := _text()
	assert_string_contains(text, "You climax inside the goo.")
	assert_eq(int(game.value("goo_log.climaxes")), 1)
	assert_eq(int(game.value("captivity.lust")), 30, "lust starts over from libido")


func test_the_labels_follow_obliging_and_recovering() -> void:
	game.runner.start("caught")
	var labels: Array = game.take_output().filter(func(e): return e.type == "choices")[0].options.map(func(o): return o.text)
	assert_eq(labels, ["Struggle", "Oblige", "Endure"], "obliging while hp > 0")
	game.set_value("player.hp", 0)
	game.set_value("player.humanity", 80)
	game.state.values["captivity.recover"] = true
	game.runner.choose(1)
	labels = game.take_output().filter(func(e): return e.type == "choices")[0].options.map(func(o): return o.text)
	assert_eq(labels.slice(0, 3), ["Struggle", "Oblige", "Recover"], "once obliging, always obliging (as in the original)")


func test_abide_is_offered_while_not_obliging() -> void:
	game.set_value("player.hp", 0)
	game.set_value("player.humanity", 80)
	game.runner.start("caught")
	var labels: Array = game.take_output().filter(func(e): return e.type == "choices")[0].options.map(func(o): return o.text)
	assert_eq(labels, ["Struggle", "Abide", "Endure"])


func test_losing_all_humanity_ends_it() -> void:
	game.set_value("player.humanity", 30)
	game.runner.start("caught")
	_text()
	game.runner.choose(2)  # endure: - 30
	assert_string_contains(_text(), "The goo keeps you forever.")
	assert_eq(game.state.ending, "goo_end")


func test_an_action_can_end_the_captivity() -> void:
	game.runner.start("caught")
	_text()
	assert_eq(_choices().size(), 3, "the action is not offered in the first round")
	game.runner.choose(1)
	_text()
	assert_eq(_choices().size(), 4)
	game.runner.choose(3)
	var text := _text()
	assert_string_contains(text, "Someone pulls you out.")
	assert_string_contains(text, "You are free again.")


func test_captivities_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := "== captivity c\nescape at: 3 +\nclimax at: lots\npause after each: maybe\n"
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	assert_string_contains(text, "Escape at")
	assert_string_contains(text, "Climax at")
	assert_string_contains(text, "Pause after each")
	assert_string_contains(text, "struggle:")


func test_scripts_can_decide_the_escape_without_escape_at() -> void:
	var turn: int = game.state.turn
	game.runner.start("netted")
	assert_string_contains(_text(), "Knots: 0", "a captivity can write its own status line")
	game.runner.choose(0)
	assert_string_contains(_text(), "The net holds.")
	game.runner.choose(0)
	var text := _text()
	assert_string_contains(text, "You cut yourself loose.")
	assert_false(text.contains("The net holds."), "captivity is ending after the escape")
	assert_string_contains(text, "You drop to the ground.")
	assert_eq(game.state.turn, turn + 1, "escaping lets a turn pass")
