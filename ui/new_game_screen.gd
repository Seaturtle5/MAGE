class_name NewGameScreen
extends VBoxContainer
## The new-game screen: character creation in steps, with the character's
## sheet beside it that changes as choices are made.
##
## It builds itself from the loaded content, so any game gets it:
##   - Origin: the scenarios, as cards (left out when there is only one).
##   - Who you are: name and pronouns.
##   - One step for each larger creation question (four answers or more), as cards.
##   - Details: the small questions (up to three answers), as rows of chips.
##   - Feats: the free feat of each feat group, picked from a list.
##   - Challenge: the game modes and the content settings.
## The sheet runs the creation scripts on throwaway games for its numbers;
## values that come out differently on four tries are shown as rolled at the
## start. Keys: 1-9 pick a card, Enter goes on, Backspace goes back.

signal begin(scenario: String, player_name: String, pronouns: String, answers: Dictionary, modes: Array)

const PRONOUNS := [["he", "He / him"], ["she", "She / her"], ["they", "They / them"]]
const BIG_QUESTION := 4  ## a question with this many answers or more gets its own step

var game: Game
var _content_panel: Callable  ## builds the content settings (from the main screen)
var _content_summary: Callable  ## one line about them
var _pack_image: Callable  ## a content image by ID, or null
var _probe_cache := {}  ## the sheet's numbers by choices (the name does not change them)

var _scenarios: Array = []
var _questions: Array = []
var _feats: Array = []
var _game_modes: Array = []
var _steps: Array = []  ## [{title, kind, data}]
var _step := 0

var _scenario := ""
var _name := "Player"
var _pronoun := 0
var _answers := {}
var _modes: Array = []
var import_folder := ""  ## the folder of the original game's export files to bring in ("" for none)

var _bar: HBoxContainer
var _page: VBoxContainer
var _page_scroll: ScrollContainer
var _sheet: VBoxContainer
var _back: Button
var _next: Button
var _cards: Array = []  ## the cards on this step, for the number keys


func _init(g: Game, content_panel: Callable, content_summary: Callable, pack_image: Callable) -> void:
	game = g
	_content_panel = content_panel
	_content_summary = content_summary
	_pack_image = pack_image
	size_flags_vertical = SIZE_EXPAND_FILL
	size_flags_horizontal = SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)
	_scenarios = Array(game.content.all_of("scenario").keys())
	_scenario = str(_scenarios[0]) if not _scenarios.is_empty() else ""
	_questions = CreationSystem.questions(game)
	for q: Dictionary in _questions:
		_answers[q.id] = q.default
	_feats = CreationSystem.feat_choices(game).filter(func(f): return not f.feats.is_empty())
	for f: Dictionary in _feats:
		var ids: Array = f.feats.map(func(x): return x.id)
		_answers["feat " + str(f.group)] = f.default if f.default in ids else ids[0]
	_game_modes = CreationSystem.modes(game)

	if _scenarios.size() > 1:
		_steps.append({"title": "Origin", "kind": "origin"})
	_steps.append({"title": "Who you are", "kind": "identity"})
	var small: Array = []
	for q: Dictionary in _questions:
		if q.options.size() >= BIG_QUESTION:
			_steps.append({"title": str(q.title), "kind": "question", "data": q})
		else:
			small.append(q)
	if not small.is_empty():
		_steps.append({"title": "Details", "kind": "details", "data": small})
	if not _feats.is_empty():
		_steps.append({"title": "Feats", "kind": "feats"})
	_steps.append({"title": "Challenge", "kind": "challenge"})

	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 4)
	add_child(_bar)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	add_child(body)
	_page_scroll = ScrollContainer.new()
	_page_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_page_scroll)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 12)
	_page_scroll.add_child(_page)
	body.add_child(FsTheme.rule_v())
	var sheet_card := VBoxContainer.new()
	sheet_card.custom_minimum_size = Vector2(300, 0)
	body.add_child(sheet_card)
	_sheet = VBoxContainer.new()
	_sheet.add_theme_constant_override("separation", 8)
	sheet_card.add_child(_sheet)

	add_child(FsTheme.rule())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	add_child(foot)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(120, 0)
	_back.pressed.connect(func(): _go(_step - 1))
	foot.add_child(_back)
	var fill := Control.new()
	fill.size_flags_horizontal = SIZE_EXPAND_FILL
	foot.add_child(fill)
	_next = Button.new()
	_next.custom_minimum_size = Vector2(200, 0)
	_next.add_theme_font_override("font", FsTheme.strong_font())
	_next.add_theme_stylebox_override("normal", FsTheme.edged(Color(FsTheme.ACCENT_DIM, 0.8), FsTheme.ACCENT, 3, 16))
	_next.add_theme_stylebox_override("hover", FsTheme.edged(FsTheme.ACCENT_DIM, FsTheme.ACCENT, 3, 16))
	_next.add_theme_color_override("font_color", FsTheme.TEXT_STRONG)
	_next.pressed.connect(_forward)
	foot.add_child(_next)
	_go(0)


