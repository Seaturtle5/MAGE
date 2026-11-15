extends GutTest
## List values (`~ add 1 to x.list`, `entry 1 of x.list`, `3 is listed in x.list`),
## doors locked and unlocked in play, typed numbers (`~ ask x.n as number from 0
## to 13: ...`), story children with a random gender and personality (`~ new
## child`), hooks instead of resting, talking or sex and after resting, and a
## sex change that keeps the cock's strain, an event made unresolved again, a
## character's portrait changed in play, an event that starts inactive, values
## every character has with their own change texts (`when raised:`), and a
## story's unbirth pregnancy.

const ROOT := "user://lists_doors_hooks_test_packs"

const PACK := """== values log
values:
    recipes: list
    names: list "Ann", "Bob"
    first: number
    picked: number
    length: number 0 (0 to 13)
    rested: number
    sighted: number
    ambush: flag
    pick: text

== pregnancy_rules standard
child genders:
    herm: 1
personalities: grumpy

== extend character nermine
stats:
    strength: 14
companion:
    tamed: no

== tag bottled
name: Bottled

== item water_bottle
name: water bottle
tags: bottled

== region town
name: Town

== location bunker
name: Bunker
description: A bunker.
region: town
map: 0,0
rest: bed
exits:
    north: cell, door cell_door

== location cell
name: Cell
description: A cell.
region: town
map: 0,1
exits:
    south: bunker, door cell_door

== door cell_door
name: Cell door
locked: yes
locked text: The cell door is locked.

== character angie
name: Angie
image: angie_plain
lives at: bunker
talk:
    Angie purrs hello.

== character nermine
name: Nermine
lives at: bunker

== hook angie_midnight
on: instead of talking to angie
when: log.sighted = 1
do:
    Angie asks about Midnight.

== hook nermine_package
on: instead of sex with nermine
do:
    Nermine wants the gemstones first.

== hook nala_prank
on: after resting
when: log.rested = 0
do:
    Alarm clocks ring all around you.
    ~ log.rested + 1 quietly

== hook werewolf
on: instead of resting
when: log.ambush
do:
    A werewolf pounces as you lie down.

== scene recipes
~ add 3 to log.recipes
~ add 1, 2 to log.recipes
~ add 2 to log.recipes if absent
Known: [log.recipes]; first [entry 1 of log.recipes], [count of log.recipes] in all.
if 2 is listed in log.recipes and 5 is not listed in log.recipes:
    Two but not five.
~ remove 2 from log.recipes
~ sort log.recipes
~ log.first = entry 1 of log.recipes
if log.recipes is not empty:
    Still [count of log.recipes in words].

== scene names
~ remove entry 1 from log.names
~ add "Cy" to log.names
Names: [log.names]; the first is [entry 1 of log.names].
if "Bob" is listed in log.names:
    Bob is here.

== scene ask_length
~ ask log.length as number from 0 to 13: Please enter a number from 0-13.
Length [log.length].

== scene adopt
~ new child
~ child.gender = random
~ child.personality = random
~ child.name = "Kit" quietly
~ record child

== values character
values:
    affection: number 0
        when raised: **[name of change.owner]'s affection for you increased by [change.amount]!**
        when lowered: **[name of change.owner] cools by [change.amount], now [change.value].**

== creature margay
name: Margay
form: vixen

== event canning
name: Canning facility
found by: nowhere
outcomes: raided
play:
    ~ outcome raided

== event dormant
name: Dormant
found by: nowhere
active: no
play:
    Nothing yet.

== form vixen
name: Vixen
sex: female
torso:
    description: furry
    change: you grow fur
cunt:
    count: 1
    depth: 6
    tightness: 4

== form buck
name: Buck
sex: male
cock:
    count: 1
    length: 8
    description: buck
"""

var game: Game


