class_name BodySystem
extends RefCounted
## Detailed-part infection is an intentional change from the released game.

const PARTS := ["head", "torso", "back", "arms", "legs", "ass", "tail", "cock", "cunt", "skin"]
const ALIASES := {"face": "head", "body": "torso"}

static func fields(game, form: String, part: String) -> Dictionary:
	var d: FscParser.Definition = game.content.get_def("form", form)
	var out := {}
	if d == null or not d.fields.has(part):
		return out
	for line in d.fields[part].children:
		if not line.is_blank() and ":" in line.text:
			var pair: PackedStringArray = line.text.split(":", true, 1)
			out[pair[0].strip_edges()] = pair[1].strip_edges()
	return out


## Infection with a form, following the original's OldInfectionRoll
## (Core Mechanics/Infections.i7x:400-633) on the detailed parts: one part
## that differs changes (all of them when `all`, for transform effects); a
## body (torso) change also adjusts breasts, size and sex, a genital change
## adjusts sex. Resistant, Mutable and Mighty Mutation follow the original.
## `keep_sex`: the infection leaves sex alone (the original's "Nochange" sex entry).
static func infect(game, form: String, all: bool = false, keep_sex: bool = false) -> void:
	if game.content.get_def("form", form) == null:
		game.warn("No form '%s' to infect with." % form)
		return
	if all:
		for part in PARTS:
			if not fields(game, form, part).is_empty():
				_change_part(game, form, part, false)
		_breasts(game, form, true)
		_attributes(game, form)
		_set_sex_targets(game, form)
		game.set_value("player.libido", int(game.content.typed_value("form", form, "libido", "0")))
		return
	if _has(game, "resistant") and game.rng.chance(1, 3):
		_say(game, "Your nanites['] programmed resistance to change prevents further mutation.")
	else:
		_roll(game, form, keep_sex)
		if _has(game, "mutable") and game.rng.chance(1, 2):
			_roll(game, form, keep_sex)
	if _has(game, "mighty_mutation"):
		_stat_drift(game, form)
	_libido_drift(game, form)


static func _roll(game, form: String, keep_sex: bool = false) -> void:
	var available: Array = []
	for part in PARTS:
		if not fields(game, form, part).is_empty() and game.part_form("player", part) != form:
			available.append(part)
	# With nothing left to change, the body roll still adjusts size and sex.
	var part: String = "torso" if available.is_empty() else available[game.rng.range_int(0, available.size() - 1)]
	match part:
		"torso":
			_breasts(game, form)
			if game.part_form("player", "torso") != form:
				_change_part(game, form, "torso")
			_attributes(game, form)
			if not keep_sex:
				_sex(game, form)
		"cock", "cunt":
			if not keep_sex:
				_sex(game, form)
			_change_part(game, form, part, part == "cunt" or game.adjective("player", "male"))
		_:
			_change_part(game, form, part)


## The part's new form and description, with "Your face tingles as ..."
static func _change_part(game, form: String, part: String, message: bool = true) -> void:
	var data := fields(game, form, part)
	var change: String = data.get("change", "")
	# The message describes the body before it changes, as in the original.
	if message and change != "":
		var word: String = {"head": "face", "torso": "[one of][body type] [or][body descriptor] [or][body descriptor] [or][at random]body",
			"tail": "ass", "cock": "groin"}.get(part, part)
		_say(game, "Your %s [one of]tingles[or]goes flush[or]vibrates with odd pleasure[or]goes cold[or]feels oily[at random] as %s." % [word, change])
	game.set_value("player.body." + part, form)
	game.set_value("player.body_description." + part, _text(game, data.get("description", "")))


## Size, and gear that no longer fits or suits the body (Infections.i7x:952-994).
static func _attributes(game, form: String) -> void:
	game.state.values.erase("player.scale")
	var target := int(game.content.typed_value("form", form, "scale", "3"))
	var tags: Array = game.content.form_tags(form)
	if "taur" in tags or "no_legs" in tags:
		for id: String in game.state.equipped.duplicate():
			if ItemSystem.gear(game, id, "taur compatible", "no") != "yes":
				var they := ItemSystem.plural(game, id)
				_say(game, "Sadly, the %s %s incompatible with your new body type, so you can do nothing but take %s off." % [ItemSystem.item_name(game, id), "are" if they else "is", "them" if they else "it"])
				game.state.equipped.erase(id)
	ItemSystem.resize(game, target)
	game.state.values.erase("player.scale")  # the form gives the size from now on


