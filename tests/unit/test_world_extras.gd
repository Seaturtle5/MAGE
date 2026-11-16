extends GutTest
## Small world features (WorldSystem): events moved in play, a pick-up a hook can
## refuse, cursed gear a scene can take off and its text, hooks when the player
## arrives somewhere, choosing a creature and shifting into it, banned creatures,
## dangerous doors (their zone and their text), random items used up by use, a
## pregnancy by the strain a value names, characters renamed in play, a companion's
## own name, and extended play.

const ROOT := "user://world_extras_packs"

const PACK := """== values tally
values:
    n: number 0

== values shiftv
values:
    typed: text
    critter: text
    loot: text
    strain: text

== values playon
values:
    on: flag

== survival_rules sr
rescue after: 100
no rescue when: playon.on

== pregnancy_rules preg
female when: player is female
odds: 1 in 1
gestation: 6

== filter canine
name: Canine

== zone outside
name: Outside

== zone red
name: Red light district

== zone sewers
name: Sewers

== location den
name: Den
description: A den.
zone: outside
items: sneakers, rock
exits:
    north: glade
    down: door sewer_hole

== location glade
name: Glade
description: A glade.
zone: red
exits:
    south: den

== door sewer_hole
name: Sewer hole
leads to zone: sewers
going text:
    You peek into the hole, then climb down.

== event watcher
name: Watcher
found by: exploring in outside
repeat: always
play:
    Someone watches you.

== event sewer_find
name: Sewer Find
found by: exploring in sewers
repeat: always
play:
    Something glints in the muck.

== hook sneaker_check
on: before picking up sneakers
do:
    if filter canine is banned:
        You step away from the shoes.
        ~ cancel pick up
    else:
        You stash the [name of picking.item].

== hook sneaker_after
on: after picking up sneakers
do:
    After the shoes.

== hook travel_line
on: arriving
when: tally.n > 0
do:
    You arrive from [name of arrival.from].

== item sneakers
name: rubber sneakers
description: Sneakers.

== item rock
name: rock
description: A rock.

== item bandage
name: bandage
description: A bandage.
use:
    You wrap it.

== item charm
name: charm
description: A charm.
consumed: no
use:
    You rub it.

== item collar
name: collar
description: A collar.
equipment:
    slot: neck
    cursed: yes
cursed text:
    The collar flares hot under your fingers.
    ~ tally.n + 1 quietly

== item band
name: band
description: A band.
equipment:
    slot: arms
    cursed: yes

== form wolf
name: Wolf
sex: male
head:
    description: a wolf head
    change: your face stretches into a muzzle
torso:
    description: a furry body
    change: fur covers your chest
skin:
    description: grey fur
    change: grey fur sprouts
tail:
    description: a bushy tail
    change: a bushy tail grows
cock:
    count: 1
    length: 8
    description: knotted
    change: your cock grows a knot

== creature wolf
name: Wolf
found in: nowhere
hp: 20
level: 2
damage: 4
stats: strength 15, dexterity 12, stamina 11, perception 10, intelligence 9, charisma 8
libido: 40
tags: canine
form: wolf

== creature cat
name: Housecat
found in: nowhere
hp: 10
level: 1
damage: 2
stats: strength 8, dexterity 16, stamina 8, perception 12, intelligence 10, charisma 14
form: wolf

== character ann
name: Ann
lives at: den
presence: Ann sits by the fire.
description: Ann looks tired.

== character rex
name: Doctor Rex
lives at: den
companion:
    name: Rexy
    tamed: yes

== text ann_recorder
A small recorder labeled 'Ann' remains abandoned.

== scene renaming
~ character ann name "Recording of Ann"
~ character ann presence -> ann_recorder
~ character ann description -> ann_recorder

== scene restoring
~ character ann name default
~ character ann presence -> default
~ character ann description -> default

== scene each_companion_name
Companion: [companion.name].

== scene uses_new_values
if here.door_zone != "" and picking.item = "":
    Door zone [here.door_zone], from [arrival.from].
"""

var game: Game


