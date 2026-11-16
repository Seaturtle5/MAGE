class_name MapLayout
extends RefCounted
## Where every location sits on the map, worked out once from the content.
##
## **Groups.** A map shows one group of places at a time: a place's `region:`;
## else the region of the nearest place with one, following exits; else, for
## a set of connected places without any region, their most common zone
## ("zone:<id>"); else the group of the rest, "zone:".
##
## **Positions.** A hand-set `map: x, y` always wins. Other places are laid
## out from their exits on a grid: north is up, east right, and the diagonals
## between. Places joined by compass exits form a block; `up`, `down`,
## `inside`, `outside` (and any other named way) join blocks, which are set
## a step off to the side (up: up-right, down: down-left, inside: down-right,
## outside: up-left) and pushed further that way until they overlap nothing.
## A block without a hand-set place starts from its fast-travel point (or its
## first place by ID). Sets of connected places not joined to the rest are
## packed in rows below it. Doors and one-way exits count as connections, and
## so do the exits scenes make in play (`~ change north exit of A to B`, read
## from every script; set off to the side when A already has a written exit
## that way). Places behind a dangerous door (`north: door skyscrapers`, which
## leads into a zone) that no exit joins to a region belong to the region of the
## places with doors into their zone. Places flagged `off map` (holding rooms)
## are left out. Everything is visited in a fixed order, so the same content
## always gives the same map.

const STEPS := {"north": Vector2i(0, -1), "south": Vector2i(0, 1), "east": Vector2i(1, 0), "west": Vector2i(-1, 0),
	"northeast": Vector2i(1, -1), "northwest": Vector2i(-1, -1), "southeast": Vector2i(1, 1), "southwest": Vector2i(-1, 1)}
const SIDE_STEPS := {"up": Vector2i(1, -1), "down": Vector2i(-1, 1), "inside": Vector2i(1, 1), "outside": Vector2i(-1, -1)}
## Any other way out ("in", "through the portal") is set off down-right.
const OTHER_STEP := Vector2i(1, 1)
## Empty cells between sets of places packed side by side.
const GAP := 2

var group: Dictionary = {}  ## location -> group key
var position: Dictionary = {}  ## location -> Vector2i
var members: Dictionary = {}  ## group key -> [locations], sorted

var _db: ContentDB
var _links: Dictionary = {}  ## location -> [[other, step: Vector2i, compass: bool]]
var _door_into: Dictionary = {}  ## zone -> [places with a dangerous door into it], sorted


static func build(db: ContentDB) -> MapLayout:
	var m := MapLayout.new()
	m._db = db
	m._collect_links()
	m._assign_groups()
	for key: String in m.members:
		m._lay_out_group(m.members[key])
	m._db = null
	return m


## A place's hand-set position, or null.
static func hand_set(db: ContentDB, id: String) -> Variant:
	var parts := db.typed_value("location", id, "map").split(",")
	if parts.size() != 2 or not parts[0].strip_edges().is_valid_int() or not parts[1].strip_edges().is_valid_int():
		return null
	return Vector2i(int(parts[0]), int(parts[1]))


## The step on the map for leaving by `direction`, and whether it is a compass step.
static func step_of(direction: String) -> Array:
	if STEPS.has(direction):
		return [STEPS[direction], true]
	return [SIDE_STEPS.get(direction, OTHER_STEP), false]


## The places a location's written exits lead to, as [direction, place] pairs
## (doors included; a dangerous door alone leads nowhere on the map).
static func written_exits(db: ContentDB, id: String) -> Array:
	var out: Array = []
	var d := db.get_def("location", id)
	if d == null or not d.fields.has("exits"):
		return out
	var f: FscParser.Field = d.fields.exits
	for l: FscParser.Line in f.children:
		if l.is_blank() or ":" not in l.text:
			continue
		var parts := l.text.split(":", true, 1)
		var to := parts[1].split(",")[0].strip_edges()
		if to.begins_with("door ") or to == id or not db.has(to, "location"):
			continue
		out.append([parts[0].strip_edges(), to])
	return out


