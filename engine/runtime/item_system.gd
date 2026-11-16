class_name ItemSystem
extends RefCounted
## Carrying, wearing and wielding items, items on the ground, and what gear
## does in combat. Rules follow the original at baseline 6d4920e:
## Core Mechanics/Game Objects.i7x:142-225 (wearing), Basic Functions.i7x:
## 1078-1130 (wielding), Inventory.i7x:295-506 (weight, dropping, junking,
## picking up), Characters.i7x:309-331 (bare and naked), Alt Combat.i7x:
## 134-141, 341-422, 1058-1083 (bonuses and armor) and Expanded Clothing
## Mechanics.i7x (gender look and style).
##
## An item is wearable when it has `equipment:` and a weapon when it has
## `weapon:`. Both are nested fields; see the content format.

const SLOTS := ["none", "head", "hair", "eyes", "face", "neck", "back", "body", "chest", "breast", "stomach", "arms",
	"hands", "ring", "waist", "legs", "crotch", "cock", "cunt", "calves", "feet", "shield"]
const PLACEMENTS := ["end", "head", "hair", "eyes", "face", "neck", "back", "body", "chest", "breast", "stomach",
	"arms", "hands", "waist", "legs", "crotch", "feet", "shield"]
const EQUIPMENT_KEYS := {"slot": "slot", "placement": "placement", "armor": "number", "effectiveness": "number",
	"size": "number", "taur compatible": "yes/no", "cursed": "yes/no", "plural": "yes/no", "gender look": "number",
	"style": "list", "worn text": "text", "dodge bonus": "number", "damage bonus": "number", "flee bonus": "number",
	"carry bonus": "number"}
const WEAPON_KEYS := {"damage": "number", "type": "melee/ranged", "size": "number", "hit bonus": "number",
	"attack text": "text"}
## Styles the original counts (Expanded Clothing Mechanics.i7x), plus
## "adventurous", which items carry but the original never counts.
const STYLES := ["basic", "stylish", "cool", "grungy", "sporty", "violent", "smart", "sexy", "authoritive",
	"rebellious", "cute", "slutty", "bimbo", "brah", "mistress", "slave", "adventurous"]
## Unarmed fighting (Basic Functions.i7x:1084-1090).
const UNARMED_TEXT := "your fists"
const UNARMED_DAMAGE := 4


# --- Item data ----------------------------------------------------------------

## The `key: value` lines of a nested field (`equipment:` or `weapon:`).
static func sub(game, id: String, field: String) -> Dictionary:
	var d: FscParser.Definition = game.content.get_def("item", id)
	var out := {}
	if d == null or not d.fields.has(field):
		return out
	for line in d.fields[field].children:
		if not line.is_blank() and ":" in line.text:
			var pair: PackedStringArray = line.text.split(":", true, 1)
			out[pair[0].strip_edges()] = pair[1].strip_edges()
	return out


static func gear(game, id: String, key: String, default: String = "") -> String:
	if key in ["armor", "effectiveness"] and game.state.values.has("item.%s.%s" % [id, key]):
		return str(game.state.values["item.%s.%s" % [id, key]])  # changed in play (~ item X armor + 5)
	return str(sub(game, id, "equipment").get(key, default))


static func arm(game, id: String, key: String, default: String = "") -> String:
	if key in ["damage", "hit bonus"] and game.state.values.has("item.%s.%s" % [id, key]):
		return str(game.state.values["item.%s.%s" % [id, key]])  # changed in play (~ item X damage + 1)
	return str(sub(game, id, "weapon").get(key, default))


static func is_wearable(game, id: String) -> bool:
	var d: FscParser.Definition = game.content.get_def("item", id)
	return d != null and d.fields.has("equipment")


static func is_weapon(game, id: String) -> bool:
	var d: FscParser.Definition = game.content.get_def("item", id)
	return d != null and d.fields.has("weapon")


static func count(game, id: String) -> int:
	return int(game.state.inventory.get(id, 0))


static func item_name(game, id: String) -> String:
	return game.content.typed_value("item", id, "name", id)


# --- Stats for the interface --------------------------------------------------

