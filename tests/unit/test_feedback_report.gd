extends GutTest
## Report a bug / Feedback: the game pack's fields, the player's last steps
## and the text shown last (ring buffers, not saved), exactly the data a
## report gathers, the state of the game and the save it may hold, the
## Discord message within Discord's limits, what the receiver gets, and the
## window without an address or with an answer. No network: nothing here
## sends anything.

const ROOT := "user://feedback_report_packs"

const MANIFEST := """== pack p
name: Test
version: 2.3.4
title: Test Game
feedback webhook: https://discord.com/api/webhooks/1/abc
feedback receiver: https://reports.example.org/intake/abc
start notice title: Welcome
start notice:
    A **public** test.
    All feedback is *welcome*.

    Join us at https://example.org/chat.
"""

const PACK := """== location field
name: Field
description: Tall grass.
exits:
    north: barn

== location barn
name: Barn
description: Hay.
exits:
    south: field

== character ann
name: Ann
lives at: field
talk:
    Ann waves.
    * Wave back
        You wave.
    * Say your name
        You tell her your name.

== values pet
values:
    name: text
    mood: text
    tricks: 0

== item apple
name: apple

== feat keen
name: Keen

== scene naming
~ ask pet.name: What do you call the dog?
Thanks.

== event storm
name: The Storm
play:
    Rain falls.
    * Shelter
        You hide.
"""


var game: Game
var db: ContentDB


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": MANIFEST, "player_values.fsc": TestPlayerValues.TEXT, "content.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	db = ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors().map(func(d): return "%d %s" % [d.line, d.message]), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("field")
	game.take_output()


func after_each() -> void:
	game.dispose()


func test_pack_fields() -> void:
	var b := db.branding()
	assert_eq(b.version, "2.3.4")
	assert_eq(b["feedback webhook"], "https://discord.com/api/webhooks/1/abc")
	assert_eq(b["feedback receiver"], "https://reports.example.org/intake/abc")
	assert_eq(b["start notice title"], "Welcome")
	assert_eq(b["start notice"], "A **public** test. All feedback is *welcome*.\n\nJoin us at https://example.org/chat.")


func test_ring_buffer_keeps_the_last_steps() -> void:
	var f := FeedbackReport.new()
	for i in 34:
		f.note("step %d" % i)
	assert_eq(f.steps.size(), FeedbackReport.STEPS_KEPT)
	assert_eq(f.step_lines()[0], "step 4", "the oldest steps fall out")
	assert_eq(f.step_lines()[-1], "step 33")
	f.note("explore")
	f.note("explore")
	f.note("explore")
	assert_eq(f.step_lines()[-1], "explore (3 times)", "a repeated step counts up")
	f.note("  ")
	assert_eq(f.step_lines()[-1], "explore (3 times)", "an empty step is not noted")
	f.note("x".repeat(200))
	assert_eq(str(f.step_lines()[-1]).length(), FeedbackReport.STEP_LIMIT)


func test_steps_come_from_play_and_are_not_saved() -> void:
	game.runner.act("go", "north")
	game.runner.act("go", "south")
	game.runner.act("talk", "ann")
	assert_eq(game.runner.status, "choice")
	game.runner.choose(0)
	game.runner.act("wait")
	assert_eq(game.feedback.step_lines(), ["go north", "go south", "talk to ann", "choose: Wave back", "wait"])
	var saved := JSON.stringify(game.save_dict())
	assert_false("talk to ann" in saved, "the steps are not part of a save")
	var loaded := Game.new(db, 3)
	assert_true(loaded.load_dict(game.save_dict()))
	assert_eq(loaded.feedback.step_lines(), ["load a saved game"])
	loaded.dispose()


func test_typed_answers_are_never_noted() -> void:
	game.runner.start("naming")
	assert_eq(game.runner.status, "input")
	game.runner.enter_text("Secret Name")
	assert_eq(game.feedback.step_lines()[-1], "type an answer")
	assert_false("Secret" in str(game.feedback.step_lines()))


