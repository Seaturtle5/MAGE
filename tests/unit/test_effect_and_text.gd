extends GutTest

class FakeGame:
	var rng := Rng.new(1)
	var values := {"player.thirst": 30, "n": 2}
	var described: Array = []
	func value(path: String) -> Variant:
		return values.get(path, null)
	func state_index(_p: String, _v: Variant) -> int:
		return 0
	func turns_since(_p: String) -> int:
		return 0
	func ask(node: Dictionary) -> bool:
		return node.get("adjective", "") == "male"
	func describe(name: String) -> String:
		described.append(name)
		return "<%s>" % name
	func variation(_key: String, _count: int, order: String) -> int:
		return 1 if order == "cycling" else 0

func test_effects_compile() -> void:
	for e in ["drink 25", "drink 25 to 40", "player.libido - 10% quietly", "morale + 20 up to 0",
			"score + player.thirst / 3", "score - (player.thirst - 15) / 3", "give food 2", "take all chips",
			"feat + fertile", "alexandra trait + horny", "condition pill for 9 hours", "quest q = s",
			"outcome saved", "resolve", "move adam to lab", "adam lives at lab", "discover plaza", "spend 2 turns",
			"infect wyvern 2 to 3 times", "sex player receives anal from adam", "cancel use", "end heat",
			"adam.talk_progress = camp", "schedule timer.first after 2 actions"]:
		assert_false(Effect.compile(e).has("error"), e)

func test_quietly_and_amounts() -> void:
	var e := Effect.compile("player.libido - 10% quietly")
	assert_true(e.quiet)
	assert_eq(e.amount.percent, 10)
	var g := FakeGame.new()
	assert_eq(Effect.resolve_amount(Effect.compile("score - (player.thirst - 15) / 3").amount, g), 5)
	assert_eq(Effect.compile("condition pill for 9 hours").turns, 3)

func test_unknown_effect_is_error() -> void:
	assert_true(Effect.compile("dance wildly").has("error"))
	assert_true(Effect.compile("schedule timer.first after 0 actions").has("error"))

func test_effect_rules_are_tried_by_first_word() -> void:
	assert_eq(Effect._first_word("^give one of ([a-z0-9_, ]+)$"), "give")
	assert_eq(Effect._first_word("^cancel use$"), "cancel")
	assert_eq(Effect._first_word("^(lock|unlock) (\\w+)$"), "")  # starts with a choice
	assert_eq(Effect._first_word("^resolve(?: (\\w+))?$"), "")  # the word may go on
	assert_eq(Effect._first_word("^turns? left$"), "")
	assert_eq(Effect._first_word("^go ?home$"), "")  # the space is optional
	assert_eq(Effect._first_word("^go home|stay$"), "")  # a choice of whole sentences
	assert_eq(Effect._first_word("^go [|] home$"), "go")
	# Every rule is tried for the first word it needs, and rules without one for every word.
	for rule: Array in Effect._rules:
		var word := Effect._first_word((rule[1] as RegEx).get_pattern())
		assert_true(Effect._rules_by_word[word].has(rule), str(rule[0]))
		if word == "":
			for w: String in Effect._rules_by_word:
				assert_true(Effect._rules_by_word[w].has(rule), "%s for %s" % [rule[0], w])
	assert_eq(Effect.compile("give food 2").op, "give")
	assert_eq(Effect.compile("give.count = 2").op, "set")

func test_text_tokens() -> void:
	var tok := func(text: String) -> String:
		return " ".join(PackedStringArray(TextTemplate._tokenize(text).map(func(t: Dictionary) -> String: return "%s(%s)" % [t.k, t.v])))
	assert_eq(tok.call(""), "")
	assert_eq(tok.call("plain words"), "lit(plain words)")
	assert_eq(tok.call("a [ if x ] b[end if]"), "lit(a ) tag(if x) lit( b) tag(end if)")
	assert_eq(tok.call("**bold** *it* *"), "em(bold) lit(bold) em(bold) lit( ) em(italic) lit(it) em(italic) lit( ) em(italic)")
	# A "[" with no "]" after it is prose, and so is every later "["; a tag may hold "*" and "[".
	assert_eq(tok.call("x [a*b] y [z *w* [v"), "lit(x ) tag(a*b) lit( y [z ) em(italic) lit(w) em(italic) lit( [v)")
	assert_eq(tok.call("[[a]]"), "tag([a) lit(])")
	assert_eq(tok.call("é[ü]中*文"), "lit(é) tag(ü) lit(中) em(italic) lit(文)")

func test_text_markup_renders() -> void:
	var g := FakeGame.new()
	var t := TextTemplate.compile("Hi [if player is male]sir[else]madam[end if], [one of]a[or]b[cycling] **bold** [cock of player].")
	assert_false(t.has("error"))
	var spans := TextTemplate.render(t, g)
	assert_eq(TextTemplate.plain(spans), "Hi sir, b bold <cock of player>.")
	var bold := spans.filter(func(s): return s.bold)
	assert_eq(bold[0].text, "bold")

func test_text_errors() -> void:
	assert_true(TextTemplate.compile("[if a.b]never closed").has("error"))
	assert_true(TextTemplate.compile("stray [end if]").has("error"))
	assert_true(TextTemplate.compile("[one of]a[or]b").has("error"))
