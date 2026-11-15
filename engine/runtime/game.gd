class_name Game
extends RefCounted
## A running game: content, state, randomness and output.
##
## Conditions, effects and text call into this object (value, ask, apply,
## describe, variation). The scene runner plays scripts. Everything the
## player should see is appended to `output` as events, which the interface
## draws and tests record. Nothing here touches the scene tree.

const PLAYER_DEFAULTS := {
	"fatigue": 0,
	"hp": 20, "maxhp": 20, "xp": 0, "level": 1, "score": 0,
	"strength": 12, "dexterity": 12, "stamina": 12, "charisma": 12, "intelligence": 12, "perception": 12,
	"hunger": 0, "thirst": 0,
	"cocks": 0, "cunts": 1, "nipples": 2, "name": "Player",
	# Body numbers the original's body adjectives read (Characters.i7x:48-75, 198, 239).
	"weight": 5, "definition": 5, "androgyny": 5, "body_hair": 2, "ass.width": 3, "ass.depth": 9, "ass.tightness": 2,
	"mouth.length": 5, "mouth.circumference": 3, "clit.size": 3,
}
const BOUNDED := {"hunger": [0, 100], "thirst": [0, 100], "balls.size": [0, 7]}
const ATTRIBUTES := ["strength", "dexterity", "stamina", "charisma", "intelligence", "perception"]
const TIME_SLOTS := ["pre dawn", "post midnight", "night", "early night", "evening", "afternoon", "morning", "early morning"]
const FILTER_STATES := ["normal", "warded", "banned"]
const CREATURE_SEXES := ["male", "female", "herm", "neuter"]

var content: ContentDB
var state: GameState
var rng: Rng
var runner: SceneRunner
var output: Array = []
## Per-game settings, saved with the game. "started" locks bans once a
## scenario has begun.
var settings := default_settings()
var last_fight := ""  ## outcome of the most recent fight ("won", "lost" ...)
var use_cancelled := false
var fight_cancelled := false  # set by `~ no fight` in an encounter
var continue_moving := false  ## '~ continue moving': a leaving event lets the player walk on
## '~ end captivity' ("end") or '~ escape captivity' ("escape", a turn passes): the
## captivity ends when the current script is done.
var captivity_exit := ""
var cancel_companion := false  ## '~ cancel summon' / '~ cancel dismiss' in a companion's text
var warnings: Array = []  ## runtime problems (missing descriptors and so on)


static func default_settings() -> Dictionary:
	return {"banned": [], "warded": [], "levels": {}, "interests": {}, "mode": [], "scenario": "", "started": false}


func _init(db: ContentDB, seed_value: int = 1) -> void:
	content = db
	state = GameState.new()
	rng = Rng.new(seed_value)
	runner = SceneRunner.new(self)


## Breaks the reference cycle between the game and its runner. Call when done.
func dispose() -> void:
	if runner != null:
		runner.game = null
		runner = null


func emit(event: Dictionary) -> void:
	output.append(event)


## Removes and returns all output produced so far.
func take_output() -> Array:
	var out := output
	output = []
	return out


func notice(text: String, quiet: bool) -> void:
	if not quiet:
		emit({"type": "notice", "text": text})


func warn(message: String) -> void:
	warnings.append(message)


# --- Values -----------------------------------------------------------------

## While a text snippet describes someone else ("[cock_size_desc of francois]"),
## the snippet's player values and adjectives read that character's.
var _subject := ""
var _ready_checking: Array = []  ## events whose requirements are being checked (no loops)
var play_loops: Array = []  ## [index, count] of `play X N times` running inside a fight script


func value(path: String) -> Variant:
	if _subject != "" and path.begins_with("player."):
		path = _subject + path.substr(6)
	if path == "game.turn":
		return state.turn  # turns passed since the start, for timing in content
	if path == "places.known":
		return state.known.size()  # fast-travel places the player knows (the original's number of known fasttravel rooms)
	if path == "play.index" or path == "play.count":
		# The repetition a `play X N times` is on (from 1), and how many there are.
		var loop: Array = play_loops[-1] if not play_loops.is_empty() else runner.play_loop()
		return (loop[0] if path == "play.index" else loop[1]) if not loop.is_empty() else 0
	if path.begins_with("people.") and path.count(".") == 1:
		return people_at(path.substr(7).replace("_", " "))  # people.collected, people.bunker ...
	if path.begins_with("party."):
		match path:
			"party.size":
				return state.companions.size()
			"party.limit":
				return CompanionSystem.limit(self)
			"party.tamed":
				return CompanionSystem.tamed(self).size()
	if path.begins_with("offspring.") and path.substr(10) in ["with_you", "bunker", "roaming", "total"]:
		return CompanionSystem.offspring(self, path.substr(10))
	if path.begins_with("feat."):
		return 1 if path.substr(5) in state.feats else 0  # for formulas: feat.good_teacher * 50
	if path.begins_with("enemy.") or path.begins_with("fight."):
		return _fight_value(path)
	if state.values.has(path):
		return state.values[path]
	if path.begins_with("level."):
		# A content level as a number: its option's place in the list (1 for the first).
		var id := path.trim_prefix("level.")
		return Array(content.levels.get(id, {}).get("options", [])).find(level(id)) + 1
	if content.values.has(path):
		if content.values[path].get("kind", "") == "time":
			return state.stamps.get(path)  # the turn it was set (null before that)
		if content.values[path].get("kind", "") == "list":
			return content.values[path].default.duplicate()  # never the declaration's own list
		return content.values[path].get("default")
	if path.begins_with("pregnancy."):
		var key := path.substr(10)
		if key in PregnancySystem.COMPUTED:
			return PregnancySystem.computed(self, key)
		if key in PregnancySystem.STORED:
			return PregnancySystem.stored_default(key)
	if path.begins_with("child.") and path.substr(6) in PregnancySystem.CHILD_VALUES:
		return false if path.substr(6) in ["feral", "pureblood", "albino", "melanism", "show_tail", "show_legs"] else 0 if path == "child.number" else ""
	if path.begins_with("captivity.") and path.substr(10) in CaptivitySystem.VALUES:
		# The engine's captivity numbers start at 0 (flags at no) until a captivity sets them.
		return false if path.substr(10) in ["enduring", "obliging", "recover"] else 0
	if path.begins_with("player."):
		var key := path.substr(7)
		if PLAYER_DEFAULTS.has(key):
			return PLAYER_DEFAULTS[key]
		match key:
			"capacity":
				return ItemSystem.capacity(self)
			"carried_weight":
				return ItemSystem.carried_weight(self)
			"scale":
				return ItemSystem.scale(self)
			"heat_turns", "heat_starts_in", "heat_ends_in", "heat_cycle", "heat_duration":
				return HeatSystem.computed(self, key)
		if key.ends_with(".strain_damage"):
			# The damage of the creature whose strain a body part has (natural weapons:
			# the original's Natural Armaments and Tail Strike read its Table row).
			return CombatSystem.strain_damage(self, part_form("player", key.trim_suffix(".strain_damage")))
		if key.begins_with("carried."):
			return ItemSystem.count(self, key.trim_prefix("carried."))  # how many of an item the player carries
		if key.begins_with("style.") or key == "gender_look":
			return ItemSystem.looks(self).get(key.trim_prefix("style."), 0)
	return null


## The carried items with a tag, sorted ("milky": the bottles of milk).
func carried_tagged(tag: String) -> Array:
	var out: Array = []
	for id: String in state.inventory.keys():
		var def: FscParser.Definition = content.get_def("item", id)
		if int(state.inventory[id]) > 0 and def != null and tag in content._list(def, "tags"):
			out.append(id)
	out.sort()
	return out


## A character's portrait: the one set in play (`~ character X image Y`), else its `image:`.
func character_image(id: String) -> String:
	if state.values.has("character.%s.image" % id):
		return str(state.values["character.%s.image" % id])
	return content.typed_value("character", id, "image")


## A creature field that play can change (`~ creature X found in Z`), else its definition's.
func creature_field(id: String, field: String, fallback: String = "") -> String:
	var key := "creature.%s.%s" % [id, field]
	if state.values.has(key):
		return str(state.values[key])
	var v: Variant = VariantSystem.field(self, id, field)  # the variant met this time
	if v != null:
		return str(v)
	return content.typed_value("creature", id, field, fallback)


## The creature being fought (`enemy.hp`, `enemy.damage` ...) and a fight's own
## scratch numbers (`fight.<name>`, reset when a fight starts; `fight.damage` is
## the last blow's damage). Outside a fight they read as 0.
const ENEMY_STATE := {"hp": "hp", "max_hp": "maxhp", "lust": "libido", "round": "round", "grappled": "grappled"}


func _fight_value(path: String) -> Variant:
	var c: Dictionary = state.combat
	var key := path.get_slice(".", 1)
	if path.begins_with("fight."):
		return c.get("vars", {}).get(key, 0) if not c.is_empty() else 0
	if c.is_empty():
		return false if key == "grappled" else 0
	if ENEMY_STATE.has(key):
		return c[ENEMY_STATE[key]]
	if key == "scale":
		return VoreSystem.scale_of(self, c.creature)
	if key == "form":
		return creature_field(c.creature, "form", c.creature)  # the strain it infects with
	if key in CombatSystem.ATTRIBUTES:
		return CombatSystem.stat(self, c.creature, key)
	return CombatSystem.number(self, c.creature, key.replace("_", " "), CombatSystem.ENEMY_DEFAULTS.get(key, 0))


func _set_fight_value(path: String, v: Variant) -> void:
	var c: Dictionary = state.combat
	if c.is_empty():
		warn("%s can only change during a fight." % path)
		return
	var key := path.get_slice(".", 1)
	if path.begins_with("fight."):
		c.vars[key] = v
	elif ENEMY_STATE.has(key):
		c[ENEMY_STATE[key]] = Condition._truthy(v) if key == "grappled" else int(v)
	else:
		c.overrides[key] = int(v)


## The value playing an engine role ("sanity", "arousal", "morale"; a pack gives
## it with `role:` under the value's declaration), or "" when none does.
func role(name: String) -> String:
	return str(content.roles.get(name, ""))


