class_name LooksSystem
extends RefCounted
## Body and text readings: whether the player is looking at themself, a form's
## body numbers, strain names, the child carried now, the newest child, a
## character's traits and the heat that applies to the player.
##
## - `player is looking at themself`: true while the player's own description
##   is shown (the `self_description` text, the character screen), the
##   original's looknow, so a part's description can say more there than in a
##   scene. A part description that asks it is shown fresh each time instead of
##   as worded when the part changed.
## - `form.<id>.<part>.<number>` (`form.panda.cock.length`, `form.wolf.breasts.size`)
##   and `form.<id>.scale`: a form's body numbers, as play may have changed them.
## - `strain of <operand>` in values and `[strain of <operand>]` in text: the
##   name in lower case of the strain a form or creature ID (named, or held by a
##   value) is; a text that names no strain stays as it is, in lower case.
## - `~ unborn child looks like snake`, `~ unborn child head, torso look like "Seal Toy"`:
##   the child carried now takes that strain for those parts (all seven without
##   parts); nothing happens when the player carries no child. `unborn.<part>`
##   reads the strain's name as the form gives it, `unborn.show_tail` whether its
##   tail strain has a tail.
## - `offspring.last.<value>`: the newest child on record (`offspring.last.torso`).
## - `[traits of alexandra]`: a character's traits, "a, b and c".
## - `player.heat_name`: the name of the heat that applies to the player's sex now.
## - `player.milk_item`, `player.cum_item`: the item the strain of the player's
##   torso gives as milk, and the strain of their cock as cum (the forms'
##   `milk item` and `cum item`; `""` when the strain has none), for
##   `~ give player.milk_item 2`.

const FORM_NUMBERS := {"cock": ["count", "length", "girth"], "balls": ["count", "size"],
	"cunt": ["count", "depth", "tightness"], "breasts": ["size", "nipples", "male_size"]}
## Readings written "<what> of <operand>" in values and text.
const READINGS := ["strain", "armor", "effectiveness", "damage"]
const PLAYER_PATHS := ["player.heat_name", "player.carried_weapons", "player.milk_item", "player.cum_item"]
const LOOKING := "looking at themself"


# --- Looking at oneself ---------------------------------------------------------

## The original's looknow: the player's own description is being shown.
static func looking(game, who: String) -> bool:
	game.looking_asked = true
	return who == "player" and game.looking > 0


## Renders the text snippet `id` (or calls `show`) with the player looking at themself.
static func look(game, show: Callable) -> Variant:
	game.looking += 1
	var out: Variant = show.call()
	game.looking -= 1
	return out


# --- Values -----------------------------------------------------------------------

## The values of this system, or null when `path` is not one.
static func value(game, path: String) -> Variant:
	var head := path.get_slice(".", 0)
	if head == "form":
		var parts := path.split(".")
		if parts.size() == 3 and parts[2] == "scale":
			return BodySystem.form_scale(game, parts[1])
		if parts.size() == 4 and FORM_NUMBERS.has(parts[2]) and parts[3] in FORM_NUMBERS[parts[2]]:
			return int(BodySystem.fields(game, parts[1], parts[2]).get(parts[3].replace("_", " "), "0"))
		return null
	if head == "unborn":
		return unborn(game, path.substr(7))
	if path.begins_with("offspring.last."):
		return last_child(game, path.substr(15))
	if head == "player":
		match path:
			"player.heat_name":
				return heat_name(game)
			"player.carried_weapons":
				return GearSystem.carried(game, ["weapon"]).size()
			"player.milk_item":
				return game.content.typed_value("form", game.part_form("player", "torso"), "milk item")
			"player.cum_item":
				return game.content.typed_value("form", game.part_form("player", "cock"), "cum item")
	return null


## The child carried now: `unborn.head` ... the strain's name ("" when not pregnant).
static func unborn(game, key: String) -> Variant:
	if PregnancySystem.gestation(game) <= 0:
		return false if key == "show_tail" else ""
	if key == "show_tail":
		var tail := str(game.state.values.get("pregnancy.child_tail", ""))
		return tail != "" and tail != "human" and BodySystem.fields(game, tail, "tail").get("description", "") != ""
	if key not in PregnancySystem.CHILD_PARTS:
		return null
	var strain := str(game.state.values.get("pregnancy.child_" + key, ""))
	if strain == "":
		strain = game.part_form("player", key)
	return game.content.typed_value("form", strain, "name", strain.capitalize() if strain == "human" else strain)


