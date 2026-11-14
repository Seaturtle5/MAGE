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
	"hp": 20, "maxhp": 20, "xp": 0, "level": 1, "score": 0, "freecred": 0,
	"strength": 12, "dexterity": 12, "stamina": 12, "charisma": 12, "intelligence": 12, "perception": 12,
	"hunger": 0, "thirst": 0, "morale": 0, "libido": 0, "humanity": 100, "lust": 0,
	"cocks": 0, "cunts": 1, "nipples": 2, "name": "Player",
}
const BOUNDED := {"hunger": [0, 100], "thirst": [0, 100], "humanity": [0, 100], "libido": [0, 100], "balls.size": [0, 7]}
const ATTRIBUTES := ["strength", "dexterity", "stamina", "charisma", "intelligence", "perception"]
const TIME_SLOTS := ["pre dawn", "post midnight", "night", "early night", "evening", "afternoon", "morning", "early morning"]
const FILTER_STATES := ["normal", "warded", "banned"]

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
var warnings: Array = []  ## runtime problems (missing descriptors and so on)


static func default_settings() -> Dictionary:
	return {"banned": [], "warded": [], "levels": {}, "mode": [], "scenario": "", "started": false}


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

func value(path: String) -> Variant:
	if path == "game.turn":
		return state.turn  # turns passed since the start, for timing in content
	if state.values.has(path):
		return state.values[path]
	if path.begins_with("level."):
		# A content level as a number: its option's place in the list (1 for the first).
		var id := path.trim_prefix("level.")
		return Array(content.levels.get(id, {}).get("options", [])).find(level(id)) + 1
	if content.values.has(path):
		return content.values[path].default
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
		if key.begins_with("carried."):
			return ItemSystem.count(self, key.trim_prefix("carried."))  # how many of an item the player carries
		if key.begins_with("style.") or key == "gender_look":
			return ItemSystem.looks(self).get(key.trim_prefix("style."), 0)
	return null


## A creature field that play can change (`~ creature X found in Z`), else its definition's.
func creature_field(id: String, field: String, fallback: String = "") -> String:
	var key := "creature.%s.%s" % [id, field]
	if state.values.has(key):
		return str(state.values[key])
	return content.typed_value("creature", id, field, fallback)


func set_value(path: String, v: Variant) -> void:
	if path.begins_with("player."):
		var key := path.substr(7)
		if BOUNDED.has(key):
			v = clampi(int(v), BOUNDED[key][0], BOUNDED[key][1])
		elif key == "hp":
			v = mini(int(v), int(value("player.maxhp")))
	var decl: Dictionary = content.values.get(path, {})
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
		set_value(path, int(value(path)) + delta)


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
		"part_is":
			return part_form(node.who, node.part) == node.form
		"part_tagged":
			return node.tag in content.form_tags(part_form(node.who, node.part))
		"is":
			return adjective(node.who, node.adjective)
	warn("Condition '%s' is not supported yet." % node.op)
	return false


func adjective(who: String, adj: String) -> bool:
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
		"in heat":
			# The heat system (characters package) sets <who>.heat; until then nobody is in heat.
			return Condition._truthy(value("%s.heat" % who))
		"fighting":
			# The original's inafight: true while a fight is going on.
			return who == "player" and not state.combat.is_empty() and str(state.combat.get("result", "")) == ""
		"resolved", "active":
			return bool(state.events.get(who, {}).get(adj, adj == "active"))
		"companion":
			return who in state.companions
		"here":
			return where(who) == state.location
		"collected":
			return "collected" in content.list_field(where(who), "flags")
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
	if who == "player":
		return state.location
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
	var n := name.strip_edges()
	# "[a cock_size_desc]": the text with "a" or "an" in front.
	if n.begins_with("a ") or n.begins_with("A "):
		var rest := describe(n.substr(2))
		if rest == "":
			return ""
		var article := "an" if rest.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a"
		return "%s %s" % [article.capitalize() if n.begins_with("A") else article, rest]
	# "[player.nipples in words]": a number written out.
	if n.ends_with(" in words"):
		var counted = value(n.trim_suffix(" in words"))
		return number_words(int(counted) if counted != null else 0)
	if n.begins_with("player.") or ("." in n and not " " in n):
		var v = value(n)
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
			return content.typed_value("form", form, "body type", content.typed_value("form", form, "name", form).to_lower())
		"skin":
			var skin = value("%s.body_description.skin" % who)
			return str(skin) if skin != null and str(skin) != "" else "smooth"
		"ghe", "ghis", "ghim", "ghishers", "gche", "gchis", "gchim", "gchishers", "gdragon", "gmasculine":
			return monster_word(what)
		"body descriptor":
			# The original's bodydesc (Infections.i7x:982-984, 1072).
			var form := part_form(who, "torso")
			var words: Array = Array(content.typed_value("form", form, "descriptor").split(",", false)).map(func(w): return str(w).strip_edges())
			if words.is_empty():
				words = ["average", "normal", "unchanged"]
			return str(words[variation("body descriptor", words.size(), "at random")])
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


