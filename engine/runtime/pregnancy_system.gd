class_name PregnancySystem
extends RefCounted
## Pregnancy, after the original's Pregnancy.i7x (Core Mechanics): impregnation
## rolls, gestation, birth and the children, female and male (MPreg) alike,
## plus creatures the player sires young on.
##
## The policy is pack data: one `pregnancy_rules` definition says who can carry
## (`female when`, `male when`, `blocked when`), the odds and what changes them,
## how long gestation lasts and what speeds it up, litter sizes, what the child
## looks like, and the scripts that tell it all (`conceived`, `each turn`,
## `birth`, `child`, `after birth`, `sired`, `sired birth`). The engine keeps
## the numbers and runs the steps. A form can bias its offspring's gender
## (`offspring gender: male 9 in 10`).
##
## State (saved with the game's values):
##   pregnancy.gestation     turns until birth (0: not pregnant)
##   pregnancy.kind          "female" or "male" (MPreg) while pregnant
##   pregnancy.father        the form that fathered the child ("" for self)
##   pregnancy.ovi           an egg pregnancy
##   pregnancy.hijack, pregnancy.male_hijack   content occupies the womb or the
##                           male (anal) womb (the original's preghijack, mpreghijack)
##   pregnancy.child_<part>  the child's strain for head, torso, back, arms, legs, ass, tail
##   pregnancy.litter        children of the birth under way
##   pregnancy.births, pregnancy.children, pregnancy.mpreg_count, pregnancy.feral_births
##   pregnancy.offspring     the children kept on record (a list, see `~ record child`)
##   pregnancy.sired, pregnancy.sired_turns   a creature carrying the player's young
## Read-only (computed): fpreg_ok, mpreg_ok, impreg_ok, fpreg_able, mpreg_able,
## impreg_able, fpreg_now, mpreg_now, impreg_now, fem_vacant, male_vacant,
## partial_vacant, total_vacant (the original's definitions of the same names).
## While a child is being born: child.number, child.gender, child.personality,
## child.feral, child.pureblood, child.albino, child.melanism, child.show_tail,
## child.show_legs, child.<part> (the strain's name in lower case),
## child.<part>_form, and child.name and child.home for content to fill in.

const CHILD_PARTS := ["head", "torso", "back", "arms", "legs", "ass", "tail"]
const STORED := ["gestation", "kind", "father", "ovi", "hijack", "male_hijack", "litter", "births", "children",
	"mpreg_count", "feral_births", "offspring", "sired", "sired_turns", "self", "rolled", "unbirth", "child_head", "child_torso", "child_back",
	"child_arms", "child_legs", "child_ass", "child_tail"]
const COMPUTED := ["fpreg_ok", "mpreg_ok", "impreg_ok", "fpreg_able", "mpreg_able", "impreg_able", "fpreg_now",
	"mpreg_now", "impreg_now", "fem_vacant", "male_vacant", "partial_vacant", "total_vacant", "sire_bonus", "father_name",
	"sired_name"]
const CHILD_VALUES := ["number", "gender", "personality", "feral", "pureblood", "albino", "melanism", "show_tail",
	"show_legs", "name", "home", "relationship", "head", "torso", "back", "arms", "legs", "ass", "tail", "head_form", "torso_form",
	"back_form", "arms_form", "legs_form", "ass_form", "tail_form"]
const FLAGS := ["ovi", "hijack", "male_hijack", "self", "rolled"]


static func rules(game) -> String:
	var defs: Dictionary = game.content.all_of("pregnancy_rules")
	return "" if defs.is_empty() else str(defs.keys()[0])


static func _rule(game, field: String, fallback: String = "") -> String:
	var id := rules(game)
	return fallback if id == "" else game.content.typed_value("pregnancy_rules", id, field, fallback)


static func _holds(game, field: String, empty: bool = false) -> bool:
	var text := _rule(game, field)
	if text == "":
		return empty
	return Condition.evaluate(Condition.compile(text), game)


static func _v(game, key: String) -> Variant:
	return game.state.values.get("pregnancy." + key, null)


static func _num(game, key: String) -> int:
	return int(game.state.values.get("pregnancy." + key, 0))


static func _flag(game, key: String) -> bool:
	return Condition._truthy(game.state.values.get("pregnancy." + key, false))


static func _put(game, key: String, v: Variant) -> void:
	game.state.values["pregnancy." + key] = v


