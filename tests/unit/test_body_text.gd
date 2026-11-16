extends GutTest
## Body and text readings (LooksSystem, GearSystem): looking at oneself, a
## form's body numbers, strain names, the child carried now and the newest
## child, traits in text, the heat that applies, and weapons and armor in
## scenes and text.

const ROOT := "user://body_text_packs"

const PACK := """== values log
values:
    cock: text
    pick: text
    number: number
    kept: text
    boost: number
    forms: list "fox", "viper"

== location room
name: Room
description: A room.

== form fox
name: Fox
sex: male
scale: 2
torso:
    description: lithe
    change: you turn lithe
skin:
    description: [if player is looking at themself]a coat of long red fur covering your[else]fox-furred[end if]
    change: red fur sprouts
cock:
    count: 1
    length: 7
    girth: 2
    description: knotted
    change: your cock turns vulpine
balls:
    size: 2
breasts:
    size: 0
    nipples: 6
tail:
    description: a bushy tail
    change: a tail grows

== form snake
name: Snake
sex: female
head:
    description: a serpent's head
    change: scales
tail:
    description: a long tail
    change: a tail grows
cunt:
    count: 1
    depth: 8
    description: a slit
    change: your sex turns serpentine

== creature viper
name: Viper
level: 1
hp: 10
form: snake
gender: female

== creature fox
name: Fox
level: 1
hp: 10
form: fox
gender: male

== text self_description
You look at yourself. Your skin is [skin description]. [skin] skin.

== scene look_in_scene
In passing: [skin description].
[self_description]

== scene note_cock
~ log.cock = strain of player.body.cock
~ log.kept = strain of viper
Kept [log.cock] and [log.kept], [strain of log.cock], [strain of fox] and [strain of "Husky"].
~ log.pick = strain of entry 2 of log.forms
From a list: [log.pick].

== scene read_form
~ log.number = form.fox.cock.length + form.fox.balls.size
Fox: [form.fox.cock.length] inches, nipples [form.fox.breasts.nipples], size [form.fox.scale].

== pregnancy_rules test
female when: player is female
odds: 1 in 1
gestation: 6
extra children: 0
albino: 0 in 100
melanism: 0 in 100
child genders:
    female: 1
personalities: calm
child:
    CHILD [child.head] [child.torso] [child.tail]
    ~ record child

== scene conceive
~ impregnate by fox

== scene snake_child
~ unborn child looks like viper

== scene seal_child
~ unborn child head, body and tail look like "Seal Toy"

== scene monitor
Head: [unborn.head] Torso: [unborn.torso][if unborn.show_tail] Tail: [unborn.tail][end if]

== heat_rules policy
default: plain
female when: player is female
mpreg when: player is not female

== heat plain
name: Ordinary heat
cycle: 2
duration: 1

== heat fox
name: Fox heat
cycle: 3
duration: 1

== character alexandra
name: Alexandra
lives at: room

== scene list_traits
Traits: [traits of alexandra].

== item knife
name: pocketknife
weapon:
    damage: 5
    type: melee

== item club
name: club
weapon:
    damage: 7

== item jacket
name: leather jacket
equipment:
    slot: body
    armor: 20
    effectiveness: 50

== item scarf
name: scarf
equipment:
    slot: neck

== scene weapon_talk
You [if player wields anything]wave your [wielded weapon][else]raise your fists[end if]. You carry [player.carried_weapons] weapons.

== scene smithing
~ ask log.pick as weapon or armor: Which do you offer?
if log.pick is empty:
    Nothing.
else if player wields log.pick:
    Stop wielding it first.
else if player wears log.pick:
    Stop wearing it first.
else if damage of log.pick > 0:
    ~ item log.pick damage + 1
    Sharper: [damage of log.pick] damage.
else:
    ~ log.boost = max(2, armor of log.pick * 5 / 100)
    ~ item log.pick armor + log.boost up to 100
    ~ item log.pick effectiveness + effectiveness of log.pick / 10
    Improved: [armor of log.pick] armor, [effectiveness of log.pick]%.
"""

var game: Game


