class_name VariantSystem
extends RefCounted
## Creature variants: one creature met in different shapes, such as a goblin
## that is female one time and male the next. This is the original's PrepCombat
## idiom that rolls a gender for each meeting and respects bans and wards
## (Goblin, Pit Bull, Clockwork Fox, Impala, Horny Doctor, Wereraptor ...).
##
##   == creature goblin
##   variants:
##       female:
##           gender: female
##           image: goblin_female
##       male:
##           gender: male
##           special: grapple 20%
##
## Each meeting picks one variant:
## - A variant is never met while one of its filters is banned. Its filters are
##   `filters:`, or else the filters whose `genders:` list holds its gender.
## - A variant with `when:` is only met while that condition holds, so events can
##   force one ("when: not hd.forced is female").
## - Warded variants only come up when nothing else can, or when the player hunts
##   the creature; hunting picks among the unwarded ones 1 time in 3, otherwise
##   among all (the original's "2/3rds chance to get the unwarded option").
## - `pick variant: random` (the default) weighs variants by `chance:` (1 when
##   not given); `pick variant: in order` takes the first one allowed.
## `fight goblin (female):` and `~ creature goblin variant female` choose one
## directly. The chosen variant's fields stand in for the creature's own while
## it is met; scenes test `goblin is female` (its gender) or
## `goblin is variant female`.

const FIELDS := ["gender", "filters", "when", "chance", "title", "image", "special", "loot", "level", "hp",
	"damage", "stats", "libido", "hit bonus", "dodge bonus", "mind bonus", "infection sex", "seduction immune"]


## Variant names in the order written, with their fields.
static func variants(content, id: String) -> Dictionary:
	var d: FscParser.Definition = content.get_def("creature", id)
	var out := {}
	if d == null or not d.fields.has("variants"):
		return out
	var base := -1
	var current := ""
	for line: FscParser.Line in d.fields["variants"].children:
		if line.is_blank():
			continue
		if base < 0:
			base = line.indent
		var text := line.text.strip_edges()
		if line.indent <= base:
			current = text.trim_suffix(":").strip_edges()
			out[current] = {"_line": line.number}
		elif current != "" and ":" in text:
			var pair := text.split(":", true, 1)
			out[current][pair[0].strip_edges()] = pair[1].strip_edges()
	return out


static func has_variants(content, id: String) -> bool:
	var d: FscParser.Definition = content.get_def("creature", id)
	return d != null and d.fields.has("variants")


## The filters that keep a variant out.
static func filters_of(content, id: String, variant: String) -> Array:
	var v: Dictionary = variants(content, id).get(variant, {})
	if v.has("filters"):
		return Array(str(v.filters).split(",", false)).map(func(s): return s.strip_edges())
	var gender := str(v.get("gender", ""))
	var out: Array = []
	if gender == "":
		return out
	for f in content.all_of("filter"):
		if gender in content.list_field(f, "genders"):
			out.append(f)
	return out


## All variants' filters together: the creature's own tags leave these to the variants.
static func all_filters(content, id: String) -> Array:
	var out: Array = []
	for v in variants(content, id):
		for f in filters_of(content, id, v):
			if f not in out:
				out.append(f)
	return out


## Variants that can be met now: no banned filter and `when` holds.
static func allowed(game, id: String) -> Array:
	var out: Array = []
	var all := variants(game.content, id)
	for v in all:
		if game.filter_block(filters_of(game.content, id, v), true) != "":
			continue
		var when := str(all[v].get("when", ""))
		if when != "" and not Condition.evaluate(Condition.compile(when), game):
			continue
		out.append(v)
	return out


## Can the creature be met at all (random or hunted)? A creature without
## variants always can, as far as variants go.
static func meetable(game, id: String, hunted: bool) -> bool:
	if not has_variants(game.content, id):
		return true
	var ok := allowed(game, id)
	if hunted:
		return not ok.is_empty()
	return ok.any(func(v): return game.filter_block(filters_of(game.content, id, v)) == "")


## Picks the variant for this meeting (or sets `forced`) and remembers it.
static func pick(game, id: String, hunted: bool = false, forced: String = "") -> String:
	var key := "creature.%s.variant" % id
	if not has_variants(game.content, id):
		return ""
	if forced != "":
		game.state.values[key] = forced
		return forced
	var ok := allowed(game, id)
	if ok.is_empty():
		game.state.values.erase(key)
		return ""
	var unwarded := ok.filter(func(v): return game.filter_block(filters_of(game.content, id, v)) == "")
	var pool := ok
	if not unwarded.is_empty() and (not hunted or game.rng.chance(1, 3)):
		pool = unwarded
	var choice := str(pool[0])
	if game.content.typed_value("creature", id, "pick variant", "random") == "random":
		choice = _weighted(game, id, pool)
	game.state.values[key] = choice
	return choice


static func _weighted(game, id: String, pool: Array) -> String:
	var all := variants(game.content, id)
	var total := 0
	for v in pool:
		total += maxi(0, int(all[v].get("chance", "1")))
	if total <= 0:
		return str(pool[0])
	var roll: int = game.rng.range_int(1, total)
	for v in pool:
		roll -= maxi(0, int(all[v].get("chance", "1")))
		if roll <= 0:
			return str(v)
	return str(pool[-1])


static func current(game, id: String) -> String:
	return str(game.state.values.get("creature.%s.variant" % id, ""))


## A field of the creature's current variant, or null when it has none.
static func field(game, id: String, name: String) -> Variant:
	var v := current(game, id)
	if v == "":
		return null
	var fields: Dictionary = variants(game.content, id).get(v, {})
	return fields.get(name, null)