## Shows a step (from 0), as clicking it in the step bar.
func go_to_step(index: int) -> void:
	_go(index)


## Goes to the last step with the content settings open.
func show_content() -> void:
	_go(_steps.size() - 1)
	for c in _page.get_children():
		if c is Button and c.toggle_mode:
			c.button_pressed = true


## Keys while the screen is open; true when the key was used.
func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_9 and key - KEY_1 < _cards.size():
		var b: Button = _cards[key - KEY_1]
		if not b.disabled:
			b.pressed.emit()
		return true
	if key == KEY_ENTER or key == KEY_KP_ENTER:
		_forward()
		return true
	if key == KEY_BACKSPACE and not (get_viewport().gui_get_focus_owner() is LineEdit):
		_go(_step - 1)
		return true
	return false


func _forward() -> void:
	if _step < _steps.size() - 1:
		_go(_step + 1)
	else:
		var player_name := _name.strip_edges()
		begin.emit(_scenario, player_name if player_name != "" else "Player", PRONOUNS[_pronoun][0],
			_answers.duplicate(), _modes.duplicate())


func _go(index: int) -> void:
	_step = clampi(index, 0, _steps.size() - 1)
	_build_bar()
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	_cards.clear()
	var step: Dictionary = _steps[_step]
	match step.kind:
		"origin":
			_build_origin()
		"identity":
			_build_identity()
		"question":
			_build_question(step.data)
		"details":
			_build_details(step.data)
		"feats":
			_build_feats()
		"challenge":
			_build_challenge()
	_back.disabled = _step == 0
	_back.modulate.a = 0.0 if _step == 0 else 1.0
	if _step < _steps.size() - 1:
		_next.text = "Next: %s  ›" % str(_steps[_step + 1].title)
	else:
		_next.text = "Begin" + ("  —  " + _scenario_name(_scenario) if _scenarios.size() > 1 else "")
	_page_scroll.scroll_vertical = 0
	_update_sheet()


# --- Step bar ---------------------------------------------------------------

func _build_bar() -> void:
	for c in _bar.get_children():
		_bar.remove_child(c)
		c.queue_free()
	for i in _steps.size():
		var done := i < _step
		var here := i == _step
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, str(_steps[i].title)]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", FsTheme.label_font())
		b.add_theme_font_size_override("font_size", 14)
		var color := FsTheme.ACCENT if here else (FsTheme.TEXT_DIM if done else FsTheme.TEXT_FAINT)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(state, color if state == "font_color" else FsTheme.ACCENT)
		var line := StyleBoxFlat.new()
		line.bg_color = Color.TRANSPARENT
		line.border_color = FsTheme.ACCENT if here else (FsTheme.ACCENT_DIM if done else FsTheme.BORDER)
		line.border_width_bottom = 3 if here else 2
		line.content_margin_left = 10
		line.content_margin_right = 10
		line.content_margin_top = 6
		line.content_margin_bottom = 8
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(state, line)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(_go.bind(i))
		_bar.add_child(b)


# --- Steps ------------------------------------------------------------------

func _intro(title: String, text: String) -> void:
	_page.add_child(FsTheme.title(title, 24))
	if text != "":
		_page.add_child(FsTheme.label(text, 15, FsTheme.TEXT_DIM))


func _build_origin() -> void:
	_intro("Where does your story begin?", "Each start puts you somewhere different, with its own gear and history.")
	var grid := _grid(2)
	for id in _scenarios:
		var desc := game.content.typed_value("scenario", id, "description")
		var card := _card(grid, _scenario_name(id), desc, id == _scenario, true, _scenario_image(id))
		card.pressed.connect(func():
			_scenario = id
			_go(_step))


