extends GutTest
## What the inventory and the character sheet show about numbers: an item's
## stats compared with the gear in use (ItemSystem.stats), what changes the
## player's numbers now and where it comes from (Game.applied_bonuses), and the
## game's own details about the body (the status bar's `details:`).

const ROOT := "user://sheet_details_test_packs"

const PACK := """== location camp
name: Camp
description: A camp.

== item knife
name: knife
weight: 1
weapon:
    damage: 5
    type: melee
    hit bonus: -1

== item rifle
name: rifle
weight: 8
weapon:
    damage: 9
    type: ranged
    size: 5

== item helmet
name: helmet
weight: 3
equipment:
    slot: head
    placement: head
    armor: 60
    effectiveness: 80
    taur compatible: yes
    style: cool, sporty

== item cap
name: cap
equipment:
    slot: head
    placement: head
    armor: 10
    effectiveness: 50
    dodge bonus: 1
    gender look: -2

== item backpack
name: backpack
equipment:
    slot: back
    carry bonus: 20
    cursed: yes

== item cocoa
name: cocoa
in combat: yes
use:
    You drink it.

== feat strong_back
name: Strong Back
carry bonus: 25

== condition buzz
name: Caffeine buzz
while active:
    player.dexterity + 2

== text gender_word
[if player is herm]both[else if player is male]man[else if player is female]woman[else]neither[end if]

== status_bar bar
meters: hp
details:
    Gender: [gender_word]
    Cock: [if player is male][player.cocks] of [player.cock.length] inches[end if]
    Breasts: [if player.breasts.size > 0][player.breasts.size][end if]
    Numbers:
        Luck: [one of]a[or]b[or]c[at random]
        Empty: [if player.cocks > 5]many[end if]
    Last: [player.nipples]
"""

const PLAIN := """== location camp
name: Camp
description: A camp.

== status_bar bar
meters: hp
"""

var game: Game


func _game(text: String) -> Game:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "e.fsc": text}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	var g := Game.new(db, 4)
	g.start("camp")
	g.take_output()
	return g


func before_each() -> void:
	game = _game(PACK)


func after_each() -> void:
	game.dispose()


func _row(rows: Array, label: String) -> Dictionary:
	for r: Dictionary in rows:
		if r.label == label:
			return r
	return {}


func test_a_weapon_shows_its_numbers_and_the_difference_to_the_wielded_one() -> void:
	for id in ["knife", "rifle"]:
		game.apply(Effect.compile("give " + id))
	var rows := ItemSystem.stats(game, "knife")
	assert_eq(_row(rows, "Damage").value, "5")
	assert_eq(_row(rows, "Damage").compare, "", "nothing wielded: nothing to compare with")
	assert_eq(_row(rows, "Type").value, "melee, strength adds damage")
	assert_eq(_row(rows, "Size").value, "right for you")
	assert_eq(_row(rows, "Hit bonus").value, "-1")
	assert_eq(_row(rows, "Weight").value, "1 lb")
	ItemSystem.wield(game, "knife", true)
	assert_eq(_row(ItemSystem.stats(game, "knife"), "Damage").compare, "", "not compared with itself")
	rows = ItemSystem.stats(game, "rifle")
	assert_eq(_row(rows, "Damage").compare, "+4 compared with your knife")
	assert_eq(_row(rows, "Damage").better, 1)
	assert_eq(_row(rows, "Type").value, "ranged, perception adds damage")
	assert_eq(_row(rows, "Size").value, "too big for you: -5 to hit")
	assert_eq(_row(rows, "Size").better, -1)
	assert_eq(_row(rows, "Hit bonus").value, "+0", "a bonus the wielded knife has shows as lost")
	assert_eq(_row(rows, "Hit bonus").compare, "+1 compared with your knife")
	ItemSystem.unwield(game, true)
	assert_eq(_row(ItemSystem.stats(game, "rifle"), "Hit bonus"), {}, "a field the item does not have is not shown")


func test_a_damage_changed_in_play_shows_with_its_base() -> void:
	game.apply(Effect.compile("give knife"))
	game.apply(Effect.compile("item knife damage + 2"))
	assert_eq(_row(ItemSystem.stats(game, "knife"), "Damage").value, "7 (base 5)")


func test_wearables_show_their_fields_and_compare_with_the_slot_in_use() -> void:
	for id in ["helmet", "cap", "backpack"]:
		game.apply(Effect.compile("give " + id))
	var rows := ItemSystem.stats(game, "helmet")
	assert_eq(_row(rows, "Slot").value, "head")
	assert_eq(_row(rows, "Armor").value, "60")
	assert_eq(_row(rows, "Effectiveness").value, "80%")
	assert_eq(_row(rows, "Protects").value, "the head")
	assert_eq(_row(rows, "Size").value, "fits you")
	assert_eq(_row(rows, "Style").value, "cool, sporty")
	assert_eq(_row(rows, "Taur compatible").value, "yes")
	assert_eq(_row(rows, "Cursed"), {})
	ItemSystem.wear(game, "cap", true)
	rows = ItemSystem.stats(game, "helmet")
	assert_eq(_row(rows, "Armor").compare, "+50 compared with your cap")
	assert_eq(_row(rows, "Effectiveness").compare, "+30% compared with your cap")
	assert_eq(_row(rows, "Dodge bonus").value, "+0", "a bonus the worn cap has shows as lost")
	assert_eq(_row(rows, "Dodge bonus").better, -1)
	assert_eq(_row(ItemSystem.stats(game, "cap"), "Gender look").value, "-2 (feminine)")
	rows = ItemSystem.stats(game, "backpack")
	assert_eq(_row(rows, "Carry bonus").value, "+20")
	assert_eq(_row(rows, "Cursed").better, -1)
	assert_eq(_row(rows, "Armor"), {})


