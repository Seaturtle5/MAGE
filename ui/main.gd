extends Control
## The main game screen.
##
## The center "stage" always shows the current moment, never a growing log:
##   - location mode: a banner image, the place's description, the people
##     here as cards and items on the ground;
##   - scene mode: the current page of a scene (talk, event, result of an
##     action) with its speaker, and choices as cards. A new page replaces
##     the old one.
## Navigation (compass, fast travel, map) and actions (explore, rest ...) are
## separate panels on the right; they dim while a scene needs attention.
## Everything shown is also kept in a history, opened with the Log button.
##
## The screen only draws the game's output events and sends input back.
##
## The game opens on the title screen (ui/title_screen.gd); a game is
## created when the player starts a new one or loads a save.
##
## Command line (after `--`): `--seed N`, `--start ID` (skip the title and
## start at a location), and for automated screenshots
## `--steps "new bunker_start;go up"` with `--shot path.png`.

const MapView := preload("res://ui/map_view.gd")
## The content settings chosen for the last new game, offered again next time.
const CONTENT_PREFS := "user://content_settings.json"
## Display preferences, kept outside saves.
const PREFS := "user://preferences.cfg"
const UI_SCALES := [0.9, 1.0, 1.1, 1.25]
const BACKDROP := "res://ui/art/backdrop_texture.png"
const PORTRAIT_MASK := preload("res://ui/portrait.gdshader")
## Left edge of headings and story text on the stage.
const READING_SIDE := 40
## Width of the framed picture beside a scene's text.
const PLATE_WIDTH := 290.0
## Equipment slots shown in the inventory, empty or not.
const SLOT_ORDER := ["head", "eyes", "face", "neck", "chest", "back", "arms", "hands", "crotch", "legs", "feet"]
const INVENTORY_TABS := [["all", "All"], ["equipment", "Wearables"], ["armaments", "Weapons"],
	["consumables", "Consumables"], ["other", "Other"]]
const BAG_COLUMNS := 6
const BAG_TILE := 92
const EXIT_ORDER := ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest",
	"up", "down", "inside", "outside"]
const ACTION_INFO := {
	"explore": ["Explore", "Search the area for places, people and trouble.", "1 turn"],
	"rest": ["Rest", "Sleep and recover your health.", "2 turns"],
	"wait": ["Wait", "Let time pass.", "1 turn"],
	"observe": ["Observe", "Stay out of sight and watch what happens.", ""],
	"scavenge": ["Scavenge", "Look for food and water.", "1 turn"],
	"hunt": ["Hunt", "Look for a particular creature.", "1 turn"],
	"actions": ["Actions", "Things you can do here.", ""],
	"shop": ["Shop", "Buy, sell and trade.", ""],
}

var game: Game
var location_view: Dictionary = {}
var history: Array = []  ## [{"kind", "text"}] for the log

# Stage
var stage: PanelContainer
var stage_box: VBoxContainer
var mode := ""  ## "location", "scene" or "moment"
var page_box: VBoxContainer
var page_new := true
var choices_box: VBoxContainer
var scene_title := ""
var scene_image := ""
var scene_character := ""
var scene_art: TextureRect
var scene_plate: Control  ## the framed picture beside a scene's text
var scene_credit: Label
var image_cache: Dictionary = {}
var icon_cache: Dictionary = {}

# Panels
var nav_panel: VBoxContainer
var nav_extra: VBoxContainer  ## one row per exit
var nav_links: HBoxContainer  ## fast travel and the map
var actions_panel: VBoxContainer
var actions_box: VBoxContainer
var sidebar_scroll: ScrollContainer
var status_place: Label
var status_time: Label
var status_sleep: Label
var meters: Dictionary = {}
var meters_row: HBoxContainer
var meters_keys: Array = []  ## the status bar's meters as last built
var money_box: Control
var level_label: Label
var money_label: Label
var mini_map: Control
var activity_label: Label
var quest_label: Label
var overlay: Control
var toast_box: VBoxContainer
var choice_count := 0
var shot_path := ""
var shot_steps: Array = []
var db: ContentDB
var seed_value := 0  ## from --seed; 0 means a new seed for each game
var store := SaveStore.new()
var prefs := ConfigFile.new()
var title: TitleScreen
var game_root: Control  ## the in-game screen, hidden while the title shows
var last_autosave_turn := -1
var content_toggle: Button  ## shows the content settings on the new-game screen
var overlay_scroll: ScrollContainer
var overlay_footer: HBoxContainer  ## buttons below an overlay's scrolling content
var inv_selected := ""  ## the item shown in the inventory's detail pane
var inv_filter := "all"  ## the inventory tab
var inv_bag_scroll: ScrollContainer


func _ready() -> void:
	theme = FsTheme.build()
	_build()
	var args := OS.get_cmdline_user_args()
	var start := ""
	var test_content := false
	var extra_packs: Array = []
	for i in args.size():
		match args[i]:
			"--test-content":
				test_content = true
			"--seed":
				seed_value = int(args[i + 1])
			"--start":
				start = args[i + 1]
			"--shot":
				shot_path = args[i + 1]
			"--steps":
				shot_steps = Array(args[i + 1].split(";"))
			"--packs":
				extra_packs.append(args[i + 1])
	# Automated screenshots use default preferences and their own save folder.
	if shot_path == "":
		prefs.load(PREFS)
		_apply_display_prefs()
	else:
		store = SaveStore.new("user://screenshot_saves")
	db = ContentDB.new()
	db.load_folders(["res://tests/packs"] if test_content else _content_folders(extra_packs))
	if not db.errors().is_empty():
		_show_errors(db.errors())
		return
	if shot_path == "":
		store.import_legacy()
	if start != "" or test_content:
		_reset_game()
		game.start(start if start != "" else "shelter")
		_drain()
	else:
		_show_title()
	if shot_path != "":
		_take_screenshot.call_deferred()


## Where content packs are looked for: folders given with `--packs DIR`,
## the `packs` folder inside the game, a `packs` folder next to the game's
## program, and the player's own `user://packs`.
static func _content_folders(extra: Array) -> Array:
	var folders: Array = extra.duplicate()
	folders.append("res://packs")
	if not OS.has_feature("editor"):
		folders.append(OS.get_executable_path().get_base_dir().path_join("packs"))
	folders.append("user://packs")
	return folders


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave_now()


func _exit_tree() -> void:
	if game != null:
		game.dispose()


# --- Layout -----------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = FsTheme.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	if ResourceLoader.exists(BACKDROP):
		var grain := TextureRect.new()
		grain.texture = load(BACKDROP) as Texture2D
		grain.stretch_mode = TextureRect.STRETCH_TILE
		grain.modulate.a = 0.5
		grain.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(grain)
	# Status band on top, the tool bar at the bottom, both flush with the
	# window; the three columns sit between them.
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	game_root = root
	root.add_child(_status_bar())
	var middle := _padded(18, 16)
	middle.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(middle)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	middle.add_child(body)
	body.add_child(_left_column())
	stage = PanelContainer.new()
	stage.add_theme_stylebox_override("panel", FsTheme.box(FsTheme.SURFACE, FsTheme.RADIUS, Color.TRANSPARENT, 0))
	stage.size_flags_horizontal = SIZE_EXPAND_FILL
	stage.clip_contents = true
	body.add_child(stage)
	body.add_child(_right_column())
	root.add_child(_nav_bar())


