extends GutTest
## Companions: tamed characters who follow the player, fight beside them,
## gain experience and levels, and the rules that limit the party.

const ROOT := "user://companion_test_packs"

const PACK := """== feat double_team
name: Double Team

== feat good_teacher
name: Good Teacher

== feat ringmaster
name: Ringmaster

== values log
values:
    assists: number

== zone woods
name: Woods

== location camp
name: Camp
description: A camp.
zone: woods
exits:
    north: glade

== location glade
name: Glade
description: A glade.
exits:
    south: camp

== companion_rules standard
party size: 1
party size modifiers:
    player has feat double_team: +1
companion xp: fight.level * 2
player xp cost: fight.level * 2 / 3
player xp cost when: not player has feat ringmaster
level up at: companion.level * 10
level up at modifiers:
    player has feat good_teacher: - companion.level * 4
levels while: companion.level < player.level
damage every: 3
dexterity every: 5
leveled:
    [companion.name] reaches level [companion.level]!
party too big:
    Your party is too big.

== character rex
name: Rex
pronouns: he
lives at: glade
stats:
    level: 2
    damage: 10
    dexterity: 40
companion:
    tamed: yes
summon:
    Rex bounds up to you.
dismiss:
    Rex trots home.
companion attack:
    Rex bites!

== character mia
name: Mia
pronouns: she
stats:
    level: 1
    charisma: 40
companion:
    attacks with: seduction
summon:
    if player.hp < 5:
        Mia shakes her head.
        ~ cancel summon
    else:
        Mia smiles and joins you.

== creature wolf
name: Wolf
found in: nowhere
level: 3
hp: 500
damage: 1
stats: strength 10, dexterity 1, stamina 10, perception 10, intelligence 10, charisma 10
libido: 0

== hook helping_hand
on: player hits
do:
    ~ log.assists + 1 quietly

== scene brawl
fight wolf:
    won:
        The wolf flees.
    lost:
        The wolf wins.
"""

var game: Game


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "/p")
	var files := {"pack.fsc": "== pack p\nname: Test\n", "c.fsc": PACK}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT])
	assert_eq(db.errors(), [], "the pack loads without errors")
	game = Game.new(db, 4)
	game.start("camp")
	game.set_value("player.hp", 100)
	game.set_value("player.level", 5)
	game.set_value("player.dexterity", 40)
	game.take_output()


func after_each() -> void:
	game.dispose()


func _do(effect: String) -> void:
	game.apply(Effect.compile(effect))


func _text() -> String:
	var out: PackedStringArray = []
	for e in game.take_output():
		if e.type in ["paragraph", "notice"]:
			out.append(TextTemplate.plain(e.spans) if e.has("spans") else str(e.get("text", "")))
	return "\n".join(out)


func test_summoning_and_the_party_limit() -> void:
	assert_true(game.adjective("player", "lonely"))
	_do("summon rex")
	assert_string_contains(_text(), "Rex bounds up to you.")
	assert_true(game.adjective("rex", "companion"))
	assert_false(game.adjective("player", "lonely"))
	_do("summon rex")
	assert_string_contains(_text(), "already following you")
	_do("summon mia")
	assert_string_contains(_text(), "no ally called Mia", "not tamed yet")
	_do("tame mia")
	_do("summon mia")
	assert_string_contains(_text(), "cannot have any more allies")
	assert_eq(int(game.value("party.limit")), 1)
	_do("feat + double_team")
	assert_eq(int(game.value("party.limit")), 2)
	_do("summon mia")
	assert_string_contains(_text(), "Mia smiles and joins you.")
	assert_eq(int(game.value("party.size")), 2)


func test_a_summon_text_can_refuse() -> void:
	_do("tame mia")
	game.set_value("player.hp", 3)
	_do("summon mia")
	assert_string_contains(_text(), "Mia shakes her head.")
	assert_false(game.adjective("mia", "companion"))


func test_companions_follow_and_go_home_when_dismissed() -> void:
	assert_eq(game.where("rex"), "glade")
	_do("summon rex")
	assert_eq(game.where("rex"), "camp", "a companion is where the player is")
	assert_true(game.adjective("rex", "here"))
	_do("dismiss rex")
	assert_string_contains(_text(), "Rex trots home.")
	assert_eq(game.where("rex"), "glade")