static func _has(game, feat: String) -> bool:
	return feat in game.state.feats


## The original's preference adjectives (Feats.i7x:36-52).
## The sex a form's infection moves toward: its `sex`, or with `sex by preference: yes`
## the player's preferred sex when there is one (the original's PrepCombat
## "if Player is MalePreferred: now sex entry is ..." idiom).
static func target_sex(game, form: String) -> String:
	if game.content.typed_value("form", form, "sex by preference", "no") == "yes":
		for p in ["male", "herm", "female"]:
			if _prefers(game, p):
				return p
	return game.content.typed_value("form", form, "sex", "")


static func _prefers(game, sex: String) -> bool:
	var m := _has(game, "male_preferred")
	var f := _has(game, "female_preferred")
	var h := _has(game, "herm_preferred")
	match sex:
		"male":
			return m and not f and not h
		"female":
			return f and not m and not h
		"herm":
			return (h or (_has(game, "always_cocky") and _has(game, "always_a_pussy"))) and not m and not f and not _has(game, "single_sexed")
	return false


static func _num(game, path: String) -> int:
	var v = game.value("player." + path)
	return int(v) if v != null else 0


static func _setn(game, path: String, v: int) -> void:
	game.set_value("player." + path, v)


static func _target(game, form: String, part: String, key: String) -> int:
	return int(fields(game, form, part).get(key, "0"))