## The original's pronouns for the creature being fought or last met
## (Gender Pronouns.i7x Section 4, set by setmongender).
func monster_word(word: String) -> String:
	var id: String = str(state.combat.get("creature", "")) if not state.combat.is_empty() else ""
	if id == "" and not state.encountered.is_empty():
		id = state.encountered[-1]
	var g: String = creature_field(id, "gender", "neuter")
	var set := "male" if g in ["male", "male neuter", "male herm", "cuntboy"] else "female" if g in ["female", "female neuter", "herm", "shemale"] else "neuter"
	var words: Dictionary = {
		"male": {"ghis": "his", "ghe": "he", "ghim": "him", "ghishers": "his", "gdragon": "dragon", "gmasculine": "masculine"},
		"female": {"ghis": "her", "ghe": "she", "ghim": "her", "ghishers": "hers", "gdragon": "dragoness", "gmasculine": "feminine"},
		"neuter": {"ghis": "their", "ghe": "it", "ghim": "it", "ghishers": "theirs", "gdragon": "dragon", "gmasculine": "particular"},
	}[set]
	if word.begins_with("gc"):
		return str(words["g" + word.substr(2)]).capitalize()
	return str(words[word])


func pronoun(who: String, form: String) -> String:
	var p := content.field_value(who, "pronouns", "they")
	if who == "player" and value("player.pronouns") != null:
		p = str(value("player.pronouns"))
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
				state.companions.append(e.who)
				notice("%s joins you." % content.field_value(e.who, "name", e.who), quiet)
			elif not e.add:
				state.companions.erase(e.who)
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
		"activate", "deactivate":
			_event(e.event).active = e.op == "activate"
		"creature_change":
			state.values["creature.%s.%s" % [e.creature, e.field]] = e.value
		"move":
			if e.who == "player":
				go_to(e.place)
			else:
				state.char_location[e.who] = e.place
		"lives_at":
			state.residence[e.who] = e.place
			state.char_location.erase(e.who)
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
			for who in [e.taker, e.giver]:
				if who != "player":
					set_value("%s.had_sex" % who, true)
					set_value("%s.met" % who, true)
			var virgin_key: String = {"anal": "anal_virgin", "anal_toy": "anal_virgin", "vaginal": "virgin", "oral_cock": "oral_virgin"}.get(e.act, "")
			if virgin_key != "":
				set_value("%s.%s" % [e.taker, virgin_key], false)
			state.stamps["%s.last_sex" % e.giver] = state.turn
			state.stamps["%s.last_sex" % e.taker] = state.turn
		"condition":
			start_condition(e.condition, e.turns, quiet)
		"infects_as":
			# Only during a fight's scenes: the loss infection uses this creature.
			if not state.combat.is_empty():
				state.combat["infects_as"] = e.creature
		"infect":
			var form: String = e.form if e.get("part", "") == "" else part_form("player", e.part)
			for _i in Effect.resolve_amount(e.times, self):
				BodySystem.infect(self, form, false, e.get("keep_sex", false))
		"transform":
			BodySystem.infect(self, e.form, true)
		"reset_human":
			BodySystem.reset(self)
		"cancel_use":
			use_cancelled = true
		"no_fight":
			fight_cancelled = true
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
			state.ending = e.ending
			emit({"type": "ending", "ending": e.ending})
		_:
			warn("Effect '%s' is not supported yet." % e.op)
			emit({"type": "notice", "text": "[effect '%s' not implemented yet]" % e.op})