## A value of the newest child on record (`offspring.last.torso`).
static func last_child(game, key: String) -> Variant:
	var list: Array = Array(game.state.values.get("pregnancy.offspring", []))
	var child: Dictionary = list[-1] if not list.is_empty() and list[-1] is Dictionary else {}
	if child.has(key):
		return child[key]
	return false if key in ["feral", "pureblood", "albino", "melanism", "show_tail", "show_legs"] else ""


## The name of the heat that applies to the player's sex now (the original's
## Infection Monitor: the strain's own heat, else the default one), "" with an
## untouched sex.
static func heat_name(game) -> String:
	var form := HeatSystem.strain(game)
	if form == "human" or HeatSystem.rules(game) == "":
		return ""
	var heat := HeatSystem.heat_of(game, form, "female" if game.adjective("player", "female") else "mpreg")
	return "" if heat == "" else game.content.typed_value("heat", heat, "name", heat)


## The strain an ID is, by name in lower case: a form's name, a creature's
## form's name; a text that names neither stays as it is (in lower case).
static func strain_name(game, id: Variant) -> String:
	var s := str(id) if id != null else ""
	if s == "" or s == "human":
		return s
	if not game.content.has(s, "form") and game.content.has(s, "creature"):
		s = game.creature_field(s, "form", s)
	return game.content.typed_value("form", s, "name", s).to_lower()


## "<what> of <operand>" in a value: `strain of x.form`, `armor of x.item`.
static func read_of(game, what: String, v: Variant) -> Variant:
	if what == "strain":
		return strain_name(game, v)
	return GearSystem.number(game, str(v) if v != null else "", what)


# --- Text ---------------------------------------------------------------------------

## The text substitutions of this system, or null when `n` is not one.
static func describe(game, n: String) -> Variant:
	if n == "wielded weapon":
		return GearSystem.wielded_name(game)
	var what := n.get_slice(" of ", 0)
	if " of " not in n:
		return null
	if what == "traits":
		return traits(game, n.substr(10).strip_edges())
	if what in READINGS or what in WorldSystem.READINGS:  # also a creature's numbers and zones: [level of x], [zones of x]
		var e := Expr.parse(n)
		if not e.has("error"):
			var v: Variant = Expr.evaluate(e, game)
			return str(v) if v != null else ""
	return null


## A character's traits in words: "horny, shy and whistle taken".
static func traits(game, who: String) -> String:
	var words: Array = Array(game.state.traits.get(who, [])).map(func(t): return str(t).replace("_", " "))
	if words.size() < 2:
		return "" if words.is_empty() else str(words[0])
	return "%s and %s" % [", ".join(words.slice(0, -1)), words[-1]]


# --- The child carried now ------------------------------------------------------------

static func compile(rule: String, m: RegExMatch) -> Dictionary:
	if rule != "unborn_looks":
		return GearSystem.compile(rule, m)
	var parts: Array = []
	var written := m.get_string(1).strip_edges()
	if written == "":
		parts = PregnancySystem.CHILD_PARTS.duplicate()
	else:
		for p in written.replace(" and ", ",").split(",", false):
			if p.strip_edges() == "":
				continue
			var part: String = BodySystem.ALIASES.get(p.strip_edges(), p.strip_edges())
			if part not in PregnancySystem.CHILD_PARTS:
				return {"error": "The unborn child has no part '%s'. Its parts: %s." % [p.strip_edges(), ", ".join(PregnancySystem.CHILD_PARTS)]}
			if part not in parts:
				parts.append(part)
	var strain := Expr.parse(m.get_string(2))
	if strain.has("error"):
		return {"error": "cannot read the strain '%s': %s" % [m.get_string(2), strain.error]}
	if not Expr.is_simple(strain) and strain.get("op", "") not in ["entry", "random_entry", "of"]:
		return {"error": "The unborn child looks like a form or creature, a text in quotes or a value holding one: '%s'." % m.get_string(2)}
	return {"op": "unborn_looks", "parts": parts, "strain": strain}


## `~ unborn child looks like ...`: the strain of those parts of the child carried now.
static func apply(game, e: Dictionary) -> void:
	if e.op != "unborn_looks":
		GearSystem.apply(game, e)
		return
	if PregnancySystem.gestation(game) <= 0:
		return  # no child is carried (the original's "if gestation of Child is not 0")
	var v: Variant = Expr.evaluate(e.strain, game)
	var strain := str(v) if v != null and not v is bool else ""
	if strain == "":
		return
	if not game.content.has(strain, "form") and game.content.has(strain, "creature"):
		strain = game.creature_field(strain, "form", strain)
	for part: String in e.parts:
		game.state.values["pregnancy.child_" + part] = strain