func test_gather_holds_exactly_the_listed_data() -> void:
	game.set_value("player.name", "Zed")
	game.runner.act("talk", "ann")
	var r := FeedbackReport.gather(db, game, "  The barn door is stuck.  ", "1.0.0")
	assert_eq(r.keys(), FeedbackReport.KEYS, "exactly the listed fields, nothing else")
	assert_eq(r.text, "The barn door is stuck.")
	assert_eq(r.place_id, "field")
	assert_eq(r.place_name, "Field")
	assert_eq(r.playing.get("title"), "Talking with Ann", "the scene playing now")
	assert_eq(r.playing.get("scene"), "ann#talk")
	assert_eq(r.steps, ["talk to ann"])
	assert_eq(r.game_version, "2.3.4")
	assert_eq(r.engine_version, "1.0.0")
	assert_eq(r.kind, "bug")
	assert_eq(r.level, "Basic")
	assert_eq(r.platform, OS.get_name())
	assert_eq(str(r.report_id).length(), 36, "a report has its own number")
	var all := JSON.stringify(r)
	for private in ["Zed", "user://", "res://", ROOT, "hp", "humanity"]:
		assert_false(private in all, "a report holds no '%s'" % private)


func test_gather_with_a_discord_name() -> void:
	var r := FeedbackReport.gather(db, game, "Hi", "1.0.0", "  some_user#1\n ")
	assert_eq(r.keys(), FeedbackReport.KEYS + ["discord"], "the name only when given")
	assert_eq(r.discord, "some_user#1")
	assert_false(FeedbackReport.gather(db, game, "Hi", "1.0.0", "   ").has("discord"), "an empty name stays anonymous")
	assert_eq(FeedbackReport.clean_name("x".repeat(60)).length(), FeedbackReport.NAME_LIMIT)


func test_gather_in_an_event_and_free_to_act() -> void:
	var free := FeedbackReport.gather(db, game, "x", "1.0.0")
	assert_eq(free.playing, {}, "nothing plays: the player is free to act")
	game.runner.start_event("storm")
	var r := FeedbackReport.gather(db, game, "x", "1.0.0")
	assert_eq(r.playing.get("event"), "storm")
	assert_eq(r.playing.get("title"), "The Storm")


func test_gather_without_a_game() -> void:
	var r := FeedbackReport.gather(db, null, "Crash on start", "1.0.0")
	assert_eq(r.keys(), FeedbackReport.KEYS)
	assert_eq(r.place_id, "")
	assert_eq(r.steps, [])
	assert_eq(r.game_version, "2.3.4")


func test_the_player_name_is_blotted_out() -> void:
	game.set_value("player.name", "Ann")
	game.runner.act("talk", "ann")
	var r := FeedbackReport.gather(db, game, "Ann is my name", "1.0.0")
	assert_eq(r.text, "Ann is my name", "the player's own text is theirs")
	assert_eq(r.steps, ["talk to [player]"])
	assert_eq(r.playing.get("title", ""), "Talking with [player]")
	game.runner.choose(1)
	assert_eq(FeedbackReport.gather(db, game, "", "1.0.0").steps, ["talk to [player]", "choose: Say your name"])


func test_text_is_limited() -> void:
	var r := FeedbackReport.gather(db, game, "y".repeat(5000), "1.0.0")
	assert_eq(r.text.length(), FeedbackReport.TEXT_LIMIT)


func test_webhook_problems() -> void:
	assert_ne(FeedbackReport.webhook_problem(""), "", "no address")
	assert_ne(FeedbackReport.webhook_problem(FeedbackReport.PLACEHOLDER), "", "the placeholder")
	assert_ne(FeedbackReport.webhook_problem("  https://x/PASTE-WEBHOOK-URL-HERE "), "", "the placeholder anywhere")
	assert_ne(FeedbackReport.webhook_problem("http://discord.com/api/webhooks/1/a"), "", "not https")
	assert_eq(FeedbackReport.webhook_problem("https://discord.com/api/webhooks/1/abc"), "")
	assert_string_contains(FeedbackReport.webhook_problem(""), "cannot be sent yet")


