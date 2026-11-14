class_name HeatSystem
extends RefCounted
## Heat cycles, after the original's Needy Heat (Core Mechanics/Needy Heat.i7x).
##
## The policy is pack data. One `heat_rules` definition says who can go into
## heat (`female when`, `mpreg when`), when heat is off or intense, the default
## heat and the shared scripts (becoming vulnerable, switching kind, ending).
## A `heat` definition gives one strain's cycle: `cycle` and `duration` in days,
## whether it has a `female` and an `mpreg` heat, and its scripts (`trigger`,
## `mpreg trigger`, `start`, `each turn`, `end`). A form uses the heat with its
## own ID, another one named by its `heat:` field, `none`, or else the default.
##
## State (saved with the game's values):
##   player.heat             in heat now
##   player.heat_kind        "female" or "mpreg" while in heat
##   player.heat_turns       turns into the current cycle
##   player.heat_vulnerable  the body can go into heat (the original's animal heat)
##   player.heat_paused      content can pause heat (the original's heat enabled)
##   player.heat_hold        turns the current heat is held at its place (extend heat)

const TURNS_PER_DAY := 8


static func rules(game) -> String:
	var defs: Dictionary = game.content.all_of("heat_rules")
	return "" if defs.is_empty() else str(defs.keys()[0])


static func _rule(game, field: String, fallback: String = "") -> String:
	var id := rules(game)
	return fallback if id == "" else game.content.typed_value("heat_rules", id, field, fallback)


static func _holds(game, field: String) -> bool:
	var text := _rule(game, field)
	return text != "" and Condition.evaluate(Condition.compile(text), game)


## The strain of the player's sex (the original's CockName): the cunt for a
## female, else the cock; an untouched part falls back to the other one.
static func strain(game) -> String:
	var female: bool = game.adjective("player", "female")
	var form: String = game.part_form("player", "cunt" if female else "cock")
	if form == "human":
		form = game.part_form("player", "cock" if female else "cunt")
	return form


## The heat a strain has for a kind ("female" or "mpreg"), or "" for none.
static func heat_of(game, form: String, kind: String) -> String:
	var id: String = game.content.typed_value("form", form, "heat", "")
	if id == "none":
		return ""
	if id == "" and game.content.has(form, "heat"):
		id = form
	if id != "" and game.content.typed_value("heat", id, kind, "yes") == "no":
		id = ""  # no heat of this kind: the default one, as in the original
	if id == "":
		id = _rule(game, "default")
	return id if game.content.has(id, "heat") else ""


## The kind of heat the body can have now: "female", "mpreg" or "".
static func kind_now(game) -> String:
	if rules(game) == "":
		return ""
	var form := strain(game)
	if form == "human":
		return ""
	var kind := ""
	if game.adjective("player", "female"):
		kind = "female" if _holds(game, "female when") else ""
	elif _holds(game, "mpreg when"):
		kind = "mpreg"
	return kind if kind != "" and heat_of(game, form, kind) != "" else ""


## Cycle length and the turn heat starts at, in turns, for the heat in use.
static func timing(game, heat: String) -> Dictionary:
	var cycle := int(game.content.typed_value("heat", heat, "cycle", "7"))
	var duration := int(game.content.typed_value("heat", heat, "duration", "1"))
	return {"cycle": cycle * TURNS_PER_DAY, "start": (cycle - duration) * TURNS_PER_DAY,
		"duration": duration * TURNS_PER_DAY}


static func current(game) -> String:
	var kind := kind_now(game)
	return "" if kind == "" else heat_of(game, strain(game), kind)


static func in_heat(game) -> bool:
	return Condition._truthy(game.value("player.heat"))


static func turns(game) -> int:
	return int(game.state.values.get("player.heat_turns", 0))


static func _set_turns(game, n: int) -> void:
	game.state.values["player.heat_turns"] = n


