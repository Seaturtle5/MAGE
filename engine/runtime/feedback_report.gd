class_name FeedbackReport
extends RefCounted
## A player's bug report or feedback: what it holds and the message sent.
##
## The game keeps the player's last few steps here (`note`), in a small ring
## buffer that is not saved with the game. `gather` collects exactly what a
## report shares: the player's text, the place and what plays there now, the
## last steps, and the game's and the engine's version. Nothing else: no
## player name (it is blotted out of everything gathered), no save, no stats,
## no system information and no file paths. `discord_message` formats a
## report as a Discord webhook message; the interface sends it. The player
## may add their Discord username so the game's makers can reply; without it
## the report is anonymous.

const STEPS_KEPT := 10  ## how many steps a report shares
const TEXT_LIMIT := 1500  ## the most characters a player can write
const NAME_LIMIT := 40  ## the most characters of the Discord username
const STEP_LIMIT := 80  ## the most characters of one step
## The address a game pack writes until it has a real one (`feedback webhook:`).
const PLACEHOLDER := "PASTE-WEBHOOK-URL-HERE"
## Discord's limits: an embed's description, a field's value, all of an embed.
const DESCRIPTION_LIMIT := 4096
const FIELD_LIMIT := 1024
const EMBED_LIMIT := 6000
## The keys of a gathered report, and no others (plus "discord" when the
## player gives their Discord username).
const KEYS := ["text", "place_id", "place_name", "playing", "steps", "game_version", "engine_version"]

## How actions read in the list of steps ("talk" with "adam" is "talk to adam").
const ACTION_WORDS := {"talk": "talk to", "sex": "sex with", "look": "look at", "give": "give to",
	"travel": "travel to", "hunt": "hunt for", "hunt_name": "hunt for", "actions": "actions with", "smell_item": "smell",
	"smell_place": "smell the place", "smell_self": "smell yourself", "take_all": "take everything",
	"drop_all": "drop all", "drop_everything": "drop everything", "junk_all": "junk all"}

var steps: Array = []  ## [{"text": String, "count": int}], oldest first
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


## The validator's checks of the pack fields: `feedback webhook`, `start
## notice` and `start notice title` count only in the game pack (the one with
## a `title:`); the address is a secure web address or the placeholder.
static func check(v) -> void:
	var game_pack := str(v.db.branding().get("pack", ""))
	for p: Dictionary in v.db.packs:
		var d: FscParser.Definition = p.def
		v._path = d.path
		for key in ["feedback webhook", "start notice", "start notice title"]:
			if d.fields.has(key) and p.id != game_pack:
				v._warn(d.fields[key].line, "'%s' counts only in the game's own pack (the one with a 'title:'), which is '%s'; this one is not used." % [key, game_pack] if game_pack != "" else "'%s' counts only in the game's own pack, the one with a 'title:'; this pack has none, so it is not used." % key)
		if p.id != game_pack or not d.fields.has("feedback webhook"):
			continue
		var url := str(d.fields["feedback webhook"].value).strip_edges()
		if PLACEHOLDER in url or url == "":
			v._warn(d.fields["feedback webhook"].line, "The feedback webhook is not set yet: players' reports cannot be sent until it holds the Discord webhook address.")
		elif not url.begins_with("https://") or " " in url:
			v._err(d.fields["feedback webhook"].line, "A feedback webhook is a secure web address starting with https:// (a Discord webhook address).")
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


## Exactly what a report shares (the keys in KEYS, and "discord" when the
## player wrote a Discord username). `game` may be null (no game started
## yet); `db` gives the game pack's version.
static func gather(db: ContentDB, game, text: String, engine_version: String, discord: String = "") -> Dictionary:
	var out := {"text": text.strip_edges().left(TEXT_LIMIT), "place_id": "", "place_name": "", "playing": {},
		"steps": [], "game_version": str(db.branding().get("version", "")) if db != null else "",
		"engine_version": engine_version}
	var contact := clean_name(discord)
	if contact != "":
		out["discord"] = contact
	if game == null or game.state == null:
		return out
	var loc: String = game.state.location
	out.place_id = loc
	out.place_name = game.content.typed_value("location", loc, "name", loc) if loc != "" else ""
	out.playing = playing_now(game)
	out.steps = game.feedback.step_lines()
	# The player's name never leaves with a report, not even inside a title or a choice.
	var name := str(game.value("player.name")).strip_edges()
	if name.length() >= 2:
		var blot := func(s: String) -> String: return _blot(s, name)
		out.place_name = blot.call(out.place_name)
		for key in out.playing:
			out.playing[key] = blot.call(str(out.playing[key]))
		out.steps = out.steps.map(blot)
	return out


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


## `text` with every whole-word `name` (any case) replaced by "[player]".
static func _blot(text: String, name: String) -> String:
	var re := RegEx.create_from_string("(?i)\\b" + _regex_quote(name) + "\\b")
	return re.sub(text, "[player]", true) if re.is_valid() else text.replace(name, "[player]")


static func _regex_quote(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if c in "\\^$.|?*+()[]{}" else c
	return out


## A report as plain lines, as the player may read it before sending.
static func summary(report: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("From: " + _from(report))
	lines.append("Place: " + _place(report))
	lines.append("Playing now: " + _playing(report))
	lines.append("Last steps: " + ("; ".join(report.steps) if not report.steps.is_empty() else "none"))
	lines.append("Versions: " + _versions(report))
	return "\n".join(lines)


## The Discord webhook message for a report: one embed with the player's
## text, the place, what plays now, the last steps and the versions, within
## Discord's limits. Mentions in the player's text never ping anyone.
static func discord_message(report: Dictionary) -> Dictionary:
	var text := str(report.text).strip_edges()
	var steps := ""
	for i in report.steps.size():
		steps += "%d. %s\n" % [i + 1, str(report.steps[i]).replace("`", "'")]
	var fields := [
		{"name": "From", "value": _clip(_from(report), FIELD_LIMIT), "inline": false},
		{"name": "Place", "value": _clip(_place(report), FIELD_LIMIT), "inline": true},
		{"name": "Playing now", "value": _clip(_playing(report), FIELD_LIMIT), "inline": true},
		{"name": "Last steps", "value": _clip("```\n%s```" % steps, FIELD_LIMIT, "\n…```") if steps != "" else "none", "inline": false},
	]
	var embed := {
		"title": "Report",
		"description": _clip(text if text != "" else "(no text)", DESCRIPTION_LIMIT),
		"fields": fields,
		"footer": {"text": _versions(report)},
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


## `text` cut to `limit` characters, ending in `tail` when cut.
static func _clip(text: String, limit: int, tail: String = "…") -> String:
	if text.length() <= limit:
		return text
	return text.left(limit - tail.length()) + tail
