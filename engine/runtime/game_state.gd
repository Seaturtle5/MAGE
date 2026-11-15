class_name GameState
extends RefCounted
## All mutable game state, keyed by content IDs.
##
## Only changes are stored: a value that was never changed is taken from its
## declared default. This keeps saves small and lets new content add values
## without migrations. Everything here is plain data (Dictionaries, Arrays,
## numbers, text), so the whole state converts to JSON for saving.

var values: Dictionary = {}  ## "owner.name" -> value (changed values only)
var turn := 0  ## turns passed since the start (a turn is 3 hours)
var actions := 0  ## completed gameplay actions, independent of survival turns
var action_pending := false
var scheduled: Array = []  ## {scene, due: completed action count}
var location := ""  ## the player's location
var known: Dictionary = {}  ## location id -> true when discovered
var visited: Dictionary = {}  ## location id -> true once the player has been there
var inventory: Dictionary = {}  ## item id -> count
var equipped: Array = []  ## worn item ids, in the order put on
var wielded := ""  ## the weapon in hand; "" fights unarmed
## Items lying in places: location id -> {item id -> count}. A place is added
## the first time it is needed, starting from its `items:` field.
var ground: Dictionary = {}
var feats: Array = []
var traits: Dictionary = {}  ## character id -> [trait ids]
var char_location: Dictionary = {}  ## character id -> location id
var residence: Dictionary = {}  ## character id -> location id
var companions: Array = []
var events: Dictionary = {}  ## event id -> {"resolved", "active", "last_turn"}
var conditions: Dictionary = {}  ## condition id -> {"remaining": turns}
var variations: Dictionary = {}  ## text variation key -> state
var stamps: Dictionary = {}  ## "owner.name" -> turn (time values)
var ending := ""
var rng_state: Array = []
var runner: Array = []  ## scene runner frames, when saved mid-scene
var combat: Dictionary = {}
var settings: Dictionary = {}
var encountered: Array = []  ## creature ids the player has fought, in order met
## Ways out changed in play: location id -> {direction -> exit ("" when removed)}.
var exits: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"values": values, "turn": turn, "location": location, "known": known, "visited": visited, "inventory": inventory,
		"equipped": equipped, "wielded": wielded, "ground": ground,
		"feats": feats, "traits": traits, "char_location": char_location, "residence": residence,
		"companions": companions, "events": events, "conditions": conditions, "variations": variations,
		"stamps": stamps, "ending": ending, "rng": rng_state, "runner": runner,
		"combat": combat, "settings": settings,
		"actions": actions, "action_pending": action_pending, "scheduled": scheduled, "encountered": encountered,
		"exits": exits,
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.values = d.get("values", {})
	s.turn = int(d.get("turn", 0))
	s.actions = int(d.get("actions", 0))
	s.action_pending = bool(d.get("action_pending", false))
	s.scheduled = d.get("scheduled", [])
	for entry: Dictionary in s.scheduled:
		entry.due = int(entry.due)
	s.location = d.get("location", "")
	s.known = d.get("known", {})
	s.visited = d.get("visited", d.get("known", {}).duplicate())  # older saves: what was known
	s.inventory = _ints(d.get("inventory", {}))
	s.equipped = d.get("equipped", [])
	s.wielded = d.get("wielded", "")
	for loc in d.get("ground", {}):
		s.ground[loc] = _ints(d.ground[loc])
	s.feats = d.get("feats", [])
	s.traits = d.get("traits", {})
	s.char_location = d.get("char_location", {})
	s.residence = d.get("residence", {})
	s.companions = d.get("companions", [])
	s.events = _whole(d.get("events", {}))  # last_turn and other numbers
	s.conditions = d.get("conditions", {})
	for entry: Dictionary in s.conditions.values():
		entry.remaining = int(entry.get("remaining", 0))
		for undo: Dictionary in entry.get("undo", []):
			if undo.has("delta"):
				undo.delta = int(undo.delta)
			if undo.get("value") is float and undo.value == floor(undo.value):
				undo.value = int(undo.value)
	s.variations = d.get("variations", {})
	s.stamps = _ints(d.get("stamps", {}))
	s.ending = d.get("ending", "")
	s.rng_state = d.get("rng", []).map(func(n): return int(n))
	s.runner = d.get("runner", [])
	s.combat = _whole(d.get("combat", {}))  # nested per-fight numbers included
	s.settings = d.get("settings", {})
	s.encountered = d.get("encountered", [])
	s.exits = d.get("exits", {})
	# JSON turns whole numbers into floats; restore them.
	for k in s.values:
		var v = s.values[k]
		if v is float and v == floor(v):
			s.values[k] = int(v)
		elif v is Array:
			s.values[k] = _whole(v)  # list values: their numbers too
	return s


## JSON turns whole numbers into floats: restores them everywhere in a value.
static func _whole(v: Variant) -> Variant:
	if v is float and v == floor(v):
		return int(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _whole(v[k])
		return out
	if v is Array:
		return v.map(func(x): return _whole(x))
	return v


static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out
