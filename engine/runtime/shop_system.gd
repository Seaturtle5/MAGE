class_name ShopSystem
extends RefCounted
## Shops and trading, after the original's stores (Core Mechanics/Basic Shops.i7x,
## Store Mechanics.i7x, the Zephyr store, Darius's counter, Drenraya's shop) and
## its trading with traders (Inventory.i7x:488-504).
##
##   == shop darius_counter
##   name: Darius's counter
##   at: dariuss_crib
##   run by: darius                  (only open while he is here)
##   open when: <condition>          (optional)
##   currency: item food             (or a player value such as freecred; default:
##                                    the status bar's currency)
##   intro:   text when the shop opens
##   closed:  text when the place has the shop but it is not open now
##   stock:
##       bliss_tablet: 1
##       pixie_dust: 2 [if quest x is done]
##   buys:                           (items the shop pays for)
##       gem: 10
##   trades: yes                     (the player's items with `trades for` can be swapped)
##   trade bonus when: player has feat haggler
##   trade bonus chance: 1 in 3      (a second item for free, as Haggler does)
##   bought: / sold:                 scripts after each purchase or sale; `shop.item`
##                                   names the item and `shop.price` the price.
##
## The shop is a menu of Buy / Sell / Trade lines, with Leave. Lines the player
## cannot afford are shown but disabled.

static func field(game, id: String, name: String, fallback: String = "") -> String:
	return game.content.typed_value("shop", id, name, fallback)


## Shops at the player's place: open ones, and closed ones that say why.
static func here(game) -> Array:
	var out: Array = []
	for id in game.content.all_of("shop"):
		if game.state.location in game.content.list_field(id, "at"):
			if is_open(game, id) or game.content.program("shop:%s#closed" % id) != null:
				out.append(id)
	out.sort()
	return out


static func is_open(game, id: String) -> bool:
	var keeper := field(game, id, "run by")
	if keeper != "" and game.where(keeper) != game.state.location:
		return false
	var when := field(game, id, "open when")
	return when == "" or Condition.evaluate(Condition.compile(when), game)


## The currency: {"item": id} or {"value": "player.x"}, with labels for one
## and for several (`currency names: coin, coins` on the shop or the status bar).
static func currency(game, id: String) -> Dictionary:
	var c := field(game, id, "currency")
	var names: Array = game.content._list(game.content.get_def("shop", id), "currency names")
	for bar in game.content.all_of("status_bar"):
		if c == "":
			c = game.content.typed_value("status_bar", bar, "currency")
		if names.is_empty():
			names = game.content._list(game.content.get_def("status_bar", bar), "currency names")
		break
	var out := {}
	if c.begins_with("item "):
		var item := c.substr(5).strip_edges()
		out = {"item": item, "label": game.content.typed_value("item", item, "name", item)}
	else:
		out = {"value": "player." + c, "label": c}
	out["one"] = str(names[0]) if names.size() >= 1 else out.label
	out["label"] = str(names[1]) if names.size() >= 2 else out.label
	return out


## "1 coin", "3 coins".
static func amount(cur: Dictionary, n: int) -> String:
	return "%d %s" % [n, cur.one if n == 1 else cur.label]


static func money(game, cur: Dictionary) -> int:
	if cur.has("item"):
		return int(game.state.inventory.get(cur.item, 0))
	var v = game.value(cur.value)
	return int(v) if v != null else 0


static func pay(game, cur: Dictionary, amount: int) -> void:
	if cur.has("item"):
		game.apply({"op": "take", "item": cur.item, "amount": {"value": {"op": "num", "v": amount}}, "quiet": true})
	else:
		game.set_value(cur.value, money(game, cur) - amount)


static func earn(game, cur: Dictionary, amount: int) -> void:
	if cur.has("item"):
		game.apply({"op": "give", "item": cur.item, "amount": {"value": {"op": "num", "v": amount}}, "quiet": true})
	else:
		game.set_value(cur.value, money(game, cur) + amount)


## The lines of a `stock:` or `buys:` field: [{"item", "price", "cond"}].
static func lines(game, id: String, name: String) -> Array:
	var d: FscParser.Definition = game.content.get_def("shop", id)
	var out: Array = []
	if d == null or not d.fields.has(name):
		return out
	var re := RegEx.create_from_string("^(\\w+)\\s*:\\s*(\\d+)(?:\\s*\\[if (.+)\\])?$")
	for l: FscParser.Line in d.fields[name].children:
		if l.is_blank():
			continue
		var m := re.search(l.text.strip_edges())
		if m != null:
			out.append({"item": m.get_string(1), "price": int(m.get_string(2)), "cond": m.get_string(3), "line": l.number})
	return out


