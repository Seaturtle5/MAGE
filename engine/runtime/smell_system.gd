class_name SmellSystem
extends RefCounted
## Smelling things: a character here, a carried item, the place the player is
## in, and the player themself (the Smell buttons). A thing's own `scent:`
## plays as a scene; a game's `== smell_rules` adds what is said before it and
## what is said when there is none:
##
##   == smell_rules my_smells
##   smelling: You sniff the [name of smell.thing].     (before a thing's or place's scent)
##   smelling person: You sniff [name of smell.thing].  (before a character's scent; else `smelling`)
##   no scent: It smells pretty normal for [a name of smell.thing].   (a thing or character without one)
##   no place scent: This place smells as you'd expect.               (a place without one)
##   yourself:                                                         (the player's own smell)
##       You smell like a [species of player].
##
## While a smell plays, `smell.thing` holds the ID of what is smelled (empty
## for the player) and `smell.kind` what it is: character, item, location or player. Without smell rules only things with a scent can be smelled.
##
## A place can hold more to smell: the doors on its ways out with a `scent:` of their
## own, and its `scenery scents:` (options naming a thing looked at there, each with
## its scent). Then the place's Smell asks what to smell: the place, each such door
## and each thing (`smell.kind` door or scenery; `smell.thing` the door's ID or the
## thing's name).

## The kinds of thing, by the action that smells them.
const ACTIONS := {"smell": "character", "smell_item": "item", "smell_place": "location", "smell_self": "player"}


static func rules(game) -> String:
	var defs: Dictionary = game.content.all_of("smell_rules")
	return "" if defs.is_empty() else str(defs.keys()[0])


## The program of a smell rules field, or "" when the game has none.
static func _rule(game, field: String) -> String:
	var id := rules(game)
	if id == "":
		return ""
	var pid := "smell_rules:%s#%s" % [id, field]
	return pid if game.content.program(pid) != null else ""


## The scene a thing's smell plays: its own scent, else the rules' fallback.
static func _scent(game, kind: String, id: String) -> String:
	if kind == "player":
		return _rule(game, "yourself")
	var own := "%s:%s#scent" % [kind, id]
	if game.content.program(own) != null:
		return own
	return _rule(game, "no place scent" if kind == "location" else "no scent")


## Whether the player can smell it now: a character here, an item carried, the
## place they are in ("" or its ID), or themself; and there is something to say.
static func can_smell(game, kind: String, id: String = "") -> bool:
	match kind:
		"character":
			if not game.content.has(id, "character") or game.where(id) != game.state.location or game.character_hidden(id):
				return false
		"item":
			if int(game.state.inventory.get(id, 0)) <= 0:
				return false
		"location":
			if id != "" and id != game.state.location:
				return false
		"player":
			pass
		_:
			return false
	if kind == "location" and not extras(game).is_empty():
		return true  # its doors or scenery have scents of their own
	return _scent(game, kind, game.state.location if kind == "location" else id) != ""


## Smells it: a title, the rules' line before the scent, then the scent (or the
## fallback). `action` is one of ACTIONS. Returns false when it cannot be smelled.
static func smell(game, action: String, arg: String) -> bool:
	var kind: String = ACTIONS.get(action, "")
	if kind == "" or not can_smell(game, kind, arg):
		return false
	if kind == "location" and not extras(game).is_empty():
		# Doors and things here have scents of their own: ask which to smell.
		game.runner.frames.append({"kind": "smell_choice", "shown": false})
		game.runner.run()
		return true
	var id: String = game.state.location if kind == "location" else ("" if kind == "player" else arg)
	_begin(game, kind, id, _scent(game, kind, id), "")
	game.runner.run()
	return true


## Puts a smell on the runner: a title, the rules' line before the scent, then the scent.
static func _begin(game, kind: String, id: String, scent: String, title: String) -> void:
	var db: ContentDB = game.content
	game.state.values["smell.thing"] = id
	game.state.values["smell.kind"] = kind
	match kind:
		"character":
			game.runner.emit_title(db.typed_value("character", id, "name", id), id)
		"player":
			game.runner.emit_title(str(game.value("player.name")))
		"scenery":
			game.runner.emit_title(title)
		_:
			game.runner.emit_title(db.typed_value(kind, id, "name", id).capitalize() if kind == "item" else db.typed_value(kind, id, "name", id))
	# Frames run last pushed first: the scent, then the line said before it on top.
	var frames: Array = game.runner.frames
	frames.append({"kind": "script", "pid": scent, "pc": 0})
	var before := ""
	if kind == "character":
		before = _rule(game, "smelling person")
	if before == "" and kind != "player":
		before = _rule(game, "smelling")
	if before != "":
		frames.append({"kind": "script", "pid": before, "pc": 0})


## What else there is to smell here besides the place: [{"kind", "id", "label", "scent"}]
## for the doors on its ways out that have a scent, then its `scenery scents:` options
## whose condition holds.
static func extras(game) -> Array:
	var db: ContentDB = game.content
	var loc: String = game.state.location
	var out: Array = []
	for door: String in game.runner.exit_doors(loc):
		if db.program("door:%s#scent" % door) != null and not out.any(func(x: Dictionary) -> bool: return x.id == door):
			out.append({"kind": "door", "id": door, "label": db.typed_value("door", door, "name", door), "scent": "door:%s#scent" % door})
	var menu_id := "%s.scenery scents" % loc
	if db.menus.has(menu_id):
		var options: Array = db.menus[menu_id].options
		for i in options.size():
			var o: Dictionary = options[i]
			if o.condition != "":
				var c := Condition.compile(o.condition)
				if c.has("error") or not Condition.evaluate(c, game):
					continue
			out.append({"kind": "scenery", "id": str(o.label), "label": str(o.label), "scent": "%s@%d" % [menu_id, i]})
	return out


## The choice of what to smell here: the place, its scented doors and things, Nevermind.
static func step(runner, f: Dictionary) -> bool:
	var game = runner.game
	if f.shown:
		runner.frames.erase(f)
		return false
	f.shown = true
	var loc: String = game.state.location
	var shown: Array = []
	runner.pending = []
	if _scent(game, "location", loc) != "":  # the place itself (its scent, or the rules' fallback)
		shown.append({"text": game.content.typed_value("location", loc, "name", loc), "description": "", "enabled": true})
		runner.pending.append({"smell": "location", "enabled": true})
	var things := extras(game)
	for i in things.size():
		shown.append({"text": str(things[i].label), "description": "", "enabled": true})
		runner.pending.append({"smell": "thing", "index": i, "enabled": true})
	shown.append({"text": "Nevermind", "description": "", "enabled": true, "leave": true})
	runner.pending.append({"smell": "", "enabled": true})
	game.emit({"type": "choices", "title": "Smell what?", "options": shown})
	runner.status = "choice"
	return true


static func choose(runner, f: Dictionary, p: Dictionary) -> void:
	var game = runner.game
	runner.frames.erase(f)
	match str(p.smell):
		"location":
			_begin(game, "location", game.state.location, _scent(game, "location", game.state.location), "")
		"thing":
			var things := extras(game)
			if int(p.index) < things.size():
				var t: Dictionary = things[int(p.index)]
				_begin(game, str(t.kind), str(t.id), str(t.scent), str(t.label))

