class_name SexSystem
extends RefCounted
## Records what happened in a sex scene, after the original's NPCSexAftermath and
## CreatureSexAftermath (Core Mechanics/Basic Functions.i7x:545-960):
##
##   ~ sex player receives vaginal from francois
##   ~ sex francois receives anal from player
##   ~ sex leah receives oral_cock from wolf
##
## Partners are the player, characters and creatures. A record:
## - marks the player's partner as met and had sex (the original's PlayerFucked);
## - takes the receiving partner's virginity for the act (vaginal and vaginal_toy:
##   virgin; anal and anal_toy: anal virginity; oral acts: oral virginity) and the
##   giving partner's penile virginity for anal and vaginal, with the original's
##   bold line, and remembers who took it (`<who>.first_<kind>_partner`);
## - counts the act for the player (`player.sex.given.<act>`, `player.sex.taken.<act>`);
## - rolls for the player's pregnancy when a creature, or a fertile character with a
##   strain (`body: form`), penetrates the player (vaginal: female pregnancy, anal:
##   MPreg; with eggs when the strain is tagged ovi_impregnator);
## - plays a character's `impregnation` script when the character is penetrated by
##   a fertile partner (the original's ImpregFunction of the character);
## - runs the hooks `on: after sex`, which read `sex.taker`, `sex.giver` and
##   `sex.act`, and `sex.with` (character or creature: the player's partner's kind);
##   Core Mechanics lowers libido after sex with a character there.

const VIRGINITY := {"anal": "anal_virgin", "anal_toy": "anal_virgin", "vaginal": "virgin", "vaginal_toy": "virgin",
	"oral_cock": "oral_virgin", "oral_pussy": "oral_virgin", "oral_toy": "oral_virgin"}
const WORDS := {"anal_virgin": "anal virginity", "virgin": "virginity", "oral_virgin": "oral virginity",
	"penile_virgin": "penile virginity"}
const FIRST := {"anal_virgin": "anal", "virgin": "vaginal", "oral_virgin": "oral", "penile_virgin": "penile"}


static func record(game, taker: String, act: String, giver: String) -> void:
	var involved := taker == "player" or giver == "player"
	for who in [taker, giver]:
		if who != "player" and involved:
			game.set_value("%s.had_sex" % who, true)
			game.set_value("%s.met" % who, true)
	if involved:
		var partner := giver if taker == "player" else taker
		game.state.values["player.last_partner"] = partner
	game.state.stamps["%s.last_sex" % giver] = game.state.turn
	game.state.stamps["%s.last_sex" % taker] = game.state.turn
	_take(game, taker, VIRGINITY.get(act, ""), giver)
	if act in ["anal", "vaginal"]:
		_take(game, giver, "penile_virgin", taker)
	if taker == "player":
		_count(game, "taken", act)
	if giver == "player":
		_count(game, "given", act)
	_pregnancy(game, taker, act, giver)
	game.state.values["sex.taker"] = taker
	game.state.values["sex.giver"] = giver
	game.state.values["sex.act"] = act
	var partner := giver if taker == "player" else taker
	game.state.values["sex.with"] = "character" if game.content.has(partner, "character") \
		else "creature" if game.content.has(partner, "creature") else ""
	game.run_hooks("after sex")


## The partner loses a virginity; the line says who took it.
static func _take(game, who: String, key: String, other: String) -> void:
	if key == "" or not _keeps_records(game, who):
		return
	var v = game.value("%s.%s" % [who, key])
	if v != null and not Condition._truthy(v):
		return
	game.set_value("%s.%s" % [who, key], false)
	game.set_value("%s.experienced" % who, true)
	game.state.values["%s.first_%s_partner" % [who, FIRST[key]]] = other
	var word: String = WORDS[key]
	var line := ""
	if who == "player":
		line = "You have lost your %s to %s!" % [word, _name(game, other, true)] if key != "penile_virgin" \
			else "You have lost your penile virginity fucking %s!" % _name(game, other, true)
	elif other == "player":
		line = "You have taken %s's %s!" % [_name(game, who, false), word]
	else:
		line = "%s has lost their %s to %s!" % [_name(game, who, false), word, _name(game, other, true)]
	game.notice(line, false)


## Only the player and characters keep virginities and partners; creatures do not.
static func _keeps_records(game, who: String) -> bool:
	return who == "player" or game.content.has(who, "character")


static func _name(game, who: String, article: bool) -> String:
	if who == "player":
		return "you"
	if game.content.has(who, "character"):
		return WorldSystem.character_name(game, who)
	var n: String = game.creature_field(who, "name", who).to_lower()
	return ("the " + n) if article else n


static func _count(game, side: String, act: String) -> void:
	var path := "player.sex.%s.%s" % [side, act]
	game.state.values[path] = int(game.state.values.get(path, 0)) + 1


static func _pregnancy(game, taker: String, act: String, giver: String) -> void:
	if act not in ["anal", "vaginal"]:
		return
	if taker == "player" and giver != "player":
		var form := _strain(game, giver)
		if form == "" or (game.content.has(giver, "character") and Condition._truthy(game.value("%s.sterile" % giver))):
			return
		var eggs: bool = "ovi_impregnator" in CreatureChangeSystem.form_tags(game, form)
		PregnancySystem.attempt(game, "female" if act == "vaginal" else "male", form, eggs, false)
	elif game.content.has(taker, "character"):
		# The character's own pregnancy (the original's ImpregFunction): a fertile giver.
		if giver == "player" and Condition._truthy(game.value("player.sterile")):
			return
		if game.content.has(giver, "character") and Condition._truthy(game.value("%s.sterile" % giver)):
			return
		game.state.values["sex.giver"] = giver
		game.state.values["sex.act"] = act
		var prog: Program = game.content.program("%s#impregnation" % taker, "character")
		if prog != null:
			game.runner.play_now(prog.id)


## The strain a partner's seed carries: a creature's form, a character's body form.
static func _strain(game, who: String) -> String:
	if game.content.has(who, "character"):
		var form = game.value("%s.form" % who)
		return str(form) if form != null and str(form) not in ["", "none", "human"] else ""
	if game.content.has(who, "creature"):
		return game.creature_field(who, "form", who)
	return ""
