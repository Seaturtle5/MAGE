extends GutTest
## Hunting by a typed name (`by name: yes` in the hunting rules): a place, an
## event or a creature, the search for it, and the answers when it cannot be
## hunted.

const ROOT := "user://hunt_by_name_test_packs"

const WORLD := """== zone woods
name: Woods

== zone hills
name: Hills

== location camp
name: Camp
description: A camp.
zone: woods
flags: fast travel

== location tower
name: Old Tower
description: A tower.
zone: none
flags: fast travel

== location lake
name: Still Lake
description: A lake.
zone: none
flags: fast travel

== location vault
name: Hidden Vault
description: A vault.
zone: none
flags: fast travel, private

== location shed
name: Tool Shed
description: A shed.
zone: none

== tag slimy
name: Slimy

== filter slimy
name: Slimy things

== feat pathfinder
name: Pathfinder

== feat keen
name: Keen

== feat keyholder
name: Keyholder

== feat crowded
name: Crowded

== creature fox
name: Fox
found in: woods
level: 1
hp: 5
damage: 1

== creature owl
name: Barn Owl
title: Night Bird
found in: woods
active: night
level: 1
hp: 5
damage: 1

== creature bear
name: Bear
found in: hills
level: 1
hp: 5
damage: 1

== creature slug
name: Slug
found in: woods
tags: slimy
level: 1
hp: 5
damage: 1

== creature ghost
name: Ghost Fox
found in: nowhere
level: 1
hp: 5
damage: 1

== event lost_hiker
name: Lost Hiker
found by: exploring in woods
play:
    A HIKER WAVES

== event far_cry
name: Far Cry
found by: exploring in hills
play:
    A CRY

== event old_debt
name: Old Debt
found by: exploring in woods
active: no
play:
    A DEBT

== event steep_climb
name: Steep Climb
found by: exploring in woods
level: 5
play:
    A CLIMB

== event locked_door
name: Locked Door
found by: exploring in woods
requires: player has feat keyholder
play:
    A DOOR

== event doorstep
name: Doorstep
found by: walking into tower
play:
    A STEP

== event fox
name: Fox Den
found by: exploring in woods
repeat: always
play:
    A DEN

== feat herdmate
name: Herdmate

== feat marked
name: Marked

== form fox
name: Fox
tail:
    description: a fox's tail
    change: a tail grows

== combat_rules test
creature chance: 0 in 20
creature chance modifiers:
    player has feat keen: + 20
kindred when: player has feat herdmate
kindred parts: torso, tail

== hook the_owl_hunts_the_marked
on: hunting
when: player has feat marked
do:
    ~ hunt may meet bear 50 times

== survival_rules test
rescue after: 1000
"""

const RULES := """== hunt_rules test
by name: yes
events listed when: player has feat pathfinder
others when: player has feat crowded
kindred when: player has feat herdmate
kindred chance: 1 in 1
tracks: TRACKS OF [hunt.name]
searching: SEARCHING FOR [hunt.name]
search bonus: 0
search bonus modifiers:
    player has feat keen: + 100
search target: 100
search label: Perception
search certain when: player has feat pathfinder
place found: REACHED [hunt.name]
event found: CAME UPON [hunt.name]
place not found: NO PLACE
event not found: NO EVENT
search fight: SOMEONE ON THE WAY
nothing found: NO SUCH THING AS [hunt.name]
wrong time: WRONG TIME
wrong area: WRONG AREA
creature banned: BANNED CREATURE
place hidden: HIDDEN PLACE
place unreachable: UNREACHABLE PLACE
search failed: SEARCH FAILED
event elsewhere: EVENT ELSEWHERE
event too hard: EVENT TOO HARD
event resolved: EVENT RESOLVED
event not ready: EVENT NOT READY
event inactive: EVENT INACTIVE
"""

var game: Game


func _load(rules: String) -> ContentDB:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "world.fsc": WORLD, "rules.fsc": rules}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	return db


func _start(rules: String = RULES) -> void:
	if game != null:
		game.dispose()
	var db := _load(rules)
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("camp")
	game.set_value("player.hp", 100)
	while not game.is_day():
		game.pass_turn()
	game.take_output()