func test_discord_message() -> void:
	game.runner.act("go", "north")
	var r := FeedbackReport.gather(db, game, "Stuck @everyone", "1.0.0")
	var m := FeedbackReport.discord_message(r)
	assert_eq(m.keys(), ["embeds", "allowed_mentions"])
	assert_eq(e_title(m), "Bug report")
	assert_eq(m.allowed_mentions, {"parse": []}, "the player's text pings no one")
	var e: Dictionary = m.embeds[0]
	assert_eq(e.description, "Stuck @everyone")
	assert_eq(e.fields.map(func(f): return f.name), ["From", "Place", "Playing now", "Last steps"])
	assert_eq(e.fields[0].value, "Anonymous")
	assert_eq(e.fields[1].value, "Barn (barn)")
	assert_eq(e.fields[2].value, "nothing (the player was free to act)")
	assert_eq(e.fields[3].value, "```\n1. go north\n```")
	assert_eq(e.footer.text, "Game 2.3.4 · Engine 1.0.0 · %s · %s" % [OS.get_name(), str(r.report_id).left(8)])
	var named := FeedbackReport.discord_message(FeedbackReport.gather(db, game, "Hi", "1.0.0", "turtle"))
	assert_eq(named.embeds[0].fields[0].value, "turtle")


func e_title(message: Dictionary) -> String:
	return str(message.embeds[0].title)


func test_discord_message_stays_within_limits() -> void:
	var f := game.feedback
	for i in 30:
		f.note("`%d` %s" % [i, "z".repeat(200)])
	var r := FeedbackReport.gather(db, game, "w".repeat(9000), "1.0.0", "n".repeat(90), {"state": true, "save": true})
	assert_eq(r.steps.size(), 30, "with the state every remembered step is shared")
	r.place_name = "p".repeat(3000)  # longer than any place name, to test the cut
	var e: Dictionary = FeedbackReport.discord_message(r).embeds[0]
	assert_true(str(e.description).length() <= FeedbackReport.DESCRIPTION_LIMIT)
	for field: Dictionary in e.fields:
		assert_true(str(field.value).length() <= FeedbackReport.FIELD_LIMIT, "field %s within 1,024" % field.name)
	assert_true(FeedbackReport.embed_length(e) <= FeedbackReport.EMBED_LIMIT)
	assert_false("``" + "`" in str(e.fields[3].value).trim_prefix("```").trim_suffix("```"), "a step cannot close the code block")
	assert_eq(JSON.parse_string(JSON.stringify(FeedbackReport.discord_message(r))) is Dictionary, true)


func test_describe_action() -> void:
	assert_eq(FeedbackReport.describe_action("go", "north"), "go north")
	assert_eq(FeedbackReport.describe_action("talk", "adam"), "talk to adam")
	assert_eq(FeedbackReport.describe_action("explore", ""), "explore")
	assert_eq(FeedbackReport.describe_action("smell_self", "x"), "smell yourself")
	assert_eq(FeedbackReport.describe_action("drop_all", "water"), "drop all water")


func test_summary_lists_what_is_sent() -> void:
	var s := FeedbackReport.summary(FeedbackReport.gather(db, game, "x", "1.0.0"))
	assert_eq(s.split("\n").size(), 6)
	assert_string_contains(s, "From: Anonymous")
	assert_string_contains(s, "Kind: Bug")
	assert_string_contains(s, "Place: Field (field)")
	assert_string_contains(s, "Versions: Game 2.3.4 · Engine 1.0.0, on " + OS.get_name())
	var full := FeedbackReport.summary(FeedbackReport.gather(db, game, "x", "1.0.0", "", {"state": true, "save": true}))
	assert_string_contains(full, "The state of your game")
	assert_string_contains(full, "A save of this moment")


func test_text_shown_last_is_remembered_and_not_saved() -> void:
	var f := FeedbackReport.new()
	for i in 25:
		f.note_text("line %d" % i)
	assert_eq(f.lines.size(), FeedbackReport.LINES_KEPT)
	assert_eq(f.lines[0], "line 5")
	f.note_text("and more", true)
	assert_eq(f.lines[-1], "line 24 and more", "the rest of a sentence joins its line")
	f.note_text("x".repeat(900))
	assert_eq(str(f.lines[-1]).length(), FeedbackReport.LINE_LIMIT)
	game.runner.act("talk", "ann")
	assert_true("Ann waves." in game.feedback.lines, "what the game showed")
	assert_true("Talking with Ann" in game.feedback.lines, "titles too")
	assert_false("Ann waves." in JSON.stringify(game.save_dict()), "not part of a save")


