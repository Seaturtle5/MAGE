class_name FsTheme
extends RefCounted
## The game's visual theme, built in code so it is readable and diffable.
##
## Warm ink tones lit by one lantern-amber accent, matching the title art.
## Story text is set in a book serif (Literata); the interface uses a
## sturdy grotesque (Barlow) with condensed, letter-spaced labels. Surfaces
## are flat with small radii; hover and focus show an amber edge rather than
## an outlined box. All colors and fonts live here so the look can be
## changed in one place.
##
## Two palettes: dark (ink, the default) and light (warm paper, the same
## amber deepened for contrast). `use_palette` switches them; controls built
## afterwards use the new colors, so the screens are rebuilt after a switch.

const DARK := {
	"BG": Color("0f0e0c"), "SURFACE": Color("191714"), "SURFACE_2": Color("221f1b"), "SURFACE_3": Color("2d2924"),
	"BORDER": Color("38322b"), "TEXT": Color("ece5d8"), "TEXT_DIM": Color("a9a092"), "TEXT_FAINT": Color("71695e"),
	"TEXT_STRONG": Color("ffffff"), "ACCENT": Color("e3a04f"), "ACCENT_DIM": Color("5e4224"),
	"GOOD": Color("93c08a"), "BAD": Color("dc735f"), "INFO": Color("86aecd"), "SHADOW": Color(0, 0, 0, 0.85),
	"METER": {"hp": Color("d9644f"), "hunger": Color("d39a52"), "thirst": Color("6ea8cc"),
		"humanity": Color("a596d6"), "libido": Color("d27fa8"), "xp": Color("93c08a")},
}
const LIGHT := {
	"BG": Color("efe9dd"), "SURFACE": Color("faf7f1"), "SURFACE_2": Color("f1ebe0"), "SURFACE_3": Color("e5ddcf"),
	"BORDER": Color("d2c7b4"), "TEXT": Color("2a241c"), "TEXT_DIM": Color("5c5244"), "TEXT_FAINT": Color("877b69"),
	"TEXT_STRONG": Color("120e09"), "ACCENT": Color("9c5a16"), "ACCENT_DIM": Color("f0d6ad"),
	"GOOD": Color("3d7533"), "BAD": Color("b0402c"), "INFO": Color("2c6a97"), "SHADOW": Color(1, 1, 1, 0.8),
	"METER": {"hp": Color("c24a35"), "hunger": Color("b97a2e"), "thirst": Color("3f86b0"),
		"humanity": Color("7a68b8"), "libido": Color("b85a8a"), "xp": Color("5a9a50")},
}

static var light := false  ## the light palette is in use
static var BG: Color = DARK.BG
static var SURFACE: Color = DARK.SURFACE
static var SURFACE_2: Color = DARK.SURFACE_2
static var SURFACE_3: Color = DARK.SURFACE_3
static var BORDER: Color = DARK.BORDER
static var TEXT: Color = DARK.TEXT
static var TEXT_DIM: Color = DARK.TEXT_DIM
static var TEXT_FAINT: Color = DARK.TEXT_FAINT
static var TEXT_STRONG: Color = DARK.TEXT_STRONG  ## hovered text: brighter than TEXT on dark, darker on light
static var ACCENT: Color = DARK.ACCENT
static var ACCENT_DIM: Color = DARK.ACCENT_DIM
static var GOOD: Color = DARK.GOOD
static var BAD: Color = DARK.BAD
static var INFO: Color = DARK.INFO
static var SHADOW: Color = DARK.SHADOW  ## behind text drawn over pictures
static var METER: Dictionary = DARK.METER


## Switches to the light or the dark palette (call `build` again afterwards).
static func use_palette(use_light: bool) -> void:
	light = use_light
	var p: Dictionary = LIGHT if use_light else DARK
	BG = p.BG
	SURFACE = p.SURFACE
	SURFACE_2 = p.SURFACE_2
	SURFACE_3 = p.SURFACE_3
	BORDER = p.BORDER
	TEXT = p.TEXT
	TEXT_DIM = p.TEXT_DIM
	TEXT_FAINT = p.TEXT_FAINT
	TEXT_STRONG = p.TEXT_STRONG
	ACCENT = p.ACCENT
	ACCENT_DIM = p.ACCENT_DIM
	GOOD = p.GOOD
	BAD = p.BAD
	INFO = p.INFO
	SHADOW = p.SHADOW
	METER = p.METER

const RADIUS := 4
const FONT_SIZE := 17
const PROSE_SIZE := 19

const FONTS := "res://ui/fonts/"

static var _fonts: Dictionary = {}


## Interface text, regular weight.
static func ui_font() -> Font:
	return _font("ui", "Barlow-Medium.ttf")


## Interface text, for names and titles.
static func strong_font() -> Font:
	return _font("strong", "Barlow-SemiBold.ttf")


## Small capitals for section labels, tags and key hints.
static func label_font() -> Font:
	return _font("label", "BarlowSemiCondensed-SemiBold.ttf", 0, 1)


## Story text.
static func prose_font(bold: bool = false, italic: bool = false) -> Font:
	var key := "prose%s%s" % ["_b" if bold else "", "_i" if italic else ""]
	return _font(key, "Literata-Italic.ttf" if italic else "Literata.ttf", 640 if bold else 400)


static func _font(key: String, file: String, weight: int = 0, spacing: int = 0) -> Font:
	if _fonts.has(key):
		return _fonts[key]
	var font: Font
	if ResourceLoader.exists(FONTS + file):
		var v := FontVariation.new()
		v.base_font = load(FONTS + file) as Font
		if weight > 0:
			v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		v.spacing_glyph = spacing
		font = v
	else:
		font = ThemeDB.fallback_font
	_fonts[key] = font
	return font


