extends GutTest
## Art packs: `art: replaces` packs whose pictures win over the content's own,
## `art: fallback` packs that only fill gaps, switching them off, image files
## replaced by name, and the player's own pictures added and removed in play
## (PlayerArt), shown at once and kept for the next start.

const ROOT := "user://art_packs_test"
const PLAYER := "user://art_packs_test_player"

const MAIN := """== location bunker
name: Bunker
image: own_bunker

== character adam
name: Adam

== character eve
name: Eve

== creature wolf
name: Wolf
image: own_wolf
"""


func _png(path: String, w: int = 4, h: int = 4) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.2, 0.1))
	img.save_png(path)


func _file(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_wipe(path.path_join(sub))
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func before_each() -> void:
	_wipe(ROOT)
	_wipe(PLAYER)
	_file(ROOT + "/main/pack.fsc", "== pack main\nname: Main\n")
	_file(ROOT + "/main/world.fsc", MAIN)
	_png(ROOT + "/main/images/own_bunker.png")
	_png(ROOT + "/main/images/own_wolf.png")
	_png(ROOT + "/main/images/shared.png")
	_file(ROOT + "/fill/pack.fsc", "== pack fill\nname: Fill\nart: fallback\n")
	_file(ROOT + "/fill/art.fsc", "== extend location bunker\nimage: fill_bunker\n\n== extend character adam\nimage: fill_adam\n")
	_png(ROOT + "/fill/images/fill_bunker.png")
	_png(ROOT + "/fill/images/fill_adam.png")
	_png(ROOT + "/fill/images/only_fill.png")
	_file(ROOT + "/redo/pack.fsc", "== pack redo\nname: Redo\nart: replaces\n")
	_file(ROOT + "/redo/art.fsc", "== extend location bunker\nimage: redo_bunker\n\n== extend creature wolf\nimage: redo_wolf\n")
	_png(ROOT + "/redo/images/redo_bunker.png")
	_png(ROOT + "/redo/images/redo_wolf.png")
	_png(ROOT + "/redo/images/shared.png")
	_file(ROOT + "/old/pack.fsc", "== pack old\nname: Old\n")
	_file(ROOT + "/old/art.fsc", "== extend character eve\nimage: old_eve\n")
	_png(ROOT + "/old/images/old_eve.png")


func _load(folders: Array) -> ContentDB:
	var db := ContentDB.new()
	db.load_folders(folders)
	return db


func test_replacing_and_fallback_art_packs() -> void:
	var db := _load([ROOT])
	assert_eq(db.errors(), [])
	assert_eq(db.image_of("location", "bunker"), "redo_bunker", "a replacing art pack wins over the place's own")
	assert_eq(db.image_of("character", "adam"), "fill_adam", "a fallback fills a gap")
	assert_eq(db.image_of("character", "eve"), "old_eve", "a plain pack's image: still fills a gap, as before")
	assert_eq(db.image_file("shared"), ROOT + "/redo/images/shared.png", "a replacing pack's file wins by name")
	assert_eq(db.image_file("only_fill"), ROOT + "/fill/images/only_fill.png")
	assert_eq(db.art_packs().map(func(p: Dictionary) -> String: return p.id), ["fill", "redo"])
	db.art_off = ["redo"]
	assert_eq(db.image_of("location", "bunker"), "own_bunker", "switched off: the place's own again")
	assert_eq(db.image_file("shared"), ROOT + "/main/images/shared.png")
	assert_false(db.art_packs()[1].on)
	db.art_off = ["redo", "fill"]
	assert_eq(db.image_of("character", "adam"), "")
	assert_eq(db.image_file("only_fill"), "", "a switched-off pack's files are not used")


func test_a_replacing_picture_wins_in_play() -> void:
	var game := Game.new(_load([ROOT]), 1)
	assert_eq(game.creature_field("wolf", "image"), "redo_wolf")
	game.content.art_off = ["redo"]
	assert_eq(game.creature_field("wolf", "image"), "own_wolf")
	game.dispose()


func test_the_players_own_picture() -> void:
	var db := _load([ROOT])
	_png(ROOT + "/photo.png", 3000, 1000)
	assert_eq(PlayerArt.add(db, PLAYER, "location", "bunker", ProjectSettings.globalize_path(ROOT + "/photo.png")), "")
	assert_eq(db.image_of("location", "bunker"), "location_bunker", "shown at once, over every other picture")
	assert_true(PlayerArt.has_image(db, "location", "bunker"))
	var file := db.image_file("location_bunker")
	assert_eq(file, PLAYER + "/my-images/images/location_bunker.png")
	var img := Image.load_from_file(file)
	assert_eq(img.get_size(), Vector2i(2048, 683), "scaled down to 2048 pixels")
	assert_eq(db.typed_value("image", "location_bunker", "artist"), "added by the player")
	assert_eq(db.typed_value("image", "location_bunker", "source"), "photo.png")
	assert_eq(PlayerArt.add(db, PLAYER, "character", "adam", ProjectSettings.globalize_path(ROOT + "/main/world.fsc")),
		"That file is not a picture the game can read (PNG, JPG or WebP).")
	# The next start loads the player's pack like any other.
	var again := _load([ROOT, PLAYER])
	assert_eq(again.errors(), [])
	assert_eq(again.image_of("location", "bunker"), "location_bunker", "kept for the next start")
	assert_true(again.art_packs().any(func(p: Dictionary) -> bool: return p.id == "my-images" and p.replaces))
	PlayerArt.remove(db, PLAYER, "location", "bunker")
	assert_eq(db.image_of("location", "bunker"), "redo_bunker", "removed: the picture before it")
	assert_false(PlayerArt.has_image(db, "location", "bunker"))
	assert_false(FileAccess.file_exists(file))


func test_art_packs_are_validated_and_never_block_loading() -> void:
	_file(ROOT + "/bad/pack.fsc", "== pack bad\nname: Bad\nart: sometimes\n")
	_file(ROOT + "/bad/art.fsc", "== extend location gone\nimage: missing_picture\n\n== extend location bunker\nimage: missing_picture\n")
	var db := _load([ROOT])
	var errors := db.diagnostics.filter(func(d: Dictionary) -> bool: return d.severity == "error").map(
		func(d: Dictionary) -> String: return "%s %d %s" % [str(d.path).get_file(), d.line, d.message])
	var warnings := db.diagnostics.filter(func(d: Dictionary) -> bool: return d.severity == "warning").map(
		func(d: Dictionary) -> String: return "%s %d %s" % [str(d.path).get_file(), d.line, d.message])
	assert_eq(errors.size(), 1, str(errors))
	assert_true(errors.any(func(m: String) -> bool: return m.begins_with("pack.fsc 3 An art pack is 'art: replaces'")), str(errors))
	assert_true(warnings.has("art.fsc 1 Cannot extend location gone: it does not exist, so its picture is not used."), str(warnings))
	assert_true(warnings.any(func(m: String) -> bool: return m.begins_with("art.fsc 5 Image 'missing_picture' was not found")), str(warnings))
