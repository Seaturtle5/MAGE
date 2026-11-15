extends GutTest
## The validator must report broken references with file, line and a hint.

const ROOT := "user://validator_test_packs"


func _load(files: Dictionary) -> ContentDB:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	for f in DirAccess.get_files_at(ROOT + "/p"):
		DirAccess.remove_absolute(ROOT + "/p/" + f)
	var all := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT}
	all.merge(files)
	for name in all:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(all[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	return db


func _messages(db: ContentDB, severity: String = "error") -> Array:
	return db.diagnostics.filter(func(d): return d.severity == severity).map(func(d): return "%d %s" % [d.line, d.message])


func _has(list: Array, fragment: String) -> bool:
	for m in list:
		if fragment in m:
			return true
	return false


const WORLD := "== region r\nname: R\n\n== zone z\nname: Z\n\n== location a\nname: A\nregion: r\nzone: z\nexits:\n    north: plaza\n\n== location plaza\nname: Plaza\nregion: r\nexits:\n    south: a\n"


func test_clean_content_has_no_errors() -> void:
	var db := _load({"w.fsc": WORLD})
	assert_eq(_messages(db), [])


func test_character_image_with_shared_id_passes_validation() -> void:
	var db := ContentDB.new()
	db.load_folders(["res://tests/packs"])
	assert_eq(_messages(db), [])
	assert_eq(db.typed_value("character", "mira", "image"), "mira")
	assert_true(db.has("mira", "image"), "portrait keeps its own credit definition")
	assert_false(_has(_messages(db, "warning"), "Image 'mira'"))


func test_missing_character_image_reports_file_and_line() -> void:
	var db := _load({"c.fsc": "== character c\nname: C\nimage: missing_portrait\n"})
	assert_eq(_messages(db), [], "missing art uses the lettered fallback")
	var warnings := db.diagnostics.filter(func(d): return d.severity == "warning" and "missing_portrait" in d.message)
	assert_eq(warnings.size(), 1)
	if warnings.size() == 1:
		assert_true(str(warnings[0].path).ends_with("c.fsc"))
		assert_eq(warnings[0].line, 3)
		assert_string_contains(warnings[0].message, "placeholder")


func test_missing_exit_target_with_suggestion() -> void:
	var db := _load({"w.fsc": WORLD.replace("north: plaza", "north: plazza")})
	var errs := _messages(db)
	assert_true(_has(errs, "12 Exit north leads to 'plazza'"), str(errs))
	assert_true(_has(errs, "Did you mean 'plaza'?"), str(errs))


func test_one_way_exit_warning() -> void:
	# The plaza has no way back to a: a warning on a's exit line, unless marked one way.
	var db := _load({"w.fsc": WORLD.replace("exits:\n    south: a\n", "")})
	assert_true(_has(_messages(db, "warning"), "12 Exit north leads to plaza, but plaza has no exit back"), str(_messages(db, "warning")))
	db = _load({"w.fsc": WORLD.replace("exits:\n    south: a\n", "").replace("north: plaza", "north: plaza, one way")})
	assert_false(_has(_messages(db, "warning"), "has no exit back"))


func test_unknown_scene_value_state_and_item() -> void:
	var db := _load({"w.fsc": WORLD, "s.fsc": "== character c\nname: C\nlives at: a\nvalues:\n    mood: calm, angry\n\n== scene s\nHello.\n~ c.mood = furious\n~ give lantern\n-> nowhere\nif c.moods is calm:\n    Hi\n"})
	var errs := _messages(db)
	assert_true(_has(errs, "'furious' is not a state of c.mood"), str(errs))
	assert_true(_has(errs, "Item 'lantern' does not exist"), str(errs))
	assert_true(_has(errs, "no scene or menu called 'nowhere'"), str(errs))
	assert_true(_has(errs, "'c.moods' is not a declared value"), str(errs))
	assert_true(_has(errs, "Did you mean 'c.mood'?"), str(errs))


func test_unknown_quest_stage_and_substitution() -> void:
	var db := _load({"w.fsc": WORLD, "q.fsc": "== quest q\nname: Q\nstages:\n    start\n    done: Done.\n\n== scene s\n~ quest q = finished\nHello [nonsense of player].\n"})
	var errs := _messages(db)
	assert_true(_has(errs, "'finished' is not a stage of quest q"), str(errs))
	assert_true(_has(errs, "Unknown text substitution [nonsense of player]"), str(errs))


func test_shared_id_lookup_prefers_main_type() -> void:
	# An image loaded before the location with the same ID must not hide it.
	var db := _load({"a_images.fsc": "== image plaza\nartist: someone\n", "w.fsc": WORLD})
	assert_eq(db.field_value("plaza", "name"), "Plaza")
	assert_eq(db.type_of("plaza"), "location")


func test_unsupported_behavior_and_invalid_combat_numbers_fail_on_load() -> void:
	var db := _load({"c.fsc": "== creature c\nname: C\nhp: twelve\nspecial: unknown_move 50%\n\n== feat f\nexploration bonus: many\n\n== form f\nlibido: lots\n"})
	assert_true(_has(_messages(db), "3 Hp must be a positive whole number"))
	assert_true(_has(_messages(db), "4 Unknown combat behaviour 'unknown_move 50%'"))
	assert_true(_has(_messages(db), "7 Exploration Bonus must be a whole number"))
	assert_true(_has(_messages(db), "10 Libido must be a whole number"))


func test_description_actions_and_pending_effects_are_not_silently_ignored() -> void:
	var db := _load({"w.fsc": "== location a\nname: A\ndescription:\n    ~ player.hunger + 1\n\n== scene s\n~ end pregnancy\n~ pregnancy faster by 2\n"})
	assert_true(_has(_messages(db), "4 This description can contain text and conditions only"))
	assert_false(_has(_messages(db), "Effect 'end_pregnancy'"), "pregnancy effects are implemented now")
	assert_false(_has(_messages(db), "Effect 'pregnancy_faster'"))


func test_body_typos_are_reported_before_play() -> void:
	var db := _load({"s.fsc": "== scene s\n~ player.body.hed = human\n"})
	assert_true(_has(_messages(db), "2 Unknown body part 'hed'"))


func test_missing_door_and_unknown_exit_options_are_reported() -> void:
	var db := _load({"w.fsc": WORLD.replace("north: plaza", "north: plaza, door missing, teleport")})
	assert_true(_has(_messages(db), "12 Door 'missing' does not exist"))
	assert_true(_has(_messages(db), "12 Unknown exit option 'teleport'"))


func test_scheduled_scenes_are_checked_before_play() -> void:
	var db := _load({"s.fsc": "== scene start\n~ schedule missing after 1 action\n~ schedule start after 0 actions\n"})
	assert_true(_has(_messages(db), "2 Scene 'missing' does not exist"))
	assert_true(_has(_messages(db), "3 Schedule delay must be at least 1 action"))


func test_bad_rest_rules_and_bedding_fail_before_play() -> void:
	var db := _load({"s.fsc": "== item pillow\nrest: magic\n\n== rest_rules r\ncondition: missing\nduration: many\ncollapse at: 4\ncollapse fatigue: 3\ncollapse turns: 2\nstatuses:\n    tired: Spent\nwarnings:\n    6: [unknown descriptor]\n"})
	var errors := _messages(db)
	assert_true(_has(errors, "2 Rest quality must be"))
	assert_true(_has(errors, "5 Condition 'missing'"))
	assert_true(_has(errors, "6 Duration must be a whole number"))
	assert_true(_has(errors, "avoid repeated collapses"))
	assert_true(_has(errors, "11 Use a numeric fatigue threshold"))
	assert_true(_has(errors, "13 Unknown text substitution"))


func test_duplicate_sleep_policies_and_unsafe_condition_modifiers_fail() -> void:
	var db := _load({"s.fsc": "== condition c\nblocks rest: maybe\nwhile active:\n    player.hp + 4\n\n== rest_rules a\ncondition: c\n\n== rest_rules b\ncondition: c\ncollapse:\n    ~ give missing\n"})
	var errors := _messages(db)
	assert_true(_has(errors, "Blocks rest must be yes or no"))
	assert_true(_has(errors, "six player attributes only"))
	assert_true(_has(errors, "Only one rest_rules"))
	assert_true(_has(errors, "This description can contain text and conditions only"))


func test_condition_scripts_and_extensions_keep_the_type_when_ids_are_shared() -> void:
	var db := _load({"s.fsc": "== feat shared\nname: Metadata\n\n== condition shared\nname: Condition\nends: Original ending.\n\n== extend condition shared\nends: Extra ending.\n"})
	assert_eq(_messages(db), [])
	var program := db.program("shared#ends", "condition")
	assert_not_null(program)
	if program != null:
		assert_eq(program.id, "condition:shared#ends")
		assert_eq(program.code.filter(func(ins): return ins.op == "text").size(), 2)
		assert_eq(db.program(program.id), program, "saved typed program ID resolves to the same script")


func test_each_type_is_validated_when_script_field_names_are_shared() -> void:
	var db := _load({"s.fsc": "== item shared\ndescription:\n    ~ give missing_item\n\n== character shared\ndescription:\n    ~ give missing_character\n"})
	assert_true(_has(_messages(db), "3 Item 'missing_item'"))
	assert_true(_has(_messages(db), "7 Item 'missing_character'"))


func test_map_positions_are_checked() -> void:
	var db := _load({"w.fsc": "== region r\nname: R\nmap grid: 4 x 4\n\n== region bad\nname: Bad\nmap grid: big\n\n== location a\nname: A\nregion: r\nmap: 1, 1\n\n== location b\nname: B\nregion: r\nmap: 1, 1\n\n== location c\nname: C\nregion: r\nmap: 9, 2\n\n== location d\nname: D\nmap: 2, 2\n\n== location e\nname: E\nregion: r\nmap: two, 2\n"})
	var errors := _messages(db)
	var warnings := _messages(db, "warning")
	assert_true(_has(errors, "7 A map grid is written 'width x height'"), str(errors))
	assert_true(_has(errors, "26 d has a map position but no region"), str(errors))
	assert_true(_has(errors, "31 A map position is written 'x, y'"), str(errors))
	assert_true(_has(warnings, "17 b is drawn on top of a at map position 1, 1."), str(warnings))
	assert_true(_has(warnings, "22 Map position 9, 2 is outside the 4 x 4 grid of region r."), str(warnings))


func test_conversion_assistant_markers_block_loading() -> void:
	var db := _load({"draft.fsc": "== scene s\nHello.\n// UNCONVERTED: challenge \"Wolf\";  (line 12)\n"})
	assert_true(_has(_messages(db), "3 Line left unconverted by the conversion assistant"), str(_messages(db)))


func test_resolving_an_unknown_event_is_reported() -> void:
	var db := _load({"s.fsc": "== scene s\n~ resolve no_such_event\n"})
	assert_true(_has(_messages(db), "2 Event 'no_such_event' does not exist."), str(_messages(db)))


func test_unknown_sex_act() -> void:
	var errs := _messages(_load({"s.fsc": "== scene s\n~ sex player receives oral_cock from player\n~ sex player receives oralcock from player\n"}))
	assert_true(_has(errs, "3 Unknown sex act 'oralcock'"), str(errs))
	assert_false(_has(errs, "'oral_cock'"), str(errs))
