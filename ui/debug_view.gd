class_name DebugView
extends HBoxContainer
## The Debug window, for someone who makes content: on the left a line to type
## a command or an action into, with what it could become listed below as it
## is typed (every command when nothing is typed); on the right the game's
## values, looked up by a part of their name and changed by hand.
##
## The rules are the engine's (DebugSystem); this view only shows them. What a
## line makes the game say goes to the game's page as usual (`after_run`), and
## is repeated here, since the window covers the page.

const ROWS := 150  ## values shown at once
const SUGGESTIONS := 60

static var typed := ""  ## the line being typed, kept between openings
static var searched := ""  ## the value search, kept between openings
static var only_changed := false
static var history: Array = []  ## lines that ran, oldest first

var game: Game
var after_run: Callable  ## shows what the game put out
var close: Callable  ## closes the window
var line: LineEdit
var run_button: Button
var outcome: Label
var said: Label
var suggestions: VBoxContainer
var search: LineEdit
var changed_box: CheckBox
var count: Label
var rows: VBoxContainer
var value_note: Label
var _history_at := -1
var _first: Dictionary = {}  ## the first suggestion, which Tab completes to


func setup(playing: Game, show_output: Callable, close_window: Callable) -> void:
	game = playing
	after_run = show_output
	close = close_window
	add_theme_constant_override("separation", 22)
	add_child(_commands_side())
	add_child(FsTheme.rule_v())
	add_child(_values_side())
	_suggest()
	_fill_values()
	line.grab_focus.call_deferred()
	line.caret_column = line.text.length()


# --- Commands -------------------------------------------------------------------

