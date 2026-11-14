extends GutTest
## Plays the test pack through the real content database, game and runner.

var game: Game

func before_each() -> void:
	var db := ContentDB.new()
	db.load_folders(["res://tests/packs"])
	assert_eq(db.errors(), [], "test pack loads without errors")
	game = Game.new(db, 42)
	game.start("shelter")

func after_each() -> void:
	game.dispose()

func _texts() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
		elif e.type == "location":
			for p in e.description:
				out.append(TextTemplate.plain(p))
	return "\n".join(out)

func test_start_shows_location_with_presence_from_extend() -> void:
	var text := _texts()
	assert_string_contains(text, "battery lantern")
	assert_string_contains(text, "Mira sits at the table")

func test_menu_loop_and_quest() -> void:
	game.take_output()
	assert_true(game.runner.act("talk", "mira"))
	assert_eq(game.runner.status, "choice")
	assert_true(game.runner.choose(1))  # Supplies
	assert_eq(game.value("quest.supplies"), "asked")
	assert_eq(game.runner.status, "continue")
	game.runner.proceed()
	assert_eq(game.runner.status, "choice", "menu shows again after the pause")

func test_portrait_metadata_reaches_location_and_conversation() -> void:
	var locations := game.take_output().filter(func(e): return e.type == "location")
	assert_eq(locations[-1].people[0].id, "mira")
	assert_eq(locations[-1].people[0].image, "mira")
	assert_true(game.runner.act("talk", "mira"))
	var titles := game.take_output().filter(func(e): return e.type == "title")
	assert_eq(titles[0].character, "mira")
	assert_eq(titles[0].image, "mira")
	game.runner.choose(0)
	game.take_output()
	game.runner.proceed()
	assert_eq(game.runner.status, "choice", "portrait metadata leaves conversation flow intact")

func test_movement_and_items() -> void:
	assert_true(game.runner.act("go", "up"))
	assert_eq(game.state.location, "plaza")
	assert_false(game.runner.act("go", "west"), "no such exit")
	game.runner.act("go", "east")
	assert_true(game.runner.act("take", "can_of_beans"))
	assert_eq(game.state.inventory.get("can_of_beans", 0), 1)
	assert_false(game.runner.act("take", "can_of_beans"), "taken already")

func test_item_use_cancel_gives_item_back() -> void:
	game.state.inventory["water_bottle"] = 1
	game.set_value("player.thirst", 0)
	assert_true(game.runner.act("use", "water_bottle"))
	assert_eq(game.state.inventory.get("water_bottle", 0), 1, "not thirsty: bottle returned")
	game.set_value("player.thirst", 40)
	game.runner.act("use", "water_bottle")
	assert_eq(game.state.inventory.get("water_bottle", 0), 0)
	assert_eq(game.value("player.thirst"), 15)

func test_save_and_load_round_trip() -> void:
	game.runner.act("talk", "mira")
	game.runner.choose(1)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(game.save_dict()))
	var db := game.content
	var other := Game.new(db, 1)
	other.load_dict(saved)
	assert_eq(other.value("quest.supplies"), "asked")
	assert_eq(other.state.location, "shelter")
	assert_eq(other.rng.get_state(), game.rng.get_state())
	other.dispose()


func test_timed_condition_applies_and_undoes() -> void:
	game.state.inventory["energy_drink"] = 1
	game.take_output()
	assert_true(game.runner.act("use", "energy_drink"))
	assert_true(game.state.conditions.has("wired"))
	assert_has(game.state.feats, "jittery")
	game.take_output()
	game.pass_turn()  # 2 turns: "each turn" runs on the first, "ends" on the last
	var first := _texts()
	assert_string_contains(first, "fingers drum")
	assert_has(game.state.feats, "jittery")
	game.pass_turn()
	var last := _texts()
	assert_string_contains(last, "buzz fades")
	assert_does_not_have(game.state.feats, "jittery")
	assert_false(game.state.conditions.has("wired"))


func test_condition_keeps_a_feat_the_player_already_had() -> void:
	game.state.feats.append("jittery")
	game.start_condition("wired", 1)
	game.pass_turn()
	assert_has(game.state.feats, "jittery", "a feat the player had before stays after the condition ends")


func test_caffeine_item_blocks_rest_until_its_condition_expires() -> void:
	game.state.inventory.energy_drink = 1
	game.runner.act("use", "energy_drink")
	assert_false(game.runner.act("rest"))
	assert_eq(game.state.turn, 0)
	assert_string_contains(_texts(), "Too much caffeine keeps you awake.")
	game.runner.act("wait")
	game.runner.act("wait")
	assert_true(game.runner.act("rest"))
	assert_eq(game.state.turn, 4)


func test_an_effect_can_resolve_another_event() -> void:
	var db := ContentDB.new()
	db.load_folders(["res://tests/packs"])
	var g := Game.new(db, 1)
	g.start("plaza")
	assert_has(g.runner.explore_events("streets"), "stray_dog")
	g.apply(Effect.compile("resolve stray_dog"))
	assert_does_not_have(g.runner.explore_events("streets"), "stray_dog", "a resolved event is not found again")
	g.dispose()


func test_text_variation_orders_follow_inform() -> void:
	var db := ContentDB.new()
	db.load_folders(["res://tests/packs"])
	var g := Game.new(db, 5)
	var last := -1
	for _i in 60:
		var pick := g.variation("k", 3, "at random")
		assert_ne(pick, last, "[at random] never repeats the previous choice")
		last = pick
	var seen: Array = []
	for _i in 4:
		seen.append(g.variation("r", 4, "in random order"))
	seen.sort()
	assert_eq(seen, [0, 1, 2, 3], "[in random order] uses every option before repeating")
	var counts := [0, 0, 0]
	for _i in 600:
		counts[g.variation("d", 3, "as decreasingly likely outcomes")] += 1
	assert_gt(counts[0], counts[1])
	assert_gt(counts[1], counts[2])
	var compiled := TextTemplate.compile("[one of]a[or]b[sticky random]")
	assert_false(compiled.has("error"), "[sticky random] is accepted")
	g.dispose()


func test_fight_results_tell_how_the_fight_ended() -> void:
	var cases := {"won": ["won", "won by fighting"], "won by seduction": ["won", "won by seduction"],
		"lost": ["lost", "lost by injury"], "lost by submitting": ["lost", "lost by submitting"], "fled": ["fled"]}
	var all := ["won", "won by fighting", "won by seduction", "lost", "lost by injury", "lost by submitting", "lost by lust", "fled"]
	for result in cases:
		game.last_fight = result
		for word in all:
			assert_eq(Condition.evaluate(Condition.compile(word), game), word in cases[result], "%s after '%s'" % [word, result])


func test_an_effect_can_set_another_events_outcome() -> void:
	game.apply(Effect.compile("outcome bitten of stray_dog"))
	assert_eq(str(game.value("stray_dog.outcome")), "bitten")