## Every turn (the original's check heat rule).
static func tick(game) -> void:
	if rules(game) == "" or Condition._truthy(game.value("player.heat_paused")) or _holds(game, "off when"):
		return
	if int(game.value("player.humanity")) <= 0 or not game.state.combat.is_empty():
		return
	var v: Dictionary = game.state.values
	var kind := kind_now(game)
	if kind == "":
		if v.get("player.heat_vulnerable", false):
			_clear(game)
			_play(game, "heat_rules:%s#not vulnerable" % rules(game))
		return
	if not v.get("player.heat_vulnerable", false):
		_play(game, "heat_rules:%s#vulnerable" % rules(game))
		_set_turns(game, 0)
		v["player.heat_vulnerable"] = true
	var hold := int(v.get("player.heat_hold", 0))
	if hold > 0 and in_heat(game):
		v["player.heat_hold"] = hold - 1  # an extended heat: the cycle waits
	else:
		v.erase("player.heat_hold")
		_set_turns(game, turns(game) + 1)
	var heat := heat_of(game, strain(game), kind)
	var t := timing(game, heat)
	var intense := _holds(game, "intense when")
	if turns(game) > t.cycle:
		_set_turns(game, 0)
	if turns(game) >= t.start and not in_heat(game):
		v["player.heat"] = true
		v["player.heat_kind"] = kind
		_play(game, "heat:%s#%s" % [heat, "trigger" if kind == "female" else "mpreg trigger"])
		_play(game, "heat:%s#start" % heat)
	elif turns(game) >= t.start:
		if v.get("player.heat_kind", "") != kind:
			v["player.heat_kind"] = kind
			_play(game, "heat_rules:%s#switches" % rules(game))
		else:
			_play(game, "heat:%s#each turn" % heat)
			if intense and _roll(game, "intense lengthens"):
				_set_turns(game, turns(game) - 1)
	elif in_heat(game):
		v["player.heat_kind"] = kind
		_end(game, heat)
	elif intense and _roll(game, "intense quickens"):
		_set_turns(game, turns(game) + 1)


## Brings heat on sooner, or makes the current one last longer (the original's
## drive heat); `now` also runs a heat turn at once (its heatdrive 1).
static func drive(game, now: bool) -> void:
	if not game.state.values.get("player.heat_vulnerable", false):
		return
	var heat := current(game)
	if heat == "":
		return
	var t := timing(game, heat)
	if not in_heat(game):
		_set_turns(game, turns(game) + 1)
	elif turns(game) > t.start:
		_set_turns(game, turns(game) - (2 if now else 1))
	if now:
		tick(game)


## The current heat lasts `n` turns longer; out of heat, the next one comes `n` turns later.
static func extend(game, n: int) -> void:
	if in_heat(game):
		game.state.values["player.heat_hold"] = int(game.state.values.get("player.heat_hold", 0)) + n
	else:
		_set_turns(game, turns(game) - n)


## Ends the current heat now, with its end scripts; the cycle starts over.
static func end_now(game) -> void:
	if in_heat(game):
		_end(game, current(game))
	_set_turns(game, 0)


## Takes away heat altogether without any text; it can come back next turn.
static func reset(game) -> void:
	_clear(game)


static func _end(game, heat: String) -> void:
	_play(game, "heat_rules:%s#ends" % rules(game))
	if heat != "":
		_play(game, "heat:%s#end" % heat)
	for key in ["player.heat", "player.heat_kind", "player.heat_hold"]:
		game.state.values.erase(key)


static func _clear(game) -> void:
	for key in ["player.heat", "player.heat_kind", "player.heat_turns", "player.heat_vulnerable", "player.heat_hold"]:
		game.state.values.erase(key)


## Values content can read: turns until the next heat and until this one ends.
static func computed(game, key: String) -> Variant:
	if key == "heat_turns":
		return turns(game)
	var heat := current(game)
	if heat == "" or not game.state.values.get("player.heat_vulnerable", false):
		return 0
	var t := timing(game, heat)
	match key:
		"heat_starts_in":
			return 0 if in_heat(game) else maxi(0, t.start - turns(game))
		"heat_ends_in":
			return maxi(0, t.cycle - turns(game)) + int(game.state.values.get("player.heat_hold", 0)) if in_heat(game) else 0
		"heat_cycle":
			return t.cycle
		"heat_duration":
			return t.duration
	return null


static func _roll(game, field: String) -> bool:
	var m := RegEx.create_from_string("^(\\d+) in (\\d+)$").search(_rule(game, field))
	return m != null and game.rng.chance(int(m.get_string(1)), int(m.get_string(2)))


static func _play(game, pid: String) -> void:
	if game.content.program(pid) != null:
		game.runner.play_now(pid)
