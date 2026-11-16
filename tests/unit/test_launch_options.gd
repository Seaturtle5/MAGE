extends GutTest
## The command-line options that start a game for trying out a pack.

func _game() -> Game:
	var db := ContentDB.new()
	db.load_folders(["res://tests/packs"])
	assert_eq(db.errors(), [], "test pack loads without errors")
	return Game.new(db, 42)

func _texts(game: Game) -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)

func test_parse_reads_every_option() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--seed", "7", "--packs", "/a", "--packs", "/b", "--only-packs", "--data", "/tmp/try",
		"--scenario", "arrival", "--start", "shelter", "--play", "mira.about_town", "--set", "mira.trust=3", "--set", "mira.met=yes", "--set", "player.name=Sam"]))
	assert_eq(o.seed, 7)
	assert_eq(o.packs, ["/a", "/b"])
	assert_true(o.only_packs)
	assert_eq(o.data, "/tmp/try")
	assert_eq(o.scenario, "arrival")
	assert_eq(o.start, "shelter")
	assert_eq(o.play, "mira.about_town")
	assert_eq(o.values, {"mira.trust": 3, "mira.met": true, "player.name": "Sam"})
	assert_true(o.starts_game())

func test_unknown_options_and_a_missing_value_are_skipped() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--light", "--shot", "x.png", "--start"]))
	assert_eq(o.start, "")
	assert_false(o.starts_game())
	assert_eq(LaunchOptions.parse(PackedStringArray(["--only-packs", "--start", "shelter"])).start, "shelter", "a switch takes no value")

func test_only_packs_leaves_out_the_usual_folders() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--packs", "/try"]))
	assert_eq(o.content_folders(["res://packs", "user://packs"]), ["/try", "res://packs", "user://packs"])
	o.only_packs = true
	assert_eq(o.content_folders(["res://packs", "user://packs"]), ["/try"])

func test_data_folder_holds_saves_and_settings() -> void:
	var o := LaunchOptions.new()
	assert_eq(o.data_path("user://saves"), "user://saves")
	o.data = "/tmp/try"
	assert_eq(o.data_path("user://saves"), "/tmp/try/saves")
	assert_eq(o.data_path("user://preferences.cfg"), "/tmp/try/preferences.cfg")

func test_begin_starts_at_a_location_sets_values_and_plays_a_story() -> void:
	var game := _game()
	var o := LaunchOptions.parse(PackedStringArray(["--start", "shelter", "--set", "quest.supplies=asked", "--play", "mira.about_town"]))
	assert_true(o.begin(game))
	assert_eq(game.state.location, "shelter")
	assert_eq(game.value("quest.supplies"), "asked", "the value is set before the story plays")
	assert_ne(_texts(game), "", "the story plays")
	assert_eq(game.warnings, [])
	game.dispose()

func test_begin_without_a_start_does_nothing() -> void:
	var game := _game()
	assert_false(LaunchOptions.parse(PackedStringArray(["--play", "mira.about_town"])).begin(game))
	assert_eq(game.state.location, "")
	game.dispose()

func test_an_unknown_story_is_a_warning_not_a_crash() -> void:
	var game := _game()
	assert_true(LaunchOptions.parse(PackedStringArray(["--start", "shelter", "--play", "no_such_story"])).begin(game))
	assert_string_contains(str(game.warnings), "no_such_story")
	game.dispose()

func test_begin_plays_an_event() -> void:
	var game := _game()
	assert_true(LaunchOptions.parse(PackedStringArray(["--start", "shelter", "--play", "event:stray_dog"])).begin(game))
	assert_eq(game.warnings, [])
	assert_ne(game.runner.status, "", "the event's story runs")
	game.dispose()