## A role's value as a number; 0 when no value plays the role.
func role_number(name: String) -> int:
	var path := role(name)
	var v = value(path) if path != "" else null
	return int(v) if v != null else 0


## A fight is under way (and not decided yet).
func in_fight() -> bool:
	return not state.combat.is_empty() and str(state.combat.get("result", "")) == ""


## After a fight, values that may go higher in fights return within their bounds.
func settle_fight_values() -> void:
	for path in content.values:
		if content.values[path].has("fight_max") and state.values.has(path):
			set_value(path, value(path))


func set_value(path: String, v: Variant) -> void:
	if path.begins_with("enemy.") or path.begins_with("fight."):
		_set_fight_value(path, v)
		return
	var decl: Dictionary = content.values.get(path, {})
	if decl.has("max"):
		var top: int = decl.fight_max if decl.has("fight_max") and in_fight() else decl.max
		v = clampi(int(v), int(decl.min), top)
	if path.begins_with("player."):
		var key := path.substr(7)
		if BOUNDED.has(key):
			v = clampi(int(v), BOUNDED[key][0], BOUNDED[key][1])
		elif key == "hp":
			v = mini(int(v), int(value("player.maxhp")))
	if decl.get("kind", "") == "time":
		state.stamps[path] = state.turn
		return
	if decl.has("default") and v == decl.default:
		state.values.erase(path)
	else:
		state.values[path] = v


## Relative attribute changes use the source StatChange stamina/health rule.
func change_value(path: String, delta: int) -> void:
	if path == "player.stamina":
		for _i in absi(delta):
			var stamina := int(value(path)) + signi(delta)
			set_value(path, stamina)
			var hp_delta := int(value("player.level")) + 1
			if delta > 0 and posmod(stamina, 2) == 0:
				set_value("player.maxhp", int(value("player.maxhp")) + hp_delta)
				set_value("player.hp", int(value("player.hp")) + hp_delta)
			elif delta < 0 and posmod(stamina, 2) == 1:
				set_value("player.maxhp", int(value("player.maxhp")) - hp_delta)
				set_value("player.hp", value("player.hp"))
	else:
		var before = value(path)
		set_value(path, (int(before) if before != null else 0) + delta)  # an unset number counts as 0


func state_index(path: String, v: Variant) -> int:
	var decl: Dictionary = content.values.get(path, {})
	var states: Array = decl.get("states", [])
	return states.find(str(v))


func turns_since(path: String) -> int:
	if not state.stamps.has(path):
		return 1 << 30
	return state.turn - int(state.stamps[path])


func time_slot() -> String:
	# Time.i7x starts at 240 (slot 0), then counts down to 239 (slot 7).
	return TIME_SLOTS[posmod(8 - state.turn, 8)]


func is_day() -> bool:
	return time_slot() in ["morning", "early morning", "afternoon", "evening"]


# --- Conditions -------------------------------------------------------------

## The name of the strain a body part has (a character's form for a character).
func species_name(who: String, part: String) -> String:
	var form := part_form(who, part)
	if who != "player" and content.has(who, "character") and value("%s.form" % who) != null:
		form = str(value("%s.form" % who))
	return content.typed_value("form", form, "name", form)


func ask(node: Dictionary) -> bool:
	match node.op:
		"chance":
			return rng.chance(node.n, node.d)
		"check":
			return skill_check(node.stat, node.target)
		"check_expr":
			return roll_check("", Expr._num(Expr.evaluate(node.bonus, self)), Expr._num(Expr.evaluate(node.target, self)))
		"quest":
			var path := "quest.%s" % node.quest
			var cur := state_index(path, value(path))
			var target := state_index(path, node.stage)
			match node.rel:
				"is":
					return cur == target
				"reached":
					return cur >= target
				"is before":
					return cur < target
			return false
		"outcome":
			return str(value("%s.outcome" % node.event)) == node.outcome
		"time":
			return node.slot == time_slot() or (node.slot == "day" and is_day()) or (node.slot == "night" and not is_day())
		"filter":
			match node.get("state", "allowed"):
				"banned":
					return node.filter in settings.banned
				"warded":
					return node.filter in settings.warded
			return node.filter not in settings.banned
		"level":
			var current := level(node.category)
			var rel: String = node.get("rel", "is")
			if rel == "is":
				return current == node.option
			var options: Array = content.levels.get(node.category, {}).get("options", [])
			var have := options.find(current)
			var want := options.find(node.option)
			if have < 0 or want < 0:
				return false
			return have >= want if rel == "at least" else have <= want
		"mode":
			return node.mode in settings.mode
		"scenario":
			return settings.scenario == node.scenario
		"can_vore":
			# The original's "Player can vore" / "Player can UB" (VoreSystem).
			return VoreSystem.can(self, node.kind)
		"enemy_tagged":
			# The creature being fought (or met last) or its form carries the tag.
			return node.tag in VoreSystem.tags_of(self, current_creature())
		"fight_result":
			# "won by fighting" and "lost by injury" are the plain results ("won", "lost");
			# "lost by lust" comes with lust attacks (combat package) and is not produced yet.
			match node.result:
				"won", "lost":
					return last_fight.begins_with(node.result)
				"won by fighting":
					return last_fight == "won"
				"lost by injury":
					return last_fight == "lost"
			return last_fight == node.result
		"feat":
			return node.id in state.feats
		"trait":
			return node.id in state.traits.get(node.who, [])
		"had_sex":
			return bool(value("%s.had_sex" % node.who))
		"has_part":
			return body_count(node.who, node.part) > 0
		"has_item":
			return int(state.inventory.get(node.item, 0)) >= node.n
		"has_tagged":
			return not carried_tagged(node.tag).is_empty()
		"has_condition":
			return state.conditions.has(node.id)
		"wears":
			return ItemSystem.wears(self, node.item)
		"wields":
			return state.wielded == node.item if node.item != "anything" else state.wielded != ""
		"lives_at":
			return state.residence.get(node.who, content.field_value(node.who, "lives at")) == node.place
		"is_at":
			return where(node.who) == node.place
		"knows":
			return state.known.has(node.place)
		"visited":
			return state.visited.has(node.place)
		"part_is":
			return part_form(node.who, node.part) == node.form
		"part_tagged":
			return node.tag in content.form_tags(part_form(node.who, node.part))
		"at_flagged":
			var at := state.location if node.who == "player" else where(node.who)
			return at != "" and node.flag in content.list_field(at, "flags")
		"parts_all":
			# The original's purehuman: every body part one of the given strains.
			for part in BodySystem.PARTS:
				if part_form(node.who, part) not in node.forms:
					return false
			return true
		"species_contains":
			# The original's "BodyName of Player matches the text "Wolf"": the strain's name.
			return species_name(node.who, node.part).to_lower().contains(str(node.text).to_lower())
		"species_same":
			# The original's "BodySpeciesName of Player is not FaceSpeciesName of Player".
			return species_name(node.who, node.part).to_lower() == species_name(node.other, node.other_part).to_lower()
		"is":
			return adjective(node.who, node.adjective)
	warn("Condition '%s' is not supported yet." % node.op)
	return false


func adjective(who: String, adj: String) -> bool:
	if _subject != "" and who == "player":
		who = _subject
	if who == "enemy":
		if content.has(adj, "creature"):
			return current_creature() == adj  # "enemy is bald_eagle"
		who = current_creature()  # "enemy is female": the creature being fought or met
	if who == "player" and adj in ["dead", "imprisoned", "gone"]:
		# What the endings said happened (EndingSystem): "player is dead".
		return Condition._truthy(state.values.get("end." + ("left" if adj == "gone" else adj), false))
	if who == "captivity" and adj == "ending":
		return captivity_exit != ""  # '~ end captivity' or '~ escape captivity' ran this round
	if who == "here":
		# The player's location: "here is flagged fast travel", "here is explorable" (it has a zone).
		if adj.begins_with("flagged "):
			return adj.substr(8) in content.list_field(state.location, "flags")
		if adj == "explorable":
			return zone_here() != ""
	if content.has(who, "creature") and (adj in CREATURE_SEXES or adj.begins_with("variant ")):
		# A creature's sex follows its gender (that of the variant met this time).
		if adj.begins_with("variant "):
			return VariantSystem.current(self, who) == adj.substr(8)
		var g := creature_field(who, "gender", "neuter")
		var cock := g in ["male", "herm", "shemale", "male herm"]
		var cunt := g in ["female", "herm", "male herm", "cuntboy"]
		return {"male": cock, "female": cunt, "herm": cock and cunt, "neuter": not cock and not cunt}[adj]
	if adj in ["locked", "unlocked"] and content.has(who, "door"):
		# "cell_door is locked": its state in play, else its `locked:` field.
		return runner._door_locked(who) == (adj == "locked")
	if who == "player" and adj.begins_with("interested in "):
		return interest(adj.substr(14).strip_edges())
	match adj:
		"male":
			return body_count(who, "cock") > 0
		"female":
			return body_count(who, "cunt") > 0
		"herm":
			return body_count(who, "cock") > 0 and body_count(who, "cunt") > 0
		"neuter":
			return body_count(who, "cock") == 0 and body_count(who, "cunt") == 0
		"naked":
			return who == "player" and ItemSystem.naked(self)
		"barefoot", "barecrotch", "barechest":
			return who == "player" and ItemSystem.bare(self, adj)
		"overburdened":
			return who == "player" and ItemSystem.overburdened(self)
		"male preferred", "female preferred", "herm preferred":
			# The original's MalePreferred etc. (Feats.i7x): the gender-preference feats.
			return who == "player" and BodySystem._prefers(self, adj.get_slice(" ", 0))
		"in an event":
			# The original's inasituation: an event is running (a fight it started included).
			return who == "player" and runner.current_event() != ""
		"pregnant":
			# Carrying a child now (PregnancySystem; the original's impreg_now).
			return who == "player" and PregnancySystem.gestation(self) > 0
		"in heat":
			# Set by the heat system (HeatSystem) for the player.
			return Condition._truthy(value("%s.heat" % who))
		"in female heat", "in mpreg heat":
			return who == "player" and HeatSystem.in_heat(self) and str(value("player.heat_kind")) == adj.get_slice(" ", 1)
		"captive":
			# Held in a captivity (the original's boundstate).
			return who == "player" and runner.frames.any(func(f): return f.kind == "captivity")
		"arrived by walking", "arrived by travelling":
			# How the player came to this place, for arrival events (the original's NavArrival).
			return who == "player" and str(state.values.get("arrival.mode", "")) == ("walk" if adj.ends_with("walking") else "travel")
		"creature picked":
			return str(state.values.get("picked.creature", "")) != ""
		"vulnerable to heat":
			# The body can go into heat now (sex, strain and heat_rules' female/mpreg when).
			return who == "player" and HeatSystem.kind_now(self) != ""
		"heat paused":
			return who == "player" and Condition._truthy(value("player.heat_paused"))
		"fighting":
			# The original's inafight: true while a fight is going on.
			return who == "player" and not state.combat.is_empty() and str(state.combat.get("result", "")) == ""
		"resolved", "active":
			var ev: Dictionary = state.events.get(who, {})
			if ev.has(adj):
				return bool(ev[adj])
			# An event not touched yet starts as its definition says (active: no).
			if adj == "active" and content.has(who, "event"):
				return content.typed_value("event", who, "active", "yes") == "yes"
			return adj == "active"
		"ready":
			# The original's PrereqComplete: the event's own requirements hold now.
			if not content.has(who, "event"):
				return false
			var req := content.typed_value("event", who, "requires")
			if req == "" or who in _ready_checking:
				return req == ""  # an event that needs itself to be ready is never ready
			_ready_checking.append(who)
			var rc := Condition.compile(req)
			var ok := not rc.has("error") and Condition.evaluate(rc, self)
			_ready_checking.erase(who)
			return ok
		"companion":
			return who in state.companions
		"lonely":
			# The original's "the player is lonely": no companion follows.
			return who == "player" and state.companions.is_empty()
		"here":
			return where(who) == state.location
		"collected":
			return "collected" in content.list_field(where(who), "flags")
		"pansexual":
			# The original's pansexual: interested in every interest the game declares.
			return who == "player" and interested_in_all()
		"pure":
			# Characters.i7x:494: head, body, tail, skin and cock all of one strain.
			# Parts the body's strain does not describe (a form without a tail) are not counted.
			var form := part_form(who, "torso")
			for part in ["head", "tail", "skin", "cock"]:
				if part_form(who, part) != form and (form == "human" or not BodySystem.fields(self, form, part).is_empty()):
					return false
			return true
		"met":
			# A creature the player has fought (the original's EncounteredEnemies); else a value.
			if content.has(who, "creature"):
				return who in state.encountered
			return bool(value("%s.met" % who))
		"virgin", "oral virgin", "anal virgin", "penile virgin":
			var v = value("%s.%s" % [who, adj.replace(" ", "_")])
			return true if v == null else bool(v)
	# Any other adjective is a flag value of that name: "library_computer is powered".
	return bool(value("%s.%s" % [who, adj.replace(" ", "_")]))