func before_each() -> void:
	_start()


func after_each() -> void:
	game.dispose()
	game = null


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
		elif e.type == "title":
			out.append("[title] " + str(e.text))
		elif e.type == "roll":
			out.append("[roll]")
	return "\n".join(out)


func _actions() -> Array:
	game.take_output()
	game.runner.show_location()
	for e in game.take_output():
		if e.type == "location":
			return e.actions.map(func(a): return a.id)
	return []


func test_without_by_name_a_typed_hunt_is_refused() -> void:
	_start("== hunt_rules test\ntarget weight: 1\nothers when: player has feat crowded\n")
	assert_false(game.runner.act("hunt_name", "fox"), "the rules do not allow hunting by name")
	assert_true(game.runner.act("hunt", "fox"), "the list still works")


func test_hunt_is_offered_where_there_is_a_zone() -> void:
	assert_has(_actions(), "hunt")
	game.go_to("tower")
	assert_does_not_have(_actions(), "hunt", "no zone: nothing to hunt in")
	assert_false(game.runner.act("hunt_name", "fox"))


func test_a_creature_by_its_whole_name() -> void:
	var turn: int = game.state.turn
	assert_true(game.runner.act("hunt_name", "  FOX "), "case and spaces do not matter")
	var text := _text()
	assert_string_contains(text, "TRACKS OF fox")
	assert_string_contains(text, "[title] Encounter: Fox")
	assert_true(Condition.evaluate(Condition.compile("player is hunting"), game), "it counts as a hunt for that creature")
	assert_eq(game.state.turn, turn, "the turn passes after the meeting")


func test_a_creature_by_a_part_of_its_name_or_its_title() -> void:
	# "bea" is part of Bear only; the bear lives in the hills.
	assert_true(game.runner.act("hunt_name", "bea"))
	assert_string_contains(_text(), "WRONG AREA")
	# The ghost fox roams nowhere, so "ghost" names nothing that can be hunted.
	assert_true(game.runner.act("hunt_name", "ghost"))
	assert_string_contains(_text(), "NO SUCH THING AS ghost")


func test_creature_answers_and_the_turn_they_cost() -> void:
	var turn: int = game.state.turn
	assert_true(game.runner.act("hunt_name", "night bird"), "a creature answers to its title")
	var text := _text()
	assert_string_contains(text, "TRACKS OF night bird")
	assert_string_contains(text, "WRONG TIME")
	assert_eq(game.state.turn, turn + 1, "a hunt that finds nothing still takes its turn")
	assert_true(game.runner.act("hunt_name", "bear"))
	text = _text()
	assert_string_contains(text, "WRONG AREA")
	assert_false("TRACKS" in text, "no tracks of a creature that does not roam here")
	assert_true(game.set_filter("slimy", "banned"))
	assert_true(game.runner.act("hunt_name", "slug"))
	text = _text()
	assert_string_contains(text, "TRACKS OF slug")
	assert_string_contains(text, "BANNED CREATURE")
	assert_true(game.runner.act("hunt_name", "unicorn"))
	assert_string_contains(_text(), "NO SUCH THING AS unicorn")


func test_a_place_is_found_by_a_search() -> void:
	# Target 100 with no bonus: the search fails, with its roll shown.
	assert_true(game.runner.act("hunt_name", "old tower"))
	var text := _text()
	assert_string_contains(text, "SEARCHING FOR Old Tower")
	assert_string_contains(text, "[roll]")
	assert_string_contains(text, "NO PLACE")
	assert_string_contains(text, "SEARCH FAILED")
	assert_eq(game.state.location, "camp")
	assert_false(game.state.known.has("tower"))
	# A pathfinder finds it without a roll, goes there and knows the place from then on.
	game.state.feats.append("pathfinder")
	assert_true(game.runner.act("hunt_name", "Old Tower"))
	text = _text()
	assert_string_contains(text, "REACHED Old Tower")
	assert_false("[roll]" in text, "certain: no roll")
	assert_eq(game.state.location, "tower")
	assert_true(game.state.known.has("tower"))


