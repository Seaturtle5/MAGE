extends GutTest
## Places and shops: exits added by another pack, dangerous doors, visited and
## forgotten places, using an item from a scene, worn-item descriptors, event
## counters, collected people, travel events that replace the trip, and shops.

const ROOT := "user://places_test_packs"

const BASE := """== region city
name: City

== zone alleys
name: Alleys
ambient:
    Rats skitter in the alleys.

== location street
name: Street
description: A street.
region: city
zone: none
map: 1, 1
flags: fast travel, known at start
exits:
    north: plaza
    west: door alley_door

== location plaza
name: Plaza
description: A plaza.
region: city
map: 1, 0
flags: fast travel
exits:
    south: street

== location shelter
name: Shelter
description: A shelter.
region: city
map: 2, 1
flags: fast travel, collected
exits:
    west: street, one way

== door alley_door
name: Back alleys
leads to zone: alleys
shown in room: Dark alleys open to the west.

== character mo
name: Mo
lives at: shelter

== character pat
name: Pat
lives at: street

== item coin
name: coin
category: other

== item boots
name: boots
category: clothing
equipment:
    slot: feet

== item tonic
name: tonic
category: drink
use:
    The tonic tastes of mint.
    ~ log.tonics + 1 quietly

== item fur
name: fur
category: other
trades for: coin

== item gem
name: gem
category: other

== values log
values:
    tonics: number
    bought: text

== event signpost
name: Signpost
found by: nowhere
play:
    ~ signpost.resolution + 1 quietly
    The sign creaks [signpost.resolution] times.

== event roadblock
name: Roadblock
found by: travelling to plaza
replaces trip: yes
repeat: always
play:
    A roadblock stops you before you get there.

== scene sip
You uncork the tonic.
~ use tonic
You feel refreshed.

== scene dress
Your [worn feet] squeak. [if player is barefoot]Bare.[end if]

== values player
values:
    freecred: number 0

== shop stall
name: Market stall
at: street
run by: pat
currency: freecred
stock:
    tonic: 3
    boots: 50
    gem: 1 [if log.tonics > 5]
buys:
    gem: 4
trades: yes
trade bonus when: log.tonics > 0
trade bonus chance: 1 in 1
intro:
    Pat waves you over.
closed:
    The stall is shuttered.
bought:
    Pat hands over the [shop.item] for [shop.price].

== shop barter
name: Barter table
at: plaza
currency: item coin
stock:
    gem: 2
"""

const ADDON := """== location garden
name: Garden
description: A garden.
region: city
map: 1, 2
exits:
    north: street

== extend location street
exits:
    south: garden
"""

var game: Game


