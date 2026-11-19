class_name ReportView
extends VBoxContainer
## The Report a bug window: what a report shares, what kind it is, a text
## box, what may go with it, and Send.
##
## The report itself is gathered by the engine (FeedbackReport.gather, passed
## in as `gather`); this view only shows it and posts it with HTTPRequests:
## the short report to the game pack's Discord webhook (`feedback webhook:`),
## the whole report to the game's own report receiver (`feedback receiver:`).
## The state of the game and a save are offered only when there is a game and
## a receiver to take them. The text stays while the player tries again, and
## between openings until it is sent.

const EXPLANATION := "Sending a report shares what you write below, the scene you are in, your last few steps in the game, the versions of the game and its engine, and the name of your operating system. Your character's name is never sent, and nothing that identifies you unless you add your Discord username below."
const STATE_LABEL := "Include the state of my game"
const STATE_HINT := "Your packs, your character's values, feats and items, everything that has changed in your game, your content settings, the size of the window and the last lines of text. It often shows us the cause without asking you. Names you gave to others in the game may be in it."
const SAVE_LABEL := "Attach a save of this moment"
const SAVE_HINT := "Lets us load your game as it is now. Your character's name is replaced and your journal's notes are taken out."
const PRIVATE_HINT := "Both are kept with the makers' own list of reports and are not posted to Discord."
const KIND_LABELS := {"bug": "A bug", "suggestion": "A suggestion", "feedback": "Other feedback"}
const USER_AGENT := "MAGE-Report/2.0"
const TIMEOUT := 20.0
const RECEIVER_TIMEOUT := 60.0  ## the whole report with a save may be large

static var draft := ""  ## what the player has written and not sent yet
static var discord := ""  ## the Discord username the player gave, kept for the next report
static var with_state := true  ## the state box, as the player left it
static var with_save := false  ## the save box, as the player left it

var targets: Array = []  ## where the report goes: {"to", "url", "http", "state", "tries", "result", "code"}
var gather: Callable  ## (text, discord username, options) -> the report (FeedbackReport.gather)
var report_id := ""  ## this report's number, the same for every try
var kind := "bug"
var offers_state := false  ## a game is running and a receiver takes its state
var field: TextEdit
var name_field: LineEdit
var counter: Label
var status: Label
var details: Label
var details_link: LinkButton
var state_view: TextEdit
var state_box: CheckButton
var save_box: CheckButton
var kind_buttons: Dictionary = {}
var send_button: Button
var close_button: Button
var refresh: Timer
var sending := false
var sent := false
var _posting: Dictionary = {}  ## the report on its way