func where(who: String) -> String:
	if who == "player" or who in state.companions:
		return state.location  # companions follow the player
	if state.char_location.has(who):
		return state.char_location[who]
	return state.residence.get(who, content.field_value(who, "lives at"))


func body_count(who: String, part: String) -> int:
	var key: String = {"cock": "cocks", "cunt": "cunts"}.get(part, part)
	var v = value("%s.%s" % [who, key])
	return int(v) if v != null else 0


func part_form(who: String, part: String) -> String:
	part = BodySystem.ALIASES.get(part, part)
	var v = value("%s.body.%s" % [who, part])
	return str(v) if v != null else "human"


func skill_check(stat: String, target: int) -> bool:
	var stat_value := int(value("player.%s" % stat)) if value("player.%s" % stat) != null else 10
	return roll_check(stat.capitalize(), (stat_value - 10) / 2, target, stat)


## A visible d20 roll plus a bonus against a target, shown to the player.
func roll_check(label: String, bonus: int, target: int, stat: String = "") -> bool:
	var roll := rng.range_int(1, 20)
	var ok := roll + bonus >= target
	emit({"type": "roll", "stat": stat, "roll": roll, "bonus": bonus, "target": target, "success": ok,
		"text": "%s %d %+d = %d against %d: %s" % [label + " check: rolled" if label != "" else "Rolled", roll, bonus, roll + bonus, target, "success" if ok else "failure"]})
	return ok


# --- Text -------------------------------------------------------------------

func describe(name: String) -> String:
	# "[children at bunker as offspring_line]": a text snippet once per recorded child living there.
	var cm := RegEx.create_from_string("^children at (\\w+) as (\\w+)$").search(name)
	if cm != null:
		return PregnancySystem.describe_children(self, cm.get_string(1), cm.get_string(2))
	var n := name.strip_edges()
	# "[a cock_size_desc]": the text with "a" or "an" in front.
	if n.begins_with("a ") or n.begins_with("A "):
		var rest := describe(n.substr(2))
		if rest == "":
			return ""
		var article := "an" if rest.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a"
		return "%s %s" % [article.capitalize() if n.begins_with("A") else article, rest]
	# "[worn feet]", "[worn waist, legs, crotch]": the item worn on the first of the
	# slots that has one (the original's feetDesc, crotchDesc, chestDesc), else "".
	if n.begins_with("worn "):
		for slot in n.substr(5).split(","):
			for id: String in state.equipped:
				if ItemSystem.gear(self, id, "slot", "none") == slot.strip_edges():
					return content.typed_value("item", id, "name", id)
		return ""
	# "[player.nipples in words]": a number written out (also an expression: "[a.x + 1 in words]").
	if n.ends_with(" in words"):
		var base := n.trim_suffix(" in words")
		var be := Expr.text_expression(base)
		var counted = Expr.evaluate(be, self) if not be.is_empty() else value(base)
		return number_words(int(counted) if counted != null else 0)
	# "[people.bunker + people.library]": arithmetic on values.
	var calc := Expr.text_expression(n)
	if not calc.is_empty():
		var result = Expr.evaluate(calc, self)
		# A list's entry may be a text ("[entry 1 of x.names]"); a missing entry is nothing.
		return result if result is String else "" if result == null else str(Expr._num(result))
	if n.begins_with("player.") or ("." in n and not " " in n):
		var v = value(n)
		if v is Array:
			return ", ".join(v.map(func(x): return str(x)))  # a list: its entries
		return str(v) if v != null else ""
	var parts := n.split(" of ", true, 1)
	var what := parts[0]
	var who := parts[1] if parts.size() > 1 else "player"
	match what:
		"name":
			if who == "player":
				return str(value("player.name"))
			# "[name of event.item]": the name of the thing a value holds.
			if "." in who:
				var held := str(value(who))
				return content.field_value(held, "name", held)
			return content.field_value(who, "name", who)
		"sir":
			return "sir" if adjective("player", "male") else "ma'am"
		"s", "es":
			var count := int(value(who)) if "." in who else 0
			return what if count > 1 else ""
		"he", "him", "his", "hers", "He", "Him", "His", "Hers":
			return pronoun(who, what)
		"cock":
			# The original's Cock of Player: the cock's descriptive word.
			var word := BodySystem.part_description(self, who, "cock")
			return word if word != "" else "human"
		"head description", "face description", "torso description", "body description", "back description", \
				"arms description", "legs description", "ass description", "tail description", "cock description", \
				"cunt description", "skin description":
			return BodySystem.part_description(self, who, what.get_slice(" ", 0))
		"upper breast curve", "second breast curve", "lower breast curve":
			return BodySystem.breast_curve(self, what.get_slice(" ", 0))
		"marks":
			return BodySystem.marks(self)
		"gear description":
			return ItemSystem.worn_description(self)
		"strip crotch":
			return ItemSystem.strip_text(self, ["waist", "legs", "crotch"], "pull down", "crotch", "stroke over your bare crotch")
		"strip chest":
			return ItemSystem.strip_text(self, ["body", "back", "chest", "breast"], "pull off", "chest", "casually stroke over your bare chest")
		"companions description":
			return companions_description()
		"humanity description":
			return SurvivalSystem.humanity_description(self)
		"species":
			return SurvivalSystem.species(self, who)
		"head species", "torso species", "skin species", "cock species", "cunt species", "tail species":
			# The original's FaceSpeciesName and BodyName, in lower case.
			var form := part_form(who, what.get_slice(" ", 0))
			return content.typed_value("form", form, "name", form).to_lower()
		"body type":
			# The original's bodytype: the body's type, or its name (Infections.i7x:985-988).
			var form := part_form(who, "torso")
			if form == "human":
				return "human"
			var body_type := content.typed_value("form", form, "body type", content.typed_value("form", form, "name", form).to_lower())
			if "[" in body_type:  # "[one of]bunny[or]rabbit[at random]"
				var t := TextTemplate.compile(body_type)
				return body_type if t.has("error") else TextTemplate.plain(render(t))
			return body_type
		"skin":
			var skin = value("%s.body_description.skin" % who)
			return str(skin) if skin != null and str(skin) != "" else "smooth"
		"ghe", "ghis", "ghim", "ghishers", "gche", "gchis", "gchim", "gchishers", "gdragon", "gmasculine":
			return monster_word(what)
		"enemy body type":
			# The original's "type entry": the body type of the creature being fought.
			var foe_form := creature_field(current_creature(), "form", current_creature())
			var foe_type := content.typed_value("form", foe_form, "body type", content.typed_value("form", foe_form, "name", foe_form).to_lower())
			if "[" in foe_type:
				var ft := TextTemplate.compile(foe_type)
				return foe_type if ft.has("error") else TextTemplate.plain(render(ft))
			return foe_type
		"body descriptor":
			# The original's bodydesc (Infections.i7x:982-984, 1072).
			var form := part_form(who, "torso")
			var words: Array = Array(content.typed_value("form", form, "descriptor").split(",", false)).map(func(w): return str(w).strip_edges())
			if words.is_empty():
				words = ["average", "normal", "unchanged"]
			return str(words[variation("body descriptor", words.size(), "at random")])
		"bracket":
			return "["  # a literal bracket, which markup would otherwise read as a substitution
		"close bracket":
			return "]"
		"The enemy", "Enemy name":
			# At the start of a sentence (the original's EnemyCapNameOrTitle).
			var lower := describe(n.to_lower())
			return lower.left(1).to_upper() + lower.substr(1)
		"enemy name", "the enemy":
			# The original's EnemyNameOrTitle: the creature fought (or met last), "the wolf",
			# or a unique creature's own title.
			var foe := current_creature()
			if creature_field(foe, "name known", "no") == "yes" and creature_field(foe, "personal name") != "":
				return creature_field(foe, "personal name")  # the original's enemy type 2: "Yodgrak"
			var title := creature_field(foe, "title")
			var unique := creature_field(foe, "unique", "no") == "yes"
			var word := title if title != "" else creature_field(foe, "name", foe if foe != "" else "creature").to_lower()
			return word if unique or n == "enemy name" else "the " + word
		"picked creature":
			var picked := str(state.values.get("picked.creature", ""))
			return content.typed_value("creature", picked, "name", picked).to_lower()
		"random encountered creature":
			if state.encountered.is_empty():
				return "monster"
			var met: String = state.encountered[rng.range_int(0, state.encountered.size() - 1)]
			return content.typed_value("creature", met, "name", met).to_lower()
		"cup size":
			# The player's cup letter: breast size 1 is an A cup (the original's cupsize).
			var size := int(value("player.breasts.size")) if value("player.breasts.size") != null else 0
			return "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[size - 1] if size >= 1 and size <= 26 else ""
		"cock size":
			return _size_word(int(value("player.cock.length")) if value("player.cock.length") != null else 6)
	# A text snippet about someone else: "[cock_size_desc of francois]".
	if parts.size() > 1 and who != "player" and content.has(what, "text"):
		var described := content.program(what)
		if described != null:
			var before := _subject
			_subject = who
			var text := runner.render_inline(described)
			_subject = before
			return text
	# A text snippet.
	if content.has(n, "text"):
		var prog := content.program(n)
		if prog != null:
			return runner.render_inline(prog)
	warn("Unknown descriptor [%s]" % n)
	return "[%s]" % n


