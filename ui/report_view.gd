class_name ReportView
extends VBoxContainer
## The Report a bug window: what a report shares, a text box, and Send.
##
## The report itself is gathered by the engine (FeedbackReport.gather, passed
## in as `gather`); this view only shows it and posts it to the game pack's
## Discord webhook (`feedback webhook:`) with an HTTPRequest. The text stays
## while the player tries again, and between openings until it is sent.

const EXPLANATION := "Sending a report shares only what you write below, the scene you are in, your last few steps in the game and the versions of the game and its engine. Nothing else is sent, and nothing that identifies you unless you add your Discord username below."
const USER_AGENT := "MAGE-Report/1.0"
const TIMEOUT := 20.0

static var draft := ""  ## what the player has written and not sent yet
static var discord := ""  ## the Discord username the player gave, kept for the next report

var url := ""
var gather: Callable  ## (text, discord username) -> the report (FeedbackReport.gather)
var field: TextEdit
var name_field: LineEdit
var counter: Label
var status: Label
var details: Label
var details_link: LinkButton
var send_button: Button
var close_button: Button
var http: HTTPRequest
var sending := false
var sent := false


## Builds the view. Send and Cancel go in `footer` (the window's button row);
## `close` closes the window.
func setup(webhook: String, gather_report: Callable, footer: HBoxContainer, close: Callable) -> void:
	url = webhook.strip_edges()
	gather = gather_report
	add_theme_constant_override("separation", 12)
	var intro := FsTheme.label(EXPLANATION, 16, FsTheme.TEXT_DIM)
	add_child(intro)
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
		if details.visible:
			_fill_details())
	contact.add_child(name_field)
	add_child(contact)
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
	http = HTTPRequest.new()
	http.timeout = TIMEOUT
	http.request_completed.connect(_on_completed)
	add_child(http)
	var problem := FeedbackReport.webhook_problem(url)
	if problem != "":
		show_status(problem, FsTheme.BAD)
	_on_text_changed()
	field.grab_focus.call_deferred()


## Whether the game has somewhere to send reports to.
func can_send() -> bool:
	return FeedbackReport.webhook_problem(url) == ""


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
	if details.visible:
		_fill_details()


static func _thousands(n: int) -> String:
	return str(n) if n < 1000 else "%d,%03d" % [n / 1000, n % 1000]


func _toggle_details() -> void:
	details.visible = not details.visible
	details_link.text = "Hide what is sent" if details.visible else "Show exactly what is sent"
	if details.visible:
		_fill_details()


func _fill_details() -> void:
	details.text = "Besides your text, the report holds:\n" + FeedbackReport.summary(_report())


## The report as it would be sent now.
func _report() -> Dictionary:
	return gather.call(field.text, name_field.text)


func show_status(text: String, color: Color = FsTheme.TEXT_DIM) -> void:
	status.text = text
	status.add_theme_color_override("font_color", color)


## Posts the report. Returns false (with the reason shown) when it cannot.
func send() -> bool:
	if sending or sent:
		return false
	var problem := FeedbackReport.webhook_problem(url)
	if problem != "":
		show_status(problem, FsTheme.BAD)
		return false
	if field.text.strip_edges() == "":
		show_status("Please write a few words first.", FsTheme.BAD)
		return false
	var body := JSON.stringify(FeedbackReport.discord_message(_report()))
	var headers := PackedStringArray(["Content-Type: application/json", "User-Agent: " + USER_AGENT])
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		show_result(HTTPRequest.RESULT_CANT_CONNECT, 0)
		return false
	set_sending()
	return true


## The window while a report is on its way.
func set_sending() -> void:
	sending = true
	field.editable = false
	name_field.editable = false
	send_button.disabled = true
	show_status("Sending…", FsTheme.TEXT_DIM)


func _on_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	show_result(result, code)


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
	if result != HTTPRequest.RESULT_SUCCESS:
		show_status("The report could not be sent: the game could not reach the report server. Check your internet connection and try again.", FsTheme.BAD)
	elif code == 429:
		show_status("The report server is busy right now. Please wait a minute and try again.", FsTheme.BAD)
	else:
		show_status("The report server refused the report (error %d). Your text is kept; please try again later." % code, FsTheme.BAD)
	_on_text_changed()
