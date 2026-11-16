class_name HelpSystem
extends RefCounted
## The help topics a game and its packs offer (the Help screen). Any pack can
## add topics:
##
##   == help hunting
##   title: Hunting
##   order: 20                 (lower first; topics without one come last, in load order)
##   text:
##       You can hunt for specific creatures.
##
## A topic's text is text and conditions (or `-> scene` of text), worked out
## each time it is shown.


## The topics in order: [{"id", "title"}].
static func topics(game) -> Array:
	var db: ContentDB = game.content
	var ids: Array = db.all_of("help").keys()
	var place := {}
	for i in ids.size():
		place[ids[i]] = i
	var order := func(id: String) -> int:
		var o := db.typed_value("help", id, "order")
		return int(o) if o.is_valid_int() else 1 << 30
	ids.sort_custom(func(a: String, b: String) -> bool:
		var oa: int = order.call(a)
		var ob: int = order.call(b)
		return oa < ob or (oa == ob and int(place[a]) < int(place[b])))
	return ids.map(func(id: String) -> Dictionary: return {"id": id, "title": db.typed_value("help", id, "title", id)})


## A topic's text as paragraphs of spans, as descriptions are.
static func text(game, id: String) -> Array:
	return game.runner.render_paragraphs(game.content.program("help:%s#text" % id))