## The numbers and yes/no fields of an item, for the inventory: a row
## {label, value, compare, better} for each field the item has. Where gear of
## the same slot (or the wielded weapon) is in use and this item is not it,
## `compare` says the difference ("+3 compared with your pocketknife") and
## `better` is 1 when it is an improvement, -1 when worse, else 0.
static func stats(game, id: String) -> Array:
	var rows: Array = []
	var d: FscParser.Definition = game.content.get_def("item", id)
	if d == null:
		return rows
	if is_weapon(game, id):
		var w := sub(game, id, "weapon")
		var held: String = game.state.wielded if game.state.wielded != id and count(game, game.state.wielded) > 0 else ""
		var base := int(w.get("damage", "4"))
		var damage := int(arm(game, id, "damage", "4"))
		var row := _stat("Damage", str(damage) if damage == base else "%d (base %d)" % [damage, base])
		if held != "":
			_compare(game, row, damage - int(arm(game, held, "damage", "4")), held)
		rows.append(row)
		var type := arm(game, id, "type", "melee")
		rows.append(_stat("Type", "%s, %s adds damage" % [type, "perception" if type == "ranged" else "strength"]))
		rows.append(_weapon_fit(game, id))
		if w.has("hit bonus") or game.state.values.has("item.%s.hit bonus" % id) or (held != "" and int(arm(game, held, "hit bonus", "0")) != 0):
			var hit := int(arm(game, id, "hit bonus", "0"))
			row = _stat("Hit bonus", "%+d" % hit)
			if held != "":
				_compare(game, row, hit - int(arm(game, held, "hit bonus", "0")), held)
			rows.append(row)
	if is_wearable(game, id):
		var g := sub(game, id, "equipment")
		var slot := str(g.get("slot", "none"))
		# What is worn on the same slot now (gear without a slot is never in the way).
		var other := ""
		if slot != "none" and id not in game.state.equipped:
			for e: String in game.state.equipped:
				if gear(game, e, "slot", "none") == slot:
					other = e
					break
		rows.append(_stat("Slot", slot if slot != "none" else "no slot"))
		var armor := int(g.get("armor", "0"))
		if g.has("armor") or (other != "" and int(gear(game, other, "armor", "0")) != 0):
			var row := _stat("Armor", str(armor))
			if other != "":
				_compare(game, row, armor - int(gear(game, other, "armor", "0")), other)
			rows.append(row)
		if g.has("effectiveness"):
			var row := _stat("Effectiveness", "%d%%" % int(g.effectiveness))
			if other != "" and int(gear(game, other, "armor", "0")) > 0:
				_compare(game, row, int(g.effectiveness) - int(gear(game, other, "effectiveness", "0")), other, "%")
			rows.append(row)
		if armor > 0:
			var place := str(g.get("placement", "end"))
			var where := _stat("Protects", {"head": "the head", "body": "the body", "shield": "as a shield"}.get(place,
				"nothing: armor counts with placement head, body or shield"))
			where.better = 0 if place in ["head", "body", "shield"] else -1
			rows.append(where)
		rows.append(_gear_fit(game, id, slot))
		for key: String in ["dodge bonus", "damage bonus", "flee bonus", "carry bonus"]:
			if g.has(key) or (other != "" and int(gear(game, other, key, "0")) != 0):
				var row := _stat(key.left(1).to_upper() + key.substr(1), "%+d" % int(g.get(key, "0")))
				if other != "":
					_compare(game, row, int(g.get(key, "0")) - int(gear(game, other, key, "0")), other)
				rows.append(row)
		if g.has("gender look"):
			var look := int(g["gender look"])
			rows.append(_stat("Gender look", "%+d (%s)" % [look, "feminine" if look < 0 else "masculine" if look > 0 else "neutral"]))
		if str(g.get("style", "")) != "":
			rows.append(_stat("Style", ", ".join(Array(str(g["style"]).split(",")).map(func(s: String) -> String: return s.strip_edges()))))
		if g.has("taur compatible"):
			rows.append(_stat("Taur compatible", str(g["taur compatible"])))
		if str(g.get("cursed", "no")) == "yes":
			var row := _stat("Cursed", "yes, it won't come off")
			row.better = -1
			rows.append(row)
	var pounds := int(game.content.typed_value("item", id, "weight", "0"))
	rows.append(_stat("Weight", ("%d lb%s" % [pounds, "" if pounds == 1 else "s"]) if pounds > 0 else "weightless"))
	if game.content.typed_value("item", id, "in combat", "no") == "yes":
		rows.append(_stat("In combat", "can be used in a fight"))
	if d.fields.has("use") or d.fields.has("use action"):
		if game.content.typed_value("item", id, "consumed", "yes") == "no":
			rows.append(_stat("Used up", "no"))
	if game.content.typed_value("item", id, "rest") != "":
		rows.append(_stat("Bedding", game.content.typed_value("item", id, "rest")))
	if game.content.typed_value("item", id, "keep", "no") == "yes":
		rows.append(_stat("Kept", "can't be junked or dropped with the rest"))
	return rows


static func _stat(label: String, value: String) -> Dictionary:
	return {"label": label, "value": value, "compare": "", "better": 0}


