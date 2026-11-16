extends GutTest
## Storage (stashing items in a place and taking them back) and collections
## (things owned by name, with their list, effects and values), plus the
## `infection` hook moment and the fought creature's values.

const ROOT := "user://storage_test_packs"

const PACK := """== location shed
name: Shed
description: A shed.
flags: fast travel, known at start
exits:
    east: yard

== location yard
name: Yard
description: A yard.
flags: fast travel
exits:
    west: shed

== storage shed_bin
name: Bin
at: shed
description: A tin bin for your things.
stash: You drop [storage.item_name] in the bin.
stash all: You drop [storage.count] of [storage.item_name] in the bin.
retrieve: You fish [storage.item_name] out of the bin.
stash everything: [if storage.count = 0]Nothing to store[else]You store [storage.count] things ([storage.kinds] kinds)[end if].
retrieve everything: You empty the bin of [storage.count] things.
kept: Keep that.
in use: You're using that.

== item stone
name: stone
weight: 2

== item diary
name: diary
keep: yes

== item cap
name: cap
equipment:
    slot: head

== form wisp
name: Wisp
tail:
    description: a wispy tail
    change: a wispy tail grows

== creature wisp
name: Wisp
found in: nowhere
form: wisp
level: 2
hp: 1
damage: 1

== creature tame_wisp
name: Tame wisp
found in: nowhere
form: wisp
infectious: no

== form shade
name: Shade
tail:
    description: a shady tail
    change: a shady tail grows

== creature shade
name: Shade
found in: nowhere
form: shade
research bypass: yes

== values infection
values:
    bypass: flag

== values lab
values:
    seen: text
    hits: number 0
    drinking: flag

== hook lab_sample
on: infection
when: not infection.bypass and not lab.drinking
do:
    ~ lab.seen = infection.creature quietly
    ~ lab.hits + 1 quietly
    ~ collect infection.creature in jars

== collection jars
name: Jars
of: creature
title: Your jars:
empty: Your jar shelf is empty.
label: [collection.name] x[collection.count]
leave: Done
gained: You bottle some [collection.name].
lost: You lose [collection.amount] [collection.name] jar[if collection.amount > 1]s[end if].
entry:
    * Drink it [then leave]
        Down it goes.
        ~ discard collection.entry from jars
        ~ lab.drinking = yes quietly
        ~ infect collection.entry
        ~ lab.drinking = no quietly
    * Smash all [then leave]
        ~ discard all of collection.entry from jars
options:
    * Clear the shelf [then leave]
        ~ discard everything from jars

== collection songs
name: Songs
gained: You learn [collection.name].

== scene shelf
-> jars

== scene learn
~ collect "Old Road" in songs
~ collect 2 of "Old Road" in songs quietly
Songs: [collection.songs.total], kinds [collection.songs.kinds], wisp jars [collection.jars.wisp].
"""

var game: Game
var db: ContentDB