## A number in words, as Inform's "in words" (up to ninety-nine).
static func number_words(n: int) -> String:
	const ONES := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
		"eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
	const TENS := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
	if n < 0 or n > 99:
		return str(n)
	if n < 20:
		return ONES[n]
	return TENS[n / 10] + ("-" + ONES[n % 10] if n % 10 != 0 else "")


## Who travels with the player, as examining yourself says it
## (Game UI.i7x:507-511): "Accompanying you is Fang, who is level 4."
func companions_description() -> String:
	if state.companions.is_empty():
		return ""
	var names: PackedStringArray = []
	for i in state.companions.size():
		var id: String = state.companions[i]
		var level = value(id + ".level")
		if level == null:
			level = content.field_value(id, "level", "")
		var entry := content.field_value(id, "name", id)
		if str(level) != "":
			entry += ", who is level %s" % str(level)
		if i > 0 and i == state.companions.size() - 1:
			entry = "and " + entry
		names.append(entry)
	return "Accompanying you %s %s." % ["is" if names.size() == 1 else "are", ", ".join(names)]


## The player's look in words, as examining yourself shows it: the
## paragraphs of the "self_description" text. Looking changes nothing.
func self_description() -> PackedStringArray:
	var out: PackedStringArray = []
	var prog := content.program("self_description")
	if prog == null:
		return out
	var saved_rng := rng.get_state()
	var saved_variations := state.variations.duplicate(true)
	var paragraphs: Array = runner.render_paragraphs(prog)
	rng.set_state(saved_rng)
	state.variations = saved_variations
	for spans: Array in paragraphs:
		for para in TextTemplate.plain(spans).split("\n"):
			var clean := para.strip_edges()
			while "  " in clean:
				clean = clean.replace("  ", " ")
			if clean != "":
				out.append(clean)
	return out


## The creature being fought, else one a scene picked, else the one met last.
func current_creature() -> String:
	var id: String = str(state.combat.get("creature", "")) if not state.combat.is_empty() else ""
	if id == "" and runner != null:
		id = runner.meeting()  # its encounter scene plays before the fight
	if id == "":
		id = str(state.values.get("picked.creature", ""))  # a creature a scene picked
	if id == "" and not state.encountered.is_empty():
		id = state.encountered[-1]
	return id


## The original's pronouns for the creature being fought or last met
## (Gender Pronouns.i7x Section 4, set by setmongender).
func monster_word(word: String) -> String:
	var g: String = creature_field(current_creature(), "gender", "neuter")
	var set := "male" if g in ["male", "male neuter", "male herm", "cuntboy"] else "female" if g in ["female", "female neuter", "herm", "shemale"] else "neuter"
	var words: Dictionary = {
		"male": {"ghis": "his", "ghe": "he", "ghim": "him", "ghishers": "his", "gdragon": "dragon", "gmasculine": "masculine"},
		"female": {"ghis": "her", "ghe": "she", "ghim": "her", "ghishers": "hers", "gdragon": "dragoness", "gmasculine": "feminine"},
		"neuter": {"ghis": "their", "ghe": "it", "ghim": "it", "ghishers": "theirs", "gdragon": "dragon", "gmasculine": "particular"},
	}[set]
	if word.begins_with("gc"):
		return str(words["g" + word.substr(2)]).capitalize()
	return str(words[word])


## A pronoun of the player or a character. A character's pronouns are the ones
## set in play (`~ character X pronouns she`), else its `pronouns:` field;
## `by body` follows its body now: he with only a cock, she with a cunt, else they.
func pronoun(who: String, form: String) -> String:
	var p := content.field_value(who, "pronouns", "they")
	if state.values.has("character.%s.pronouns" % who):
		p = str(state.values["character.%s.pronouns" % who])
	if who == "player" and value("player.pronouns") != null:
		p = str(value("player.pronouns"))
	if p == "by body":
		p = "she" if body_count(who, "cunt") > 0 else ("he" if body_count(who, "cock") > 0 else "they")
	var table := {
		"he": {"he": "he", "him": "him", "his": "his", "hers": "his"},
		"she": {"he": "she", "him": "her", "his": "her", "hers": "hers"},
		"they": {"he": "they", "him": "them", "his": "their", "hers": "theirs"},
		"it": {"he": "it", "him": "it", "his": "its", "hers": "its"},
	}
	var row: Dictionary = table.get(p, table["they"])
	var word: String = row[form.to_lower()]
	return word.capitalize() if form[0] == form[0].to_upper() else word


func _size_word(length: int) -> String:
	if length < 4:
		return "small"
	if length < 8:
		return "average"
	if length < 14:
		return "large"
	return "huge"


func variation(key: String, count: int, order: String) -> int:
	match order:
		"cycling":
			var i := int(state.variations.get(key, 0))
			state.variations[key] = (i + 1) % count
			return i % count
		"stopping":
			var i := int(state.variations.get(key, 0))
			state.variations[key] = mini(i + 1, count - 1)
			return mini(i, count - 1)
		"sticky":
			if not state.variations.has(key):
				state.variations[key] = rng.range_int(0, count - 1)
			return int(state.variations[key])
		"purely at random":
			return rng.range_int(0, count - 1)
		"as decreasingly likely outcomes":
			# Weights count, count - 1 ... 1, as in Inform.
			var roll := rng.range_int(1, count * (count + 1) / 2)
			for k in count:
				roll -= count - k
				if roll <= 0:
					return k
			return count - 1
		"in random order":
			var deck: Array = state.variations.get(key, [])
			if deck.is_empty():
				for k in count:
					deck.append(k)
				for k in range(count - 1, 0, -1):  # Fisher-Yates with the game's RNG
					var j := rng.range_int(0, k)
					var tmp = deck[k]
					deck[k] = deck[j]
					deck[j] = tmp
			var pick := int(deck.pop_front())
			state.variations[key] = deck
			return pick
	# "at random": never the same choice twice running.
	if count < 2:
		return 0
	var last := int(state.variations.get(key + "@last", -1))
	var choice := rng.range_int(0, count - 2 if last >= 0 else count - 1)
	if last >= 0 and choice >= last:
		choice += 1
	state.variations[key + "@last"] = choice
	return choice


func render(compiled: Dictionary) -> Array:
	return TextTemplate.render(compiled, self)


# --- Effects ----------------------------------------------------------------

