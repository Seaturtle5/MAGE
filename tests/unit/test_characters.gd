extends GutTest
## Characters: body, stats and relationship values, descriptors about them,
## sex records with virginities and pregnancy, presence lines and the actions
## a character or place offers.

const ROOT := "user://character_test_packs"

const PACK := """== values temp
values:
    num: number

== values log
values:
    hooks: number
    impregnations: number

== location bakery
name: Bakery
description: Flour everywhere.
actions:
    * Bake something
        You bake a loaf.

== form mutt
name: Mutt
sex: male
cock:
    description: canine
    change: your cock turns canine
    count: 1

== text cock_size_desc
[if player.cock.length < 6]small[else if player.cock.length < 12]large[else]huge[end if]

== character francois
name: Francois
pronouns: he
lives at: bakery
body:
    form: mutt
    cocks: 1
    cock length: 8
    ball size: 3
    cunts: 0
    ass depth: 12
stats:
    level: 5
    strength: 14
relationship:
    anal virgin: no
description:
    A mutt in an apron.
scent:
    He smells of bread.
presence:
    Francois kneads dough behind the counter.
talk:
    'Bonjour!'
sex:
    You and Francois share a moment.
impregnation:
    ~ log.impregnations + 1 quietly
actions:
    * Buy a croissant
        He hands you a croissant.

== character mabel
name: Mabel
pronouns: she
lives at: bakery
body:
    cunts: 1
    cunt depth: 6
    sterile: yes

== hook count_sex
on: after sex
when: sex.with = character
do:
    ~ log.hooks + 1 quietly
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "c.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 2)
	game.start("bakery")
	game.take_output()


func after_each() -> void:
	game.dispose()


func _notices() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type in ["notice", "paragraph"]:
			out.append(str(e.get("text", "")) if e.type == "notice" else TextTemplate.plain(e.spans))
	return "\n".join(out)


func test_body_stats_and_relationship_become_values() -> void:
	assert_eq(int(game.value("francois.cock.length")), 8)
	assert_eq(int(game.value("francois.balls.size")), 3)
	assert_eq(int(game.value("francois.ass.depth")), 12)
	assert_eq(int(game.value("francois.level")), 5)
	assert_eq(str(game.value("francois.form")), "mutt")
	assert_true(game.adjective("francois", "male"))
	assert_false(game.adjective("francois", "female"))
	assert_true(game.adjective("mabel", "female"))
	assert_false(game.adjective("francois", "met"), "met starts as no")
	assert_true(game.adjective("francois", "virgin"), "virginities start as yes")
	assert_false(game.adjective("francois", "anal virgin"), "unless the definition says otherwise")
	game.apply(Effect.compile("francois.cock.length + 4"))
	assert_eq(int(game.value("francois.cock.length")), 12, "scenes change them like any value")


func test_a_snippet_can_describe_a_character() -> void:
	game.set_value("player.cock.length", 3)
	assert_eq(game.describe("cock_size_desc"), "small", "about the player")
	assert_eq(game.describe("cock_size_desc of francois"), "large", "about Francois")
	assert_eq(game.describe("cock_size_desc"), "small", "the player again afterwards")


func test_sex_takes_virginities_counts_and_runs_hooks() -> void:
	game.apply(Effect.compile("sex player receives vaginal from francois"))
	var text := _notices()
	assert_string_contains(text, "You have lost your virginity to Francois!")
	assert_string_contains(text, "You have taken Francois's penile virginity!")
	assert_false(game.adjective("player", "virgin"))
	assert_false(game.adjective("francois", "penile virgin"))
	assert_true(game.adjective("francois", "met"))
	assert_true(Condition.evaluate(Condition.compile("francois has had sex"), game))
	assert_eq(int(game.value("player.sex.taken.vaginal")), 1)
	assert_eq(str(game.value("francois.first_penile_partner")), "player")
	assert_eq(int(game.value("log.hooks")), 1, "the after sex hook ran")
	game.apply(Effect.compile("sex player receives vaginal from francois"))
	assert_false(_notices().contains("virginity"), "a virginity is lost once")
	assert_eq(int(game.value("player.sex.taken.vaginal")), 2)


func test_a_fertile_partner_can_get_the_character_pregnant() -> void:
	game.apply(Effect.compile("sex mabel receives vaginal from player"))
	assert_string_contains(_notices(), "You have taken Mabel's virginity!")
	assert_eq(int(game.value("log.impregnations")), 0, "Mabel has no impregnation script")
	game.apply(Effect.compile("sex francois receives anal from player"))
	assert_eq(int(game.value("log.impregnations")), 1, "Francois's impregnation script runs")
	game.set_value("player.sterile", true)
	game.apply(Effect.compile("sex francois receives anal from player"))
	assert_eq(int(game.value("log.impregnations")), 1, "not by a sterile player")


func test_presence_actions_and_doings_appear_at_the_place() -> void:
	game.runner.show_location()
	var view: Dictionary = game.take_output().filter(func(e): return e.type == "location")[-1]
	var desc := "\n".join(view.description.map(func(p): return TextTemplate.plain(p)))
	assert_string_contains(desc, "Francois kneads dough behind the counter.")
	assert_true(view.actions.any(func(a): return a.id == "actions" and a.label == "Actions"), "the place's actions")
	var f: Dictionary = view.people.filter(func(p): return p.id == "francois")[0]
	assert_true(f.talk and f.sex and f.smell and f.look and f.actions)
	var m: Dictionary = view.people.filter(func(p): return p.id == "mabel")[0]
	assert_false(m.talk or m.sex or m.actions)
	assert_true(game.runner.act("smell", "francois"))
	assert_string_contains(_notices(), "He smells of bread.")
	assert_true(game.runner.act("actions", "francois"))
	game.take_output()
	game.runner.choose(0)
	assert_string_contains(_notices(), "He hands you a croissant.")


func test_character_fields_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := "== character c\nname: C\nbody:\n    tails: 2\n    cock length: long\n    sterile: maybe\n    form: nothing\nstats:\n    hp: 5\nrelationship:\n    friends: yes\n    met: sometimes\n\n== scene s\n[cock_size_desc of nobody]\n\n== text cock_size_desc\nbig\n"
	var files := {"pack.fsc": "== pack p\nname: Test\n", "player_values.fsc": TestPlayerValues.TEXT, "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	for part in ["tails", "cock length must", "sterile must", "nothing", "max hp", "friends", "met must", "nobody"]:
		assert_string_contains(text, part)