## Fills in a stat row's difference against the item in use (bigger is better).
static func _compare(game, row: Dictionary, diff: int, against: String, unit: String = "") -> void:
	if diff != 0:
		row.compare = "%+d%s compared with your %s" % [diff, unit, item_name(game, against)]
	row.better = 1 if diff > 0 else -1


## How a weapon suits the player's size (Basic Functions.i7x:1099-1130):
## one category off costs 2 to hit, two cost 5, three or more can't be wielded.
static func _weapon_fit(game, id: String) -> Dictionary:
	var diff := scale(game) - int(arm(game, id, "size", "3"))
	var way := "small" if diff > 0 else "big"
	var row := _stat("Size", "right for you")
	match absi(diff):
		0:
			pass
		1:
			row.value = "a little %s for you: -2 to hit" % way
			row.better = -1
		2:
			row.value = "too %s for you: -5 to hit" % way
			row.better = -1
		_:
			row.value = "too %s for you to wield" % way
			row.better = -1
	return row


## Whether worn gear fits the player (the checks of `wear`).
static func _gear_fit(game, id: String, slot: String) -> Dictionary:
	var row := _stat("Size", "fits any size")
	var tags := _body_tags(game)
	if slot in ["feet", "legs", "waist"] and ("taur" in tags or "no_legs" in tags):
		row.value = "doesn't fit your body type"
		row.better = -1
		return row
	var size := int(gear(game, id, "size", "3"))
	if size <= 0:
		return row
	var diff := scale(game) - size
	row.value = {1: "a little small for you", 0: "fits you", -1: "a little big for you"}.get(diff,
		"too small for you to wear" if diff > 1 else "too big for you to wear")
	row.better = -1 if absi(diff) > 1 else 0
	return row


## Items named in the plural ("wild berries", pants, boots): the item's own
## `plural: yes`, or its equipment's.
static func plural(game, id: String) -> bool:
	var own: String = game.content.typed_value("item", id, "plural", "")
	if own != "":
		return own == "yes"
	return gear(game, id, "plural", "no") == "yes"


## "It is" or "They are" for an item, as the original's plural property.
static func _is(game, id: String) -> String:
	return "are" if plural(game, id) else "is"


static func _say(game, text: String, quiet: bool = false) -> void:
	if not quiet:
		game.emit({"type": "paragraph", "spans": game.render(TextTemplate.compile(text))})


# --- The player's size and shape ---------------------------------------------

## The player's size category, 1 (tiny) to 5 (huge); 3 is human sized. It
## comes from the form of the player's torso (the original's body), if set.
static func scale(game) -> int:
	if game.state.values.has("player.scale"):
		return int(game.state.values["player.scale"])
	var form: String = game.part_form("player", "torso")
	return BodySystem.form_scale(game, form)


## Changes the player's size and adjusts worn gear (Special Merchandize.i7x:
## 99-111): gear two sizes off comes off, one size off stretches or hangs loose.
static func resize(game, to: int, quiet: bool = false) -> void:
	game.state.values["player.scale"] = clampi(to, 1, 5)
	for id: String in game.state.equipped.duplicate():
		var size := int(gear(game, id, "size", "3"))
		if size <= 0:
			continue
		var name := item_name(game, id)
		var they := plural(game, id)
		var diff := scale(game) - size
		if diff > 1:
			_say(game, "**You quickly rip your %s off your body before %s destroyed when you grow larger than %s could support.**" % [name, "they are" if they else "it is", "they" if they else "it"], quiet)
			game.state.equipped.erase(id)
		elif diff == 1:
			_say(game, "**Your %s stretch%s a bit as %s forced to conform to a larger body.**" % [name, "" if they else "es", "they are" if they else "it is"], quiet)
		elif diff < -1:
			_say(game, "**As you shrink, %s becomes far too big to fit you. You have little choice but to take %s off.**" % [name, "them" if they else "it"], quiet)
			game.state.equipped.erase(id)
		elif diff == -1:
			_say(game, "**Your %s hang%s fairly loose on your now smaller frame.**" % [name, "" if they else "s"], quiet)


static func _body_tags(game) -> Array:
	var form: String = game.part_form("player", "torso")
	var d: FscParser.Definition = game.content.get_def("form", form)
	return game.content._list(d, "tags") if d != null else []


# --- Weight ------------------------------------------------------------------

static func carried_weight(game) -> int:
	var total := 0
	for id in game.state.inventory:
		total += int(game.content.typed_value("item", id, "weight", "0")) * int(game.state.inventory[id])
	return total


## Carrying capacity: five pounds per point of strength (Game Start.i7x:223
## and StatChange in Basic Functions.i7x:1012), plus feats' `carry bonus`.
## Worn gear's `carry bonus` adds too (bags such as the hiking backpack).
static func capacity(game) -> int:
	return int(game.value("player.strength")) * 5 + game.feat_bonus("carry bonus") + bonus(game, "carry bonus")


