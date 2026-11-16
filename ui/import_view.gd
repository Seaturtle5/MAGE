class_name ImportView
extends RefCounted
## The interface of importing progress from the original game (ImportSystem):
## the "Earlier progress" section of the new-game screen and the report shown
## after the import.


## Whether the loaded content can import anything.
static func available(game: Game) -> bool:
	return not game.content.all_of("save_import").is_empty()


## The new-game section: what is chosen, and a button that opens a folder picker.
## `chosen` is called with the folder ("" to bring nothing over).
static func section(game: Game, folder: String, chosen: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(FsTheme.section("Earlier progress"))
	box.add_child(FsTheme.label("Bring your progress over from the original game: export it there, then choose the folder that holds its export files. It is brought in after the start.", 15, FsTheme.TEXT_DIM))
	if folder != "":
		var found := ImportSystem.recognised(game.content, folder)
		var name := folder.trim_suffix("/").get_file()
		var line := "Folder “%s”: %d of the %d files the game reads" % [name if name != "" else folder, found.found.size(), found.total]
		var status := FsTheme.label(line, 15, FsTheme.GOOD if not found.found.is_empty() else FsTheme.BAD)
		status.tooltip_text = folder
		status.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(status)
		if found.found.is_empty():
			box.add_child(FsTheme.label("No export files are in this folder. They are named like FSPlayerSave.glkdata.", 14, FsTheme.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var pick := Button.new()
	pick.text = "Choose folder" if folder == "" else "Choose another folder"
	pick.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(pick)
	if folder != "":
		var clear := Button.new()
		clear.text = "Start fresh instead"
		clear.pressed.connect(func(): chosen.call(""))
		row.add_child(clear)
	pick.pressed.connect(func():
		var dialog := FileDialog.new()
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.title = "The folder with the original game's export files"
		dialog.use_native_dialog = true
		if folder != "":
			dialog.current_dir = folder
		dialog.dir_selected.connect(func(dir: String): chosen.call(dir))
		dialog.canceled.connect(dialog.queue_free)
		dialog.dir_selected.connect(func(_d: String): dialog.queue_free())
		box.add_child(dialog)
		dialog.popup_centered_ratio(0.7))
	return box


## Fills an overlay with the import report.
static func fill_report(box: VBoxContainer, report: Dictionary) -> void:
	var missed: Array = report.not_imported
	box.add_child(FsTheme.label("%d entries came over. %d were 0, empty or no in the original and needed nothing; %d are left out on purpose (this game keeps them otherwise or asks for them anew). %d could not be brought over; they are listed below." % [
		int(report.imported), int(report.at_start), int(report.get("skipped", 0)), missed.size()], 16, FsTheme.TEXT))
	box.add_child(FsTheme.section("Files"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for f: Dictionary in report.files:
		var note := "%d imported" % int(f.imported)
		if not (f.unread_columns as Array).is_empty():
			note += " · not read: " + ", ".join(f.unread_columns)
		_row(grid, str(f.name), _rows(int(f.rows)), note, FsTheme.TEXT)
	for name: String in report.missing:
		_row(grid, name, "—", "not in the folder", FsTheme.TEXT_FAINT)
	for u: Dictionary in report.unread:
		if int(u.rows) == 0:
			_row(grid, str(u.file), "empty", "nothing in this game reads this file", FsTheme.TEXT_FAINT)
		else:
			_row(grid, str(u.file), _rows(int(u.rows)), "nothing in this game reads this file", FsTheme.BAD)
	for p: Dictionary in report.problems:
		box.add_child(FsTheme.label("%s: %s" % [p.file, p.message], 15, FsTheme.BAD))
	if missed.is_empty():
		return
	box.add_child(FsTheme.section("Not brought over"))
	var by_file := {}
	for n: Dictionary in missed:
		var key := str(n.get("name", n.file))
		if not by_file.has(key):
			by_file[key] = []
		by_file[key].append(n)
	for file: String in by_file:
		box.add_child(FsTheme.heading("%s  ·  %d" % [file, by_file[file].size()], 13, FsTheme.TEXT_DIM))
		var lines: PackedStringArray = []
		for n: Dictionary in by_file[file]:
			lines.append("%s — %s" % [n.entry, n.why])
		var text := FsTheme.label("\n".join(lines), 14, FsTheme.TEXT_DIM)
		box.add_child(text)


## One line of the files table: a name and a count that do not wrap, then a note that does.
static func _row(grid: GridContainer, name: String, rows: String, note: String, color: Color) -> void:
	for text in [name, rows]:
		var l := FsTheme.label(text, 15, color if text == name else FsTheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(l)
	var n := FsTheme.label(note, 15, color if color == FsTheme.BAD else FsTheme.TEXT_DIM)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(n)


static func _rows(n: int) -> String:
	return "1 row" if n == 1 else "%d rows" % n
