extends GutTest
## Maps laid out from exits: groups (a place's region, the nearest region along
## its exits, its connected places' zone, or the rest), positions from compass
## exits with hand-set ones winning, blocks joined by up/down/inside/outside set
## off to the side, separate parts packed apart, no two places in one cell, the
## same map every time, and the overview of known areas.

const ROOT := "user://map_layout_test_packs"

const PACK := """== region town
name: Town
travel order: 1

== region docks
name: Docks
travel order: 2

== zone forest
name: Forest

== location square
name: Square
region: town
map: 5, 5
flags: fast travel
exits:
    north: hall
    east: market
    south: cellar_door

== location hall
name: Hall
exits:
    south: square
    up: attic
    east: tower

== location attic
name: Attic
exits:
    down: hall

== location market
name: Market
exits:
    west: square
    north: tower
    southwest: kiosk

== location tower
name: Tower
exits:
    south: market
    west: hall

== location cellar_door
name: Cellar Door
exits:
    north: square

== location kiosk
name: Kiosk
exits:
    northeast: market

== location pier
name: Pier
region: docks
flags: fast travel
exits:
    inside: boat

== location boat
name: Boat
exits:
    outside: pier

== location warehouse
name: Warehouse
region: docks

== location clearing
name: Clearing
zone: forest
exits:
    east: thicket

== location thicket
name: Thicket
zone: none
exits:
    west: clearing

== location lonely
name: Lonely Place
zone: none
"""

var game: Game


func before_each() -> void:
	game = Game.new(_load({"pack.fsc": "== pack p\nname: Test\n", "main.fsc": PACK, "values.fsc": TestPlayerValues.TEXT}), 3)
	game.start("square")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _load(files: Dictionary) -> ContentDB:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	for f in DirAccess.get_files_at(ROOT + "/p"):
		DirAccess.remove_absolute(ROOT + "/p/" + f)
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	return db


func _at(id: String) -> Vector2i:
	return game.content.map_layout().position[id]


func test_groups_follow_regions_then_exits_then_zones() -> void:
	assert_eq(game.content.errors(), [], "the pack loads without errors")
	var layout := game.content.map_layout()
	assert_eq(layout.group.square, "town", "its own region")
	assert_eq(layout.group.hall, "town", "the nearest region along its exits")
	assert_eq(layout.group.attic, "town", "two steps away, through up")
	assert_eq(layout.group.boat, "docks")
	assert_eq(layout.group.warehouse, "docks", "its own region, without exits")
	assert_eq(layout.group.clearing, "zone:forest", "no region anywhere near: the connected places' zone")
	assert_eq(layout.group.thicket, "zone:forest", "a zoneless place joins its neighbour's zone")
	assert_eq(layout.group.lonely, "zone:", "the rest")
	assert_eq(game.map_group_name("zone:forest"), "Forest")
	assert_eq(game.map_group_name("zone:"), "")


func test_positions_come_from_exits_and_hand_set_ones_win() -> void:
	assert_eq(_at("square"), Vector2i(5, 5), "hand-set")
	assert_eq(_at("hall"), Vector2i(5, 4), "north is up")
	assert_eq(_at("market"), Vector2i(6, 5), "east is right")
	assert_eq(_at("tower"), Vector2i(6, 4), "reached two ways, the same cell")
	assert_eq(_at("cellar_door"), Vector2i(5, 6))
	assert_eq(_at("attic"), Vector2i(6, 3), "up: a step up and to the right")
	assert_eq(_at("boat") - _at("pier"), Vector2i(1, 1), "inside: a step down and to the right")
	assert_true(_at("warehouse").x >= _at("boat").x + 2, "a separate part is packed beside the others")
	assert_eq(_at("thicket") - _at("clearing"), Vector2i(1, 0))


func test_no_two_places_share_a_cell_and_the_map_is_the_same_every_time() -> void:
	var layout := game.content.map_layout()
	var seen := {}
	for id: String in layout.position:
		var key := "%s:%s" % [layout.group[id], layout.position[id]]
		assert_false(seen.has(key), "%s and %s share a cell" % [id, seen.get(key, "")])
		seen[key] = id
	assert_ne(_at("kiosk"), _at("cellar_door"), "a clash is moved to a free cell")
	var again := MapLayout.build(game.content)
	assert_eq(again.position, layout.position, "the same content gives the same map")
	assert_eq(again.group, layout.group)
	assert_eq(game.content.map_layout(), layout, "worked out once and kept")


func test_map_data_and_overview() -> void:
	var data := game.map_data()
	assert_eq(data.region, "town", "the player's own group by default")
	assert_eq(data.name, "Town")
	var ids: Array = data.places.map(func(p: Dictionary) -> String: return p.id)
	ids.sort()
	assert_eq(ids, ["attic", "cellar_door", "hall", "kiosk", "market", "square", "tower"], "every place of the group, laid out")
	var groups := game.map_groups()
	assert_eq(groups.map(func(g: Dictionary) -> String: return g.id), ["town"], "only areas with a known place")
	assert_true(groups[0].current)
	game.state.known["clearing"] = true
	game.state.known["pier"] = true
	game.state.known["lonely"] = true
	groups = game.map_groups()
	assert_eq(groups.map(func(g: Dictionary) -> String: return g.id), ["town", "docks", "zone:forest", "zone:"],
		"regions in travel order, then zones, then the rest")
	assert_eq(groups[1].known, 1)
	assert_eq(groups[1].places, 3)
	assert_eq(groups[1].fast_travel, 1)
	assert_eq(game.map_data("docks").places.size(), 3)


func test_a_bent_way_back_is_reported() -> void:
	var db := _load({"pack.fsc": "== pack p\nname: Test\n", "values.fsc": TestPlayerValues.TEXT,
		"w.fsc": "== location a\nname: A\nexits:\n    west: b\n\n== location b\nname: B\nexits:\n    west: a\n\n== location c\nname: C\nexits:\n    up: d\n\n== location d\nname: D\nexits:\n    west: c\n"})
	var warnings: Array = []
	for d in db.diagnostics:
		if d.severity == "warning":
			warnings.append("%s %d %s" % [str(d.path).get_file(), d.line, d.message])
	var bent := warnings.filter(func(w: String) -> bool: return "map bends" in w)
	assert_eq(bent.size(), 1, str(warnings))
	assert_true("w.fsc 4 Exit west leads to b, but its way back is west" in str(bent), str(bent))
