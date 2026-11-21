extends GutTest
## A creature's encounter plays as a scene before its fight: it can set values
## and flags, and conditions can read them on the next meeting.

const ROOT := "user://encounter_test_packs"

const PACK := """== values wolf
values:
    met: number

== location den
name: Den
description: A dark den.

== creature wolf
name: Wolf
hp: 10
level: 1
damage: 1
encounter:
    if wolf.met = 0:
        A wolf you have never seen before blocks the path.
        ~ wolf.met + 1 quietly
    else:
        The wolf is back.

== creature fox
name: Fox
hp: 5
form: fox

== form fox
name: Fox
head:
    description: a fox's head
    change: your face stretches into a fox's muzzle
torso:
    description: a fox's body
    change: your body turns lean and fox-like
skin:
    description: red fur
    change: red fur spreads over you

== zone plains
name: Plains

== creature jackal
name: Jackal
hp: 5
found in: nowhere
infectious: no
encounter:
    A jackal slinks closer.
victory:
    The jackal leaves you to a fox.
    ~ this fight infects as fox

== creature hare
name: Hare
hp: 3
encounter:
    The hare waves and hops away.
    ~ no fight

== creature crow
name: Crow
hp: 3
attack: -> crow_pecks

== scene crow_pecks
[if wolf.met > 5]The crow ignores you.[else]The crow pecks at you.[end if]
~ libido + 2 quietly

== text crow_mood
if wolf.met > 5:
    calm
else:
    restless

== tag canine
name: Canine

== location field
name: Field
description: An open field.
zone: plains

== creature coyote
name: Coyote
hp: 5
found in: plains
tags: canine
form: fox
victory:
    The coyote has its way with you.

== creature lark
name: Lark
hp: 2
found in: plains

== scene heat_hunt
~ pick random creature tagged canine nearby
if a creature is picked:
    You find a [picked creature], and [ghe] finds you.
    play picked creature victory
    ~ infect picked creature
else:
    Nothing canine is around.

== scene rampage
play rampage_round 3 times
~ transform skin into fox

== scene rampage_some
play rampage_round 2 to 4 times

== scene rampage_round
~ wolf.met + 1 quietly
~ pick random creature nearby or outside
Round.

== scene meet_wolf
fight wolf:
    won:
        You won.
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "wolf.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 1)
	game.start("den")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func test_encounter_sets_a_value_then_the_fight_starts() -> void:
	game.runner.start_encounter("wolf")
	assert_string_contains(_text(), "never seen before")
	assert_eq(int(game.value("wolf.met")), 1)
	assert_eq(game.runner.status, "combat", "the fight starts after the encounter")
	assert_eq(str(game.state.combat.creature), "wolf")


func test_a_scene_fight_plays_the_encounter_first() -> void:
	game.set_value("wolf.met", 1)
	game.runner.start("meet_wolf")
	assert_string_contains(_text(), "The wolf is back.")
	assert_eq(int(game.value("wolf.met")), 1, "the second meeting does not count again")
	assert_eq(game.runner.status, "combat")


func test_a_loss_scene_can_name_the_creature_that_infects() -> void:
	game.set_value("player.hp", 0)  # the fight is lost at once
	game.runner.start_encounter("jackal")
	assert_string_contains(_text(), "leaves you to a fox")
	var changed := false
	for part in ["head", "torso", "skin"]:
		changed = changed or game.part_form("player", part) == "fox"
	assert_true(changed, "the jackal does not infect, so the fox it named did")
	assert_true(Effect.compile("this fight infects as fox").op == "infects_as")


func test_infection_can_keep_the_players_sex() -> void:
	var e := Effect.compile("infect fox 3 times keeping sex")
	assert_true(e.keep_sex)
	assert_false(Effect.compile("infect fox").keep_sex)


func test_in_an_event_is_false_outside_events() -> void:
	assert_false(Condition.evaluate(Condition.compile("player is in an event"), game))
	assert_true(Condition.evaluate(Condition.compile("player is not in an event"), game))


func test_a_creature_is_met_once_fought() -> void:
	var met := Condition.compile("wolf is met")
	assert_false(Condition.evaluate(met, game))
	game.runner.start_encounter("wolf")
	assert_true(Condition.evaluate(met, game))


func test_purity_means_one_strain_for_the_main_parts() -> void:
	assert_true(Condition.evaluate(Condition.compile("player is pure"), game), "all human")
	game.apply(Effect.compile("transform into fox"))
	assert_true(Condition.evaluate(Condition.compile("player is pure"), game), "the fox form describes no tail or cock, so those do not count")
	game.set_value("player.body.head", "human")
	assert_false(Condition.evaluate(Condition.compile("player is pure"), game), "a human head on a fox body")


func test_strip_text_with_nothing_worn() -> void:
	assert_eq(ItemSystem.strip_text(game, ["waist", "legs", "crotch"], "pull down", "crotch", "stroke over your bare crotch"), "stroke over your bare crotch")


func test_a_text_field_can_hand_over_to_a_text_scene() -> void:
	var paras: Array = game.runner.render_paragraphs(game.content.program("crow#attack"))
	assert_eq(paras.size(), 1)
	assert_eq(TextTemplate.plain(paras[0]), "The crow pecks at you.")



func test_play_can_move_a_creature_into_a_zone_and_make_it_infectious() -> void:
	assert_false("jackal" in game.runner.encounter_pool("plains"))
	game.apply(Effect.compile("creature jackal found in plains"))
	assert_true("jackal" in game.runner.encounter_pool("plains"))
	assert_eq(game.creature_field("jackal", "infectious", "yes"), "no")
	game.apply(Effect.compile("creature jackal infectious yes"))
	assert_eq(game.creature_field("jackal", "infectious", "yes"), "yes")
	game.apply(Effect.compile("creature jackal found in nowhere"))
	assert_false("jackal" in game.runner.encounter_pool("plains"))


func test_a_text_snippet_can_choose_its_lines() -> void:
	assert_eq(game.describe("crow_mood"), "restless")
	game.state.values["wolf.met"] = 9
	assert_eq(game.describe("crow_mood"), "calm")


func test_an_encounter_can_pick_the_creatures_gender() -> void:
	game.runner.start_encounter("jackal")
	game.apply(Effect.compile("creature jackal gender female"))
	assert_eq(game.monster_word("ghe"), "she")
	game.apply(Effect.compile("creature jackal gender male"))
	assert_eq(game.monster_word("ghis"), "his")


func test_an_encounter_can_end_without_a_fight() -> void:
	game.runner.start_encounter("hare")
	assert_string_contains(_text(), "hops away")
	assert_true(game.state.combat.is_empty(), "no fight started")
	assert_eq(game.runner.status, "idle")


func test_an_attack_text_can_change_values_as_it_lands() -> void:
	var before := int(game.value("player.libido"))
	game.runner.render_paragraphs(game.content.program("crow#attack"))
	assert_eq(int(game.value("player.libido")), before, "showing the text alone changes nothing")
	game.runner.render_paragraphs(game.content.program("crow#attack"), 0, true)
	assert_eq(int(game.value("player.libido")), before + 2, "the landed attack runs its effects")


func test_a_scene_picks_a_random_creature_of_the_zone_by_tag() -> void:
	game.runner.start("heat_hunt")
	assert_string_contains(_text(), "Nothing canine is around.", "the den has no zone and the outside has no canines")
	game.go_to("field")
	game.take_output()
	game.runner.start("heat_hunt")
	var text := _text()
	assert_string_contains(text, "You find a coyote, and it finds you.")
	assert_string_contains(text, "The coyote has its way with you.")
	assert_eq(game.part_form("player", "torso") != "human" or game.part_form("player", "head") != "human" or game.part_form("player", "skin") != "human", true, "infected with the coyote's form")
	assert_true(Effect.compile("pick random creature tagged canine in plains favoring coyote").favoring == ["coyote"])


func test_a_scene_can_be_played_a_set_number_of_times_and_set_one_part() -> void:
	game.runner.start("rampage")
	assert_eq(int(game.value("wolf.met")), 3)
	assert_eq(_text().count("Round."), 3)
	assert_eq(game.part_form("player", "skin"), "fox")
	assert_eq(game.part_form("player", "head"), "human", "only that part changes")
	game.runner.start("rampage_some")
	var n := _text().count("Round.")
	assert_true(n >= 2 and n <= 4, str(n))


func test_pick_random_creature_as_a_meeting_parses() -> void:
	var e := Effect.compile("pick random creature nearby as a meeting")
	assert_true(e.meeting, "weighted as a random meeting")
	e = Effect.compile("pick random creature nearby favoring wolf, fox as a meeting")
	assert_eq(e.favoring, ["wolf", "fox"])
	assert_true(e.meeting)
	assert_false(Effect.compile("pick random creature nearby").meeting)