func _change_stat(key: String, delta: int, label: String, quiet: bool) -> void:
	var path := "player." + key
	var cur := int(value(path))
	set_value(path, cur + delta)
	var diff := int(value(path)) - cur
	notice("%s %+d" % [label, diff], quiet or diff == 0)


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
	return {"filters": filters, "levels": levels, "started": settings.started}


# --- World and time ---------------------------------------------------------

func start_scenario(id: String, name: String = "Player", main_stat: String = "strength", pronouns: String = "he") -> bool:
	if not content.has(id, "scenario") or main_stat not in ["strength", "dexterity", "stamina", "charisma", "intelligence", "perception"]:
		warn("The scenario or main stat is not available.")
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
	set_value("player.level", 0)
	set_value("player." + main_stat, 17)
	set_value("player.maxhp", int(value("player.stamina")) * 2 + 5)
	set_value("player.hp", value("player.maxhp"))
	set_value("player.morale", int(value("player.charisma")) + int(value("player.perception")))
	set_value("player.cocks", 1)
	set_value("player.cunts", 0)
	set_value("player.balls.size", 3)
	set_value("player.balls.count", 2)
	set_value("player.cock.length", 6)
	set_value("player.breasts.size", 0)
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
	if not state.known.has(place):
		set_value("player.score", int(value("player.score")) + 1)
	state.known[place] = true
	runner.show_location()
	var arrival := content.program(place + "#enter")
	if arrival != null:
		runner.play_now(arrival.id)


func feat_bonus(field: String) -> int:
	var bonus := 0
	for id in state.feats:
		bonus += int(content.typed_value("feat", id, field, "0"))
	return bonus


func pass_turn() -> void:
	if state.ending != "":
		return
	state.turn += 1
	SurvivalSystem.tick(self)
	RestSystem.tick(self)
	ItemSystem.tick(self)
	MeterSystem.tick(self)
	for c in state.conditions.keys():
		state.conditions[c].remaining -= 1
		if state.conditions[c].remaining > 0:
			var each := content.program("%s#each turn" % c, "condition")
			if each != null:
				runner.play_now(each.id)
		else:
			end_condition(c)
	run_hooks("each turn")


## The moments hooks can run at (`on:` of a hook).
const HOOK_MOMENTS := ["each turn"]


## Runs the form turn hook of the player's body, then the hooks for `moment`
## in pack load order. `when:` must hold; `while incapacitated: skip` skips a
## hook while the player is in a fight.
func run_hooks(moment: String) -> void:
	if moment == "each turn":
		var each := content.program("%s#each turn" % part_form("player", "torso"), "form")
		if each != null:
			runner.play_now(each.id)
	for id: String in content.all_of("hook"):
		if content.typed_value("hook", id, "on") != moment:
			continue
		if content.typed_value("hook", id, "while incapacitated") == "skip" and not state.combat.is_empty():
			continue
		var when := content.typed_value("hook", id, "when")
		if when != "" and not Condition.evaluate(Condition.compile(when), self):
			continue
		var prog := content.program("%s#do" % id, "hook")
		if prog != null:
			runner.play_now(prog.id)


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
			history.append(q.journal.get(q.stages[k], ""))
		var done_at := content.field_value(id, "done at", q.stages[-1])
		out.append({"id": id, "name": content.field_value(id, "name", id),
			"region": content.field_value(content.field_value(id, "region"), "name", "Other"),
			"stage": stage, "journal": q.journal.get(stage, ""), "history": history,
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
		var f: FscParser.Field = content.get_def("location", id).fields.get("exits", null)
		if f != null:
			for l in f.children:
				if not l.is_blank() and ":" in l.text:
					exits.append(l.text.split(":", true, 1)[1].split(",")[0].strip_edges())
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