func _status_bar() -> Control:
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", FsTheme.band(FsTheme.SURFACE))
	var pad := _padded(22, 12)
	band.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	pad.add_child(row)
	var place := VBoxContainer.new()
	place.add_theme_constant_override("separation", 1)
	place.custom_minimum_size = Vector2(300, 0)
	status_place = FsTheme.title("", 21)
	place.add_child(status_place)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	status_time = _plain_label("", 14, FsTheme.TEXT_DIM)
	line.add_child(status_time)
	status_sleep = FsTheme.heading("", 12, FsTheme.GOOD)
	status_sleep.size_flags_vertical = SIZE_SHRINK_CENTER
	line.add_child(status_sleep)
	place.add_child(line)
	row.add_child(place)
	# The meters come from the game's status bar (Game.status_bar), built on the first refresh.
	meters_row = HBoxContainer.new()
	meters_row.add_theme_constant_override("separation", 26)
	row.add_child(meters_row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(spacer)
	level_label = _plain_label("", 15, FsTheme.TEXT_DIM)
	money_label = _plain_label("", 15, FsTheme.ACCENT)
	row.add_child(_with_icon("xp", level_label, FsTheme.METER.xp))
	money_box = _with_icon("freecred", money_label, FsTheme.ACCENT)
	row.add_child(money_box)
	return band


func _plain_label(text: String, size: int, color: Color) -> Label:
	var l := FsTheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


func _meter(key: String, label: String = "") -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.custom_minimum_size = Vector2(124, 0)
	box.size_flags_vertical = SIZE_SHRINK_CENTER
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var colour: Color = FsTheme.METER.get(key, FsTheme.ACCENT)
	var icon_name := "health" if key == "hp" else key
	top.add_child(_icon_view(icon_name if _icon(icon_name) != null else "other", 14, colour))
	var name := FsTheme.heading(label if label != "" else {"hp": "Health"}.get(key, key.capitalize()), 12, FsTheme.TEXT_DIM)
	name.size_flags_horizontal = SIZE_EXPAND_FILL
	var num := _plain_label("", 14, FsTheme.TEXT)
	num.add_theme_font_override("font", FsTheme.strong_font())
	top.add_child(name)
	top.add_child(num)
	box.add_child(top)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	bar.add_theme_stylebox_override("fill", FsTheme.box(colour, 2, Color.TRANSPARENT, 0))
	box.add_child(bar)
	meters[key] = {"bar": bar, "num": num}
	return box


func _left_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(290, 0)
	col.add_theme_constant_override("separation", 10)
	col.add_child(FsTheme.section("Area"))
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", FsTheme.box(FsTheme.SURFACE, FsTheme.RADIUS, Color.TRANSPARENT, 0))
	# The map shrinks first when the window is short.
	frame.size_flags_vertical = SIZE_EXPAND_FILL
	mini_map = MapView.new()
	mini_map.custom_minimum_size = Vector2(260, 140)
	mini_map.compact = true
	mini_map.place_clicked.connect(_on_map_place)
	frame.add_child(mini_map)
	col.add_child(frame)
	col.add_child(_gap(10))
	col.add_child(FsTheme.section("Now"))
	activity_label = FsTheme.label("", 17, FsTheme.TEXT)
	col.add_child(activity_label)
	col.add_child(_gap(10))
	col.add_child(FsTheme.section("Quest"))
	quest_label = FsTheme.label("", 15, FsTheme.TEXT_DIM)
	col.add_child(quest_label)
	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(fill)
	toast_box = VBoxContainer.new()
	toast_box.add_theme_constant_override("separation", 8)
	col.add_child(toast_box)
	return col


func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _right_column() -> Control:
	sidebar_scroll = ScrollContainer.new()
	sidebar_scroll.custom_minimum_size = Vector2(350, 0)
	sidebar_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar_scroll.follow_focus = true
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(336, 0)
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	sidebar_scroll.add_child(col)
	nav_panel = VBoxContainer.new()
	nav_panel.add_theme_constant_override("separation", 10)
	nav_panel.add_child(FsTheme.section("Exits"))
	nav_extra = VBoxContainer.new()
	nav_extra.add_theme_constant_override("separation", 4)
	nav_panel.add_child(nav_extra)
	nav_links = HBoxContainer.new()
	nav_links.add_theme_constant_override("separation", 4)
	nav_panel.add_child(nav_links)
	col.add_child(nav_panel)
	col.add_child(_gap(10))
	actions_panel = VBoxContainer.new()
	actions_panel.add_theme_constant_override("separation", 10)
	actions_panel.add_child(FsTheme.section("Actions"))
	actions_box = VBoxContainer.new()
	actions_box.add_theme_constant_override("separation", 4)
	actions_panel.add_child(actions_box)
	col.add_child(actions_panel)
	return sidebar_scroll


func _nav_bar() -> Control:
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", FsTheme.band(FsTheme.SURFACE, true))
	var pad := _padded(12, 6)
	band.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	pad.add_child(row)
	for spec in [["Inventory", "I", _open_inventory], ["Journal", "J", _open_journal], ["Map", "M", _open_map],
			["Character", "C", _open_character], ["Log", "L", _open_log]]:
		_bar_button(row, spec[0], str(spec[0]).to_lower(), spec[1], spec[2])
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(spacer)
	_bar_button(row, "Settings", "settings", "", _open_settings)
	_bar_button(row, "Save", "save", "F5", func(): _open_saves(true))
	_bar_button(row, "Load", "load", "", func(): _open_saves(false))
	_bar_button(row, "Menu", "", "Esc", _open_pause)
	return band


## A quiet tool-bar button: icon, name and its key.
func _bar_button(parent: Control, text: String, icon: String, key: String, pressed: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if icon != "":
		row.add_child(_icon_view(icon, 18, FsTheme.TEXT_DIM))
	row.add_child(_plain_label(text, 16, FsTheme.TEXT))
	if key != "":
		row.add_child(FsTheme.keycap(key))
	var b := _face_button(parent, row, pressed, false, 14, 8)
	var quiet := FsTheme.box(Color.TRANSPARENT)
	b.add_theme_stylebox_override("normal", quiet)
	return b


## A button whose face is laid out from controls. `content` sits on top of
## the button and lets clicks through; the holder sizes both to fit the
## content. Disabled buttons fade their content.
func _face_button(parent: Control, content: Control, pressed: Callable, disabled: bool = false,
		h_pad: int = 14, v_pad: int = 10) -> Button:
	var holder := MarginContainer.new()
	var b := Button.new()
	b.disabled = disabled
	b.pressed.connect(pressed)
	holder.add_child(b)
	var pad := _padded(h_pad, v_pad)
	pad.add_child(content)
	_pass_clicks(pad)
	if disabled:
		pad.modulate.a = 0.4
	holder.add_child(pad)
	parent.add_child(holder)
	return b


func _pass_clicks(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_pass_clicks(c)


# --- Game output ------------------------------------------------------------

func _drain() -> void:
	var waiting := false
	for e in game.take_output():
		match e.type:
			"title":
				_begin_scene(e.text, e.get("character", ""), e.get("image", ""))
			"paragraph":
				_page_text(_bbcode(e.spans), TextTemplate.plain(e.spans))
			"notice":
				# In a scene the note belongs on the page; outside one it is a toast.
				if mode == "location" and game.runner.status == "idle":
					_toast(e.text)
					_log("note", e.text)
				else:
					_page_note(e.text, FsTheme.GOOD)
			"roll":
				_page_note(e.text, FsTheme.INFO)
			"combat":
				_show_combat(e)
				waiting = true
			"image":
				_ensure_page()
				_set_scene_image(str(e.image))
			"choices":
				_page_choices(e)
				waiting = true
			"page_break":
				_page_continue(func(): _continue())
				waiting = true
			"location":
				location_view = e
			"scene_end":
				pass
			"ending":
				# A sentence saying why the game ended ("You survived until the rescue came.");
				# an ending's ID says nothing itself: its epilogue follows.
				var ending: String = str(e.ending)
				if " " in ending:
					_page_text(_esc(ending), ending)
			"game_over":
				_page_text("[b]Game over[/b]", "Game over")
				_page_continue(func(): _show_title())
				waiting = true
	if game.runner.status == "idle":
		if mode in ["scene", "moment"] and not page_new and not waiting:
			# Text produced outside a scene (exploring, travelling, resting):
			# show it as a moment the player acknowledges, then the location.
			mode = "moment"
			_page_continue(_finish_moment)
		elif mode != "moment" or page_new:
			_show_location()
	# Outside a titled scene, "Now" names where the player is.
	if mode != "scene" and game.state.location != "":
		activity_label.text = "At %s" % game.save_summary().location
	_refresh_panels()
	_refresh_status()
	_maybe_autosave()


func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


func _bbcode(spans: Array) -> String:
	var out := ""
	for s in spans:
		var t := _esc(s.text)
		if s.bold:
			t = "[b]%s[/b]" % t
		if s.italic:
			t = "[i]%s[/i]" % t
		if s["class"] == "roll":
			t = "[color=#%s]%s[/color]" % [FsTheme.INFO.to_html(false), t]
		elif s["class"] == "warning":
			t = "[color=#%s]%s[/color]" % [FsTheme.BAD.to_html(false), t]
		out += t
	return out


func _clear_stage() -> void:
	for c in stage.get_children():
		c.queue_free()
	stage_box = VBoxContainer.new()
	stage_box.add_theme_constant_override("separation", 0)
	stage.add_child(stage_box)


# Location mode --------------------------------------------------------------

func _show_location() -> void:
	mode = "location"
	page_new = true
	_clear_stage()
	var e := location_view
	if e.is_empty():
		return
	stage_box.add_child(_banner(e.image, e.name, "%s  ·  %s" % [game.status_snapshot().region, _time_text()]))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stage_box.add_child(scroll)
	var pad := _reading_pad(scroll, 28)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.add_child(body)
	for p in e.description:
		body.add_child(_rich(_bbcode(p)))
		_log("text", TextTemplate.plain(p))
	if not e.people.is_empty():
		body.add_child(_gap(4))
		body.add_child(FsTheme.section("People here"))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 12)
		for p in e.people:
			row.add_child(_person_card(p))
		body.add_child(row)
	if not e.items.is_empty():
		body.add_child(_gap(4))
		body.add_child(FsTheme.section("On the ground"))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 12)
		for it in e.items:
			row.add_child(_item_card(it))
		var total := 0
		for it in e.items:
			total += int(it.get("count", 1))
		if total > 1:
			var all := Button.new()
			all.text = "Take all"
			_button_icon(all, "take")
			all.pressed.connect(func(): _act("take_all", ""))
			row.add_child(all)
		body.add_child(row)
	activity_label.text = "At %s" % e.name


func _banner(image_id: String, heading: String, subtitle: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 250)
	holder.clip_contents = true
	var tex := TextureRect.new()
	tex.texture = _image_or_placeholder(image_id, heading)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	holder.add_child(tex)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(FsTheme.SURFACE, 1.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.35)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	holder.add_child(shade)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	text.offset_left = READING_SIDE
	text.offset_top = -84
	text.offset_bottom = -12
	text.add_child(FsTheme.heading(subtitle, 13, FsTheme.ACCENT))
	text.add_child(FsTheme.title(heading, 36))
	holder.add_child(text)
	var artist := game.content.get_def("image", image_id) if game != null and image_id != "" else null
	if artist != null and artist.fields.has("artist"):
		var credit := _plain_label("Art: " + artist.fields["artist"].value, 13, Color(FsTheme.TEXT, 0.5))
		credit.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
		credit.offset_left = -400
		credit.offset_top = -34
		credit.offset_right = -20
		credit.offset_bottom = -12
		credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		credit.clip_text = true
		credit.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		holder.add_child(credit)
	return holder


func _person_card(p: Dictionary) -> Control:
	var card := FsTheme.card(FsTheme.SURFACE_2, 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(_avatar(p.name, 52, p.get("image", "")))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(FsTheme.title(p.name, 18))
	var buttons := HBoxContainer.new()
	var id: String = p.id
	# Talk, then the character's other doings: its actions menu, sex, scent and look.
	for spec in [["talk", "Talk", "talk"], ["actions", "Actions", "use"], ["sex", "Sex", "libido"],
			["smell", "Smell", "observe"], ["look", "Look", "character"]]:
		if not p.get(spec[0], false):
			continue
		var b := Button.new()
		b.text = spec[1]
		_button_icon(b, spec[2])
		var act: String = spec[0]
		b.pressed.connect(func(): _act(act, id))
		buttons.add_child(b)
	if p.get("companion", false) or p.get("tamed", false):
		# A companion following the player can be sent away; a tamed one asked along.
		var following: bool = p.get("companion", false)
		var b := Button.new()
		b.text = "Dismiss" if following else "Summon"
		_button_icon(b, "travel" if following else "character")
		var action := "dismiss" if following else "summon"
		b.pressed.connect(func(): _act(action, id))
		buttons.add_child(b)
	v.add_child(buttons)
	row.add_child(v)
	return card


func _item_card(it: Dictionary) -> Control:
	var card := FsTheme.card(FsTheme.SURFACE_2, 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(_item_icon(str(it.id), 32))
	var count := int(it.get("count", 1))
	row.add_child(_plain_label(it.name.capitalize() + ("  ×%d" % count if count > 1 else ""), 17, FsTheme.TEXT))
	var b := Button.new()
	b.text = "Take"
	_button_icon(b, "take")
	var id: String = it.id
	b.pressed.connect(func(): _act("take", id))
	row.add_child(b)
	return card


## An item's picture, or a line icon when it has none: clothing by the slot it is
## worn on, weapons by type, anything else by category.
func _item_icon(id: String, size: int) -> Control:
	var tex := _pack_image(game.content.typed_value("item", id, "image"))
	if tex == null:
		var category := game.content.typed_value("item", id, "category", "other").to_lower()
		var name := category
		var chosen := game.content.typed_value("item", id, "icon")
		if chosen != "" and _icon(chosen) != null:
			name = chosen  # the item names one of the interface's icons ("icon: milk")
		elif category == "clothing" and _icon("clothing_" + ItemSystem.gear(game, id, "slot")) != null:
			name = "clothing_" + ItemSystem.gear(game, id, "slot")
		elif category == "weapon":
			name = "weapon_" + ItemSystem.arm(game, id, "type", "melee")
		return _icon_view(name if _icon(name) != null else "other", size, FsTheme.TEXT_DIM)
	var view := TextureRect.new()
	view.texture = tex
	view.custom_minimum_size = Vector2(size, size)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.size_flags_vertical = SIZE_SHRINK_CENTER
	return view


func _avatar(name: String, size: int, image_id: String = "") -> Control:
	var texture := _pack_image(image_id)
	if texture != null:
		var portrait := TextureRect.new()
		portrait.texture = texture
		portrait.custom_minimum_size = Vector2(size, size)
		portrait.size_flags_vertical = SIZE_SHRINK_CENTER
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var mask := ShaderMaterial.new()
		mask.shader = PORTRAIT_MASK
		portrait.material = mask
		portrait.tooltip_text = name
		var credit := game.content.typed_value("image", image_id, "artist")
		if credit != "":
			portrait.tooltip_text += "\nArt: " + credit
		return portrait
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(size, size)
	panel.size_flags_vertical = SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", FsTheme.box(FsTheme.SURFACE_3, FsTheme.RADIUS, Color.TRANSPARENT, 0))
	panel.tooltip_text = name
	var figure := _icon_view("character", int(size * 0.5), FsTheme.TEXT_FAINT)
	figure.size_flags_horizontal = SIZE_SHRINK_CENTER
	panel.add_child(figure)
	return panel


# Scene mode -----------------------------------------------------------------

func _begin_scene(heading: String, character: String = "", image: String = "") -> void:
	mode = "scene"
	scene_title = heading
	scene_image = image
	scene_character = character
	_log("title", heading)
	activity_label.text = heading
	_new_page()


func _new_page() -> void:
	_clear_stage()
	page_new = false
	var header := _padded(READING_SIDE, 22)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 18)
	header.add_child(hrow)
	var title: String = scene_title if scene_title != "" else location_view.get("name", "")
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	tv.size_flags_vertical = SIZE_SHRINK_CENTER
	tv.add_child(FsTheme.heading(location_view.get("name", ""), 13, FsTheme.ACCENT))
	tv.add_child(FsTheme.title(title, 29))
	hrow.add_child(tv)
	stage_box.add_child(header)
	stage_box.add_child(FsTheme.rule())
	var content := HBoxContainer.new()
	content.size_flags_vertical = SIZE_EXPAND_FILL
	stage_box.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var pad := _reading_pad(scroll, 26)
	page_box = VBoxContainer.new()
	page_box.add_theme_constant_override("separation", 16)
	page_box.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.add_child(page_box)
	content.add_child(_scene_plate())
	_set_scene_image(scene_image)
	choices_box = VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 6)
	var cpad := _padded(READING_SIDE, 20)
	cpad.add_child(choices_box)
	stage_box.add_child(cpad)
	page_box.modulate.a = 0.0
	create_tween().tween_property(page_box, "modulate:a", 1.0, 0.25)


## The scene's picture, mounted like a print: a dark mat with a hairline
## edge and a soft shadow, top-aligned with the text, the artist below.
func _scene_plate() -> Control:
	var col := MarginContainer.new()
	col.add_theme_constant_override("margin_top", 28)
	col.add_theme_constant_override("margin_right", 32)
	col.add_theme_constant_override("margin_bottom", 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_vertical = SIZE_SHRINK_BEGIN
	col.add_child(v)
	var frame := PanelContainer.new()
	var mat := FsTheme.box(FsTheme.BG, 3, FsTheme.BORDER, 7)
	mat.content_margin_top = 7
	mat.content_margin_bottom = 7
	mat.shadow_color = Color(0, 0, 0, 0.45)
	mat.shadow_size = 14
	mat.shadow_offset = Vector2(0, 4)
	frame.add_theme_stylebox_override("panel", mat)
	v.add_child(frame)
	scene_art = TextureRect.new()
	scene_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(scene_art)
	scene_credit = FsTheme.heading("", 12, FsTheme.TEXT_FAINT)
	v.add_child(scene_credit)
	scene_plate = col
	return col


func _set_scene_image(id: String) -> void:
	scene_image = id
	var texture := _pack_image(id)
	scene_art.texture = texture
	scene_plate.visible = texture != null
	if texture == null:
		return
	# A fixed width; the height follows the picture, within limits (very
	# tall pictures are trimmed top and bottom).
	var ratio := float(texture.get_height()) / maxf(1.0, float(texture.get_width()))
	scene_art.custom_minimum_size = Vector2(PLATE_WIDTH, clampf(PLATE_WIDTH * ratio, 150.0, 420.0))
	var artist := game.content.typed_value("image", id, "artist")
	scene_credit.text = ("Art  ·  " + artist).to_upper() if artist != "" else ""
	scene_art.tooltip_text = "Art: " + artist if artist != "" else ""
	scene_credit.visible = artist != ""


func _ensure_page() -> void:
	if mode == "location" or page_new or page_box == null or not is_instance_valid(page_box):
		if mode == "location":
			mode = "moment"
			scene_title = ""
			scene_image = ""
			scene_character = ""
		_new_page()


func _page_text(bb: String, plain: String) -> void:
	_ensure_page()
	page_box.add_child(_rich(bb))
	_log("text", plain)


func _page_note(text: String, color: Color) -> void:
	_ensure_page()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tick := ColorRect.new()
	tick.color = color
	tick.custom_minimum_size = Vector2(3, 18)
	tick.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(tick)
	var l := FsTheme.label(text, 16, color)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(l)
	page_box.add_child(row)
	_log("note", text)


func _page_choices(e: Dictionary) -> void:
	_ensure_page()
	if e.get("title", "") != "":
		page_box.add_child(_plain_label(e.title, 16, FsTheme.TEXT_DIM))
	for c in choices_box.get_children():
		c.queue_free()
	var n := 0
	for o in e.options:
		n += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var key := FsTheme.keycap(str(n)) if n <= 9 else Control.new()
		key.size_flags_vertical = SIZE_SHRINK_BEGIN
		row.add_child(key)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 1)
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		text.add_child(FsTheme.label(o.text, 17))
		if o.description != "":
			text.add_child(FsTheme.label(o.description, 14, FsTheme.TEXT_DIM))
		row.add_child(text)
		var index := n - 1
		_face_button(choices_box, row, func(): _choose(index), not o.enabled, 14, 11)
	choice_count = n
	page_new = true


func _page_continue(callback: Callable) -> void:
	_ensure_page()
	for c in choices_box.get_children():
		c.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(FsTheme.title("Continue", 17))
	row.add_child(FsTheme.keycap("Space"))
	var b := _face_button(choices_box, row, callback, false, 14, 12)
	b.add_theme_stylebox_override("normal", FsTheme.box(FsTheme.ACCENT_DIM.darkened(0.25)))
	b.add_theme_stylebox_override("hover", FsTheme.edged(FsTheme.ACCENT_DIM, FsTheme.ACCENT))
	b.grab_focus.call_deferred()
	page_new = true


func _rich(bb: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = true
	r.add_theme_constant_override("line_separation", 3)
	r.size_flags_horizontal = SIZE_EXPAND_FILL
	r.text = bb
	return r


## Padding for story text, with its left edge in line with the heading.
## The text takes the stage's full width; a scene picture sits beside it.
func _reading_pad(scroll: ScrollContainer, v: int) -> MarginContainer:
	var pad := _padded(READING_SIDE, v)
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(pad)
	return pad


func _padded(h: int, v: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)
	return m


# Panels ---------------------------------------------------------------------

func _refresh_panels() -> void:
	var busy := game.runner.status != "idle" or mode == "moment"
	for box in [nav_extra, nav_links, actions_box]:
		for c in box.get_children():
			c.queue_free()
	var e := location_view
	var exits := {}
	for x in e.get("exits", []):
		exits[x.direction] = x
	# Exits in compass order, then the vertical and in/out ones.
	var order: Array = EXIT_ORDER.filter(func(d): return exits.has(d))
	order.append_array(exits.keys().filter(func(d): return d not in EXIT_ORDER))
	for dir: String in order:
		_exit_row(dir, exits[dir], busy)
	if exits.is_empty():
		nav_extra.add_child(FsTheme.label("No way out from here.", 15, FsTheme.TEXT_FAINT))
	var travel := game.travel_destinations()
	if not travel.is_empty():
		var t := _link_button(nav_links, "Fast travel", "travel", str(travel.size()), _open_travel, busy)
		t.tooltip_text = "Travel to a place you have found (%d)." % travel.size()
	_link_button(nav_links, "Map", "map", "M", _open_map, false)
	for a in e.get("actions", []):
		_action_tile(a.id, busy, str(a.get("label", "")), str(a.get("arg", "")))
	if e.get("actions", []).is_empty():
		actions_box.add_child(FsTheme.label("Nothing to do here right now.", 15, FsTheme.TEXT_FAINT))
	nav_panel.modulate.a = 0.45 if busy else 1.0
	actions_panel.modulate.a = 0.45 if busy else 1.0


## One exit: its direction as a tag, then where it leads.
func _exit_row(dir: String, exit: Dictionary, busy: bool) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var tag := FsTheme.heading(_dir_short(dir), 14, FsTheme.ACCENT)
	tag.custom_minimum_size = Vector2(44, 0)
	row.add_child(tag)
	var name := _plain_label(("%s (explore)" % exit.name) if exit.get("explore", false) else exit.name, 17, FsTheme.TEXT)
	name.size_flags_horizontal = SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.clip_text = true
	row.add_child(name)
	var b := _face_button(nav_extra, row, func(): _act("go", dir), busy or not exit.get("enabled", true), 14, 9)
	b.tooltip_text = "%s to %s" % [dir.capitalize(), exit.name]
	return b


## A small secondary button below the exits.
func _link_button(parent: Control, text: String, icon: String, hint: String, pressed: Callable, disabled: bool) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_icon_view(icon, 16, FsTheme.TEXT_DIM))
	row.add_child(_plain_label(text, 15, FsTheme.TEXT_DIM))
	if hint != "":
		row.add_child(FsTheme.keycap(hint))
	var b := _face_button(parent, row, pressed, disabled, 10, 7)
	(b.get_parent() as Control).size_flags_horizontal = SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", FsTheme.box(Color.TRANSPARENT, FsTheme.RADIUS, FsTheme.BORDER))
	return b


func _dir_short(dir: String) -> String:
	return {"north": "N", "south": "S", "east": "E", "west": "W", "northeast": "NE", "northwest": "NW",
		"southeast": "SE", "southwest": "SW", "up": "Up", "down": "Down", "inside": "In",
		"outside": "Out"}.get(dir, dir.capitalize())


func _action_tile(id: String, busy: bool, label: String = "", arg: String = "") -> Button:
	var info: Array = ACTION_INFO.get(id, [id.capitalize(), "", ""]).duplicate()
	if id in ["actions", "shop"] and label != "":
		info[0] = label  # the menu's own title
	var icon_name := id if _icon(id) != null else "use"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var icon := _icon_view(icon_name, 22, FsTheme.ACCENT)
	icon.size_flags_vertical = SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 1)
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.add_child(FsTheme.title(info[0], 17))
	if info[1] != "":
		text.add_child(FsTheme.label(info[1], 14, FsTheme.TEXT_DIM))
	row.add_child(text)
	if info[2] != "":
		var cost := FsTheme.heading(info[2], 12, FsTheme.TEXT_FAINT)
		cost.size_flags_vertical = SIZE_SHRINK_BEGIN
		row.add_child(cost)
	return _face_button(actions_box, row, _open_hunt if id == "hunt" else func(): _act(id, arg), busy, 14, 11)