static func gestation(game) -> int:
	return _num(game, "gestation")


static func pregnant(game) -> bool:
	return gestation(game) > 0 or _num(game, "litter") > 0


## Lines "condition: value" of a fields block in the policy, in order.
static func _pairs(game, field: String) -> Array:
	var id := rules(game)
	var d: FscParser.Definition = game.content.get_def("pregnancy_rules", id) if id != "" else null
	var out: Array = []
	if d == null or not d.fields.has(field):
		return out
	for line: FscParser.Line in d.fields[field].children:
		var t := line.text.strip_edges()
		if t == "" or ":" not in t:
			continue
		var k := t.rfind(":")
		out.append([t.substr(0, k).strip_edges(), t.substr(k + 1).strip_edges(), line.number])
	return out


## The sum of the numbers whose conditions hold ("player has feat fertile: -3").
static func _modifier(game, field: String) -> int:
	var total := 0
	for p in _pairs(game, field):
		if Condition.evaluate(Condition.compile(p[0]), game):
			total += int(p[1])
	return total


# --- The original's definitions --------------------------------------------

static func computed(game, key: String) -> Variant:
	match key:
		"fpreg_ok":
			return rules(game) != "" and _holds(game, "female when", false)
		"mpreg_ok":
			return rules(game) != "" and _holds(game, "male when", false)
		"impreg_ok":
			return computed(game, "fpreg_ok") or computed(game, "mpreg_ok")
		"fpreg_able":
			return computed(game, "fpreg_ok") and not pregnant(game) and not _flag(game, "hijack") and not _holds(game, "blocked when")
		"mpreg_able":
			return computed(game, "mpreg_ok") and not pregnant(game) and not _flag(game, "male_hijack") and not _holds(game, "blocked when")
		"impreg_able":
			return computed(game, "fpreg_able") or computed(game, "mpreg_able")
		"fpreg_now":
			return gestation(game) > 0 and _v(game, "kind") == "female"
		"mpreg_now":
			return gestation(game) > 0 and _v(game, "kind") == "male"
		"impreg_now":
			return gestation(game) > 0
		"fem_vacant":
			return game.adjective("player", "female") and not (pregnant(game) and _v(game, "kind") == "female") \
				and not _flag(game, "hijack") and not _holds(game, "blocked when")
		"male_vacant":
			return not (pregnant(game) and _v(game, "kind") == "male") and not _flag(game, "male_hijack") \
				and not _holds(game, "blocked when")
		"partial_vacant":
			return computed(game, "fem_vacant") or computed(game, "male_vacant")
		"total_vacant":
			return computed(game, "fem_vacant") and computed(game, "male_vacant")
		"sire_bonus":
			return _sire_bonus(game, str(game.state.values.get("pregnancy.partner", "")))
		"father_name":
			# The father's strain in lower case ("" for a self-impregnation), also while asking.
			var f := str(_v(game, "pending_father") if _v(game, "pending_kind") != null else _v(game, "father") if _v(game, "father") != null else "")
			return "" if f == "" else _species(game, f)
		"sired_name":
			var c := str(_v(game, "sired") if _v(game, "sired") != null else "")
			return "" if c == "" else game.creature_field(c, "name", c).to_lower()
	return null


## The default for a stored value nobody has set yet.
static func stored_default(key: String) -> Variant:
	if key in FLAGS:
		return false
	if key in ["kind", "father", "sired"] or key.begins_with("child_"):
		return ""
	if key == "offspring":
		return []
	return 0


# --- Impregnation -------------------------------------------------------------

