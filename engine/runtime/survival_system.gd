class_name SurvivalSystem
extends RefCounted
## The turn's survival rules, after Core Mechanics/Time.i7x: healing,
## hunger and thirst, their warnings and deaths, morale, humanity loss,
## the humanity ending and the rescue.
##
## Thresholds and texts are pack data (`survival_rules`); without them the
## numbers stay and only the endings are reported. Feat effects (Spartan
## Diet, Perky, the psyche and booster feats, Automatic Survival) belong to
## the feats package and are not applied yet.

const RESCUE_TURNS := 480  ## Turns starts at 240 and the rescue comes at -240


## One of the rules' scripts (`healing`, `hunger rises`, `thirst rises`), if it has it.
static func _script(game, field: String) -> void:
	var r := rules(game)
	if r != null and game.content.program("survival_rules:%s#%s" % [r.id, field]) != null:
		game.runner.play_now("survival_rules:%s#%s" % [r.id, field])


static func rules(game) -> FscParser.Definition:
	var definitions: Dictionary = game.content.all_of("survival_rules")
	return null if definitions.is_empty() else definitions.values()[0]


static func text(game, field: String, fallback: String = "") -> String:
	var r := rules(game)
	return fallback if r == null else game.content.typed_value("survival_rules", r.id, field, fallback)


## "N: text" lines, highest threshold first.
static func thresholds(game, field: String) -> Array:
	var out: Array = []
	var r := rules(game)
	if r == null or not r.fields.has(field):
		return out
	for line in r.fields[field].children:
		if line.is_blank():
			continue
		var pair: PackedStringArray = line.text.split(":", true, 1)
		if pair.size() == 2 and pair[0].strip_edges().is_valid_int():
			out.append([int(pair[0].strip_edges()), pair[1].strip_edges()])
	out.sort_custom(func(a, b): return a[0] > b[0])
	return out


## The text of the highest threshold the value is above, or "".
static func above(game, field: String, value: int) -> String:
	for t in thresholds(game, field):
		if value > int(t[0]):
			return str(t[1])
	return ""


static func say(game, template: String) -> void:
	if template == "":
		return
	var compiled := TextTemplate.compile(template)
	if not compiled.has("error"):
		game.emit({"type": "paragraph", "spans": game.render(compiled)})


static func tick(game) -> void:
	var stamina := int(game.value("player.stamina"))
	if "no_heal" not in game.settings.mode:
		game.set_value("player.hp", int(game.value("player.hp")) + stamina / 2)
	_script(game, "healing")  # the rules' extra healing (feats that heal each turn)
	if int(game.value("player.hp")) < 0:
		game.set_value("player.hp", 1)
	if game.rng.range_int(1, 20) > game.rng.range_int(1, stamina + 1):
		game.set_value("player.hunger", int(game.value("player.hunger")) + 1)
		_script(game, "hunger rises")  # feats that slow it, others who share your food
	if game.rng.range_int(1, 25) > game.rng.range_int(1, stamina + 1):
		game.set_value("player.thirst", int(game.value("player.thirst")) + 3)
		_script(game, "thirst rises")
	if (241 - game.state.turn) % 3 == 0:
		var hunger := int(game.value("player.hunger"))
		var thirst := int(game.value("player.thirst"))
		if hunger > 3 or thirst > 12:
			for key in ["hunger", "thirst"]:
				var value := int(game.value("player." + key))
				say(game, above(game, key + " warnings", value))
				if value > 30:
					game.set_value("player.morale", int(game.value("player.morale")) - (value - 30) / 5)
				if value > 99:
					_end(game, key, text(game, key + " death", "You have died of %s." % key))
					return
			var hint_at := int(text(game, "starving hint at", "50"))
			if hunger > hint_at or thirst > hint_at:
				say(game, text(game, "starving hint"))
		var maxmorale := int(game.value("player.charisma")) + int(game.value("player.perception"))
		if int(game.value("player.morale")) > maxmorale + int(game.value("player.level")):
			say(game, text(game, "morale normalized"))
			game.set_value("player.morale", maxmorale)
	var corruption := 0
	for part in BodySystem.PARTS:
		if game.part_form("player", part) != "human":
			corruption += game.rng.range_int(0, 1)
	if corruption > 0:
		corruption -= game.rng.range_int(0, maxi(0, (int(game.value("player.perception")) - 10) / 2))
		corruption -= game.rng.range_int(0, maxi(0, (int(game.value("player.charisma")) - 10) / 2))
	if corruption > 0:
		game.set_value("player.humanity", int(game.value("player.humanity")) - corruption)
		say(game, text(game, "humanity loss"))
		if int(game.value("player.humanity")) < int(text(game, "journal hint below", "50")):
			say(game, text(game, "journal hint"))
	if int(game.value("player.humanity")) <= 0:
		_end(game, "humanity", text(game, "humanity ending", "Your mind is lost to the infection."))
	elif game.state.turn >= RESCUE_TURNS:
		_end(game, "rescue", text(game, "rescue ending", "You survived until the rescue came."))
	elif RESCUE_TURNS - game.state.turn < int(text(game, "anticipation within", "20")) and game.rng.chance(1, 3):
		say(game, text(game, "rescue anticipation"))


## "clean thoughts.", or with a high libido "... thoughts. You are ...": the
## original's brain description (Characters.i7x, brain descr rule).
static func humanity_description(game) -> String:
	var out := _plain(game, above(game, "humanity descriptions", int(game.value("player.humanity")))) + " thoughts."
	var lust := _plain(game, above(game, "lust descriptions", int(game.value("player.libido"))))
	return out + (" " + lust if lust != "" else "")


static func _plain(game, template: String) -> String:
	var compiled := TextTemplate.compile(template)
	return "" if template == "" or compiled.has("error") else TextTemplate.plain(game.render(compiled))


## The species of the first changed part, in the original's order (face,
## body, skin, cock, tail), in lower case; "corrupted" when none has changed.
static func species(game, who: String) -> String:
	for part in ["head", "torso", "skin", "cock", "tail"]:
		var form: String = game.part_form(who, part)
		if form != "human":
			return game.content.typed_value("form", form, "name", form).to_lower()
	return "corrupted"


static func _end(game, cause: String, ending: String) -> void:
	game.end_game(cause, ending)
