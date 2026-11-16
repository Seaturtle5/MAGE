class_name OriginalExport
extends RefCounted
## Reads the files an Inform 7 game writes with "write File of X from the Table
## of Y" (Glk data files, usually named "<name>.glkdata"):
##
##   * //IFID// FileName                  ("*" when complete, "-" while being written)
##   ! Table of Something (3)             (the table's name and filled rows)
##   S72,105,0; 12 1 --                   (one line per row: cells followed by a space)
##
## A text cell is "S", its Unicode code points separated by commas, then ",0;"
## ("S0;" when empty); numbers are decimal, truth states 1 or 0, a blank cell "--".
## The file does not name its columns; whoever reads it knows their order.
## Texts stay Strings, numbers become ints and blank cells null.

const EXTENSIONS := ["glkdata", "glkd", "dat", "txt"]


## Reads one file's text. Returns {"name", "table", "rows": [[cells]], "complete",
## "problems": [plain messages]}.
static func parse(text: String, fallback_name: String = "") -> Dictionary:
	var out := {"name": fallback_name, "table": "", "rows": [], "complete": true, "problems": []}
	var lines := text.replace("\r\n", "\n").split("\n")
	var i := 0
	if lines.size() > 0 and (lines[0].begins_with("*") or lines[0].begins_with("-")):
		out.complete = lines[0].begins_with("*")
		var parts := lines[0].split("//")
		if parts.size() >= 3 and parts[2].strip_edges() != "":
			out.name = parts[2].strip_edges()
		i = 1
	if i < lines.size() and lines[i].begins_with("!"):
		var head := lines[i].substr(1).strip_edges()
		var open := head.rfind(" (")
		out.table = head.substr(0, open) if open >= 0 else head
		i += 1
	if not out.complete:
		out.problems.append("The file was not finished when it was written.")
	for n in range(i, lines.size()):
		var line := lines[n]
		if line.strip_edges() == "":
			continue
		var row := parse_row(line)
		if row.has("problem"):
			out.problems.append("Line %d: %s" % [n + 1, row.problem])
			continue
		out.rows.append(row.cells)
	return out


## One row line: {"cells": [...]} or {"problem": "..."}.
static func parse_row(line: String) -> Dictionary:
	var cells: Array = []
	var at := 0
	var size := line.length()
	while at < size:
		var c := line[at]
		if c == " " or c == "\t":
			at += 1
			continue
		if c == "S":
			var end := line.find(";", at)
			if end < 0:
				return {"problem": "a text does not end with ';'."}
			var codes := line.substr(at + 1, end - at - 1).split(",", false)
			var text := ""
			for code in codes:
				if not code.is_valid_int():
					return {"problem": "a text holds '%s', which is not a character number." % code}
				var n := int(code)
				if n == 0:
					break
				text += String.chr(n)
			cells.append(text)
			at = end + 1
			continue
		var stop := line.find(" ", at)
		if stop < 0:
			stop = size
		var word := line.substr(at, stop - at)
		if word == "--":
			cells.append(null)
		elif word.is_valid_int():
			cells.append(int(word))
		elif word.is_valid_float():
			cells.append(float(word))
		else:
			return {"problem": "'%s' is not a number, a text or a blank." % word}
		at = stop
	return {"cells": cells}


## The export files in a folder: {lower-case name -> parsed file (with "path")}.
## A name may end in .glkdata (or another data ending) or have none.
static func read_folder(folder: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	var files := Array(dir.get_files())
	files.sort()
	for f: String in files:
		var ext := f.get_extension().to_lower()
		var base := f.get_basename() if ext in EXTENSIONS else f
		if ext != "" and ext not in EXTENSIONS:
			continue
		var path := folder.path_join(f)
		var text := FileAccess.get_file_as_string(path)
		if not (text.begins_with("* //") or text.begins_with("- //") or text.begins_with("!")):
			continue  # not an Inform table file
		var parsed := parse(text, base)
		parsed["path"] = path
		var key := base.to_lower()
		if out.has(key) and ext != "glkdata":
			continue  # the .glkdata one wins over a copy with another ending
		out[key] = parsed
	return out