## Builds the view. Send and Cancel go in `footer` (the window's button row);
## `close` closes the window. `receiver` is the game's own report receiver;
## `has_game` says whether a game is running (its state can be shared).
func setup(webhook: String, gather_report: Callable, footer: HBoxContainer, close: Callable, receiver: String = "",
		has_game: bool = false) -> void:
	gather = gather_report
	report_id = FeedbackReport.new_id()
	for t: Dictionary in FeedbackReport.destinations(webhook, receiver):
		var http := HTTPRequest.new()
		http.timeout = TIMEOUT if t.to == "discord" else RECEIVER_TIMEOUT
		http.request_completed.connect(_on_completed.bind(targets.size()))
		add_child(http)
		targets.append({"to": t.to, "url": t.url, "http": http, "state": "idle", "tries": 0, "result": 0, "code": 0})
	offers_state = has_game and targets.any(func(t: Dictionary) -> bool: return t.to == "receiver")
	add_theme_constant_override("separation", 12)
	var intro := FsTheme.label(EXPLANATION, 16, FsTheme.TEXT_DIM)
	add_child(intro)
	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for id: String in KIND_LABELS:
		var b := Button.new()
		b.text = KIND_LABELS[id]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == kind
		b.custom_minimum_size = Vector2(150, 40)
		b.pressed.connect(_set_kind.bind(id))
		kinds.add_child(b)
		kind_buttons[id] = b
	add_child(kinds)
	add_child(FsTheme.heading("What happened, or what would you like to tell us?", 13, FsTheme.TEXT_FAINT))
	field = TextEdit.new()
	field.custom_minimum_size = Vector2(0, 130)
	field.size_flags_vertical = SIZE_EXPAND_FILL
	field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	field.placeholder_text = "For a bug: what you did, what you expected and what happened instead."
	field.add_theme_font_size_override("font_size", 17)
	field.text = draft
	field.text_changed.connect(_on_text_changed)
	add_child(field)
	var under := HBoxContainer.new()
	status = FsTheme.label("", 15, FsTheme.TEXT_DIM)
	status.size_flags_horizontal = SIZE_EXPAND_FILL
	under.add_child(status)
	counter = FsTheme.label("", 14, FsTheme.TEXT_FAINT)
	counter.autowrap_mode = TextServer.AUTOWRAP_OFF
	counter.size_flags_vertical = SIZE_SHRINK_BEGIN
	under.add_child(counter)
	add_child(under)
	var contact := HBoxContainer.new()
	contact.add_theme_constant_override("separation", 12)
	var contact_label := FsTheme.label("Discord username (optional, so we can reply)", 15, FsTheme.TEXT_DIM)
	contact_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	contact.add_child(contact_label)
	name_field = LineEdit.new()
	name_field.max_length = FeedbackReport.NAME_LIMIT
	name_field.placeholder_text = "Leave empty to stay anonymous"
	name_field.custom_minimum_size = Vector2(300, 40)
	name_field.size_flags_horizontal = SIZE_EXPAND_FILL
	name_field.text = discord
	name_field.text_changed.connect(func(t: String) -> void:
		discord = t
		_refresh_details())
	contact.add_child(name_field)
	add_child(contact)
	state_box = _tick(STATE_LABEL, STATE_HINT, with_state, func(on: bool) -> void:
		with_state = on
		save_box.disabled = not on
		_refresh_details())
	save_box = _tick(SAVE_LABEL, SAVE_HINT + (" " + PRIVATE_HINT if targets.size() > 1 else ""), with_save, func(on: bool) -> void:
		with_save = on
		_refresh_details())
	save_box.disabled = not with_state
	details_link = LinkButton.new()
	details_link.text = "Show exactly what is sent"
	details_link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	details_link.add_theme_color_override("font_color", FsTheme.ACCENT)
	details_link.add_theme_color_override("font_hover_color", FsTheme.TEXT_STRONG)
	details_link.add_theme_font_size_override("font_size", 15)
	details_link.pressed.connect(_toggle_details)
	add_child(details_link)
	details = FsTheme.label("", 13, FsTheme.TEXT_DIM)
	details.visible = false
	add_child(details)
	state_view = TextEdit.new()
	state_view.editable = false
	state_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	state_view.custom_minimum_size = Vector2(0, 240)
	state_view.add_theme_font_size_override("font_size", 13)
	state_view.visible = false
	add_child(state_view)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(spacer)
	close_button = Button.new()
	close_button.text = "Cancel"
	close_button.custom_minimum_size = Vector2(130, 44)
	close_button.pressed.connect(close)
	footer.add_child(close_button)
	send_button = Button.new()
	send_button.text = "Send"
	send_button.custom_minimum_size = Vector2(150, 44)
	send_button.add_theme_font_override("font", FsTheme.strong_font())
	send_button.add_theme_stylebox_override("normal", FsTheme.box(FsTheme.recede(FsTheme.ACCENT_DIM, 0.1)))
	send_button.pressed.connect(send)
	footer.add_child(send_button)
	refresh = Timer.new()
	refresh.one_shot = true
	refresh.wait_time = 0.4
	refresh.timeout.connect(_fill_details)
	add_child(refresh)
	if targets.is_empty():
		show_status(FeedbackReport.sending_problem(webhook, receiver), FsTheme.BAD)
	_on_text_changed()
	field.grab_focus.call_deferred()


