class_name PlayerArt
extends RefCounted
## The player's own pictures, added in play ("Add image" under a picture).
##
## They live in an art pack of the player's own, `my-images` in the player's
## packs folder (`user://packs`), made on first use: a `pack.fsc` with
## `art: replaces`, the pictures in `images/` named `<type>_<id>.png`, an
## `== extend <type> <id>` with `image:` for each in `images.fsc`, and a credit
## for each in `images/credits.fsc`. The loaded content is updated at once, so
## the new picture shows without restarting.

const PACK_ID := "my-images"
const FOLDER := "my-images"
## Pictures larger than this (either side, in pixels) are scaled down.
const MAX_SIDE := 2048
const FORMATS := ["png", "jpg", "jpeg", "webp"]


static func pack_path(root: String) -> String:
	return root.path_join(FOLDER)


## The image ID of the player's picture for a definition.
static func image_id(type: String, id: String) -> String:
	return "%s_%s" % [type, id]


## Whether the player has a picture of their own for a definition.
static func has_image(db: ContentDB, type: String, id: String) -> bool:
	for e: Dictionary in db.art_images.get("%s:%s" % [type, id], []):
		if e.pack == PACK_ID:
			return true
	return false


## Copies a picture file into the player's pack as the picture of a
## definition (scaled down when very large) and shows it from now on.
## Returns "" or what went wrong, in plain words.
static func add(db: ContentDB, root: String, type: String, id: String, file: String) -> String:
	if file.get_extension().to_lower() not in FORMATS or not FileAccess.file_exists(file):
		return "That file is not a picture the game can read (PNG, JPG or WebP)."
	var img := Image.load_from_file(file)
	if img == null or img.is_empty():
		return "That file is not a picture the game can read (PNG, JPG or WebP)."
	var side := maxi(img.get_width(), img.get_height())
	if side > MAX_SIDE:
		var f := float(MAX_SIDE) / float(side)
		img.resize(maxi(1, roundi(img.get_width() * f)), maxi(1, roundi(img.get_height() * f)), Image.INTERPOLATE_LANCZOS)
	var path := pack_path(root)
	DirAccess.make_dir_recursive_absolute(path.path_join("images"))
	if not FileAccess.file_exists(path.path_join("pack.fsc")):
		_write(path.path_join("pack.fsc"), "== pack %s\nname: My Images\nversion: 1.0.0\nauthors: the player\nart: replaces\n" % PACK_ID
			+ "// Pictures added in play with \"Add image\". Each one replaces the game's own picture\n"
			+ "// of that place, character, creature or item. Switch this pack off in Content settings,\n"
			+ "// or delete this folder, to see the game's pictures again.\n")
	var image := image_id(type, id)
	_remove_files(path, image)
	if img.save_png(path.path_join("images/%s.png" % image)) != OK:
		return "The picture could not be saved."
	var entries := _entries(path)
	entries["%s:%s" % [type, id]] = {"type": type, "id": id, "image": image, "source": file.get_file()}
	_save_entries(path, entries)
	db.reload_art_pack(path)
	return ""


## Takes the player's own picture of a definition away again.
static func remove(db: ContentDB, root: String, type: String, id: String) -> void:
	var path := pack_path(root)
	_remove_files(path, image_id(type, id))
	var entries := _entries(path)
	entries.erase("%s:%s" % [type, id])
	_save_entries(path, entries)
	db.reload_art_pack(path)


static func _remove_files(path: String, image: String) -> void:
	for ext in FORMATS:
		var file := path.path_join("images/%s.%s" % [image, ext])
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## The pictures in the pack: "type:id" -> {"type", "id", "image", "source"}.
static func _entries(path: String) -> Dictionary:
	var out := {}
	var sources := {}
	var credits := path.path_join("images/credits.fsc")
	if FileAccess.file_exists(credits):
		for d: FscParser.Definition in FscParser.parse(FileAccess.get_file_as_string(credits), credits).definitions:
			if d.type == "image" and d.fields.has("source"):
				sources[d.id] = d.fields.source.value
	var list := path.path_join("images.fsc")
	if FileAccess.file_exists(list):
		for d: FscParser.Definition in FscParser.parse(FileAccess.get_file_as_string(list), list).definitions:
			if d.mode == "extend" and d.fields.has("image"):
				var image: String = d.fields.image.value
				out["%s:%s" % [d.type, d.id]] = {"type": d.type, "id": d.id, "image": image, "source": sources.get(image, "")}
	return out


static func _save_entries(path: String, entries: Dictionary) -> void:
	var keys: Array = entries.keys()
	keys.sort()
	var list := "// Pictures added in play: each one is the picture of what it extends.\n"
	var credits := "// Credits for the pictures added in play.\n"
	for key: String in keys:
		var e: Dictionary = entries[key]
		list += "\n== extend %s %s\nimage: %s\n" % [e.type, e.id, e.image]
		credits += "\n== image %s\nartist: added by the player\n" % e.image
		var source := str(e.source).replace("\n", " ").strip_edges()
		if source != "":
			credits += "source: %s\n" % source
	_write(path.path_join("images.fsc"), list)
	_write(path.path_join("images/credits.fsc"), credits)


static func _write(file: String, text: String) -> void:
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
