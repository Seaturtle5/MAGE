class_name CreationSystem
extends RefCounted
## Character creation: what a new game asks before it starts.
##
## One `== creation_rules` definition (pack data) names the questions and the
## scripts around them:
##
##   == creation_rules my_game
##   choices: main_stat, starting_body       (menus asked on the new-game screen, in order)
##   feats:
##       basic: survivalist                  (a free feat of a feat group, and its default)
##   before:
##       ~ player.strength = 12 quietly      (runs first)
##   after:
##       ~ player.maxhp = player.stamina * 2 + 5 quietly   (runs after the choices, before the free feats)
##
## Each choice is an ordinary `== menu`: its title heads the question, each
## option (`* Label -- description [if condition]`) is an answer, and the
## chosen option's script runs when the game starts. `== game_mode` definitions
## are switches on the same screen; the chosen ones are the game's modes
## (`mode <id>` in conditions). Without creation rules a game starts with the
## engine's plain defaults.


static func rules(game) -> String:
	var defs: Dictionary = game.content.all_of("creation_rules")
	return "" if defs.is_empty() else str(defs.keys()[0])


## The questions for the new-game screen: [{id, title, options: [{label, description, enabled}], default}].
static func questions(game) -> Array:
	var out: Array = []
	var r := rules(game)
	if r == "":
		return out
	for id in game.content.list_field(r, "choices"):
		var menu: Dictionary = game.content.menus.get(id, {})
		if menu.is_empty():
			continue
		var options: Array = []
		var first := -1
		for i in menu.options.size():
			var o: Dictionary = menu.options[i]
			var ok := true
			if str(o.condition) != "":
				var c := Condition.compile(o.condition)
				ok = not c.has("error") and Condition.evaluate(c, game)
			options.append({"label": str(o.label), "description": str(o.description), "enabled": ok})
			if ok and first < 0:
				first = i
		var title: String = menu.settings.get("title", "")
		out.append({"id": id, "title": title if title != "" else str(id).capitalize(), "options": options,
			"default": maxi(first, 0)})
	return out


## The free feats: [{group, default, feats: [{id, name, description}]}].
static func feat_choices(game) -> Array:
	var out: Array = []
	var r := rules(game)
	if r == "":
		return out
	var d: FscParser.Definition = game.content.get_def("creation_rules", r)
	if d == null or not d.fields.has("feats"):
		return out
	for line: FscParser.Line in d.fields["feats"].children:
		if line.is_blank() or not ":" in line.text:
			continue
		var p := line.text.split(":", true, 1)
		var group := p[0].strip_edges()
		var feats: Array = []
		for id: String in LevelSystem.offered_feats(game, group):
			feats.append({"id": id, "name": game.content.typed_value("feat", id, "name", id),
				"description": game.content.typed_value("feat", id, "description")})
		out.append({"group": group, "default": p[1].strip_edges(), "feats": feats})
	return out


## The game modes a new game can switch on: [{id, name, description}].
static func modes(game) -> Array:
	var out: Array = []
	for id in game.content.all_of("game_mode"):
		out.append({"id": id, "name": game.content.typed_value("game_mode", id, "name", str(id).capitalize()),
			"description": game.content.typed_value("game_mode", id, "description")})
	return out


## Runs creation for a new game: `before`, each chosen answer (by question ID,
## an option index; the default when not given), `after`, then the free feats
## (by "feat <group>", a feat ID; the default when not given).
static func create(game, choices: Dictionary = {}) -> void:
	var r := rules(game)
	if r == "":
		return
	_play(game, "creation_rules:%s#before" % r)
	for q: Dictionary in questions(game):
		var index := int(choices.get(q.id, q.default))
		if index < 0 or index >= q.options.size() or not q.options[index].enabled:
			index = q.default
		_play(game, "%s@%d" % [q.id, index])
	_play(game, "creation_rules:%s#after" % r)
	# The free feats come last, as in the original: a feat's `gained` can build on the starting numbers.
	for f: Dictionary in feat_choices(game):
		var feat := str(choices.get("feat " + str(f.group), f.default))
		if feat != "" and game.content.has(feat, "feat") and feat not in game.state.feats:
			LevelSystem.take_feat(game, feat)


static func _play(game, pid: String) -> void:
	if game.content.program(pid) != null:
		game.runner.play_now(pid)
