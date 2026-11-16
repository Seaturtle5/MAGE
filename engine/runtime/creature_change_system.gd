class_name CreatureChangeSystem
extends RefCounted
## Creatures and forms changed in play, saved with the game:
##
##   ~ creature german_shepherd tag + no_vore     tags added or removed from now on
##   ~ form husky_bitch tags + latex, quadrupedal (the original's lists of infections,
##   ~ form husky_bitch tag - bipedal              such as VoreExclusion or LatexList)
##   ~ creature husky_alpha attack -> hunter_bite  a combat text replaced by a scene or
##   ~ creature husky_alpha attack -> default      text, and back (attack, miss, before
##                                                 attack, after attack, each round)
##   ~ creature reindeer loot chance + 3 to 10 up to 80   (also - N and = N)
##
## Tag changes are kept per definition as "+tag" / "-tag" entries in
## `state.values["tags.<type>.<id>"]`, with the changed definitions listed in
## `state.values["tags.changed"]`; every engine reading of a creature's or a
## form's tags goes through creature_tags() and form_tags() here.

const CHANGED := "tags.changed"
## The combat texts that can be replaced in play.
const SCRIPTS := ["attack", "miss", "before attack", "after attack", "each round"]


## Adds or removes tags of a creature or a form from now on.
static func change_tags(game, type: String, id: String, add: bool, tags: Array) -> void:
	var key := "tags.%s.%s" % [type, id]
	var changes: Array = (game.state.values.get(key, []) as Array).duplicate()
	for t: String in tags:
		changes = changes.filter(func(c: String) -> bool: return c.substr(1) != t)
		changes.append(("+" if add else "-") + t)
	game.state.values[key] = changes
	var index: Array = (game.state.values.get(CHANGED, []) as Array).duplicate()
	if "%s:%s" % [type, id] not in index:
		index.append("%s:%s" % [type, id])
	game.state.values[CHANGED] = index


static func _changed(game, type: String, id: String, tags: Array) -> Array:
	var changes = game.state.values.get("tags.%s.%s" % [type, id])
	if not changes is Array:
		return tags
	var out: Array = tags.duplicate()
	for c: String in changes:
		var t := c.substr(1)
		if c.begins_with("+"):
			if t not in out:
				out.append(t)
		else:
			out = out.filter(func(x: String) -> bool: return x != t)
	return out


## A definition's own `tags:` with the changes made in play.
static func own_tags(game, type: String, id: String) -> Array:
	var d: FscParser.Definition = game.content.get_def(type, id)
	var tags: Array = game.content._list(d, "tags") if d != null else []
	return _changed(game, type, id, tags)


## A creature's tags now.
static func creature_tags(game, id: String) -> Array:
	return own_tags(game, "creature", id)


## A form's tags now: its own and those of the creatures that infect with it
## (ContentDB.form_tags), with the changes made in play to those creatures, then
## to the form itself.
static func form_tags(game, form: String) -> Array:
	var tags: Array = game.content.form_tags(form)
	if not game.state.values.has(CHANGED):
		return tags
	for entry: String in game.state.values[CHANGED]:
		var parts := entry.split(":")
		if parts[0] == "creature" and game.content.typed_value("creature", parts[1], "form") == form:
			tags = _changed(game, "creature", parts[1], tags)
	return _changed(game, "form", form, tags)


## Replaces one of a creature's combat texts with a scene or text (`default`: its own again).
static func replace_script(game, id: String, field: String, target: String) -> void:
	var key := "creature.%s.%s" % [id, field]
	if target == "default":
		game.state.values.erase(key)
	else:
		game.state.values[key] = target


## One of a creature's combat scripts: the one put in its place in play, else its own.
static func combat_script(game, id: String, field: String) -> Program:
	if field in SCRIPTS:
		var target = game.state.values.get("creature.%s.%s" % [id, field])
		if target != null and str(target) != "":
			return game.content.program(str(target))
	return game.content.program("%s#%s" % [id, field], "creature")


## `~ creature reindeer loot chance + 3 to 10 up to 80`: the chance of its `loot:`
## from now on, kept between 0 and 100 (the original's "increase lootchance entry").
static func change_loot_chance(game, e: Dictionary) -> void:
	var loot: PackedStringArray = game.creature_field(e.creature, "loot").split(" ", false)
	if loot.size() != 2 or loot[0] == "none":
		game.warn("%s has no loot whose chance could change." % e.creature)
		return
	var cur := int(loot[1].trim_suffix("%"))
	var amount: int = Effect.resolve_amount(e.amount, game, cur)
	var nv: int = amount if e.how == "=" else cur + (amount if e.how == "+" else -amount)
	if e.amount.has("limit") and e.how != "=":
		var lim: int = e.amount.limit_value
		nv = mini(nv, maxi(cur, lim)) if e.amount.limit == "up" else maxi(nv, mini(cur, lim))
	game.state.values["creature.%s.loot" % e.creature] = "%s %d%%" % [loot[0], clampi(nv, 0, 100)]