## A switch with its name and a line saying what it shares, as in Settings;
## shown only when the state of a game can be sent.
func _tick(text: String, hint: String, on: bool, changed: Callable) -> CheckButton:
	var card := FsTheme.card(FsTheme.SURFACE_2, 10)
	card.visible = offers_state
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.add_child(FsTheme.label(text, 16))
	words.add_child(FsTheme.label(hint, 13, FsTheme.TEXT_DIM))
	row.add_child(words)
	var box := CheckButton.new()
	box.button_pressed = on
	box.text = "Yes" if on else "No"
	box.size_flags_vertical = SIZE_SHRINK_CENTER
	box.visible = offers_state
	box.toggled.connect(func(now: bool) -> void:
		box.text = "Yes" if now else "No"
		changed.call(now))
	row.add_child(box)
	add_child(card)
	return box


## Whether the game has somewhere to send reports to.
func can_send() -> bool:
	return not targets.is_empty()


func _set_kind(id: String) -> void:
	kind = id
	_refresh_details()


## Keeps the text within the limit, counts it and keeps it as the draft.
func _on_text_changed() -> void:
	if field.text.length() > FeedbackReport.TEXT_LIMIT:
		var line := field.get_caret_line()
		var column := field.get_caret_column()
		field.text = field.text.left(FeedbackReport.TEXT_LIMIT)
		field.set_caret_line(line)
		field.set_caret_column(column)
	if not sent:
		draft = field.text
	var n := field.text.length()
	counter.text = "%s / %s" % [_thousands(n), _thousands(FeedbackReport.TEXT_LIMIT)]
	counter.add_theme_color_override("font_color", FsTheme.BAD if n >= FeedbackReport.TEXT_LIMIT else FsTheme.TEXT_FAINT)
	send_button.disabled = sending or sent or not can_send() or field.text.strip_edges() == ""
	if details.visible and refresh.is_inside_tree():
		refresh.start()  # once the typing pauses: the state of a long game takes a moment to gather


static func _thousands(n: int) -> String:
	return str(n) if n < 1000 else "%d,%03d" % [n / 1000, n % 1000]


func _toggle_details() -> void:
	details.visible = not details.visible
	details_link.text = "Hide what is sent" if details.visible else "Show exactly what is sent"
	_refresh_details()
	if details.visible and is_inside_tree():
		_scroll_to_details.call_deferred()


## Brings what is sent into view: it opens below the window's edge.
func _scroll_to_details() -> void:
	var around: Node = get_parent()
	while around != null and not around is ScrollContainer:
		around = around.get_parent()
	if around == null:
		return
	await get_tree().process_frame  # the window has laid the new lines out
	var scroll := around as ScrollContainer
	scroll.scroll_vertical += int(details_link.get_global_rect().position.y - scroll.get_global_rect().position.y)


func _refresh_details() -> void:
	if details.visible:
		_fill_details()
	else:
		state_view.visible = false


## What is sent, in full: the short report as lines and, with the state of
## the game, the whole report as it goes to the receiver.
func _fill_details() -> void:
	var report := _report()
	var lines := "Besides your text, the report holds:\n" + FeedbackReport.summary(report)
	if targets.size() > 1:
		lines += "\nTo Discord: your text and the lines above up to \"Versions\"." + (" The state of your game" + (" and the save" if report.has("save") else "") + " are not posted there." if report.has("state") else "")
	details.text = lines
	state_view.visible = details.visible and report.has("state")
	if state_view.visible:
		var scroll := state_view.scroll_vertical
		state_view.text = JSON.stringify(FeedbackReport.document(report), "  ", false)
		state_view.scroll_vertical = scroll


## The report as it would be sent now.
func _report() -> Dictionary:
	var state := offers_state and state_box.button_pressed
	return gather.call(field.text, name_field.text,
		{"kind": kind, "id": report_id, "state": state, "save": state and save_box.button_pressed})


