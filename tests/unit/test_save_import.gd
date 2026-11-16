extends GutTest
## Importing progress from an Inform game's export files: the file reader, the
## save_import rules (values by `from:`, characters, the player, items, places,
## events, traits, lists, notes), the report, the `after import` hook and the
## validator's checks. The export files are small, hand-made ones.

const ROOT := "user://import_test_packs"
const EXPORT := "user://import_test_export"

const PACK := """== location shed
name: Shed
description: A shed.
flags: fast travel, known at start
items: stone
exits:
    east: yard

== location yard
name: Yard
original name: Back Yard, Old Yard
description: A yard.
flags: fast travel
exits:
    west: shed

== storage locker
name: Locker
at: shed

== item stone
name: stone
weight: 1

== item cap
name: cap
original name: old hat
equipment:
    slot: head

== item knife
name: knife
weapon:
    damage: 4

== form wolf
name: Wolf
head:
    description: a wolf's head
    change: your face stretches

== creature wolf
name: Grey Wolf
found in: nowhere
form: wolf

== feat tough
name: Tough
description: Hard to hurt.

== quest farm
name: Farm Work
stages:
    not_started
    open: You help at the farm.
    done: The farm is safe.
done at: done

== filter furry
name: Furry
description: Furry creatures.
from: FurryList, "Furries"

== collection jars
name: Jars
of: creature
gained: You get a jar.

== event lost_dog
name: Lost Dog
found by: nowhere
outcomes: found = 1, fled = 2
play:
    A dog.

== event old_mill
name: Old Mill
found by: nowhere
play:
    A mill.

== character adam
name: Adam
pronouns: he
lives at: shed
body:
    cock length: 6
values:
    talk: none, himself, camp
        from: Energy of Adam = 0, 1, 2
    trust: number 0
        from: HP of Adam

== character bea
name: Bea
pronouns: she
values:
    hp: number 0
    energy: none, met, friends

== character rex
name: Rex
pronouns: he
stats:
    level: 1
companion:
    tamed: no
summon:
    Rex comes.

== values player
values:
    freecred: number 0
        from: freecred
    hunted: flag
        from: hunteddog
    nickname: text
        from: PetName
    mood: calm, angry
        from: moodnumber
    last_bath: time
        from: lastbath (a turn stamp)
    last_nap: time
        from: lastnap
    songs: list
        from: songlist

== values town
values:
    stage: early, middle, late
        from: TownStage = 0, 5, 10
    colour: none, red, blue
        from: PickedColour

== values marks
values:
    note: text

== hook marked
on: after import
do:
    ~ marks.note = done quietly

== save_import numbers
name: Numbers
file: FSNumberSave
columns: NumberVarName, NumberVarValue
rows: named values
turn stamps: 240 counting down
map:
    Player_extra: player.score
    Turns: clock

== save_import truths
file: FSTruthSave
columns: TruthVarName, TruthVarValue
rows: named values

== save_import texts
file: FSTextSave
columns: TextVarName, TextVarValue
rows: named values

== save_import textlists
file: FSTextListSave
columns: TextListVarName, TextListVarValue
rows: named values

== save_import characters
name: Characters
file: FSCharacterVariable4Save
columns: Name, LocationName, Energy, HP, XP, Strength, Cock Length, PlayerMet
rows: characters
player row: yourself
nowhere: NPC Nexus
map:
    LocationName: location
    Cock Length: cock.length
    PlayerMet: met
    Strength: skip
    XP: skip
player:
    LocationName: location
    HP: hp
    XP: xp
    Strength: strength
    Cock Length: cock.length
    PlayerMet: skip
    Energy: skip

== save_import old_characters
file: FSCharacterVariable3Save
columns: Name, LocationName
rows: characters
when missing: FSCharacterVariable4Save
map like: characters

== save_import oldest_characters
file: FSCharacterVariable2Save
columns: Name, LocationName
rows: characters
when missing: FSCharacterVariable4Save, FSCharacterVariable3Save
map like: characters

== save_import possessions
file: FSPossessionSave
columns: Name, CarriedNumber, StoredNumber, EquippedStatus, CurseStatus
rows: items
map:
    CarriedNumber: carried
    StoredNumber: stored in locker
    EquippedStatus: worn
    CurseStatus: skip

== save_import room_items
file: FSRoomInventorySave
columns: RoomName, ItemName
rows: ground items

== save_import events
file: FSEventSave
columns: Name, ResolveState, ActiveState, Resolution, SituationArea
rows: events
map:
    ResolveState: resolved if Resolved
    ActiveState: active if Active
    Resolution: resolution
    SituationArea: skip

== save_import rooms
file: FSRoomSave
columns: Name, Reachability, ExplorationStatus, RestSafety
rows: places
map:
    ExplorationStatus: known if Known
    Reachability: skip
    RestSafety: skip

== save_import traits
file: FSTraitSave
columns: OwnerName, TraitText
rows: traits
map:
    Tamed: tamed
    currentCompanion: in party

== save_import body
file: FSNewPlayerSave
columns: HeadName, Hair Color
rows: player
map:
    HeadName: form of head
    Hair Color: skip

== save_import lists
file: FSPlayerListsSave
columns: ListName, EntryText
rows: lists
ignore: Imported
map:
    Feat: feats
    OpenQuest: quests open
    CompletedQuest: quests done
    EncounteredEnemy: creatures met
    BanList: filters banned
    WardList: filters warded
    Vial: collection jars
    Tape: list player.songs
    BlockList: skip

== save_import notes
file: FSNoteSave
columns: Date, Note
rows: notes
map:
    Date: day
    Note: text
"""

