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
	return _scent(game, kind, game.state.location if kind == "location" else id) != ""


## Smells it: a title, the rules' line before the scent, then the scent (or the
## fallback). `action` is one of ACTIONS. Returns false when it cannot be smelled.
static func smell(game, action: String, arg: String) -> bool:
	var kind: String = ACTIONS.get(action, "")
	if kind == "" or not can_smell(game, kind, arg):
		return false
	var db: ContentDB = game.content
	var id: String = game.state.location if kind == "location" else ("" if kind == "player" else arg)
	game.state.values["smell.thing"] = id
	game.state.values["smell.kind"] = kind
	match kind:
		"character":
			game.runner.emit_title(db.typed_value("character", id, "name", id), id)
		"player":
			game.runner.emit_title(str(game.value("player.name")))
		_:
			game.runner.emit_title(db.typed_value(kind, id, "name", id).capitalize() if kind == "item" else db.typed_value(kind, id, "name", id))
	# Frames run last pushed first: the scent, then the line said before it on top.
	var frames: Array = game.runner.frames
	frames.append({"kind": "script", "pid": _scent(game, kind, id), "pc": 0})
	var before := ""
	if kind == "character":
		before = _rule(game, "smelling person")
	if before == "" and kind != "player":
		before = _rule(game, "smelling")
	if before != "":
		frames.append({"kind": "script", "pid": before, "pc": 0})
	game.runner.run()
	return true
