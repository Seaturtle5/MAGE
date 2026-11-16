class_name GearSystem
extends RefCounted
## Weapons and armor in scenes and text.
##
## - `[wielded weapon]`: the name of the weapon the player wields ("" unarmed),
##   the original's [weapon object of Player].
## - `player.carried_weapons`: how many different weapons the player carries
##   (the original's number of owned armaments).
## - `~ ask x.pick as weapon or armor: <prompt>` (also `as weapon`, `as armor`):
##   the player picks a carried weapon, or armor (worn gear with armor and
##   effectiveness), or Nevermind; its ID goes into the text value ("" for none).
## - `~ item x.pick armor + 5 up to 100`: an item's `damage`, `hit bonus`,
##   `armor` or `effectiveness` from now on (saved, for every copy), the item
##   named or held by a value.
## - `damage of x.pick`, `armor of leather_jacket`, `effectiveness of x.pick`:
##   those numbers in a value or a text (`[armor of x.pick]`).
## - `player wields x.pick`, `player wears x.pick`: the item a value holds is
##   wielded or worn.

const NUMBERS := ["damage", "hit bonus", "armor", "effectiveness"]


## The name of the wielded weapon, "" when the player fights unarmed.
static func wielded_name(game) -> String:
	var id: String = game.state.wielded
	if id == "" or ItemSystem.count(game, id) <= 0:
		return ""
	return ItemSystem.item_name(game, id)


## Armor: wearable gear with armor and effectiveness (the original's smithing check).
static func is_armor(game, id: String) -> bool:
	return ItemSystem.is_wearable(game, id) and number(game, id, "armor") > 0 and number(game, id, "effectiveness") > 0


## The carried items of these kinds ("weapon", "armor"), sorted by ID.
static func carried(game, kinds: Array) -> Array:
	var out: Array = []
	for id: String in game.state.inventory:
		if ItemSystem.count(game, id) <= 0:
			continue
		if ("weapon" in kinds and ItemSystem.is_weapon(game, id)) or ("armor" in kinds and is_armor(game, id)):
			out.append(id)
	out.sort()
	return out


## An item's damage, hit bonus, armor or effectiveness, as play may have changed it.
static func number(game, id: String, what: String) -> int:
	if id == "" or not game.content.has(id, "item"):
		return 0
	if what in ["damage", "hit bonus"]:
		return int(ItemSystem.arm(game, id, what, "0"))
	if what in ["armor", "effectiveness"]:
		return int(ItemSystem.gear(game, id, what, "0"))
	return 0


## `player wields x.pick` / `player wears x.pick`: the item a value holds.
static func holds(game, node: Dictionary) -> bool:
	var v: Variant = game.value(node.path)
	var id := str(v) if v != null else ""
	if id == "":
		return false
	return game.state.wielded == id if node.verb == "wields" else ItemSystem.wears(game, id)


static func compile(rule: String, m: RegExMatch) -> Dictionary:
	match rule:
		"ask_gear":
			var prompt := TextTemplate.compile(m.get_string(3))
			if prompt.has("error"):
				return {"error": prompt.error}
			var kinds: Array = Array(m.get_string(2).split(" or ")).map(func(k): return str(k).strip_edges())
			return {"op": "ask_gear", "path": m.get_string(1), "kinds": kinds, "prompt": prompt}
		"gear_number":
			var amt := Effect.amount(m.get_string(4))
			if amt.has("error"):
				return {"error": amt.error}
			var item := m.get_string(1)
			return {"op": "gear_number", "item": "" if "." in item else item, "path": item if "." in item else "",
				"field": m.get_string(2), "how": m.get_string(3), "amount": amt}
	return {"error": "unknown gear effect"}


static func apply(game, e: Dictionary) -> void:
	match e.op:
		"ask_gear":
			game.runner.frames.append({"kind": "item_choice", "path": e.path, "gear": e.kinds, "prompt": e.prompt, "shown": false})
			if game.runner.status == "idle":
				game.runner.run()
		"gear_number":
			var id: String = e.item
			if e.path != "":
				var held: Variant = game.value(e.path)
				id = str(held) if held != null else ""
			if not game.content.has(id, "item"):
				if id != "":
					game.warn("~ item %s %s: '%s' is not an item." % [e.path, e.field, id])
				return
			var cur := number(game, id, e.field)
			var by: int = Effect.resolve_amount(e.amount, game, cur)
			var nv: int = by if e.how == "=" else cur + (by if e.how == "+" else -by)
			if e.amount.has("limit") and e.how != "=":
				var lim: int = e.amount.limit_value
				nv = mini(nv, maxi(cur, lim)) if e.amount.limit == "up" else maxi(nv, mini(cur, lim))
			game.state.values["item.%s.%s" % [id, e.field]] = nv


static func check_effect(v, e: Dictionary, line: int) -> void:
	match e.op:
		"ask_gear":
			v._check_path(e.path, line)
			var kind: String = v.db.values.get(e.path, {}).get("kind", "")
			if kind != "" and kind != "text":
				v._err(line, "~ ask ... as %s stores an item's ID: '%s' must be a text value." % [" or ".join(e.kinds), e.path])
			v._check_template(e.prompt, line, "")
		"gear_number":
			if e.path != "":
				v._check_path(e.path, line)
			else:
				check_item(v, e.item, e.field, line)
			if e.amount.has("value"):
				v._check_expr(e.amount.value, line)


## An item named for its numbers: it must exist and have the field the number belongs to.
static func check_item(v, id: String, what: String, line: int) -> void:
	if not v.db.has(id, "item"):
		v._err(line, "Unknown item '%s'.%s" % [id, v._suggest(id, v._ids("item"))])
		return
	var field := "weapon" if what in ["damage", "hit bonus"] else "equipment"
	if not v.db.get_def("item", id).fields.has(field):
		v._err(line, "'%s' has no %s field, so it has no %s." % [id, field, what])