## The original's impregchance and its kinds: `kind` "female", "male", "self" or
## "" (whichever the body allows, female first); `father` a creature or form ID,
## "" for the creature met now, or "random" for a random infectious creature.
## `sure` skips the roll (the original's impregnate with).
static func attempt(game, kind: String, father: String, eggs: bool, sure: bool) -> void:
	if rules(game) == "":
		return
	if kind == "self":
		if not computed(game, "impreg_able"):
			return
		kind = "female" if computed(game, "fpreg_able") else "male"
		father = "self"
	elif kind == "":
		kind = "female" if computed(game, "fpreg_able") else "male" if computed(game, "mpreg_able") else ""
	if kind == "" or not computed(game, "%spreg_able" % ("f" if kind == "female" else "m")):
		return
	var form := _father_form(game, father)
	if form == "" and father != "self":
		return
	if not sure:
		var odds := _odds(game, _rule(game, "self odds" if father == "self" else "odds", "2 in 12" if father == "self" else "2 in 10"))
		var target: int = maxi(1, odds[1] + _modifier(game, "odds modifiers"))
		if not game.rng.chance(odds[0], target):
			return
	# A fixed father overrides the roll's (the original's Chase's Breeder, Fang's Mate ...).
	for p in _pairs(game, "fathers"):
		if Condition.evaluate(Condition.compile(p[1]), game):
			form = p[0]
			father = form
			break
	_put(game, "pending_kind", kind)
	_put(game, "pending_father", "" if father == "self" else form)
	_put(game, "self", father == "self")
	_put(game, "rolled", not sure)
	# Eggs when the creature lays them, unless the ovi level says never or always.
	var ovi_level: String = game.level("ovi") if game.content.levels.has("ovi") else ""
	_put(game, "pending_ovi", ovi_level == "always" or (eggs and ovi_level != "none"))
	if _holds(game, "ask when"):
		# The original's Selective Mother: the `ask` script calls ~ accept pregnancy.
		_play(game, "ask")
	else:
		accept(game)


## Conception: the pending pregnancy begins.
static func accept(game) -> void:
	var kind := str(_v(game, "pending_kind") if _v(game, "pending_kind") != null else "")
	if kind == "":
		return
	var father := str(_v(game, "pending_father"))
	_put(game, "kind", kind)
	_put(game, "father", father)
	_put(game, "ovi", Condition._truthy(_v(game, "pending_ovi")))
	for key in ["pending_kind", "pending_father", "pending_ovi"]:
		game.state.values.erase("pregnancy." + key)
	var span := _range(_rule(game, "gestation", "24 to 48"))
	_put(game, "gestation", game.rng.range_int(span[0], span[1]))
	_shape_child(game, father)
	_play(game, "conceived")


## Unbirthing (VoreSystem, the original's ubbyplayer): the swallowed creature
## becomes a pregnancy of its own strain at once, whatever the player's
## fertility, lasting the vore rules' `unbirth gestation` (else the usual gestation).
## `pregnancy.unbirth` holds the creature until the birth.
static func unbirth(game, creature: String) -> void:
	if rules(game) == "" or gestation(game) > 0:
		return
	var form := _father_form(game, creature)
	if form == "":
		return
	_put(game, "kind", "female")
	_put(game, "father", form)
	_put(game, "self", false)
	_put(game, "rolled", false)
	var ovi_level: String = game.level("ovi") if game.content.levels.has("ovi") else ""
	_put(game, "ovi", ovi_level == "always")
	var span := _range(VoreSystem.rule(game, "unbirth gestation", _rule(game, "gestation", "24 to 48")))
	_put(game, "gestation", game.rng.range_int(span[0], span[1]))
	for part in CHILD_PARTS:
		_put(game, "child_" + part, form)
	_put(game, "unbirth", creature)


## The child's strains, part by part: the father's, the player's, or one of the two at random.
static func _shape_child(game, father: String) -> void:
	var like := "mix"
	if father == "":
		like = "mother"
	elif _holds(game, "child like father when"):
		like = "father"
	elif _holds(game, "child like mother when"):
		like = "mother"
	for part in CHILD_PARTS:
		var mine: String = game.part_form("player", part)
		var pick := father if like == "father" else mine if like == "mother" else (father if game.rng.chance(1, 2) else mine)
		_put(game, "child_" + part, pick)


static func _father_form(game, father: String) -> String:
	if father == "self":
		return ""
	if father == "random":
		var pool: Array = []
		for id in game.content.all_of("creature"):
			if game.creature_field(id, "infectious", "yes") != "no" and game.filter_block(game.content._list(game.content.get_def("creature", id), "tags"), true) == "" \
					and game.creature_field(id, "form") != "":
				pool.append(id)
		if pool.is_empty():
			return ""
		pool.sort()
		father = pool[game.rng.range_int(0, pool.size() - 1)]
	if father == "":
		father = game.current_creature()
	if game.content.has(father, "creature"):
		return game.creature_field(father, "form", father)
	return father if game.content.has(father, "form") else ""


# --- Gestation and birth ------------------------------------------------------

