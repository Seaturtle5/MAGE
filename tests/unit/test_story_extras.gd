extends GutTest
## Small story features (StorySystem and friends): fights away from a creature's
## usual place, a rest from a scene, a random event of a kind, arrival events for a
## whole area, items any character can be given, discovering and resolving by flag
## and tag, level options with a condition, `instead of using` hooks, scents on doors
## and scenery, scripts for every companion, and values of mixed kinds.

const ROOT := "user://story_extras_packs"

const STATS := """hp: 30
level: 1
damage: 2
stats: strength 10, dexterity 10, stamina 10, perception 10, intelligence 10, charisma 10
"""

const PACK := """== values tally
values:
    n: number 0
    seen: flag

== values wolf
values:
    met: number

== tag dream
name: Dream

== tag landmark_event
name: Landmark event

== feat insomniac
name: Insomniac

== condition rested
name: Rested

== rest_rules rules
condition: rested
refreshed:
    You feel refreshed.

== smell_rules smells
smelling: You sniff the [name of smell.thing].
no scent: It smells pretty normal.
no place scent: This place smells as you'd expect.

== level ovi
name: Eggs
default: standard
options:
    none: Never eggs.
    standard: Eggs when the creature lays them.
    always: Always eggs.
        when: tally.n > 5

== region north_side
name: North Side

== zone woods
name: Woods

== location den
name: Den
description: A den.
region: north_side
zone: woods
flags: landmark
rest: cot
scent: Musty fur.
exits:
    north: glade
    east: hall, door oak_door
scenery scents:
    * Old stove
        It smells of soot.
    * Hidden nook [if tally.n > 5]
        It smells of secrets.

== location glade
name: Glade
description: A glade.
region: north_side
zone: woods
exits:
    south: den

== location hall
name: Hall
description: A hall.
flags: landmark, private
exits:
    west: den, door oak_door

== location cellar
name: Cellar
description: A cellar.

== door oak_door
name: Oak Door
scent: It smells of oak and old varnish.

== event woods_welcome
name: Woods Welcome
found by: walking into any place in woods
repeat: always
play:
    The woods welcome you.

== event north_hello
name: North Hello
found by: arriving at any place in north_side
requires: tally.n > 50
repeat: always
play:
    Hello from the north.

== event sweet_dream
name: Sweet Dream
found by: nowhere
tags: dream
play:
    A sweet dream.

== event bad_dream
name: Bad Dream
found by: nowhere
active: no
tags: dream
play:
    A bad dream.

== event later_dream
name: Later Dream
found by: nowhere
tags: dream
requires: tally.n > 5
play:
    A later dream.

== event landmark_found
name: Landmark found
found by: nowhere
tags: landmark_event
play:
    Found it.

== scene dreaming
~ pick random event tagged dream
if an event is picked:
    Dream: [name of picked.event][if picked.event is tagged dream], a dream[end if].
    play picked event
    After the dream.
else:
    No dreams.

== scene ambush
fight wolf away from home:
    won:
        [if fight is away from home]Still away.[else]Back home.[end if]

== scene meeting
fight wolf:
    won:
        Won at home.

== scene train
~ companion.xp + 5 quietly

== creature wolf
name: Wolf
found in: nowhere
%s
encounter:
    [if fight is away from home]A wolf far from its woods.[else]A wolf in its woods.[end if]
defeated:
    The wolf runs [if fight is away from home]off somewhere[else]into the trees[end if].

== character ann
name: Ann
lives at: den

== character bob
name: Bob
lives at: den
gift tags: flower
gift:
    Bob takes the [name of gift.item].
    ~ take gift.item

== character rex
name: Rex
lives at: glade
companion:
    tamed: yes

== character mia
name: Mia
lives at: glade
companion:
    tamed: no

== item lust_potion
name: lust potion
description: A potion.
given:
    You give the lust potion to [name of gift.to].
    ~ gift.to.last_sex earlier by 8 turns
    if since gift.to.last_sex >= 8 turns:
        They look ready.
    ~ take gift.item

== item flower
name: flower
description: A flower.
tags: flower

== tag flower
name: Flower

== item bandage
name: bandage
description: A bandage.
use:
    You wrap it yourself.

== hook paula_wraps
on: instead of using bandage
when: tally.n > 5
do:
    Paula wraps it for you.
""" % STATS

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


func _win() -> void:
	assert_eq(game.runner.status, "combat")
	game.state.combat.result = "won"
	game.runner._finish_fight()
	game.runner.run()


func test_a_fight_away_from_home_changes_the_creatures_texts_until_it_is_over() -> void:
	game.runner.start("ambush")
	assert_true(game.value("encounter.away_from_home") == true)
	_win()
	var said := _said()
	assert_string_contains(said, "A wolf far from its woods.")
	assert_string_contains(said, "The wolf runs off somewhere.")
	assert_string_contains(said, "Back home.", "the flag ends with the creature's own texts")
	game.runner.start("meeting")
	_win()
	said = _said()
	assert_string_contains(said, "A wolf in its woods.")
	assert_string_contains(said, "The wolf runs into the trees.")


