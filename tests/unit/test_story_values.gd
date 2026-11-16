extends GutTest
## Smaller story tools: a part's change text for a picked creature, the count of
## all fast-travel places, a character's talk or sex played from another scene,
## a weapon's damage changed in play, time values set back to never, the debug
## level, reflexive pronouns and a blank portrait, one list entry replaced, a
## random creature's loot, and separate conditions for events found by walking
## in and by exploring.

const ROOT := "user://story_values_test_packs"

const PACK := """== zone fields
name: Fields

== location hall
name: Hall
description: A hall.
flags: fast travel
zone: fields
exits:
    north: yard

== location yard
name: Yard
description: A yard.
flags: fast travel
zone: fields
exits:
    south: hall

== location shed
name: Shed
description: A shed.

== item sword
name: sword
weapon:
    damage: 6
    hit bonus: 1

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

== text stripcrotch
[if worn.waist + worn.legs + worn.crotch = 0]strokes over your bare crotch[else if worn.waist + worn.legs + worn.crotch = 1]pulls down your [worn list waist, legs, crotch] and bares your crotch[else]pulls down your [worn list waist, legs, crotch], baring your crotch[end if]

== text drake_grows
~ creature wolf scale = 4
It grows.

== hook whistle_taken
on: after taking trophy whistle
do:
    ~ log.whistle_taken = yes

== values log
values:
    when: time
    names: list
    prize: text
    walk_ok: flag
    explore_ok: flag
    whistle_taken: flag

== form vixen_form
name: Vixen
torso:
    change: you grow red fur

== creature vixen
name: Vixen
form: vixen_form
hp: 5
level: 1
damage: 1
loot: fur 30%
stats: strength 10, dexterity 10, stamina 10, perception 10, intelligence 10, charisma 10

== creature wolf
name: Wolf
hp: 5
level: 1
damage: 1
loot: fur 50%
trophies: whistle 100% if not log.whistle_taken
stats: strength 10, dexterity 10, stamina 10, perception 10, intelligence 10, charisma 10
defeated:
    The wolf flees.

== character gina
name: Gina
pronouns: she
image: gina_face
talk:
    Gina chats with you.
sex:
    Gina winks.

== character bob
name: Bob
pronouns: they

== hook bob_talk
on: instead of talking to bob
do:
    Bob shrugs.

== scene asks_gina
Before.
play talk of gina
After.

== scene asks_bob
play talk of bob

== event lovers
name: Lovers
found by: exploring in fields; walking into yard
repeat: always
requires: not log.names is empty
arrival requires: log.walk_ok
exploring requires: log.explore_ok
play:
    The lovers meet.

== scenario start
name: Start
start: hall
"""

var game: Game


