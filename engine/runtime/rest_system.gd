class_name RestSystem
extends RefCounted
## Rest/sleep policy is pack data; rules never refer to a specific item or room.

const QUALITY := {"none": 0, "rough": 1, "bed": 2, "cot": 2, "hammock": 3}


## Fatigue and the rest buff switched off (`off when`, such as an insomniac mode).
static func off(game) -> bool:
	var config := rules(game)
	if config == null or not config.fields.has("off when"):
		return false
	return Condition.evaluate(Condition.compile(config.fields["off when"].value), game)


static func rules(game) -> FscParser.Definition:
	var definitions: Dictionary = game.content.all_of("rest_rules")
	return null if definitions.is_empty() else definitions.values()[0]


static func number(game, field: String, fallback: int) -> int:
	var config := rules(game)
	return fallback if config == null else int(game.content.typed_value("rest_rules", config.id, field, str(fallback)))


static func bedding(game) -> Dictionary:
	var loc: String = game.state.location
	var result := {"quality": game.content.typed_value("location", loc, "rest", "none"),
		"text": game.content.typed_value("location", loc, "rest text", "You rest for a while.")}
	# Carried and loose bedding can improve the location's permanent bedding.
	var here := ItemSystem.ground(game, loc)
	var candidates: Array = game.state.inventory.keys() + here.keys()
	for id: String in candidates:
		var owned: bool = int(game.state.inventory.get(id, 0)) > 0
		var available := int(here.get(id, 0))
		if not owned and available <= 0:
			continue
		var quality: String = game.content.typed_value("item", id, "rest", "none")
		if QUALITY.get(quality, 0) >= QUALITY.get(result.quality, 0) and quality != "none":
			result.quality = quality
			result.text = game.content.typed_value("item", id, "carried rest text" if owned else "ground rest text", "You rest for a while.")
	# A feat can be bedding of its own (`rest: rough` and `rest text:`): a rest
	# anywhere, when nothing at least as good is at hand.
	for id: String in game.state.feats:
		var quality: String = game.content.typed_value("feat", id, "rest", "none")
		if QUALITY.get(quality, 0) > QUALITY.get(result.quality, 0):
			result.quality = quality
			result.text = game.content.typed_value("feat", id, "rest text", "You rest for a while.")
	return result


static func blocking_condition(game) -> String:
	for id: String in game.state.conditions:
		if game.content.typed_value("condition", id, "blocks rest", "no") == "yes":
			return id
	return ""


static func recover(game, quality: String) -> void:
	var quarter := int(game.value("player.maxhp")) / 4
	var stamina := int(game.value("player.stamina")) * 3 / 2 + int(game.value("player.level"))
	# Beds and cots: the better of the two; rough bedding: their average; none at all
	# (only a rest a scene gives, `~ rest`): the lower (the original's Rest phrase).
	var recovery := (quarter + stamina) / 2 if quality == "rough" else mini(quarter, stamina) if quality == "none" else maxi(quarter, stamina)
	game.apply({"op": "survival", "kind": "heal", "amount": {"value": {"op": "num", "v": recovery}}, "quiet": true})
	var config := rules(game)
	if config == null or off(game):
		return
	if int(game.value("player.fatigue")) >= number(game, "fresh below", 10):
		var amount := number(game, "hammock recovery", 6) if quality == "hammock" else number(game, "exhausted recovery", 5)
		game.change_value("player.fatigue", -amount)
		return
	game.set_value("player.fatigue", number(game, "hammock fresh fatigue", -3) if quality == "hammock" else number(game, "fresh fatigue", -2))
	var condition: String = config.fields.condition.value
	var fresh: bool = not game.state.conditions.has(condition)
	game.start_condition(condition, number(game, "duration", 7), true, true)
	if fresh:
		_emit(game, "refreshed")


static func tick(game) -> void:
	var config := rules(game)
	if config == null or game.state.ending != "" or off(game):
		return
	# The original tests the feat before expiring it and freezes fatigue while active.
	if game.state.conditions.has(config.fields.condition.value):
		return
	var fatigue := int(game.value("player.fatigue"))
	if fatigue >= number(game, "collapse at", 12):
		_emit(game, "collapse")
		game.set_value("player.fatigue", number(game, "collapse fatigue", 3))
		for _i in number(game, "collapse turns", 2):
			game.pass_turn()
		_emit(game, "wake")
	else:
		var warnings := _pairs(config, "warnings")
		if warnings.has(fatigue):
			game.emit({"type": "paragraph", "spans": game.render(TextTemplate.compile(warnings[fatigue]))})
	game.change_value("player.fatigue", 1)


static func status(game) -> String:
	var config := rules(game)
	if config == null:
		return ""
	var statuses := _pairs(config, "statuses")
	var thresholds: Array = statuses.keys()
	thresholds.sort()
	var label := ""
	var fatigue: int = 0 if off(game) else int(game.value("player.fatigue"))
	for threshold: int in thresholds:
		if label == "" or threshold <= fatigue:
			label = statuses[threshold]
	return label


static func _pairs(config: FscParser.Definition, field: String) -> Dictionary:
	var result := {}
	if not config.fields.has(field):
		return result
	for line in config.fields[field].children:
		if not line.is_blank() and ":" in line.text:
			var pair: PackedStringArray = line.text.split(":", true, 1)
			result[int(pair[0].strip_edges())] = pair[1].strip_edges()
	return result


## Whether a rest here can be interrupted at all: `interruption chance` is set and
## `interruption when` holds (a place that is not safe to sleep in).
static func can_be_interrupted(game) -> bool:
	var config := rules(game)
	if config == null or not config.fields.has("interruption chance"):
		return false
	if config.fields.has("interruption when"):
		return Condition.evaluate(Condition.compile(config.fields["interruption when"].value), game)
	return true


## Rolls `interruption chance` (N in M) plus its modifiers (`condition: + n` lines).
static func interrupted(game) -> bool:
	var config := rules(game)
	var parts: PackedStringArray = config.fields["interruption chance"].value.split(" in ")
	if parts.size() != 2:
		return false
	var n := int(parts[0])
	if config.fields.has("interruption chance modifiers"):
		for l: FscParser.Line in config.fields["interruption chance modifiers"].children:
			if l.is_blank() or not ":" in l.text:
				continue
			var p := l.text.rsplit(":", true, 1)
			if Condition.evaluate(Condition.compile(p[0].strip_edges()), game):
				n += int(p[1].replace(" ", ""))
	return game.rng.chance(n, int(parts[1]))


## Plays a rest rules script (`interrupted`, `undisturbed` ...); false when there is none.
static func play(game, field: String) -> bool:
	var config := rules(game)
	if config == null or game.content.program(config.id + "#" + field, "rest_rules") == null:
		return false
	_emit(game, field)
	return true


static func _emit(game, field: String) -> void:
	var config := rules(game)
	for spans in game.runner.render_paragraphs(game.content.program(config.id + "#" + field, "rest_rules")):
		game.emit({"type": "paragraph", "spans": spans})
