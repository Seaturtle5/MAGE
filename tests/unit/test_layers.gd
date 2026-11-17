extends GutTest
## Layered content (ContentDB.layer()): packs loaded over content that stays
## as it was, for a tool that reloads one pack after each change; definitions
## kept unchanged when an extension adds to them (protect_definitions); a
## check of only some packs' scripts; compiling from several threads.

const ROOT := "user://layers_test"

const BASE := """== tag human
name: Human

== tag tall
name: Tall

== location bunker
name: Bunker
description: A bunker.
flags: safe rest
exits:
    north: yard

== location yard
name: Yard
description: A yard.
exits:
    south: bunker

== character adam
name: Adam
tags: human
lives at: bunker
values:
    met: flag
talk:
    Hello.

== menu chat
title: Chat
* Ask
    An answer.

== scene base_story
Words of the base.
~ adam.met = true

== extend location cellar
exits:
    up: bunker
"""

const TOP := """== location cellar
name: Cellar
description: A cellar.

== scene top_story
Words on top.
~ adam.met = true
-> base_story

== extend location bunker
exits:
    down: cellar

== extend character adam
tags: tall
talk:
    And more.

== extend menu chat
* Ask again
    Another answer.
"""


func _file(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_wipe(path.path_join(sub))
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func before_each() -> void:
	_wipe(ROOT)
	_file(ROOT + "/base/pack.fsc", "== pack base\nname: Base\n")
	_file(ROOT + "/base/world.fsc", BASE)
	_file(ROOT + "/top/pack.fsc", "== pack top\nname: Top\nrequires: base\n")
	_file(ROOT + "/top/more.fsc", TOP)


func after_all() -> void:
	_wipe(ROOT)


func _base() -> ContentDB:
	var db := ContentDB.new()
	db.load_pack(ROOT + "/base")
	db._finish()
	return db


func _exits(db: ContentDB, id: String) -> Array:
	var out: Array = []
	for l: FscParser.Line in db.get_def("location", id).fields.exits.children:
		if not l.is_blank():
			out.append(l.text)
	return out


func _messages(db: ContentDB) -> Array:
	return db.diagnostics.map(func(d: Dictionary) -> String: return "%s: %s" % [d.severity, d.message])


func test_a_layer_adds_packs_and_leaves_the_content_below_as_it_was() -> void:
	var base := _base()
	var bunker := base.get_def("location", "bunker")
	var adam := base.get_def("character", "adam")
	var top := base.layer()
	top.load_pack(ROOT + "/top")
	top._finish()
	assert_eq(_exits(top, "bunker"), ["north: yard", "down: cellar"], "the layer's extension adds its exit")
	assert_eq(top.get_def("character", "adam").fields.tags.value, "human, tall")
	assert_eq(top.menus.chat.options.size(), 2, "and its menu option")
	assert_true(top.has("top_story", "scene") and top.has("base_story", "scene"))
	assert_eq(top.program("character:adam#talk").code.filter(func(i: Dictionary) -> bool: return i.op == "text").size(), 2, "the script is the base's with the layer's added")
	# Below, nothing moved.
	assert_eq(_exits(base, "bunker"), ["north: yard"])
	assert_eq(base.get_def("character", "adam").fields.tags.value, "human")
	assert_eq(base.menus.chat.options.size(), 1)
	assert_false(base.has("top_story", "scene"))
	assert_same(base.get_def("location", "bunker"), bunker, "the base keeps its own definitions")
	assert_same(base.get_def("character", "adam"), adam)
	assert_eq(base.program("character:adam#talk").code.filter(func(i: Dictionary) -> bool: return i.op == "text").size(), 1)
	assert_same(top.get_def("location", "yard"), base.get_def("location", "yard"), "what the layer does not touch is shared")


func test_an_extension_below_finds_what_the_layer_brings() -> void:
	var base := _base()
	assert_true(_messages(base).has("error: Cannot extend location cellar: it does not exist."), "alone, the base's extension has nothing to extend")
	var top := base.layer()
	assert_false(_messages(top).has("error: Cannot extend location cellar: it does not exist."), "the layer tries it again")
	top.load_pack(ROOT + "/top")
	top._finish()
	assert_eq(top.errors(), [], "and it applies once the cellar is there")
	assert_eq(_exits(top, "cellar"), ["up: bunker"])
	var other := base.layer()
	other._finish()
	assert_true(_messages(other).has("error: Cannot extend location cellar: it does not exist."), "without the cellar the problem is reported on the layer")


func test_a_base_can_be_layered_again_and_again() -> void:
	var base := _base()
	for round in 3:
		var top := base.layer()
		top.load_pack(ROOT + "/top")
		top._finish()
		Validator.run(top)
		assert_eq(top.errors(), [], "round %d" % round)
		assert_eq(_exits(top, "bunker"), ["north: yard", "down: cellar"], "round %d" % round)
		assert_eq(top.menus.chat.options.size(), 2)
	assert_eq(_exits(base, "bunker"), ["north: yard"])


func test_a_layer_can_replace_a_scene_below() -> void:
	var base := _base()
	assert_not_null(base.program("base_story"))
	_file(ROOT + "/top/replace.fsc", "== replace scene base_story\nOther words.\n")
	var top := base.layer()
	top.load_pack(ROOT + "/top")
	top._finish()
	assert_eq(top.program("base_story").code[0].text.parts[0].v, "Other words.", "the layer's scene, not the program compiled below")
	assert_eq(base.program("base_story").code[0].text.parts[0].v, "Words of the base.")


func test_protected_definitions_stay_as_parsed() -> void:
	var db := ContentDB.new()
	db.protect_definitions = true
	db.load_pack(ROOT + "/base")
	db.load_pack(ROOT + "/top")
	var parsed_bunker := db.get_def("location", "bunker")
	var parsed_adam := db.get_def("character", "adam")
	db._finish()
	Validator.run(db)
	assert_eq(db.errors(), [])
	assert_eq(_exits(db, "bunker"), ["north: yard", "down: cellar"])
	assert_eq(db.get_def("character", "adam").fields.tags.value, "human, tall")
	assert_eq(parsed_bunker.fields.exits.children.filter(func(l: FscParser.Line) -> bool: return not l.is_blank()).size(), 1, "the parsed place keeps its one exit")
	assert_eq(parsed_adam.fields.tags.value, "human", "and the parsed character its own tags")
	# Without it the loader changes the parsed definitions, as it always did.
	var plain := ContentDB.new()
	plain.load_pack(ROOT + "/base")
	plain.load_pack(ROOT + "/top")
	var plain_adam := plain.get_def("character", "adam")
	plain._finish()
	assert_same(plain.get_def("character", "adam"), plain_adam)
	assert_eq(plain_adam.fields.tags.value, "human, tall")


func test_a_check_of_one_packs_scripts() -> void:
	_file(ROOT + "/base/broken.fsc", "== scene base_broken\n~ give no_such_item\n")
	_file(ROOT + "/top/broken.fsc", "== scene top_broken\n~ give missing_thing\n\n== extend character adam\ntalk:\n    ~ give absent_thing\n")
	var base := _base()
	var top := base.layer()
	top.load_pack(ROOT + "/top")
	top._finish()
	Validator.run(top, [ROOT + "/top"])
	var found := _messages(top).filter(func(m: String) -> bool: return m.begins_with("error"))
	assert_true(found.any(func(m: String) -> bool: return "missing_thing" in m), "a problem in the pack's own scene: %s" % [found])
	assert_true(found.any(func(m: String) -> bool: return "absent_thing" in m), "and in a script it adds to content below")
	assert_false(found.any(func(m: String) -> bool: return "no_such_item" in m), "the other pack's scripts are not checked again")
	var whole := base.layer()
	whole.load_pack(ROOT + "/top")
	whole._finish()
	Validator.run(whole)
	assert_true(_messages(whole).any(func(m: String) -> bool: return "no_such_item" in m), "a full check finds them all")


func test_compiled_content_can_be_forgotten() -> void:
	var first := Effect.compile("player.hp + 77")
	assert_same(Effect.compile("player.hp + 77"), first, "a line compiled twice is kept")
	Condition.compile("player.hp >= 77")
	TextTemplate.compile("[if player.hp > 77]Yes[end if]")
	ContentDB.forget_compiled()
	assert_eq(Effect._cache.size() + Condition._cache.size() + TextTemplate._cache.size(), 0, "nothing is kept")
	var again := Effect.compile("player.hp + 77")
	assert_eq(again, first, "and the line compiles the same again")
	assert_not_same(again, first)
	var base := _base()
	assert_not_null(base.program("base_story"), "loaded content keeps its programs")
	ContentDB.forget_compiled()
	assert_eq(base.program("base_story").code[0].text.parts[0].v, "Words of the base.")


func test_content_compiles_from_several_threads() -> void:
	var texts: Array = []
	for i in 400:
		texts.append("player.hp + %d" % i)
	var work := func() -> int:
		var done := 0
		for t: String in texts:
			if Effect.compile("~ " + t.trim_prefix("~ ")).has("op") or true:
				done += 1
			Condition.compile("player.hp >= %d and chance 1 in 3" % done)
			TextTemplate.compile("[if player.hp > %d]Yes[else]No[end if]" % done)
		return done
	var threads: Array[Thread] = []
	for i in 4:
		var thread := Thread.new()
		thread.start(work)
		threads.append(thread)
	var total := 0
	for thread: Thread in threads:
		total += int(thread.wait_to_finish())
	assert_eq(total, 1600, "four threads compiled the same texts side by side")


func test_the_map_layout_reads_each_definition_once() -> void:
	_file(ROOT + "/base/doors.fsc", "== location shed\nname: Shed\ndescription: A shed.\n\n== scene open_shed\nThe shed stands open.\n~ change east exit of yard to shed\n")
	_file(ROOT + "/top/doors.fsc", "== location loft\nname: Loft\ndescription: A loft.\n\n== scene open_loft\nA ladder comes down.\n~ change up exit of shed to loft\n\n== extend character adam\ngift:\n    Adam opens a gate.\n    ~ change west exit of yard to loft\n")
	var base := _base()
	assert_eq(MapLayout.changed_exits(base), [["east", "yard", "shed"]], "an exit a scene makes in play is found")
	var scene := base.get_def("scene", "open_shed")
	var read: Variant = scene.changed_exits
	assert_eq(Array(read), ["east yard shed"], "and the definition remembers it")
	assert_eq(Array(base.get_def("scene", "base_story").changed_exits), [], "as does one that makes none")
	var top := base.layer()
	top.load_pack(ROOT + "/top")
	top._finish()
	assert_eq(MapLayout.changed_exits(top), [["east", "yard", "shed"], ["up", "shed", "loft"], ["west", "yard", "loft"]], "a layer adds what its own packs make, also in a script it adds to content below")
	assert_same(top.get_def("scene", "open_shed"), scene, "what the layer shares")
	assert_true(is_same(scene.changed_exits, read), "is not read a second time")
	assert_eq(MapLayout.changed_exits(base), [["east", "yard", "shed"]], "and the content below still makes only its own")
	assert_eq(top.map_layout().group.get("loft", ""), top.map_layout().group.get("yard", "?"), "the layout joins the places such exits lead to")
	# Without protection an extension changes the definition itself: it is read again.
	var plain := ContentDB.new()
	plain.load_pack(ROOT + "/base")
	plain._finish()
	assert_eq(MapLayout.changed_exits(plain).size(), 1)
	plain.load_pack(ROOT + "/top")
	plain._finish()
	assert_eq(MapLayout.changed_exits(plain).size(), 3, "an extension loaded later is read")