func test_the_search_bonus_and_its_modifiers() -> void:
	game.state.feats.append("keen")  # + 100 against 100: always found
	assert_true(game.runner.act("hunt_name", "still lake"))
	var text := _text()
	assert_string_contains(text, "[roll]")
	assert_string_contains(text, "REACHED Still Lake")
	# Keen also brings the creature chance to 20 in 20: someone comes up on the way.
	assert_string_contains(text, "SOMEONE ON THE WAY")
	assert_eq(game.runner.status, "continue", "the meeting waits for the player to read on")


func test_places_that_cannot_be_hunted_for() -> void:
	game.state.feats.append("pathfinder")
	assert_true(game.runner.act("hunt_name", "hidden vault"))
	assert_string_contains(_text(), "HIDDEN PLACE")
	assert_true(game.runner.act("hunt_name", "tool shed"))
	assert_string_contains(_text(), "UNREACHABLE PLACE")
	assert_eq(game.state.location, "camp")


func test_a_part_of_a_name_finds_only_places_not_known_yet() -> void:
	game.state.feats.append("pathfinder")
	game.state.known["lake"] = true
	assert_true(game.runner.act("hunt_name", "lake"), "the lake is known: its part of a name finds nothing")
	assert_string_contains(_text(), "NO SUCH THING AS lake")
	assert_true(game.runner.act("hunt_name", "towe"))
	assert_eq(game.state.location, "tower", "the tower was not known")


func test_an_event_is_found_by_a_search_and_plays() -> void:
	game.state.feats.append("pathfinder")
	assert_true(game.runner.act("hunt_name", "lost hiker"))
	var text := _text()
	assert_string_contains(text, "[title] Lost Hiker")
	assert_string_contains(text, "SEARCHING FOR Lost Hiker")
	assert_string_contains(text, "CAME UPON Lost Hiker")
	assert_string_contains(text, "A HIKER WAVES")
	assert_lt(text.find("CAME UPON"), text.find("A HIKER WAVES"), "the search comes before the event's own text")
	game.runner.proceed()
	game.take_output()
	assert_true(game.runner.act("hunt_name", "lost hiker"))
	assert_string_contains(_text(), "EVENT RESOLVED")


func test_a_failed_search_for_an_event() -> void:
	assert_true(game.runner.act("hunt_name", "hiker"), "a part of the name will do")
	var text := _text()
	assert_string_contains(text, "NO EVENT")
	assert_string_contains(text, "SEARCH FAILED")
	assert_false("A HIKER WAVES" in text)
	assert_false(game._event("lost_hiker").resolved)


func test_event_answers() -> void:
	game.state.feats.append("pathfinder")
	for pair: Array in [["far cry", "EVENT ELSEWHERE"], ["old debt", "EVENT INACTIVE"], ["steep climb", "EVENT TOO HARD"],
			["locked door", "EVENT NOT READY"], ["doorstep", "EVENT ELSEWHERE"]]:
		assert_true(game.runner.act("hunt_name", pair[0]))
		assert_string_contains(_text(), pair[1], pair[0])
	game.set_value("player.level", 5)
	game.state.feats.append("keyholder")
	assert_true(game.runner.act("hunt_name", "steep climb"))
	assert_string_contains(_text(), "A CLIMB")
	game.runner.proceed()
	assert_true(game.runner.act("hunt_name", "locked door"))
	assert_string_contains(_text(), "A DOOR")


func test_a_whole_name_comes_first_and_events_before_creatures() -> void:
	game.state.feats.append("pathfinder")
	# "fox den" is the event's whole name; "fox" alone is the creature's.
	assert_true(game.runner.act("hunt_name", "fox den"))
	assert_string_contains(_text(), "A DEN")
	game.runner.proceed()
	game.take_output()
	assert_true(game.runner.act("hunt_name", "fox"))
	assert_string_contains(_text(), "Encounter: Fox")