func test_other_items_show_plain_fields() -> void:
	game.apply(Effect.compile("give cocoa"))
	var rows := ItemSystem.stats(game, "cocoa")
	assert_eq(rows.map(func(r: Dictionary) -> String: return r.label), ["Weight", "In combat"])
	assert_eq(_row(rows, "Weight").value, "weightless")


func test_applied_bonuses_name_their_sources() -> void:
	for id in ["knife", "helmet", "cap", "backpack"]:
		game.apply(Effect.compile("give " + id))
	ItemSystem.wield(game, "knife", true)
	ItemSystem.wear(game, "helmet", true)
	ItemSystem.wear(game, "backpack", true)
	game.apply(Effect.compile("feat + strong_back"))
	var dex := int(game.value("player.dexterity"))
	game.start_condition("buzz", 5, true)
	var applied := game.applied_bonuses()
	var a: Dictionary = applied.attributes.dexterity
	assert_eq(a.value, dex + 2)
	assert_eq(a.base, dex, "the value without the condition")
	assert_eq(a.sources, [{"name": "Caffeine buzz", "delta": "+2"}])
	assert_eq(applied.attributes.strength.sources, [], "untouched attributes have no sources")
	var rows: Array = applied.rows
	assert_eq(_row(rows, "Weapon").value, "knife: damage 5, melee")
	assert_eq(_row(rows, "Hit bonus").value, "-1")
	assert_eq(_row(rows, "Armor, head").value, "60")
	assert_eq(_row(rows, "Armor, head").sources, [{"name": "helmet", "delta": "60"}])
	assert_eq(_row(rows, "Carry bonus").value, "+45")
	assert_eq(_row(rows, "Carry bonus").sources, [{"name": "Strong Back", "delta": "+25"}, {"name": "backpack", "delta": "+20"}])
	assert_eq(_row(rows, "Style").value, "cool 1, sporty 1")
	assert_eq(_row(rows, "Libido"), {})
	# Other values a condition changed, as its entry remembers them.
	game.state.conditions["buzz"].undo.append({"path": "player.libido", "delta": 5})
	rows = game.applied_bonuses().rows
	assert_eq(_row(rows, "Libido").value, "+5", "other values a condition changes")
	assert_eq(_row(rows, "Libido").sources, [{"name": "Caffeine buzz", "delta": "+5"}])
	game.end_condition("buzz")
	assert_eq(game.applied_bonuses().attributes.dexterity.sources, [])
	assert_eq(_row(game.applied_bonuses().rows, "Libido"), {})


func test_details_render_their_rows_and_leave_out_empty_ones() -> void:
	game.set_value("player.cocks", 0)
	game.set_value("player.cunts", 1)
	game.set_value("player.breasts.size", 0)
	var details := game.sheet_details()
	assert_eq(details.size(), 3, "rows, a group, then rows again")
	assert_eq(details[0].heading, "")
	assert_eq(details[0].rows, [{"label": "Gender", "text": "woman"}], "empty rows are left out")
	assert_eq(details[1].heading, "Numbers")
	assert_eq(details[1].rows.map(func(r: Dictionary) -> String: return r.label), ["Luck"])
	assert_eq(details[2].rows, [{"label": "Last", "text": "2"}])
	game.set_value("player.cocks", 2)
	game.set_value("player.cock.length", 7)
	game.set_value("player.breasts.size", 3)
	details = game.sheet_details()
	assert_eq(details[0].rows, [{"label": "Gender", "text": "both"}, {"label": "Cock", "text": "2 of 7 inches"},
		{"label": "Breasts", "text": "3"}])


func test_showing_details_rolls_no_dice() -> void:
	var before := game.rng.get_state()
	game.sheet_details()
	assert_eq(game.rng.get_state(), before)


func test_a_game_without_details_shows_none() -> void:
	var plain := _game(PLAIN)
	assert_eq(plain.sheet_details(), [])
	plain.dispose()


func test_the_validator_checks_details() -> void:
	var text := PACK.replace("    Last: [player.nipples]", "    Last: [no_such_snippet]\n    no colon here")
	var dir := "user://sheet_details_validate/v"
	DirAccess.make_dir_recursive_absolute(dir)
	var files := {"pack.fsc": "== pack v\nname: V\n", "player_values.fsc": TestPlayerValues.TEXT, "e.fsc": text}
	for name: String in files:
		var fa := FileAccess.open(dir + "/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders(["user://sheet_details_validate"])
	var messages: Array = db.errors().map(func(p: Dictionary) -> String: return str(p.message))
	assert_true(messages.any(func(m: String) -> bool: return m.contains("no_such_snippet")), "unknown snippets are reported")
	assert_true(messages.any(func(m: String) -> bool: return m.contains("'Label: text'")), "lines without a label are reported")
