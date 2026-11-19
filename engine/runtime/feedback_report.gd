class_name FeedbackReport
extends RefCounted
## A player's bug report or feedback: what it holds and the messages sent.
##
## The game keeps the player's last steps (`note`) and the lines of text shown
## last (`note_text`) here, in small ring buffers that are not saved with the
## game. `gather` collects what every report shares: the player's text, what
## kind of report it is, the place and what plays there now, the last few
## steps, the game's, the engine's and Godot's version and the operating
## system's name. `add_state` adds the state of the game when the player
## allows it (packs, the player's values, items, every changed value, events,
## settings, the screen, all remembered steps and the text shown last), and
## `add_save` a save of the moment. Never in a report: the player's name
## (blotted out of every text gathered), the journal's notes, what the player
## typed into a value (`~ ask`), file paths and anything about the computer
## beyond the operating system's name. The player may add their Discord
## username so the game's makers can reply; without it the report is anonymous.
##
## A report goes to the game's Discord webhook (`discord_message`: the short
## report only) and to the game's own report receiver (`receiver_body`: the
## whole report as JSON, the only place the state and a save go to). The
## interface sends.

const SCHEMA := 1  ## the version of the report's JSON layout
const STEPS_KEPT := 30  ## how many steps are remembered (shared with the game's state)
const STEPS_BASIC := 10  ## how many steps a report without the game's state shares
const LINES_KEPT := 20  ## how many lines of text shown last are remembered
const LINE_LIMIT := 300  ## the most characters of one such line
const TEXT_LIMIT := 1500  ## the most characters a player can write
const NAME_LIMIT := 40  ## the most characters of the Discord username
const STEP_LIMIT := 80  ## the most characters of one step
const VALUES_LIMIT := 5000  ## the most changed values, and the most events, a report lists
const SAVE_LIMIT := 3000000  ## a save larger than this (as JSON text) is left out
## The address a game pack writes until it has a real one (`feedback webhook:`).
const PLACEHOLDER := "PASTE-WEBHOOK-URL-HERE"
## Discord's limits: an embed's description, a field's value, all of an embed.
const DESCRIPTION_LIMIT := 4096
const FIELD_LIMIT := 1024
const EMBED_LIMIT := 6000
## The kinds of report, and how each is named.
const KINDS := {"bug": "Bug", "suggestion": "Suggestion", "feedback": "Feedback"}
## How much a report holds: the basic report, with the game's state, and with a save too.
const LEVELS := ["Basic", "State", "State and save"]
## The keys of a gathered report, and no others (plus "discord" when the
## player gives their Discord username, "state" and "save" when added).
const KEYS := ["report_id", "kind", "level", "text", "place_id", "place_name", "playing", "steps",
	"game_version", "engine_version", "godot_version", "platform", "omitted"]
## What the interface may tell about the screen (`add_state`'s `client`).
const CLIENT_KEYS := ["window", "ui_scale", "theme", "fullscreen", "debug_tools", "own_packs"]
## In place of a text the player typed.
const TYPED := "(typed by the player)"

## How actions read in the list of steps ("talk" with "adam" is "talk to adam").
const ACTION_WORDS := {"talk": "talk to", "sex": "sex with", "look": "look at", "give": "give to",
	"travel": "travel to", "hunt": "hunt for", "hunt_name": "hunt for", "actions": "actions with", "smell_item": "smell",
	"smell_place": "smell the place", "smell_self": "smell yourself", "take_all": "take everything",
	"drop_all": "drop all", "drop_everything": "drop everything", "junk_all": "junk all"}

var steps: Array = []  ## [{"text": String, "count": int}], oldest first
var lines: Array = []  ## the text shown last as plain lines, oldest first
var choice_labels: Array = []  ## the choices on screen, so a choice is noted by its words
var scene_title := ""  ## the title of the scene shown last