func before_each() -> void:
	game = Game.new(_load({"main.fsc": PACK}), 3)
	game.start("hall")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _load(files: Dictionary) -> ContentDB:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	for f in DirAccess.get_files_at(ROOT + "/p"):
		DirAccess.remove_absolute(ROOT + "/p/" + f)
	var all := {"pack.fsc": "== pack p\nname: Test\n", "values.fsc": TestPlayerValues.TEXT}
	all.merge(files)
	for name: String in all:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(all[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	return db


func _errors(db: ContentDB) -> Array:
	return db.errors().map(func(d: Dictionary) -> String: return "%d %s" % [d.line, d.message])


func _warnings(db: ContentDB) -> Array:
	return db.diagnostics.filter(func(d: Dictionary) -> bool: return d.severity == "warning").map(
		func(d: Dictionary) -> String: return "%d %s" % [d.line, d.message])


func _say(text: String) -> String:
	return TextTemplate.plain(game.render(TextTemplate.compile(text)))


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
	return "\n".join(out)


func _yes(condition: String) -> bool:
	return Condition.evaluate(Condition.compile(condition), game)


func test_the_pack_loads_cleanly() -> void:
	assert_eq(_errors(game.content), [])
	assert_eq(_warnings(game.content).filter(func(m: String) -> bool: return not "gina_face" in m), [])


# --- [<part> change of picked.creature] ----------------------------------------

func test_a_parts_change_text_for_a_picked_creature() -> void:
	game.state.values["picked.creature"] = "vixen"
	assert_eq(_say("Your body shifts as [torso change of picked.creature]."), "Your body shifts as you grow red fur.",
		"the creature's strain (its form has another ID)")
	assert_eq(_say("[body change of vixen]"), "you grow red fur", "a named creature")


func test_change_texts_are_validated() -> void:
	var db := _load({"main.fsc": PACK, "more.fsc": "== scene s\n[torso change of picked.creature] [tail change of vixen_form]\n[wing change of vixen]\n[head change of nobody]\n[head change of log.nothing]\n"})
	var errors := _errors(db)
	assert_eq(errors.size(), 3, str(errors))
	assert_true(errors.any(func(m: String) -> bool: return "'wing' is not a body part" in m), str(errors))
	assert_true(errors.any(func(m: String) -> bool: return "'nobody' is neither a form nor a creature" in m), str(errors))
	assert_true(errors.any(func(m: String) -> bool: return "log.nothing" in m), str(errors))


# --- places.total --------------------------------------------------------------

func test_all_fast_travel_places_known_or_not() -> void:
	assert_eq(game.value("places.total"), 2, "hall and yard, not the shed")
	assert_eq(game.value("places.known"), 1, "the start")
	assert_eq(_say("[places.known * 100 / places.total]%"), "50%")
	game.state.known["yard"] = true
	assert_eq(_say("[places.known * 100 / places.total]%"), "100%")


# --- play talk of / play sex of ----------------------------------------------

func test_a_characters_talk_played_from_another_scene() -> void:
	game.runner.start("asks_gina")
	assert_eq(_text(), "Before.\nGina chats with you.\nAfter.")
	assert_true(game.value("gina.met"), "the character counts as met")
	game.runner.play_now("character:gina#sex")
	assert_eq(_text(), "Gina winks.")


func test_a_hook_instead_of_talking_plays_instead() -> void:
	game.runner.start("asks_bob")
	assert_eq(_text(), "Bob shrugs.")
	assert_eq(game.warnings, [])


func test_playing_a_missing_talk_is_an_error() -> void:
	var db := _load({"main.fsc": PACK, "more.fsc": "== character mute\nname: Mute\n\n== scene s\nplay sex of bob\nplay talk of mute\nplay talk of nobody\n"})
	var errors := _errors(db)
	assert_eq(errors.size(), 3, str(errors))
	assert_true(errors.any(func(m: String) -> bool: return m.begins_with("5 ") and "bob has no sex" in m), str(errors))
	assert_true(errors.any(func(m: String) -> bool: return m.begins_with("6 ") and "mute has no talk" in m), str(errors))
	assert_true(errors.any(func(m: String) -> bool: return m.begins_with("7 ") and "'nobody' does not exist" in m), str(errors))


# --- ~ item X damage + N -------------------------------------------------------

func test_a_weapons_damage_changes_in_play() -> void:
	game.state.inventory["sword"] = 1
	game.state.wielded = "sword"
	assert_eq(game.value("player.weapon_damage"), 6)
	game.apply(Effect.compile("item sword damage + 1"))
	assert_eq(int(ItemSystem.weapon(game).damage), 7)
	assert_eq(game.value("player.weapon_damage"), 7)
	game.apply(Effect.compile("item sword hit bonus = 3"))
	assert_eq(int(ItemSystem.weapon(game).hit), 3)
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(game.state.to_dict())))
	assert_eq(int(saved.values["item.sword.damage"]), 7, "kept in a save")
	game.state.wielded = ""
	assert_eq(game.value("player.weapon_damage"), 4, "unarmed: the fists' damage")


func test_only_a_weapons_damage_can_change() -> void:
	var db := _load({"main.fsc": PACK, "more.fsc": "== scene s\n~ item rope damage + 1\n~ item nothing damage = 2\n~ item sword damage + 2\n"})
	var errors := _errors(db)
	assert_eq(errors.size(), 2, str(errors))
	assert_true(errors.any(func(m: String) -> bool: return m.begins_with("2 ") and "not a weapon" in m), str(errors))


# --- ~ x = never ---------------------------------------------------------------

func test_a_time_value_set_back_to_never() -> void:
	assert_true(_yes("since log.when > 100 turns"), "never set: long ago")
	game.apply(Effect.compile("log.when = now"))
	assert_false(_yes("since log.when > 100 turns"))
	game.apply(Effect.compile("log.when = never"))
	assert_true(_yes("since log.when > 100 turns"), "long ago again")
	assert_eq(game.value("log.when"), null)


func test_a_time_value_set_to_a_number_is_a_warning() -> void:
	var db := _load({"main.fsc": PACK, "more.fsc": "== scene s\n~ log.when = 0\n~ log.when = never\n~ log.when = now\n"})
	assert_eq(_errors(db), [])
	var warnings := _warnings(db).filter(func(m: String) -> bool: return "time value" in m)
	assert_eq(warnings.size(), 1, str(warnings))
	assert_true(str(warnings).contains("2 log.when"), str(warnings))


# --- game.debug ----------------------------------------------------------------