func _build_identity() -> void:
	_intro("Who are you?", "How the story names you and speaks of you.")
	_page.add_child(FsTheme.heading("Name"))
	var name_field := LineEdit.new()
	name_field.text = _name
	name_field.placeholder_text = "Your name"
	name_field.select_all_on_focus = true
	name_field.custom_minimum_size = Vector2(380, 44)
	name_field.size_flags_horizontal = SIZE_SHRINK_BEGIN
	name_field.add_theme_font_size_override("font_size", 20)
	name_field.text_changed.connect(func(t: String):
		_name = t
		_update_sheet())
	name_field.text_submitted.connect(func(_t): _forward())
	_page.add_child(name_field)
	name_field.grab_focus.call_deferred()
	_page.add_child(_spacer(8))
	_page.add_child(FsTheme.heading("Pronouns"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_page.add_child(row)
	for i in PRONOUNS.size():
		var chip := _chip(row, PRONOUNS[i][1], i == _pronoun)
		chip.pressed.connect(func():
			_pronoun = i
			_go(_step))
		_cards.append(chip)


func _build_question(q: Dictionary) -> void:
	_intro(str(q.title), "Pick one. Its effect shows on your sheet at the right.")
	var grid := _grid(2)
	for i in q.options.size():
		var o: Dictionary = q.options[i]
		var card := _card(grid, "%d   %s" % [i + 1, str(o.label)] if i < 9 else str(o.label), str(o.description),
			int(_answers[q.id]) == i, bool(o.enabled))
		card.pressed.connect(func():
			_answers[q.id] = i
			_go(_step))


func _build_details(qs: Array) -> void:
	_intro("A few details", "")
	for q: Dictionary in qs:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", FsTheme.box(FsTheme.SURFACE_2, FsTheme.RADIUS, Color.TRANSPARENT, 14))
		_page.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		card.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 2)
		row.add_child(text)
		text.add_child(FsTheme.label(str(q.title), 18))
		var chosen := int(_answers[q.id])
		text.add_child(FsTheme.label(str(q.options[chosen].description), 14, FsTheme.TEXT_DIM))
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation", 6)
		chips.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(chips)
		for i in q.options.size():
			var chip := _chip(chips, str(q.options[i].label), i == chosen, bool(q.options[i].enabled))
			chip.pressed.connect(func():
				_answers[q.id] = i
				_go(_step))


func _build_feats() -> void:
	_intro("Feats", "A free feat to start with. More come as you level up.")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = SIZE_EXPAND_FILL
	_page.add_child(cols)
	for f: Dictionary in _feats:
		var key := "feat " + str(f.group)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 8)
		cols.add_child(col)
		var head := HBoxContainer.new()
		head.add_child(FsTheme.section("%s feat" % str(f.group).capitalize()))
		head.get_child(0).size_flags_horizontal = SIZE_EXPAND_FILL
		var dice := Button.new()
		dice.text = "Surprise me"
		dice.focus_mode = Control.FOCUS_NONE
		dice.add_theme_font_size_override("font_size", 14)
		dice.pressed.connect(func():
			_answers[key] = f.feats[randi() % f.feats.size()].id
			_go(_step))
		head.add_child(dice)
		col.add_child(head)
		var picked: Dictionary = f.feats.filter(func(x): return x.id == _answers[key]).front()
		var shown := _card(col, str(picked.name), str(picked.description), true)
		shown.disabled = true
		shown.mouse_default_cursor_shape = Control.CURSOR_ARROW
		var list_scroll := ScrollContainer.new()
		list_scroll.custom_minimum_size = Vector2(0, 300)
		list_scroll.size_flags_vertical = SIZE_EXPAND_FILL
		list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(list_scroll)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		list_scroll.add_child(grid)
		for x: Dictionary in f.feats:
			var chip := _chip(grid, str(x.name), x.id == _answers[key])
			chip.size_flags_horizontal = SIZE_EXPAND_FILL
			chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
			chip.tooltip_text = str(x.description)
			chip.pressed.connect(func():
				_answers[key] = x.id
				_go(_step))