func _played() -> void:
	game.set_value("player.name", "Zed")
	game.set_value("pet.mood", "Zed's best friend")
	game.set_value("pet.tricks", 3)
	game.set_value("notes.list", [[0, "my private note"]])
	game.state.inventory["apple"] = 2
	game.state.feats.append("keen")
	game.runner.start("naming")
	game.runner.enter_text("Rexfordia")
	game.take_output()
	game.runner.act("talk", "ann")


func test_state_of_the_game() -> void:
	_played()
	var client := {"window": "1280x720", "ui_scale": 125, "theme": "Dark", "debug_tools": true, "own_packs": ["p"], "path": "/home/someone"}
	var r := FeedbackReport.gather(db, game, "Broken", "1.0.0", "", {"kind": "suggestion", "id": "abc", "state": true, "client": client})
	assert_eq(r.keys(), FeedbackReport.KEYS + ["state"])
	assert_eq(r.level, "State")
	assert_eq(r.kind, "suggestion")
	assert_eq(r.report_id, "abc")
	var st: Dictionary = r.state
	assert_eq(st.packs.loaded, [{"id": "p", "version": "2.3.4", "own": true}])
	assert_eq(str(st.packs.set_id).length(), 12)
	assert_eq(st.session.turn, game.state.turn)
	assert_eq(st.session.day, 1)
	assert_eq(st.session.status, "choice")
	assert_eq(st.session.choices, ["Wave back", "Say your name"])
	assert_eq(st.rng.state, game.rng.get_state(), "the random numbers' state, and gathering rolled nothing")
	assert_eq(st.player.hp, game.value("player.hp"))
	assert_true(st.player.has("strength"))
	assert_false(st.player.has("name"), "never the name")
	assert_eq(st.inventory, {"apple": 2})
	assert_eq(st.feats, ["keen"])
	assert_eq(st.here.characters, ["ann"])
	assert_eq(st.values.get("pet.tricks"), 3, "a changed value")
	assert_eq(st.values.get("pet.name"), FeedbackReport.TYPED, "never what the player typed")
	assert_eq(st.values.get("pet.mood"), "[player]'s best friend", "the name is blotted out of a text")
	assert_false(st.values.has("player.name"))
	assert_false(st.values.has("notes.list"), "never the journal's notes")
	assert_eq(st.screen, {"window": "1280x720", "ui_scale": 125, "theme": "Dark", "debug_tools": true}, "only what is listed")
	assert_true("Ann waves." in st.recent_text)
	assert_true(st.running.frames.any(func(f): return f.get("pid", "") == "ann#talk"), "what is running")
	assert_eq(r.omitted, [])
	var all := JSON.stringify(FeedbackReport.document(r))
	for private in ["Zed", "Rexfordia", "my private note", "user://", ROOT, "/home/someone"]:
		assert_false(private in all, "a report holds no '%s'" % private)
	assert_eq(JSON.parse_string(all).state.values["pet.tricks"], 3.0, "it is all plain JSON")


func test_state_says_what_is_left_out() -> void:
	for i in FeedbackReport.VALUES_LIMIT + 7:
		game.state.values["x.v%05d" % i] = i
	var r := FeedbackReport.gather(db, game, "x", "1.0.0", "", {"state": true})
	assert_eq(r.state.values.size(), FeedbackReport.VALUES_LIMIT)
	assert_eq(r.omitted.size(), 1)
	assert_string_contains(r.omitted[0], "values: ")
	assert_string_contains(FeedbackReport.summary(r), "Left out: values")


func test_state_and_save_need_a_game() -> void:
	var r := FeedbackReport.gather(db, null, "Crash on start", "1.0.0", "", {"state": true, "save": true})
	assert_eq(r.keys(), FeedbackReport.KEYS)
	assert_eq(r.level, "Basic")