func test_the_debug_level() -> void:
	assert_eq(game.value("game.debug"), 0, "off in normal play")
	assert_false(_yes("game.debug"))
	assert_eq(_say("[if game.debug]Debug: on.[else]Quiet.[end if]"), "Quiet.")
	game.set_value("game.debug", 10)
	assert_true(_yes("game.debug >= 10"))
	assert_eq(_say("[if game.debug]Debug: on.[else]Quiet.[end if]"), "Debug: on.")
	assert_false(game.save_dict().values().any(func(v: Variant) -> bool: return str(v).contains("game.debug")), "not saved")


func test_the_debug_start_option() -> void:
	assert_eq(LaunchOptions.parse(PackedStringArray([])).debug, 0)
	assert_eq(LaunchOptions.parse(PackedStringArray(["--debug", "--start", "hall"])).debug, 1, "a switch")
	var o := LaunchOptions.parse(PackedStringArray(["--debug", "10", "--start", "hall"]))
	assert_eq(o.debug, 10)
	assert_eq(o.start, "hall")
	assert_true(o.begin(game))
	assert_eq(game.value("game.debug"), 10)
	var by_set := LaunchOptions.parse(PackedStringArray(["--start", "hall", "--set", "game.debug=2"]))
	assert_true(by_set.begin(game))
	assert_eq(game.value("game.debug"), 2, "--set game.debug works too")


# --- [himself of x], ~ character X image none -----------------------------------

func test_reflexive_pronouns() -> void:
	assert_eq(_say("[himself of gina]"), "herself")
	assert_eq(_say("[Himself of bob]"), "Themselves")
	game.apply(Effect.compile("character bob pronouns it"))
	assert_eq(_say("[himself of bob]"), "itself")
	game.apply(Effect.compile("character bob pronouns he"))
	assert_eq(_say("[himself of bob]"), "himself")
	assert_eq(game.warnings, [])


func test_a_blank_portrait() -> void:
	assert_eq(game.character_image("gina"), "gina_face")
	game.apply(Effect.compile("character gina image none"))
	assert_eq(game.character_image("gina"), "", "no picture")
	game.apply(Effect.compile("character gina image default"))
	assert_eq(game.character_image("gina"), "gina_face")
	var db := _load({"main.fsc": PACK, "more.fsc": "== scene s\n~ character gina image none\n"})
	assert_false(_warnings(db).any(func(m: String) -> bool: return "'none'" in m))


# --- ~ entry N of x.list = V ---------------------------------------------------

func test_one_list_entry_replaced() -> void:
	game.apply(Effect.compile("add \"Ann\", \"Bea\", \"Cy\" to log.names"))
	game.apply(Effect.compile("entry 2 of log.names = \"Bo\""))
	assert_eq(game.value("log.names"), ["Ann", "Bo", "Cy"])
	game.apply(Effect.compile("entry 1 + 2 of log.names = entry 1 of log.names"))
	assert_eq(game.value("log.names"), ["Ann", "Bo", "Ann"], "places and values can be computed")
	game.apply(Effect.compile("entry 9 of log.names = 1"))
	assert_eq(game.value("log.names"), ["Ann", "Bo", "Ann"], "no such entry: unchanged")
	assert_string_contains(str(game.warnings), "no entry 9")


func test_list_entries_are_validated() -> void:
	var db := _load({"main.fsc": PACK, "more.fsc": "== scene s\n~ entry 1 of log.prize = 2\n~ entry 1 of log.names = log.missing\n"})
	var errors := _errors(db)
	assert_true(errors.any(func(m: String) -> bool: return m.begins_with("2 ") and "not a list" in m), str(errors))
	assert_true(errors.any(func(m: String) -> bool: return m.begins_with("3 ") and "log.missing" in m), str(errors))


# --- loot of random creature ---------------------------------------------------

func test_a_random_creatures_loot() -> void:
	game.apply(Effect.compile("log.prize = loot of random creature"))
	assert_eq(game.value("log.prize"), "fur", "both creatures drop fur")
	game.apply(Effect.compile("give loot of random creature"))
	assert_eq(ItemSystem.count(game, "fur"), 1)
	game.apply(Effect.compile("creature vixen loot none"))
	game.apply(Effect.compile("creature wolf loot none"))
	game.apply(Effect.compile("log.prize = loot of random creature"))
	assert_eq(game.value("log.prize"), "", "a creature without loot gives nothing")
	game.apply(Effect.compile("give loot of random creature"))
	assert_eq(ItemSystem.count(game, "fur"), 1)
	assert_eq(game.warnings, [])


func test_loot_goes_into_a_text_value() -> void:
	var db := _load({"main.fsc": PACK, "more.fsc": "== scene s\n~ log.walk_ok = loot of random creature\n~ give loot of random creature\n"})
	var errors := _errors(db)
	assert_eq(errors.size(), 1, str(errors))
	assert_true(errors[0].begins_with("2 ") and "declare it as text" in errors[0], str(errors))


