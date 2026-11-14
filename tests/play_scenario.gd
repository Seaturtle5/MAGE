extends SceneTree
## Plays a scenario against the engine headless and prints a transcript.
##
## Usage:
##   godot --headless --path . --script res://tests/play_scenario.gd -- \
##       [--seed 42] [--start shelter] [--packs res://tests/packs] SCENARIO.txt
##
## Scenario steps, one per line ("#" starts a comment):
##   choose N         pick option N (1-based) of the current choice list
##   type TEXT        answer a typed question (~ ask) with TEXT
##   continue         past a page break
##   go DIRECTION     take an exit
##   talk ID          talk to a character
##   use ID, take ID  use or pick up an item
##   explore, rest, wait, observe, travel ID, hunt ID
##   new ID           start a scenario
##   filter ID STATE  set a content filter: normal, warded or banned
##   level ID OPTION  set a content level, for example "level anal more"
##   save PATH, load PATH   save or load the game as JSON
##
## The transcript format: text, then
## [title], [notice], [roll], [combat], {N:option} lists and >>> step lines.
## A scenario with a matching .expected.txt file is checked by the tests.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := 42
	var start_loc := "shelter"
	var packs := ["res://tests/packs"]
	var scenario := ""
	var i := 0
	while i < args.size():
		match args[i]:
			"--seed":
				seed_value = int(args[i + 1])
				i += 1
			"--start":
				start_loc = args[i + 1]
				i += 1
			"--packs":
				packs = Array(args[i + 1].split(","))
				i += 1
			_:
				scenario = args[i]
		i += 1
	var text := FileAccess.get_file_as_string(scenario) if scenario != "" else ""
	printraw(ScenarioPlayer.play(text, seed_value, start_loc, packs))
	quit()