func _build_challenge() -> void:
	_intro("Challenge", "Optional rules that make the game harder or different.")
	if not _game_modes.is_empty():
		var grid := _grid(2)
		for m: Dictionary in _game_modes:
			var on: bool = m.id in _modes
			var card := _card(grid, ("✓  " if on else "") + str(m.name), str(m.description), on)
			card.pressed.connect(func():
				if m.id in _modes:
					_modes.erase(m.id)
				else:
					_modes.append(m.id)
				_go(_step))
	_page.add_child(_spacer(6))
	_page.add_child(FsTheme.section("Content"))
	var summary := FsTheme.label(str(_content_summary.call()), 15, FsTheme.TEXT_DIM)
	_page.add_child(summary)
	var panel: Control = _content_panel.call()
	panel.visible = false
	var toggle := Button.new()
	toggle.text = "Content settings"
	toggle.toggle_mode = true
	toggle.size_flags_horizontal = SIZE_SHRINK_BEGIN
	toggle.toggled.connect(func(on: bool):
		panel.visible = on
		summary.text = str(_content_summary.call()))
	panel.child_entered_tree.connect(func(_c: Node): summary.text = str(_content_summary.call()))
	_page.add_child(toggle)
	_page.add_child(panel)
	if ImportView.available(game):
		_page.add_child(_spacer(6))
		_page.add_child(ImportView.section(game, import_folder, set_import_folder))


## Chooses the folder of export files to import after the start ("" for none).
func set_import_folder(dir: String) -> void:
	import_folder = dir
	_go(_step)


# --- The character sheet -----------------------------------------------------

func _update_sheet() -> void:
	for c in _sheet.get_children():
		_sheet.remove_child(c)
		c.queue_free()
	_sheet.add_child(FsTheme.heading("Your character", 13, FsTheme.ACCENT))
	var shown_name := _name.strip_edges()
	var name_label := FsTheme.title(shown_name if shown_name != "" else "Player", 26)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	_sheet.add_child(name_label)
	var who: PackedStringArray = [str(PRONOUNS[_pronoun][1])]
	if _scenarios.size() > 1:
		who.append(_scenario_name(_scenario))
	_sheet.add_child(FsTheme.label(" · ".join(who), 14, FsTheme.TEXT_DIM))
	# The numbers: creation run twice on throwaway games; values that differ are rolled at the start.
	var key := str([_scenario, _pronoun, _answers, _modes, game.settings])
	if not _probe_cache.has(key):
		_probe_cache[key] = [[_probe(7), _probe(1009), _probe(52361), _probe(918273)], _probe_base()]
	var tries: Array = _probe_cache[key][0]
	var a: Dictionary = tries[0]
	var varies := func(k: String) -> bool: return tries.any(func(t): return t.get(k) != a.get(k))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_sheet.add_child(_spacer(4))
	_sheet.add_child(grid)
	var base: Dictionary = _probe_cache[key][1]
	for k: String in Game.ATTRIBUTES:
		var rolled: bool = varies.call(k)
		grid.add_child(_stat_block(k, int(a.get(k, 0)), rolled, int(a.get(k, 0)) > int(base.get(k, 0))))
	if a.has("maxhp"):
		var rolled_hp: bool = varies.call("maxhp")
		_sheet.add_child(_fact("Health", "?" if rolled_hp else str(int(a.maxhp))))
	if Game.ATTRIBUTES.any(func(k): return varies.call(k)):
		_sheet.add_child(FsTheme.label("? — rolled when the game starts.", 13, FsTheme.TEXT_FAINT))
	_sheet.add_child(_spacer(6))
	for q: Dictionary in _questions:
		_sheet.add_child(_fact(str(q.title), str(q.options[int(_answers[q.id])].label)))
	for f: Dictionary in _feats:
		var id = _answers["feat " + str(f.group)]
		_sheet.add_child(_fact("%s feat" % str(f.group).capitalize(),
			game.content.typed_value("feat", str(id), "name", str(id))))
	if not _game_modes.is_empty():
		var names: Array = _game_modes.filter(func(m): return m.id in _modes).map(func(m): return str(m.name))
		_sheet.add_child(_fact("Modes", ", ".join(names) if not names.is_empty() else "None"))


## The player's values after creation with the current choices, on a throwaway game.
func _probe(seed_value: int) -> Dictionary:
	var probe := Game.new(game.content, seed_value)
	probe.settings = game.settings.duplicate(true)
	probe.settings.mode = _modes.duplicate()
	probe.settings.scenario = _scenario
	probe.set_value("player.name", _name)
	probe.set_value("player.pronouns", PRONOUNS[_pronoun][0])
	CreationSystem.create(probe, _answers)
	var out := {}
	for k: String in Game.ATTRIBUTES:
		out[k] = probe.value("player." + k)
	out["maxhp"] = probe.value("player.maxhp")
	probe.dispose()
	return out