func _write(dir: String, files: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for name: String in files:
		var fa := FileAccess.open(dir + "/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()


func before_each() -> void:
	_write(ROOT + "/p", {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "all.fsc": PACK})
	db = ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("shed")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func _choices() -> Array:
	var out: Array = []
	for e in game.take_output():
		if e.type == "choices":
			out = e.options.map(func(o): return o.text)
	return out


# --- Storage -------------------------------------------------------------------

func test_the_storage_is_offered_where_it_is() -> void:
	game.runner.show_location()
	var view: Dictionary = game.take_output().filter(func(e): return e.type == "location")[0]
	assert_true(view.actions.any(func(a): return a.id == "storage" and a.arg == "shed_bin" and a.label == "Bin"))
	game.state.location = "yard"
	assert_eq(StorageSystem.here(game), [], "not in the yard")
	assert_false(game.runner.act("stash_everything", "shed_bin"), "only where it is")


func test_stash_and_retrieve() -> void:
	game.apply(Effect.compile("give stone 3"))
	assert_true(game.runner.act("stash", "shed_bin:stone"))
	assert_string_contains(_text(), "You drop stone in the bin.")
	assert_eq(ItemSystem.count(game, "stone"), 2)
	assert_eq(StorageSystem.stored(game, "shed_bin", "stone"), 1)
	assert_false(Condition.evaluate(Condition.compile("player has stone 3"), game), "stored items are not carried")
	assert_true(game.runner.act("stash_all", "shed_bin:stone"))
	assert_string_contains(_text(), "You drop 2 of stone in the bin.")
	assert_eq(ItemSystem.count(game, "stone"), 0)
	assert_eq(int(game.value("player.carried_weight")), 0, "stored items weigh nothing")
	assert_true(game.runner.act("retrieve", "shed_bin:stone"))
	assert_string_contains(_text(), "You fish stone out of the bin.")
	assert_eq(StorageSystem.list(game, "shed_bin"), [{"id": "stone", "name": "stone", "count": 2}])
	assert_false(game.runner.act("retrieve", "shed_bin:diary"), "nothing of it stored")


func test_kept_and_used_items_stay_with_the_player() -> void:
	game.apply(Effect.compile("give diary"))
	game.apply(Effect.compile("give cap"))
	game.apply(Effect.compile("give stone 2"))
	game.apply(Effect.compile("wear cap"))
	game.take_output()
	assert_false(game.runner.act("stash", "shed_bin:diary"))
	assert_string_contains(str(game.take_output()), "Keep that.")
	assert_false(game.runner.act("stash_all", "shed_bin:cap"))
	assert_eq(game.take_output().map(func(e): return e.get("text", "")), ["You're using that."])
	assert_true(game.runner.act("stash_everything", "shed_bin"))
	assert_string_contains(_text(), "You store 2 things (1 kinds).")
	assert_eq(ItemSystem.count(game, "diary"), 1)
	assert_eq(ItemSystem.count(game, "cap"), 1)
	game.runner.act("stash_everything", "shed_bin")
	assert_string_contains(_text(), "Nothing to store.")
	assert_true(game.runner.act("retrieve_everything", "shed_bin"))
	assert_string_contains(_text(), "You empty the bin of 2 things.")
	assert_eq(ItemSystem.count(game, "stone"), 2)


func test_stored_items_are_saved() -> void:
	game.apply(Effect.compile("give stone 2"))
	game.runner.act("stash_all", "shed_bin:stone")
	game.apply(Effect.compile("collect wisp in jars quietly"))
	var data: Dictionary = JSON.parse_string(JSON.stringify(game.save_dict()))
	var other := Game.new(db, 3)
	assert_true(other.load_dict(data))
	assert_eq(StorageSystem.stored(other, "shed_bin", "stone"), 2)
	assert_eq(CollectionSystem.count(other, "jars", "wisp"), 1)
	other.dispose()


# --- Collections -----------------------------------------------------------------

func test_collect_and_discard_with_texts_and_values() -> void:
	game.runner.start("learn")
	assert_string_contains(_text(), "You learn Old Road.\nSongs: 3, kinds 1, wisp jars 0.")
	game.apply(Effect.compile("collect 3 of wisp in jars"))
	assert_string_contains(_text(), "You bottle some Wisp.")
	game.apply(Effect.compile("discard 2 of wisp from jars"))
	assert_string_contains(_text(), "You lose 2 Wisp jars.")
	assert_eq(int(game.value("collection.had")), 3)
	assert_eq(int(game.value("collection.count")), 1)
	game.apply(Effect.compile("discard all of wisp from jars"))
	assert_string_contains(_text(), "You lose 1 Wisp jar.")
	assert_eq(int(game.value("collection.jars.wisp")), 0)


func test_the_list_and_its_entry_menu() -> void:
	game.runner.start("shelf")
	assert_string_contains(_text(), "Your jar shelf is empty.", "an empty collection says so and closes")
	assert_eq(game.runner.status, "idle")
	game.apply(Effect.compile("collect 2 of wisp in jars quietly"))
	game.apply(Effect.compile("collect shade in jars quietly"))
	game.runner.start("shelf")
	assert_eq(_choices(), ["Shade x1", "Wisp x2", "Clear the shelf", "Done"], "sorted by name, then the options")
	game.runner.choose(1)
	assert_eq(_choices(), ["Drink it", "Smash all", "Leave"], "the picked entry's menu")
	game.runner.choose(0)
	var text := _text()
	assert_string_contains(text, "Down it goes.")
	assert_eq(game.part_form("player", "tail"), "wisp", "drinking infects with the creature's strain")
	assert_eq(CollectionSystem.count(game, "jars", "wisp"), 1)
	game.runner.choose(1)
	game.runner.choose(1)
	game.take_output()
	assert_eq(CollectionSystem.count(game, "jars", "wisp"), 0)
	game.runner.choose(0)
	game.runner.choose(1)
	assert_eq(game.runner.status, "idle", "the emptied collection closes without a word")
	assert_false(_text().contains("empty"))


func test_the_infection_hook_names_the_creature() -> void:
	game.apply(Effect.compile("infect wisp"))
	assert_eq(str(game.value("lab.seen")), "wisp")
	assert_eq(CollectionSystem.count(game, "jars", "wisp"), 1, "the hook played at once")
	game.apply(Effect.compile("infect shade"))
	assert_eq(int(game.value("lab.hits")), 1, "not for a creature with research bypass (this hook's condition)")
	game.apply(Effect.compile("transform into shade"))
	assert_eq(int(game.value("lab.hits")), 1, "a transformation is not an infection")


func test_the_fought_creature_values() -> void:
	CombatSystem.begin(game, "wisp")
	assert_eq(str(game.value("enemy.id")), "wisp")
	assert_true(game.value("enemy.infectious"))
	assert_false(game.value("enemy.research_bypass"))
	game.state.combat = {}
	CombatSystem.begin(game, "tame_wisp")
	assert_false(game.value("enemy.infectious"))


func test_collections_are_validated() -> void:
	var bad := """== collection count
of: thing
gained: [if]

== collection jars2
of: creature

== scene sc
~ collect ghost in jars2
~ collect wisp in nowhere_jars
~ discard x.unknown from jars2
[collection.jars2.ghost] [collection.cows.x] [collection.what]
-> jars2

== storage box
open when: player is happy
stash: [if]
"""
	_write(ROOT + "_bad/p", {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "bad.fsc": bad})
	var bad_db := ContentDB.new()
	bad_db.load_folders([ROOT + "_bad"])
	var text := "\n".join(bad_db.errors().map(func(e): return str(e.message)))
	for part in ["can't be called 'count'", "'of:' is creature", "'ghost'", "nowhere_jars", "x.unknown", "'cows'",
			"collection.what", "needs 'at:'", "happy"]:
		assert_string_contains(text, part)