## The original's sex change rule (Infections.i7x:10-224).
static func _sex(game, form: String) -> void:
	var sex: String = target_sex(game, form)
	var maleish := sex in ["male", "herm"]
	var femaleish := sex in ["female", "herm"]
	var single := 0
	if _has(game, "single_sexed"):
		single = 1 if game.adjective("player", "herm") else 2 if game.adjective("player", "male") else 3 if game.adjective("player", "female") else 0
	var modest := _has(game, "modest_organs")
	var one_way := _has(game, "one_way")
	var keep_male := _prefers(game, "male") or _prefers(game, "herm") or _has(game, "always_cocky")
	var keep_female := _prefers(game, "female") or _prefers(game, "herm") or _has(game, "always_a_pussy")
	if maleish:
		var target := _target(game, form, "cock", "length")
		var length := _num(game, "cock.length")
		if length < target and game.adjective("player", "male") and not _prefers(game, "female"):
			length += 1
			length += (target - length) / 3
			if modest:
				length = mini(length, 8)
			if length > _num(game, "cock.length"):
				_setn(game, "cock.length", length)
				_snippet(game, "infection_cock_grows")
		elif length > target * 150 / 100 and not one_way:
			length -= 1
			length -= (length - target * 150 / 100) / 3
			if keep_male:
				length = maxi(length, 5)
			if modest:
				length = mini(length, 8)
			if length < _num(game, "cock.length"):
				_setn(game, "cock.length", length)
				_snippet(game, "infection_cock_shrinks")
		var balls := _num(game, "balls.size")
		var balls_target := _target(game, form, "balls", "size")
		if balls < balls_target and game.adjective("player", "male") and not _prefers(game, "female"):
			balls = mini(balls + 1, 3) if modest else balls + 1
			if balls > _num(game, "balls.size"):
				_setn(game, "balls.size", balls)
				_snippet(game, "infection_balls_grow")
		elif balls > balls_target and not one_way:
			balls -= 1
			if keep_male:
				balls = maxi(balls, 3)
			if modest:
				balls = mini(balls, 3)
			if balls < _num(game, "balls.size"):
				_setn(game, "balls.size", balls)
				_snippet(game, "infection_balls_shrink")
		if _num(game, "cocks") < _target(game, form, "cock", "count") and not _prefers(game, "female") and single != 3:
			var before := _num(game, "cocks")
			if not game.adjective("player", "male") or _num(game, "cock.length") == 0 or _num(game, "balls.size") == 0:
				if not game.adjective("player", "male"):
					_setn(game, "cocks", before + 1)
				_setn(game, "cock.length", 1 + target / 3)
				_setn(game, "balls.size", 1)
				if modest:
					_setn(game, "cock.length", mini(_num(game, "cock.length"), 8))
			elif game.rng.chance(2, 3) and not _has(game, "just_one"):
				_setn(game, "cocks", before + 1)
			if _num(game, "cocks") > before:
				_snippet(game, "infection_cock_appears")
	if game.adjective("player", "male") and not one_way:
		if sex in ["female", "neuter"]:
			var length := _num(game, "cock.length")
			var balls := _num(game, "balls.size")
			var new_length := length - 1
			new_length -= new_length / 3
			var new_balls := balls - 1
			if keep_male:
				new_length = maxi(new_length, 5)
				new_balls = maxi(new_balls, 3)
			_setn(game, "cock.length", new_length)
			_setn(game, "balls.size", new_balls)
			if single == 1 and sex == "female":
				_remove(game, "cock")
			if new_length < length or new_balls < balls:
				_snippet(game, "infection_cock_dwindles")
				if new_length < 1 or new_balls < 1:
					_snippet(game, "infection_male_lost")
					_remove(game, "cock")
			if _num(game, "cocks") > 1 and game.rng.chance(2, 5) and not _has(game, "all_the_things"):
				_snippet(game, "infection_cock_vanishes")
				_setn(game, "cocks", _num(game, "cocks") - 1)
		elif _num(game, "cocks") > _target(game, form, "cock", "count") and game.rng.chance(1, 3) and not _has(game, "all_the_things"):
			_snippet(game, "infection_extra_cock_vanishes")
			_setn(game, "cocks", _num(game, "cocks") - 1)
	if femaleish:
		var target := _target(game, form, "cunt", "depth")
		var depth := _num(game, "cunt.depth")
		if depth < target and game.adjective("player", "female") and not _prefers(game, "male"):
			depth += 1
			depth += (target - depth) / 3
			if modest:
				depth = mini(depth, 8)
			if depth > _num(game, "cunt.depth"):
				_setn(game, "cunt.depth", depth)
				_snippet(game, "infection_cunt_deepens")
		elif depth > target * 150 / 100 and not one_way:
			depth -= 1
			depth -= (depth - target * 150 / 100) / 3
			if keep_female:
				depth = maxi(depth, 5)
			if modest:
				depth = mini(depth, 8)
			if depth < _num(game, "cunt.depth"):
				_setn(game, "cunt.depth", depth)
				_snippet(game, "infection_cunt_shallows")
		var tight_target := _target(game, form, "cunt", "tightness")
		var tight := _num(game, "cunt.tightness")
		if tight < tight_target and game.adjective("player", "female") and not _prefers(game, "male"):
			tight += 1
			tight += (tight_target - tight) / 3
			if modest:
				tight = mini(tight, 5)
			if tight > _num(game, "cunt.tightness"):
				_setn(game, "cunt.tightness", tight)
				_snippet(game, "infection_cunt_widens")
		elif tight > tight_target * 150 / 100 and not one_way:
			tight -= 1
			tight -= (tight - tight_target * 150 / 100) / 3
			if keep_female:
				tight = maxi(tight, 3)
			if modest:
				tight = mini(tight, 5)
			if tight < _num(game, "cunt.tightness"):
				_setn(game, "cunt.tightness", tight)
				_snippet(game, "infection_cunt_tightens")
		if _num(game, "cunts") < _target(game, form, "cunt", "count") and not _prefers(game, "male") and single != 2:
			var before := _num(game, "cunts")
			if not game.adjective("player", "female") or _num(game, "cunt.depth") == 0 or _num(game, "cunt.tightness") == 0:
				if not game.adjective("player", "female"):
					_setn(game, "cunts", before + 1)
				_setn(game, "cunt.depth", 1 + target / 3)
				_setn(game, "cunt.tightness", 1 + tight_target / 3)
				if modest:
					_setn(game, "cunt.depth", mini(_num(game, "cunt.depth"), 8))
					_setn(game, "cunt.tightness", mini(_num(game, "cunt.tightness"), 5))
			elif game.rng.chance(2, 3) and not _has(game, "just_one"):
				_setn(game, "cunts", before + 1)
			if _num(game, "cunts") > before:
				_snippet(game, "infection_cunt_appears")
	if game.adjective("player", "female") and not one_way:
		if sex in ["male", "neuter"]:
			var depth := _num(game, "cunt.depth")
			var tight := _num(game, "cunt.tightness")
			var new_depth := depth - 1
			new_depth -= new_depth / 3
			var new_tight := tight - 1
			new_tight -= new_tight / 4
			if keep_female:
				new_depth = maxi(new_depth, 5)
				new_tight = maxi(new_tight, 3)
			_setn(game, "cunt.depth", new_depth)
			_setn(game, "cunt.tightness", new_tight)
			if single == 1 and sex == "male":
				_remove(game, "cunt")
			if new_depth < depth or new_tight < tight:
				_snippet(game, "infection_cunt_dwindles")
				if new_depth < 1 or new_tight < 1:
					_snippet(game, "infection_female_lost")
					_remove(game, "cunt")
			if _num(game, "cunts") > 1 and game.rng.chance(2, 5) and not _has(game, "all_the_things"):
				_snippet(game, "infection_cunt_vanishes")
				_setn(game, "cunts", _num(game, "cunts") - 1)
		elif _num(game, "cunts") > _target(game, form, "cunt", "count") and game.rng.chance(1, 3) and not _has(game, "all_the_things"):
			_snippet(game, "infection_cunt_vanishes")
			_setn(game, "cunts", _num(game, "cunts") - 1)


