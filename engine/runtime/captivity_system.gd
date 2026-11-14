class_name CaptivitySystem
extends RefCounted
## Captivity: the player is held (swallowed, bound, enveloped) and each round
## picks Struggle, Oblige or Abide, Endure or Recover, after the original's
## bound states (Core Mechanics/Bound State Universals.i7x and the loops that
## copy its template). Content declares `== captivity <id>` with scripts for
## each step; the engine runs the rounds, keeps the shared numbers and shows
## the menu and status line. A scene starts one with `play <id>` or `-> <id>`.
##
## Values (reset when a captivity starts and ends):
##   captivity.lust      lust toward a climax (starts at the player's libido)
##   captivity.struggle  struggle progress; reaching `escape at` frees the player
##   captivity.round     rounds so far
##   captivity.enduring, captivity.obliging, captivity.recover   flags
##   captivity.segment, captivity.mod, captivity.mod2, captivity.counter,
##   captivity.timer     free numbers for stages and timers (the original's
##                       boundsegment, boundmod, boundmod2, boundcounter, bsextimer)

const VALUES := ["lust", "struggle", "round", "enduring", "obliging", "recover", "segment", "mod", "mod2",
	"counter", "timer"]
const DEFAULT_OBLIGING := "player.hp > 0 or player.humanity < 50"


static func field(game, id: String, name: String, fallback: String = "") -> String:
	return game.content.typed_value("captivity", id, name, fallback)


static func reset(game) -> void:
	for v in VALUES + ["recover_chance"]:
		game.state.values.erase("captivity." + v)


static func begin(game, id: String) -> void:
	reset(game)
	game.state.values["captivity.lust"] = int(game.value("player.libido"))
	game.state.values["captivity.recover_chance"] = -1
	game.captivity_exit = ""


## The original's checkboundrecover: a chance that grows each round until it
## succeeds, then starts over.
static func roll_recover(game) -> void:
	var v: Dictionary = game.state.values
	if not Condition._truthy(v.get("captivity.recover", false)):
		v["captivity.recover_chance"] = int(v.get("captivity.recover_chance", -1)) + 1
	var chance := int(v.get("captivity.recover_chance", -1))
	if chance > 0 and game.rng.chance(chance, 9):
		v["captivity.recover"] = true
		v["captivity.recover_chance"] = -1


static func escape_at(game, id: String) -> int:
	var text := field(game, id, "escape at", "3")
	var e := Expr.parse(text)
	return 3 if e.has("error") else int(Expr.evaluate(e, game))


static func number(game, name: String) -> int:
	return int(game.state.values.get("captivity." + name, 0))


static func flag(game, name: String) -> bool:
	return Condition._truthy(game.state.values.get("captivity." + name, false))


## The line under the menu: sanity, lust, hunger, thirst and a struggle bar.
static func status_line(game, id: String) -> String:
	var custom := field(game, id, "status")
	if custom != "":
		var t := TextTemplate.compile(custom)
		return "" if t.has("error") else TextTemplate.plain(game.render(t))
	var width := maxi(1, escape_at(game, id) - 1) if field(game, id, "escape at") != "" else maxi(1, number(game, "struggle"))
	var done := clampi(number(game, "struggle"), 0, width)
	return "Sanity: %d/100   Lust: %d/%s   Hunger: %d   Thirst: %d   Struggle: [%s%s]" % [
		int(game.value("player.humanity")), number(game, "lust"), field(game, id, "climax at", "100"),
		int(game.value("player.hunger")), int(game.value("player.thirst")),
		"-".repeat(width - done), "X".repeat(done)]


## The three standard choices, with the labels the captivity gives them.
static func choices(game, id: String) -> Array:
	var oblige := flag(game, "obliging")
	var recover := flag(game, "recover")
	return [
		{"text": field(game, id, "struggle label", "Struggle"), "action": "struggle"},
		{"text": field(game, id, "oblige label", "Oblige") if oblige else field(game, id, "abide label", "Abide"), "action": "oblige"},
		{"text": field(game, id, "recover label", "Recover") if recover else field(game, id, "endure label", "Endure"), "action": "endure"},
	]