## Notes one step of the player's ("go north"). The same step again counts up
## instead of taking a new line; only the last STEPS_KEPT are kept.
func note(text: String) -> void:
	var clean := text.strip_edges().replace("\n", " ").left(STEP_LIMIT)
	if clean == "":
		return
	if not steps.is_empty() and steps[-1].text == clean:
		steps[-1].count += 1
		return
	steps.append({"text": clean, "count": 1})
	while steps.size() > STEPS_KEPT:
		steps.pop_front()


## Notes a line of text the game showed; `joins` adds it to the line before
## (the rest of a sentence). Only the last LINES_KEPT are kept.
func note_text(text: String, joins: bool = false) -> void:
	var clean := text.strip_edges().replace("\n", " ")
	if clean == "":
		return
	if joins and not lines.is_empty():
		lines[-1] = (str(lines[-1]) + " " + clean).left(LINE_LIMIT)
		return
	lines.append(clean.left(LINE_LIMIT))
	while lines.size() > LINES_KEPT:
		lines.pop_front()


## Notes the choice at `index` of the choices shown last ("choose: Take it").
func note_choice(index: int) -> void:
	if index >= 0 and index < choice_labels.size():
		note("choose: " + str(choice_labels[index]))
	else:
		note("choose: option %d" % (index + 1))


## The steps as lines, oldest first ("explore (3 times)").
func step_lines() -> Array:
	return steps.map(func(s): return str(s.text) if int(s.count) == 1 else "%s (%d times)" % [s.text, s.count])


## How an action and its argument read as a step: "go north", "talk to adam".
static func describe_action(action: String, arg: String) -> String:
	var words: String = ACTION_WORDS.get(action, action.replace("_", " "))
	if action in ["smell_place", "smell_self", "take_all", "drop_everything"]:
		return words
	return words + (" " + arg if arg != "" else "")


## The validator's checks of the pack fields: `feedback webhook`, `feedback
## receiver`, `start notice` and `start notice title` count only in the game
## pack (the one with a `title:`); an address is a secure web address or the
## placeholder.
static func check(v) -> void:
	var game_pack := str(v.db.branding().get("pack", ""))
	for p: Dictionary in v.db.packs:
		var d: FscParser.Definition = p.def
		v._path = d.path
		for key in ["feedback webhook", "feedback receiver", "start notice", "start notice title"]:
			if d.fields.has(key) and p.id != game_pack:
				v._warn(d.fields[key].line, "'%s' counts only in the game's own pack (the one with a 'title:'), which is '%s'; this one is not used." % [key, game_pack] if game_pack != "" else "'%s' counts only in the game's own pack, the one with a 'title:'; this pack has none, so it is not used." % key)
		if p.id != game_pack:
			continue
		for key: String in ["feedback webhook", "feedback receiver"]:
			if not d.fields.has(key):
				continue
			var url := str(d.fields[key].value).strip_edges()
			var what := "the Discord webhook address" if key == "feedback webhook" else "the address of the game's report receiver"
			if PLACEHOLDER in url or url == "":
				v._warn(d.fields[key].line, "The %s is not set yet: players' reports cannot be sent there until it holds %s." % [key, what])
			elif not url.begins_with("https://") or " " in url:
				v._err(d.fields[key].line, "A %s is a secure web address starting with https:// (%s)." % [key, what])
		if d.fields.has("start notice title") and not d.fields.has("start notice"):
			v._warn(d.fields["start notice title"].line, "A start notice title without a 'start notice:' shows nothing.")


## Why reports cannot be sent to this address, in plain words; "" when they can.
static func webhook_problem(url: String) -> String:
	var u := url.strip_edges()
	if u == "" or PLACEHOLDER in u:
		return "Reports cannot be sent yet: this game has no address to send them to."
	if not u.begins_with("https://"):
		return "Reports cannot be sent: the game's report address is not a secure web address."
	return ""