func test_save_loads_and_holds_nothing_private() -> void:
	_played()
	game.runner.choose(0)
	var r := FeedbackReport.gather(db, game, "Broken", "1.0.0", "", {"id": "12345678-aaaa", "state": true, "save": true})
	assert_eq(r.keys(), FeedbackReport.KEYS + ["state", "save"])
	assert_eq(r.level, "State and save")
	var text := JSON.stringify(r.save)
	for private in ["Zed", "Rexfordia", "my private note"]:
		assert_false(private in text, "a save holds no '%s'" % private)
	assert_eq(r.save.meta.id, "save-report-12345678")
	assert_eq(game.value("player.name"), "Zed", "the game itself is untouched")
	assert_eq(game.value("pet.name"), "Rexfordia")
	var loaded := Game.new(db, 9)
	assert_true(loaded.load_dict(JSON.parse_string(text)), "it loads like any save")
	assert_eq(loaded.value("player.name"), "Player")
	assert_eq(loaded.value("pet.tricks"), 3)
	assert_eq(loaded.state.inventory, {"apple": 2})
	assert_eq(loaded.state.location, "field")
	loaded.dispose()
	assert_false(FeedbackReport.gather(db, game, "x", "1.0.0", "", {"save": true}).has("save"), "no save without the state")


func test_receiver_gets_the_whole_report_and_discord_the_short_one() -> void:
	_played()
	var r := FeedbackReport.gather(db, game, "Broken", "1.0.0", "turtle", {"state": true, "save": true})
	var body := FeedbackReport.receiver_body(r)
	assert_eq(body.keys(), ["schema_version", "report_id", "kind", "diagnostics_level", "text", "discord", "build", "context", "state", "omitted", "save"])
	assert_eq(body.schema_version, 1)
	assert_eq(body.diagnostics_level, "State and save")
	assert_eq(body.build, {"game_version": "2.3.4", "engine_version": "1.0.0", "godot_version": r.godot_version, "platform": OS.get_name()})
	assert_eq(body.context.place_id, "field")
	assert_eq(JSON.parse_string(body.save).meta.id, FeedbackReport.save_id(r.report_id), "the save as the text of a save file")
	assert_false(FeedbackReport.document(r).has("save"), "the document itself is without the save")
	var m := FeedbackReport.discord_message(r)
	var sent := JSON.stringify(m)
	assert_false("pet.tricks" in sent, "Discord never gets the state")
	assert_false("apple" in sent)
	assert_eq(m.embeds[0].fields[-1].name, "More")
	assert_string_contains(m.embeds[0].fields[-1].value, "and a save")
	assert_string_contains(m.embeds[0].footer.text, str(r.report_id).left(8))
	assert_eq(e_title(FeedbackReport.discord_message(FeedbackReport.gather(db, game, "x", "1.0.0", "", {"kind": "feedback"}))), "Feedback")
	var basic := FeedbackReport.receiver_body(FeedbackReport.gather(db, game, "Hi", "1.0.0"))
	assert_eq(basic.keys(), ["schema_version", "report_id", "kind", "diagnostics_level", "text", "build", "context", "omitted"])


func test_destinations() -> void:
	var hook := "https://discord.com/api/webhooks/1/abc"
	var intake := "https://reports.example.org/intake/abc"
	assert_eq(FeedbackReport.destinations(hook, intake), [{"to": "discord", "url": hook}, {"to": "receiver", "url": intake}])
	assert_eq(FeedbackReport.destinations(hook), [{"to": "discord", "url": hook}])
	assert_eq(FeedbackReport.destinations("", " " + intake + " "), [{"to": "receiver", "url": intake}], "a receiver alone is enough")
	assert_eq(FeedbackReport.destinations(FeedbackReport.PLACEHOLDER, "http://example.org"), [])
	assert_eq(FeedbackReport.sending_problem(hook, ""), "")
	assert_eq(FeedbackReport.sending_problem("", intake), "")
	assert_string_contains(FeedbackReport.sending_problem("", ""), "cannot be sent yet")
	assert_string_contains(FeedbackReport.sending_problem("", "http://example.org"), "not a secure web address")


func test_report_numbers() -> void:
	var a := FeedbackReport.new_id()
	assert_eq(a.length(), 36)
	assert_eq(a[14], "4")
	assert_ne(a, FeedbackReport.new_id())
	assert_eq(FeedbackReport._scrub("Could not read /home/someone/x.json or C:\\Users\\me\\y today"), "Could not read [path] or [path] today")


# --- The window (no network: answers are shown as the request would give them) ---

func _view(url: String, receiver: String = "", has_game: bool = false) -> ReportView:
	ReportView.draft = ""
	ReportView.discord = ""
	ReportView.with_state = true
	ReportView.with_save = false
	var footer := HBoxContainer.new()
	add_child_autofree(footer)
	var view := ReportView.new()
	add_child_autofree(view)
	view.setup(url, func(text: String, name: String, options: Dictionary) -> Dictionary:
			return FeedbackReport.gather(db, game, text, "1.0.0", name, options),
		footer, func(): pass, receiver, has_game)
	return view