func _write(dir: String, files: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for name: String in files:
		var fa := FileAccess.open(dir + "/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()


func _load(base: String, addon: String) -> ContentDB:
	_write(ROOT + "/base", {"pack.fsc": "== pack base\nname: Base\n", "city.fsc": base})
	_write(ROOT + "/addon", {"pack.fsc": "== pack addon\nname: Addon\nrequires: base\n", "garden.fsc": addon})
	var db := ContentDB.new()
	db.load_folders([ROOT])
	return db


func before_each() -> void:
	var db := _load(BASE, ADDON)
	assert_eq(db.errors(), [], "the packs load without errors")
	game = Game.new(db, 1)
	game.start("street")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func test_another_pack_adds_an_exit() -> void:
	assert_true(game.runner.act("go", "south"), "the extended exit works")
	assert_eq(game.state.location, "garden")
	var db := _load(BASE, "== extend location street\nexits:\n    north: plaza\n")
	assert_string_contains(str(db.errors()), "already has an exit north")


func test_a_dangerous_door_explores_its_zone() -> void:
	assert_eq(game.zone_here(), "alleys", "the door's zone is this place's exploring ground")
	assert_true(game.adjective("here", "explorable"))
	assert_true(game.runner.act("go", "west"))
	assert_eq(game.state.location, "street", "going through explores instead of moving")
	assert_string_contains(_text(), "Rats skitter")
	game.set_value("player.hp", 0)
	game.runner.act("go", "west")
	assert_string_contains(str(game.take_output()), "too injured to go far")


func test_visited_and_forgotten_places() -> void:
	assert_true(Condition.evaluate(Condition.compile("player has visited street"), game))
	assert_true(Condition.evaluate(Condition.compile("player has not visited plaza"), game))
	game.apply(Effect.compile("discover plaza"))
	assert_true(Condition.evaluate(Condition.compile("player knows plaza"), game))
	assert_true(Condition.evaluate(Condition.compile("player has not visited plaza"), game), "known is not visited")
	game.apply(Effect.compile("forget plaza"))
	assert_false(Condition.evaluate(Condition.compile("player knows plaza"), game))


func test_a_scene_uses_an_item() -> void:
	game.apply(Effect.compile("give tonic 2"))
	game.runner.start("sip")
	var text := _text()
	assert_string_contains(text, "You uncork the tonic.\nThe tonic tastes of mint.\nYou feel refreshed.")
	assert_eq(int(game.value("log.tonics")), 1)
	assert_eq(int(game.state.inventory.get("tonic", 0)), 1, "one is used up")


func test_worn_item_descriptor() -> void:
	game.runner.start("dress")
	assert_string_contains(_text(), "Your  squeak. Bare.")
	game.apply(Effect.compile("give boots"))
	ItemSystem.wear(game, "boots")
	game.runner.start("dress")
	assert_string_contains(_text(), "Your boots squeak.")


func test_an_event_counts_with_its_resolution() -> void:
	game.runner.start_event("signpost")
	game.runner.start_event("signpost")
	assert_string_contains(_text(), "The sign creaks 2 times.")
	assert_true(Condition.evaluate(Condition.compile("signpost.resolution = 2"), game))


func test_collected_people() -> void:
	assert_eq(int(game.value("people.collected")), 1, "Mo is in a collected place")
	game.apply(Effect.compile("mo lives at street"))
	game.apply(Effect.compile("move mo to street"))
	assert_eq(int(game.value("people.collected")), 0)


func test_an_event_replaces_the_trip() -> void:
	game.apply(Effect.compile("discover plaza"))
	var turn: int = game.state.turn
	assert_true(game.runner.act("travel", "plaza"))
	assert_string_contains(_text(), "A roadblock stops you")
	assert_eq(game.state.location, "street", "the player stays")
	assert_eq(game.state.turn, turn, "no trip, no time")


func _shop_options() -> Array:
	var out: Array = []
	for e in game.take_output():
		if e.type == "choices":
			out = e.options.map(func(o): return [o.text, o.enabled])
	return out


func test_shop_buys_sells_and_trades() -> void:
	game.set_value("player.freecred", 10)
	assert_true(game.runner.act("shop", "stall"))
	var opts := _shop_options()
	assert_eq(opts[0], ["Buy tonic - 3 freecred", true])
	assert_eq(opts[1], ["Buy boots - 50 freecred", false], "too expensive: shown but not offered")
	assert_eq(opts.size(), 3, "no gem for sale yet, nothing to sell or trade, Leave")
	game.runner.choose(0)
	assert_eq(int(game.state.inventory.get("tonic", 0)), 1)
	assert_eq(int(game.value("player.freecred")), 7)
	assert_string_contains(str(game.output.map(func(e): return TextTemplate.plain(e.get("spans", [])))), "Pat hands over the tonic for 3.", "the bought script knows the item")
	game.apply(Effect.compile("give gem"))
	game.apply(Effect.compile("give fur"))
	game.apply(Effect.compile("log.tonics = 1"))
	game.runner.choose(game.runner.pending.size() - 1)
	game.runner.act("shop", "stall")
	opts = _shop_options()
	var labels := opts.map(func(o): return o[0])
	assert_has(labels, "Sell gem - 4 freecred")
	assert_has(labels, "Trade fur for coin")
	game.runner.choose(labels.find("Sell gem - 4 freecred"))
	assert_eq(int(game.value("player.freecred")), 11)
	labels = _shop_options().map(func(o): return o[0])
	game.runner.choose(labels.find("Trade fur for coin"))
	assert_eq(int(game.state.inventory.get("coin", 0)), 2, "a trade, plus the bonus")


func test_a_shop_closes_without_its_keeper_and_pays_in_items() -> void:
	game.apply(Effect.compile("move pat to plaza"))
	game.take_output()
	assert_true(game.runner.act("shop", "stall"))
	assert_string_contains(_text(), "The stall is shuttered.")
	game.go_to("plaza")
	game.take_output()
	game.apply(Effect.compile("give coin 3"))
	game.runner.act("shop", "barter")
	var opts := _shop_options()
	assert_eq(opts[0], ["Buy gem - 2 coin", true])
	game.runner.choose(0)
	assert_eq(int(game.state.inventory.get("coin", 0)), 1)
	assert_eq(int(game.state.inventory.get("gem", 0)), 1)


func test_places_and_shops_are_validated() -> void:
	var bad := """== location a
name: A
exits:
    north: door plain

== door plain
name: Plain door

== door pit
name: Pit
leads to zone: nowhere_zone

== shop s
name: S
at: nowhere_place
run by: nobody
currency: item nothing
trades: maybe
trade bonus chance: often
stock:
    ghost_item: 5
    junk
buys:
    a: x

== event e
found by: walking into a
replaces trip: yes

== scene sc
~ use ghost
~ forget nowhere_place
[worn hat, tail]
if player has visited nowhere_place:
    Hm.
"""
	_write(ROOT + "_bad/p", {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "bad.fsc": bad})
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	for part in ["needs a dangerous door", "nowhere_zone", "nowhere_place", "nobody", "nothing", "Trades must be",
			"N in M", "ghost_item", "item_id: price", "travelling to", "ghost", "tail"]:
		assert_string_contains(text, part)