## Where a report goes: the game's Discord webhook and its own report
## receiver, each when it has a usable address ([{"to": "discord" or
## "receiver", "url"}]). A report is sent to all of them.
static func destinations(webhook: String, receiver: String = "") -> Array:
	var out: Array = []
	if webhook_problem(webhook) == "":
		out.append({"to": "discord", "url": webhook.strip_edges()})
	if webhook_problem(receiver) == "":
		out.append({"to": "receiver", "url": receiver.strip_edges()})
	return out


## Why reports cannot be sent at all, in plain words; "" when at least one
## address can take them.
static func sending_problem(webhook: String, receiver: String = "") -> String:
	if not destinations(webhook, receiver).is_empty():
		return ""
	if webhook.strip_edges() == "" and receiver.strip_edges() != "":
		return webhook_problem(receiver)
	return webhook_problem(webhook)


## A new report's own number (a random UUID): the same for every try at
## sending one report, so a receiver takes it once. It says nothing about the
## player or the computer.
static func new_id() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


## What every report shares (the keys in KEYS, and "discord" when the player
## wrote a Discord username). `game` may be null (no game started yet); `db`
## gives the game pack's version. `options`: "kind" (one of KINDS, a bug
## unless said), "id" (the report's number, a new one unless given), "state"
## (true adds the state of the game, see `add_state`, with "client" for what
## the interface tells about the screen) and "save" (true adds a save too).
static func gather(db: ContentDB, game, text: String, engine_version: String, discord: String = "", options: Dictionary = {}) -> Dictionary:
	var kind := str(options.get("kind", "bug"))
	var id := str(options.get("id", ""))
	var out := {"report_id": id if id != "" else new_id(), "kind": kind if KINDS.has(kind) else "bug", "level": LEVELS[0],
		"text": text.strip_edges().left(TEXT_LIMIT), "place_id": "", "place_name": "", "playing": {},
		"steps": [], "game_version": str(db.branding().get("version", "")) if db != null else "",
		"engine_version": engine_version, "godot_version": str(Engine.get_version_info().get("string", "")),
		"platform": OS.get_name(), "omitted": []}
	var contact := clean_name(discord)
	if contact != "":
		out["discord"] = contact
	if game == null or game.state == null:
		return out
	var loc: String = game.state.location
	out.place_id = loc
	out.place_name = game.content.typed_value("location", loc, "name", loc) if loc != "" else ""
	out.playing = playing_now(game)
	var all: Array = game.feedback.step_lines()
	out.steps = all.slice(maxi(0, all.size() - STEPS_BASIC))
	# The player's name never leaves with a report, not even inside a title or a choice.
	var name := _player_name(game)
	if name != "":
		var blot := func(s: String) -> String: return _blot(s, name)
		out.place_name = blot.call(out.place_name)
		for key in out.playing:
			out.playing[key] = blot.call(str(out.playing[key]))
		out.steps = out.steps.map(blot)
	if options.get("state", false):
		add_state(out, game, options.get("client", {}))
		if options.get("save", false):
			add_save(out, game)
	return out


## Adds the state of the game to a gathered report (see `state_of`), with
## every remembered step instead of the last few. `client` is what the
## interface tells about the screen (the keys in CLIENT_KEYS). Without a game
## the report stays as it is.
static func add_state(report: Dictionary, game, client: Dictionary = {}) -> Dictionary:
	if game == null or game.state == null:
		return report
	var omitted: Array = report.omitted
	report["state"] = state_of(game, client, omitted)
	report.level = LEVELS[1]
	report.steps = _blot_all(game.feedback.step_lines(), _player_name(game))
	return report


