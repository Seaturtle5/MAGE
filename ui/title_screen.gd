class_name TitleScreen
extends Control
## The main menu: background art, the game's logo and the menu.
##
## It only draws and reports choices through `chosen`; the main screen
## decides what each choice does. The title, subtitle, logo, background and
## footer come from the loaded content (`set_branding`); without them the
## menu shows the project's name on plain colours. The engine's own card
## (lower right) and the Report a bug / Feedback button (bottom middle) are
## always there.

signal chosen(action: String)

var _continue_button: Button
var _background: TextureRect
var _logo: TextureRect
var _title: Label
var _subtitle: Label
var _footer: Label
var _continue_info: Label
var _message: Label
var _menu: VBoxContainer
var _menu_art: Array = []  ## pictures that pop up beside the hovered entry (pack `menu icons`)
var _hover_art: TextureRect
var _art_tween: Tween
var _last_art := -1
var _engine_card: PanelContainer  ## the engine's own card, lower right
var _report: Button  ## Report a bug / Feedback, bottom middle


func _init() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = FsTheme.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_background)
	# Darken the left side, where the menu is, so it reads on any art.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(FsTheme.BG, 0.94))
	gradient.set_color(1, Color(FsTheme.BG, 0.0))
	gradient.set_offset(0, 0.25)
	gradient.set_offset(1, 0.75)
	var gt := GradientTexture2D.new()
	gt.gradient = gradient
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(480, 0)
	col.size_flags_horizontal = SIZE_SHRINK_BEGIN
	margin.add_child(col)
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.visible = false
	col.add_child(_logo)
	_title = FsTheme.label(str(ProjectSettings.get_setting("application/config/name", "")), 58, FsTheme.ACCENT)
	_title.add_theme_font_override("font", FsTheme.strong_font())
	col.add_child(_title)
	_subtitle = FsTheme.heading("", 14, FsTheme.ACCENT)
	col.add_child(_subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	col.add_child(gap)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 2)
	col.add_child(_menu)
	_continue_button = _button("continue", "Continue")
	_continue_info = FsTheme.label("", 14, FsTheme.TEXT_DIM)
	var indent := StyleBoxEmpty.new()
	indent.content_margin_left = 18
	indent.content_margin_bottom = 8
	_continue_info.add_theme_stylebox_override("normal", indent)
	_continue_info.custom_minimum_size = Vector2(380, 0)
	_menu.add_child(_continue_info)
	for spec in [["new", "New game"], ["load", "Load game"], ["settings", "Settings"], ["credits", "Credits"], ["quit", "Quit"]]:
		_button(spec[0], spec[1])
	_message = FsTheme.label("", 15, FsTheme.BAD)
	col.add_child(_message)
	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(fill)
	_footer = FsTheme.label("", 13, FsTheme.TEXT_FAINT)
	col.add_child(_footer)
	# The engine's own card in the lower right corner: its name, an invitation
	# to make a game with it, its Discord and GitHub, its maker and version. Packs cannot change it.
	_engine_card = _make_engine_card()
	add_child(_engine_card)
	# Report a bug / Feedback, at the bottom in the middle (as in the game's tool bar).
	_report = Button.new()
	_report.add_theme_stylebox_override("normal", FsTheme.box(Color(FsTheme.SURFACE, 0.82), FsTheme.RADIUS, Color(FsTheme.ACCENT, 0.35), 0))
	_report.pressed.connect(func(): chosen.emit("report"))
	var face := HBoxContainer.new()
	face.add_theme_constant_override("separation", 6)
	face.mouse_filter = MOUSE_FILTER_IGNORE
	var bug := "res://ui/icons/bug.svg"
	if ResourceLoader.exists(bug):
		var icon := TextureRect.new()
		icon.texture = load(bug) as Texture2D
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(16, 16)
		icon.self_modulate = FsTheme.ACCENT
		icon.mouse_filter = MOUSE_FILTER_IGNORE
		face.add_child(icon)
	var words := FsTheme.label("Report a bug / Feedback", 15, FsTheme.ACCENT)
	words.autowrap_mode = TextServer.AUTOWRAP_OFF
	words.mouse_filter = MOUSE_FILTER_IGNORE
	face.add_child(words)
	var pad := MarginContainer.new()
	pad.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	pad.add_child(face)
	# The button and its face share a holder that sizes both to the face.
	var holder := MarginContainer.new()
	holder.add_child(_report)
	holder.add_child(pad)
	holder.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	holder.grow_horizontal = GROW_DIRECTION_BOTH
	holder.grow_vertical = GROW_DIRECTION_BEGIN
	holder.offset_bottom = -12  # below the footer, which ends 48 above the bottom
	add_child(holder)
	# Light or dark: a sun and a moon in the upper right corner; the one in use is lit.
	var modes := PanelContainer.new()
	modes.add_theme_stylebox_override("panel", FsTheme.box(Color(FsTheme.SURFACE, 0.82), 20, FsTheme.BORDER, 4))
	modes.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	modes.grow_horizontal = GROW_DIRECTION_BEGIN
	modes.offset_right = -24
	modes.offset_top = 20
	add_child(modes)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 2)
	modes.add_child(pair)
	pair.add_child(_theme_button("sun", "light", "Light theme", FsTheme.light))
	pair.add_child(_theme_button("moon", "dark", "Dark theme", not FsTheme.light))