## The values before any choice (the `before` script alone), to mark what the choices raised.
func _probe_base() -> Dictionary:
	var probe := Game.new(game.content, 7)
	var r := CreationSystem.rules(probe)
	if r != "" and probe.content.program("creation_rules:%s#before" % r) != null:
		probe.runner.play_now("creation_rules:%s#before" % r)
	var out := {}
	for k: String in Game.ATTRIBUTES:
		out[k] = probe.value("player." + k)
	probe.dispose()
	return out


func _stat_block(key: String, value: int, rolled: bool, raised: bool) -> Control:
	var block := PanelContainer.new()
	var style := FsTheme.box(FsTheme.SURFACE_2, FsTheme.RADIUS, FsTheme.ACCENT if raised and not rolled else Color.TRANSPARENT, 8)
	block.add_theme_stylebox_override("panel", style)
	block.size_flags_horizontal = SIZE_EXPAND_FILL
	block.tooltip_text = key.capitalize() + (" (rolled when the game starts)" if rolled else " %d (modifier %+d)" % [value, (value - 10) / 2])
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var abbr := FsTheme.heading(key.substr(0, 3), 12, FsTheme.TEXT_FAINT)
	abbr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(abbr)
	var num := FsTheme.title("?" if rolled else str(value), 24, FsTheme.ACCENT if raised or rolled else FsTheme.TEXT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(num)
	block.add_child(inner)
	return block


func _fact(label: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var l := FsTheme.heading(label, 12, FsTheme.TEXT_FAINT)
	l.custom_minimum_size = Vector2(120, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var v := FsTheme.label(value, 15)
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(v)
	return row


# --- Pieces -----------------------------------------------------------------

func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_page.add_child(grid)
	return grid


## A choice card: a title and a description; the chosen one is lit.
func _card(parent: Control, title: String, description: String, chosen: bool, enabled: bool = true,
		picture: Texture2D = null) -> Button:
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(holder)
	var b := Button.new()
	b.disabled = not enabled
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var rest := FsTheme.edged(Color(FsTheme.ACCENT_DIM, 0.55), FsTheme.ACCENT, 3, 16) if chosen \
		else FsTheme.box(FsTheme.SURFACE_2, FsTheme.RADIUS, Color.TRANSPARENT, 16)
	b.add_theme_stylebox_override("normal", rest)
	b.add_theme_stylebox_override("disabled", rest)
	b.add_theme_stylebox_override("hover", FsTheme.edged(Color(FsTheme.ACCENT_DIM, 0.55) if chosen else FsTheme.SURFACE_3, FsTheme.ACCENT, 3, 16))
	holder.add_child(b)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16 if side in ["left", "right"] else 12)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)
	if picture != null:
		var art := TextureRect.new()
		art.texture = picture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.custom_minimum_size = Vector2(96, 96)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(art)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 4)
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var t := FsTheme.title(title, 18, FsTheme.ACCENT if chosen else FsTheme.TEXT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(t)
	if description != "":
		var d := FsTheme.label(description, 14, FsTheme.TEXT_DIM)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(d)
	if not enabled:
		pad.modulate.a = 0.4
	_cards.append(b)
	return b


## A small pill for short answers.
func _chip(parent: Control, text: String, chosen: bool, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_ALL
	var rest := FsTheme.box(Color(FsTheme.ACCENT_DIM, 0.7) if chosen else FsTheme.SURFACE_2, 16,
		FsTheme.ACCENT if chosen else FsTheme.BORDER, 14)
	rest.content_margin_top = 6
	rest.content_margin_bottom = 6
	var hover := rest.duplicate() as StyleBoxFlat
	hover.border_color = FsTheme.ACCENT
	b.add_theme_stylebox_override("normal", rest)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", rest)
	b.add_theme_color_override("font_color", FsTheme.TEXT_STRONG if chosen else FsTheme.TEXT)
	parent.add_child(b)
	return b


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _scenario_name(id: String) -> String:
	return game.content.typed_value("scenario", id, "name", id)


## A scenario's `image:` for its card, when it has one.
func _scenario_image(id: String) -> Texture2D:
	var image := game.content.image_of("scenario", id)
	return _pack_image.call(image) if image != "" else null