## Adds a save of the moment to a report that holds the game's state (see
## `save_of`); a save too large to send is left out and named in "omitted".
static func add_save(report: Dictionary, game) -> Dictionary:
	if game == null or game.state == null or not report.has("state"):
		return report
	var save := save_of(game, str(report.report_id))
	if JSON.stringify(save).length() > SAVE_LIMIT:
		var omitted: Array = report.omitted
		omitted.append("save: left out, it is larger than %d MB" % (SAVE_LIMIT / 1000000))
		return report
	report["save"] = save
	report.level = LEVELS[2]
	return report


## The state of the game as a report shares it: the packs, the session, the
## random numbers' state, every value of the player, feats, items, companions,
## every value that differs from how it starts, the events touched, the
## content settings, the screen, the text shown last and what is running.
## Lists longer than VALUES_LIMIT are cut, and `omitted` says by how much.
static func state_of(game, client: Dictionary = {}, omitted: Array = []) -> Dictionary:
	var db: ContentDB = game.content
	var st: GameState = game.state
	var name := _player_name(game)
	var out := {}
	# The packs, in the order they loaded.
	var loaded: Array = []
	var manifest: PackedStringArray = []
	var own: Array = client.get("own_packs", [])
	for p: Dictionary in db.packs:
		var version := db.field_value(str(p.id), "version", "0")
		var entry := {"id": str(p.id), "version": version}
		if str(p.get("art", "")) != "":
			entry["art"] = str(p.art)
		if p.id in db.art_off:
			entry["off"] = true
		if p.id in own:
			entry["own"] = true
		loaded.append(entry)
		manifest.append("%s@%s%s" % [p.id, version, " off" if p.id in db.art_off else ""])
	out["packs"] = {"set_id": "\n".join(manifest).sha1_text().left(12), "loaded": loaded}
	out["session"] = {"scenario": str(game.settings.get("scenario", "")), "modes": game.settings.get("mode", []),
		"turn": st.turn, "actions": st.actions, "day": game.day(), "time": game.time_slot(), "ending": st.ending,
		"status": str(game.runner.status) if game.runner != null else "",
		"choices": _blot_all(game.feedback.choice_labels, name) if game.runner != null and game.runner.status == "choice" else []}
	# The state the random numbers are in now; reading it rolls nothing.
	out["rng"] = {"algorithm": "xoshiro128**", "state": game.rng.get_state()}
	var player := {}
	for key: String in game.PLAYER_DEFAULTS:
		if key != "name":
			player[key] = game.value("player." + key)
	for path: String in db.values:
		if path.begins_with("player.") and path != "player.name":
			player[path.substr(7)] = _shared(db, path, game.value(path), name)
	out["player"] = player
	out["feats"] = st.feats.duplicate()
	out["traits"] = st.traits.duplicate(true)
	out["inventory"] = st.inventory.duplicate()
	out["equipped"] = st.equipped.duplicate()
	out["wielded"] = st.wielded
	out["companions"] = st.companions.duplicate(true)
	var conditions := {}
	for id: String in st.conditions:
		conditions[id] = int(st.conditions[id].get("remaining", 0))
	out["conditions"] = conditions
	var here: Array = []
	for who: String in db.all_of("character"):
		if game.where(who) == st.location:
			here.append(who)
	out["here"] = {"characters": here, "items": st.ground.get(st.location, {}).duplicate()}
	out["moved"] = _cut(st.char_location, omitted, "moved")  # the characters that are not where they live
	out["storage"] = st.storage.duplicate(true)
	out["scheduled"] = st.scheduled.duplicate(true)
	# Every value that differs from how it starts (the game stores only those).
	var paths: Array = st.values.keys().filter(func(path: String) -> bool: return path != "player.name" and path != NotesSystem.LIST)
	paths.sort()
	var values := {}
	for path: String in paths.slice(0, VALUES_LIMIT):
		values[path] = _shared(db, path, st.values[path], name)
	out["values"] = values
	_note_cut(omitted, "values", paths.size())
	out["times"] = _cut(st.stamps, omitted, "times")
	out["events"] = _cut(st.events, omitted, "events")
	out["settings"] = {"banned": game.settings.get("banned", []), "warded": game.settings.get("warded", []),
		"levels": game.settings.get("levels", {}), "interests": game.settings.get("interests", {})}
	var screen := {}
	for key: String in CLIENT_KEYS:
		if client.has(key) and key != "own_packs":
			screen[key] = client[key]
	out["screen"] = screen
	out["recent_text"] = _blot_all(game.feedback.lines, name)
	var running := {"last_fight": str(game.last_fight)}
	if game.runner != null:
		running["frames"] = game.runner.frames.map(func(f: Dictionary) -> Dictionary: return _scalars(f))
	if game.in_fight():
		running["fight"] = _scalars(st.combat)
	running["warnings"] = game.warnings.slice(maxi(0, game.warnings.size() - 20)).map(func(w: Variant) -> String: return _blot(_scrub(str(w)), name))
	out["running"] = running
	return out