## Every turn (the original's pregprotocol).
static func tick(game) -> void:
	if rules(game) == "":
		return
	_tick_sired(game)
	if gestation(game) <= 0:
		return
	var left := gestation(game) - 1
	for p in _pairs(game, "quickens"):
		var odds := _odds(game, p[1])
		if Condition.evaluate(Condition.compile(p[0]), game) and game.rng.chance(odds[0], odds[1]):
			left -= 1
	_put(game, "gestation", maxi(0, left))
	if left > 0:
		_play(game, "each turn")
		return
	if not computed(game, "impreg_ok") or not game.state.combat.is_empty():
		_put(game, "gestation", 1)  # birth waits until the body can (the original's impreg_ok)
		return
	birth(game)


## The birth: the litter's size, the `birth` script, then each child, then `after birth`.
static func birth(game) -> void:
	if _v(game, "kind") == "female" and not game.adjective("player", "female"):
		_put(game, "kind", "male")
	_put(game, "gestation", 0)
	var litter := 1
	var bonus := _modifier(game, "extra child bonus")
	for c in str(_rule(game, "extra children", "1, 3, 5, 0, 0")).split(",", false):
		if game.rng.chance(clampi(int(c.strip_edges()) + bonus, 0, 100), 100):
			litter += 1
	litter = mini(litter, maxi(1, int(_rule(game, "most children", "4"))))
	if _holds(game, "single child when"):
		litter = 1
	_put(game, "litter", litter)
	_put(game, "births", _num(game, "births") + 1)
	game.runner.start_birth(litter)


## Sets the child.* values for child `n` of the litter (called by the runner just before its script).
static func make_child(game, n: int) -> void:
	var v: Dictionary = game.state.values
	for key in CHILD_VALUES:
		v.erase("child." + key)
	if _holds(game, "child like mother at birth when"):
		for part in CHILD_PARTS:
			_put(game, "child_" + part, game.part_form("player", part))
	var forms := {}
	for part in CHILD_PARTS:
		var f := str(_v(game, "child_" + part) if _v(game, "child_" + part) != null else "")
		if f == "":
			f = game.part_form("player", part)
		forms[part] = f
		v["child.%s_form" % part] = f
		v["child." + part] = _species(game, f)
	v["child.number"] = n
	v["child.pureblood"] = CHILD_PARTS.all(func(p): return forms[p] == forms.head)
	v["child.gender"] = _gender(game, forms.torso)
	v["child.personality"] = random_personality(game)
	v["child.feral"] = _holds(game, "feral when")
	var albino := _odds(game, _rule(game, "albino", "3 in 100"))
	var melanism := _odds(game, _rule(game, "melanism", "2 in 100"))
	v["child.albino"] = game.rng.chance(albino[0], albino[1])
	v["child.melanism"] = not v["child.albino"] and game.rng.chance(melanism[0], melanism[1])
	v["child.show_tail"] = forms.tail != "human" and BodySystem.fields(game, forms.tail, "tail").get("description", "") != ""
	v["child.show_legs"] = BodySystem.fields(game, forms.legs, "legs").get("locomotion", "") not in ["serpentine", "sliding"]
	v["child.name"] = ""
	v["child.home"] = ""
	_put(game, "children", _num(game, "children") + 1)
	if v["child.feral"]:
		_put(game, "feral_births", _num(game, "feral_births") + 1)


## After the last child: the count of male births grows (the `after birth` script follows).
static func after_children(game) -> void:
	if _v(game, "kind") == "male":
		_put(game, "mpreg_count", _num(game, "mpreg_count") + maxi(1, _num(game, "litter")))  # practice at it


## The pregnancy is over.
static func finish_birth(game) -> void:
	for key in ["kind", "father", "ovi", "litter", "self", "rolled"] + CHILD_PARTS.map(func(p): return "child_" + p):
		game.state.values.erase("pregnancy." + key)


static func _species(game, form: String) -> String:
	if form == "human" or form == "":
		return "human"
	return game.content.typed_value("form", form, "name", form).to_lower()


## The child's gender: the form's bias first, else a weighted pick from `child genders`.
static func _gender(game, torso: String) -> String:
	var bias: String = game.content.typed_value("form", torso, "offspring gender", "")
	if bias != "":
		var m := RegEx.create_from_string("^(\\w+(?: \\w+)?) (\\d+) in (\\d+)$").search(bias)
		if m != null and game.rng.chance(int(m.get_string(2)), int(m.get_string(3))):
			return m.get_string(1)
	return random_gender(game)