## A round icon button for the light or dark theme.
func _theme_button(icon: String, action: String, tip: String, active: bool) -> Button:
	var b := Button.new()
	var path := "res://ui/icons/%s.svg" % icon
	if ResourceLoader.exists(path):
		b.icon = load(path) as Texture2D
	else:
		b.text = tip.substr(0, 1)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(38, 38)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rest := FsTheme.box(Color(FsTheme.ACCENT_DIM, 0.9) if active else Color.TRANSPARENT, 17, Color.TRANSPARENT, 8)
	var hover := FsTheme.box(FsTheme.SURFACE_3, 17, Color.TRANSPARENT, 8)
	var ring := FsTheme.box(Color.TRANSPARENT, 17, FsTheme.ACCENT, 8)
	for state in ["normal", "disabled"]:
		b.add_theme_stylebox_override(state, rest)
	for state in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, hover)
	b.add_theme_stylebox_override("focus", ring)
	var tint := FsTheme.ACCENT if active else FsTheme.TEXT_DIM
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_color_override("icon_%s_color" % state, FsTheme.ACCENT if state != "normal" else tint)
	b.pressed.connect(func(): chosen.emit(action))
	return b


## The engine's Discord, where people who make their own games meet, and its code.
const ENGINE_DISCORD := "https://discord.gg/K8YGRC7sWK"
const ENGINE_GITHUB := "https://github.com/Seaturtle5/MAGE"


## The engine's card: MAGE, "Make your own adventure game", its Discord and
## GitHub, its maker and version. Quiet on purpose: small type in the faint
## text colours on a thin translucent panel, so it is found by those looking
## for it and never draws the eye from the game's title and menu.
func _make_engine_card() -> PanelContainer:
	var card := PanelContainer.new()
	# Translucent on the dark palette; on the light one the art behind is dark, so less see-through to stay readable.
	card.add_theme_stylebox_override("panel", FsTheme.box(Color(FsTheme.SURFACE, 0.85 if FsTheme.light else 0.6), FsTheme.RADIUS, Color(FsTheme.BORDER, 0.7), 14))
	card.custom_minimum_size = Vector2(220, 0)
	card.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	card.grow_horizontal = GROW_DIRECTION_BEGIN
	card.grow_vertical = GROW_DIRECTION_BEGIN
	card.offset_right = -24
	card.offset_bottom = -12
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	var name := FsTheme.label("MAGE", 17, FsTheme.TEXT_DIM)
	name.add_theme_font_override("font", FsTheme.strong_font())
	col.add_child(name)
	col.add_child(FsTheme.heading("Modular Adventure Game Engine", 10, FsTheme.TEXT_FAINT))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 3)
	col.add_child(gap)
	var pitch := FsTheme.label("Make your own adventure game with this engine.", 13, FsTheme.TEXT_DIM)
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(pitch)
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 4)
	links.add_child(_card_link("Discord", ENGINE_DISCORD))
	links.add_child(_card_link("GitHub", ENGINE_GITHUB))
	col.add_child(links)
	col.add_child(FsTheme.label("Made by Seaturtle5 · version %s" % engine_version(), 12, FsTheme.TEXT_FAINT))
	return card


## A quiet link-button on the engine's card that opens `url` in the browser:
## faint text and a faint outline, a little brighter on hover.
func _card_link(text: String, url: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = url
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", FsTheme.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", FsTheme.TEXT)
	b.add_theme_color_override("font_pressed_color", FsTheme.TEXT)
	b.add_theme_color_override("font_focus_color", FsTheme.TEXT_DIM)
	var looks := {"normal": [Color.TRANSPARENT, Color(FsTheme.BORDER, 0.8)], "hover": [Color(FsTheme.SURFACE_3, 0.5), FsTheme.BORDER],
		"pressed": [FsTheme.SURFACE_3, FsTheme.BORDER], "hover_pressed": [FsTheme.SURFACE_3, FsTheme.BORDER],
		"focus": [Color.TRANSPARENT, FsTheme.TEXT_FAINT]}
	for state: String in looks:
		var box := FsTheme.box(looks[state][0], FsTheme.RADIUS, looks[state][1], 8)
		box.content_margin_top = 2
		box.content_margin_bottom = 2
		b.add_theme_stylebox_override(state, box)
	b.pressed.connect(func(): OS.shell_open(url))
	return b