static func overburdened(game) -> bool:
	if "remove_carry_limits" in game.state.traits.get("player", []):
		return false
	return carried_weight(game) > capacity(game)


# --- Gaining and losing -------------------------------------------------------

static func gain(game, id: String, n: int) -> void:
	if n > 0:
		game.state.inventory[id] = count(game, id) + n


## Removes up to n; returns how many were removed. Gear whose last copy is
## gone is taken off or put away (the original left it marked as in use).
static func lose(game, id: String, n: int) -> int:
	var have := count(game, id)
	n = mini(have, maxi(n, 0))
	if have - n <= 0:
		game.state.inventory.erase(id)
		game.state.equipped.erase(id)
		if game.state.wielded == id:
			game.state.wielded = ""
	else:
		game.state.inventory[id] = have - n
	return n


# --- Wearing ----------------------------------------------------------------

## Puts on a carried item, following the checks in Game Objects.i7x:180-218.
## Returns true if the item is now worn.
static func wear(game, id: String, quiet: bool = false) -> bool:
	if count(game, id) <= 0 or not is_wearable(game, id) or id in game.state.equipped:
		return false
	var name := item_name(game, id)
	var slot := gear(game, id, "slot", "none")
	if slot != "none":
		for other: String in game.state.equipped:
			if gear(game, other, "slot", "none") == slot:
				_say(game, "**Your %s %s in the way!**" % [item_name(game, other), _is(game, other)], quiet)
				return false
	var tags := _body_tags(game)
	if slot in ["feet", "legs", "waist"] and ("taur" in tags or "no_legs" in tags):
		_say(game, "**Sadly, the %s %s incompatible with your body type!**" % [name, _is(game, id)], quiet)
		return false
	var size := int(gear(game, id, "size", "3"))
	var they := plural(game, id)
	if size > 0:
		var diff := scale(game) - size
		if diff > 1:
			_say(game, "**You can't even begin to fit into the %s. %s meant for smaller beings than yourself.**" % [name, "They are" if they else "It is"], quiet)
			return false
		if diff < -1:
			_say(game, "**The %s %s simply too big! %s meant for much larger beings than yourself.**" % [name, _is(game, id), "They are" if they else "It is"], quiet)
			return false
		var fit: String = {
			1: "They are quite small for your body size, but still barely fit" if they else "It is quite small for your body size, but still barely fits",
			0: "They fit fairly well" if they else "It fits fairly well",
			-1: "They are quite big for your body size, but fit more or less with some adjustments" if they else "It is quite big for your body size, but fits more or less with some adjustments",
		}[diff]
		_say(game, "**You start wearing the %s. %s.**" % [name, fit], quiet)
	else:
		_say(game, "**You start wearing the %s.**" % name, quiet)
	game.state.equipped.append(id)
	_play(game, id, "on wear")
	return true


## Takes off a worn item. Cursed items stay on; their text explains why.
static func remove(game, id: String, quiet: bool = false) -> bool:
	if id not in game.state.equipped or gear(game, id, "cursed", "no") == "yes":
		return false
	_say(game, "**You take off the %s.**" % item_name(game, id), quiet)
	game.state.equipped.erase(id)
	_play(game, id, "on remove")
	return true


static func _play(game, id: String, field: String) -> void:
	if game.content.program("%s#%s" % [id, field], "item") != null:
		game.runner.play_now("item:%s#%s" % [id, field])


static func wears(game, id: String) -> bool:
	return id in game.state.equipped


## The original's clothing adjectives (Characters.i7x:309-331).
static func bare(game, what: String) -> bool:
	for id: String in game.state.equipped:
		var slot := gear(game, id, "slot", "none")
		match what:
			"barefoot":
				if slot == "feet":
					return false
			"barecrotch":
				if slot in ["waist", "legs", "crotch"]:
					return false
			"barechest":
				if slot in ["body", "back", "chest", "breast"] and gear(game, id, "placement", "end") == "body":
					return false
	return true


## What the player wears and carries, as examining yourself says it
## (Game UI.i7x:461-505): each slot's first worn item's `worn text`, from
## head to feet, with remarks on a bare chest, crotch or feet, then the
## weapon and what hangs on the back or sits at the end. A covered bra or
## underwear is not mentioned.
## The player undressing a body area, for scene text (Basic Functions.i7x
## SelfStripCrotch / SelfStripChest): the worn items in `slots`, in that order.
static func strip_text(game, slots: Array, verb: String, area: String, bare: String) -> String:
	var items: Array = []
	for slot in slots:
		for id: String in game.state.equipped:
			if gear(game, id, "slot", "none") == slot and item_name(game, id) not in items:
				items.append(item_name(game, id))
				break
	if items.is_empty():
		return bare
	var listed: String = items[0] if items.size() == 1 else ", ".join(items.slice(0, -1)) + " and " + str(items[-1])
	if items.size() == 1:
		return "%s your %s and bare your %s" % [verb, listed, area]
	return "%s your %s, baring your %s" % [verb, listed, area]