## A gender from the weighted lines of `child genders` (the original's random child gender).
static func random_gender(game) -> String:
	var pool: Array = []
	for p in _pairs(game, "child genders"):
		var m := RegEx.create_from_string("^(\\d+)(?: if (.+))?$").search(p[1])
		if m == null or (m.get_string(2) != "" and not Condition.evaluate(Condition.compile(m.get_string(2)), game)):
			continue
		for _i in int(m.get_string(1)):
			pool.append(p[0])
	if pool.is_empty():
		return "male" if game.rng.chance(1, 2) else "female"
	return pool[game.rng.range_int(0, pool.size() - 1)]


## A personality from `personalities` (the original's random child personality).
static func random_personality(game) -> String:
	var personalities := Array(_rule(game, "personalities", "friendly").split(",", false)).map(func(s): return s.strip_edges())
	return personalities[game.rng.range_int(0, personalities.size() - 1)]


## `~ new child`: a story child starts blank; the last child's child.* values are gone.
static func new_child(game) -> void:
	for key in CHILD_VALUES + ["age_turns", "age_days", "turn"]:
		game.state.values.erase("child." + key)


## `~ child.gender = random`, `~ child.personality = random`: drawn as for a birth.
static func random_child_value(game, what: String) -> void:
	game.state.values["child." + what] = random_gender(game) if what == "gender" else random_personality(game)


## `~ record child`: the child being born joins the record (pregnancy.offspring).
static func record_child(game) -> void:
	# A birth sets child.number; a story child (the original's "choose a blank row in the
	# Table of PlayerChildren") sets the child.* values it needs, then records it.
	var v: Dictionary = game.state.values
	if not CHILD_VALUES.any(func(k): return v.has("child." + k)):
		return
	var entry := {"turn": game.state.turn}
	for key in CHILD_VALUES:
		if key != "number" and v.has("child." + key):
			entry[key] = v["child." + key]
	var list: Array = Array(v.get("pregnancy.offspring", [])).duplicate()
	list.append(entry)
	v["pregnancy.offspring"] = list


## The text snippet `snippet` rendered once for each recorded child whose home is
## `home` (or every child for "any"), with that child's values as `child.*` and
## `child.age_turns` and `child.age_days` (since birth); the values in play are restored after.
static func describe_children(game, home: String, snippet: String) -> String:
	var prog: Program = game.content.program(snippet, "text")
	if prog == null:
		return ""
	var v: Dictionary = game.state.values
	var saved := {}
	for key in v.keys():
		if str(key).begins_with("child."):
			saved[key] = v[key]
	var out: PackedStringArray = []
	for child in Array(v.get("pregnancy.offspring", [])):
		if not child is Dictionary or (home != "any" and str(child.get("home", "")) != home):
			continue
		for key in v.keys():
			if str(key).begins_with("child."):
				v.erase(key)
		for key in child:
			v["child." + str(key)] = child[key]
		v["child.age_turns"] = game.state.turn - int(child.get("turn", game.state.turn))
		v["child.age_days"] = v["child.age_turns"] / Game.TIME_SLOTS.size()
		out.append(game.runner.render_inline(prog))
	for key in v.keys():
		if str(key).begins_with("child."):
			v.erase(key)
	for key in saved:
		v[key] = saved[key]
	return " ".join(out)


## `~ for each child [at <home>] play <scene>`: the scene once for each recorded
## child (living at `home`, or all), with that child's values as `child.*`;
## changes the scene makes to `child.*` are kept in the record. The scene runs at
## once, like a fight's script: text, conditions and effects (the original's
## "repeat through Table of PlayerChildren").
static func each_child(game, home: String, scene: String) -> void:
	var prog: Program = game.content.program(scene)
	if prog == null:
		game.warn("No scene '%s' to play for each child." % scene)
		return
	var v: Dictionary = game.state.values
	var saved := {}
	for key in v.keys():
		if str(key).begins_with("child."):
			saved[key] = v[key]
	var count := Array(v.get("pregnancy.offspring", [])).size()
	for i in count:
		var live: Array = Array(v.get("pregnancy.offspring", [])).duplicate()
		var child = live[i]
		if not child is Dictionary or (home != "" and str(child.get("home", "")) != home):
			continue
		for key in v.keys():
			if str(key).begins_with("child."):
				v.erase(key)
		for key in child:
			v["child." + str(key)] = child[key]
		v["child.age_turns"] = game.state.turn - int(child.get("turn", game.state.turn))
		v["child.age_days"] = v["child.age_turns"] / Game.TIME_SLOTS.size()
		CombatSystem._play(game, prog)
		var updated: Dictionary = child.duplicate()
		for key in CHILD_VALUES:
			if key != "number" and v.has("child." + key):
				updated[key] = v["child." + key]
		live = Array(v.get("pregnancy.offspring", [])).duplicate()  # the scene may have recorded more
		live[i] = updated
		v["pregnancy.offspring"] = live
	for key in v.keys():
		if str(key).begins_with("child."):
			v.erase(key)
	for key in saved:
		v[key] = saved[key]