## The engine's version (project setting application/config/version).
static func engine_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Title, subtitle, logo and background textures, footer text and the hover
## pictures from the content; empty values keep the defaults.
## `version` is the game's own, shown after the subtitle.
func set_branding(title: String, subtitle: String, logo: Texture2D, background: Texture2D, footer: String,
		menu_art: Array = [], version: String = "") -> void:
	_menu_art = menu_art
	if title != "":
		_title.text = title
	var line: PackedStringArray = []
	if subtitle != "":
		line.append(subtitle)
	if version != "":
		line.append("Version " + version)
	_subtitle.text = " · ".join(line).to_upper()
	_subtitle.visible = not line.is_empty()
	_background.texture = background
	_logo.texture = logo
	_logo.visible = logo != null
	_title.visible = logo == null
	if logo != null:
		_logo.custom_minimum_size = Vector2(480, 480.0 * logo.get_height() / logo.get_width())
	_footer.text = footer
	_footer.visible = footer != ""


func _button(action: String, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(340, 50)
	b.add_theme_font_override("font", FsTheme.strong_font())
	b.add_theme_font_size_override("font_size", 22)
	# Menu entries are text on the art; hover and focus add a panel and an amber edge.
	var rest := FsTheme.box(Color.TRANSPARENT, FsTheme.RADIUS, Color.TRANSPARENT, 18)
	b.add_theme_stylebox_override("normal", rest)
	b.add_theme_stylebox_override("hover", FsTheme.edged(Color(FsTheme.SURFACE_2, 0.85), FsTheme.ACCENT, 3, 26))
	b.add_theme_stylebox_override("pressed", FsTheme.edged(Color(FsTheme.ACCENT_DIM, 0.9), FsTheme.ACCENT, 3, 18))
	b.add_theme_stylebox_override("focus", FsTheme.edged(Color.TRANSPARENT, FsTheme.ACCENT, 3, 18))
	b.size_flags_horizontal = SIZE_SHRINK_BEGIN
	b.pressed.connect(func(): chosen.emit(action))
	b.mouse_entered.connect(_show_art.bind(b))
	b.focus_entered.connect(_show_art.bind(b))
	b.mouse_exited.connect(_hide_art.bind(b))
	_menu.add_child(b)
	return b


## A creature picture pops up beside the hovered (or focused) entry.
func _show_art(b: Button) -> void:
	if _menu_art.is_empty() or not is_visible_in_tree():
		return
	if _hover_art == null:
		_hover_art = TextureRect.new()
		_hover_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_hover_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_hover_art.mouse_filter = MOUSE_FILTER_IGNORE
		_hover_art.self_modulate = FsTheme.ACCENT
		add_child(_hover_art)
	var pick := randi() % _menu_art.size()
	if _menu_art.size() > 1 and pick == _last_art:
		pick = (pick + 1) % _menu_art.size()
	_last_art = pick
	_hover_art.texture = _menu_art[pick]
	var side := 72.0
	_hover_art.size = Vector2(side, side)
	_hover_art.pivot_offset = Vector2(side, side) / 2
	var rect := b.get_global_rect()
	# Just after the entry's text (the hover style indents it by 26).
	var text_width := b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		b.get_theme_font_size("font_size")).x
	var target := rect.position - global_position + Vector2(26 + text_width + 18, (rect.size.y - side) / 2)
	_hover_art.position = target - Vector2(14, 0)
	_hover_art.modulate.a = 0.0
	_hover_art.scale = Vector2(0.6, 0.6)
	_hover_art.rotation = -0.35 if randi() % 2 == 0 else 0.35
	_hover_art.visible = true
	if _art_tween != null:
		_art_tween.kill()
	_art_tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_art_tween.tween_property(_hover_art, "modulate:a", 0.9, 0.18)
	_art_tween.tween_property(_hover_art, "position", target, 0.28)
	_art_tween.tween_property(_hover_art, "scale", Vector2.ONE, 0.32)
	_art_tween.tween_property(_hover_art, "rotation", 0.0, 0.4).set_trans(Tween.TRANS_ELASTIC)


func _hide_art(b: Button) -> void:
	if _hover_art == null or b.has_focus():
		return
	if _art_tween != null:
		_art_tween.kill()
	_art_tween = create_tween()
	_art_tween.tween_property(_hover_art, "modulate:a", 0.0, 0.15)


## Shows or hides Continue with a line about the newest save.
func set_continue(info: String) -> void:
	_continue_button.visible = info != ""
	_continue_info.visible = info != ""
	_continue_info.text = info
	(_continue_button if info != "" else _menu.get_child(2) as Button).grab_focus.call_deferred()


## The Report button's tooltip (that reports cannot be sent yet, when so).
func set_report_tip(text: String) -> void:
	_report.tooltip_text = text


func show_message(text: String) -> void:
	_message.text = text