## The names of the items worn on these slots (the first on each, in that order):
## "jeans and boxers" (`[worn list waist, legs, crotch]`), "" when none is worn.
static func worn_list(game, slots: Array) -> String:
	var items: Array = []
	for slot in slots:
		for id: String in game.state.equipped:
			if gear(game, id, "slot", "none") == str(slot).strip_edges() and item_name(game, id) not in items:
				items.append(item_name(game, id))
				break
	if items.size() < 2:
		return "" if items.is_empty() else str(items[0])
	return ", ".join(items.slice(0, -1)) + " and " + str(items[-1])


## 1 when the player wears something on the slot, else 0 (`worn.legs`).
static func worn_on(game, slot: String) -> int:
	for id: String in game.state.equipped:
		if gear(game, id, "slot", "none") == slot:
			return 1
	return 0


## The player dressing again after a strip (Basic Functions.i7x SelfDressCrotch /
## SelfDressChest): "collect your jeans and boxers to put them back on".
static func dress_text(game, slots: Array, bare: String) -> String:
	var items: Array = []
	for slot in slots:
		for id: String in game.state.equipped:
			if gear(game, id, "slot", "none") == slot and item_name(game, id) not in items:
				items.append(item_name(game, id))
				break
	if items.is_empty():
		return bare
	if items.size() == 1:
		return "collect and put your %s back on" % items[0]
	return "collect your %s and %s to put them back on" % [", ".join(items.slice(0, -1)), items[-1]]