func apply(e: Dictionary) -> void:
	var quiet: bool = e.get("quiet", false)
	match e.op:
		"schedule":
			ActionScheduler.schedule(self, e.scene, e.actions)
		"extend_game":
			# The rescue comes later (the original's "extend game by N").
			state.values["game.extended"] = int(state.values.get("game.extended", 0)) + int(Expr._num(Expr.evaluate(e.by, self)))
		"shift_time":
			# An earlier or later stamp; a time never set stays unset ("never").
			if state.stamps.has(e.path):
				state.stamps[e.path] = int(state.stamps[e.path]) + e.sign * int(Expr._num(Expr.evaluate(e.by, self)))
		"set_time":
			# A turn stamp N turns in the past or the future (the original's "turns + 8").
			state.stamps[e.path] = state.turn + e.sign * int(Expr._num(Expr.evaluate(e.by, self)))
		"set":
			if e.has("range"):
				set_value(e.path, rng.range_int(Expr._num(Expr.evaluate(e.range[0], self)), Expr._num(Expr.evaluate(e.range[1], self))))
			else:
				set_value(e.path, Expr.evaluate(e.value, self))
		"change":
			var cur := int(value(e.path)) if value(e.path) != null else 0
			var amount: int = Effect.resolve_amount(e.amount, self, cur)
			var nv: int = cur + e.sign * amount
			if e.amount.has("limit"):
				var lim: int = e.amount.limit_value
				nv = mini(nv, maxi(cur, lim)) if e.amount.limit == "up" else maxi(nv, mini(cur, lim))
			change_value(e.path, nv - cur)
			var said: String = content.values.get(e.path, {}).get("raised" if e.sign > 0 else "lowered", "")
			if said != "" and amount != 0 and not quiet:
				# The value's own text for a change ("when raised:"), with change.owner, change.amount
				# (as asked) and change.value (now), even when a limit kept the value where it was.
				_say_change(said, e.path, absi(amount))
			else:
				notice("%s %+d" % [_label(e.path), int(value(e.path)) - cur], quiet or int(value(e.path)) == cur)
		"survival":
			var amount: int = Effect.resolve_amount(e.amount, self)
			match e.kind:
				"drink":
					_change_stat("thirst", -amount, "Thirst", quiet)
				"eat":
					_change_stat("hunger", -amount, "Hunger", quiet)
				"heal":
					_change_stat("hp", amount, "HP", quiet)
				"hurt":
					_change_stat("hp", -amount, "HP", quiet)
		"give":
			if e.get("item_path", "") != "":
				e = e.duplicate()
				e.item = str(value(e.item_path))
			var n: int = Effect.resolve_amount(e.amount, self)
			ItemSystem.gain(self, e.item, n)
			notice("Gained: %s%s" % [content.field_value(e.item, "name", e.item), " x%d" % n if n > 1 else ""], quiet)
		"give_one":
			# One item picked at random, as the original's random list entries.
			var picked: String = e.items[rng.range_int(0, e.items.size() - 1)]
			ItemSystem.gain(self, picked, 1)
			notice("Gained: %s" % content.field_value(picked, "name", picked), quiet)
		"take", "take_all":
			if e.get("item_path", "") != "":
				e = e.duplicate()
				e.item = str(value(e.item_path))
			var have := int(state.inventory.get(e.item, 0))
			var n: int = ItemSystem.lose(self, e.item, have if e.op == "take_all" else Effect.resolve_amount(e.amount, self))
			if n > 0:
				notice("Lost: %s%s" % [content.field_value(e.item, "name", e.item), " x%d" % n if n > 1 else ""], quiet)
		"feat":
			if e.add and e.feat not in state.feats:
				state.feats.append(e.feat)
				notice("Feat gained: %s" % e.feat.capitalize(), quiet)
			elif not e.add and e.feat in state.feats:
				state.feats.erase(e.feat)
				notice("Feat lost: %s" % e.feat.capitalize(), quiet)
		"trait":
			var list: Array = state.traits.get(e.who, [])
			if e.add and e.trait not in list:
				list.append(e.trait)
			elif not e.add:
				list.erase(e.trait)
			state.traits[e.who] = list
		"companion":
			if e.add and e.who not in state.companions:
				CompanionSystem.join(self, e.who)
				notice("%s joins you." % content.field_value(e.who, "name", e.who), quiet)
			elif not e.add:
				CompanionSystem.leave(self, e.who)
		"tame":
			CompanionSystem.tame(self, e.who, e.yes)
			if e.yes:
				notice("%s can now join you." % content.field_value(e.who, "name", e.who), quiet)
		"summon":
			CompanionSystem.summon(self, e.who)
		"dismiss":
			CompanionSystem.dismiss(self, e.who)
		"cancel_companion":
			cancel_companion = true
		"companion_level":
			if e.who == "player":
				LevelSystem.level_up(self)
			else:
				CompanionSystem.level_up(self, e.who)
		"check_level":
			LevelSystem.check(self)
		"choose_feat":
			runner.choose_feat(e.group)
		"ask_item":
			runner.choose_item(e.path, e.tag, e.prompt)
		"ask":
			if e.get("number", false):
				# A typed number, within its bounds when it has them (worked out now).
				var low = Expr._num(Expr.evaluate(e.low, self)) if e.has("low") else null
				var high = Expr._num(Expr.evaluate(e.high, self)) if e.has("high") else null
				runner.ask_number(e.path, e.prompt, low, high)
			else:
				runner.ask_text(e.path, e.prompt, e.max)
		"send_children":
			CompanionSystem.move_children(self, e.from, e.to)
		"quest":
			var path := "quest.%s" % e.quest
			set_value(path, e.stage)
			var journal: String = content.quests.get(e.quest, {}).get("journal", {}).get(e.stage, "")
			notice("Quest updated: %s%s" % [content.field_value(e.quest, "name", e.quest), (" - " + journal) if journal else ""], quiet)
		"outcome":
			var ev: String = e.get("event", "")
			if ev == "":
				ev = runner.current_event()
			if ev != "":
				set_value("%s.outcome" % ev, e.outcome)
		"resolve":
			var ev: String = e.get("event", "")
			if ev == "":
				ev = runner.current_event()
			if ev != "":
				_event(ev).resolved = true
		"unresolve":
			# Found again from now on; its outcome and resolution number stay, as in the original.
			_event(e.event).resolved = false
		"activate", "deactivate":
			_event(e.event).active = e.op == "activate"
		"form_sex":
			state.values["form.%s.sex" % e.form] = e.sex
		"form_number":
			state.values["form.%s.%s.%s" % [e.form, e.part, e.key]] = int(Expr._num(Expr.evaluate(e.value, self)))
		"sex_change":
			BodySystem.change_again(self, e.what, e.form, e.get("keep_cock", false))
		"lock":
			# A door locked or unlocked in play; it stays so (saved), whatever its `locked:` says.
			state.values["door.%s.locked" % e.door] = e.locked
		"list_add", "list_remove", "list_remove_entry", "list_clear", "list_sort":
			_change_list(e)
		"change_exit":
			# "change the north exit of X to Y" (the original's map changes): saved, and
			# shown on the map and the place's ways out from now on.
			var changed: Dictionary = state.exits.get(e.place, {})
			changed[e.direction] = e.to
			state.exits[e.place] = changed
		"grow":
			BodySystem.grow(self, e.part, Effect.resolve_amount(e.amount, self))
		"creature_change":
			state.values["creature.%s.%s" % [e.creature, e.field]] = e.value
		"creature_number":
			# A lasting change to a creature's numbers ("increase wdam entry by 2").
			var cur := CombatSystem.stat(self, e.creature, e.field) if e.field in CombatSystem.ATTRIBUTES \
				else int(creature_field(e.creature, e.field, "0"))
			var amount: int = Effect.resolve_amount(e.amount, self, cur)
			var nv: int = amount if e.how == "=" else cur + (amount if e.how == "+" else -amount)
			state.values["creature.%s.%s" % [e.creature, e.field]] = nv
		"player_move":
			if state.combat.is_empty() or state.combat.result != "":
				if state.combat.is_empty():
					warn("'%s' only works during a fight." % ("attack enemy" if e.move == "attack" else "try to flee"))
				return
			if e.move == "attack":
				CombatSystem.player_attack(self)
			else:
				CombatSystem.player_flee(self)
		"enemy_attack", "enemy_strike", "fight_result":
			if state.combat.is_empty():
				warn("'%s' only works during a fight." % e.op.replace("_", " "))
				return
			var id: String = state.combat.creature
			match e.op:
				"enemy_attack":
					if CombatSystem.hit_roll(self, creature_field(id, "strike with", "dexterity")):
						for spans in runner.render_paragraphs(content.program(id + "#attack", "creature"), 0, true):
							emit({"type": "paragraph", "spans": spans})
						CombatSystem.strike(self, CombatSystem.roll_damage(self, id, e.percent))
					else:
						notice(TextTemplate.plain(render(TextTemplate.compile("[The enemy] misses."))), quiet)
				"enemy_strike":
					var damage: int = Effect.resolve_amount(e.amount, self) if e.has("amount") else CombatSystem.roll_damage(self, id, e.percent)
					CombatSystem.strike(self, damage, e.armor, not quiet)
				"fight_result":
					state.combat.result = e.result
		"put":
			var place: String = state.location if e.place == "here" else e.place
			var ground := ItemSystem.ground(self, place)
			ground[e.item] = int(ground.get(e.item, 0)) + e.count
		"remove_from":
			var place: String = state.location if e.place == "here" else e.place
			ItemSystem.ground(self, place).erase(e.item)
		"item_strain":
			# "now Strain of skunk goo is ..." (the original's strain of an infectious item).
			state.values["item.%s.infectious" % e.item] = "" if e.form == "nothing" else e.form
		"move":
			if e.who == "player":
				go_to(e.place)
			else:
				state.char_location[e.who] = e.place
		"character_pronouns":
			if e.pronouns == "default":
				state.values.erase("character.%s.pronouns" % e.who)
			else:
				state.values["character.%s.pronouns" % e.who] = e.pronouns
		"character_image":
			if e.image == "default":
				state.values.erase("character.%s.image" % e.who)
			else:
				state.values["character.%s.image" % e.who] = e.image
		"lives_at":
			state.residence[e.who] = e.place
			state.char_location.erase(e.who)
		"forget":
			# The original's "now X is unknown": no longer a fast travel point the player knows.
			state.known.erase(e.place)
		"use_item":
			runner.use_item_now(e.item)
		"discover":
			if not state.known.has(e.place):
				state.known[e.place] = true
				notice("Discovered: %s" % content.field_value(e.place, "name", e.place), quiet)
		"go":
			go_to(e.place)
		"spend":
			for _t in e.turns:
				pass_turn()
		"sex":
			# "enemy" stands for the creature being fought or met (vore and fight scenes).
			var taker: String = current_creature() if e.taker == "enemy" else e.taker
			var giver: String = current_creature() if e.giver == "enemy" else e.giver
			SexSystem.record(self, taker, e.act, giver)
			if giver == "player":
				PregnancySystem.after_sex(self, taker, e.act)  # a creature may carry the player's young
		"condition":
			start_condition(e.condition, e.turns, quiet)
		"infects_as":
			# Only during a fight's scenes: the loss infection uses this creature.
			if not state.combat.is_empty():
				state.combat["infects_as"] = e.creature
		"pick":
			runner.pick_creature(e.tag, e.zone, e.favoring, e.get("with_outside", false))
			var picked := str(state.values.get("picked.creature", ""))
			if picked != "":
				BodySystem.remember_strain(self, creature_field(picked, "form", picked))
		"infect":
			var form: String = e.form if e.get("part", "") == "" else part_form("player", e.part)
			if form == "@picked":
				# The creature picked with "~ pick random creature": its form.
				var picked := str(value("picked.creature"))
				form = content.typed_value("creature", picked, "form", picked) if picked != "" else ""
				if form == "":
					return
			var source := str(value("picked.creature")) if e.form == "@picked" else form
			for _i in Effect.resolve_amount(e.times, self):
				state.values["infection.bypass"] = content.has(source, "creature") and creature_field(source, "research bypass", "no") == "yes"
				BodySystem.infect(self, form, false, e.get("keep_sex", false))
		"transform":
			if e.has("form_path"):
				var kept = value(e.form_path)
				if kept != null and str(kept) != "":
					BodySystem.set_part(self, str(kept), e.part)
			elif e.get("part", "") != "":
				BodySystem.set_part(self, e.form, e.part)
			else:
				BodySystem.infect(self, e.form, true)
		"reset_human":
			BodySystem.reset(self)
		"cancel_use":
			use_cancelled = true
		"no_fight":
			fight_cancelled = true
		"impregnate":
			PregnancySystem.attempt(self, e.kind, e.father, e.eggs, e.sure)
		"accept_pregnancy":
			PregnancySystem.accept(self)
		"pregnancy_faster":
			# The original's "decrease gestation of child by N": never past the last turn.
			if PregnancySystem.gestation(self) > 0:
				state.values["pregnancy.gestation"] = maxi(1, PregnancySystem.gestation(self) - int(e.by))
		"give_birth":
			if PregnancySystem.gestation(self) > 0:
				PregnancySystem.birth(self)
		"record_child":
			PregnancySystem.record_child(self)
		"new_child":
			PregnancySystem.new_child(self)
		"child_random":
			PregnancySystem.random_child_value(self, e.what)
		"each_child":
			PregnancySystem.each_child(self, e.home, e.scene)
		"end_pregnancy":
			PregnancySystem.end(self)
		"vore":
			VoreSystem.perform(self, e.kind)
		"absorb_enemy_stat":
			VoreSystem.absorb_stat(self, quiet)
		"infect_enemy":
			VoreSystem.infect_enemy(self)
		"unbirth_pregnancy":
			PregnancySystem.unbirth(self, e.get("creature", "") if e.get("creature", "") != "" else current_creature())
		"continue_moving":
			continue_moving = true
		"end_captivity":
			captivity_exit = "escape" if e.get("escape", false) else "end"
		"end_heat":
			HeatSystem.end_now(self)
		"extend_heat":
			HeatSystem.extend(self, int(e.turns))
		"drive_heat":
			HeatSystem.drive(self, e.get("now", false))
		"reset_heat":
			HeatSystem.reset(self)
		"set_level":
			# A scene can change a content level the player chose (a doctor adjusting your heat).
			set_level(e.level, e.option)
		"wear":
			ItemSystem.wear(self, e.item, quiet)
		"remove":
			ItemSystem.remove(self, e.item, quiet)
		"wield":
			ItemSystem.wield(self, e.item, quiet)
		"unwield":
			ItemSystem.unwield(self, quiet)
		"resize":
			ItemSystem.resize(self, e.to, quiet)
		"meter":
			# Changes a meter, such as alcohol, and applies its stage.
			var path := content.typed_value("meter", e.meter, "value")
			var cur := int(value(path)) if value(path) != null else 0
			state.values[path] = maxi(0, cur + e.sign * Effect.resolve_amount(e.amount, self))
			MeterSystem.update(self, e.meter)
		"ending":
			# The game ends here; the epilogue plays (EndingSystem).
			if content.has(e.ending, "ending"):
				EndingSystem.trigger(self, e.ending)
			end_game(e.ending, e.ending)
		"trigger_ending":
			EndingSystem.trigger(self, e.ending)
		"end_state":
			EndingSystem.set_state(self, e.state)
		"ending_reason":
			state.values["end.reason"] = e.reason
		"ending_flag":
			EndingSystem.flag(self, e.flag)
		"exclude_endings":
			EndingSystem.exclude(self, e.type)
		_:
			warn("Effect '%s' is not supported yet." % e.op)
			emit({"type": "notice", "text": "[effect '%s' not implemented yet]" % e.op})


