extends SceneTree
## Checks content packs and prints every problem the validator finds.
##
##   godot --headless --path . --script res://tests/validate_packs.gd [-- FOLDER ...]
##
## Without folders it checks res://packs, the packs that come with the engine
## (a folder of packs, each with its pack.fsc).


func _init() -> void:
	var folders: Array = Array(OS.get_cmdline_user_args())
	if folders.is_empty():
		folders = ["res://packs"]
	var db := ContentDB.new()
	db.load_folders(folders)
	var errors := 0
	for d in db.diagnostics:
		print("%s: %s:%d: %s" % [d.severity, d.path, d.line, d.message])
		if d.severity == "error":
			errors += 1
	var count := 0
	for type in db.definitions:
		count += db.definitions[type].size()
	print("%d packs, %d definitions: %d errors, %d warnings" % [db.packs.size(), count, errors, db.diagnostics.size() - errors])
	quit(1 if errors > 0 else 0)