# --- Validation -----------------------------------------------------------------------

static func check_effect(v, e: Dictionary, line: int) -> void:
	if e.op != "unborn_looks":
		GearSystem.check_effect(v, e, line)
		return
	v._check_expr(e.strain, line)
	if e.strain.get("op", "") == "word" and not v.db.has(e.strain.v, "form") and not v.db.has(e.strain.v, "creature"):
		v._err(line, "'%s' is neither a form nor a creature; a strain that is neither is written in quotes (\"Seal Toy\").%s" % [e.strain.v, v._suggest(e.strain.v, v._ids("form"))])


## Checks a value path of this system; returns false when it is not one.
static func check_path(v, parts: PackedStringArray, line: int) -> bool:
	var path := ".".join(parts)
	if path in PLAYER_PATHS:
		return true
	match parts[0]:
		"form":
			if parts.size() < 3 or parts.size() > 4:
				return false
			if not v.db.has(parts[1], "form"):
				v._err(line, "'%s' reads a form's numbers, but there is no form '%s'.%s" % [path, parts[1], v._suggest(parts[1], v._ids("form"))])
			elif parts.size() == 3 and parts[2] != "scale":
				v._err(line, "'%s': a form's numbers are form.<id>.scale and form.<id>.<part>.<number> (%s)." % [path, _number_list()])
			elif parts.size() == 4 and not (FORM_NUMBERS.has(parts[2]) and parts[3] in FORM_NUMBERS[parts[2]]):
				v._err(line, "'%s' is not a form number. Known: %s." % [path, _number_list()])
			return true
		"unborn":
			if parts.size() != 2 or (parts[1] not in PregnancySystem.CHILD_PARTS and parts[1] != "show_tail"):
				v._err(line, "'%s' is not a value of the unborn child. Known: unborn.%s, unborn.show_tail." % [path, ", unborn.".join(PregnancySystem.CHILD_PARTS)])
			return true
		"offspring":
			if parts.size() < 2 or parts[1] != "last":
				return false
			if parts.size() != 3 or parts[2] not in PregnancySystem.CHILD_VALUES:
				v._err(line, "'%s' is not a value of a child. Known: %s." % [path, ", ".join(PregnancySystem.CHILD_VALUES)])
			return true
	return false


static func _number_list() -> String:
	var out: PackedStringArray = []
	for part: String in FORM_NUMBERS:
		for key: String in FORM_NUMBERS[part]:
			out.append("%s.%s" % [part, key])
	return ", ".join(out)


## Checks a text substitution of this system; returns false when it is not one.
static func check_text(v, n: String, line: int) -> bool:
	if n == "wielded weapon":
		return true
	if " of " not in n:
		return false
	var what := n.get_slice(" of ", 0)
	if what == "traits":
		var who := n.substr(10).strip_edges()
		if who != "player" and not v.db.has(who, "character"):
			v._err(line, "[%s]: '%s' is not a character.%s" % [n, who, v._suggest(who, v._ids("character"))])
		return true
	if what in READINGS or what in WorldSystem.READINGS:
		var e := Expr.parse(n)
		if e.has("error"):
			v._err(line, "[%s]: %s" % [n, e.error])
		else:
			v._check_expr(e, line)
		return true
	return false


## Checks the "<what> of <operand>" readings in an expression: a named ID must
## be a form or creature (strain) or an item with those numbers.
static func check_expr(v, node: Dictionary, line: int) -> void:
	match node.get("op", ""):
		"of":
			var inner: Dictionary = node.a
			if inner.get("op", "") == "word":
				var id: String = inner.v
				if node.what == "strain":
					if not v.db.has(id, "form") and not v.db.has(id, "creature"):
						v._err(line, "'strain of %s': '%s' is neither a form nor a creature.%s" % [id, id, v._suggest(id, v._ids("form"))])
				else:
					GearSystem.check_item(v, id, node.what, line)
			check_expr(v, inner, line)
		"+", "-", "*", "/", "%", "random", "min", "max", "sqrt", "entry":
			check_expr(v, node.a, line)
			if node.has("b"):
				check_expr(v, node.b, line)