func _load(text: String, folder: String) -> ContentDB:
	DirAccess.make_dir_recursive_absolute(folder + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "content.fsc": text}
	for name: String in files:
		var fa := FileAccess.open(folder + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([folder])
	return db


func before_each() -> void:
	var db := _load(PACK, ROOT)
	assert_eq(db.errors().map(func(d): return "%d %s" % [d.line, d.message]), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("den")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _said() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
		elif e.type in ["notice", "title"]:
			out.append(str(e.text))
	return "\n".join(out)


func _choices() -> Array:
	var shown: Array = game.output.filter(func(e): return e.type == "choices")
	return [] if shown.is_empty() else shown[-1].options.map(func(o): return str(o.text))


func _holds(condition: String) -> bool:
	var c := Condition.compile(condition)
	assert_false(c.has("error"), "%s: %s" % [condition, c.get("error", "")])
	return Condition.evaluate(c, game)


func _eval(expression: String) -> Variant:
	var e := Expr.parse(expression)
	assert_false(e.has("error"), "%s: %s" % [expression, e.get("error", "")])
	return Expr.evaluate(e, game)


func test_an_event_moves_to_another_area_and_level_in_play() -> void:
	assert_eq(game.runner.explore_events("outside"), ["watcher"])
	game.apply(Effect.compile("event watcher found in red"))
	assert_eq(game.runner.explore_events("outside"), [], "no longer found outside")
	assert_eq(game.runner.explore_events("red"), ["watcher"], "found in the red light district now")
	game.apply(Effect.compile("event watcher level = 9"))
	assert_eq(WorldSystem.event_level(game, "watcher"), 9)
	assert_eq(game.runner.explore_events("red"), [], "too high for a level 1 player")
	game.apply(Effect.compile("event watcher level - 9"))
	assert_eq(game.runner.explore_events("red"), ["watcher"])
	game.apply(Effect.compile("event watcher found in nowhere"))
	assert_eq(game.runner.explore_events("red"), [])
	var saved: Dictionary = game.save_dict().duplicate(true)
	var again := Game.new(game.content, 3)
	assert_true(again.load_dict(saved))
	assert_eq(again.runner.explore_events("outside") + again.runner.explore_events("red"), [], "saved with the game")
	again.dispose()


func test_a_hook_can_refuse_a_pick_up() -> void:
	game.settings.banned.append("canine")
	assert_true(game.runner.act("take", "sneakers"))
	var said := _said()
	assert_string_contains(said, "You step away from the shoes.")
	assert_false(said.contains("You pick up"), said)
	assert_eq(ItemSystem.count(game, "sneakers"), 0)
	assert_eq(ItemSystem.on_ground(game, "den", "sneakers"), 1, "it stays on the ground")
	game.settings.banned.erase("canine")
	assert_true(game.runner.act("take_all", ""))
	said = _said()
	assert_true(said.find("You stash the rubber sneakers.") < said.find("You pick up the rubber sneakers") and said.find("You pick up the rubber sneakers") < said.find("After the shoes."), said)
	assert_string_contains(said, "You pick up the rock", "everything else is taken too")
	assert_eq([ItemSystem.count(game, "sneakers"), ItemSystem.count(game, "rock")], [1, 1])
	assert_eq(game.runner.status, "idle")
	assert_eq(str(game.value("picking.item")), "", "cleared afterwards")


func test_cursed_gear_says_why_and_only_a_scene_takes_it_off() -> void:
	game.apply(Effect.compile("give collar quietly"))
	game.apply(Effect.compile("give band quietly"))
	game.apply(Effect.compile("wear collar quietly"))
	game.apply(Effect.compile("wear band quietly"))
	game.take_output()
	assert_true(game.runner.act("remove", "collar"), "its cursed text plays")
	assert_string_contains(_said(), "The collar flares hot under your fingers.")
	assert_true(ItemSystem.wears(game, "collar"), "still worn")
	assert_eq(int(game.value("tally.n")), 1)
	assert_false(game.runner.act("remove", "band"), "cursed, with nothing to say")
	var listed: Array = game.inventory_list().filter(func(it): return it.id in ["collar", "band"]).map(func(it): return [it.id, it.cursed_text])
	listed.sort()
	assert_eq(listed, [["band", false], ["collar", true]])
	game.apply(Effect.compile("remove whatever is worn on neck"))
	assert_true(ItemSystem.wears(game, "collar"), "taking off whatever is on a slot leaves cursed gear")
	game.apply(Effect.compile("remove collar"))
	assert_false(ItemSystem.wears(game, "collar"), "a scene takes it off (the original's now X is not equipped)")


func test_hooks_play_when_the_player_arrives_somewhere() -> void:
	assert_true(game.runner.act("go", "north"))
	assert_false(_said().contains("You arrive from"), "its when: does not hold")
	game.set_value("tally.n", 1)
	assert_true(game.runner.act("go", "south"))
	assert_string_contains(_said(), "You arrive from Glade.")
	assert_eq(str(game.value("arrival.from")), "glade")
	game.apply(Effect.compile("go to glade"))
	assert_string_contains(_said(), "You arrive from Den.", "a scene moving the player counts too")
	game.go_to("glade")
	assert_false(_said().contains("You arrive from"), "staying in the same place is no arrival")


func test_the_player_chooses_a_creature_and_shifts_into_it() -> void:
	game.set_value("shiftv.typed", "WOLF")
	assert_eq(_eval("creature named shiftv.typed"), "wolf", "by name, in any case")
	assert_eq(_eval("creature named \"cat\""), "cat", "a part of the name")
	assert_eq(_eval("creature named \"dragon\""), "")
	assert_eq(_eval("strength of wolf"), 15)
	assert_eq(_eval("charisma of cat"), 14)
	assert_eq(_eval("libido of wolf"), 40)
	game.state.encountered.append_array(["wolf", "cat"])
	game.apply(Effect.compile("ask shiftv.critter as creature met: Shift into what?"))
	assert_eq(_choices(), ["Housecat", "Wolf", "Nevermind"], "the creatures met, by name")
	game.runner.choose(1)
	assert_eq(str(game.value("shiftv.critter")), "wolf")
	game.take_output()
	assert_true(_holds("player.strength < strength of shiftv.critter"))
	game.apply(Effect.compile("shift into shiftv.critter"))
	var said := _said()
	for change in ["grey fur sprouts", "your face stretches into a muzzle", "a bushy tail grows", "fur covers your chest"]:
		assert_string_contains(said, change)
	assert_true(said.find("grey fur sprouts") < said.find("your face stretches") and said.find("a bushy tail grows") < said.find("fur covers your chest"),
		"skin, face and tail before the body, as the original: " + said)
	for part in ["head", "torso", "skin", "tail"]:
		assert_eq(game.part_form("player", part), "wolf", part)
	game.apply(Effect.compile("reset to human"))
	game.apply(Effect.compile("transform into shiftv.critter"))
	assert_eq(game.part_form("player", "head"), "wolf", "~ transform into a value: every part, quietly")


func test_whether_a_creature_is_banned() -> void:
	assert_false(_holds("creature wolf is banned"))
	assert_true(_holds("creature cat is not banned"))
	game.settings.banned.append("canine")
	assert_true(_holds("creature wolf is banned"))
	game.set_value("shiftv.critter", "wolf")
	assert_true(_holds("creature shiftv.critter is banned"))
	game.settings.banned.erase("canine")
	game.settings.warded.append("canine")
	assert_false(_holds("creature wolf is banned"), "a ward is not a ban")


func test_dangerous_doors_have_a_zone_and_a_text() -> void:
	assert_eq(str(game.value("here.door_zone")), "sewers")
	game.set_value("player.perception", 40)  # the zone's event comes up every time
	assert_true(game.runner.act("go", "down"))
	var kinds: Array = []
	for e in game.output:
		if e.type in ["title", "paragraph"]:
			kinds.append(e.type if e.type == "title" else TextTemplate.plain(e.spans))
	assert_eq(kinds.slice(0, 3), ["title", "You peek into the hole, then climb down.", "Something glints in the muck."],
		"the door's text is read on the page of what lies beyond")
	game.take_output()
	game.go_to("glade")
	assert_eq(str(game.value("here.door_zone")), "", "no dangerous door here")


func test_a_random_item_used_up_by_use() -> void:
	assert_false(_holds("player has an item used up by use"))
	for item in ["charm", "collar", "bandage"]:
		game.apply(Effect.compile("give %s quietly" % item))
	assert_true(_holds("player has an item used up by use"))
	assert_eq(_eval("random carried item used up by use"), "bandage", "not gear, not consumed: no")
	game.apply(Effect.compile("shiftv.loot = random carried item used up by use"))
	game.apply(Effect.compile("take shiftv.loot quietly"))
	assert_true(_holds("player does not have an item used up by use"))
	assert_true(str(_eval("random carried item")) in ["charm", "collar"])


func test_a_pregnancy_by_the_strain_a_value_names() -> void:
	game.set_value("player.cunts", 1)
	game.set_value("shiftv.strain", "cat")
	game.apply(Effect.compile("impregnation chance female by shiftv.strain"))
	assert_eq(PregnancySystem.gestation(game), 6)
	assert_eq(str(game.value("pregnancy.father")), "wolf", "the cat's strain")


func test_characters_are_renamed_in_play_and_companions_have_their_own_name() -> void:
	game.runner.start("renaming")
	game.take_output()
	assert_eq(game.describe("name of ann"), "Recording of Ann")
	game.runner.show_location()
	var view: Dictionary = game.output.filter(func(e): return e.type == "location")[-1]
	assert_true(view.people.any(func(p): return p.name == "Recording of Ann"))
	assert_string_contains(" ".join(view.description.map(func(s): return TextTemplate.plain(s))), "A small recorder labeled 'Ann' remains abandoned.")
	game.take_output()
	assert_true(game.runner.act("look", "ann"))
	assert_string_contains(_said(), "A small recorder labeled 'Ann' remains abandoned.")
	var saved: Dictionary = game.save_dict().duplicate(true)
	game.runner.start("restoring")
	assert_eq(game.describe("name of ann"), "Ann")
	assert_true(game.runner.act("look", "ann"))
	assert_string_contains(_said(), "Ann looks tired.")
	assert_true(game.load_dict(saved))
	assert_eq(game.describe("name of ann"), "Recording of Ann", "saved with the game")
	assert_eq(WorldSystem.companion_name(game, "rex"), "Rexy")
	assert_eq(game.describe("name of rex"), "Doctor Rex", "the character keeps its own name")
	game.apply(Effect.compile("summon rex"))
	game.take_output()
	assert_eq(game.companions_description(), "Accompanying you is Rexy, who is level 1.")
	game.apply(Effect.compile("for each companion play each_companion_name"))
	assert_string_contains(_said(), "Companion: Rexy.")


func test_extended_play_keeps_the_rescue_away() -> void:
	assert_eq(SurvivalSystem.rescue_turn(game), 100)
	game.set_value("playon.on", true)
	assert_eq(SurvivalSystem.rescue_turn(game), -1, "the rescue never comes")
	game.state.turn = 150
	game.pass_turn()
	assert_eq(game.state.ending, "", "no rescue ending")


func test_the_validator_reports_the_new_forms() -> void:
	var bad := """== zone red
name: Red

== creature wolf
name: Wolf
found in: nowhere

== character ann
name: Ann
companion:
    name:

== item stone
name: stone
cursed text:
    It won't come off.

== item ring
name: ring
equipment:
    slot: ring
cursed text:
    It won't come off.

== door plain_door
name: Plain
going text:
    You go through.

== survival_rules sr
no rescue when: player is grumpy

== event arriving_one
name: Arriving
found by: walking into ann_place
play:
    Hi.

== location ann_place
name: Place
description: A place.

== scene s
~ event nosuch found in red
~ event arriving_one found in red
~ event arriving_one found in blue
~ shift into wolff
if creature wolff is banned:
    No.
if player.strength < strength of wolff:
    No.
~ character bob name "Bob"
~ character ann presence -> missing_text
~ impregnate female by no_such.value
"""
	var db := _load(bad, ROOT + "_bad")
	var all: Array = db.diagnostics.map(func(d): return "%s %d %s" % [d.severity, d.line, d.message])
	var has := func(fragment: String) -> bool: return all.any(func(m: String) -> bool: return fragment in m)
	assert_true(has.call("Event 'nosuch' does not exist"), str(all))
	assert_true(has.call("warning") and has.call("arriving_one is found by arriving"), str(all))
	assert_true(has.call("'blue'"), str(all))
	assert_true(has.call("'wolff' is neither a creature nor a form"), str(all))
	assert_true(has.call("Creature 'wolff' does not exist"), str(all))
	assert_true(has.call("'strength of wolff'"), str(all))
	assert_true(has.call("Character 'bob' does not exist"), str(all))
	assert_true(has.call("missing_text"), str(all))
	assert_true(has.call("A companion's name needs a text"), str(all))
	assert_true(has.call("stone: 'cursed text' is for gear"), str(all))
	assert_true(has.call("ring is not cursed"), str(all))
	assert_true(has.call("plain_door: 'going text'"), str(all))
	assert_true(has.call("grumpy"), str(all))
	assert_true(has.call("no_such.value"), str(all))