## The list effects: a changed copy of the list is stored (lists are saved with the game).
func _change_list(e: Dictionary) -> void:
	var current = value(e.path)
	var list: Array = (current as Array).duplicate() if current is Array else []
	match e.op:
		"list_add":
			for item: Dictionary in e.items:
				var v = Expr.evaluate(item, self)
				if not (e.if_absent and Condition.list_has(list, v)):
					list.append(v)
		"list_remove":
			# Every entry equal to the value goes, as the original's "remove X from L".
			for item: Dictionary in e.items:
				var v = Expr.evaluate(item, self)
				list = list.filter(func(x): return not Condition.compare(x, "=", v, {}, self))
		"list_remove_entry":
			var at := Expr._num(Expr.evaluate(e.items[0], self))
			if at >= 1 and at <= list.size():
				list.remove_at(at - 1)
		"list_clear":
			list = []
		"list_sort":
			match e.order:
				"random":
					# Shuffled with the game's own random numbers, so a seed replays the same.
					for i in range(list.size() - 1, 0, -1):
						var j: int = rng.range_int(0, i)
						var t = list[i]
						list[i] = list[j]
						list[j] = t
				"reverse":
					list.sort_custom(func(a, b): return _list_before(b, a))
				_:
					list.sort_custom(func(a, b): return _list_before(a, b))
	set_value(e.path, list)


## The order of list entries: numbers by size, then texts alphabetically.
static func _list_before(a: Variant, b: Variant) -> bool:
	if a is String or b is String:
		if (a is String) != (b is String):
			return not a is String  # numbers first
		return str(a) < str(b)
	return Expr._num(a) < Expr._num(b)


func _change_stat(key: String, delta: int, label: String, quiet: bool) -> void:
	var path := "player." + key
	var cur := int(value(path))
	set_value(path, cur + delta)
	var diff := int(value(path)) - cur
	notice("%s %+d" % [label, diff], quiet or diff == 0)


func _say_change(text: String, path: String, amount: int) -> void:
	var owner := path.get_slice(".", 0)
	var saved := {}
	for k in ["owner", "amount", "value"]:
		if state.values.has("change." + k):
			saved[k] = state.values["change." + k]
	state.values["change.owner"] = owner
	state.values["change.amount"] = amount
	state.values["change.value"] = value(path)
	emit({"type": "paragraph", "spans": render(TextTemplate.compile(text))})
	for k in ["owner", "amount", "value"]:
		state.values.erase("change." + k)
		if saved.has(k):
			state.values["change." + k] = saved[k]


func _label(path: String) -> String:
	return path.substr(7).capitalize() if path.begins_with("player.") else path


func _event(id: String) -> Dictionary:
	if not state.events.has(id):
		state.events[id] = {"resolved": false, "active": content.typed_value("event", id, "active", "yes") == "yes", "last_turn": -1}
	return state.events[id]


# --- Content settings -------------------------------------------------------

## "normal", "warded" or "banned".
func filter_state(id: String) -> String:
	if id in settings.banned:
		return "banned"
	if id in settings.warded:
		return "warded"
	return "normal"


## Wards can change at any time. Bans are chosen before the game starts,
## as in the original; afterwards a filter can't be banned or unbanned here.
func can_set_filter(id: String, to: String) -> bool:
	if not content.has(id, "filter") or to not in FILTER_STATES:
		return false
	var current := filter_state(id)
	return current == to or not settings.started or (current != "banned" and to != "banned")


func set_filter(id: String, to: String) -> bool:
	if not can_set_filter(id, to):
		return false
	settings.banned.erase(id)
	settings.warded.erase(id)
	if to != "normal":
		settings[to].append(id)
	return true


## The chosen option of a content level, or its default.
## Whether the player is interested in `id` (an `== interest`, the original's
## MaleInterest and friends): the player's choice, else the interest's default.
func interest(id: String) -> bool:
	var chosen: Dictionary = settings.get("interests", {})
	if chosen.has(id):
		return bool(chosen[id])
	return content.typed_value("interest", id, "default", "yes") == "yes"


## Sets an interest; the player can change interests at any time, as in the original.
func set_interest(id: String, on: bool) -> bool:
	if not content.has(id, "interest"):
		return false
	if not settings.has("interests"):
		settings["interests"] = {}
	settings.interests[id] = on
	return true


## Interested in every declared interest (the original's pansexual).
func interested_in_all() -> bool:
	var ids: Array = content.all_of("interest").keys()
	return not ids.is_empty() and ids.all(func(i): return interest(str(i)))


func level(id: String) -> String:
	if settings.levels.has(id):
		return str(settings.levels[id])
	return str(content.levels.get(id, {}).get("default", "standard"))


## Sets a content level. Some options ban or allow filters, such as no vore
## banning the vore filters; this applies during play too, as in the original.
func set_level(id: String, option: String) -> bool:
	var decl: Dictionary = content.levels.get(id, {})
	if option not in decl.get("options", []):
		return false
	settings.levels[id] = option
	for f in decl.bans.get(option, []):
		settings.warded.erase(f)
		if f not in settings.banned:
			settings.banned.append(f)
	for f in decl.allows.get(option, []):
		settings.banned.erase(f)
	return true


## The filter that keeps tagged content out, or "". Banned filters always
## do; warded filters only keep content out of random selection.
## A character whose tags hold a banned filter is hidden: not shown at its place,
## and its talk, sex, look, smell, actions and summoning are not offered. Wards
## do not hide characters (the player seeks them out, as with a hunt).
func character_hidden(id: String) -> bool:
	return content.has(id, "character") and filter_block(content._list(content.get_def("character", id), "tags"), true) != ""


func filter_block(tags: Array, hunted: bool = false) -> String:
	for t in tags:
		if t in settings.banned:
			return str(t)
	if not hunted:
		for t in tags:
			if t in settings.warded:
				return str(t)
	return ""