## `~ end pregnancy`: the pregnancy ends without a birth.
static func end(game) -> void:
	for key in ["gestation", "kind", "father", "ovi", "litter", "self", "rolled", "unbirth", "pending_kind", "pending_father", "pending_ovi"] + CHILD_PARTS.map(func(p): return "child_" + p):
		game.state.values.erase("pregnancy." + key)


# --- Siring young on creatures ---------------------------------------------------

## After the player gives `act` to a creature (the original's CreatureSexAftermath
## with the Impregnated Feral stand-in): a chance the creature carries the player's young.
static func after_sex(game, taker: String, act: String) -> void:
	if rules(game) == "" or act not in ["vaginal", "anal"] or not game.content.has(taker, "creature"):
		return
	if _num(game, "sired_turns") > 0 or game.creature_field(taker, "unique", "no") == "yes":
		return
	if act == "anal":
		var tag := _rule(game, "sire anal tag", "mpreg")
		var tags: Array = game.content._list(game.content.get_def("creature", taker), "tags") + game.content.form_tags(game.creature_field(taker, "form", taker))
		if tag not in tags:
			return
	game.state.values["pregnancy.partner"] = taker
	var ok := _holds(game, "sire when", true)
	var odds := _odds(game, _rule(game, "sire odds", "2 in 10"))
	var chance: int = odds[0] + _modifier(game, "sire odds modifiers") + _sire_bonus(game, taker)
	game.state.values.erase("pregnancy.partner")
	if not ok or not game.rng.chance(clampi(chance, 0, odds[1]), odds[1]):
		return
	var span := _range(_rule(game, "sire turns", "8 to 24"))
	_put(game, "sired", taker)
	_put(game, "sired_turns", game.rng.range_int(span[0], span[1]))
	_play(game, "sired")


## The original's bonus: the player's ball size, less the creature's size above the
## player's, one more when the player is much larger; at least 1.
static func _sire_bonus(game, taker: String) -> int:
	if taker == "":
		return 0
	var bonus := int(game.value("player.balls.size")) if game.value("player.balls.size") != null else 0
	var mine := int(game.value("player.scale"))
	var theirs := BodySystem.form_scale(game, game.creature_field(taker, "form", taker))
	if theirs > mine:
		bonus -= theirs - mine
	elif mine > theirs + 1 and bonus < 7:
		bonus += 1
	return maxi(1, bonus)


static func _tick_sired(game) -> void:
	var left := _num(game, "sired_turns")
	if left <= 0:
		return
	_put(game, "sired_turns", left - 1)
	if left - 1 == 0:
		_put(game, "feral_births", _num(game, "feral_births") + 1)
		_play(game, "sired birth")


# --- Helpers ------------------------------------------------------------------------

static func _odds(game, text: String) -> Array:
	var m := RegEx.create_from_string("^(\\d+) in (\\d+)$").search(text.strip_edges())
	return [2, 10] if m == null else [int(m.get_string(1)), maxi(1, int(m.get_string(2)))]


static func _range(text: String) -> Array:
	var m := RegEx.create_from_string("^(\\d+)(?: to (\\d+))?$").search(text.strip_edges())
	if m == null:
		return [24, 48]
	var a := int(m.get_string(1))
	var b := int(m.get_string(2)) if m.get_string(2) != "" else a
	return [mini(a, b), maxi(a, b)]


static func _play(game, field: String) -> void:
	var pid := "pregnancy_rules:%s#%s" % [rules(game), field]
	if game.content.program(pid) != null:
		game.runner.play_now(pid)
