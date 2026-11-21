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



## One of the rules' scripts (`healing`, `hunger rises`, `thirst rises`), if it has it.
static func _script(game, field: String) -> void:
	var r := rules(game)
	if r != null and game.content.program("survival_rules:%s#%s" % [r.id, field]) != null:
		game.runner.play_now("survival_rules:%s#%s" % [r.id, field])


## Healing every turn, unless `natural healing when` fails (a no-heal mode).
static func _natural_healing(game) -> bool:
	var t := text(game, "natural healing when")
	return t == "" or Condition.evaluate(Condition.compile(t), game)


static func rules(game) -> FscParser.Definition:
	var definitions: Dictionary = game.content.all_of("survival_rules")
	return null if definitions.is_empty() else definitions.values()[0]


## A rules field that is an expression, as a number.
static func _number(game, field: String, fallback: String) -> int:
	var e := Expr.parse(text(game, field, fallback))
	return 0 if e.has("error") else Expr._num(Expr.evaluate(e, game))


## The sum of a rules field's `condition: amount` lines whose condition holds.
static func _modifiers(game, field: String) -> int:
	var d: FscParser.Definition = rules(game)
	var total := 0
	if d == null or not d.fields.has(field):
		return 0
	for l: FscParser.Line in d.fields[field].children:
		if l.is_blank() or not ":" in l.text:
			continue
		var p := l.text.rsplit(":", true, 1)
		if Condition.evaluate(Condition.compile(p[0].strip_edges()), game):
			var amount := Expr.parse(CompanionSystem.amount_text(p[1]))
			if not amount.has("error"):
				total += Expr._num(Expr.evaluate(amount, game))
	return total


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
	if _natural_healing(game):
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
				if value > 30 and game.role("morale") != "":
					game.set_value(game.role("morale"), game.role_number("morale") - (value - 30) / 5)
				if value > 99:
					_end(game, key, text(game, key + " death", "You have died of %s." % key))
					return
			var hint_at := int(text(game, "starving hint at", "50"))
			if hunger > hint_at or thirst > hint_at:
				say(game, text(game, "starving hint"))
		# The rules' `morale limit` (default: charisma plus perception) with its modifiers; morale
		# above that plus the level, plus `morale reset modifiers`, falls back to it.
		var maxmorale := _number(game, "morale limit", "player.charisma + player.perception") + _modifiers(game, "morale limit modifiers")
		if game.role("morale") != "" and game.role_number("morale") > maxmorale + int(game.value("player.level")) + _modifiers(game, "morale reset modifiers"):
			say(game, text(game, "morale normalized"))
			game.set_value(game.role("morale"), maxmorale)
	var corruption := 0
	for part in BodySystem.PARTS:
		if game.part_form("player", part) != "human":
			corruption += game.rng.range_int(0, 1)
	if corruption > 0:
		corruption -= game.rng.range_int(0, maxi(0, (int(game.value("player.perception")) - 10) / 2))
		corruption -= game.rng.range_int(0, maxi(0, (int(game.value("player.charisma")) - 10) / 2))
	# Infected parts wear down the value playing sanity (the rolls above happen either way).
	var sanity: String = game.role("sanity")
	if corruption > 0 and sanity != "":
		game.set_value(sanity, game.role_number("sanity") - corruption)
		say(game, text(game, "humanity loss"))
		if game.role_number("sanity") < int(text(game, "journal hint below", "50")):
			say(game, text(game, "journal hint"))
	# Survival rules can keep sanity from running out (Flexible Survival's Researcher start).
	var floor_when := text(game, "sanity floor when", "")
	if sanity != "" and game.role_number("sanity") < 1 and floor_when != "" and Condition.evaluate(Condition.compile(floor_when), game):
		game.set_value(sanity, 1)
	if sanity != "" and game.role_number("sanity") <= 0:
		_end(game, sanity.get_slice(".", 1), text(game, "humanity ending", "Your sanity is lost."))
	elif rescue_turn(game) >= 0 and game.state.turn >= rescue_turn(game):
		_end(game, "rescue", text(game, "rescue ending", "You survived until the rescue came."))
	elif rescue_turn(game) >= 0 and rescue_turn(game) - game.state.turn < int(text(game, "anticipation within", "20")) and game.rng.chance(1, 3):
		say(game, text(game, "rescue anticipation"))


## The turn the rescue comes: the rules' `rescue after` plus `~ extend game by N turns`;
## -1 when the rules set no rescue, or while their `no rescue when:` holds (extended play).
static func rescue_turn(game) -> int:
	var after := text(game, "rescue after")
	if not after.is_valid_int() or WorldSystem.no_rescue(game):
		return -1
	return int(after) + int(game.state.values.get("game.extended", 0))


## "clean thoughts.", or with a high libido "... thoughts. You are ...": the
## original's brain description (Characters.i7x, brain descr rule).
static func humanity_description(game) -> String:
	var out := _plain(game, above(game, "humanity descriptions", game.role_number("sanity"))) + " thoughts."
	var lust := _plain(game, above(game, "lust descriptions", game.role_number("arousal")))
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