func test_window_without_an_address_cannot_send() -> void:
	for url in ["", FeedbackReport.PLACEHOLDER]:
		var view := _view(url)
		view.field.text = "It broke."
		view._on_text_changed()
		assert_false(view.can_send())
		assert_true(view.send_button.disabled, "Send is off")
		assert_string_contains(view.status.text, "cannot be sent yet")
		assert_false(view.send(), "nothing is sent")
		assert_false(view.sending)


func test_window_counts_limits_and_keeps_the_draft() -> void:
	var view := _view("https://discord.com/api/webhooks/1/abc")
	assert_true(view.send_button.disabled, "nothing written yet")
	view.field.text = "q".repeat(1600)
	view._on_text_changed()
	assert_eq(view.field.text.length(), FeedbackReport.TEXT_LIMIT)
	assert_eq(view.counter.text, "1,500 / 1,500")
	assert_false(view.send_button.disabled)
	assert_eq(ReportView.draft.length(), FeedbackReport.TEXT_LIMIT, "kept for the next opening")
	view.name_field.text = "turtle"
	view.name_field.text_changed.emit("turtle")
	assert_eq(view._report().discord, "turtle")


func test_window_answers() -> void:
	var view := _view("https://discord.com/api/webhooks/1/abc")
	view.field.text = "Text to keep"
	view._on_text_changed()
	view.set_sending()
	assert_eq(view.status.text, "Sending…")
	assert_false(view.field.editable)
	view.show_result(HTTPRequest.RESULT_CANT_CONNECT, 0)
	assert_string_contains(view.status.text, "could not reach")
	assert_eq(view.field.text, "Text to keep", "the text is kept to try again")
	assert_true(view.field.editable)
	assert_false(view.send_button.disabled)
	view.show_result(HTTPRequest.RESULT_SUCCESS, 400)
	assert_string_contains(view.status.text, "refused")
	view.show_result(HTTPRequest.RESULT_SUCCESS, 429)
	assert_string_contains(view.status.text, "busy")
	view.show_result(HTTPRequest.RESULT_SUCCESS, 204)
	assert_eq(view.status.text, "Thank you, your report was sent.")
	assert_eq(ReportView.draft, "", "a sent report is no draft")
	assert_false(view.send_button.visible)
	assert_eq(view.close_button.text, "Close")


func test_window_offers_the_state_only_with_a_game_and_a_receiver() -> void:
	var discord_only := _view("https://discord.com/api/webhooks/1/abc", "", true)
	assert_false(discord_only.state_box.visible, "Discord never gets the state: nothing to offer")
	assert_false(discord_only._report().has("state"))
	var no_game := _view("https://discord.com/api/webhooks/1/abc", "https://reports.example.org/intake/abc", false)
	assert_false(no_game.state_box.visible, "no game, no state")
	var view := _view("https://discord.com/api/webhooks/1/abc", "https://reports.example.org/intake/abc", true)
	assert_eq(view.targets.map(func(t): return t.to), ["discord", "receiver"])
	assert_true(view.state_box.visible)
	assert_true(view.state_box.button_pressed, "the state is on until the player says no")
	assert_false(view.save_box.button_pressed, "a save only when the player says yes")
	var r := view._report()
	assert_true(r.has("state"))
	assert_false(r.has("save"))
	assert_eq(r.level, "State")
	view.save_box.button_pressed = true
	assert_eq(view._report().level, "State and save")
	view.state_box.button_pressed = false
	assert_true(view.save_box.disabled, "no save without the state")
	r = view._report()
	assert_eq(r.level, "Basic")
	assert_false(r.has("save"))
	assert_false(ReportView.with_state, "the box stays as the player left it")
	view.kind_buttons["suggestion"].pressed.emit()
	assert_eq(view._report().kind, "suggestion")
	assert_eq(view._report().report_id, view.report_id, "one number for every try")