func _load(text: String, folder: String) -> ContentDB:
	DirAccess.make_dir_recursive_absolute(folder + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "content.fsc": text}
	for name: String in files:
		var fa := FileAccess.open(folder + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([folder])
	return db


func before_each() -> void:
	var db := _load(PACK, ROOT)
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 3)
	game.start("room")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _said() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type == "paragraph":
			out.append(TextTemplate.plain(e.spans))
		elif e.type == "choices":
			out.append(" | ".join(e.options.map(func(o): return str(o.text))))
	return "\n".join(out)


func _play(scene: String) -> String:
	game.runner.start(scene)
	return _said()


func test_a_part_says_more_while_the_player_looks_at_themself() -> void:
	game.apply(Effect.compile("transform skin into fox"))
	game.apply(Effect.compile("transform torso into fox"))
	game.take_output()
	assert_false(game.state.values.has("player.body_description.skin"), "a description that asks is worded each time")
	assert_true(game.state.values.has("player.body_description.torso"), "others keep the wording of the change")
	assert_false(game.adjective("player", "looking at themself"))
	var said := _play("look_in_scene")
	assert_string_contains(said, "In passing: fox-furred.")
	assert_string_contains(said, "Your skin is a coat of long red fur covering your.", "[self_description] in a scene: looking")
	var own := " ".join(game.self_description())
	assert_string_contains(own, "Your skin is a coat of long red fur covering your. a coat of long red fur covering your skin.")
	assert_eq(game.looking, 0, "looking ends with the description")
	var skin: Array = BodySystem.view(game).filter(func(p): return p.id == "skin")
	assert_eq(str(skin[0].description), "a coat of long red fur covering your", "the character screen is looking too")
	assert_eq(game.describe("skin description"), "fox-furred")
	assert_eq(game.describe("skin"), "fox-furred", "[skin] reads the part's description")


func test_a_forms_body_numbers() -> void:
	assert_eq(game.value("form.fox.cock.length"), 7)
	assert_eq(game.value("form.fox.cock.girth"), 2)
	assert_eq(game.value("form.fox.breasts.nipples"), 6)
	assert_eq(game.value("form.fox.cunt.depth"), 0, "a number the form does not give is 0")
	assert_eq(game.value("form.fox.scale"), 2)
	assert_eq(game.value("form.snake.scale"), 3)
	game.apply(Effect.compile("form fox cock length = 9"))
	assert_eq(_play("read_form"), "Fox: 9 inches, nipples 6, size 2.")
	assert_eq(game.value("log.number"), 11, "numbers in amounts")


func test_strain_names_in_lower_case_and_in_text_values() -> void:
	game.apply(Effect.compile("transform cock into fox"))
	game.take_output()
	assert_eq(_play("note_cock"), "Kept fox and snake, fox, fox and husky.\nFrom a list: snake.")
	assert_eq(game.value("log.cock"), "fox", "stored as text when it was said: it stays")
	game.apply(Effect.compile("transform cock into snake"))
	assert_eq(game.value("log.cock"), "fox")


func test_the_unborn_childs_strains_from_a_scene() -> void:
	_play("snake_child")
	assert_eq(game.value("pregnancy.child_head"), "", "no child carried: nothing changes")
	_play("conceive")
	assert_true(game.value("pregnancy.child_torso") in ["fox", "human"], "the father's or the mother's")
	_play("snake_child")
	for part in PregnancySystem.CHILD_PARTS:
		assert_eq(game.value("pregnancy.child_" + part), "snake", "a creature gives its form: " + part)
	assert_eq(_play("monitor"), "Head: Snake Torso: Snake Tail: Snake")
	_play("seal_child")
	assert_eq(game.value("pregnancy.child_torso"), "Seal Toy", "body is the torso")
	assert_eq(game.value("pregnancy.child_back"), "snake")
	assert_eq(_play("monitor"), "Head: Seal Toy Torso: Seal Toy", "a text strain has no tail to show")
	game.set_value("pregnancy.gestation", 1)
	game.pass_turn()
	assert_string_contains(_said(), "CHILD seal toy seal toy seal toy")
	assert_eq(game.value("offspring.last.head"), "seal toy", "the newest child")
	assert_eq(game.value("offspring.last.back"), "snake")
	assert_eq(game.value("offspring.last.gender"), "female")
	assert_eq(game.value("unborn.head"), "", "nothing is carried now")


