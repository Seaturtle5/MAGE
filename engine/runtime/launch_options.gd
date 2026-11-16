class_name LaunchOptions
extends RefCounted
## What the game is asked to do on the command line (after `--`).
##
##   --seed N          fix the random seed
##   --packs DIR       also load packs from this folder (can be repeated)
##   --only-packs      load packs from the --packs folders only
##   --data DIR        keep saves and remembered settings in this folder
##                     instead of the player's own
##   --scenario ID     skip the title screen and start this scenario
##   --start ID        skip the title screen and start at this location
##   --play ID         then play a story: a scene's ID, `event:<id>`, or a
##                     story inside content as `<type>:<id>#<field>`
##                     (`character:adam#talk`)
##   --set PATH=VALUE  set a value before the story plays (can be repeated):
##                     a number, yes or no, or words
##
## Together they let a pack be tried without touching the player's saves.

var seed := 0
var packs: Array = []
var only_packs := false
var data := ""
var scenario := ""
var start := ""
var play := ""
var values: Dictionary = {}


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	var i := 0
	while i < args.size():
		var value := args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--only-packs":
				options.only_packs = true
				i -= 1
			"--seed":
				options.seed = int(value)
			"--packs":
				options.packs.append(value)
			"--data":
				options.data = value
			"--scenario":
				options.scenario = value
			"--start":
				options.start = value
			"--play":
				options.play = value
			"--set":
				var at := value.find("=")
				if at > 0:
					options.values[value.left(at).strip_edges()] = read_value(value.substr(at + 1).strip_edges())
			_:
				i -= 1
		i += 2
	return options


## "3" is a number, "yes" and "no" are flags, anything else is words.
static func read_value(text: String) -> Variant:
	if text.is_valid_int():
		return int(text)
	if text in ["yes", "true"]:
		return true
	if text in ["no", "false"]:
		return false
	return text.trim_prefix("\"").trim_suffix("\"")


## Whether the game should skip the title screen.
func starts_game() -> bool:
	return scenario != "" or start != ""


## The folders packs are loaded from: the --packs folders first, then the
## game's usual ones unless --only-packs was given.
func content_folders(usual: Array) -> Array:
	var folders: Array = packs.duplicate()
	if not only_packs:
		folders.append_array(usual)
	return folders


## Where a file or folder of the player's data goes: under --data when
## given, else where it usually is ("user://saves").
func data_path(usual: String) -> String:
	return usual if data == "" else data.path_join(usual.trim_prefix("user://"))


## Starts the game as asked: the scenario or location, then the values, then
## the story. Returns false when neither a scenario nor a location was given.
func begin(game: Game) -> bool:
	if scenario != "":
		if not game.start_scenario(scenario):
			return false
	elif start != "":
		game.start(start)
	else:
		return false
	for path in values:
		game.set_value(path, values[path])
	if play.begins_with("event:"):
		var event := play.trim_prefix("event:")
		if not game.content.has(event, "event"):
			game.warn("There is no event '%s' to play." % event)
		elif game.runner.status == "idle":
			game.runner.start_event(event)
	elif play != "":
		if not game.content.menus.has(play) and game.content.program(play) == null:
			game.warn("There is no story '%s' to play." % play)
		else:
			game.runner.play_now(play)
	return true