## A save of the moment as a report shares it: the game's own save data with
## the player's name replaced, the journal's notes taken out and every text
## the player typed replaced. It loads like any save (put the file in the
## saves folder under its own name).
static func save_of(game, report_id: String = "") -> Dictionary:
	var save: Dictionary = game.save_dict().duplicate(true)
	var name := _player_name(game)
	var values: Dictionary = save.state.values
	values.erase(NotesSystem.LIST)
	for path: String in values.keys():
		var v: Variant = values[path]
		if not v is String:
			continue
		if path == "player.name":
			values[path] = "Player"
		elif game.content.asked.has(path) and v != "":
			values[path] = "Name"
		elif name != "" and str(v).findn(name) >= 0:
			values[path] = _blot(str(v), name, "Player")
	var meta: Dictionary = game.save_summary()
	meta.player = "Player"
	meta.id = save_id(report_id)
	meta.kind = "Save"
	meta.name = "Report " + report_id.left(8)
	meta.saved_at = int(Time.get_unix_time_from_system())
	save["meta"] = meta
	return save


## The name a report's save goes by (its file is `<this>.json`).
static func save_id(report_id: String) -> String:
	return "save-report-" + report_id.left(8)


## The report as one JSON document, without the save.
static func document(report: Dictionary) -> Dictionary:
	var doc := {"schema_version": SCHEMA, "report_id": report.report_id, "kind": report.kind,
		"diagnostics_level": report.level, "text": report.text}
	if str(report.get("discord", "")) != "":
		doc["discord"] = report.discord
	doc["build"] = {"game_version": report.game_version, "engine_version": report.engine_version,
		"godot_version": report.godot_version, "platform": report.platform}
	doc["context"] = {"place_id": report.place_id, "place_name": report.place_name, "playing": report.playing,
		"steps": report.steps}
	if report.has("state"):
		doc["state"] = report.state
	doc["omitted"] = report.omitted
	return doc


## What a game's own report receiver gets (`feedback receiver:`), as the JSON
## body of a POST: the document and, when there is a save, the text of the
## save file under "save" (a receiver stores it as it is).
static func receiver_body(report: Dictionary) -> Dictionary:
	var doc := document(report)
	if report.has("save"):
		doc["save"] = JSON.stringify(report.save)
	return doc


## What plays now: the scene's title, the event, the innermost scene or menu,
## a captivity and the fight, each only when there is one ({} when the player
## is free to act).
static func playing_now(game) -> Dictionary:
	var out := {}
	var runner = game.runner
	if runner == null or (runner.frames.is_empty() and runner.status == "idle"):
		return out
	if game.feedback.scene_title != "":
		out["title"] = game.feedback.scene_title
	var event: String = runner.current_event()
	if event != "":
		out["event"] = event
	for i in range(runner.frames.size() - 1, -1, -1):
		var f: Dictionary = runner.frames[i]
		if f.kind == "script" and not out.has("scene"):
			out["scene"] = str(f.pid)
		elif f.kind == "menu" and not out.has("scene"):
			out["scene"] = "menu " + str(f.id)
		elif f.kind == "captivity" and not out.has("captivity"):
			out["captivity"] = str(f.id)
	if game.in_fight():
		out["fight"] = str(game.state.combat.get("creature", ""))
	return out


