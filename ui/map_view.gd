extends Control
## Draws a region map from location positions and exits.
##
## Known places are drawn with their names; places next to a known place
## are shown as unexplored ("?"); the rest stay hidden. The current place is
## highlighted, fast-travel points are diamonds and can be clicked.
## Names are placed where they cross the fewest paths, places and other
## names; a name that would still cover another is left out and shown when
## the pointer is over its place (the current place is always named). The
## compact map shows only the places near the player. Behind the map sits
## the region's image, if it has one, or a faint dot grid.

signal place_clicked(id: String)

## Label positions tried in order, as directions from the place.
const LABEL_SLOTS := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0),
	Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]

## How far from the player the compact map reaches, in map steps.
const NEAR := Vector2(3, 2)

var data: Dictionary = {}
var compact := false
var background: Texture2D  ## the region's image, if any
var current_point := Vector2.ZERO  ## where the player's place was last drawn
var _hit: Array = []  ## [Rect2, id]
var _names: Array = []  ## [centre, radius, name] of every drawn place, for tooltips


func _init() -> void:
	clip_contents = true


func _draw() -> void:
	_hit.clear()
	_names.clear()
	_draw_background()
	var by_id := {}
	var visible := _visible(by_id)
	if visible.is_empty():
		return
	var bounds := _span(visible, by_id)
	var minp: Vector2 = bounds.position
	var span: Vector2 = bounds.size
	var pad := _pad()
	var area := size - Vector2(pad, pad) * 2
	var scale_f := minf(area.x / span.x, area.y / span.y)
	scale_f = minf(scale_f, 90.0 if compact else 160.0)
	var offset := (size - span * scale_f) / 2.0
	var to_screen := func(p: Dictionary) -> Vector2:
		return offset + (Vector2(p.x, p.y) - minp) * scale_f
	for id in visible:
		if by_id[id].current:
			current_point = to_screen.call(by_id[id])
	var font := get_theme_default_font()
	# Paths need more contrast over a region picture.
	var line_col := Color(FsTheme.TEXT_DIM, 0.7) if background != null else Color(FsTheme.BORDER, 1.0)
	var segments: Array = []  ## [a, b] of every drawn path, to keep names off them
	for id in visible:
		var p: Dictionary = by_id[id]
		if visible[id] != "known":
			continue
		for x in p.exits:
			if visible.has(x):
				var dashed: bool = visible[x] != "known"
				var a: Vector2 = to_screen.call(p)
				var b: Vector2 = to_screen.call(by_id[x])
				segments.append([a, b])
				if dashed:
					draw_dashed_line(a, b, line_col, 2.0, 6.0)
				else:
					draw_line(a, b, line_col, 3.0, true)
	var r := 7.0 if compact else 11.0
	var dots: Array = []  ## [centre, radius] of every place
	for id in visible:
		dots.append([to_screen.call(by_id[id]), r + 4.0])
	var labels: Array = []  ## rectangles of names already placed
	# The current place is named first so it gets the best spot.
	var order: Array = visible.keys()
	order.sort_custom(func(a, b): return by_id[a].current and not by_id[b].current)
	for id in order:
		var p: Dictionary = by_id[id]
		var c: Vector2 = to_screen.call(p)
		if visible[id] == "unexplored":
			draw_circle(c, r, FsTheme.SURFACE_2)
			draw_arc(c, r, 0, TAU, 24, FsTheme.TEXT_FAINT, 1.5, true)
			draw_string(font, c + Vector2(-4, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FsTheme.TEXT_FAINT)
			continue
		var fill := FsTheme.ACCENT if p.current else FsTheme.SURFACE_3
		if p.fast_travel:
			var d := r * 1.35
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), fill)
			_hit.append([Rect2(c - Vector2(d, d), Vector2(d, d) * 2), p.id])
		else:
			draw_circle(c, r, fill)
		if p.current:
			draw_arc(c, r + 5, 0, TAU, 32, FsTheme.ACCENT, 2.0, true)
		var size_f := 12 if compact else 15
		var label_col := FsTheme.TEXT if p.current else FsTheme.TEXT_DIM
		var text_size := font.get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, size_f)
		_names.append([c, r + 4.0, p.name])
		var box := best_label_rect(c, r + (8.0 if p.current else 4.0), text_size, segments, dots, labels, Rect2(Vector2.ZERO, size))
		if not p.current and (labels.any(func(other: Rect2) -> bool: return box.grow(1).intersects(other))
				or dots.any(func(d: Array) -> bool: return d[0] != c and _rect_hits_circle(box, d[0], d[1] - 4.0))
				or not Rect2(Vector2.ZERO, size).encloses(box)):
			continue
		labels.append(box)
		# A soft plate keeps the name readable where it can't avoid a path.
		draw_rect(box.grow(2), Color(FsTheme.SURFACE, 0.72), true)
		draw_string(font, Vector2(box.position.x, box.position.y + font.get_ascent(size_f)), p.name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size_f, label_col)