func _commands_side() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.15
	col.add_theme_constant_override("separation", 10)
	col.add_child(FsTheme.section("Commands and actions"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	line = LineEdit.new()
	line.placeholder_text = "A command's name, or an action such as  ~ give rope 2"
	line.text = typed
	line.size_flags_horizontal = SIZE_EXPAND_FILL
	line.custom_minimum_size = Vector2(0, 44)
	line.add_theme_font_size_override("font_size", 17)
	line.text_changed.connect(func(text: String) -> void:
		typed = text
		_history_at = -1
		_suggest())
	line.text_submitted.connect(func(_text: String) -> void: _run(line.text))
	line.gui_input.connect(_line_key)
	row.add_child(line)
	run_button = Button.new()
	run_button.text = "Run"
	run_button.custom_minimum_size = Vector2(96, 44)
	run_button.add_theme_font_override("font", FsTheme.strong_font())
	run_button.pressed.connect(func() -> void: _run(line.text))
	row.add_child(run_button)
	col.add_child(row)
	col.add_child(FsTheme.label("Enter runs the line · Tab completes it · Up and Down bring back earlier lines", 13, FsTheme.TEXT_FAINT))
	outcome = FsTheme.label("", 15, FsTheme.TEXT_DIM)
	outcome.visible = false
	col.add_child(outcome)
	said = FsTheme.label("", 14, FsTheme.TEXT_DIM)
	said.visible = false
	col.add_child(said)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	suggestions = VBoxContainer.new()
	suggestions.size_flags_horizontal = SIZE_EXPAND_FILL
	suggestions.add_theme_constant_override("separation", 2)
	scroll.add_child(suggestions)
	col.add_child(scroll)
	return col


## Tab completes to the first suggestion; Up and Down walk the lines run before.
func _line_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var key: int = (event as InputEventKey).keycode
	if key == KEY_TAB:
		if not _first.is_empty():
			_take(str(_first.text))
		line.accept_event()
	elif key == KEY_UP or key == KEY_DOWN:
		if history.is_empty():
			return
		if _history_at < 0:
			_history_at = history.size()
		_history_at = clampi(_history_at + (-1 if key == KEY_UP else 1), 0, history.size())
		_take(str(history[_history_at]) if _history_at < history.size() else "", false)
		line.accept_event()


## Puts a text on the line, ready to go on typing.
func _take(text: String, fresh_history: bool = true) -> void:
	line.text = text
	line.caret_column = text.length()
	typed = text
	if fresh_history:
		_history_at = -1
	_suggest()
	line.grab_focus()


## The list under the line: what the typed text could become.
func _suggest() -> void:
	for c in suggestions.get_children():
		c.queue_free()
	var found: Array = DebugSystem.suggest(game, line.text, SUGGESTIONS)
	_first = found[0] if not found.is_empty() and line.text.strip_edges() != "" else {}
	if found.is_empty():
		suggestions.add_child(FsTheme.label("Nothing starts like that. Enter runs the line as it is.", 14, FsTheme.TEXT_FAINT))
		return
	var heading := ""
	for s: Dictionary in found:
		var under: String = "Actions" if s.command == "" else ("Debug commands" if DebugSystem.is_debug(game.content, s.command) else "Commands")
		if line.text.strip_edges() == "" and under != heading:
			heading = under
			suggestions.add_child(FsTheme.heading(under, 12, FsTheme.TEXT_FAINT))
		suggestions.add_child(_suggestion(s))


func _suggestion(s: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_stylebox_override("normal", FsTheme.box(Color.TRANSPARENT, FsTheme.RADIUS, Color.TRANSPARENT, 8))
	# The face: what it is called, what it does (dim), and a word about it at the right.
	var face := HBoxContainer.new()
	face.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	face.offset_left = 10
	face.offset_right = -10
	face.add_theme_constant_override("separation", 14)
	face.mouse_filter = MOUSE_FILTER_IGNORE
	var name := _one_line(str(s.label), FsTheme.TEXT)
	face.add_child(name)
	var note := _one_line(str(s.note), FsTheme.TEXT_DIM)
	note.size_flags_horizontal = SIZE_EXPAND_FILL
	note.clip_text = true
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	face.add_child(note)
	if str(s.get("tag", "")) != "":
		face.add_child(_one_line(str(s.tag), FsTheme.ACCENT if str(s.tag) == "debug" else FsTheme.TEXT_FAINT, 13))
	b.add_child(face)
	if s.command != "":
		b.tooltip_text = "Run %s%s" % [s.label, ": " + str(s.note) if str(s.note) != "" else ""]
		var id := str(s.command)
		b.pressed.connect(func() -> void: _run(id))
	else:
		b.tooltip_text = "Put this on the line"
		var text := str(s.text)
		b.pressed.connect(func() -> void: _take(text))
	return b


func _one_line(text: String, color: Color, size: int = 15) -> Label:
	var l := FsTheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	return l


func _run(text: String) -> void:
	var r: Dictionary = DebugSystem.run(game, text)
	outcome.text = str(r.message)
	outcome.add_theme_color_override("font_color", FsTheme.GOOD if r.ok else FsTheme.BAD)
	outcome.visible = true
	var lines: Array = r.said
	said.text = "\n".join(lines.slice(0, 6).map(func(t: Variant) -> String: return str(t).left(160))) + ("\n…" if lines.size() > 6 else "")
	said.visible = not lines.is_empty()
	if not r.ok:
		line.grab_focus()
		return
	if history.is_empty() or str(history[-1]) != text.strip_edges():
		history.append(text.strip_edges())
	typed = ""
	after_run.call()
	if game.runner.status != "idle" or game.state.ending != "":
		close.call()  # a scene or a fight began: it is the game's turn
		return
	_take("")
	_fill_values()


# --- Values -----------------------------------------------------------------------

func _values_side() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	col.add_child(FsTheme.section("Values"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	search = LineEdit.new()
	search.placeholder_text = "Look up a value: part of its name"
	search.text = searched
	search.size_flags_horizontal = SIZE_EXPAND_FILL
	search.custom_minimum_size = Vector2(0, 44)
	search.add_theme_font_size_override("font_size", 17)
	search.text_changed.connect(func(text: String) -> void:
		searched = text
		_fill_values())
	row.add_child(search)
	changed_box = CheckBox.new()
	changed_box.text = "Changed only"
	changed_box.tooltip_text = "Only the values that differ from how they start"
	changed_box.button_pressed = only_changed
	changed_box.toggled.connect(func(on: bool) -> void:
		only_changed = on
		_fill_values())
	row.add_child(changed_box)
	col.add_child(row)
	count = FsTheme.label("", 13, FsTheme.TEXT_FAINT)
	col.add_child(count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	col.add_child(scroll)
	value_note = FsTheme.label("", 14, FsTheme.TEXT_DIM)
	value_note.visible = false
	col.add_child(value_note)
	return col


func _fill_values() -> void:
	for c in rows.get_children():
		c.queue_free()
	var found: Dictionary = DebugSystem.values(game, search.text, changed_box.button_pressed, ROWS)
	var shown: int = found.rows.size()
	if shown == 0:
		count.text = "No value is called so." if search.text.strip_edges() != "" else "No values."
	elif shown < int(found.matched):
		count.text = "The first %d of %d: type more of the name to narrow it down. Values that differ from their start are marked." % [shown, found.matched]
	else:
		count.text = "%d value%s. Those that differ from their start are marked." % [shown, "" if shown == 1 else "s"]
	for r: Dictionary in found.rows:
		rows.add_child(_value_row(r))


func _value_row(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name := FsTheme.label(str(r.path), 15, FsTheme.ACCENT if r.changed else FsTheme.TEXT)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.clip_text = true
	name.size_flags_horizontal = SIZE_EXPAND_FILL
	name.mouse_filter = MOUSE_FILTER_STOP
	name.tooltip_text = "%s\n%s, starts as %s" % [r.path, _kind_words(r), r.default if str(r.default) != "" else "nothing"]
	row.add_child(name)
	var path := str(r.path)
	match str(r.kind):
		"flag":
			var box := CheckButton.new()
			box.custom_minimum_size = Vector2(190, 0)
			box.button_pressed = str(r.shown) == "yes"
			box.text = str(r.shown)
			box.toggled.connect(func(on: bool) -> void: _change(path, "yes" if on else "no"))
			row.add_child(box)
		"states":
			var pick := OptionButton.new()
			pick.fit_to_longest_item = false
			pick.clip_text = true
			pick.custom_minimum_size = Vector2(190, 0)
			var states: Array = r.states
			for st: Variant in states:
				pick.add_item(str(st))
			pick.select(states.find(str(r.shown)))
			pick.item_selected.connect(func(i: int) -> void: _change(path, str(states[i])))
			row.add_child(pick)
		"list":
			var shown := FsTheme.label(str(r.shown) if str(r.shown) != "" else "(empty)", 15, FsTheme.TEXT_DIM)
			shown.custom_minimum_size = Vector2(190, 0)
			shown.autowrap_mode = TextServer.AUTOWRAP_OFF
			shown.clip_text = true
			shown.tooltip_text = "A list: change it with an action, such as  ~ add 3 to %s" % path
			shown.mouse_filter = MOUSE_FILTER_STOP
			row.add_child(shown)
		_:
			var field := LineEdit.new()
			field.text = str(r.shown)
			field.custom_minimum_size = Vector2(190, 0)
			field.add_theme_font_size_override("font_size", 15)
			field.tooltip_text = "Enter sets it" + ("; a time is now, never, or how many turns ago" if str(r.kind) == "time" else "")
			field.text_submitted.connect(func(text: String) -> void: _change(path, text))
			row.add_child(field)
	return row


func _kind_words(r: Dictionary) -> String:
	match str(r.kind):
		"flag":
			return "yes or no"
		"states":
			return "one of: %s" % ", ".join((r.states as Array).map(func(s: Variant) -> String: return str(s)))
		"time":
			return "a time"
		"list":
			return "a list"
		"text":
			return "a text"
	return "a number"


func _change(path: String, text: String) -> void:
	var r: Dictionary = DebugSystem.set_value(game, path, text)
	value_note.text = str(r.message)
	value_note.add_theme_color_override("font_color", FsTheme.GOOD if r.ok else FsTheme.BAD)
	value_note.visible = true
	if r.ok:
		after_run.call()
	_fill_values.call_deferred()