## Filters and levels for a settings screen, in content order.
func content_settings() -> Dictionary:
	var filters: Array = []
	for id in content.all_of("filter"):
		filters.append({"id": id, "name": content.typed_value("filter", id, "name", str(id).capitalize()),
			"group": content.typed_value("filter", id, "group"), "description": content.typed_value("filter", id, "description"),
			"state": filter_state(id), "can_ban": can_set_filter(id, "banned"), "can_normal": can_set_filter(id, "normal"),
			"can_ward": can_set_filter(id, "warded")})
	var levels: Array = []
	for id in content.levels:
		var lv: Dictionary = content.levels[id]
		var options: Array = []
		for o in lv.options:
			options.append({"id": o, "name": str(o).capitalize(), "description": lv.text.get(o, "")})
		levels.append({"id": id, "name": content.typed_value("level", id, "name", str(id).capitalize()),
			"description": content.typed_value("level", id, "description"), "options": options, "value": level(id)})
	var interests: Array = []
	for id in content.all_of("interest"):
		interests.append({"id": id, "name": content.typed_value("interest", id, "name", str(id).capitalize()),
			"group": content.typed_value("interest", id, "group"), "description": content.typed_value("interest", id, "description"),
			"value": interest(id)})
	return {"filters": filters, "levels": levels, "interests": interests, "started": settings.started}


# --- World and time ---------------------------------------------------------

## Starts a new game with a scenario. `choices` holds the new-game answers
## (CreationSystem: question ID -> option index, "feat <group>" -> feat ID);
## the game's modes are already in `settings.mode`.
func start_scenario(id: String, name: String = "Player", pronouns: String = "he", choices: Dictionary = {}) -> bool:
	if not content.has(id, "scenario"):
		warn("The scenario is not available.")
		return false
	state = GameState.new()
	runner.frames.clear()
	runner.pending.clear()
	runner.status = "idle"
	last_fight = ""
	output.clear()
	settings.scenario = id
	settings.started = true
	set_value("player.name", name)
	set_value("player.pronouns", pronouns)
	CreationSystem.create(self, choices)
	output.clear()  # creation speaks quietly; the game starts with the scenario
	start(content.typed_value("scenario", id, "start"))
	runner.start(id + "#setup")
	runner.emit_title(content.typed_value("scenario", id, "name", id))
	runner.start(id + "#intro")
	return true

## Starts a new game at a location.
func start(location: String) -> void:
	for id in content.all_of("location"):
		if "known at start" in content.list_field(id, "flags"):
			state.known[id] = true
	go_to(location)


func go_to(place: String) -> void:
	if not content.has(place, "location"):
		warn("No location '%s'." % place)
		return
	state.location = place
	state.visited[place] = true
	if not state.known.has(place):
		set_value("player.score", int(value("player.score")) + 1)
	state.known[place] = true
	runner.show_location()
	var arrival := content.program(place + "#enter")
	if arrival != null:
		runner.play_now(arrival.id)


## The zone exploring, hunting and resting use at a place: its own zone, or the
## zone of a dangerous door out of it (the original's marea), or "".
func zone_here(loc: String = "") -> String:
	if loc == "":
		loc = state.location
	var zone := content.typed_value("location", loc, "zone")
	if zone not in ["", "none"]:
		return zone
	for door in runner.exit_doors(loc):
		var z := content.typed_value("door", door, "leads to zone")
		if z != "":
			return z
	return ""


## People staying at places with a flag (`people.collected` is the original's
## "number of collected people", `people.bunker` its bunkered people ...).
## Characters tagged `uncounted` (a talking book, a ghost) are left out.
func people_at(flag: String) -> int:
	var n := 0
	for c in content.all_of("character"):
		if "uncounted" in content.list_field(c, "tags"):
			continue
		var at := where(c)
		if at != "" and flag in content.list_field(at, "flags"):
			n += 1
	return n



func feat_bonus(field: String) -> int:
	var bonus := 0
	for id in state.feats:
		bonus += int(content.typed_value("feat", id, field, "0"))
	# Game modes chosen at the start carry the same bonuses (Blind Mode's better exploring).
	for id in settings.mode:
		if content.has(id, "game_mode"):
			bonus += int(content.typed_value("game_mode", id, field, "0"))
	return bonus


## Ends the game: `cause` is what ended it (an ending's ID, "humanity", "rescue",
## "hunger" ...), `ending` what `state.ending` records. The scene runner then
## plays the epilogue (EndingSystem).
func end_game(cause: String, ending: String) -> void:
	if state.ending != "":
		return
	state.ending = ending
	state.values["end.cause"] = cause
	emit({"type": "ending", "ending": ending})
	runner.begin_epilogue()


func pass_turn() -> void:
	if state.ending != "":
		return
	var was_day := is_day()
	state.turn += 1
	SurvivalSystem.tick(self)
	RestSystem.tick(self)
	ItemSystem.tick(self)
	MeterSystem.tick(self)
	HeatSystem.tick(self)
	PregnancySystem.tick(self)
	CompanionSystem.tick(self)
	for c in state.conditions.keys():
		state.conditions[c].remaining -= 1
		if state.conditions[c].remaining > 0:
			var each := content.program("%s#each turn" % c, "condition")
			if each != null:
				runner.play_now(each.id)
		else:
			end_condition(c)
	run_hooks("each turn")
	if is_day() != was_day:
		run_hooks("day starts" if is_day() else "night starts")  # sunrise and sunset


## The moments hooks can run at (`on:` of a hook).
const HOOK_MOMENTS := ["each turn", "day starts", "night starts", "captivity starts", "captivity round", "after sex", "player hits",
	"after resting", "instead of resting"]
## Moments about one character: "instead of talking to adam", "instead of sex with adam".
const HOOK_CHARACTER_MOMENTS := ["instead of talking to ", "instead of sex with "]


## Runs the form turn hook of the player's body, then the hooks for `moment`
## in pack load order. `when:` must hold; `while incapacitated: skip` skips a
## hook while the player is in a fight.
func run_hooks(moment: String) -> void:
	if moment == "each turn":
		var each := content.program("%s#each turn" % part_form("player", "torso"), "form")
		if each != null:
			runner.play_now(each.id)
	for id: String in content.all_of("hook"):
		if _hook_applies(id, moment):
			runner.play_now(content.program("%s#do" % id, "hook").id)


## An "instead of" moment: the script of the first hook (in pack load order) for
## it whose `when:` holds, which plays instead of the action; "" when none does.
func hook_instead(moment: String) -> String:
	for id: String in content.all_of("hook"):
		if _hook_applies(id, moment):
			return content.program("%s#do" % id, "hook").id
	return ""


## Whether a hook for `moment` exists at all (without checking its `when:`).
func has_hook(moment: String) -> bool:
	return content.all_of("hook").keys().any(func(id): return content.typed_value("hook", id, "on") == moment)


func _hook_applies(id: String, moment: String) -> bool:
	if content.typed_value("hook", id, "on") != moment:
		return false
	if content.typed_value("hook", id, "while incapacitated") == "skip" and not state.combat.is_empty():
		return false
	var when := content.typed_value("hook", id, "when")
	if when != "" and not Condition.evaluate(Condition.compile(when), self):
		return false
	return content.program("%s#do" % id, "hook") != null


# --- Views for the interface (read-only) -----------------------------------

func day() -> int:
	return 1 + state.turn / 8


func status_snapshot() -> Dictionary:
	var stats := {}
	for k in PLAYER_DEFAULTS:
		stats[k] = value("player." + k)
	var loc := state.location
	return {"location": content.field_value(loc, "name", loc), "region": content.field_value(content.field_value(loc, "region"), "name", ""),
		"day": day(), "time": time_slot(), "stats": stats, "conditions": state.conditions.keys(),
		"sleep": RestSystem.status(self),
		"companions": state.companions.map(func(c): return content.field_value(c, "name", c))}


## The top bar's meters and money: the game's `== status_bar` (its `meters` are
## player values, `currency` one more), else health alone. Each meter has a
## label (a meter definition's name, "Health" for hp) and a maximum (maxhp for
## hp, a meter's limit, else 100).
func status_bar() -> Dictionary:
	var keys: Array = ["hp"]
	var currency := ""
	var defs: Dictionary = content.all_of("status_bar")
	if not defs.is_empty():
		var id: String = defs.keys()[0]
		keys = content._list(content.get_def("status_bar", id), "meters")
		currency = content.typed_value("status_bar", id, "currency")
	var out: Array = []
	for k: String in keys:
		var label := "Health" if k == "hp" else k.capitalize()
		var top := 100
		var meter := MeterSystem.owner_of(self, "player." + k)
		if meter != "":
			label = content.typed_value("meter", meter, "name", label)
			var limit := int(content.typed_value("meter", meter, "limit", "0"))
			top = limit if limit > 0 else top
		if k == "hp":
			top = int(value("player.maxhp"))
		var v = value("player." + k)
		out.append({"key": k, "label": label, "value": int(v) if v != null else 0, "max": top})
	var money = value("player." + currency) if currency != "" else null
	# Values the character sheet lists besides the meters (`sheet:`).
	var sheet: Array = []
	if not defs.is_empty():
		for k: String in content._list(content.get_def("status_bar", defs.keys()[0]), "sheet"):
			var meter := MeterSystem.owner_of(self, "player." + k)
			var label: String = content.typed_value("meter", meter, "name", k.capitalize()) if meter != "" else k.capitalize()
			var sv = value("player." + k)
			sheet.append({"key": k, "label": label, "value": int(sv) if sv != null else 0})
	return {"meters": out, "currency": currency, "money": int(money) if money != null else 0, "sheet": sheet}


## Carried items for the inventory. "section" follows the original's
## listing: equipment, armaments, consumables, other (Inventory.i7x:66-229).
func inventory_list() -> Array:
	var out: Array = []
	var order := ["equipment", "armaments", "consumables", "other"]
	for id in state.inventory:
		var d := content.get_def("item", id)
		var wearable := ItemSystem.is_wearable(self, id)
		var weapon := ItemSystem.is_weapon(self, id)
		var consumed := content.typed_value("item", id, "consumed", "yes") != "no"
		var section := "equipment" if wearable else "armaments" if weapon else "consumables" if consumed and d != null and (d.fields.has("use") or d.fields.has("use action")) else "other"
		out.append({"id": id, "name": content.typed_value("item", id, "name", id), "count": int(state.inventory[id]),
			"category": content.typed_value("item", id, "category", "other"), "section": section,
			"description": item_description(id),
			"usable": d != null and (d.fields.has("use") or d.fields.has("use action")), "weight": int(content.typed_value("item", id, "weight", "0")),
			"wearable": wearable, "worn": id in state.equipped, "weapon": weapon, "wielded": state.wielded == id,
			"cursed": ItemSystem.gear(self, id, "cursed", "no") == "yes",
			"keep": content.typed_value("item", id, "keep", "no") == "yes",
			"purifiable": ItemSystem.microwave_here(self),
			"slot": ItemSystem.gear(self, id, "slot", "") if wearable else ""})
	out.sort_custom(func(a, b): return [order.find(a.section), a.name] < [order.find(b.section), b.name])
	return out


