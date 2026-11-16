extends GutTest
## A moment raised in a scene for other packs' hooks (`~ moment`), scripts
## played for each companion in the party (with `~ level up companion` and the
## companion's numbers changed through `companion.*`), and taming every companion.

const ROOT := "user://moments_test_packs"

const BASE := """== location camp
name: Camp
description: A camp.
flags: fast travel, known at start

== values bag
values:
    names: list
    rate: number 5

== scene open_bag
~ clear bag.names
~ moment gifts
You get: [bag.names].

== character rex
name: Rex
lives at: camp
stats:
    level: 2
companion:
    tamed: yes

== character fido
name: Fido
lives at: camp
companion:
    tamed: no

== scene train
~ for each companion play train_one

== scene train_one
[companion.name] trains.
~ companion.xp + (companion.level * 2) * bag.rate quietly
~ level up companion
"""

const ADDON := """== item bone
name: bone

== hook addon_gift
on: gifts
do:
    ~ give bone quietly
    ~ add "bone" to bag.names
"""

var game: Game


func _write(dir: String, files: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for name: String in files:
		var fa := FileAccess.open(dir + "/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()


func _load(addon: String) -> ContentDB:
	_write(ROOT + "/base", {"pack.fsc": "== pack base\nname: Base\n", "player_values.fsc": TestPlayerValues.TEXT, "base.fsc": BASE})
	_write(ROOT + "/addon", {"pack.fsc": "== pack addon\nname: Addon\nrequires: base\n", "addon.fsc": addon})
	var db := ContentDB.new()
	db.load_folders([ROOT])
	return db


func before_each() -> void:
	var db := _load(ADDON)
	assert_eq(db.errors(), [], "the packs load without errors")
	game = Game.new(db, 2)
	game.start("camp")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func test_a_moment_runs_other_packs_hooks_in_place() -> void:
	game.runner.start("open_bag")
	assert_string_contains(_text(), "You get: bone.")
	assert_eq(ItemSystem.count(game, "bone"), 1)


func test_each_companion_with_its_numbers() -> void:
	game.apply(Effect.compile("summon rex"))
	game.take_output()
	game.runner.start("train")
	assert_string_contains(_text(), "Rex trains.")
	assert_eq(int(game.value("rex.level")), 3, "a level up for the companion the script is about")
	assert_eq(int(game.value("rex.xp")), 0, "the xp it was given paid for the level (2 * 2 * 5 = 20)")


func test_tame_all_companions() -> void:
	assert_false(Condition._truthy(game.value("fido.tamed")))
	game.apply(Effect.compile("tame all companions"))
	assert_true(Condition._truthy(game.value("fido.tamed")))


func test_moments_are_validated() -> void:
	var db := _load("== hook stray\non: no_such_moment\ndo:\n    Hm.\n\n== scene s\n~ for each companion play missing_scene\n")
	var text := "\n".join(db.errors().map(func(e): return str(e.message)))
	for part in ["A hook needs 'on:'", "no_such_moment", "missing_scene"]:
		assert_string_contains(text, part)
