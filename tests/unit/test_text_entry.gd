extends GutTest
## Typed answers: `~ ask <value>: <prompt>` waits for the player to type a
## short text into a value (naming a pet or a child).

const ROOT := "user://text_entry_test_packs"

const PACK := """== values pet
values:
    name: text
    named: flag

== location yard
name: Yard
description: A quiet yard.

== scene name_pet
A small dog wags its tail at you.
~ ask pet.name up to 12 letters: What do you call the dog?
if pet.name != "":
    ~ pet.named = yes quietly
    You call the dog [pet.name]. It barks happily.
else:
    The dog stays nameless.
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "pet.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 1)
	game.start("yard")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _events() -> Array:
	return game.take_output()


func _text(events: Array) -> String:
	var out: PackedStringArray = []
	for e in events:
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func test_the_scene_waits_for_a_typed_name_and_uses_it() -> void:
	game.runner.start("name_pet")
	var events := _events()
	var asks := events.filter(func(e): return e.type == "input")
	assert_eq(asks.size(), 1)
	assert_eq(asks[0].prompt, "What do you call the dog?")
	assert_eq(asks[0].max, 12)
	assert_eq(game.runner.status, "input")
	assert_false(game.runner.choose(0), "choices are not answered while typing")
	assert_true(game.runner.enter_text("  Biscuit  "))
	assert_eq(game.value("pet.name"), "Biscuit", "spaces around the answer are trimmed")
	assert_true(game.adjective("pet", "named"))
	assert_string_contains(_text(_events()), "You call the dog Biscuit.")


func test_an_empty_answer_and_long_or_marked_up_answers() -> void:
	game.runner.start("name_pet")
	_events()
	game.runner.enter_text("")
	assert_string_contains(_text(_events()), "The dog stays nameless.")
	game.runner.start("name_pet")
	_events()
	game.runner.enter_text("[Rex] the very long named dog")
	assert_eq(game.value("pet.name"), "(Rex) the ve", "brackets cannot become markup; the length is capped")


func test_a_saved_question_is_asked_again_after_loading() -> void:
	game.runner.start("name_pet")
	_events()
	var saved: Dictionary = game.save_dict()
	var other := Game.new(game.content, 2)
	assert_true(other.load_dict(saved))
	other.runner.run()
	var asks := other.take_output().filter(func(e): return e.type == "input")
	assert_eq(asks.size(), 1, "the question comes back")
	assert_true(other.runner.enter_text("Patch"))
	assert_eq(other.value("pet.name"), "Patch")
	other.dispose()


func test_ask_is_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := "== scene s\n~ ask nobody.name: Who?\n~ ask player.hp: How much?\n~ ask pet: Name?\n"
	var files := {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	assert_string_contains(text, "nobody")
	assert_string_contains(text, "player.hp")
	assert_string_contains(text, "ask pet: Name?")