func _time_text() -> String:
	var s := game.status_snapshot()
	return "Day %d, %s" % [s.day, s.time]


func _refresh_status() -> void:
	var s := game.status_snapshot()
	status_place.text = s.location
	status_time.text = "%s  ·  %s" % [s.region, _time_text()]
	status_sleep.text = s.sleep
	status_sleep.visible = s.sleep != ""
	var st: Dictionary = s.stats
	var bar := game.status_bar()
	var keys: Array = bar.meters.map(func(m): return m.key)
	if keys != meters_keys:
		for c in meters_row.get_children():
			c.queue_free()
		meters.clear()
		for m in bar.meters:
			meters_row.add_child(_meter(m.key, m.label))
		meters_keys = keys
	for m in bar.meters:
		_set_meter(m.key, int(m.value), int(m.max))
	level_label.text = "Level %d  ·  XP %d" % [int(st.level), int(st.xp)]
	money_box.visible = bar.currency != ""
	money_label.text = "%d %s" % [int(bar.money), bar.currency]
	var tracked := ""
	for q in game.quest_list():
		if not q.done:
			tracked = "%s\n%s" % [q.name, q.journal]
			break
	quest_label.text = tracked if tracked != "" else "No open quests."
	mini_map.data = game.map_data()
	mini_map.background = _pack_image(str(mini_map.data.image)) if str(mini_map.data.image) != "" else null
	mini_map.queue_redraw()


func _set_meter(key: String, v: int, maxv: int) -> void:
	meters[key].bar.max_value = maxv
	meters[key].bar.value = v
	meters[key].num.text = "%d/%d" % [v, maxv] if key == "hp" else str(v)