## A Discord username as a report carries it: one line, no code marks, at
## most NAME_LIMIT characters.
static func clean_name(name: String) -> String:
	return name.replace("\n", " ").replace("\r", " ").replace("`", "").strip_edges().left(NAME_LIMIT).strip_edges()


## The player's name as it is blotted out ("" when too short to look for).
static func _player_name(game) -> String:
	var name := str(game.value("player.name")).strip_edges()
	return name if name.length() >= 2 else ""


## `text` with every whole-word `name` (any case) replaced by `with`.
static func _blot(text: String, name: String, with: String = "[player]") -> String:
	if name == "":
		return text
	var re := RegEx.create_from_string("(?i)\\b" + _regex_quote(name) + "\\b")
	return re.sub(text, with, true) if re.is_valid() else text.replace(name, with)


## A value with the player's name blotted out of every text in it (the keys
## of a dictionary stay: they are IDs).
static func _blot_all(v: Variant, name: String) -> Variant:
	if name == "":
		return v
	if v is String:
		return _blot(v, name) if str(v).findn(name) >= 0 else v
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return _blot_all(x, name))
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = _blot_all(v[k], name)
		return out
	return v


## A game value as a report shares it: a text the player typed is replaced,
## the player's name blotted out of any other.
static func _shared(db: ContentDB, path: String, v: Variant, name: String) -> Variant:
	if v is String and v != "" and db.asked.has(path):
		return TYPED
	return _blot_all(v, name)


## File paths taken out of a message.
static func _scrub(text: String) -> String:
	var re := RegEx.create_from_string("(?:[A-Za-z]:[\\\\/]|/home/|/Users/|/tmp/|/var/|user://|res://)[^\\s'\"]*")
	return re.sub(text, "[path]", true)