func test_companions_attack_and_seduce_in_fights() -> void:
	_do("feat + double_team")
	_do("tame mia")
	_do("summon rex")
	_do("summon mia")
	game.runner.start("brawl")
	game.take_output()
	for _i in 4:
		game.runner.combat_action("attack")
	var text := _text()
	assert_string_contains(text, "Rex bites!")
	assert_string_contains(text, "damage inflicted")
	assert_true(int(game.state.combat.hp) < 500)
	assert_true(int(game.state.combat.libido) > 0, "Mia raises the wolf's lust")
	assert_true(int(game.value("log.assists")) > 0, "the player hits hook ran")


func test_winning_shares_experience_and_levels_companions_up() -> void:
	_do("summon rex")
	game.set_value("rex.xp", 19)
	game.runner.start("brawl")
	game.state.combat.hp = 1
	game.runner.combat_action("attack")
	while game.runner.status == "continue":
		game.runner.proceed()
	var text := _text()
	# The wolf is level 3: Rex gains 6 (25 of the 20 needed at level 2).
	assert_eq(int(game.value("rex.level")), 3)
	assert_eq(int(game.value("rex.xp")), 5)
	assert_eq(int(game.value("rex.damage")), 11, "damage grows every third level")
	assert_string_contains(text, "Rex reaches level 3!")
	# The player gains 6 and gives up 6 / 3 for the companion.
	assert_eq(int(game.value("player.xp")), 4)
	assert_eq(int(game.value("rex.last_fight")), game.state.turn)


func test_ringmaster_keeps_full_experience_and_levels_stop_at_the_players() -> void:
	_do("feat + ringmaster")
	_do("summon rex")
	game.set_value("player.level", 2)
	game.set_value("rex.xp", 19)
	game.runner.start("brawl")
	game.state.combat.hp = 1
	game.runner.combat_action("attack")
	while game.runner.status == "continue":
		game.runner.proceed()
	assert_eq(int(game.value("player.xp")), 6)
	assert_eq(int(game.value("rex.level")), 2, "a companion does not outgrow the player")


func test_good_teacher_lowers_the_experience_needed() -> void:
	_do("feat + good_teacher")
	_do("summon rex")
	game.set_value("rex.xp", 12)
	CompanionSystem.check_level(game, "rex")
	assert_eq(int(game.value("rex.level")), 3, "level 2 needs 12 with Good Teacher")
	assert_eq(int(game.value("rex.xp")), 0)


func test_a_party_too_big_sends_one_home() -> void:
	_do("feat + double_team")
	_do("tame mia")
	_do("summon rex")
	_do("summon mia")
	_do("feat - double_team")
	game.take_output()
	game.pass_turn()
	assert_string_contains(_text(), "Your party is too big.")
	assert_eq(int(game.value("party.size")), 1)
	assert_false(game.adjective("rex", "companion"), "the first one goes home")


func test_offspring_counts_and_moving_children() -> void:
	game.state.values["pregnancy.offspring"] = [{"home": "with_you"}, {"home": "with_you"}, {"home": "bunker"}]
	assert_eq(int(game.value("offspring.with_you")), 2)
	assert_eq(int(game.value("offspring.total")), 3)
	_do("send children from with_you to bunker")
	assert_eq(int(game.value("offspring.bunker")), 3)


func test_expression_functions() -> void:
	assert_eq(Expr.evaluate(Expr.parse("min(500, 40 * 250 / 12)"), game), 500)
	assert_eq(Expr.evaluate(Expr.parse("max(2, 7) + sqrt(30 * 12)"), game), 25)
	assert_eq(Expr.evaluate(Expr.parse("feat.ringmaster * 50"), game), 0)
	assert_true(Expr.parse("min(1)").has("error"))


func test_companions_are_validated() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "_bad/p")
	var bad := """== character c
name: C
companion:
    attacks with: magic
    hit bonus: lots
    colour: red

== character d
name: D
summon:
    Hi.

== companion_rules r
party size: 1 +
level up at modifiers:
    player is grumpy: 2

== scene s
~ summon d
~ tame nobody
"""
	var files := {"pack.fsc": "== pack p\nname: Test\n", "bad.fsc": bad}
	for name: String in files:
		var fa := FileAccess.open(ROOT + "_bad/p/" + name, FileAccess.WRITE)
		fa.store_string(files[name])
		fa.close()
	var db := ContentDB.new()
	db.load_folders([ROOT + "_bad"])
	var text := str(db.errors())
	for part in ["fighting or seduction", "Hit bonus", "colour", "needs a companion: block", "Party size", "grumpy",
			"no companion: block", "nobody"]:
		assert_string_contains(text, part)