func _pack_image(id: String) -> Texture2D:
	if image_cache.has(id):
		return image_cache[id]
	if id != "" and db != null:
		for pack in db.packs:
			for ext in ["png", "jpg", "jpeg", "webp"]:
				var path: String = pack.path.path_join("images/%s.%s" % [id, ext])
				if FileAccess.file_exists(path):
					var img := Image.load_from_file(ProjectSettings.globalize_path(path))
					if img != null:
						var texture := ImageTexture.create_from_image(img)
						image_cache[id] = texture
						return texture
	return null


func _image_or_placeholder(id: String, name: String) -> Texture2D:
	var texture := _pack_image(id)
	if texture != null:
		return texture
	# A soft gradient derived from the name, until real art exists.
	var h := float(abs(hash(name)) % 360) / 360.0
	var g := Gradient.new()
	g.set_color(0, Color.from_hsv(h, 0.45, 0.34))
	g.set_color(1, Color.from_hsv(fmod(h + 0.12, 1.0), 0.55, 0.12))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 1)
	t.width = 1200
	t.height = 300
	return t


func _icon(name: String) -> Texture2D:
	if icon_cache.has(name):
		return icon_cache[name]
	for ext in ["png", "svg"]:
		var path := "res://ui/icons/%s.%s" % [name, ext]
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			icon_cache[name] = texture
			return texture
	return null


func _button_icon(button: Button, name: String, size: int = 20) -> void:
	button.icon = _icon(name)
	button.add_theme_constant_override("icon_max_width", size)
	button.add_theme_constant_override("h_separation", 8)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var tint: Color = {"normal": FsTheme.TEXT_DIM, "disabled": FsTheme.TEXT_FAINT}.get(state, FsTheme.ACCENT)
		button.add_theme_color_override("icon_" + state + "_color", tint)


func _icon_view(name: String, size: int, tint: Color) -> TextureRect:
	var view := TextureRect.new()
	view.texture = _icon(name)
	view.custom_minimum_size = Vector2(size, size)
	view.size_flags_vertical = SIZE_SHRINK_CENTER
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.modulate = tint
	return view


func _with_icon(name: String, label: Label, tint: Color = FsTheme.ACCENT) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_icon_view(name, 18, tint))
	row.add_child(label)
	return row


func _toast(text: String) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", FsTheme.edged(FsTheme.SURFACE_3, FsTheme.ACCENT))
	card.add_child(FsTheme.label(text, 15, FsTheme.TEXT))
	toast_box.add_child(card)
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(card, "modulate:a", 0.0, 0.6)
	tw.tween_callback(card.queue_free)


func _log(kind: String, text: String) -> void:
	history.append({"kind": kind, "text": text})
	if history.size() > 2000:
		history = history.slice(history.size() - 2000)


func _show_errors(errors: Array) -> void:
	_clear_stage()
	var pad := _padded(32, 24)
	var box := VBoxContainer.new()
	pad.add_child(box)
	stage_box.add_child(pad)
	box.add_child(FsTheme.label("The content has errors and cannot be played:", 20, FsTheme.BAD))
	for d in errors:
		box.add_child(FsTheme.label("%s:%d  %s" % [str(d.path).get_file(), d.line, d.message], 15, FsTheme.TEXT_DIM))


# --- Input ------------------------------------------------------------------

func _choose(index: int) -> void:
	if game.runner.choose(index):
		_drain()


func _continue() -> void:
	if game.runner.proceed():
		_drain()


func _finish_moment() -> void:
	_show_location()
	_refresh_panels()


func _act(action: String, arg: String) -> void:
	if game.runner.status != "idle":
		return
	game.runner.act(action, arg)
	_drain() # A failed attempt can still produce notices or scheduled scenes.


func _on_map_place(id: String) -> void:
	_act("travel", id)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.keycode
	if overlay != null:
		if key == KEY_ESCAPE:
			_close_overlay()
		return
	if game == null or (title != null and title.visible):
		return
	if key == KEY_ESCAPE:
		_open_pause()
	elif key == KEY_F5:
		_quicksave()
	elif key == KEY_F9:
		_load_save(SaveStore.QUICKSAVE)
	elif key >= KEY_1 and key <= KEY_9 and game.runner.status == "choice":
		_choose(key - KEY_1)
	elif key == KEY_SPACE or key == KEY_ENTER:
		if game.runner.status == "continue":
			_continue()
		elif mode == "moment":
			_finish_moment()
	elif key == KEY_I:
		_open_inventory()
	elif key == KEY_J:
		_open_journal()
	elif key == KEY_M:
		_open_map()
	elif key == KEY_C:
		_open_character()
	elif key == KEY_L:
		_open_log()


# --- Overlays ---------------------------------------------------------------

func _open_overlay(heading: String, closable: bool = true, size: Vector2 = Vector2(900, 600)) -> VBoxContainer:
	_close_overlay()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(FsTheme.BG, 0.72)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: _close_overlay())
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", FsTheme.box(FsTheme.SURFACE, FsTheme.RADIUS, FsTheme.BORDER, 28))
	card.custom_minimum_size = size
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	var head := HBoxContainer.new()
	var t := FsTheme.title(heading, 27)
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(t)
	if closable:
		var row := HBoxContainer.new()
		row.add_child(_plain_label("Close", 15, FsTheme.TEXT_DIM))
		row.add_child(FsTheme.keycap("Esc"))
		var close := _face_button(head, row, _close_overlay, false, 10, 6)
		close.add_theme_stylebox_override("normal", FsTheme.box(Color.TRANSPARENT))
	box.add_child(head)
	box.add_child(FsTheme.rule())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	overlay_scroll = scroll
	overlay_footer = HBoxContainer.new()
	overlay_footer.add_theme_constant_override("separation", 10)
	box.add_child(overlay_footer)
	return content


func _close_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null


## The inventory: what is equipped on the left, the bag as a grid of
## slots in the middle, and the selected item with its actions on the right.
func _open_inventory() -> void:
	var view := get_viewport_rect().size
	var box := _open_overlay("Inventory", true, Vector2(minf(1240, view.x - 60), minf(720, view.y - 60)))
	var items := game.inventory_list()
	if items.filter(func(it): return it.id == inv_selected).is_empty():
		inv_selected = str(items[0].id) if not items.is_empty() else ""
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 26)
	body.custom_minimum_size = Vector2(0, 540)
	box.add_child(body)
	body.add_child(_equipment_column(items))
	body.add_child(FsTheme.rule_v())
	body.add_child(_bag_column(items))
	body.add_child(FsTheme.rule_v())
	body.add_child(_item_details(items))
	if not items.is_empty():
		var everything := Button.new()
		everything.text = "Drop everything"
		everything.tooltip_text = "Drop all but your journal and the gear you are using."
		everything.disabled = game.runner.status != "idle"
		everything.pressed.connect(func():
			if everything.text == "Drop everything":
				everything.text = "Confirm: drop everything"
				return
			_inventory_act("drop_everything", ""))
		var spacer := Control.new()
		spacer.size_flags_horizontal = SIZE_EXPAND_FILL
		overlay_footer.add_child(spacer)
		overlay_footer.add_child(everything)


func _select_item(id: String) -> void:
	inv_selected = id
	var scroll := inv_bag_scroll.scroll_vertical if is_instance_valid(inv_bag_scroll) else 0
	_open_inventory()
	_restore_scroll.call_deferred(inv_bag_scroll, scroll)


func _restore_scroll(scroll: ScrollContainer, value: int) -> void:
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = value


func _equipment_column(items: Array) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(250, 0)
	col.add_theme_constant_override("separation", 3)
	col.add_child(FsTheme.section("Equipped"))
	col.add_child(_gap(4))
	var gear := game.gear_summary()
	var wielded: Array = items.filter(func(it): return it.wielded)
	_slot_row(col, "Weapon", wielded[0] if not wielded.is_empty() else {})
	var worn := {}
	for it: Dictionary in items:
		if it.worn:
			var slot: String = it.slot if it.slot not in ["", "none"] else "other"
			if not worn.has(slot):
				worn[slot] = []
			worn[slot].append(it)
	var slots: Array = SLOT_ORDER.duplicate()
	slots.append_array(worn.keys().filter(func(s): return s not in SLOT_ORDER))
	for slot: String in slots:
		if not worn.has(slot):
			_slot_row(col, slot, {})
		for it: Dictionary in worn.get(slot, []):
			_slot_row(col, slot, it)
	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(fill)
	col.add_child(FsTheme.section("Load", FsTheme.BAD if gear.overburdened else FsTheme.TEXT_FAINT))
	var load_row := HBoxContainer.new()
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	bar.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	bar.max_value = maxi(1, int(gear.capacity))
	bar.value = mini(int(gear.weight), int(gear.capacity))
	bar.add_theme_stylebox_override("fill", FsTheme.box(FsTheme.BAD if gear.overburdened else FsTheme.ACCENT, 2, Color.TRANSPARENT, 0))
	load_row.add_child(bar)
	var weight := _plain_label("%d / %d lbs" % [gear.weight, gear.capacity], 14, FsTheme.BAD if gear.overburdened else FsTheme.TEXT)
	weight.add_theme_font_override("font", FsTheme.strong_font())
	load_row.add_child(weight)
	col.add_child(load_row)
	if gear.overburdened:
		col.add_child(FsTheme.label("Overburdened: you can't walk anywhere until you drop something.", 13, FsTheme.BAD))
	return col