func show_status(text: String, color: Color = FsTheme.TEXT_DIM) -> void:
	status.text = text
	status.add_theme_color_override("font_color", color)


## Posts the report to every address that has not taken it yet. Returns
## false (with the reason shown) when it cannot.
func send() -> bool:
	if sending or sent:
		return false
	if targets.is_empty():
		show_status(FeedbackReport.webhook_problem(""), FsTheme.BAD)
		return false
	if field.text.strip_edges() == "":
		show_status("Please write a few words first.", FsTheme.BAD)
		return false
	_posting = _report()
	var started := false
	for t: Dictionary in targets:
		if t.state != "ok":
			t.tries = 0
			started = _post(t) or started
	if not started:
		show_result(HTTPRequest.RESULT_CANT_CONNECT, 0)
		return false
	set_sending()
	return true


## Posts the report to one address: the short message to Discord, the whole
## report to the receiver.
func _post(t: Dictionary) -> bool:
	var message: Dictionary = FeedbackReport.discord_message(_posting) if t.to == "discord" else FeedbackReport.receiver_body(_posting)
	var headers := PackedStringArray(["Content-Type: application/json", "User-Agent: " + USER_AGENT])
	t.tries += 1
	var http: HTTPRequest = t.http
	var err := http.request(str(t.url), headers, HTTPClient.METHOD_POST, JSON.stringify(message, "", false))
	t.state = "sending" if err == OK else "failed"
	if err != OK:
		t.result = HTTPRequest.RESULT_CANT_CONNECT
		t.code = 0
	return err == OK


## The window while a report is on its way.
func set_sending() -> void:
	sending = true
	field.editable = false
	name_field.editable = false
	send_button.disabled = true
	for b: Button in kind_buttons.values() + [state_box, save_box]:
		b.disabled = true
	show_status("Sending…", FsTheme.TEXT_DIM)


func _on_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, index: int) -> void:
	var t: Dictionary = targets[index]
	t.result = result
	t.code = code
	t.state = "ok" if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 else "failed"
	_settle()


## Once every address has answered: thanks when at least one took the report
## (an address that failed gets one more try first), or the reason.
func _settle() -> void:
	if targets.any(func(t: Dictionary) -> bool: return t.state == "sending"):
		return
	var failed := targets.filter(func(t: Dictionary) -> bool: return t.state == "failed")
	if failed.size() == targets.size():
		show_result(int(failed[0].result), int(failed[0].code))
		return
	var again := failed.filter(func(t: Dictionary) -> bool: return int(t.tries) < 2)
	if again.is_empty():
		show_result(HTTPRequest.RESULT_SUCCESS, 200)
		return
	for t: Dictionary in again:
		t.state = "sending"
		_post_again.call_deferred(t)


func _post_again(t: Dictionary) -> void:
	if not _post(t):
		_settle()


## The answer of the report server: thanks, or a plain reason with the text
## kept so the player can try again.
func show_result(result: int, code: int) -> void:
	sending = false
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		sent = true
		draft = ""
		field.editable = false
		name_field.editable = false
		send_button.visible = false
		close_button.text = "Close"
		close_button.grab_focus.call_deferred()
		show_status("Thank you, your report was sent.", FsTheme.GOOD)
		return
	field.editable = true
	name_field.editable = true
	for id: String in kind_buttons:
		kind_buttons[id].disabled = false
	state_box.disabled = false
	save_box.disabled = not state_box.button_pressed
	if result != HTTPRequest.RESULT_SUCCESS:
		show_status("The report could not be sent: the game could not reach the report server. Check your internet connection and try again.", FsTheme.BAD)
	elif code == 429:
		show_status("The report server is busy right now. Please wait a minute and try again.", FsTheme.BAD)
	else:
		show_status("The report server refused the report (error %d). Your text is kept; please try again later." % code, FsTheme.BAD)
	_on_text_changed()