static func _holds(game, cond: String) -> bool:
	return cond == "" or Condition.evaluate(Condition.compile(cond), game)


## The menu: [{"text", "enabled", "shop": action, "item", "price"}], Leave last.
static func options(game, id: String) -> Array:
	var cur := currency(game, id)
	var have := money(game, cur)
	var out: Array = []
	for l in lines(game, id, "stock"):
		if not _holds(game, l.cond):
			continue
		out.append({"text": "Buy %s - %s" % [_name(game, l.item), amount(cur, l.price)], "enabled": l.price <= have,
			"shop": "buy", "item": l.item, "price": l.price})
	for l in lines(game, id, "buys"):
		if _holds(game, l.cond) and int(game.state.inventory.get(l.item, 0)) > 0 and l.item not in game.state.equipped:
			out.append({"text": "Sell %s - %s" % [_name(game, l.item), amount(cur, l.price)], "enabled": true,
				"shop": "sell", "item": l.item, "price": l.price})
	if field(game, id, "trades", "no") == "yes":
		var ids: Array = game.state.inventory.keys()
		ids.sort()
		for item in ids:
			var other: String = game.content.typed_value("item", item, "trades for")
			if other != "" and int(game.state.inventory[item]) > 0 and item not in game.state.equipped:
				out.append({"text": "Trade %s for %s" % [_name(game, item), _name(game, other)], "enabled": true,
					"shop": "trade", "item": item, "price": 0})
	out.append({"text": "Leave", "enabled": true, "shop": "leave", "item": "", "price": 0})
	return out


static func _name(game, item: String) -> String:
	return game.content.typed_value("item", item, "name", item)


## Carries out a Buy, Sell or Trade line. Returns the script to play after it ("" for none).
static func act(game, id: String, o: Dictionary) -> String:
	var cur := currency(game, id)
	game.state.values["shop.item"] = o.item
	game.state.values["shop.item_name"] = _name(game, o.item)  # for text: [shop.item_name]
	game.state.values["shop.price"] = o.price
	match o.shop:
		"buy":
			if money(game, cur) < int(o.price):
				game.notice("You can't afford the %s; it costs %s." % [_name(game, o.item), amount(cur, o.price)], false)
				return ""
			pay(game, cur, int(o.price))
			game.apply({"op": "give", "item": o.item, "amount": {"value": {"op": "num", "v": 1}}, "quiet": true})
			game.notice("You purchase the %s for %s." % [_name(game, o.item), amount(cur, o.price)], false)
			return "shop:%s#bought" % id
		"sell":
			game.apply({"op": "take", "item": o.item, "amount": {"value": {"op": "num", "v": 1}}, "quiet": true})
			earn(game, cur, int(o.price))
			game.notice("You sell the %s for %s." % [_name(game, o.item), amount(cur, o.price)], false)
			return "shop:%s#sold" % id
		"trade":
			# Inventory.i7x:498-504: the trader hands over the item's `trades for`.
			var other: String = game.content.typed_value("item", o.item, "trades for")
			game.apply({"op": "take", "item": o.item, "amount": {"value": {"op": "num", "v": 1}}, "quiet": true})
			game.apply({"op": "give", "item": other, "amount": {"value": {"op": "num", "v": 1}}, "quiet": true})
			game.notice("You offer up the %s and get a %s in return." % [_name(game, o.item), _name(game, other)], false)
			var bonus := field(game, id, "trade bonus when")
			var m := RegEx.create_from_string("^(\\d+) in (\\d+)$").search(field(game, id, "trade bonus chance", "1 in 3"))
			if bonus != "" and _holds(game, bonus) and m != null and game.rng.chance(int(m.get_string(1)), int(m.get_string(2))):
				game.apply({"op": "give", "item": other, "amount": {"value": {"op": "num", "v": 1}}, "quiet": true})
				game.notice("You get a second one free with your negotiating skills!", false)
			game.state.values["shop.item"] = other
			game.state.values["shop.item_name"] = _name(game, other)
			return "shop:%s#bought" % id
	return ""