func test_a_refused_creature_gives_way_to_an_event_of_that_name() -> void:
	game.state.feats.append("pathfinder")
	# "cry" names no creature; "bear" is refused here, and no event is named so: the creature's answer stays.
	assert_eq(HuntSystem.find(game, "cry", "woods").answer, "event elsewhere")
	assert_eq(HuntSystem.find(game, "bear", "woods").answer, "wrong area")
	assert_eq(HuntSystem.find(game, "bear", "hills").answer, "")
	assert_eq(HuntSystem.find(game, "", "woods").answer, "nothing found")


func test_events_are_listed_only_when_the_rules_say() -> void:
	assert_eq(HuntSystem.listed_events(game, "woods"), [], "not a pathfinder")
	game.state.feats.append("pathfinder")
	assert_eq(HuntSystem.listed_events(game, "woods"), ["fox", "lost_hiker"], "those that can be hunted now, by name")
	assert_eq(HuntSystem.listed_events(game, "hills"), ["far_cry"])


func test_plain_answers_without_lines_of_their_own() -> void:
	_start("== hunt_rules test\nby name: yes\n")
	assert_true(game.runner.act("hunt_name", "unicorn"))
	assert_string_contains(_text(), "Nothing by that name can be found here.")
	# Without a search target the search always finds it.
	assert_true(game.runner.act("hunt_name", "old tower"))
	assert_eq(game.state.location, "tower")


func test_the_validator_checks_the_rules() -> void:
	var db := _load("== hunt_rules test\nby name: maybe\nsearch target: 1 +\nsearching: LOOKING\nwrong time: [no such thing here]\n")
	var messages: Array = db.diagnostics.map(func(p): return str(p.message))
	assert_true(messages.any(func(m: String) -> bool: return "By name is yes or no" in m), str(messages))
	assert_true(messages.any(func(m: String) -> bool: return m.begins_with("Search target:")), str(messages))
	assert_true(messages.any(func(m: String) -> bool: return "Searching only matters with 'by name: yes'" in m), str(messages))
	assert_true(messages.any(func(m: String) -> bool: return "[no such thing here]" in m), "texts are checked")


func test_hooks_put_creatures_into_a_hunt() -> void:
	# The bear lives in the hills; a hook puts fifty of it into every hunt of a marked player.
	game.state.feats.append("marked")
	assert_true(game.runner.act("hunt", "fox"))
	assert_string_contains(_text(), "[title] Encounter: Bear")
	assert_false(Condition.evaluate(Condition.compile("player is hunting"), game), "not the creature hunted for")
	assert_false(game.state.values.has(HuntSystem.EXTRAS), "the hook's creatures are used up")


func test_kindred_creatures_join_a_hunt_and_random_meetings() -> void:
	assert_eq(CombatSystem.kindred(game, "fox"), 0)
	game.set_value("player.body.tail", "fox")
	game.set_value("player.body.torso", "fox")
	game.set_value("player.body.head", "fox")
	assert_eq(CombatSystem.kindred(game, "fox"), 2, "torso and tail are the kindred parts; the head is not")
	# Not a herdmate: every creature of a pool is as likely.
	var counts := {"fox": 0, "slug": 0}
	for _i in 400:
		counts[CombatSystem.draw(game, ["fox", "slug"])] += 1
	assert_almost_eq(float(counts.fox), 200.0, 45.0)
	# A herdmate meets its own strain three times as often (1 + 2 parts).
	game.state.feats.append("herdmate")
	counts = {"fox": 0, "slug": 0}
	for _i in 400:
		counts[CombatSystem.draw(game, ["fox", "slug"])] += 1
	assert_almost_eq(float(counts.fox), 300.0, 45.0)
	# In a hunt for the slug (once in the draw) the fox joins twice: it is met about two times in three.
	var met := {"fox": 0, "slug": 0}
	for _i in 300:
		met[HuntSystem.pick(game, "slug", "woods")] += 1
	assert_almost_eq(float(met.fox), 200.0, 40.0)


func test_here_zone_reads_the_zone_hunted_in() -> void:
	assert_eq(str(game.value("here.zone")), "woods")
	game.go_to("tower")
	assert_eq(str(game.value("here.zone")), "")