func test_window_shows_exactly_what_is_sent() -> void:
	var view := _view("https://discord.com/api/webhooks/1/abc", "https://reports.example.org/intake/abc", true)
	view._toggle_details()
	assert_true(view.details.visible)
	assert_true(view.state_view.visible)
	assert_string_contains(view.details.text, "The state of your game")
	assert_string_contains(view.details.text, "not posted there")
	assert_eq(JSON.parse_string(view.state_view.text), JSON.parse_string(JSON.stringify(FeedbackReport.document(view._report()))),
		"the whole report, as it goes to the receiver")
	view.state_box.button_pressed = false
	assert_false(view.state_view.visible, "without the state there is no more than the lines")
	assert_false("The state of your game" in view.details.text)


func test_window_thanks_when_one_address_took_the_report() -> void:
	var view := _view("https://discord.com/api/webhooks/1/abc", "https://reports.example.org/intake/abc", true)
	view.field.text = "It broke."
	view._posting = view._report()
	view.set_sending()
	view.targets[0].state = "sending"
	view.targets[1].state = "sending"
	view.targets[1].tries = 2  # the receiver already had its second try
	view._on_completed(HTTPRequest.RESULT_SUCCESS, 204, PackedStringArray(), PackedByteArray(), 0)
	assert_true(view.sending, "waiting for the other address")
	view._on_completed(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray(), 1)
	assert_true(view.sent, "one address has the report")
	assert_eq(view.status.text, "Thank you, your report was sent.")


func test_window_says_why_when_no_address_took_the_report() -> void:
	var view := _view("https://discord.com/api/webhooks/1/abc", "https://reports.example.org/intake/abc", true)
	view.field.text = "It broke."
	view._posting = view._report()
	view.set_sending()
	view.targets[0].state = "sending"
	view.targets[1].state = "sending"
	view._on_completed(HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(), PackedByteArray(), 0)
	view._on_completed(HTTPRequest.RESULT_SUCCESS, 500, PackedStringArray(), PackedByteArray(), 1)
	assert_false(view.sent)
	assert_string_contains(view.status.text, "busy")
	assert_false(view.state_box.disabled, "the boxes can be changed before the next try")


func test_notice_markup() -> void:
	var main_script: GDScript = load("res://ui/main.gd")
	var bb: String = main_script.notice_bbcode("A **bold** and *quiet* [note]. See https://discord.gg/abc.")
	assert_string_contains(bb, "[b]bold[/b]")
	assert_string_contains(bb, "[i]quiet[/i]")
	assert_string_contains(bb, "[lb]note]")
	assert_string_contains(bb, "[url=https://discord.gg/abc]")
	assert_false("abc.]" in bb, "the full stop after an address is not part of it")


func test_validator_checks_the_pack_fields() -> void:
	var folder := ROOT + "_check"
	for sub in ["g", "o"]:
		DirAccess.make_dir_recursive_absolute(folder + "/" + sub)
	var files := {
		"g/pack.fsc": "== pack g\nname: G\nversion: 1.0.0\ntitle: G\nfeedback webhook: http://example.org/hook\nfeedback receiver: http://example.org/intake\nstart notice title: Hi\n",
		"o/pack.fsc": "== pack o\nname: O\nversion: 1.0.0\nrequires: g\nfeedback webhook: https://example.org/hook\n",
	}
	for name: String in files:
		var fa := FileAccess.open(folder + "/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var check := ContentDB.new()
	check.load_folders([folder])  # validates too
	var errors := check.errors().map(func(d): return d.message)
	var warnings := check.diagnostics.filter(func(d): return d.severity == "warning").map(func(d): return d.message)
	assert_eq(errors.filter(func(m): return "https://" in m).size(), 2, "an address that is not https is an error, the receiver's too")
	assert_eq(warnings.filter(func(m): return "counts only in the game's own pack" in m).size(), 1, "another pack's address is not used")
	assert_eq(warnings.filter(func(m): return "shows nothing" in m).size(), 1, "a title without a notice")
	var fa := FileAccess.open(folder + "/g/pack.fsc", FileAccess.WRITE)
	fa.store_string("== pack g\nname: G\nversion: 1.0.0\ntitle: G\nfeedback webhook: PASTE-WEBHOOK-URL-HERE\n")
	fa.close()
	check = ContentDB.new()
	check.load_folders([folder])
	assert_eq(check.diagnostics.filter(func(d): return "not set yet" in d.message).size(), 1, "the placeholder is a warning")