## A color pushed toward the background: darker on the dark palette, paler on the light one.
static func recede(color: Color, amount: float) -> Color:
	return color.lightened(amount) if light else color.darkened(amount)


static func box(color: Color, radius: int = RADIUS, border: Color = Color.TRANSPARENT, margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(1)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.75
	s.content_margin_bottom = margin * 0.75
	s.anti_aliasing = true
	return s


## A surface with a colored bar on its left edge: hover, focus, toasts.
static func edged(color: Color, edge: Color, width: int = 3, margin: int = 12) -> StyleBoxFlat:
	var s := box(color, RADIUS, Color.TRANSPARENT, margin)
	s.border_color = edge
	s.border_width_left = width
	s.content_margin_left = margin
	return s


## A hairline below (or above) a band such as the status bar.
static func band(color: Color, top: bool = false) -> StyleBoxFlat:
	var s := box(color, 0, Color.TRANSPARENT, 0)
	s.border_color = BORDER
	if top:
		s.border_width_top = 1
	else:
		s.border_width_bottom = 1
	s.anti_aliasing = false
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = ui_font()
	t.default_font_size = FONT_SIZE

	t.set_stylebox("panel", "PanelContainer", box(SURFACE, RADIUS, Color.TRANSPARENT, 16))
	t.set_stylebox("panel", "Panel", box(SURFACE, RADIUS))

	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_constant("line_separation", "RichTextLabel", 6)
	t.set_font("normal_font", "RichTextLabel", prose_font())
	t.set_font("bold_font", "RichTextLabel", prose_font(true))
	t.set_font("italics_font", "RichTextLabel", prose_font(false, true))
	t.set_font("bold_italics_font", "RichTextLabel", prose_font(true, true))
	for kind in ["normal", "bold", "italics", "bold_italics"]:
		t.set_font_size(kind + "_font_size", "RichTextLabel", PROSE_SIZE)
	t.set_color("selection_color", "RichTextLabel", Color(ACCENT, 0.3))

	# Buttons: quiet surfaces; hover and focus light an amber edge.
	t.set_stylebox("normal", "Button", box(SURFACE_2, RADIUS, Color.TRANSPARENT, 12))
	t.set_stylebox("hover", "Button", edged(SURFACE_3, ACCENT))
	t.set_stylebox("pressed", "Button", edged(ACCENT_DIM, ACCENT))
	t.set_stylebox("hover_pressed", "Button", edged(ACCENT_DIM, ACCENT))
	t.set_stylebox("disabled", "Button", box(Color(SURFACE_2, 0.5), RADIUS, Color.TRANSPARENT, 12))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(ACCENT, 0.8)
	focus.set_border_width_all(1)
	focus.border_width_left = 3
	focus.set_corner_radius_all(RADIUS)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT_STRONG)
	t.set_color("font_pressed_color", "Button", TEXT_STRONG)
	t.set_color("font_hover_pressed_color", "Button", TEXT_STRONG)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_FAINT)

	# Text fields: a sunken well with an amber underline when focused.
	var well := box(BG, RADIUS, BORDER, 10)
	t.set_stylebox("normal", "LineEdit", well)
	var well_focus := box(BG, RADIUS, BORDER, 10)
	well_focus.border_color = ACCENT
	t.set_stylebox("focus", "LineEdit", well_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.3))

	t.set_stylebox("panel", "PopupMenu", box(SURFACE_2, RADIUS, BORDER, 6))
	t.set_stylebox("hover", "PopupMenu", box(SURFACE_3, 2, Color.TRANSPARENT, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", TEXT_STRONG)

	t.set_stylebox("background", "ProgressBar", box(SURFACE_3, 2, Color.TRANSPARENT, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 2, Color.TRANSPARENT, 0))
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)

	t.set_stylebox("panel", "TooltipPanel", box(SURFACE_3, RADIUS, BORDER, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)

	var scroll := StyleBoxFlat.new()
	scroll.bg_color = Color(TEXT, 0.14)
	scroll.set_corner_radius_all(3)
	scroll.content_margin_left = 3
	scroll.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", scroll)
	var scroll_hover := scroll.duplicate() as StyleBoxFlat
	scroll_hover.bg_color = Color(TEXT, 0.26)
	t.set_stylebox("grabber_highlight", "VScrollBar", scroll_hover)
	t.set_stylebox("grabber_pressed", "VScrollBar", scroll_hover)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return t


## A section label: condensed, spaced capitals.
static func heading(text: String, size: int = 13, color: Color = TEXT_FAINT) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", label_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A section label followed by a hairline that runs to the edge.
static func section(text: String, color: Color = TEXT_FAINT) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(heading(text, 13, color))
	row.add_child(rule(true))
	return row


## A one-pixel line; `fill` makes it stretch within a row.
static func rule(fill: bool = false) -> ColorRect:
	var line := ColorRect.new()
	line.color = BORDER
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fill:
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return line


static func label(text: String, size: int = FONT_SIZE, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A label in the bolder interface weight, for names and titles.
static func title(text: String, size: int, color: Color = TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", strong_font())
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## A key hint drawn as a small keycap, such as "I" or "Esc".
static func keycap(key: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(Color.TRANSPARENT, 3, BORDER, 6)
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := heading(key, 12, TEXT_FAINT)
	l.text = key
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(10, 0)
	p.add_child(l)
	return p


static func card(color: Color = SURFACE, margin: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, RADIUS, Color.TRANSPARENT, margin))
	return p


## A vertical one-pixel line between columns.
static func rule_v() -> ColorRect:
	var line := ColorRect.new()
	line.color = BORDER
	line.custom_minimum_size = Vector2(1, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