## The plain values of a dictionary (numbers, texts and flags), without what
## is nested in it.
static func _scalars(d: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in d:
		var v: Variant = d[k]
		if v is String or v is int or v is float or v is bool:
			out[k] = v
	return out


## The first VALUES_LIMIT entries of a dictionary, by key; a cut is noted.
static func _cut(d: Dictionary, omitted: Array, what: String) -> Dictionary:
	_note_cut(omitted, what, d.size())
	if d.size() <= VALUES_LIMIT:
		return d.duplicate(true)
	var keys: Array = d.keys()
	keys.sort()
	var out := {}
	for k: Variant in keys.slice(0, VALUES_LIMIT):
		out[k] = d[k]
	return out


static func _note_cut(omitted: Array, what: String, size: int) -> void:
	if size > VALUES_LIMIT:
		omitted.append("%s: %d of %d left out" % [what, size - VALUES_LIMIT, size])


static func _regex_quote(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if c in "\\^$.|?*+()[]{}" else c
	return out


## A report as plain lines, as the player may read it before sending.
static func summary(report: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("From: " + _from(report))
	lines.append("Kind: " + str(KINDS.get(report.kind, report.kind)))
	lines.append("Place: " + _place(report))
	lines.append("Playing now: " + _playing(report))
	lines.append("Last steps: " + ("; ".join(report.steps) if not report.steps.is_empty() else "none"))
	lines.append("Versions: %s, on %s" % [_versions(report), report.platform])
	if report.has("state"):
		var st: Dictionary = report.state
		lines.append("The state of your game (in full below): the packs (%d), your character's values (%d), feats (%d) and items (%d), the values that changed in your game (%d), its events (%d), your content settings, the screen and the last lines of text shown (%d)." % [
			st.packs.loaded.size(), st.player.size(), st.feats.size(), st.inventory.size(), st.values.size(), st.events.size(), st.recent_text.size()])
	if report.has("save"):
		lines.append("A save of this moment (%s): everything the game remembers of this playthrough, with your character's name replaced and your journal's notes taken out." % _size(JSON.stringify(report.save).length()))
	for note: String in report.omitted:
		lines.append("Left out: " + note)
	return "\n".join(lines)


## The Discord webhook message for a report: one embed with the player's
## text, the place, what plays now, the last steps and the versions, within
## Discord's limits. The state of the game and a save never go to Discord
## (only a line saying that the receiver got them); the report's number in
## the footer is the one the receiver gets. Mentions in the player's text
## never ping anyone.
static func discord_message(report: Dictionary) -> Dictionary:
	var text := str(report.text).strip_edges()
	var steps := ""
	var last: Array = report.steps.slice(maxi(0, report.steps.size() - STEPS_BASIC))
	for i in last.size():
		steps += "%d. %s\n" % [i + 1, str(last[i]).replace("`", "'")]
	var fields := [
		{"name": "From", "value": _clip(_from(report), FIELD_LIMIT), "inline": false},
		{"name": "Place", "value": _clip(_place(report), FIELD_LIMIT), "inline": true},
		{"name": "Playing now", "value": _clip(_playing(report), FIELD_LIMIT), "inline": true},
		{"name": "Last steps", "value": _clip("```\n%s```" % steps, FIELD_LIMIT, "\n…```") if steps != "" else "none", "inline": false},
	]
	if report.has("state"):
		fields.append({"name": "More", "value": "The state of the game%s went to the report receiver." % (" and a save" if report.has("save") else ""), "inline": false})
	var kind := str(KINDS.get(report.kind, "Bug"))
	var embed := {
		"title": kind + " report" if report.kind == "bug" else kind,
		"description": _clip(text if text != "" else "(no text)", DESCRIPTION_LIMIT),
		"fields": fields,
		"footer": {"text": "%s · %s · %s" % [_versions(report), report.platform, str(report.report_id).left(8)]},
	}
	return {"embeds": [embed], "allowed_mentions": {"parse": []}}


## How many characters of an embed count against Discord's limit of 6,000.
static func embed_length(embed: Dictionary) -> int:
	var n := str(embed.get("title", "")).length() + str(embed.get("description", "")).length()
	n += str(embed.get("footer", {}).get("text", "")).length()
	for f: Dictionary in embed.get("fields", []):
		n += str(f.name).length() + str(f.value).length()
	return n


static func _from(report: Dictionary) -> String:
	return str(report.discord) if str(report.get("discord", "")) != "" else "Anonymous"


static func _place(report: Dictionary) -> String:
	if str(report.place_id) == "":
		return "no game started"
	return "%s (%s)" % [report.place_name, report.place_id]


static func _playing(report: Dictionary) -> String:
	var p: Dictionary = report.playing
	if p.is_empty():
		return "nothing (the player was free to act)"
	var parts: PackedStringArray = []
	for key in ["title", "event", "scene", "captivity", "fight"]:
		if p.has(key):
			parts.append(("\"%s\"" % p[key]) if key == "title" else "%s %s" % [key, p[key]])
	return ", ".join(parts)


static func _versions(report: Dictionary) -> String:
	return "Game %s · Engine %s" % [str(report.game_version) if str(report.game_version) != "" else "?",
		str(report.engine_version) if str(report.engine_version) != "" else "?"]


## A number of characters as a size ("12 kB").
static func _size(n: int) -> String:
	return "%d kB" % maxi(1, n / 1000) if n < 1000000 else "%.1f MB" % (n / 1000000.0)


## `text` cut to `limit` characters, ending in `tail` when cut.
static func _clip(text: String, limit: int, tail: String = "…") -> String:
	if text.length() <= limit:
		return text
	return text.left(limit - tail.length()) + tail