func test_a_rest_from_a_scene_heals_and_refreshes_without_time() -> void:
	game.set_value("player.hp", 1)
	game.set_value("player.fatigue", 4)
	var turn := game.state.turn
	game.apply(Effect.compile("rest"))
	assert_eq(int(game.value("player.hp")), 20, "a cot: the better of a quarter of health and stamina (19), up to the top")
	assert_eq(int(game.value("player.fatigue")), -2, "fresh again")
	assert_true(game.state.conditions.has("rested"))
	assert_string_contains(_said(), "You feel refreshed.")
	assert_eq(game.state.turn, turn, "no time passes")
	game.go_to("glade")
	game.set_value("player.hp", 1)
	game.apply(Effect.compile("rest"))
	assert_eq(int(game.value("player.hp")), 6, "no bedding: the lower of the two (a quarter of 20)")


func test_a_random_event_of_a_kind_is_picked_and_played_in_place() -> void:
	game.runner.start("dreaming")
	var said := _said()
	assert_true(said.find("Dream: Sweet Dream, a dream.") < said.find("A sweet dream.") and said.find("A sweet dream.") < said.find("After the dream."), said)
	assert_true(game.adjective("sweet_dream", "resolved"), "found once, as when exploring")
	game.runner.start("dreaming")
	assert_string_contains(_said(), "No dreams.", "the inactive and unready dreams are never picked")
	game.set_value("tally.n", 6)
	game.runner.start("dreaming")
	assert_string_contains(_said(), "A later dream.")


func test_arrival_events_for_a_whole_area() -> void:
	game.go_to("hall")
	game.take_output()
	assert_true(game.runner.act("go", "west"))
	assert_string_contains(_said(), "The woods welcome you.", "walking into a place of the zone")
	game.pass_turn()  # an arrival event comes up once a turn at most
	game.take_output()
	assert_true(game.runner.act("go", "north"))
	var said := _said()
	assert_string_contains(said, "The woods welcome you.", "any place of it")
	assert_false(said.contains("Hello from the north"), "its requirement does not hold")
	assert_true(StorySystem.in_area(game, "glade", "north_side"), "a region counts too")
	assert_false(StorySystem.in_area(game, "hall", "woods"))


func test_an_item_any_character_can_be_given() -> void:
	assert_false(game.runner.can_give("ann"), "nothing to give her")
	assert_false(game.runner.can_give("bob"), "nothing he takes")
	game.apply(Effect.compile("give lust_potion"))
	game.apply(Effect.compile("give flower"))
	game.state.stamps["ann.last_sex"] = game.state.turn
	game.take_output()
	assert_true(game.runner.can_give("ann"))
	assert_true(game.runner.act("give", "ann"))
	assert_eq(_choices(), ["lust potion", "Nevermind"], "she takes only what anyone can be given")
	game.runner.choose(0)
	var said := _said()
	assert_string_contains(said, "You give the lust potion to Ann.")
	assert_string_contains(said, "They look ready.", "gift.to.last_sex is hers")
	assert_eq(int(game.state.stamps["ann.last_sex"]), game.state.turn - 8)
	assert_eq(ItemSystem.count(game, "lust_potion"), 0)
	game.apply(Effect.compile("give lust_potion"))
	game.take_output()
	assert_true(game.runner.act("give", "bob"))
	assert_eq(_choices(), ["flower", "lust potion", "Nevermind"], "his own gifts and the potion")
	game.runner.choose(0)
	assert_string_contains(_said(), "Bob takes the flower.")
	assert_true(game.runner.act("give", "bob"))
	game.runner.choose(0)
	assert_string_contains(_said(), "You give the lust potion to Bob.", "the potion's own script")


func test_every_place_with_a_flag_and_every_event_with_a_tag() -> void:
	game.state.known.clear()
	game.apply(Effect.compile("discover every place flagged landmark"))
	assert_true(game.state.known.has("den") and game.state.known.has("hall"))
	assert_false(game.state.known.has("glade"))
	assert_string_contains(_said(), "Discovered: Den, Hall")
	game.apply(Effect.compile("discover every place flagged landmark quietly"))
	assert_eq(_said(), "", "nothing new")
	game.state.known.clear()
	game.apply(Effect.compile("discover every place flagged landmark but not private quietly"))
	assert_true(game.state.known.has("den"))
	assert_false(game.state.known.has("hall"), "but not the private one")
	game.apply(Effect.compile("resolve every event tagged landmark_event"))
	assert_true(game.adjective("landmark_found", "resolved"))
	assert_false(game.adjective("sweet_dream", "resolved"))


func test_a_level_option_waits_for_its_condition() -> void:
	var options: Array = game.content_settings().levels[0].options
	assert_eq(options.map(func(o): return o.available), [true, true, false])
	assert_false(game.choose_level("ovi", "always"), "not open to the player yet")
	assert_eq(game.level("ovi"), "standard")
	assert_true(game.choose_level("ovi", "none"))
	game.apply(Effect.compile("level ovi = always"))
	assert_eq(game.level("ovi"), "always", "a story can set it")
	game.set_level("ovi", "standard")
	game.set_value("tally.n", 6)
	assert_true(game.choose_level("ovi", "always"))