var game: Game
var db: ContentDB


func _write(dir: String, files: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for name: String in files:
		var fa := FileAccess.open(dir + "/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()


## A text cell as the original writes it.
static func _t(text: String) -> String:
	var codes: PackedStringArray = []
	for c in text:
		codes.append(str(c.unicode_at(0)))
	codes.append("0")
	return "S" + ",".join(codes) + ";"


## An export file: the header, the table line and one line per row.
static func _file(name: String, table: String, rows: Array) -> String:
	var out := "* //1234-ABCD// %s\n! %s (%d)\n" % [name, table, rows.size()]
	for row: Array in rows:
		var cells: PackedStringArray = []
		for c in row:
			cells.append(_t(c) if c is String else str(c))
		out += " ".join(cells) + " \n"
	return out


func _export() -> Dictionary:
	return {
		"FSNumberSave.glkdata": _file("FSNumberSave", "Table of GameNumbers", [
			["freecred", 250], ["moodnumber", 1], ["lastbath", 244], ["TownStage", 5], ["Player_extra", 7],
			["afsmread", 0], ["Unkept", 3], ["TownStage2", 0], ["Turns", 200], ["lastnap", 0]]),
		"FSTruthSave.glkdata": _file("FSTruthSave", "Table of GameTruths", [["hunteddog", 1], ["OtherTruth", 0]]),
		"FSTextSave": _file("FSTextSave", "Table of GameTexts", [["PetName", "Fluffy"], ["PickedColour", ""]]),
		"FSTextListSave.glkdata": _file("FSTextListSave", "Table of GameTextLists", [["songlist", "Old Road"], ["songlist", "Rain"]]),
		"FSCharacterVariable4Save.glkdata": _file("FSCharacterVariable4Save", "Table of GameCharacterVariable4", [
			["yourself", "Back Yard", 0, 30, 12, 15, 4, 0],
			["Adam", "Shed", 1, 7, 0, 0, 9, 1],
			["Rex", "NPC Nexus", 0, 0, 0, 0, 0, 0],
			["Ghost", "Nowhere Land", 0, 0, 0, 0, 0, 0],
			["Bob", "Shed", 0, 0, 3, 0, 0, 0],
			["Bea", "Yard", 2, 4, 0, 0, 0, 0]]),
		"FSCharacterVariable3Save.glkdata": _file("FSCharacterVariable3Save", "Table of GameCharacterVariable3", [["Adam", "Back Yard"]]),
		"FSCharacterVariable2Save.glkdata": _file("FSCharacterVariable2Save", "Table of GameCharacterVariable2", [["Adam", "Moon Base"]]),
		"FSPossessionSave.glkdata": _file("FSPossessionSave", "Table of GamePossessions", [
			["stone", 2, 3, 0, 0], ["old hat", 1, 0, 1, 0], ["knife", 1, 0, 1, 0], ["laser gun", 1, 0, 1, 0]]),
		"FSRoomInventorySave.glkdata": _file("FSRoomInventorySave", "Table of GameRoomInventories", [["Back Yard", "knife"], ["Moon", "stone"]]),
		"FSEventSave.glkdata": _file("FSEventSave", "Table of GameEvents", [
			["Lost Dog", "Resolved", "Inactive", 2, "Outside"], ["Old Mill", "Unresolved", "Active", 0, "Nowhere"], ["Dragon Fight", "Resolved", "Active", 1, "Nowhere"]]),
		"FSRoomSave.glkdata": _file("FSRoomSave", "Table of GameRooms", [["Shed", "Public", "Unknown", "Safe"], ["Old Yard", "Public", "Known", "Safe"]]),
		"FSTraitSave.glkdata": _file("FSTraitSave", "Table of GameTraits", [
			["Adam", "Likes Fish"], ["Rex", "tamed"], ["Rex", "currentCompanion"], ["Adam", "Tamed"], ["Ghost", "Spooky"]]),
		"FSNewPlayerSave.glkdata": _file("FSNewPlayerSave", "Table of NewPlayerData", [["Grey Wolf", "red"]]),
		"FSPlayerListsSave.glkdata": _file("FSPlayerListsSave", "Table of PlayerLists", [
			["Feat", "Tough"], ["Feat", "Flying"], ["OpenQuest", "Farm Work"], ["EncounteredEnemy", "Grey Wolf"],
			["BanList", "Furries"], ["BanList", "Imported"], ["WardList", "Imported"], ["Vial", "Grey Wolf"], ["Vial", "Grey Wolf"],
			["Tape", "Old Road"], ["BlockList", "Something"], ["Hobbies", "Knitting"]]),
		"FSNoteSave.glkdata": _file("FSNoteSave", "Table of JournalNotes", [[3, "Bob owes me soap"]]),
		"FSBeastVariableSave.glkdata": _file("FSBeastVariableSave", "Table of GameBeastVariables", [["Grey Wolf", "Outside", 0, "Male", 1]]),
		"readme.txt": "These are my files.",
	}


func before_each() -> void:
	_write(ROOT + "/p", {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "all.fsc": PACK})
	_write(EXPORT, _export())
	db = ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("shed")
	ItemSystem.gain(game, "stone", 5)  # the new game's own items go
	game.take_output()


func after_each() -> void:
	game.dispose()


# --- The file format -----------------------------------------------------------

func test_reads_the_inform_table_format() -> void:
	var f := OriginalExport.parse("* //AB-12// FSStuff\n! Table of Stuff (2)\n%s -12 -- 1 \nS0; 0 S233,116,233,0; 0 \n" % _t("Hi there"))
	assert_eq(f.name, "FSStuff")
	assert_eq(f.table, "Table of Stuff")
	assert_true(f.complete)
	assert_eq(f.rows, [["Hi there", -12, null, 1], ["", 0, "été", 0]])
	var unfinished := OriginalExport.parse("- //AB-12// FSStuff\n! Table of Stuff (1)\n12 x \n")
	assert_false(unfinished.complete)
	assert_eq(unfinished.problems.size(), 2, "an unfinished file and a cell that is not a number")


func test_reads_a_folder_with_and_without_endings() -> void:
	var files := OriginalExport.read_folder(EXPORT)
	assert_true(files.has("fsnumbersave"))
	assert_true(files.has("fstextsave"), "a file without .glkdata")
	assert_false(files.has("readme"), "a file that is not an export is left alone")
	assert_eq(files["fstextsave"].rows, [["PetName", "Fluffy"], ["PickedColour", ""]])


# --- Importing -------------------------------------------------------------------

func test_values_come_from_their_from_lines() -> void:
	var report := ImportSystem.run(game, EXPORT)
	assert_eq(game.value("player.freecred"), 250)
	assert_eq(game.value("player.hunted"), true)
	assert_eq(game.value("player.nickname"), "Fluffy")
	assert_eq(game.value("town.stage"), "middle", "a number becomes the state its from: lists")
	assert_eq(game.value("player.score"), 7, "map: names a value without from:")
	assert_eq(game.value("player.songs"), ["Old Road", "Rain"], "rows with one name make a list")
	assert_eq(game.state.turn, 40, "the original's clock at 200, counting down from 240")
	assert_eq(game.turns_since("player.last_bath"), 44, "a turn stamp of 244 is 44 turns before the clock's 200")
	assert_eq(game.value("town.colour"), "none", "an empty text is the starting state")
	assert_eq(game.value("player.last_nap"), null, "a stamp of 0 is the original's never")
	var text := ImportSystem.report_text(report)
	assert_string_contains(text, "Unkept = 3 (nothing in the loaded content keeps it)")
	assert_string_contains(text, "player.mood is a list of states")
	assert_false("afsmread" in text, "values at 0 are counted, not listed")
	assert_gt(int(report.at_start), 0)


func test_characters_and_the_player() -> void:
	var report := ImportSystem.run(game, EXPORT)
	assert_eq(game.value("adam.talk"), "himself", "Energy of Adam = 1 is the second state")
	assert_eq(game.value("adam.trust"), 7, "HP of Adam")
	assert_eq(game.value("adam.cock.length"), 9)
	assert_eq(game.value("adam.met"), true)
	assert_eq(game.value("bea.hp"), 4, "a column without a line goes to the value of the same name")
	assert_eq(game.where("adam"), "shed")
	assert_eq(game.state.char_location.get("rex"), "nowhere", "NPC Nexus means off stage (Rex then joins the party)")
	assert_eq(game.state.location, "yard", "the player row moves the player (by an original name)")
	assert_eq(game.value("player.hp"), 20, "hp stays within max hp")
	assert_eq(game.value("player.xp"), 12)
	assert_eq(game.value("player.strength"), 15)
	assert_eq(game.value("player.cock.length"), 4)
	var text := ImportSystem.report_text(report)
	assert_string_contains(text, "Ghost (no character called Ghost in the loaded content)")
	assert_string_contains(text, "Bob (no character called Bob")
	assert_string_contains(text, "Energy of Bea = 2 (bea.energy is a list of states")
	assert_false("Adam at Back Yard" in text, "the older character file is not read when the newer one is there")


func test_items_places_events_and_traits() -> void:
	var report := ImportSystem.run(game, EXPORT)
	assert_eq(ItemSystem.count(game, "stone"), 2, "the new game's items are replaced")
	assert_eq(game.state.storage.get("locker", {}), {"stone": 3})
	assert_eq(game.state.equipped, ["cap"], "matched by its original name, worn")
	assert_eq(game.state.wielded, "knife")
	assert_eq(game.state.ground.get("yard", {}), {"knife": 1})
	assert_eq(game.state.ground.get("shed", {}), {}, "the place's own starting items are replaced")
	assert_true(game.state.events["lost_dog"].resolved)
	assert_false(game.state.events["lost_dog"].active)
	assert_eq(game.value("lost_dog.resolution"), 2)
	assert_eq(game.value("lost_dog.outcome"), "fled", "the outcome carrying that number")
	assert_false(game.state.known.has("shed"))
	assert_true(game.state.known.has("yard"))
	assert_eq(game.state.traits.get("adam", []), ["likes_fish", "tamed"], "Tamed of a character who is no companion stays a trait")
	assert_true(game.value("rex.tamed"))
	assert_eq(game.state.companions, ["rex"])
	var text := ImportSystem.report_text(report)
	assert_string_contains(text, "laser gun (no item called laser gun")
	assert_string_contains(text, "Dragon Fight (no event called Dragon Fight")
	assert_string_contains(text, "stone at Moon (no place called Moon)")
	assert_string_contains(text, "Spooky of Ghost")


func test_body_lists_notes_and_the_hook() -> void:
	var report := ImportSystem.run(game, EXPORT)
	assert_eq(game.part_form("player", "head"), "wolf", "a creature's name gives its form")
	assert_eq(game.state.feats, ["tough"])
	assert_eq(game.value("quest.farm"), "open")
	assert_eq(game.state.encountered, ["wolf"])
	assert_eq(game.settings.banned, ["furry"], "a filter by the name its from: quotes")
	assert_eq(CollectionSystem.count(game, "jars", "wolf"), 2)
	assert_eq(game.value("player.songs"), ["Old Road", "Rain"])
	assert_eq(NotesSystem.count(game), 1)
	assert_eq(game.value("marks.note"), "done", "after import hooks play")
	var text := ImportSystem.report_text(report)
	assert_string_contains(text, "Feat: Flying (no feat called Flying")
	assert_string_contains(text, "Hobbies: Knitting (nothing in the loaded content keeps the list Hobbies)")
	assert_false("Imported" in text.replace("Imported from", ""), "the original's marker entries are passed over")
	assert_string_contains(text, "FSBeastVariableSave: 1 rows, no pack reads this file")


func test_older_files_only_without_the_newer() -> void:
	DirAccess.remove_absolute(EXPORT + "/FSCharacterVariable4Save.glkdata")
	var report := ImportSystem.run(game, EXPORT)
	assert_eq(game.where("adam"), "yard", "the older file is read, with the newer file's lines")
	assert_false("Moon Base" in ImportSystem.report_text(report), "the oldest is read only when both newer ones are missing")


func test_report_files_missing_and_bad_files() -> void:
	DirAccess.remove_absolute(EXPORT + "/FSNoteSave.glkdata")
	DirAccess.remove_absolute(EXPORT + "/FSCharacterVariable2Save.glkdata")
	_write(EXPORT, {"FSRoomSave.glkdata": _file("FSRoomSave", "Table of GameRooms", [["Shed", "Public"]])})
	var report := ImportSystem.run(game, EXPORT)
	assert_true("FSNoteSave" in report.missing)
	assert_false("FSCharacterVariable2Save" in report.missing, "older layouts read in place of a newer file are not missed")
	var text := ImportSystem.report_text(report)
	assert_string_contains(text, "Rows have 2 cells, but the import names 4 columns")
	assert_true(game.state.known.has("shed"), "a file that does not fit is not read")


func test_imported_state_is_saved() -> void:
	ImportSystem.run(game, EXPORT)
	var copy := Game.new(db, 3)
	assert_true(copy.load_dict(JSON.parse_string(JSON.stringify(game.save_dict()))))
	assert_eq(copy.value("player.freecred"), 250)
	assert_eq(copy.state.wielded, "knife")
	assert_eq(copy.turns_since("player.last_bath"), 44)
	copy.dispose()


func test_recognised_files() -> void:
	var r := ImportSystem.recognised(db, EXPORT)
	assert_eq(r.total, 13, "the older layouts read in place of a newer file are not counted")
	assert_eq(r.found.size(), 15)
	assert_eq(ImportSystem.recognised(db, ROOT).found, [], "a folder without export files")


func test_from_lines() -> void:
	assert_eq(ImportSystem.parse_from("Energy of Adam = 0, 1, 2, 10"), {"kind": "column", "key": "energy|adam", "numbers": [0, 1, 2, 10]})
	assert_eq(ImportSystem.parse_from("lust of Sandra (a turn stamp; 555 at the start)"), {"kind": "column", "key": "lust|sandra", "numbers": []})
	assert_eq(ImportSystem.parse_from("Medeaget = 0, 1, 2; Medea's request scene is outside this slice").numbers, [0, 1, 2])
	assert_eq(ImportSystem.parse_from("VoreList, \"Vore\""), {}, "free notes stay notes")
	assert_eq(ImportSystem.parse_from("Boombox is in the Bunker"), {})
	assert_eq(ImportSystem.snake("Connected Hellfire Corridor"), "connected_hellfire_corridor")
	assert_eq(ImportSystem.snake("Tyr's Club!"), "tyr_s_club")


# --- Validation --------------------------------------------------------------------

func test_validator_checks_the_rules() -> void:
	var bad := """== storage box
name: Box

== values v
values:
    n: number 0
    names: number 0

== region r
name: R
original name: Old Region

== save_import a
file: FSOne
columns: Name, Count
rows: things

== save_import b
file: FSTwo
columns: Name, Count, Worn
rows: items
turn stamps: soon
map:
    Count: carried
    Weight: carried
    Worn: stored in cupboard
    Name: eaten

== save_import c
file: fstwo
columns: Name, Value
rows: named values
turn stamps: 100 counting up
map:
    x: v.nothing
    y: nothing

== save_import d
file: FSThree
columns: Name, Head
rows: player
player row: me
map:
    Head: form of wings

== save_import e
file: FSFour
columns: ListName, Entry
rows: lists
when missing: FSNowhere
map:
    Vial: collection none
    Tape: list v.names

== save_import f
rows: events

== save_import g
file: FSFive
columns: Name
rows: places
map like: a
"""
	_write(ROOT + "_bad/p", {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "bad.fsc": bad})
	var bad_db := ContentDB.new()
	bad_db.load_folders([ROOT + "_bad"])
	var text := "\n".join(bad_db.errors().map(func(e): return str(e.message)))
	for part in ["Unknown field 'original name' for region", "'rows: things' is not a kind of row",
			"'turn stamps:' is written", "'Weight' is not one of the columns", "Storage 'cupboard' does not exist",
			"'eaten' is not something a row of items can set", "already read by save_import b",
			"'v.nothing' is not a declared value", "'nothing' is not something a row of named values can set",
			"'player row:' is for rows: characters", "'wings' is not a body part", "Collection 'none' does not exist",
			"v.names is not a list value", "never changes anything", "save_import f needs 'file:'",
			"save_import f needs 'columns:'", "save_import a reads other rows (things)"]:
		assert_string_contains(text, part)