static func worn_description(game) -> String:
	var lines: PackedStringArray = []
	var body: String = game.content.typed_value("form", game.part_form("player", "torso"), "name", "human").to_lower()
	var chest_visible := true
	var crotch_visible := true
	var barefoot := true
	for slot: String in ["head", "eyes", "face", "neck", "body", "back", "chest", "breast", "arms", "hands", "legs", "waist", "crotch", "feet"]:
		if slot == "arms" and chest_visible:
			lines.append("Naked from the waist up, your %s %s on full display." % [body, "breasts are" if int(game.value("player.breasts.size") if game.value("player.breasts.size") != null else 0) > 0 else "chest is"])
		elif slot == "feet" and crotch_visible:
			lines.append("Your %s waist and legs are %sbare-ass naked, exposing your privates for everyone to see." % [body, "also " if chest_visible else ""])
		for id: String in game.state.equipped:
			if gear(game, id, "slot", "none") != slot or gear(game, id, "placement", "end") not in ["body", "head", "neck"]:
				continue
			if slot in ["body", "back", "chest"]:
				chest_visible = false
			elif slot == "breast":
				if not chest_visible:
					break
				chest_visible = false
			elif slot in ["legs", "waist"]:
				crotch_visible = false
			elif slot == "crotch":
				if not crotch_visible:
					break
				crotch_visible = false
			elif slot == "feet":
				barefoot = false
			_worn_text(game, id, lines)
			break
	if barefoot:
		lines.append("You are barefoot right now.")
	var out := " ".join(lines)
	var carried: PackedStringArray = []
	if game.state.wielded != "":
		var id: String = game.state.wielded
		var name := item_name(game, id)
		carried.append("You are carrying %s %s just in case of trouble." % ["an" if name.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a", name])
		var diff := scale(game) - int(arm(game, id, "size", "3"))
		if diff != 0:
			carried.append("Due to its comparatively %s size, it is %s unwieldy for you to use at the moment." % [
				"small" if diff > 0 else "big", "very" if absi(diff) > 3 else "rather" if absi(diff) == 3 else "somewhat"])
	for place: String in ["shield", "back", "end"]:
		for id: String in game.state.equipped:
			if gear(game, id, "placement", "end") != place:
				continue
			if gear(game, id, "slot", "none") == place:
				_worn_text(game, id, carried)
				break
			elif place == "end":
				_worn_text(game, id, carried)
	if not carried.is_empty():
		out += "\n" + " ".join(carried)
	return out


static func _worn_text(game, id: String, into: PackedStringArray) -> void:
	var text := gear(game, id, "worn text", "")
	if text != "":
		into.append(TextTemplate.plain(game.render(TextTemplate.compile(text))))


static func naked(game) -> bool:
	return bare(game, "barefoot") and bare(game, "barecrotch") and bare(game, "barechest")


## Gender look (sum of `gender look`, negative is feminine) and style counts
## of what is worn (Expanded Clothing Mechanics.i7x:76-167).
static func looks(game) -> Dictionary:
	var out := {"gender_look": 0}
	for s in STYLES + ["trap", "sissy", "himbo", "master"]:
		out[s] = 0
	var male: bool = game.adjective("player", "male")
	var female: bool = game.adjective("player", "female")
	for id: String in game.state.equipped:
		out.gender_look += int(gear(game, id, "gender look", "0"))
		for s: String in gear(game, id, "style").split(","):
			s = s.strip_edges()
			var gendered: Dictionary = {"cute": "trap", "slutty": "sissy", "bimbo": "himbo", "brah": "brah", "mistress": "master"}
			if gendered.has(s):
				if male:
					out[gendered[s]] += 1
				elif female and s != "brah":
					out[s] += 1
			elif out.has(s):
				out[s] += 1
	return out


# --- Wielding ---------------------------------------------------------------

## Readies a carried weapon (Basic Functions.i7x:1099-1130). Weapons three or
## more size categories off can't be used; the message says so.
static func wield(game, id: String, quiet: bool = false) -> bool:
	if count(game, id) <= 0 or not is_weapon(game, id):
		return false
	var name := item_name(game, id)
	var diff := scale(game) - int(arm(game, id, "size", "3"))
	var usable := diff > -3 and diff < 3
	if usable:
		game.state.wielded = id
	var text: String = {
		4: "You try to ready your %s, but there really is no way you could realistically use this in combat!",
		3: "You try to ready your %s, but there really is no way you could realistically use this in combat!",
		2: "Carefully taking the far too small %s in one hand, you can't help but ask yourself if this won't hinder more than help in a fight.",
		1: "You grab the %s with your comparatively large hand, finding it somewhat uncomfortable to wield.",
		0: "You ready your %s.",
		-1: "You grab your %s with your comparatively small hand, finding it somewhat uncomfortable to wield.",
		-2: "Clutching onto your %s with both hands, you have trouble controlling its momentum. This will be intensely difficult to use.",
		-3: "Trying to use your %s as a weapon is fairly ridiculous, given your size.",
		-4: "There is simply no way you could use your %s as a weapon, given your small stature.",
	}.get(clampi(diff, -4, 4), "")
	_say(game, "**%s**" % (text % name), quiet)
	return usable


static func unwield(game, quiet: bool = false) -> bool:
	if game.state.wielded == "":
		return false
	_say(game, "**You stop holding your %s.**" % item_name(game, game.state.wielded), quiet)
	game.state.wielded = ""
	return true


## Remarks on how well a weapon suits the player's size (Game Objects.i7x:100-118).
static func size_remark(game, id: String) -> String:
	if not is_weapon(game, id):
		return ""
	var diff := scale(game) - int(arm(game, id, "size", "3"))
	return {
		4: "Trying to use this as a weapon is utterly ridiculous, given your size. Don't even try it!",
		3: "Trying to use this as a weapon is fairly ridiculous, given your size.",
		2: "Trying to use this as a weapon is incredibly difficult, as it is far to small for you to comfortably hold.",
		1: "Given that it is made for someone smaller than you, this isn't all that easy to use as a weapon.",
		0: "This is just the right size for you to wield comfortably.",
		-1: "A bit big for comfortable use, but with both hands and some effort, you'll manage.",
		-2: "Trying to use this as a weapon is incredibly difficult, as its sheer size threatens to pull you over.",
		-3: "Trying to use this as a weapon is fairly ridiculous, given your size.",
		-4: "Don't even think about using this in combat! Well, you might hide under its bulk, but that's about it.",
	}.get(diff, "")


# --- Combat -------------------------------------------------------------------

## The player's weapon: {damage, type, hit bonus, size penalty, text}.
static func weapon(game) -> Dictionary:
	var id: String = game.state.wielded
	if id == "" or count(game, id) <= 0:
		# The game's own unarmed attack (combat_rules), else plain fists.
		return {"id": "", "damage": int(CombatSystem.rule(game, "unarmed damage", str(UNARMED_DAMAGE))), "type": "melee",
			"hit": 0, "penalty": 0, "text": CombatSystem.rule(game, "unarmed attack", UNARMED_TEXT)}
	var diff := absi(scale(game) - int(arm(game, id, "size", "3")))
	return {"id": id, "damage": int(arm(game, id, "damage", "4")), "type": arm(game, id, "type", "melee"),
		"hit": int(arm(game, id, "hit bonus", "0")), "penalty": {2: 5, 1: 2}.get(diff, 0),
		"text": arm(game, id, "attack text", "your " + item_name(game, id))}


## Sum of a bonus over worn gear: "dodge bonus", "damage bonus" or "flee bonus".
static func bonus(game, key: String) -> int:
	var total := 0
	for id: String in game.state.equipped:
		total += int(gear(game, id, key, "0"))
	return total


## Damage after armor (Alt Combat.i7x:1058-1083, normal absorbancy).
## Returns {"taken", "prevented"}. Without armored gear no dice are rolled,
## as the rolls could not change the result.
## `allow_shield`: false when the player can't use a shield (pinned down).
static func absorb(game, damage: int, natural: int = 100, allow_shield: bool = true) -> Dictionary:
	var armored: Array = game.state.equipped.filter(func(id): return int(gear(game, id, "armor", "0")) > 0)
	var out := damage
	var total := natural
	if not armored.is_empty():
		var target := "head" if game.rng.chance(1, 4) else "body"
		for id: String in armored:
			var ac := int(gear(game, id, "armor", "0"))
			var eff := int(gear(game, id, "effectiveness", "0"))
			var place := gear(game, id, "placement", "end")
			if place == "shield" and allow_shield and game.rng.chance(eff, 100):
				var shield := maxi(1, damage * ac / 400)
				out = damage - shield
			if place == target:
				if game.rng.chance(eff, 100):
					total += ac * ac
				else:
					var effective: int = ac * game.rng.range_int(1, maxi(1, eff)) / 100
					total += effective * effective
	var mid: int = 10000 * out / (100 + int(sqrt(total)))
	out = (mid + 99) / 100
	return {"taken": out, "prevented": damage - out}


# --- Items on the ground --------------------------------------------------------

## The items lying at a location: {item id: count}.
static func ground(game, loc: String) -> Dictionary:
	if not game.state.ground.has(loc):
		var here := {}
		for id in game.content.list_field(loc, "items"):
			here[id] = int(here.get(id, 0)) + 1
		# Saves from before items could be dropped counted taken items instead.
		for id in here.keys():
			var key := "%s.taken.%s" % [loc, id]
			here[id] = int(here[id]) - int(game.state.values.get(key, 0))
			game.state.values.erase(key)
			if here[id] <= 0:
				here.erase(id)
		game.state.ground[loc] = here
	return game.state.ground[loc]


## Item ids on the ground in a stable order: the place's `items:` order first,
## then dropped items by name (saved dictionaries come back sorted).
static func ground_ids(game, loc: String) -> Array:
	var listed: Array = game.content.list_field(loc, "items")
	var ids: Array = ground(game, loc).keys()
	ids.sort_custom(func(a, b):
		var ia := listed.find(a)
		var ib := listed.find(b)
		if ia >= 0 and ib >= 0:
			return ia < ib
		if ia >= 0 or ib >= 0:
			return ia >= 0
		return str(a) < str(b))
	return ids


static func on_ground(game, loc: String, id: String) -> int:
	return int(ground(game, loc).get(id, 0))


static func _put_down(game, id: String, n: int) -> void:
	var here := ground(game, game.state.location)
	here[id] = int(here.get(id, 0)) + n


## Picks up one item from the ground (Inventory.i7x:330-347).
static func pick_up(game, id: String) -> bool:
	var here := ground(game, game.state.location)
	if int(here.get(id, 0)) <= 0:
		return false
	here[id] = int(here[id]) - 1
	if here[id] <= 0:
		here.erase(id)
	gain(game, id, 1)
	var it := "them" if plural(game, id) else "it"
	_say(game, "You pick up the %s and tuck %s in your backpack." % [item_name(game, id), it])
	return true


## Picks up everything here (Inventory.i7x:349-360).
static func pick_up_all(game) -> bool:
	var here := ground(game, game.state.location)
	if here.is_empty():
		return false
	for id: String in here.keys():
		for _i in int(here[id]):
			gain(game, id, 1)
			_say(game, "You pick up the %s and tuck %s in your backpack." % [item_name(game, id), "them" if plural(game, id) else "it"])
	here.clear()
	return true


## Why an item can't be dropped or junked right now, or "".
static func _in_use(game, id: String, verb: String) -> String:
	if count(game, id) != 1:
		return ""
	if game.state.wielded == id:
		return "You're wielding that, take it off first."
	if id in game.state.equipped:
		return "You're using that right now. Stop using it before you %s it." % verb
	return ""


## Drops one, or all but the one in use (Inventory.i7x:425-475).
static func drop(game, id: String, all: bool = false) -> bool:
	if count(game, id) <= 0:
		return false
	var in_use: bool = id in game.state.equipped or game.state.wielded == id
	if all:
		if in_use:
			game.notice("You're %s %s. Take it off first." % ["wielding" if game.state.wielded == id else "wearing",
				"one of those" if count(game, id) > 1 else "that"], false)
			return false
		var n := count(game, id)
		lose(game, id, n)
		_put_down(game, id, n)
		_say(game, "You set down %d x %s." % [n, item_name(game, id)])
		return true
	var refusal := _in_use(game, id, "drop")
	if refusal != "":
		game.notice(refusal, false)
		return false
	lose(game, id, 1)
	_put_down(game, id, 1)
	_say(game, "You set down the %s." % item_name(game, id))
	return true


## Drops everything except kept items and gear in use (Inventory.i7x:477-497).
static func drop_everything(game) -> bool:
	var total := 0
	for id: String in game.state.inventory.keys():
		if game.content.typed_value("item", id, "keep", "no") == "yes" or id in game.state.equipped or game.state.wielded == id:
			continue
		var n := count(game, id)
		lose(game, id, n)
		_put_down(game, id, n)
		total += n
	if total == 0:
		game.notice("You don't have anything you're ready to drop.", false)
		return false
	_say(game, "You drop everything but your journal and any equipped items you have. You get rid of %d item%s in all%s." % [total, "" if total == 1 else "s", ". Ahhh! Your back feels much better now" if total > 4 else ""])
	return true


## Destroys one, or all but the one in use (Inventory.i7x:362-423). The game
## asks before junking all; the interface asks for that confirmation.
static func junk(game, id: String, all: bool = false) -> bool:
	if count(game, id) <= 0:
		return false
	if game.content.typed_value("item", id, "keep", "no") == "yes":
		game.notice("You really don't think that's a good idea.", false)
		return false
	var name := item_name(game, id)
	if not all:
		var refusal := _in_use(game, id, "trash")
		if refusal != "":
			game.notice(refusal, false)
			return false
		var word := "your" if count(game, id) == 1 else "1"
		lose(game, id, 1)
		_say(game, "**You lose %s %s!**" % [word, name])
		return true
	if count(game, id) == 1 and (id in game.state.equipped or game.state.wielded == id):
		game.notice("You're %s. You need to take it off to trash it." % ("wielding that, so you'd best stop using it first" if game.state.wielded == id else "using that right now"), false)
		return false
	if id in game.state.equipped or game.state.wielded == id:
		lose(game, id, count(game, id) - 1)
		_say(game, "You trash all of them but the %s you're %s. Bye-bye." % [name, "using" if game.state.wielded == id else "wearing"])
	else:
		lose(game, id, count(game, id))
		_say(game, "You trash all of your %s. Bye-bye." % name)
	return true


# --- Purifying ---------------------------------------------------------------

## Whether a microwave can be used here: the location's `microwave:` field
## is "yes" or a condition, such as the library's power being on.
static func microwave_here(game) -> bool:
	var spec: String = game.content.typed_value("location", game.state.location, "microwave", "no")
	if spec in ["", "no"]:
		return false
	if spec == "yes":
		return true
	var c := Condition.compile(spec)
	return not c.has("error") and Condition.evaluate(c, game)


## Microwaves one carried item (Core Mechanics/Microwave.i7x:12-34). Items
## without a `purified` result become distilled cum or milk when tagged so;
## others can't be purified. `purify refusal` replaces the whole action.
static func purify(game, id: String) -> bool:
	if count(game, id) <= 0:
		return false
	if not microwave_here(game):
		game.notice("Now where do you want to microwave that?", false)
		return false
	var refusal: String = game.content.typed_value("item", id, "purify refusal")
	if refusal != "":
		_say(game, refusal)
		return false
	var result: String = game.content.typed_value("item", id, "purified")
	var tags: Array = game.content._list(game.content.get_def("item", id), "tags")
	if result == "":
		result = "distilled_cum" if "cum" in tags else "distilled_milk" if "milky" in tags else ""
	if result == "" or not game.content.has(result, "item"):
		_say(game, "You don't think that can get any more pure, at least not this way.")
		return false
	_say(game, "After microwaving the %s on a low setting, you are left with %s." % [item_name(game, id), item_name(game, result)])
	game.apply({"op": "take", "item": id, "amount": {"value": {"op": "num", "v": 1}}, "quiet": false})
	game.apply({"op": "give", "item": result, "amount": {"value": {"op": "num", "v": 1}}, "quiet": false})
	return true


# --- Every turn ---------------------------------------------------------------

## Runs `worn each turn` scenes of worn gear (the original's everyturn rules
## on equipped items, such as Equipment.i7x:101-104).
static func tick(game) -> void:
	for id: String in game.state.equipped.duplicate():
		_play(game, id, "worn each turn")