## One equipment slot: its name, then what fills it or a dash.
func _slot_row(parent: Control, slot: String, it: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tag := FsTheme.heading(slot, 12, FsTheme.TEXT_FAINT)
	tag.custom_minimum_size = Vector2(62, 0)
	row.add_child(tag)
	if it.is_empty():
		row.add_child(_plain_label("—", 15, FsTheme.TEXT_FAINT))
		var empty := _padded(12, 5)
		empty.add_child(row)
		parent.add_child(empty)
		return
	row.add_child(_item_icon(str(it.id), 20))
	var name := _plain_label(str(it.name).capitalize(), 15, FsTheme.TEXT)
	name.size_flags_horizontal = SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.clip_text = true
	row.add_child(name)
	var id: String = it.id
	var b := _face_button(parent, row, func(): _select_item(id), false, 12, 5)
	b.tooltip_text = str(it.name).capitalize()
	b.add_theme_stylebox_override("normal", _selected_box() if id == inv_selected else FsTheme.box(FsTheme.SURFACE_2))


func _selected_box() -> StyleBoxFlat:
	var s := FsTheme.box(FsTheme.SURFACE_3, FsTheme.RADIUS, FsTheme.ACCENT)
	s.set_border_width_all(2)
	return s


func _bag_column(items: Array) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for tab: Array in INVENTORY_TABS:
		var key: String = tab[0]
		var n := items.size() if key == "all" else items.filter(func(it): return it.section == key).size()
		if n == 0 and key != "all":
			continue
		var b := Button.new()
		b.text = "%s  %d" % [tab[1], n]
		b.add_theme_font_size_override("font_size", 15)
		var active := key == inv_filter
		b.add_theme_stylebox_override("normal", FsTheme.box(FsTheme.ACCENT_DIM if active else Color.TRANSPARENT, FsTheme.RADIUS,
			Color.TRANSPARENT if active else FsTheme.BORDER, 10))
		b.add_theme_color_override("font_color", FsTheme.TEXT if active else FsTheme.TEXT_DIM)
		b.pressed.connect(func():
			inv_filter = key
			_open_inventory())
		tabs.add_child(b)
	col.add_child(tabs)
	var shown: Array = items if inv_filter == "all" else items.filter(func(it): return it.section == inv_filter)
	if shown.is_empty() and inv_filter != "all":
		inv_filter = "all"
		shown = items
	inv_bag_scroll = ScrollContainer.new()
	inv_bag_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	inv_bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(inv_bag_scroll)
	var grid := GridContainer.new()
	grid.columns = BAG_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	inv_bag_scroll.add_child(grid)
	for it: Dictionary in shown:
		_bag_tile(grid, it)
	# Empty slots fill the bag out to whole rows, at least four of them.
	var total := maxi(BAG_COLUMNS * 4, ceili(shown.size() / float(BAG_COLUMNS)) * BAG_COLUMNS)
	for _i in total - shown.size():
		var empty := Panel.new()
		empty.custom_minimum_size = Vector2(BAG_TILE, BAG_TILE)
		empty.add_theme_stylebox_override("panel", FsTheme.box(Color(FsTheme.SURFACE_2, 0.4)))
		grid.add_child(empty)
	if items.is_empty():
		col.add_child(FsTheme.label("Your pack is empty.", 15, FsTheme.TEXT_DIM))
	return col


## A bag slot: the item's picture, how many, and whether it is in use.
func _bag_tile(grid: GridContainer, it: Dictionary) -> void:
	var face := Control.new()
	face.custom_minimum_size = Vector2(BAG_TILE - 8, BAG_TILE - 8)
	var icon := _item_icon(str(it.id), 52)
	icon.set_anchors_preset(PRESET_CENTER)
	icon.offset_left = -26
	icon.offset_top = -26
	icon.offset_right = 26
	icon.offset_bottom = 26
	face.add_child(icon)
	if int(it.count) > 1:
		var count := _plain_label("×%d" % it.count, 14, FsTheme.TEXT)
		count.add_theme_font_override("font", FsTheme.strong_font())
		count.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
		count.grow_horizontal = GROW_DIRECTION_BEGIN
		count.grow_vertical = GROW_DIRECTION_BEGIN
		face.add_child(count)
	if it.worn or it.wielded:
		var tag := FsTheme.heading("Worn" if it.worn else "Held", 11, FsTheme.ACCENT)
		tag.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
		face.add_child(tag)
	var id: String = it.id
	var b := _face_button(grid, face, func(): _select_item(id), false, 4, 4)
	b.tooltip_text = str(it.name).capitalize()
	if id == inv_selected:
		b.add_theme_stylebox_override("normal", _selected_box())
		b.add_theme_stylebox_override("hover", _selected_box())


func _item_details(items: Array) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(330, 0)
	col.add_theme_constant_override("separation", 10)
	var found: Array = items.filter(func(x): return x.id == inv_selected)
	if found.is_empty():
		col.add_child(FsTheme.label("Select an item to see what it is and what you can do with it.", 15, FsTheme.TEXT_FAINT))
		return col
	var it: Dictionary = found[0]
	var frame := PanelContainer.new()
	var mat := FsTheme.box(FsTheme.BG, 3, FsTheme.BORDER, 10)
	frame.add_theme_stylebox_override("panel", mat)
	frame.custom_minimum_size = Vector2(0, 150)
	var center := CenterContainer.new()
	center.add_child(_item_icon(str(it.id), 112))
	frame.add_child(center)
	col.add_child(frame)
	var name := FsTheme.title(str(it.name).capitalize(), 24)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name)
	var tags: PackedStringArray = [{"equipment": "Wearable", "armaments": "Weapon", "consumables": "Consumable"}.get(it.section, str(it.category).capitalize())]
	if it.slot not in ["", "none"]:
		tags.append(str(it.slot))
	var pounds: int = it.weight
	tags.append(("%d lb%s" % [pounds, "" if pounds == 1 else "s"]) if pounds > 0 else "weightless")
	if int(it.count) > 1:
		tags.append("×%d carried" % it.count)
	col.add_child(FsTheme.heading("  ·  ".join(tags), 12, FsTheme.ACCENT))
	if it.worn or it.wielded:
		col.add_child(FsTheme.label("Cursed: it won't come off." if it.cursed and it.worn else ("You are wearing this." if it.worn else "You have this in hand."),
			14, FsTheme.BAD if it.cursed and it.worn else FsTheme.GOOD))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var text := FsTheme.label(str(it.description), 15, FsTheme.TEXT_DIM)
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(text)
	col.add_child(scroll)
	var id: String = it.id
	var idle: bool = game.runner.status == "idle"
	var main: Array = []
	if it.usable:
		main.append(["Use", "use", "use"])
	if it.wearable:
		main.append(["Take off", "remove", "clothing"] if it.worn else ["Wear", "wear", "clothing"])
	if it.weapon:
		main.append(["Put away", "unwield", "weapon"] if it.wielded else ["Wield", "wield", "weapon"])
	if it.purifiable:
		main.append(["Microwave", "purify", ""])
	for a: Array in main:
		var b := Button.new()
		b.text = a[0]
		if a[2] != "":
			_button_icon(b, a[2])
		b.disabled = not idle or (a[1] == "remove" and it.cursed)
		if a[1] == "remove" and it.cursed:
			b.tooltip_text = "It won't come off."
		var action: String = a[1]
		b.pressed.connect(func(): _inventory_act(action, id))
		col.add_child(b)
	var minor: Array = [["Drop", "drop"]]
	if it.count > 1:
		minor.append(["Drop all", "drop_all"])
	if not it.keep:
		minor.append(["Junk", "junk"])
		if it.count > 1:
			minor.append(["Junk all", "junk_all"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for a: Array in minor:
		var b := Button.new()
		b.text = a[0]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_stylebox_override("normal", FsTheme.box(Color.TRANSPARENT, FsTheme.RADIUS, FsTheme.BORDER, 10))
		b.disabled = not idle
		var action: String = a[1]
		if action == "junk_all":
			b.pressed.connect(func():
				if b.text == "Junk all":
					b.text = "Confirm"
					return
				_inventory_act(action, id))
		else:
			b.pressed.connect(func(): _inventory_act(action, id))
		row.add_child(b)
	col.add_child(row)
	return col


## Runs an inventory action and keeps the inventory open unless a scene started.
func _inventory_act(action: String, id: String) -> void:
	if action == "use":
		_close_overlay()
		_act("use", id)
		return
	_act(action, id)
	if game.runner.status == "idle":
		_open_inventory()
	else:
		_close_overlay()


func _open_journal() -> void:
	var box := _open_overlay("Journal")
	var quests := game.quest_list()
	if quests.is_empty():
		box.add_child(FsTheme.label("No quests yet. Talk to people to find out what they need.", 17, FsTheme.TEXT_DIM))
	for done in [false, true]:
		var list := quests.filter(func(q): return q.done == done)
		if list.is_empty():
			continue
		box.add_child(FsTheme.section("Completed" if done else "Open"))
		for q in list:
			var card := FsTheme.card(FsTheme.SURFACE_2, 14)
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 4)
			card.add_child(v)
			v.add_child(FsTheme.label(q.name, 19, FsTheme.ACCENT if not done else FsTheme.TEXT_DIM))
			v.add_child(FsTheme.label(q.region, 13, FsTheme.TEXT_FAINT))
			v.add_child(FsTheme.label(q.journal, 16, FsTheme.TEXT))
			for h in q.history:
				if h != "":
					v.add_child(FsTheme.label("·  " + h, 14, FsTheme.TEXT_DIM))
			box.add_child(card)


func _open_map() -> void:
	var box := _open_overlay("Map")
	var data := game.map_data()
	box.add_child(FsTheme.label(data.name, 18, FsTheme.TEXT_DIM))
	var view := MapView.new()
	view.custom_minimum_size = Vector2(840, 460)
	view.data = data
	view.background = _pack_image(str(data.image)) if str(data.image) != "" else null
	view.place_clicked.connect(func(id):
		_close_overlay()
		_on_map_place(id))
	box.add_child(view)
	box.add_child(FsTheme.label("Click a fast-travel point (◆) to travel there.", 14, FsTheme.TEXT_FAINT))


func _open_travel() -> void:
	var box := _open_overlay("Fast travel")
	box.add_child(FsTheme.label("Travelling takes 1 turn, and you may run into trouble on the way.", 15, FsTheme.TEXT_DIM))
	var region := ""
	for d in game.travel_destinations():
		if d.region != region:
			region = d.region
			box.add_child(FsTheme.section(region))
		var b := Button.new()
		b.text = d.name
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var id: String = d.id
		b.pressed.connect(func():
			_close_overlay()
			_act("travel", id))
		box.add_child(b)


## The character sheet: attributes, vitals and feats on the left, how the
## player looks in words in the middle, body parts and gear on the right.
func _open_character() -> void:
	var view := get_viewport_rect().size
	var box := _open_overlay(str(game.value("player.name")), true, Vector2(minf(1240, view.x - 60), minf(660, view.y - 60)))
	var s := game.status_snapshot()
	var st: Dictionary = s.stats
	var changed := BodySystem.view(game).any(func(p): return p.form_id != "human")
	var species := SurvivalSystem.species(game, "player") if changed else "human"
	var mind := SurvivalSystem.humanity_description(game).get_slice(".", 0)
	box.add_child(FsTheme.heading("Level %d  ·  %s  ·  %s" % [int(st.level), species, mind], 13, FsTheme.ACCENT))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 26)
	body.custom_minimum_size = Vector2(0, 520)
	box.add_child(body)
	body.add_child(_sheet_stats(s))
	body.add_child(FsTheme.rule_v())
	body.add_child(_sheet_appearance())
	body.add_child(FsTheme.rule_v())
	body.add_child(_sheet_body())


