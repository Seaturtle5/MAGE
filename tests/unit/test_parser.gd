extends GutTest

func _parse(text: String) -> FscParser.Result:
	return FscParser.parse(text, "test.fsc")

func test_definitions_and_fields() -> void:
	var r := _parse("== character adam\nname: Adam\nbody:\n    scale: 3\n")
	assert_true(r.ok())
	var d := r.definitions[0]
	assert_eq([d.type, d.id], ["character", "adam"])
	assert_eq(d.fields["name"].value, "Adam")
	assert_true(d.fields["body"].has_children())

func test_extend_header() -> void:
	var r := _parse("== extend location library\npresence: Hi\n")
	assert_eq(r.definitions[0].mode, "extend")
	assert_eq(r.definitions[0].type, "location")

func test_bad_header_is_error() -> void:
	var r := _parse("== Character Adam Smith\n")
	assert_false(r.ok())
	assert_eq(r.diagnostics[0].line, 1)

func test_duplicate_field_is_error() -> void:
	var r := _parse("== item x\nname: a\nname: b\n")
	assert_false(r.ok())
	assert_eq(r.diagnostics[0].line, 3)

func test_scene_paragraphs_join_lines() -> void:
	var r := _parse("== scene s\nsource: here\nOne\ntwo.\n\nThree.\n")
	var nodes := r.definitions[0].nodes
	assert_eq(r.definitions[0].fields["source"].value, "here")
	assert_eq(nodes.size(), 2)
	assert_eq(nodes[0].text, "One two.")

func test_choices_with_conditions_and_description() -> void:
	var r := _parse("== scene s\n* Yes -- Agree [if player is male] [then leave]\n    Fine.\n* No\n")
	var c: Dictionary = r.definitions[0].nodes[0]
	assert_eq(c.kind, "choices")
	assert_eq(c.options.size(), 2)
	assert_eq(c.options[0].label, "Yes")
	assert_eq(c.options[0].description, "Agree")
	assert_eq(c.options[0].condition, "player is male")
	assert_true(c.options[0].then_leave)
	assert_eq(c.options[0].body[0].text, "Fine.")

func test_an_actions_command_words_are_not_text() -> void:
	var r := _parse("== scene s\n* Use the slide -- Slide down\n    command: take slide, use slide\n    Whee.\n")
	var o: Dictionary = r.definitions[0].nodes[0].options[0]
	assert_eq(o.commands, ["take slide", "use slide"])
	assert_eq(o.body.size(), 1, "the command line is not part of the scene")
	assert_eq(o.body[0].text, "Whee.")

func test_if_else_chain() -> void:
	var r := _parse("== scene s\nif a.b:\n    A\nelse if c.d:\n    C\nelse:\n    E\nAfter\n")
	var nodes := r.definitions[0].nodes
	assert_eq(nodes[0].kind, "if")
	assert_eq(nodes[0].branches.size(), 2)
	assert_eq(nodes[0]["else"][0].text, "E")
	assert_eq(nodes[1].text, "After")

func test_fight_outcomes() -> void:
	var r := _parse("== scene s\nfight wyvern (male):\n    won:\n        Yay\n    lost:\n        play wyvern.victory\n")
	var f: Dictionary = r.definitions[0].nodes[0]
	assert_eq([f.creature, f.variant], ["wyvern", "male"])
	assert_has(f.outcomes, "won")
	assert_eq(f.outcomes["lost"][0].kind, "play")

func test_menu_options_are_flat() -> void:
	var r := _parse("== menu m\ntitle: T\n* A\n    a\n* B\n")
	assert_eq(r.definitions[0].options.size(), 2)
	assert_eq(r.definitions[0].options[1].label, "B")

func test_unexpected_indent_is_error() -> void:
	var r := _parse("== scene s\nText\n        indented\n")
	assert_false(r.ok())
