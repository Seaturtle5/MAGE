extends GutTest
## Giving a carried item to a character (`gift:`, `gift tags:`, `gift when:`,
## `gift prompt:`; the chosen item in `gift.item`, tested with `gift.item is
## tagged milky`), and outcomes with resolution numbers (`outcomes: fed = 1`,
## `outcome_2`) that `~ outcome` copies into the event's `.resolution`.

const ROOT := "user://gifts_outcomes_test_packs"

const PACK := """== tag milky
name: Milky

== tag cum
name: Cum

== location yard
name: Yard
description: A yard.

== item milk
name: bottle of milk
tags: milky

== item cream
name: cream
tags: milky, cum

== item rock
name: rock

== character mort
name: Mort
lives at: yard
gift tags: milky, cum
gift prompt: What do you hand [name of mort]?
gift:
    if gift.item is tagged cum:
        Mort sniffs the [name of gift.item] and grins.
    else:
        Mort takes the [name of gift.item].
    ~ take gift.item
    ~ mort.gifts + 1

== character xerx
name: Xerx
lives at: yard
gift when: xerx.friendly
gift:
    if gift.item is rock:
        Xerx keeps the rock.
        ~ take gift.item
    else:
        Xerx shakes his head.

== values xerx
values:
    friendly: flag

== values mort
values:
    gifts: number

== character plain
name: Plain
lives at: yard
talk:
    Hello.

== event feeding
found by: nowhere
outcomes: fed = 1, chased_off = 2, bitten
play:
    You feed it.

== event numbered
found by: nowhere
outcomes: outcome_1, outcome_2
play:
    Something.

== scene feed
~ outcome fed of feeding
"""

var game: Game


func before_each() -> void:
	game = Game.new(_load({"pack.fsc": "== pack p\nname: Test\n", "main.fsc": PACK, "values.fsc": TestPlayerValues.TEXT}), 3)
	game.start("yard")
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


func _messages(db: ContentDB, severity: String) -> Array:
	return db.diagnostics.filter(func(d: Dictionary) -> bool: return d.severity == severity).map(
		func(d: Dictionary) -> String: return "%d %s" % [d.line, d.message])


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func _person(id: String) -> Dictionary:
	game.runner.show_location()
	for e in game.take_output():
		if e.type == "location":
			for p: Dictionary in e.people:
				if p.id == id:
					return p
	return {}


func test_the_pack_loads_cleanly() -> void:
	assert_eq(_messages(game.content, "error"), [])


func test_give_offers_fitting_items_and_runs_the_characters_script() -> void:
	assert_false(_person("mort").give, "nothing fitting carried: no Give")
	game.state.inventory["rock"] = 1
	assert_false(_person("mort").give, "a rock is not milky")
	assert_false(game.runner.act("give", "mort"))
	game.state.inventory["milk"] = 2
	game.state.inventory["cream"] = 1
	assert_true(_person("mort").give)
	assert_false(_person("plain").give, "no gift: script")
	assert_true(game.runner.act("give", "mort"))
	var asked: Dictionary = game.take_output().filter(func(e: Dictionary) -> bool: return e.type == "choices")[-1]
	assert_eq(asked.title, "What do you hand Mort?")
	assert_eq(asked.options.map(func(o: Dictionary) -> String: return o.text), ["cream", "bottle of milk", "Nevermind"],
		"items with any of the tags (by ID), not the rock")
	assert_true(game.runner.choose(0))
	assert_eq(str(game.value("gift.item")), "cream")
	assert_eq(str(game.value("gift.to")), "mort")
	assert_string_contains(_text(), "Mort sniffs the cream and grins.")
	assert_eq(int(game.state.inventory.get("cream", 0)), 0, "~ take gift.item keeps it")
	assert_eq(int(game.value("mort.gifts")), 1)
	assert_eq(game.runner.status, "idle")


func test_nevermind_gives_nothing() -> void:
	game.state.inventory["milk"] = 1
	assert_true(game.runner.act("give", "mort"))
	game.take_output()
	assert_true(game.runner.choose(1), "Nevermind")
	assert_eq(str(game.value("gift.item")), "")
	assert_eq(int(game.state.inventory.get("milk", 0)), 1)
	assert_eq(int(game.value("mort.gifts")), 0, "the gift script did not run")