func _sheet_stats(s: Dictionary) -> Control:
	var st: Dictionary = s.stats
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	col.add_theme_constant_override("separation", 8)
	col.add_child(FsTheme.section("Attributes"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for k: String in ["strength", "dexterity", "stamina", "charisma", "intelligence", "perception"]:
		var v := int(st[k])
		var block := PanelContainer.new()
		block.add_theme_stylebox_override("panel", FsTheme.box(FsTheme.SURFACE_2, FsTheme.RADIUS, Color.TRANSPARENT, 10))
		block.size_flags_horizontal = SIZE_EXPAND_FILL
		block.tooltip_text = "%s %d (modifier %+d)" % [k.capitalize(), v, (v - 10) / 2]
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 0)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		var abbr := FsTheme.heading(k.substr(0, 3), 12, FsTheme.TEXT_FAINT)
		abbr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(abbr)
		var num := FsTheme.title(str(v), 28)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(num)
		var mod := FsTheme.heading("%+d" % ((v - 10) / 2), 12, FsTheme.ACCENT if v > 12 else FsTheme.TEXT_FAINT)
		mod.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(mod)
		block.add_child(inner)
		_pass_clicks(inner)
		grid.add_child(block)
	col.add_child(grid)
	col.add_child(_gap(6))
	col.add_child(FsTheme.section("Vitals"))
	for spec in [["Health", int(st.hp), int(st.maxhp), FsTheme.METER.hp], ["Humanity", int(st.humanity), 100, FsTheme.METER.humanity],
			["Libido", int(st.libido), 100, FsTheme.METER.libido], ["Hunger", int(st.hunger), 100, FsTheme.METER.hunger],
			["Thirst", int(st.thirst), 100, FsTheme.METER.thirst]]:
		col.add_child(_sheet_meter(spec[0], spec[1], spec[2], spec[3]))
	var facts := HBoxContainer.new()
	facts.add_child(_sheet_fact("Morale", str(int(st.morale))))
	facts.add_child(_sheet_fact("XP", str(int(st.xp))))
	facts.add_child(_sheet_fact("Freecred", str(int(st.freecred))))
	col.add_child(facts)
	col.add_child(_gap(6))
	col.add_child(FsTheme.section("Feats"))
	var feats := HFlowContainer.new()
	feats.add_theme_constant_override("h_separation", 6)
	feats.add_theme_constant_override("v_separation", 6)
	for id: String in game.state.feats:
		feats.add_child(_chip(game.content.typed_value("feat", id, "name", id.capitalize()),
			game.content.typed_value("feat", id, "description"), FsTheme.TEXT))
	if game.state.feats.is_empty():
		var none := FsTheme.label("None yet.", 15, FsTheme.TEXT_FAINT)
		none.autowrap_mode = TextServer.AUTOWRAP_OFF  # in a flow container a wrapping label shrinks to one letter
		feats.add_child(none)
	col.add_child(feats)
	if not s.conditions.is_empty():
		col.add_child(FsTheme.section("Conditions"))
		var conds := HFlowContainer.new()
		conds.add_theme_constant_override("h_separation", 6)
		for id: String in s.conditions:
			conds.add_child(_chip(game.content.typed_value("condition", id, "name", id),
				game.content.typed_value("condition", id, "description"), FsTheme.INFO))
		col.add_child(conds)
	return col


func _sheet_meter(name: String, v: int, maxv: int, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := FsTheme.heading(name, 12, FsTheme.TEXT_DIM)
	label.custom_minimum_size = Vector2(74, 0)
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 5)
	bar.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	bar.max_value = maxi(1, maxv)
	bar.value = v
	bar.add_theme_stylebox_override("fill", FsTheme.box(color, 2, Color.TRANSPARENT, 0))
	row.add_child(bar)
	var num := _plain_label("%d/%d" % [v, maxv] if name == "Health" else str(v), 14, FsTheme.TEXT)
	num.add_theme_font_override("font", FsTheme.strong_font())
	num.custom_minimum_size = Vector2(46, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(num)
	return row


func _sheet_fact(name: String, value: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_child(FsTheme.heading(name, 12, FsTheme.TEXT_FAINT))
	v.add_child(FsTheme.title(value, 18))
	return v


## A small tag with a tooltip, for feats and conditions.
func _chip(text: String, tip: String, color: Color) -> Control:
	var p := PanelContainer.new()
	var style := FsTheme.box(FsTheme.SURFACE_2, FsTheme.RADIUS, FsTheme.BORDER, 8)
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", style)
	p.tooltip_text = tip
	var l := _plain_label(text, 14, color)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


## How the player looks, in words (the self_description text).
func _sheet_appearance() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	col.add_child(FsTheme.section("Appearance"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 14)
	scroll.add_child(text)
	var paragraphs := game.self_description()
	if paragraphs.is_empty():
		text.add_child(FsTheme.label("There is no description of your body in the loaded content.", 15, FsTheme.TEXT_FAINT))
	for p in paragraphs:
		var r := _rich(_esc(p))
		r.add_theme_font_size_override("normal_font_size", 17)
		text.add_child(r)
	return col


## A tamed companion on the character sheet: its numbers, and Summon or Dismiss
## while no scene is open.
func _ally_row(id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var following := id in game.state.companions
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	var name := FsTheme.label(game.content.field_value(id, "name", id) + ("  ·  with you" if following else ""), 16,
		FsTheme.TEXT if following else FsTheme.TEXT_DIM)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.add_child(name)
	var numbers := FsTheme.label("Level %d  ·  damage %d  ·  dexterity %d" % [CompanionSystem.num(game, id, "level"),
		CompanionSystem.num(game, id, "damage"), CompanionSystem.num(game, id, "dexterity")], 13, FsTheme.TEXT_FAINT)
	numbers.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.add_child(numbers)
	row.add_child(info)
	if game.runner.status == "idle":
		var b := Button.new()
		b.text = "Dismiss" if following else "Summon"
		var action := "dismiss" if following else "summon"
		b.pressed.connect(func():
			_close_overlay()
			_act(action, id))
		row.add_child(b)
	return row


func _sheet_body() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	col.add_theme_constant_override("separation", 3)
	col.add_child(FsTheme.section("Body"))
	col.add_child(_gap(4))
	for part: Dictionary in BodySystem.view(game):
		if part.id in ["cock", "cunt"] and not game.adjective("player", "male" if part.id == "cock" else "female"):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.tooltip_text = str(part.description).capitalize() if str(part.description) != "" else ""
		row.mouse_filter = MOUSE_FILTER_STOP
		var tag := FsTheme.heading(part.part, 12, FsTheme.TEXT_FAINT)
		tag.custom_minimum_size = Vector2(62, 0)
		tag.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(tag)
		var changed: bool = part.form_id != "human"
		var form := _plain_label(part.form, 15, FsTheme.ACCENT if changed else FsTheme.TEXT_DIM)
		form.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(form)
		var pad := _padded(12, 4)
		pad.add_child(row)
		col.add_child(pad)
	col.add_child(_gap(10))
	col.add_child(FsTheme.section("Gear"))
	var gear := game.gear_summary()
	col.add_child(_gear_line("Weapon", str(gear.weapon) if gear.weapon != "" else "Unarmed"))
	var worn: Array = gear.worn.map(func(w): return str(w.name).capitalize())
	col.add_child(_gear_line("Wearing", ", ".join(worn) if not worn.is_empty() else "Nothing special"))
	col.add_child(_gear_line("Load", "%d / %d lbs%s" % [gear.weight, gear.capacity, "  ·  overburdened" if gear.overburdened else ""]))
	var allies := CompanionSystem.tamed(game)
	if not allies.is_empty():
		col.add_child(_gap(10))
		col.add_child(FsTheme.section("Allies  ·  %d of %d with you" % [game.state.companions.size(), CompanionSystem.limit(game)]))
		for ally: String in allies:
			col.add_child(_ally_row(ally))
	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(fill)
	var inv := Button.new()
	inv.text = "Open inventory"
	_button_icon(inv, "inventory")
	inv.pressed.connect(_open_inventory)
	col.add_child(inv)
	return col


func _gear_line(name: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var tag := FsTheme.heading(name, 12, FsTheme.TEXT_FAINT)
	tag.custom_minimum_size = Vector2(62, 0)
	tag.size_flags_vertical = SIZE_SHRINK_BEGIN
	row.add_child(tag)
	var v := FsTheme.label(value, 15, FsTheme.TEXT)
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(v)
	var pad := _padded(12, 4)
	pad.add_child(row)
	return pad


func _open_new_game() -> void:
	var fresh := _ensure_game()
	var box := _open_overlay("New game")
	var brand := db.branding()
	if str(brand.get("title", "")) != "":
		box.add_child(FsTheme.label(str(brand.title), 34, FsTheme.ACCENT))
	if str(brand.get("subtitle", "")) != "":
		box.add_child(FsTheme.label(str(brand.subtitle), 17, FsTheme.TEXT_DIM))
	var name := LineEdit.new()
	name.text = "Player"
	name.placeholder_text = "Character name"
	box.add_child(FsTheme.heading("Name"))
	box.add_child(name)
	var pronouns := OptionButton.new()
	for label in ["He / him", "She / her", "They / them"]:
		pronouns.add_item(label)
	box.add_child(FsTheme.heading("Pronouns"))
	box.add_child(pronouns)
	var main_stat := OptionButton.new()
	for label in ["Strength", "Dexterity", "Stamina", "Charisma", "Intelligence", "Perception"]:
		main_stat.add_item(label)
	box.add_child(FsTheme.heading("Main stat"))
	box.add_child(main_stat)
	box.add_child(FsTheme.label("Your main stat starts at 17 and the others at 12.", 15, FsTheme.TEXT_DIM))
	# Automated screenshots use the defaults, not this player's remembered choices.
	if shot_path == "" and fresh:
		_load_content_prefs()
	for id in game.content.all_of("scenario"):
		box.add_child(FsTheme.heading("Scenario: " + game.content.typed_value("scenario", id, "name", id)))
		box.add_child(FsTheme.label(game.content.typed_value("scenario", id, "description"), 17))
	box.add_child(FsTheme.section("Content"))
	var content_panel := _content_settings_panel()
	content_panel.visible = false
	var summary := FsTheme.label(_content_summary(), 15, FsTheme.TEXT_DIM)
	box.add_child(summary)
	box.add_child(content_panel)
	content_panel.child_entered_tree.connect(func(_c: Node): summary.text = _content_summary())
	content_toggle = Button.new()
	content_toggle.text = "Content settings"
	_button_icon(content_toggle, "settings")
	content_toggle.toggle_mode = true
	content_toggle.toggled.connect(func(on: bool):
		content_panel.visible = on
		if on:
			_scroll_to.call_deferred(summary))
	for id in game.content.all_of("scenario"):
		var start_button := Button.new()
		start_button.text = "Start — " + game.content.typed_value("scenario", id, "name", id)
		start_button.pressed.connect(func():
			_close_overlay()
			_hide_title()
			_save_content_prefs()
			game.start_scenario(id, name.text.strip_edges() if name.text.strip_edges() != "" else "Player",
				main_stat.get_item_text(main_stat.selected).to_lower(), ["he", "she", "they"][pronouns.selected])
			_drain())
		overlay_footer.add_child(start_button)
	overlay_footer.add_child(content_toggle)


func _open_settings() -> void:
	var box := _open_overlay("Settings")
	box.add_child(FsTheme.section("Display"))
	box.add_child(_choice_row("Window", "How the game window is shown.", ["Windowed", "Full screen"],
		1 if prefs.get_value("display", "fullscreen", false) else 0,
		func(i: int): _set_pref("fullscreen", i == 1)))
	var scales: Array = UI_SCALES.map(func(f): return "%d%%" % roundi(f * 100))
	box.add_child(_choice_row("Interface size", "Text and controls grow with the window; this scales them further.", scales,
		maxi(0, UI_SCALES.find(float(prefs.get_value("display", "ui_scale", 1.0)))),
		func(i: int): _set_pref("ui_scale", UI_SCALES[i])))
	box.add_child(FsTheme.section("Content"))
	if game != null and game.settings.started:
		box.add_child(_content_settings_panel())
	else:
		box.add_child(FsTheme.label("Content filters and levels are chosen on the new-game screen, and can be changed here during a game.", 15, FsTheme.TEXT_DIM))
	box.add_child(FsTheme.section("Keys"))
	box.add_child(FsTheme.label("1–9 choose · Space or Enter continue · I inventory · J journal · M map · C character · L log · F5 quicksave · F9 quickload · Esc menu", 15, FsTheme.TEXT_DIM))


func _choice_row(name: String, description: String, options: Array, selected: int, changed: Callable) -> Control:
	var card := FsTheme.card(FsTheme.SURFACE_2, 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.add_child(FsTheme.label(name, 17))
	text.add_child(FsTheme.label(description, 14, FsTheme.TEXT_DIM))
	row.add_child(text)
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(180, 0)
	pick.size_flags_vertical = SIZE_SHRINK_CENTER
	for o in options:
		pick.add_item(str(o))
	pick.select(selected)
	pick.item_selected.connect(changed)
	row.add_child(pick)
	return card


func _set_pref(key: String, value: Variant) -> void:
	prefs.set_value("display", key, value)
	if shot_path == "":
		prefs.save(PREFS)
	_apply_display_prefs()


func _apply_display_prefs() -> void:
	get_window().content_scale_factor = float(prefs.get_value("display", "ui_scale", 1.0))
	var full: bool = prefs.get_value("display", "fullscreen", false)
	var mode_now := DisplayServer.window_get_mode()
	if full and mode_now != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not full and mode_now == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## Content filters and levels, as on the new-game screen and in Settings.
func _content_settings_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	_fill_content_settings(panel)
	return panel


## Rebuilds the panel from the game's settings; a change can affect other
## rows (no vore also bans the vore filters).
func _fill_content_settings(panel: VBoxContainer) -> void:
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()
	var view := game.content_settings()
	var note := "Banned content never appears. Warded creatures only appear when you hunt for them."
	if view.started:
		note += " Bans were fixed when the game started; wards and content levels can still change."
	else:
		note += " Bans are fixed once the game starts; wards and content levels can be changed later in Settings."
	panel.add_child(FsTheme.label(note, 15, FsTheme.TEXT_DIM))
	var group := ""
	for f: Dictionary in view.filters:
		if f.group != group:
			group = f.group
			panel.add_child(FsTheme.section(group if group != "" else "Other"))
		panel.add_child(_filter_row(panel, f))
	if not view.levels.is_empty():
		panel.add_child(FsTheme.section("Content levels"))
	for lv: Dictionary in view.levels:
		panel.add_child(_level_row(panel, lv))
	var igroup := "-"
	for it: Dictionary in view.get("interests", []):
		if it.group != igroup:
			igroup = it.group
			panel.add_child(FsTheme.section(igroup if igroup != "" else "Interested in"))
		panel.add_child(_interest_row(panel, it))


## An interest (Males, Females ...): a yes/no switch the player can change at any time.
func _interest_row(panel: VBoxContainer, it: Dictionary) -> Control:
	var card := FsTheme.card(FsTheme.SURFACE_2, 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.add_child(FsTheme.label(it.name, 17))
	if it.description != "":
		text.add_child(FsTheme.label(it.description, 14, FsTheme.TEXT_DIM))
	row.add_child(text)
	var toggle := CheckButton.new()
	toggle.button_pressed = it.value
	toggle.text = "Yes" if it.value else "No"
	toggle.size_flags_vertical = SIZE_SHRINK_CENTER
	var id: String = it.id
	toggle.toggled.connect(func(on: bool):
		game.set_interest(id, on)
		_fill_content_settings(panel))
	row.add_child(toggle)
	return card


func _filter_row(panel: VBoxContainer, f: Dictionary) -> Control:
	var card := FsTheme.card(FsTheme.SURFACE_2, 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.add_child(FsTheme.label(f.name, 17))
	if f.description != "":
		text.add_child(FsTheme.label(f.description, 14, FsTheme.TEXT_DIM))
	row.add_child(text)
	var buttons := ButtonGroup.new()
	for spec in [["normal", "Normal", f.can_normal], ["warded", "Warded", f.can_ward], ["banned", "Banned", f.can_ban]]:
		var to: String = spec[0]
		var b := Button.new()
		b.text = spec[1]
		b.toggle_mode = true
		b.button_group = buttons
		b.button_pressed = f.state == to
		b.disabled = not spec[2]
		b.custom_minimum_size = Vector2(96, 0)
		if to == "banned":
			b.add_theme_stylebox_override("pressed", FsTheme.box(FsTheme.BAD.darkened(0.6), 8, FsTheme.BAD, 12))
		var id: String = f.id
		b.pressed.connect(func():
			game.set_filter(id, to)
			_fill_content_settings(panel))
		row.add_child(b)
	return card


func _level_row(panel: VBoxContainer, lv: Dictionary) -> Control:
	var card := FsTheme.card(FsTheme.SURFACE_2, 10)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.add_child(FsTheme.label(lv.name, 17))
	if lv.description != "":
		text.add_child(FsTheme.label(lv.description, 14, FsTheme.TEXT_DIM))
	top.add_child(text)
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(180, 0)
	pick.size_flags_vertical = SIZE_SHRINK_BEGIN
	var ids: Array = []
	var chosen := ""
	for o: Dictionary in lv.options:
		pick.add_item(o.name)
		ids.append(o.id)
		if o.id == lv.value:
			pick.select(ids.size() - 1)
			chosen = o.description
	var id: String = lv.id
	pick.item_selected.connect(func(index: int):
		game.set_level(id, str(ids[index]))
		_fill_content_settings(panel))
	top.add_child(pick)
	v.add_child(top)
	if chosen != "":
		v.add_child(FsTheme.label(chosen, 15, FsTheme.ACCENT))
	return card


## One line naming what is banned, warded or not at its default level.
func _content_summary() -> String:
	var view := game.content_settings()
	var parts: PackedStringArray = []
	for state in ["banned", "warded"]:
		var names: Array = view.filters.filter(func(f): return f.state == state).map(func(f): return f.name)
		if not names.is_empty():
			parts.append("%s: %s" % [state.capitalize(), ", ".join(names)])
	for lv: Dictionary in view.levels:
		if lv.value != game.content.levels[lv.id].default:
			parts.append("%s: %s" % [lv.name, str(lv.value).capitalize()])
	return "Nothing banned or warded; standard content levels." if parts.is_empty() else ". ".join(parts) + "."


func _scroll_to(control: Control) -> void:
	await get_tree().process_frame
	if overlay_scroll != null and is_instance_valid(control):
		overlay_scroll.ensure_control_visible(control)
		overlay_scroll.scroll_vertical = maxi(overlay_scroll.scroll_vertical, int(control.position.y) - 40)


func _load_content_prefs() -> void:
	if not FileAccess.file_exists(CONTENT_PREFS):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PREFS))
	if not data is Dictionary:
		return
	var levels: Dictionary = data.get("levels", {}) if data.get("levels", {}) is Dictionary else {}
	for id in levels:
		game.set_level(str(id), str(levels[id]))
	var interests: Dictionary = data.get("interests", {}) if data.get("interests", {}) is Dictionary else {}
	for id in interests:
		game.set_interest(str(id), bool(interests[id]))
	# Filters last, so they end as saved even where a level bans or allows one.
	var banned: Array = data.get("banned", []) if data.get("banned", []) is Array else []
	var warded: Array = data.get("warded", []) if data.get("warded", []) is Array else []
	for id in game.content.all_of("filter"):
		game.set_filter(id, "banned" if id in banned else "warded" if id in warded else "normal")


func _save_content_prefs() -> void:
	var f := FileAccess.open(CONTENT_PREFS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"banned": game.settings.banned, "warded": game.settings.warded,
			"levels": game.settings.levels, "interests": game.settings.get("interests", {})}, "  "))


func _open_hunt() -> void:
	var box := _open_overlay("Hunt")
	for id in game.runner.encounter_pool(game.content.typed_value("location", game.state.location, "zone"), true):
		var button := Button.new()
		button.text = game.content.typed_value("creature", id, "name", id)
		button.pressed.connect(func():
			_close_overlay()
			_act("hunt", id))
		box.add_child(button)


func _show_combat(event: Dictionary) -> void:
	_ensure_page()
	# The foe's state sits with the actions, below the scrolling text.
	choices_box.add_child(FsTheme.section("%s  ·  Round %d" % [event.name, event.round], FsTheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	for spec in [["Health", event.hp, event.maxhp, FsTheme.METER.hp], ["Lust", event.lust, 100, FsTheme.METER.libido]]:
		var name := FsTheme.heading(spec[0], 13, FsTheme.TEXT_DIM)
		name.custom_minimum_size = Vector2(56, 0)
		grid.add_child(name)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 6)
		bar.size_flags_horizontal = SIZE_EXPAND_FILL
		bar.size_flags_vertical = SIZE_SHRINK_CENTER
		bar.max_value = spec[2]
		bar.value = spec[1]
		bar.show_percentage = false
		bar.add_theme_stylebox_override("fill", FsTheme.box(spec[3], 2, Color.TRANSPARENT, 0))
		grid.add_child(bar)
		var num := _plain_label("%d / %d" % [spec[1], spec[2]], 15, FsTheme.TEXT)
		num.add_theme_font_override("font", FsTheme.strong_font())
		num.custom_minimum_size = Vector2(64, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(num)
	choices_box.add_child(grid)
	choices_box.add_child(_gap(4))
	if event.grappled:
		choices_box.add_child(FsTheme.label("You are held fast. Struggle to slip free.", 16, FsTheme.BAD))
	var buttons := GridContainer.new()
	buttons.columns = 3
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	for action: String in event.actions:
		var button := Button.new()
		button.text = {"throw": "Throw the fight", "pass": "Pass turn"}.get(action, action.capitalize())
		button.custom_minimum_size = Vector2(180, 46)
		button.pressed.connect(func():
			_new_page()
			game.runner.combat_action(action)
			_drain())
		buttons.add_child(button)
	for it in event.get("items", []):
		var item_button := Button.new()
		item_button.text = "Use %s%s" % [str(it.name), (" (%d)" % it.count) if it.count > 1 else ""]
		_button_icon(item_button, "use")
		item_button.custom_minimum_size = Vector2(180, 46)
		var item_id: String = it.id
		item_button.pressed.connect(func():
			_new_page()
			game.runner.combat_action("use " + item_id)
			_drain())
		buttons.add_child(item_button)
	choices_box.add_child(buttons)


func _open_log() -> void:
	var box := _open_overlay("Log")
	if history.is_empty():
		box.add_child(FsTheme.label("Nothing has happened yet.", 16, FsTheme.TEXT_DIM))
	for h in history.slice(maxi(0, history.size() - 300)):
		match h.kind:
			"title":
				box.add_child(FsTheme.label(h.text, 20, FsTheme.ACCENT))
			"note":
				box.add_child(FsTheme.label("•  " + h.text, 14, FsTheme.GOOD))
			_:
				box.add_child(FsTheme.label(h.text, 16, FsTheme.TEXT))


# --- Game lifecycle and title -------------------------------------------------

## Replaces the game with a fresh, unstarted one and clears the screen's memory of the old one.
func _reset_game() -> void:
	if game != null:
		game.dispose()
	game = Game.new(db, seed_value if seed_value != 0 else int(Time.get_unix_time_from_system()))
	history.clear()
	location_view = {}
	mode = ""
	last_autosave_turn = -1


## Makes sure there is a game that hasn't started, for the new-game screen.
## Returns true if a new one was made.
func _ensure_game() -> bool:
	if game != null and not game.settings.started and game.state.location == "":
		return false
	_reset_game()
	return true


func _show_title() -> void:
	_close_overlay()
	if title == null:
		title = TitleScreen.new()
		title.chosen.connect(_on_title)
		add_child(title)
		var b := db.branding()
		title.set_branding(str(b.get("title", "")), str(b.get("subtitle", "")), _pack_image(str(b.get("logo", ""))),
			_pack_image(str(b.get("background", ""))), str(b.get("about", "")),
			Array(b.get("menu icons", [])).map(func(id): return _pack_image(str(id))).filter(func(t): return t != null))
	move_child(title, get_child_count() - 1)
	title.visible = true
	title.show_message("")
	game_root.visible = false
	var latest := store.latest()
	title.set_continue(_save_line(latest) if not latest.is_empty() else "")


func _hide_title() -> void:
	if title != null:
		title.visible = false
	game_root.visible = true


func _on_title(action: String) -> void:
	match action:
		"continue":
			var latest := store.latest()
			if not latest.is_empty():
				_load_save(str(latest.id))
		"new":
			_open_new_game()
		"load":
			_open_saves(false)
		"settings":
			_open_settings()
		"credits":
			_open_credits()
		"quit":
			get_tree().quit()


## A message where the player can see it: a toast in play, a line on the title.
func _notify(text: String) -> void:
	if title != null and title.visible:
		title.show_message(text)
	else:
		_toast(text)


func _in_game() -> bool:
	return game != null and game.settings.started and not (title != null and title.visible)


func _open_pause() -> void:
	if not _in_game():
		return
	var box := _open_overlay("Menu", true, Vector2(560, 620))
	box.add_child(FsTheme.label("%s · %s · Day %d, %s" % [str(game.value("player.name")),
		game.save_summary().location, game.day(), game.time_slot()], 17, FsTheme.TEXT_DIM))
	for spec in [["Resume", _close_overlay], ["Save game", func(): _open_saves(true)], ["Load game", func(): _open_saves(false)],
			["Settings", _open_settings], ["Credits", _open_credits], ["Main menu", _to_main_menu], ["Quit", _quit]]:
		var b := Button.new()
		b.text = spec[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(320, 48)
		b.size_flags_horizontal = SIZE_SHRINK_BEGIN
		b.pressed.connect(spec[1])
		box.add_child(b)
	box.add_child(FsTheme.label("Your progress is saved automatically after each turn passes, when no scene is open.", 14, FsTheme.TEXT_FAINT))


func _to_main_menu() -> void:
	_autosave_now()
	_show_title()


func _quit() -> void:
	_autosave_now()
	get_tree().quit()


# --- Saving -----------------------------------------------------------------

func _can_save() -> bool:
	return _in_game() and game.runner.status == "idle" and game.state.ending == ""


## A small picture of the screen for the save list, or nothing.
func _thumbnail() -> PackedByteArray:
	if DisplayServer.get_name() == "headless":
		return PackedByteArray()
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return PackedByteArray()
	img.resize(320, int(320.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	return img.save_png_to_buffer()


## Autosaves once each time a turn has passed and the game is waiting for the player.
func _maybe_autosave() -> void:
	if shot_path != "" or not _can_save() or game.state.turn == last_autosave_turn:
		return
	last_autosave_turn = game.state.turn
	_autosave.call_deferred()


func _autosave() -> void:
	# Wait until the new screen is drawn so the thumbnail shows it.
	await RenderingServer.frame_post_draw
	if _can_save():
		store.write(SaveStore.AUTOSAVE, game, "", _thumbnail())


func _autosave_now() -> void:
	if shot_path == "" and _can_save():
		store.write(SaveStore.AUTOSAVE, game, "", _thumbnail())


func _quicksave() -> void:
	if not _can_save():
		_notify("You can save when you are not in the middle of a scene.")
		return
	if store.write(SaveStore.QUICKSAVE, game, "", _thumbnail()):
		_toast("Quicksaved. Press F9 to load it.")
	else:
		_toast(store.last_error)


func _write_save(id: String, name: String, thumb: PackedByteArray) -> void:
	if store.write(id, game, name, thumb):
		_close_overlay()
		_toast("Game saved.")
	else:
		_notify(store.last_error)


## Loads a save into a new game object, so a failed load leaves the current game as it was.
func _load_save(id: String) -> bool:
	var fresh := Game.new(db, seed_value if seed_value != 0 else int(Time.get_unix_time_from_system()))
	if not store.load_into(id, fresh):
		fresh.dispose()
		_notify(store.last_error)
		return false
	if game != null:
		game.dispose()
	game = fresh
	history.clear()
	location_view = {}
	mode = ""
	last_autosave_turn = game.state.turn
	_close_overlay()
	_hide_title()
	game.runner.show_location()
	_drain()
	_toast("Loaded: " + str(store.read(id).get("meta", {}).get("name", id)))
	return true


func _save_line(meta: Dictionary) -> String:
	if meta.get("damaged", false):
		return "This save file is damaged."
	var parts: PackedStringArray = []
	if str(meta.get("player", "")) != "":
		parts.append(str(meta.player))
	if str(meta.get("location", "")) != "":
		parts.append(str(meta.location))
	if meta.has("day"):
		parts.append("Day %d, %s" % [int(meta.day), str(meta.get("time", ""))])
	parts.append(_when(int(meta.get("saved_at", 0))))
	return " · ".join(parts)


static func _when(unix: int) -> String:
	if unix <= 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var t := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%04d-%02d-%02d %02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute]


## The save list, for saving (`saving`) or loading.
func _open_saves(saving: bool) -> void:
	# Take the picture before the list covers the screen.
	var thumb := _thumbnail() if saving and _can_save() else PackedByteArray()
	var box := _open_overlay("Save game" if saving else "Load game")
	if saving:
		if not _can_save():
			box.add_child(FsTheme.label("You can save when you are not in the middle of a scene or a fight.", 16, FsTheme.BAD))
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var name := LineEdit.new()
			name.placeholder_text = "%s, %s (day %d)" % [str(game.value("player.name")), game.save_summary().location, game.day()]
			name.size_flags_horizontal = SIZE_EXPAND_FILL
			row.add_child(name)
			var b := Button.new()
			b.text = "Save as new"
			_button_icon(b, "save")
			b.pressed.connect(func(): _write_save(store.new_id(), name.text if name.text.strip_edges() != "" else name.placeholder_text, thumb))
			name.text_submitted.connect(func(_t: String): b.pressed.emit())
			row.add_child(b)
			box.add_child(row)
			name.grab_focus.call_deferred()
	var saves := store.list()
	if saves.is_empty():
		box.add_child(FsTheme.label("No saved games yet.", 17, FsTheme.TEXT_DIM))
	for meta: Dictionary in saves:
		box.add_child(_save_card(meta, saving, thumb))
	if not saving:
		box.add_child(FsTheme.label("F5 quicksaves and F9 loads the quicksave. The autosave is updated after each turn.", 14, FsTheme.TEXT_FAINT))


func _save_card(meta: Dictionary, saving: bool, thumb: PackedByteArray) -> Control:
	var id := str(meta.id)
	var card := FsTheme.card(FsTheme.SURFACE_2, 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(176, 99)
	pic.size_flags_vertical = SIZE_SHRINK_CENTER
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var img := Image.new()
	if str(meta.get("thumbnail", "")) != "" and img.load(str(meta.thumbnail)) == OK:
		pic.texture = ImageTexture.create_from_image(img)
	else:
		var ph := ColorRect.new()
		ph.color = FsTheme.SURFACE_3
		ph.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		pic.add_child(ph)
	row.add_child(pic)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 3)
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var save_name := _plain_label(str(meta.get("name", id)), 18, FsTheme.TEXT)
	save_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	save_name.size_flags_horizontal = SIZE_EXPAND_FILL
	save_name.clip_text = true
	if str(meta.get("kind", "Save")) != "Save":
		head.add_child(_plain_label(str(meta.kind).to_upper(), 13, FsTheme.ACCENT))
	head.add_child(save_name)
	text.add_child(head)
	text.add_child(FsTheme.label(_save_line(meta), 14, FsTheme.BAD if meta.get("damaged", false) else FsTheme.TEXT_DIM))
	if str(meta.get("scenario", "")) != "":
		text.add_child(FsTheme.label("Scenario: %s · Level %d" % [str(meta.scenario), int(meta.get("level", 0))], 13, FsTheme.TEXT_FAINT))
	row.add_child(text)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	row.add_child(buttons)
	var damaged: bool = meta.get("damaged", false)
	if saving and _can_save() and id != SaveStore.AUTOSAVE and not damaged:
		var over := Button.new()
		over.text = "Overwrite"
		over.pressed.connect(func(): _write_save(id, str(meta.get("name", "")), thumb))
		buttons.add_child(over)
	elif not saving and not damaged:
		var load_button := Button.new()
		load_button.text = "Load"
		_button_icon(load_button, "load")
		load_button.pressed.connect(func(): _load_save(id))
		buttons.add_child(load_button)
	var del := Button.new()
	del.text = "Delete"
	del.pressed.connect(func():
		if del.text == "Delete":
			del.text = "Confirm delete"
			return
		store.delete(id)
		_open_saves(saving))
	buttons.add_child(del)
	return card


# --- Credits ------------------------------------------------------------------

func _open_credits() -> void:
	var box := _open_overlay("Credits")
	var credits := db.credits()
	var brand := db.branding()
	if str(brand.get("title", "")) != "":
		box.add_child(FsTheme.label(str(brand.title), 26, FsTheme.ACCENT))
	if str(brand.get("about", "")) != "":
		box.add_child(FsTheme.label(str(brand.about), 16, FsTheme.TEXT))
	if not credits.writers.is_empty():
		box.add_child(FsTheme.section("Writers of the content in this build"))
		box.add_child(FsTheme.label(", ".join(credits.writers) + ".", 16, FsTheme.TEXT_DIM))
	box.add_child(FsTheme.section("Art"))
	var by_artist := {}
	for a: Dictionary in credits.art:
		if not by_artist.has(a.artist):
			by_artist[a.artist] = []
		by_artist[a.artist].append(str(a.image).replace("_", " "))
	for artist in by_artist:
		box.add_child(FsTheme.label("%s — %s" % [artist, ", ".join(by_artist[artist])], 15, FsTheme.TEXT_DIM))
	box.add_child(FsTheme.section("Engine"))
	box.add_child(FsTheme.label("MAGE (Modular Adventure Game Engine), created by Seaturtle5.", 15, FsTheme.TEXT_DIM))
	box.add_child(FsTheme.label("Fonts: Literata by TypeTogether and Barlow by Jeremy Tribby, both under the SIL Open Font License (ui/fonts).", 15, FsTheme.TEXT_DIM))
	box.add_child(FsTheme.section("Content packs"))
	for p: Dictionary in credits.packs:
		box.add_child(FsTheme.label("%s %s%s" % [p.name, p.version, (" — " + str(p.authors)) if str(p.authors) != "" else ""], 15, FsTheme.TEXT_DIM))


# --- Automated screenshots --------------------------------------------------

func _take_screenshot() -> void:
	for step in shot_steps:
		var parts: PackedStringArray = step.strip_edges().split(" ", false, 1)
		if parts.is_empty():
			continue
		var arg := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"new":
				_ensure_game()
				_close_overlay()
				_hide_title()
				game.start_scenario(arg)
				_drain()
			"combat":
				_new_page()
				game.runner.combat_action(arg)
				_drain()
			"choose":
				_choose(int(arg) - 1)
			"continue":
				if game.runner.status == "continue":
					_continue()
				elif mode == "moment":
					_finish_moment()
			"filter", "level":
				# Content settings, as on the settings screen: "filter furry banned", "level anal more".
				var words := arg.split(" ", false)
				if game == null:
					_ensure_game()
				if words.size() == 2:
					if parts[0] == "filter":
						game.set_filter(words[0], words[1])
					else:
						game.set_level(words[0], words[1])
			"save":
				# "save Name" writes a manual save (screenshot runs use their own folder).
				if _can_save():
					await RenderingServer.frame_post_draw
					store.write(store.new_id() if arg == "" else arg.to_snake_case(), game, arg, _thumbnail())
			"quicksave":
				await RenderingServer.frame_post_draw
				_quicksave()
			"title":
				_show_title()
			"scroll":
				# "scroll end" shows the bottom of the open overlay.
				if arg == "actions" and sidebar_scroll != null:
					for _i in 3:
						await get_tree().process_frame
					sidebar_scroll.scroll_vertical = int(sidebar_scroll.get_v_scroll_bar().max_value)
				elif overlay != null and overlay_scroll != null:
					for _i in 3:
						await get_tree().process_frame
					overlay_scroll.scroll_vertical = int(overlay_scroll.get_v_scroll_bar().max_value)
			"open":
				match arg:
					"inventory": _open_inventory()
					"journal": _open_journal()
					"map": _open_map()
					"character": _open_character()
					"log": _open_log()
					"travel": _open_travel()
					"settings": _open_settings()
					"newgame": _open_new_game()
					"saves": _open_saves(true)
					"load": _open_saves(false)
					"credits": _open_credits()
					"menu": _open_pause()
					"content":
						if content_toggle != null and is_instance_valid(content_toggle):
							content_toggle.button_pressed = true
			_:
				_act(parts[0], arg)
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(shot_path)
	get_tree().quit()
