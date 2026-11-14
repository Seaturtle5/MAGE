class_name EndingSystem
extends RefCounted
## How the game ends, after the original's Game Endings (Core Mechanics/Game
## Endings.i7x). When the game ends (a scene's `~ ending X`, losing all
## humanity, the rescue, starving), the engine plays the epilogue: every
## `== ending` in order of `priority` (lowest first) whose `when:` holds and
## whose type is not excluded, each telling its part of what became of the
## player. An ending can say the player died, was imprisoned or left; after one
## that says died or imprisoned, no further endings play. Then the game is over.
##
##   == ending latex_wolf_infection
##   name: Latex Wolf Infection
##   type: infection
##   priority: 1000
##   when: player.humanity >= 10 and player body is latex_wolf and not ending latex_wolf_nature is triggered
##   play:
##       As the rescue rolls in, you hear an ultrasonic siren calling to you ...
##
## During play, `~ trigger ending X` marks an ending (others test `ending X is
## triggered`); an ending that plays is marked too.
##
## State (saved with the game's values):
##   end.cause      what ended the game: an ending's ID, "humanity", "rescue", "hunger", "thirst"
##   end.triggered  the endings marked so far
##   end.dead, end.imprisoned, end.left   what the endings said happened to the player
##   end.reason     extra detail ("vore by wyvern")
##   end.flags      ending flags content sets for later endings
##   end.excluded   ending types left out ("infection")

const STATES := ["dead", "imprisoned", "left"]


static func _list(game, key: String) -> Array:
	return Array(game.state.values.get("end." + key, []))


static func _add(game, key: String, item: String) -> void:
	var l := _list(game, key)
	if item not in l:
		l.append(item)
	game.state.values["end." + key] = l


static func trigger(game, id: String) -> void:
	_add(game, "triggered", id)


static func triggered(game, id: String) -> bool:
	return id in _list(game, "triggered")


static func set_state(game, kind: String) -> void:
	game.state.values["end." + kind] = true


static func flag(game, id: String) -> void:
	_add(game, "flags", id)


static func has_flag(game, id: String) -> bool:
	return id in _list(game, "flags")


static func exclude(game, type: String) -> void:
	_add(game, "excluded", type)


static func excluded(game, type: String) -> bool:
	return type in _list(game, "excluded")


## Dead or imprisoned: no further endings play.
static func stopped(game) -> bool:
	return Condition._truthy(game.state.values.get("end.dead", false)) \
		or Condition._truthy(game.state.values.get("end.imprisoned", false))


## Every ending, lowest priority first (by ID among equals).
static func ordered(game) -> Array:
	var ids: Array = game.content.all_of("ending").keys()
	ids.sort()
	ids.sort_custom(func(a, b): return priority(game, a) < priority(game, b))
	return ids


static func priority(game, id: String) -> int:
	return int(game.content.typed_value("ending", id, "priority", "500"))


## Whether an ending plays now: its type is not excluded and its condition holds.
static func applies(game, id: String) -> bool:
	if excluded(game, game.content.typed_value("ending", id, "type", "")):
		return false
	var when: String = game.content.typed_value("ending", id, "when")
	return when == "" or Condition.evaluate(Condition.compile(when), game)