func test_gift_when_and_any_item_without_tags() -> void:
	game.state.inventory["rock"] = 1
	game.state.inventory["milk"] = 1
	assert_false(_person("xerx").give, "gift when: does not hold")
	game.set_value("xerx.friendly", true)
	assert_true(_person("xerx").give)
	assert_true(game.runner.act("give", "xerx"))
	var asked: Dictionary = game.take_output().filter(func(e: Dictionary) -> bool: return e.type == "choices")[-1]
	assert_eq(asked.title, "Give what to Xerx?", "the interface's own question")
	assert_eq(asked.options.map(func(o: Dictionary) -> String: return o.text), ["bottle of milk", "rock", "Nevermind"],
		"no gift tags: any carried item")
	assert_true(game.runner.choose(0))
	assert_string_contains(_text(), "Xerx shakes his head.")
	assert_eq(int(game.state.inventory.get("milk", 0)), 1, "refused: kept")


func test_gift_fields_are_validated() -> void:
	var db := _load({"pack.fsc": "== pack p\nname: Test\n", "values.fsc": TestPlayerValues.TEXT,
		"w.fsc": "== item rock\nname: rock\n\n== character a\nname: A\ngift tags: shiny\n\n== character b\nname: B\ngift tags: shiny\ngift when: nonsense here\ngift:\n    ~ take gift.item\n    if gift.item is tagged sparkly:\n        Yes.\n"})
	var errors := _messages(db, "error")
	var warnings := _messages(db, "warning")
	assert_true(errors.any(func(m: String) -> bool: return m.begins_with("6 'gift tags' needs a 'gift:' script")), str(errors))
	assert_true(warnings.any(func(m: String) -> bool: return m.begins_with("10 No item is tagged 'shiny'")), str(warnings))
	assert_true(errors.any(func(m: String) -> bool: return m.begins_with("11 ")), "gift when is checked as a condition: " + str(errors))
	assert_true(warnings.any(func(m: String) -> bool: return "'gift.item is tagged sparkly' is never true" in m), str(warnings))
	assert_false(errors.any(func(m: String) -> bool: return "gift.item" in m), "~ take gift.item is allowed: " + str(errors))


func test_an_outcome_with_a_number_sets_the_resolution() -> void:
	game.runner.start("feed")
	game.take_output()
	assert_eq(str(game.value("feeding.outcome")), "fed")
	assert_eq(int(game.value("feeding.resolution")), 1)
	game.apply(Effect.compile("outcome chased_off of feeding"))
	assert_eq(int(game.value("feeding.resolution")), 2)
	game.apply(Effect.compile("outcome bitten of feeding"))
	assert_eq(int(game.value("feeding.resolution")), 2, "an outcome without a number leaves it")
	game.apply(Effect.compile("feeding.resolution = 7"))
	assert_eq(int(game.value("feeding.resolution")), 7, "setting it directly still works")
	game.apply(Effect.compile("outcome outcome_2 of numbered"))
	assert_eq(int(game.value("numbered.resolution")), 2, "outcome_N carries N")
	assert_true(Condition.evaluate(Condition.compile("feeding outcome is bitten"), game), "outcome names stay plain")


func test_outcome_lists_and_unset_resolutions_are_checked() -> void:
	var db := _load({"pack.fsc": "== pack p\nname: Test\n", "values.fsc": TestPlayerValues.TEXT,
		"w.fsc": "== event a\nfound by: nowhere\noutcomes: fed = x, good, good\nplay:\n    Hi.\n\n== event b\nfound by: nowhere\noutcomes: won, lost\nplay:\n    if b.resolution = 1:\n        Again.\n\n== event c\nfound by: nowhere\noutcomes: won = 1\nplay:\n    if c.resolution = 1:\n        Again.\n\n== event d\nfound by: nowhere\noutcomes: won\nplay:\n    ~ d.resolution = 3\n    if d.resolution = 3:\n        Again.\n"})
	var errors := _messages(db, "error")
	var warnings := _messages(db, "warning")
	assert_true(errors.any(func(m: String) -> bool: return m.begins_with("3 Outcome fed's number must be a whole number")), str(errors))
	assert_true(warnings.any(func(m: String) -> bool: return m.begins_with("3 Outcome good is listed twice")), str(warnings))
	var unset := warnings.filter(func(m: String) -> bool: return "nothing sets it" in m)
	assert_eq(unset.size(), 1, str(warnings))
	assert_true(str(unset).contains("11 b.resolution is read here"), str(unset))