## Exits scenes make in play, from every script: [direction, from, to] for each
## `~ change <direction> exit of <from> to <to>` (not `to nothing`), sorted.
static func changed_exits(db: ContentDB) -> Array:
	var re := RegEx.create_from_string("~\\s*change (\\w+) exit of (\\w+) to (\\w+)")
	var found := {}
	var scan := func(lines: Array) -> void:
		for l: FscParser.Line in lines:
			if "exit of" not in l.text:
				continue
			var m := re.search(l.text)
			if m != null and m.get_string(3) != "nothing":
				found["%s %s %s" % [m.get_string(1), m.get_string(2), m.get_string(3)]] = true
	for type: String in db.definitions:
		for id: String in db.definitions[type]:
			var d: FscParser.Definition = db.definitions[type][id]
			scan.call(d.body)
			for f: FscParser.Field in d.fields.values():
				scan.call(f.children)
	for key: String in db.extra_scripts:
		for extra: Dictionary in db.extra_scripts[key]:
			scan.call((extra.field as FscParser.Field).children)
	var out: Array = []
	for key: String in _sorted(found.keys()):
		out.append(Array(key.split(" ")))
	return out


func _collect_links() -> void:
	for id: String in _sorted(_db.all_of("location").keys()):
		if "off map" not in _db.list_field(id, "flags"):
			_links[id] = []
	for id: String in _sorted(_links.keys()):
		for pair: Array in written_exits(_db, id):
			if _links.has(pair[1]):
				_link(id, pair[1], step_of(pair[0]))
		# A dangerous door leads into a zone, not a place.
		var d := _db.get_def("location", id)
		if d == null or not d.fields.has("exits"):
			continue
		for l: FscParser.Line in (d.fields["exits"] as FscParser.Field).children:
			var to := l.text.split(":", true, 1)[1].split(",")[0].strip_edges() if ":" in l.text else ""
			var zone := _db.typed_value("door", to.substr(5).strip_edges(), "leads to zone") if to.begins_with("door ") else ""
			if zone != "" and id not in _door_into.get(zone, []):
				_door_into[zone] = _door_into.get(zone, []) + [id]
	for triple: Array in changed_exits(_db):
		var from: String = triple[1]
		var to: String = triple[2]
		if from == to or not _links.has(from) or not _links.has(to) or _links[from].any(func(k: Array) -> bool: return k[0] == to):
			continue
		var written := written_exits(_db, from).any(func(pair: Array) -> bool: return pair[0] == triple[0])
		_link(from, to, [OTHER_STEP, false] if written else step_of(triple[0]))


func _link(from: String, to: String, s: Array) -> void:
	_links[from].append([to, s[0], s[1]])
	_links[to].append([from, -s[0], s[1]])


func _assign_groups() -> void:
	var ids: Array = _sorted(_links.keys())
	var queue: Array = []
	for id: String in ids:
		var region := _db.typed_value("location", id, "region")
		if region != "":
			group[id] = region
			queue.append(id)
	# The nearest place with a region, following exits either way.
	_spread(queue)
	# Places behind dangerous doors: the region most of the doors into their zone are in.
	var behind: Array = []
	for zone: String in _sorted(_door_into.keys()):
		var votes := {}
		for p: String in _door_into[zone]:
			if group.has(p):
				votes[group[p]] = int(votes.get(group[p], 0)) + 1
		var best := ""
		for g: String in _sorted(votes.keys()):
			if best == "" or int(votes[g]) > int(votes[best]):
				best = g
		if best == "":
			continue
		for id: String in ids:
			if not group.has(id) and _db.typed_value("location", id, "zone") == zone:
				group[id] = best
				behind.append(id)
	_spread(behind)
	# Connected places without any region share their most common zone.
	for id: String in ids:
		if group.has(id):
			continue
		var part := _connected(id, func(_x: String) -> bool: return true)
		var counts := {}
		for p: String in part:
			var zone := _db.typed_value("location", p, "zone")
			if zone != "" and zone != "none" and _db.has(zone, "zone"):
				counts[zone] = int(counts.get(zone, 0)) + 1
		var best := ""
		for zone: String in _sorted(counts.keys()):
			if best == "" or int(counts[zone]) > int(counts[best]):
				best = zone
		for p: String in part:
			group[p] = "zone:" + best
	for id: String in ids:
		if not members.has(group[id]):
			members[group[id]] = []
		members[group[id]].append(id)