## The original's remove manhood / womanhood.
static func _remove(game, which: String) -> void:
	if which == "cock":
		for k in ["cocks", "cock.length", "balls.size"]:
			_setn(game, k, 0)
	else:
		for k in ["cunts", "cunt.depth", "cunt.tightness"]:
			_setn(game, k, 0)


## The original's breast change rule, old style (Infections.i7x:322-381).
static func _breasts(game, form: String, quiet: bool = false) -> void:
	var data := fields(game, form, "breasts")
	if data.is_empty():
		return
	var nipples := _num(game, "nipples")
	var nipple_target := int(data.get("nipples", "0"))
	if nipples != nipple_target:
		if (nipple_target > nipples and not _has(game, "one_pair")) or (nipples == 0 and nipple_target > 0):
			_setn(game, "nipples", nipples + 2)
			if not quiet:
				_snippet(game, "infection_breasts_appear")
		elif nipple_target < nipples and not _has(game, "bouncy_bouncy"):
			if not quiet:
				_snippet(game, "infection_breasts_vanish")
			_setn(game, "nipples", nipples - 2)
	if _num(game, "nipples") == 0:
		return
	var sex: String = target_sex(game, form)
	var target := -1
	var grow_ok := true
	if sex in ["female", "herm"]:
		target = int(data.get("size", "0"))
		grow_ok = (not _has(game, "male_preferred") or _has(game, "breasts")) and not _has(game, "flat_chested")
	elif sex == "male":
		target = int(data.get("male size", "0"))
		if _has(game, "breasts"):
			if target == 0:
				target = int(data.get("size", "0"))
		elif _has(game, "male_preferred") or _has(game, "flat_chested"):
			target = 0
	if target < 0:
		return
	var size := _num(game, "breasts.size")
	var before_text := TextTemplate.plain(game.render(TextTemplate.compile("[breast_size_desc]", "infection.breasts")))
	if size < target and grow_ok:
		size += 1
		size += (target - size) / 3
	elif size > target and not _has(game, "one_way"):
		size -= 1
		size -= (size - target) / 3
	else:
		return
	_setn(game, "breasts.size", size)
	if not quiet:
		_say(game, "You [one of]groan and grab at your chest[or]give a loud moan, shuddering[or]almost tip forward in surprise[or]look down fearfully as sensation builds[at random], [skin] skin glistening as your %s breasts become [breast_size_desc] [one of]orbs[or]breasts[or]jugs[or]tits[at random]!" % before_text)


