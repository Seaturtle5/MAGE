extends GutTest

class FakeGame:
	var values := {"player.libido": 60, "adam.talk_progress": "camp", "p.flag": true}
	var states := ["none", "himself", "camp", "future"]
	var asked: Array = []
	func value(path: String) -> Variant:
		return values.get(path, null)
	func state_index(_path: String, v: Variant) -> int:
		return states.find(str(v))
	func turns_since(_path: String) -> int:
		return 5
	func ask(node: Dictionary) -> bool:
		asked.append(node.op)
		return node.get("who", "") == "player"

func test_forms_compile() -> void:
	for c in ["player is male", "player is in heat", "player is in library", "quest q reached access",
			"pure_pool outcome is saved", "chance 1 in 3", "check perception vs 15", "player has feat iron_stomach",
			"player does not have feat x", "adam has had sex", "player has water_bottle 2", "adam lives at camp",
			"player cock is wyvern", "time is night", "filter noncon is allowed", "level anal is more",
			"since adam.last_workout > 2 turns", "adam.talk_progress is at least camp", "won by seduction",
			"(a.b or c.d) and not e.f", "player.libido > player.humanity", "score > 3"]:
		assert_false(Condition.compile(c).has("error"), c)

func test_in_heat_is_an_adjective() -> void:
	assert_eq(Condition.compile("player is in heat").op, "is")
	assert_eq(Condition.compile("player is in library").op, "is_at")

func test_unknown_form_is_error() -> void:
	assert_true(Condition.compile("player is very much male indeed !").has("error"))
	assert_true(Condition.compile("adam.x >").has("error"))

func test_evaluate_comparisons_and_order() -> void:
	var g := FakeGame.new()
	assert_true(Condition.evaluate(Condition.compile("player.libido > 49"), g))
	assert_false(Condition.evaluate(Condition.compile("player.libido < 49"), g))
	assert_true(Condition.evaluate(Condition.compile("adam.talk_progress is camp"), g))
	assert_true(Condition.evaluate(Condition.compile("adam.talk_progress is at least himself"), g))
	assert_false(Condition.evaluate(Condition.compile("adam.talk_progress is at least future"), g))
	assert_true(Condition.evaluate(Condition.compile("p.flag"), g))
	assert_true(Condition.evaluate(Condition.compile("since adam.x > 2 turns"), g))

func test_evaluate_logic_and_negation() -> void:
	var g := FakeGame.new()
	assert_true(Condition.evaluate(Condition.compile("player is male and not adam is male"), g))
	assert_true(Condition.evaluate(Condition.compile("adam is male or player is male"), g))
	assert_true(Condition.evaluate(Condition.compile("adam is not male"), g))

func test_odd_and_even() -> void:
	var g := FakeGame.new()
	g.values["hawk.beaten"] = 3
	assert_eq(Condition.compile("hawk.beaten is odd").op, "parity")
	assert_true(Condition.evaluate(Condition.compile("hawk.beaten is odd"), g))
	assert_false(Condition.evaluate(Condition.compile("hawk.beaten is even"), g))
	assert_true(Condition.evaluate(Condition.compile("hawk.beaten is not even"), g))
	assert_true(Condition.evaluate(Condition.compile("unset.value is even"), g), "an unset number is 0, which is even")

func test_chance_with_computed_odds() -> void:
	var g := FakeGame.new()
	g.values["d.tt"] = 4
	var node := Condition.compile("chance d.tt + 16 in player.libido")
	assert_eq(node.op, "chance_expr")
	assert_eq(Condition.compile("chance 1 in 3").op, "chance", "plain numbers keep the simple form")
	assert_true(Condition.compile("chance d.tt in").has("error"))
	Condition.evaluate(node, g)
	assert_eq(g.asked.back(), "chance", "the computed odds are rolled like a plain chance")

func test_remainder() -> void:
	var g := FakeGame.new()
	g.values["d.n"] = 7
	assert_true(Condition.evaluate(Condition.compile("d.n % 5 = 2"), g))
	assert_true(Condition.evaluate(Condition.compile("d.n % 5 != 0 and d.n > 2"), g))
	assert_true(Condition.evaluate(Condition.compile("(d.n - 2) % 5 = 0"), g))