## Gives the places joined to those in `queue` (breadth first) their group.
func _spread(queue: Array) -> void:
	var i := 0
	while i < queue.size():
		var u: String = queue[i]
		i += 1
		for link: Array in _links[u]:
			if not group.has(link[0]):
				group[link[0]] = group[u]
				queue.append(link[0])


## The places reachable from `start` over links whose other end passes `keep`, sorted.
func _connected(start: String, keep: Callable) -> Array:
	var seen := {start: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var u: String = stack.pop_back()
		for link: Array in _links[u]:
			if not seen.has(link[0]) and keep.call(link[0]):
				seen[link[0]] = true
				stack.append(link[0])
	return _sorted(seen.keys())


func _lay_out_group(places: Array) -> void:
	var key: String = group[places[0]]
	var inside := func(x: String) -> bool: return group[x] == key
	var done := {}
	var fixed: Array = []  ## parts with a hand-set place keep their positions
	var loose: Array = []
	for id: String in places:
		if done.has(id):
			continue
		var part := _connected(id, inside)
		for p: String in part:
			done[p] = true
		var cells := _lay_out_part(part)
		if part.any(func(p: String) -> bool: return hand_set(_db, p) != null):
			fixed.append(cells)
		else:
			loose.append(cells)
	var taken := {}
	var have_box := false
	var box := Rect2i()
	for cells: Dictionary in fixed:
		for p: String in cells:
			position[p] = cells[p]
			taken[cells[p]] = true
			box = Rect2i(cells[p], Vector2i.ONE) if not have_box else box.merge(Rect2i(cells[p], Vector2i.ONE))
			have_box = true
	# Larger sets first, packed in rows under the hand-set ones.
	loose.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.size() > b.size() if a.size() != b.size() else _sorted(a.keys())[0] < _sorted(b.keys())[0])
	var total := 0
	for cells: Dictionary in loose:
		total += cells.size()
	var row_width := maxi(12, int(ceil(sqrt(float(total)))) * 3)
	var origin := Vector2i(box.position.x, box.end.y + GAP) if have_box else Vector2i.ZERO
	var cursor := origin
	var row_height := 0
	for cells: Dictionary in loose:
		var b := _bounds(cells)
		if cursor.x > origin.x and cursor.x + b.size.x > origin.x + row_width:
			cursor = Vector2i(origin.x, cursor.y + row_height + GAP)
			row_height = 0
		var shift := cursor - b.position
		while cells.values().any(func(c: Vector2i) -> bool: return taken.has(c + shift)):
			shift.x += 1
		for p: String in cells:
			position[p] = cells[p] + shift
			taken[cells[p] + shift] = true
		cursor.x = b.position.x + shift.x + b.size.x + GAP
		row_height = maxi(row_height, b.size.y)