## For transform effects: the form's numbers at once.
static func _set_sex_targets(game, form: String) -> void:
	for pair in [["cock", "count", "cocks"], ["cock", "length", "cock.length"], ["balls", "size", "balls.size"],
			["cunt", "count", "cunts"], ["cunt", "depth", "cunt.depth"], ["cunt", "tightness", "cunt.tightness"],
			["breasts", "size", "breasts.size"], ["breasts", "nipples", "nipples"]]:
		var data := fields(game, form, pair[0])
		if data.has(pair[1]):
			_setn(game, pair[2], int(data[pair[1]]))


## Mighty Mutation: one attribute moves toward the form's (Infections.i7x:418-479).
static func _stat_drift(game, form: String) -> void:
	var targets := {}
	for entry in game.content.typed_value("form", form, "stats").split(","):
		var parts: PackedStringArray = entry.strip_edges().split(" ", false)
		if parts.size() == 2:
			targets[parts[0]] = int(parts[1])
	var differ: Array = targets.keys().filter(func(k): return int(game.value("player." + k)) != targets[k])
	if differ.is_empty():
		return
	var stat: String = differ[game.rng.range_int(0, differ.size() - 1)]
	var name: String = game.content.typed_value("form", form, "name", form).to_lower()
	var have := int(game.value("player." + stat))
	if have > int(targets[stat]):
		if game.rng.chance(1, 10) and not _has(game, "bestial_power") and game.rng.chance(1, 2):
			_snippet(game, "infection_%s_down" % stat)
			game.change_value("player." + stat, -1)
	else:
		_say(game, "[infection_%s_up]" % stat, name)
		game.change_value("player." + stat, 1)


## Libido moves toward the form's (Infections.i7x:480-490).
static func _libido_drift(game, form: String) -> void:
	var target := int(game.content.typed_value("form", form, "libido", "0"))
	var old := int(game.value("player.libido"))
	if old >= target:
		return
	var lib := old + 1
	lib += (target - lib) / 3
	game.set_value("player.libido", lib)
	lib = int(game.value("player.libido"))
	if old < 80 and lib > 79:
		_snippet(game, "infection_libido_80")
	elif old < 50 and lib > 49:
		_snippet(game, "infection_libido_50")


static func _snippet(game, id: String) -> void:
	if game.content.has(id, "text"):
		_say(game, "[%s]" % id)


static func _say(game, text: String, creature_name: String = "") -> void:
	if creature_name != "":
		game.set_value("infection.name", creature_name)
	game.emit({"type": "paragraph", "spans": game.render(TextTemplate.compile(text, "infection.%d" % text.hash()))})


static func reset(game) -> void:
	for key in game.state.values.keys():
		if key.begins_with("player.body.") or key.begins_with("player.body_description."):
			game.state.values.erase(key)


static func view(game) -> Array:
	var out: Array = []
	for part in PARTS:
		var form: String = game.part_form("player", part)
		out.append({"id": part, "part": part.capitalize(), "form_id": form,
			"form": game.content.typed_value("form", form, "name", form.capitalize()),
			"description": part_description(game, "player", part)})
	return out


## A part's description: what its last change left, or else the current
## form's own description of it ("" when the form has none).
static func part_description(game, who: String, part: String) -> String:
	part = ALIASES.get(part, part)
	var v = game.value("%s.body_description.%s" % [who, part])
	if v != null and str(v) != "":
		return str(v)
	return _text(game, fields(game, game.part_form(who, part), part).get("description", ""))


## How far the player's breast rows curve out, in inches, as the original
## says it (Game UI.i7x:381-385): the first row by breast size, the second
## three fifths of that, the rest a third.
static func breast_curve(game, row: String) -> String:
	var size := _num(game, "breasts.size")
	var inches: int = {"upper": size, "second": size * 3 / 5, "lower": size / 3}.get(row, size)
	return "%d inch%s" % [inches, "" if inches == 1 else "es"]


## Marks left on the player by feats, such as a mate's claw marks: the
## `body text` of each feat the player has.
static func marks(game) -> String:
	var out: PackedStringArray = []
	for id: String in game.state.feats:
		var text: String = game.content.typed_value("feat", id, "body text")
		if text != "":
			out.append(_text(game, text))
	return " ".join(out)


static func _text(game, text: String) -> String:
	return TextTemplate.plain(game.render(TextTemplate.compile(text)))