# --- arrival requires / exploring requires ------------------------------------

func test_separate_conditions_for_walking_in_and_exploring() -> void:
	game.apply(Effect.compile("add 1 to log.names"))
	assert_eq(game.runner.arrival_event("walk", "yard"), "", "walking in needs its own condition")
	assert_eq(game.runner.explore_events("fields"), [], "exploring needs its own")
	game.set_value("log.walk_ok", true)
	assert_eq(game.runner.arrival_event("walk", "yard"), "lovers")
	assert_eq(game.runner.explore_events("fields"), [], "the walk-in condition does not open exploring")
	game.set_value("log.walk_ok", false)
	game.set_value("log.explore_ok", true)
	assert_eq(game.runner.explore_events("fields"), ["lovers"])
	assert_eq(game.runner.arrival_event("walk", "yard"), "")
	game.set_value("log.walk_ok", true)
	game.apply(Effect.compile("clear log.names"))
	assert_eq(game.runner.arrival_event("walk", "yard"), "", "requires: still applies to both")
	assert_eq(game.runner.explore_events("fields"), [])


func test_trigger_conditions_are_validated() -> void:
	var db := _load({"main.fsc": PACK, "more.fsc": "== event e\nname: E\nfound by: exploring in fields\narrival requires: log.walk_ok\nexploring requires: nonsense words here\nplay:\n    Hi.\n"})
	assert_true(_errors(db).any(func(m: String) -> bool: return m.begins_with("5 ")), str(_errors(db)))
	assert_true(_warnings(db).any(func(m: String) -> bool: return m.begins_with("4 ") and "walking into" in m), str(_warnings(db)))


func test_the_loot_of_the_picked_creature() -> void:
	game.apply(Effect.compile("log.prize = loot of picked creature"))
	assert_eq(game.value("log.prize"), "", "nothing picked yet")
	game.state.values["picked.creature"] = "vixen"
	game.apply(Effect.compile("give loot of picked creature"))
	assert_eq(ItemSystem.count(game, "fur"), 1)


# --- ~ remove X N from place ---------------------------------------------------

func test_removing_some_of_the_items_lying_in_a_place() -> void:
	game.apply(Effect.compile("put rope 3 in hall"))
	game.apply(Effect.compile("remove rope 1 from hall"))
	assert_eq(ItemSystem.ground(game, "hall"), {"rope": 2})
	game.apply(Effect.compile("remove rope 5 from here"))
	assert_eq(ItemSystem.ground(game, "hall"), {}, "more than lie there: all of them")
	game.apply(Effect.compile("put rope 2 in yard"))
	game.apply(Effect.compile("remove rope from yard"))
	assert_eq(ItemSystem.ground(game, "yard"), {}, "without a number: all of them, as before")


# --- [worn list ...], worn.<slot> ---------------------------------------------

func test_someone_else_undressing_the_player() -> void:
	assert_eq(_say("He [stripcrotch]."), "He strokes over your bare crotch.")
	game.state.equipped.append("jeans")
	assert_eq(game.value("worn.legs"), 1)
	assert_eq(game.value("worn.crotch"), 0)
	assert_eq(_say("He [stripcrotch]."), "He pulls down your jeans and bares your crotch.")
	game.state.equipped.append("boxers")
	assert_eq(_say("He [stripcrotch]."), "He pulls down your jeans and boxers, baring your crotch.")
	assert_eq(_say("[worn list waist, legs, crotch]"), "jeans and boxers")
	var db := _load({"main.fsc": PACK, "more.fsc": "== scene s\n[worn list legs, wings]\n\n~ log.prize = worn.tail\n"})
	var errors := _errors(db)
	assert_eq(errors.size(), 2, str(errors))


# --- after taking trophy <item> -------------------------------------------------

func test_a_hook_after_taking_a_trophy() -> void:
	game.runner.start_encounter("wolf")
	game.take_output()
	game.set_value("enemy.hp", -100)
	game.runner.combat_action("pass")
	var options: Array = []
	for e in game.take_output():
		if e.type == "choices":
			options = e.options.map(func(o: Dictionary) -> String: return o.text)
	assert_eq(options, ["whistle", "Take nothing"])
	game.runner.choose(0)
	while game.runner.status == "continue":
		game.runner.proceed()
	assert_eq(ItemSystem.count(game, "whistle"), 1)
	assert_true(game.value("log.whistle_taken"), "the hook ran")


# --- creature changes in a text snippet -----------------------------------------

func test_a_text_snippet_may_change_a_creature() -> void:
	assert_eq(_say("[drake_grows]"), "It grows.")
	assert_eq(VoreSystem.scale_of(game, "wolf"), 4)
	assert_eq(_errors(game.content), [], "allowed in a snippet")