## Positions for one set of connected places: blocks joined by compass exits,
## set beside each other along the other ways out.
func _lay_out_part(part: Array) -> Dictionary:
	var in_part := {}
	for p: String in part:
		in_part[p] = true
	var block_of := {}  ## place -> block index
	var blocks: Array = []  ## [places]
	for id: String in part:
		if block_of.has(id):
			continue
		var block := _compass_block(id, in_part)
		for p: String in block:
			block_of[p] = blocks.size()
		blocks.append(block)
	var cells := {}  ## place -> cell
	var taken := {}  ## cell -> true
	var placed_blocks := {}
	var queue: Array = []
	# Blocks with hand-set places first, where they are.
	for b in blocks.size():
		var local := _lay_out_block(blocks[b])
		if blocks[b].any(func(p: String) -> bool: return hand_set(_db, p) != null):
			for p: String in local:
				cells[p] = local[p]
				taken[local[p]] = true
			placed_blocks[b] = local
			queue.append(b)
	if queue.is_empty():
		var start := _start_place(part)
		var b: int = block_of[start]
		var local := _lay_out_block(blocks[b])
		for p: String in local:
			cells[p] = local[p]
			taken[local[p]] = true
		placed_blocks[b] = local
		queue.append(b)
	var i := 0
	while i < queue.size():
		var b: int = queue[i]
		i += 1
		for p: String in blocks[b]:
			for link: Array in _links[p]:
				var other: String = link[0]
				if not in_part.has(other) or link[2] or placed_blocks.has(block_of[other]):
					continue
				var ob: int = block_of[other]
				var local := _lay_out_block(blocks[ob])
				var step: Vector2i = link[1]
				var shift: Vector2i = cells[p] + step - local[other]
				while local.values().any(func(c: Vector2i) -> bool: return taken.has(c + shift)):
					shift += step
				for q: String in local:
					cells[q] = local[q] + shift
					taken[local[q] + shift] = true
				placed_blocks[ob] = local
				queue.append(ob)
	return cells


## The places joined to `start` by compass exits within the set, sorted.
func _compass_block(start: String, in_part: Dictionary) -> Array:
	var seen := {start: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var u: String = stack.pop_back()
		for link: Array in _links[u]:
			if link[2] and in_part.has(link[0]) and not seen.has(link[0]):
				seen[link[0]] = true
				stack.append(link[0])
	return _sorted(seen.keys())


## Cells for a block of compass-joined places, from its hand-set places (in
## their own cells) or from its start place at 0, 0.
func _lay_out_block(block: Array) -> Dictionary:
	var in_block := {}
	for p: String in block:
		in_block[p] = true
	var cells := {}
	var taken := {}
	var queue: Array = []
	for p: String in block:
		var hand: Variant = hand_set(_db, p)
		if hand != null:
			cells[p] = hand
			taken[hand] = true
			queue.append(p)
	if queue.is_empty():
		var start := _start_place(block)
		cells[start] = Vector2i.ZERO
		taken[Vector2i.ZERO] = true
		queue.append(start)
	var i := 0
	while i < queue.size():
		var u: String = queue[i]
		i += 1
		for link: Array in _links[u]:
			var v: String = link[0]
			if not link[2] or not in_block.has(v) or cells.has(v):
				continue
			var cell := _free_near(cells[u] + link[1], link[1], taken)
			cells[v] = cell
			taken[cell] = true
			queue.append(v)
	return cells


## `want` if free; else the nearest free cell, preferring cells further along `step`.
static func _free_near(want: Vector2i, step: Vector2i, taken: Dictionary) -> Vector2i:
	if not taken.has(want):
		return want
	var r := 1
	while r < 10000:
		var best := Vector2i.ZERO
		var best_score := INF
		for y in range(want.y - r, want.y + r + 1):
			for x in range(want.x - r, want.x + r + 1):
				var c := Vector2i(x, y)
				if taken.has(c) or maxi(absi(x - want.x), absi(y - want.y)) != r:
					continue
				var d := Vector2(c - want)
				# Nearest first; then the one that keeps the way's direction.
				var score := d.length_squared() * 10.0 - d.dot(Vector2(step))
				if score < best_score:
					best_score = score
					best = c
		if best_score < INF:
			return best
		r += 1
	return want


## Where a set of places starts: its first fast-travel point, else its first place by ID.
func _start_place(places: Array) -> String:
	for p: String in places:
		if "fast travel" in _db.list_field(p, "flags"):
			return p
	return places[0]


static func _bounds(cells: Dictionary) -> Rect2i:
	var box := Rect2i()
	var first := true
	for c: Vector2i in cells.values():
		box = Rect2i(c, Vector2i.ONE) if first else box.merge(Rect2i(c, Vector2i.ONE))
		first = false
	return box


static func _sorted(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out