## The rectangle for a name next to a place at `centre`, chosen from
## LABEL_SLOTS by the fewest crossings with paths, places, earlier names
## and the map's edge.
static func best_label_rect(centre: Vector2, gap: float, text_size: Vector2, segments: Array, dots: Array,
		labels: Array, bounds: Rect2) -> Rect2:
	var best := Rect2()
	var best_score := INF
	for i in LABEL_SLOTS.size():
		var dir: Vector2 = LABEL_SLOTS[i]
		var offset := Vector2(dir.x * (gap + text_size.x / 2.0), dir.y * (gap + text_size.y / 2.0))
		var rect := Rect2(centre + offset - text_size / 2.0, text_size)
		var score := i * 0.1
		for seg in segments:
			if _rect_hits_segment(rect.grow(2), seg[0], seg[1]):
				score += 10.0
		for d in dots:
			if _rect_hits_circle(rect, d[0], d[1]):
				score += 15.0
		for other: Rect2 in labels:
			if rect.grow(3).intersects(other):
				score += 20.0
		if not bounds.encloses(rect):
			score += 30.0
		if score < best_score:
			best_score = score
			best = rect
	return best


static func _rect_hits_segment(rect: Rect2, a: Vector2, b: Vector2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for k in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[k], corners[(k + 1) % 4]) != null:
			return true
	return false


static func _rect_hits_circle(rect: Rect2, c: Vector2, radius: float) -> bool:
	var nearest := c.clamp(rect.position, rect.end)
	return nearest.distance_to(c) < radius


## The places drawn: known ones by name, their neighbours as unexplored;
## fills `by_id`.
func _visible(by_id: Dictionary) -> Dictionary:
	var places: Array = data.get("places", [])
	for p in places:
		by_id[p.id] = p
	var visible := {}
	for p in places:
		if p.known:
			visible[p.id] = "known"
	for p in places:
		if p.known:
			for x in p.exits:
				if by_id.has(x) and not visible.has(x):
					visible[x] = "unexplored"
	if compact:
		_keep_near_current(visible, by_id)
	return visible


## The smallest and the spread of the drawn places' map positions.
static func _span(visible: Dictionary, by_id: Dictionary) -> Rect2:
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for id in visible:
		var v := Vector2(by_id[id].x, by_id[id].y)
		minp = minp.min(v)
		maxp = maxp.max(v)
	return Rect2(minp, (maxp - minp).max(Vector2(1, 1)))


func _pad() -> float:
	return 28.0 if compact else 70.0


## The size that draws the map at least `cell` pixels per map step, and at
## least `least`; a large map then scrolls instead of crowding.
func preferred_size(least: Vector2, cell: float) -> Vector2:
	var by_id := {}
	var visible := _visible(by_id)
	if visible.is_empty():
		return least
	var span := _span(visible, by_id).size
	return least.max(span * cell + Vector2(_pad(), _pad()) * 2)


## Keeps only places within a few steps of the current one (the compact map).
func _keep_near_current(visible: Dictionary, by_id: Dictionary) -> void:
	var here := Vector2.INF
	for id in visible:
		if by_id[id].current:
			here = Vector2(by_id[id].x, by_id[id].y)
	if here == Vector2.INF:
		return
	for id in visible.keys():
		var at := Vector2(by_id[id].x, by_id[id].y)
		if absf(at.x - here.x) > NEAR.x or absf(at.y - here.y) > NEAR.y:
			visible.erase(id)


func _get_tooltip(at_position: Vector2) -> String:
	for n: Array in _names:
		if at_position.distance_to(n[0]) <= n[1]:
			return str(n[2])
	return ""


func _draw_background() -> void:
	var area := Rect2(Vector2.ZERO, size)
	if background != null:
		# Cover the map, faded so places and names stay readable.
		var tex_size := background.get_size()
		var cover := maxf(size.x / tex_size.x, size.y / tex_size.y)
		var draw_size := tex_size * cover
		draw_texture_rect(background, Rect2((size - draw_size) / 2.0, draw_size), false, Color(1, 1, 1, 0.5))
		return
	var step := 24.0 if compact else 40.0
	var dot := Color(FsTheme.BORDER, 0.55)
	var y := step / 2.0
	while y < area.size.y:
		var x := step / 2.0
		while x < area.size.x:
			draw_circle(Vector2(x, y), 1.0, dot)
			x += step
		y += step


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for h in _hit:
			if h[0].grow(6).has_point(event.position):
				place_clicked.emit(h[1])
				return