func test_an_instead_of_using_hook_replaces_the_use_text() -> void:
	game.apply(Effect.compile("give bandage 2"))
	game.take_output()
	assert_true(game.runner.act("use", "bandage"))
	assert_string_contains(_said(), "You wrap it yourself.")
	game.set_value("tally.n", 6)
	assert_true(game.runner.act("use", "bandage"))
	var said := _said()
	assert_string_contains(said, "Paula wraps it for you.")
	assert_false(said.contains("You wrap it yourself."))
	assert_eq(ItemSystem.count(game, "bandage"), 0, "used up both times")


func test_doors_and_scenery_have_scents() -> void:
	assert_true(game.runner.act("smell_place", ""))
	assert_eq(_choices(), ["Den", "Oak Door", "Old stove", "Nevermind"], "the hidden nook's condition does not hold")
	game.runner.choose(1)
	var said := _said()
	assert_string_contains(said, "You sniff the Oak Door.")
	assert_string_contains(said, "It smells of oak and old varnish.")
	assert_eq(str(game.value("smell.kind")), "door")
	assert_true(game.runner.act("smell_place", ""))
	game.runner.choose(2)
	said = _said()
	assert_string_contains(said, "You sniff the Old stove.")
	assert_string_contains(said, "It smells of soot.")
	assert_true(game.runner.act("smell_place", ""))
	game.runner.choose(0)
	assert_string_contains(_said(), "Musty fur.")
	game.go_to("cellar")
	game.take_output()
	assert_true(game.runner.act("smell_place", ""))
	assert_eq(_choices(), [], "nothing else to smell: the place at once")
	assert_string_contains(_said(), "This place smells as you'd expect.")


func test_scripts_for_every_tamed_or_every_companion() -> void:
	game.apply(Effect.compile("tame rex"))
	game.apply(Effect.compile("untame mia"))
	game.apply(Effect.compile("for each tamed companion play train"))
	assert_eq([CompanionSystem.num(game, "rex", "xp"), CompanionSystem.num(game, "mia", "xp")], [5, 0])
	game.apply(Effect.compile("for all companions play train"))
	assert_eq([CompanionSystem.num(game, "rex", "xp"), CompanionSystem.num(game, "mia", "xp")], [10, 5])


func test_values_of_mixed_kinds_compare_without_errors() -> void:
	game.set_value("wolf.met", true)
	assert_eq(game.value("wolf.met"), 1, "a yes stored in a number value is 1")
	assert_true(Condition.evaluate(Condition.compile("wolf.met = 1"), game))
	game.set_value("wolf.met", false)
	assert_false(game.state.values.has("wolf.met"), "back to its default")
	game.set_value("tally.seen", 1)
	assert_eq(game.value("tally.seen"), true, "a number stored in a flag is yes or no")
	game.apply(Effect.compile("sex player receives oral_cock from wolf"))
	assert_eq(game.value("wolf.met"), 1, "the sex record marks a creature met in its own number")
	assert_true(Condition.compare(true, "=", 1, {}, null))
	assert_false(Condition.compare(false, "=", 1, {}, null))
	assert_false(Condition.same([], 0))


func test_the_validator_reports_the_new_forms() -> void:
	var bad := """== feat real_feat
name: Real

== form fox
name: Fox
head:
    description: a fox head

== scene s
if player has feat real_fet:
    Typo.
~ feat + real_fet
~ transform head into fox
~ transform tail into fox
~ transform skin into foxx
if fight is near home:
    No.
~ pick random event tagged nothing_like_it
~ discover every place flagged nowhere_flag
~ for all companions play missing_scene
~ gift.to.no_such_value + 1

== event e
found by: walking into any place in nowhere_zone

== level lv
name: L
default: b
options:
    a: A.
    b: B.
        when: player.level > 2
"""
	var db := _load(bad, ROOT + "_bad")
	var errors: Array = db.diagnostics.filter(func(d): return d.severity == "error").map(func(d): return "%d %s" % [d.line, d.message])
	var has := func(fragment: String) -> bool: return errors.any(func(m: String) -> bool: return fragment in m)
	assert_true(has.call("Feat 'real_fet' does not exist. Did you mean 'real_feat'?"), str(errors))
	assert_true(has.call("Form 'fox' has no tail"), str(errors))
	assert_true(has.call("Form 'foxx' does not exist. Did you mean 'fox'?"), str(errors))
	assert_false(has.call("has no head"), "the fox has a head")
	assert_true(has.call("Use 'fight is away from home'"), str(errors))
	assert_true(has.call("No event has the tag 'nothing_like_it'"), str(errors))
	assert_true(has.call("No place has the flag 'nowhere_flag'"), str(errors))
	assert_true(has.call("missing_scene"), str(errors))
	assert_true(has.call("no character has a value 'no_such_value'"), str(errors))
	assert_true(has.call("'nowhere_zone' is neither a zone nor a region"), str(errors))
	assert_true(has.call("Option b is the default of level lv"), str(errors))
	assert_eq(errors.filter(func(m: String) -> bool: return "real_fet" in m).size(), 2, "the condition and the effect")
