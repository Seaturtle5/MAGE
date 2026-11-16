extends GutTest
## Trophies offered only while a condition holds, a creature's size changed in
## play (`~ creature X scale = 4`), hooks when a game starts and while
## travelling, dressing again (`[dress crotch]`), and items lying in a place
## (`bunker has water_bottle`).

const ROOT := "user://small_gaps_test_packs"

const PACK := """== location hall
name: Hall
description: A hall.
flags: fast travel
items: rope

== location yard
name: Yard
description: A yard.
flags: fast travel

== item rope
name: rope

== item fur
name: fur

== item whistle
name: whistle

== item jeans
name: jeans
equipment:
    slot: legs

== item boxers
name: boxers
equipment:
    slot: crotch

== values log
values:
    whistle_taken: flag
    order: list
    chatter: number

== form drake
name: Drake
scale: 3

== creature drake
name: Drake
form: drake
hp: 5
level: 1
damage: 1
stats: strength 10, dexterity 1, stamina 10, perception 10, intelligence 10, charisma 10
trophies: whistle 100% if not log.whistle_taken, fur 100%
defeated:
    The drake flees.

== scenario start
name: Start
start: hall
setup:
    ~ add 1 to log.order

== hook shuffle
on: game starts
do:
    ~ add 2 to log.order

== hook chatter
on: while travelling
do:
    Your friend hums a tune on the way.
    ~ log.chatter + 1
"""

var game: Game


func before_each() -> void:
	game = Game.new(_load({"pack.fsc": "== pack p\nname: Test\n", "main.fsc": PACK, "values.fsc": TestPlayerValues.TEXT}), 3)
	game.start("hall")
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


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func _trophies() -> Array:
	game.runner.start_encounter("drake")
	game.take_output()
	game.set_value("enemy.hp", -100)
	game.runner.combat_action("pass")
	for e in game.take_output():
		if e.type == "choices":
			return e.options.map(func(o: Dictionary) -> String: return o.text)
	return []


func test_the_pack_loads_cleanly() -> void:
	assert_eq(game.content.errors(), [])


func test_a_trophy_with_a_condition() -> void:
	assert_eq(_trophies(), ["whistle", "fur", "Take nothing"])
	game.runner.choose(0)
	game.take_output()
	game.set_value("log.whistle_taken", true)
	assert_eq(_trophies(), ["fur", "Take nothing"], "offered only while the condition holds")


func test_a_trophy_condition_is_validated() -> void:
	var db := _load({"pack.fsc": "== pack p\nname: Test\n", "values.fsc": TestPlayerValues.TEXT,
		"w.fsc": "== item fur\nname: fur\n\n== creature c\nname: C\ntrophies: fur 50% if nonsense words here\n"})
	var errors: Array = db.errors().map(func(d: Dictionary) -> String: return "%d %s" % [d.line, d.message])
	assert_true(errors.any(func(m: String) -> bool: return m.begins_with("6 ")), str(errors))


func test_a_creatures_size_changes_in_play() -> void:
	assert_eq(VoreSystem.scale_of(game, "drake"), 3)
	game.apply(Effect.compile("creature drake scale = 5"))
	assert_eq(VoreSystem.scale_of(game, "drake"), 5)
	assert_eq(BodySystem.form_scale(game, "drake"), 5, "a body of that strain too")
	game.apply(Effect.compile("creature drake scale - 1"))
	assert_eq(VoreSystem.scale_of(game, "drake"), 4)
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(game.state.to_dict())))
	assert_eq(int(saved.values["form.drake.scale"]), 4, "kept in a save")


func test_a_hook_when_the_game_starts() -> void:
	assert_true(game.start_scenario("start"))
	assert_eq(game.value("log.order"), [1, 2], "once, after the scenario's setup")


func test_a_hook_while_travelling() -> void:
	game.state.known["yard"] = true
	assert_true(game.runner.act("travel", "yard"))
	while game.runner.status == "continue":
		game.runner.proceed()
	while game.runner.status == "combat":
		game.runner.combat_action("submit")
	var text := _text()
	assert_string_contains(text, "Your friend hums a tune on the way.")
	assert_eq(int(game.value("log.chatter")), 1)
	assert_eq(game.state.location, "yard")
	assert_true(text.find("You travel to Yard") < text.find("Your friend hums"), "after the travel line")


func test_dressing_again() -> void:
	var dress := TextTemplate.compile("You [dress crotch].")
	assert_eq(TextTemplate.plain(game.render(dress)), "You casually stroke over your bare crotch.")
	game.state.equipped.append("jeans")
	assert_eq(TextTemplate.plain(game.render(dress)), "You collect and put your jeans back on.")
	game.state.equipped.append("boxers")
	assert_eq(TextTemplate.plain(game.render(dress)), "You collect your jeans and boxers to put them back on.")
	assert_eq(TextTemplate.plain(game.render(TextTemplate.compile("[dress chest]"))), "casually stroke over your bare chest")


func test_items_lying_in_a_place() -> void:
	var has := Condition.compile("hall has rope")
	assert_true(Condition.evaluate(has, game), "its items: not yet taken")
	assert_true(Condition.evaluate(Condition.compile("here has rope"), game))
	assert_false(Condition.evaluate(Condition.compile("yard has rope"), game))
	assert_false(Condition.evaluate(Condition.compile("player has rope"), game))
	assert_true(game.runner.act("take", "rope"))
	assert_false(Condition.evaluate(has, game), "taken")
	assert_true(Condition.evaluate(Condition.compile("player has rope"), game))
	assert_true(Condition.evaluate(Condition.compile("hall does not have rope"), game))


func _para(text: String) -> Dictionary:
	return {"type": "paragraph", "spans": [{"text": text, "bold": false, "italic": false, "class": ""}]}


func test_a_sentence_split_by_a_condition_stays_one_paragraph() -> void:
	game.take_output()
	game.emit(_para("This is quite a view"))
	game.emit(_para(". Watching him turns you on."))
	game.emit(_para("A new paragraph."))
	game.emit(_para("...and an ellipsis starts its own."))
	game.emit(_para(".'"))
	assert_eq(_text(), "This is quite a view. Watching him turns you on.\nA new paragraph.\n...and an ellipsis starts its own..'")
	assert_false(TextTemplate.continues([{"text": "...well."}]), "an ellipsis is not a continuation")