## An item's description with its weapon remarks, as examining it shows.
func item_description(id: String) -> String:
	var text := content.typed_value("item", id, "description", "")
	var prog := content.program("item:%s#description" % id)
	if prog != null:
		# Looking at the inventory changes nothing: no dice, no variation state.
		var saved_rng := rng.get_state()
		var saved_variations := state.variations.duplicate(true)
		text = runner.render_inline(prog)
		rng.set_state(saved_rng)
		state.variations = saved_variations
	var remark := ItemSystem.size_remark(self, id)
	return text + ("\n" + remark if remark != "" else "")


## Weight carried, capacity and what is worn and wielded, for the interface.
func gear_summary() -> Dictionary:
	return {"weight": ItemSystem.carried_weight(self), "capacity": ItemSystem.capacity(self),
		"overburdened": ItemSystem.overburdened(self),
		"worn": state.equipped.map(func(id): return {"id": id, "name": content.typed_value("item", id, "name", id),
			"slot": ItemSystem.gear(self, id, "slot", "none"), "cursed": ItemSystem.gear(self, id, "cursed", "no") == "yes"}),
		"wielded": state.wielded, "weapon": content.typed_value("item", state.wielded, "name", "") if state.wielded != "" else ""}


## Items lying at the player's location: [{id, name, count}].
func ground_list() -> Array:
	var out: Array = []
	var here := ItemSystem.ground(self, state.location)
	for id in ItemSystem.ground_ids(self, state.location):
		out.append({"id": id, "name": content.typed_value("item", id, "name", id), "count": int(here[id])})
	return out


func quest_list() -> Array:
	var out: Array = []
	for id in content.quests:
		var q: Dictionary = content.quests[id]
		var stage := str(value("quest." + id))
		var idx: int = q.stages.find(stage)
		if idx <= 0:
			continue
		var history: Array = []
		for k in range(1, idx):
			if q.journal.get(q.stages[k], "") != "":
				history.append(q.journal.get(q.stages[k], ""))
		var done_at := content.field_value(id, "done at", q.stages[-1])
		# A `journal:` text says where the quest stands now, worked out when the journal is
		# shown (the original's quest log phrases); else the stage's own line.
		var line: String = q.journal.get(stage, "")
		var written: Program = content.program("%s#journal" % id, "quest")
		if written != null:
			line = runner.render_inline(written)
		out.append({"id": id, "name": content.field_value(id, "name", id),
			"region": content.field_value(content.field_value(id, "region"), "name", "Other"),
			"stage": stage, "journal": line, "history": history,
			"done": q.stages.find(done_at) <= idx})
	return out


## Known fast-travel points the player can travel to from here (none if the
## current location is not a fast-travel point).
func travel_destinations() -> Array:
	var out: Array = []
	if "fast travel" not in content.list_field(state.location, "flags"):
		return out
	for id in content.all_of("location"):
		if id != state.location and state.known.has(id) and "fast travel" in content.list_field(id, "flags"):
			out.append({"id": id, "name": content.field_value(id, "name", id),
				"region": content.field_value(content.field_value(id, "region"), "name", "")})
	out.sort_custom(func(a, b): return a.region + a.name < b.region + b.name)
	return out


## A place's ways out as [direction, exit] pairs ("north", "plaza, door gate"): its
## `exits:` with the changes made in play (`~ change north exit of X to Y`).
func exits_of(loc: String) -> Array:
	var out: Array = []
	var changed: Dictionary = state.exits.get(loc, {})
	var d: FscParser.Definition = content.get_def("location", loc)
	var f: FscParser.Field = d.fields.get("exits", null) if d != null else null
	var seen: Array = []
	if f != null:
		for l in f.children:
			if l.is_blank() or ":" not in l.text:
				continue
			var parts := l.text.split(":", true, 1)
			var dir := parts[0].strip_edges()
			seen.append(dir)
			if not changed.has(dir):
				out.append([dir, parts[1].strip_edges()])
			elif str(changed[dir]) != "":
				out.append([dir, str(changed[dir])])
	for dir: String in changed:
		if dir not in seen and str(changed[dir]) != "":
			out.append([dir, str(changed[dir])])
	return out


## Locations of a region with map positions, for the map and mini map.
func map_data(region: String = "") -> Dictionary:
	if region == "":
		region = content.field_value(state.location, "region")
	var places: Array = []
	for id in content.all_of("location"):
		if content.field_value(id, "region") != region:
			continue
		var pos := content.field_value(id, "map").split(",")
		if pos.size() < 2:
			continue
		var exits: Array = []
		for pair: Array in exits_of(id):
			var to := SceneRunner.exit_target(pair[1])
			if to != "":
				exits.append(to)
		places.append({"id": id, "name": content.field_value(id, "name", id), "x": int(pos[0]), "y": int(pos[1]),
			"known": state.known.has(id), "current": id == state.location, "exits": exits,
			"fast_travel": "fast travel" in content.list_field(id, "flags")})
	return {"region": region, "name": content.typed_value("region", region, "name", region),
		"image": content.typed_value("region", region, "image"), "places": places}


# --- Timed conditions -------------------------------------------------------

## Starts a condition, or extends it if it is already active. Its "while
## active" effects are applied now and undone when it ends; what they
## changed is remembered in the condition's entry (saved with the game).
func start_condition(id: String, turns: int, quiet: bool = false, refresh: bool = false) -> void:
	var name := content.typed_value("condition", id, "name", id)
	if state.conditions.has(id):
		state.conditions[id].remaining = turns if refresh else int(state.conditions[id].remaining) + turns
		notice("%s lasts longer (%d turns left)" % [name, state.conditions[id].remaining], quiet)
		return
	var entry := {"remaining": turns, "undo": []}
	for e in condition_effects(id):
		match e.op:
			"feat":
				entry.undo.append({"feat": e.feat, "had": e.feat in state.feats})
			"set":
				entry.undo.append({"path": e.path, "had": state.values.has(e.path), "value": state.values.get(e.path)})
			"change":
				var before := int(value(e.path))
				apply(e)
				entry.undo.append({"path": e.path, "delta": int(value(e.path)) - before})
				continue
		apply(e)
	state.conditions[id] = entry
	notice("%s (%d turns)" % [name, turns], quiet)


func end_condition(id: String) -> void:
	var entry: Dictionary = state.conditions.get(id, {})
	state.conditions.erase(id)
	var undo: Array = entry.get("undo", [])
	undo.reverse()
	for u in undo:
		if u.has("feat"):
			if u.had and u.feat not in state.feats:
				state.feats.append(u.feat)
			elif not u.had:
				state.feats.erase(u.feat)
		elif u.has("delta"):
			change_value(u.path, -int(u.delta))
		elif u.had:
			state.values[u.path] = u.value
		else:
			state.values.erase(u.path)
	var prog := content.program("%s#ends" % id, "condition")
	if prog != null:
		runner.play_now(prog.id)


## The compiled "while active" effects of a condition.
func condition_effects(id: String) -> Array:
	var out: Array = []
	var d := content.get_def("condition", id)
	if d == null or not d.fields.has("while active"):
		return out
	for l in d.fields["while active"].children:
		if not l.is_blank():
			var e := Effect.compile(l.text + " quietly")
			if not e.has("error"):
				out.append(e)
	return out


# --- Saving -----------------------------------------------------------------

func save_dict() -> Dictionary:
	state.settings = settings.duplicate(true)
	state.rng_state = rng.get_state()
	state.runner = runner.save_frames()
	var pack_versions := {}
	for p in content.packs:
		pack_versions[p.id] = content.field_value(p.id, "version", "0")
	return {"format": 1, "packs": pack_versions, "state": state.to_dict(), "last_fight": last_fight}


## What a save list shows about this game.
func save_summary() -> Dictionary:
	var loc := state.location
	return {"player": str(value("player.name")), "location": content.typed_value("location", loc, "name", loc),
		"region": content.typed_value("region", content.typed_value("location", loc, "region"), "name", ""),
		"day": day(), "time": time_slot(), "turn": state.turn, "level": int(value("player.level")),
		"scenario": content.typed_value("scenario", str(settings.scenario), "name", str(settings.scenario)),
		"ending": state.ending}


func load_dict(d: Dictionary) -> bool:
	if int(d.get("format", 0)) != 1 or not d.get("state") is Dictionary:
		warn("This save has an unsupported format.")
		return false
	for pack in d.get("packs", {}):
		if not content.has(pack, "pack"):
			warn("This save needs the '%s' content pack." % pack)
			return false
	if not content.has(str(d.state.get("location", "")), "location"):
		warn("The saved location is not available in the loaded content.")
		return false
	if not d.state.get("scheduled", []) is Array:
		warn("The saved action timers are invalid.")
		return false
	for entry in d.state.get("scheduled", []):
		if not entry is Dictionary or not content.has(str(entry.get("scene", "")), "scene"):
			warn("A saved action timer needs a scene that is not available.")
			return false
		if not (entry.get("due") is int or entry.get("due") is float) or int(entry.due) < 1:
			warn("A saved action timer has an invalid deadline.")
			return false
	state = GameState.from_dict(d.get("state", {}))
	last_fight = d.get("last_fight", "")
	settings = default_settings()
	settings.merge(state.settings, true)
	# Saves from before bans were locked are games in progress.
	if not state.settings.has("started"):
		settings.started = true
	if state.rng_state.size() == 4:
		rng.set_state(state.rng_state)
	runner.load_frames(state.runner)
	return true
