class_name TitleScreen
extends Control
## The main menu: background art, the game's logo and the menu.
##
## It only draws and reports choices through `chosen`; the main screen
## decides what each choice does. The title, subtitle, logo, background and
## footer come from the loaded content (`set_branding`); without them the
## menu shows the project's name on plain colours.

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
var _credit: Label  ## the engine's credit, lower right


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
	# The engine's credit and version, in the lower right corner.
	var credit := FsTheme.label("Modular Adventure Game Engine by Seaturtle5 · %s" % engine_version(), 13, FsTheme.TEXT_FAINT)
	credit.autowrap_mode = TextServer.AUTOWRAP_OFF
	credit.add_theme_color_override("font_color", FsTheme.TEXT_DIM)
	credit.add_theme_color_override("font_shadow_color", FsTheme.SHADOW)
	credit.add_theme_constant_override("shadow_offset_x", 1)
	credit.add_theme_constant_override("shadow_offset_y", 1)
	credit.add_theme_constant_override("shadow_outline_size", 4)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credit.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	credit.grow_horizontal = GROW_DIRECTION_BEGIN
	credit.grow_vertical = GROW_DIRECTION_BEGIN
	credit.offset_right = -24
	credit.offset_bottom = -16
	add_child(credit)
	_credit = credit
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


## The engine's version (project setting application/config/version).
static func engine_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Title, subtitle, logo and background textures, footer text and the hover
## pictures from the content; empty values keep the defaults.
func set_branding(title: String, subtitle: String, logo: Texture2D, background: Texture2D, footer: String,
		menu_art: Array = []) -> void:
	_menu_art = menu_art
	if title != "":
		_title.text = title
	_subtitle.text = subtitle.to_upper()
	_subtitle.visible = subtitle != ""
	_background.texture = background
	# The credit sits on the picture where there is one: light text with a dark shadow, as on the dark theme.
	var on_art := background != null
	_credit.add_theme_color_override("font_color", FsTheme.DARK.TEXT_DIM if on_art else FsTheme.TEXT_DIM)
	_credit.add_theme_color_override("font_shadow_color", FsTheme.DARK.SHADOW if on_art else FsTheme.SHADOW)
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


func show_message(text: String) -> void:
	_message.text = text
