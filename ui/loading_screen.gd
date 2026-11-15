class_name LoadingScreen
extends Control
## Shown while the content packs load. The game pack may name a `loading:`
## picture: a sprite sheet of `loading frames:` frames side by side (white
## shapes on a transparent background), played as a loop in the accent colour
## and held a moment on its last frame. Without one only the line shows.

const FPS := 6.0
const HOLD := 5  ## extra steps the last frame stays before the loop starts again

var _frames: Array[AtlasTexture] = []
var _picture: TextureRect
var _label: Label
var _time := 0.0


func setup(sheet: Texture2D, frames: int) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = FsTheme.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	if sheet != null and frames > 0:
		var w := float(sheet.get_width()) / frames
		for i in frames:
			var a := AtlasTexture.new()
			a.atlas = sheet
			a.region = Rect2(i * w, 0, w, sheet.get_height())
			_frames.append(a)
		_picture = TextureRect.new()
		_picture.texture = _frames[0]
		_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_picture.custom_minimum_size = Vector2(240, 240 * sheet.get_height() / w)
		_picture.modulate = FsTheme.ACCENT
		box.add_child(_picture)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", FsTheme.TEXT)
	_label.custom_minimum_size = Vector2(240, 0)
	box.add_child(_label)
	_process(0.0)


func _process(delta: float) -> void:
	_time += delta
	if not _frames.is_empty():
		var step := int(_time * FPS) % (_frames.size() + HOLD)
		_picture.texture = _frames[mini(step, _frames.size() - 1)]
	_label.text = "Loading" + ".".repeat(int(_time * 2.0) % 4)