func before_each() -> void:
	game = Game.new(_load(ROOT, {"pack.fsc": "== pack p\nname: Test\n", "main.fsc": PACK, "values.fsc": TestPlayerValues.TEXT}), 3)
	game.start("bunker")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _load(root: String, files: Dictionary) -> ContentDB:
	DirAccess.make_dir_recursive_absolute(root + "/p")
	for name: String in files:
		var fa := FileAccess.open(root + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([root])
	if root == ROOT:
		assert_eq(db.errors(), [], "the pack loads without errors")
	return db


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
		elif e.type == "notice":
			out.append(str(e.text))
	return "\n".join(out)


func _saved() -> Game:
	var other := Game.new(game.content, 9)
	assert_true(other.load_dict(JSON.parse_string(JSON.stringify(game.save_dict()))))
	return other


func test_lists_add_remove_read_and_sort() -> void:
	game.runner.start("recipes")
	var text := _text()
	assert_string_contains(text, "Known: 3, 1, 2; first 3, 3 in all.", "adding keeps order; 'if absent' adds no second 2")
	assert_string_contains(text, "Two but not five.")
	assert_string_contains(text, "Still two.")
	assert_eq(game.value("log.recipes"), [1, 3], "removed and sorted")
	assert_eq(int(game.value("log.first")), 1)
	var other := _saved()
	assert_eq(other.value("log.recipes"), [1, 3], "a list is saved with its numbers")
	assert_true(Condition.evaluate(Condition.compile("3 is listed in log.recipes"), other))
	other.dispose()


func test_lists_of_texts_start_from_their_declaration() -> void:
	game.runner.start("names")
	var text := _text()
	assert_string_contains(text, "Names: Bob, Cy; the first is Bob.")
	assert_string_contains(text, "Bob is here.")
	game.apply(Effect.compile("clear log.names"))
	assert_true(Condition.evaluate(Condition.compile("log.names is empty"), game))
	assert_eq(game.content.values["log.names"].default, ["Ann", "Bob"], "the declaration's own list is never changed")


func test_a_list_shuffles_and_picks_with_the_games_random_numbers() -> void:
	game.apply(Effect.compile("add 1, 2, 3, 4, 5, 6 to log.recipes"))
	game.apply(Effect.compile("sort log.recipes in random order"))
	var shuffled: Array = game.value("log.recipes")
	assert_eq(shuffled.size(), 6)
	var sorted := shuffled.duplicate()
	sorted.sort()
	assert_eq(sorted, [1, 2, 3, 4, 5, 6], "the same entries")
	game.apply(Effect.compile("sort log.recipes in reverse order"))
	assert_eq(game.value("log.recipes"), [6, 5, 4, 3, 2, 1])
	game.apply(Effect.compile("log.picked = random entry of log.recipes"))
	assert_between(int(game.value("log.picked")), 1, 6)
	assert_eq(Expr.evaluate(Expr.parse("entry 9 of log.recipes"), game), null, "no ninth entry")


func test_a_door_is_unlocked_and_locked_in_play() -> void:
	var locked := Condition.compile("cell_door is locked")
	assert_true(Condition.evaluate(locked, game), "its locked: field")
	assert_false(game.runner.act("go", "north"))
	assert_string_contains(_text(), "The cell door is locked.")
	game.apply(Effect.compile("unlock cell_door"))
	assert_false(Condition.evaluate(locked, game))
	assert_true(Condition.evaluate(Condition.compile("cell_door is unlocked"), game))
	var other := _saved()
	assert_true(Condition.evaluate(Condition.compile("cell_door is not locked"), other), "kept in a save")
	other.dispose()
	assert_true(game.runner.act("go", "north"))
	assert_eq(game.state.location, "cell")
	game.apply(Effect.compile("lock cell_door"))
	assert_false(game.runner.act("go", "south"), "locked again")


func test_a_typed_number_is_asked_again_until_it_fits() -> void:
	game.runner.start("ask_length")
	var asks := game.take_output().filter(func(e): return e.type == "input")
	assert_eq(asks.size(), 1)
	assert_true(asks[0].number)
	assert_eq([asks[0].low, asks[0].high], [0, 13])
	assert_true(game.runner.enter_text("twelve"))
	assert_eq(game.runner.status, "input", "not a number: asked again")
	assert_string_contains(_text(), "Please enter a number from 0 to 13.")
	assert_true(game.runner.enter_text("14"))
	assert_eq(game.runner.status, "input", "out of range: asked again")
	var other := _saved()
	other.runner.run()
	assert_eq(int(other.take_output().filter(func(e): return e.type == "input")[0].high), 13, "a saved question keeps its range")
	other.dispose()
	_text()
	assert_true(game.runner.enter_text(" 11 "))
	assert_eq(game.value("log.length"), 11)
	assert_string_contains(_text(), "Length 11.")


func test_a_story_child_starts_blank_with_a_random_gender_and_personality() -> void:
	game.set_value("child.relationship", "wary")
	game.set_value("child.home", "bunker")
	game.runner.start("adopt")
	_text()
	var kids: Array = game.value("pregnancy.offspring")
	assert_eq(kids.size(), 1)
	assert_eq([kids[0].name, kids[0].gender, kids[0].personality], ["Kit", "herm", "grumpy"], "drawn from the pregnancy rules")
	assert_false(kids[0].has("relationship"), "the last child's values are gone")
	assert_false(kids[0].has("home"))


func test_hooks_instead_of_talking_and_sex() -> void:
	game.runner.show_location()
	var view: Dictionary = game.take_output().filter(func(e): return e.type == "location")[0]
	var nermine: Dictionary = view.people.filter(func(p): return p.id == "nermine")[0]
	assert_true(nermine.sex, "a hook adds sex to a character without its own")
	assert_false(nermine.talk)
	assert_true(game.runner.act("talk", "angie"))
	assert_string_contains(_text(), "Angie purrs hello.", "its own talk while the hook does not apply")
	game.set_value("log.sighted", 1)
	assert_true(game.runner.act("talk", "angie"))
	var text := _text()
	assert_string_contains(text, "Angie asks about Midnight.")
	assert_false(text.contains("purrs hello"), "instead of its own talk")
	assert_true(game.runner.act("sex", "nermine"))
	assert_string_contains(_text(), "Nermine wants the gemstones first.")
	assert_false(game.runner.act("talk", "nermine"), "no talk of its own and no hook for it")


func test_hooks_after_and_instead_of_resting() -> void:
	var turn := game.state.turn
	assert_true(game.runner.act("rest"))
	assert_string_contains(_text(), "Alarm clocks ring all around you.", "after the rest")
	assert_eq(game.state.turn, turn + 2)
	assert_true(game.runner.act("rest"))
	assert_false(_text().contains("Alarm clocks"), "its when: no longer holds")
	game.set_value("log.ambush", true)
	turn = game.state.turn
	assert_true(game.runner.act("rest"))
	var text := _text()
	assert_string_contains(text, "A werewolf pounces as you lie down.")
	assert_eq(game.state.turn, turn, "no rest happened")


func test_a_sex_change_keeping_the_cock_strain() -> void:
	game.set_value("player.body.cock", "vixen")
	game.apply(Effect.compile("sex change toward buck keeping cock"))
	assert_eq(int(game.value("player.cocks")), 1, "a cock appears")
	assert_eq(game.part_form("player", "cock"), "vixen", "with the strain the cock had")
	for key in ["cocks", "cock.length", "balls.size"]:
		game.set_value("player." + key, 0)
	game.apply(Effect.compile("sex change toward buck"))
	assert_eq(game.part_form("player", "cock"), "buck", "otherwise it takes the new strain, as in the original")
	assert_true(Effect.compile("breast change keeping cock").has("error"))


func test_an_event_is_made_unresolved_again() -> void:
	game.runner.start_event("canning")
	_text()
	assert_true(game.adjective("canning", "resolved"))
	game.apply(Effect.compile("unresolve canning"))
	assert_false(game.adjective("canning", "resolved"), "it can be found again")
	assert_true(Condition.evaluate(Condition.compile("canning outcome is raided"), game), "its outcome stays, as in the original")
	var other := _saved()
	assert_false(other.adjective("canning", "resolved"), "kept in a save")
	other.dispose()


func test_an_event_starting_inactive_reads_so_until_activated() -> void:
	assert_false(game.adjective("dormant", "active"), "active: no holds before anything touches the event")
	assert_true(game.adjective("canning", "active"))
	game.apply(Effect.compile("activate dormant"))
	assert_true(game.adjective("dormant", "active"))
	var other := _saved()
	assert_true(other.adjective("dormant", "active"), "kept in a save")
	assert_eq(typeof(other.state.events.dormant.last_turn), TYPE_INT, "its numbers stay whole numbers after loading")
	other.dispose()


func test_a_portrait_changes_in_play() -> void:
	game.apply(Effect.compile("character angie image angie_rubber"))
	game.runner.act("talk", "angie")
	var title: Dictionary = game.take_output().filter(func(e): return e.type == "title")[0]
	assert_eq(title.image, "angie_rubber")
	var other := _saved()
	other.runner.show_location()
	var view: Dictionary = other.take_output().filter(func(e): return e.type == "location")[0]
	assert_eq(view.people.filter(func(p): return p.id == "angie")[0].image, "angie_rubber", "kept in a save")
	other.dispose()
	game.apply(Effect.compile("character angie image default"))
	assert_eq(game.character_image("angie"), "angie_plain")


func test_a_part_goes_back_to_a_form_kept_in_a_value() -> void:
	game.apply(Effect.compile("transform torso into vixen"))
	game.set_value("log.pick", str(game.value("player.body.torso")))
	game.set_value("player.body.torso", "human")  # the curse's change at night
	game.apply(Effect.compile("transform torso into log.pick"))
	assert_eq(game.part_form("player", "torso"), "vixen", "back to the kept form")
	game.set_value("log.pick", "")
	game.apply(Effect.compile("transform torso into log.pick"))
	assert_eq(game.part_form("player", "torso"), "vixen", "an empty value changes nothing")


func test_an_extension_can_give_a_character_stats_and_a_companion_block() -> void:
	assert_eq(int(game.value("nermine.strength")), 14, "declared by the extension's stats:")
	assert_true(game.content.values.has("nermine.damage"), "the companion block's fighting numbers")
	assert_eq(game.value("nermine.tamed"), false)


func test_a_time_value_moves_earlier_or_later() -> void:
	game.apply(Effect.compile("nermine.last_sex earlier by 2 turns"))
	assert_false(game.state.stamps.has("nermine.last_sex"), "never set: stays never")
	game.apply(Effect.compile("nermine.last_sex = now"))
	var t := int(game.state.stamps["nermine.last_sex"])
	game.apply(Effect.compile("nermine.last_sex earlier by 2 turns"))
	assert_eq(int(game.state.stamps["nermine.last_sex"]), t - 2)
	game.apply(Effect.compile("nermine.last_sex later by 5 turns"))
	assert_eq(int(game.state.stamps["nermine.last_sex"]), t + 3)


func test_known_places_are_counted() -> void:
	var before := int(game.value("places.known"))
	game.apply(Effect.compile("discover cell"))
	assert_eq(int(game.value("places.known")), before + 1)
	game.apply(Effect.compile("forget cell"))
	assert_eq(int(game.value("places.known")), before)


func test_a_carried_item_is_chosen_by_its_tag() -> void:
	var has := Condition.compile("player has an item tagged bottled")
	game.state.inventory.erase("water_bottle")
	assert_false(Condition.evaluate(has, game))
	game.apply(Effect.compile("ask log.pick as item tagged bottled: Which bottle?"))
	assert_eq(str(game.value("log.pick")), "", "nothing to choose: empty, no question")
	game.state.inventory["water_bottle"] = 2
	assert_true(Condition.evaluate(has, game))
	assert_false(Condition.evaluate(Condition.compile("player does not have an item tagged bottled"), game))
	game.apply(Effect.compile("ask log.pick as item tagged bottled: Which bottle?"))
	var asked: Dictionary = game.take_output().filter(func(e): return e.type == "choices")[-1]
	assert_eq(asked.title, "Which bottle?")
	assert_eq(asked.options.map(func(o): return o.text), ["water bottle", "Nevermind"])
	assert_true(game.runner.choose(0))
	assert_eq(str(game.value("log.pick")), "water_bottle")
	game.apply(Effect.compile("take log.pick"))
	assert_eq(int(game.state.inventory.get("water_bottle", 0)), 1, "~ take with the value that holds the item")


func test_pronouns_change_in_play_and_can_follow_the_body() -> void:
	game.apply(Effect.compile("character angie pronouns he"))
	assert_eq(game.pronoun("angie", "He"), "He")
	assert_eq(game.pronoun("angie", "his"), "his")
	var other := _saved()
	assert_eq(other.pronoun("angie", "him"), "him", "kept in a save")
	other.dispose()
	game.apply(Effect.compile("character angie pronouns by body"))
	game.state.values["angie.cocks"] = 1
	game.state.values["angie.cunts"] = 0
	assert_eq(game.pronoun("angie", "he"), "he", "only a cock")
	game.state.values["angie.cunts"] = 1
	assert_eq(game.pronoun("angie", "he"), "she", "a cunt")
	game.state.values["angie.cocks"] = 0
	game.state.values["angie.cunts"] = 0
	assert_eq(game.pronoun("angie", "he"), "they", "neither")
	game.apply(Effect.compile("character angie pronouns default"))
	assert_eq(game.pronoun("angie", "he"), game.pronoun("angie", "he"))
	assert_false(game.state.values.has("character.angie.pronouns"))


func test_values_every_character_has_and_their_change_texts() -> void:
	assert_eq(int(game.value("nermine.affection")), 0, "every character has it")
	game.apply(Effect.compile("nermine.affection + 3 up to 100"))
	assert_eq(_text(), "**Nermine's affection for you increased by 3!**".replace("**", ""))
	assert_eq(int(game.value("nermine.affection")), 3)
	game.apply(Effect.compile("angie.affection - 2"))
	assert_eq(_text(), "Angie cools by 2, now -2.")
	game.apply(Effect.compile("angie.affection + 1 quietly"))
	assert_eq(_text(), "", "quietly says nothing")
	assert_null(game.value("change.owner"), "the change values are gone afterwards")


func test_a_story_unbirth_pregnancy_of_a_named_creature() -> void:
	game.apply(Effect.compile("unbirth pregnancy of margay"))
	assert_true(game.adjective("player", "pregnant"))
	assert_eq(game.value("pregnancy.unbirth"), "margay")
	assert_eq(game.value("pregnancy.father"), "vixen", "the creature's strain")


func test_the_new_forms_are_validated() -> void:
	var bad := """== values log
values:
    count: number
    words: text
    mood: calm, angry
== door gate
name: Gate
== scene s
~ add 1 to log.count
~ log.count = entry 1 of log.mood
~ ask log.words as number from 1 to 3: How many?
~ unlock nowhere_door
~ unresolve nowhere_event
~ character nobody_here image x
~ unbirth pregnancy of nothing_at_all
if gate is open:
    Hm.
if log.count is empty:
    Hm.
if 1 is listed in log.words:
    Hm.
== hook h
on: instead of talking to nobody
do:
    Hi.
"""
	var db := _load(ROOT + "_bad", {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad, "values.fsc": TestPlayerValues.TEXT})
	var text := str(db.errors())
	for part in ["log.count is not a list", "log.mood is not a list", "must be a number value", "nowhere_door",
			"A door is", "not a number", "log.words is not a list", "nobody", "nowhere_event", "nobody_here", "nothing_at_all"]:
		assert_string_contains(text, part)