func test_traits_in_text_and_the_heat_that_applies() -> void:
	assert_eq(_play("list_traits"), "Traits: .")
	game.apply(Effect.compile("alexandra trait + horny"))
	assert_eq(_play("list_traits"), "Traits: horny.")
	game.apply(Effect.compile("alexandra trait + whistle_taken"))
	game.apply(Effect.compile("alexandra trait + shy"))
	assert_eq(_play("list_traits"), "Traits: horny, whistle taken and shy.")
	assert_eq(game.value("player.heat_name"), "", "an untouched sex has no heat")
	game.apply(Effect.compile("transform cock into fox"))
	assert_eq(game.value("player.heat_name"), "Fox heat", "an untouched cunt: the cock's strain")
	game.apply(Effect.compile("transform cunt into snake"))
	assert_eq(game.value("player.heat_name"), "Ordinary heat", "a strain without its own heat: the default")


func test_the_wielded_weapon_and_carried_weapons() -> void:
	assert_eq(_play("weapon_talk"), "You raise your fists. You carry 0 weapons.")
	game.apply(Effect.compile("give knife quietly"))
	game.apply(Effect.compile("give club 2 quietly"))
	game.apply(Effect.compile("give jacket quietly"))
	game.apply(Effect.compile("wield knife quietly"))
	assert_eq(_play("weapon_talk"), "You wave your pocketknife. You carry 2 weapons.", "kinds of weapon, not copies")
	assert_eq(game.describe("wielded weapon"), "pocketknife")


func test_choosing_a_weapon_or_armor_and_improving_it() -> void:
	for item in ["knife", "club", "jacket", "scarf"]:
		game.apply(Effect.compile("give %s quietly" % item))
	game.apply(Effect.compile("wield knife quietly"))
	var said := _play("smithing")
	assert_string_contains(said, "club | leather jacket | pocketknife | Nevermind", "weapons and armor, not other gear")
	game.runner.choose(1)
	assert_string_contains(_said(), "Improved: 22 armor, 55%.")
	assert_eq(ItemSystem.gear(game, "jacket", "armor"), "22", "the armor counts from now on")
	_play("smithing")
	game.runner.choose(0)
	assert_string_contains(_said(), "Sharper: 8 damage.")
	_play("smithing")
	game.runner.choose(2)
	assert_string_contains(_said(), "Stop wielding it first.")
	_play("smithing")
	game.runner.choose(3)
	assert_string_contains(_said(), "Nothing.")
	game.apply(Effect.compile("item jacket armor + 200 up to 100"))
	assert_eq(GearSystem.number(game, "jacket", "armor"), 100, "a limit holds")
	var saved := game.save_dict()
	var g := Game.new(game.content, 1)
	g.load_dict(saved)
	assert_eq(GearSystem.number(g, "jacket", "armor"), 100, "saved with the game")
	g.dispose()


func test_body_and_gear_readings_are_validated() -> void:
	var bad := """== values v
values:
    pick: text
    n: number

== form f
name: F

== item rock
name: rock

== scene sc
~ v.n = form.f.cock.size + form.nothing.cock.length + form.f.weight
~ v.n = unborn.wings + offspring.last.wings
~ v.pick = strain of nowhere
~ v.n = armor of rock + damage of pebble
~ v.n = damage of rock
~ item rock armor + 1
~ item v.pick armor + 1
~ ask v.n as weapon: Which?
~ unborn child skin looks like f
~ unborn child looks like mystery
[strain of nowhere] [traits of nobody] [wielded weapon]
if player wields v.missing:
    Hm.
"""
	var db := _load(bad, ROOT + "_bad")
	var text := "\n".join(db.errors().map(func(e): return str(e.message)))
	for part in ["form.f.cock.size", "no form 'nothing'", "form.f.weight", "unborn.wings", "offspring.last.wings",
			"'nowhere' is neither a form nor a creature", "'rock' has no equipment field", "Unknown item 'pebble'",
			"'rock' has no weapon field", "'v.n' must be a text value", "no part 'skin'", "'mystery' is neither a form nor a creature",
			"'nobody' is not a character", "v.missing"]:
		assert_string_contains(text, part)
	assert_false(text.contains("wielded weapon"), "[wielded weapon] is known")
