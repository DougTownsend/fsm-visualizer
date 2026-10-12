# Unit tests for FSMModel (scripts/model/fsm_model.gd).
#
# GUT runs every function starting with "test_". `before_each()` runs before
# each test, so every test gets a fresh model. `watch_signals(obj)` makes GUT
# record the signals obj emits, so `assert_signal_emitted` can check them.
extends GutTest

var model: FSMModel


func before_each() -> void:
	model = FSMModel.create_default()


# --- defaults ---------------------------------------------------------------

func test_default_model_has_one_input_one_output_no_states() -> void:
	assert_eq(model.inputs.size(), 1)
	assert_eq(model.inputs[0].name, "in0")
	assert_eq(model.inputs[0].width, 1)
	assert_eq(model.outputs.size(), 1)
	assert_eq(model.outputs[0].name, "out0")
	assert_eq(model.states.size(), 0)
	assert_eq(model.initial_state_id, -1)
	assert_eq(model.machine_type, FSMModel.MachineType.MOORE)


# --- input combination encoding ----------------------------------------------

func test_combo_encoding_first_input_is_most_significant() -> void:
	model.set_input_width(0, 1)
	model.add_input("b", 2)
	assert_eq(model.input_combo_count(), 8)
	# combo 0b1_01: in0 = 1, b = 01
	assert_eq(model.combo_to_values(0b101), [1, 1] as Array[int])
	assert_eq(model.combo_to_values(0b010), [0, 2] as Array[int])
	assert_eq(model.combo_label(0b101), "1 01")


func test_values_to_combo_is_inverse_of_combo_to_values() -> void:
	model.add_input("b", 2)
	for combo in model.input_combo_count():
		assert_eq(model.values_to_combo(model.combo_to_values(combo)), combo)


func test_format_value() -> void:
	assert_eq(FSMModel.format_value(5, 4), "0101")
	assert_eq(FSMModel.format_value(1, 1), "1")
	assert_eq(FSMModel.format_value(300, 12), "300")


# --- states ----------------------------------------------------------------

func test_add_state_default_names_and_initial() -> void:
	watch_signals(model)
	var s0 := model.add_state()
	var s1 := model.add_state()
	assert_eq(s0.name, "S0")
	assert_eq(s1.name, "S1")
	assert_ne(s0.id, s1.id)
	assert_eq(model.initial_state_id, s0.id, "first state becomes initial")
	assert_signal_emit_count(model, "structure_changed", 2)


func test_new_state_has_unset_transitions_and_zero_outputs() -> void:
	var s := model.add_state()
	assert_eq(s.transitions.size(), 2)
	for t in s.transitions:
		assert_eq(t.next_id, FSMTransition.UNSET)
		assert_eq(t.output, [0] as Array[int])
	assert_eq(s.moore_output, [0] as Array[int])


func test_default_name_reuses_lowest_free_number() -> void:
	var s0 := model.add_state()
	model.add_state()
	model.remove_state(s0.id)
	assert_eq(model.add_state().name, "S0")


func test_new_states_get_distinct_positions() -> void:
	var a := model.add_state()
	var b := model.add_state()
	assert_ne(a.position, b.position)


func test_auto_layout_spaces_states_evenly_on_a_circle() -> void:
	var s0 := model.add_state()
	assert_eq(s0.position, Vector2.ZERO, "a lone state sits in the middle")
	for i in 3:
		model.add_state()
	var radius := model.states[0].position.length()
	for s in model.states:
		assert_almost_eq(s.position.length(), radius, 0.01)
	assert_almost_eq(model.states[0].position.distance_to(model.states[1].position),
		model.states[1].position.distance_to(model.states[2].position), 0.01)
	model.remove_state(model.states[1].id)
	assert_almost_eq(model.states[0].position.angle_to(model.states[1].position),
		TAU / 3, 0.01, "re-spaced after removal")


func test_moving_a_state_turns_auto_layout_off() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	model.set_state_position(s1.id, Vector2(300, 300))
	assert_false(model.auto_layout)
	var s2 := model.add_state()
	assert_eq(s1.position, Vector2(300, 300), "hand-placed state stays put")
	for other in [s0, s1]:
		assert_gt(s2.position.distance_to(other.position),
			FSMModel.LAYOUT_MIN_DISTANCE - 0.01, "new state not on top of " + other.name)


func test_arrange_states_turns_auto_layout_back_on() -> void:
	model.add_state()
	var s1 := model.add_state()
	model.set_state_position(s1.id, Vector2(300, 300))
	watch_signals(model)
	model.arrange_states()
	assert_true(model.auto_layout)
	assert_eq(s1.position, FSMModel.circle_layout(2)[1])
	assert_signal_emit_count(model, "state_moved", 2)


func test_remove_state_unsets_incoming_transitions() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	model.set_next_state(s0.id, 1, s1.id)
	model.remove_state(s1.id)
	assert_eq(s0.transitions[1].next_id, FSMTransition.UNSET)
	assert_eq(model.states.size(), 1)


func test_remove_initial_state_moves_initial_to_first_remaining() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	model.remove_state(s0.id)
	assert_eq(model.initial_state_id, s1.id)
	model.remove_state(s1.id)
	assert_eq(model.initial_state_id, -1)


func test_rename_state() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	watch_signals(model)
	assert_true(model.rename_state(s0.id, "  IDLE "), "spaces are trimmed")
	assert_eq(s0.name, "IDLE")
	assert_signal_emitted_with_parameters(model, "state_renamed", [s0.id])
	assert_false(model.rename_state(s1.id, "IDLE"), "duplicate names rejected")
	assert_false(model.rename_state(s1.id, "   "), "empty names rejected")
	assert_eq(s1.name, "S1")


func test_rename_does_not_break_transitions() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	model.set_next_state(s0.id, 0, s1.id)
	model.rename_state(s1.id, "DONE")
	assert_eq(model.state_name(s0.transitions[0].next_id), "DONE")


func test_set_next_state_rejects_unknown_state() -> void:
	var s0 := model.add_state()
	model.set_next_state(s0.id, 0, 999)
	assert_eq(s0.transitions[0].next_id, FSMTransition.UNSET)


func test_set_next_state_emits_transition_changed() -> void:
	var s0 := model.add_state()
	watch_signals(model)
	model.set_next_state(s0.id, 1, s0.id)
	assert_signal_emitted_with_parameters(model, "transition_changed", [s0.id, 1])


func test_outputs_are_clamped_to_port_width() -> void:
	var s0 := model.add_state()
	model.set_output_width(0, 2)
	model.set_moore_output(s0.id, 0, 99)
	model.set_mealy_output(s0.id, 1, 0, -5)
	assert_eq(s0.moore_output[0], 3)
	assert_eq(s0.transitions[1].output[0], 0)


func test_set_initial_state() -> void:
	model.add_state()
	var s1 := model.add_state()
	watch_signals(model)
	model.set_initial_state(s1.id)
	assert_eq(model.initial_state_id, s1.id)
	assert_signal_emitted(model, "initial_state_changed")


func test_set_machine_type_emits_structure_changed() -> void:
	watch_signals(model)
	model.set_machine_type(FSMModel.MachineType.MEALY)
	assert_eq(model.machine_type, FSMModel.MachineType.MEALY)
	assert_signal_emitted(model, "structure_changed")


# --- input ports -------------------------------------------------------------

func test_input_bits_are_capped() -> void:
	assert_false(model.add_input("big", FSMModel.MAX_INPUT_BITS))
	assert_true(model.add_input("ok", FSMModel.MAX_INPUT_BITS - 1))
	assert_eq(model.total_input_bits(), FSMModel.MAX_INPUT_BITS)
	assert_false(model.set_input_width(0, 2))
	assert_eq(model.inputs[0].width, 1)


func test_widening_input_keeps_existing_columns() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	model.set_next_state(s0.id, 1, s1.id)
	model.set_input_width(0, 2)
	assert_eq(s0.transitions.size(), 4)
	assert_eq(s0.transitions[0].next_id, FSMTransition.UNSET)
	assert_eq(s0.transitions[1].next_id, s1.id, "value 1 keeps its transition")
	assert_eq(s0.transitions[2].next_id, FSMTransition.UNSET, "new values start unset")
	assert_eq(s0.transitions[3].next_id, FSMTransition.UNSET)


func test_narrowing_input_keeps_low_values() -> void:
	model.set_input_width(0, 2)
	var s0 := model.add_state()
	model.set_next_state(s0.id, 1, s0.id)
	model.set_next_state(s0.id, 3, s0.id)
	model.set_input_width(0, 1)
	assert_eq(s0.transitions.size(), 2)
	assert_eq(s0.transitions[1].next_id, s0.id)


func test_adding_input_copies_behaviour_for_every_value_of_it() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	model.set_next_state(s0.id, 1, s1.id)  # in0 = 1 -> S1
	model.add_input("b", 1)
	# combos are now {in0, b}: in0 = 1 is combos 0b10 and 0b11
	assert_eq(s0.transitions.size(), 4)
	assert_eq(s0.transitions[0b10].next_id, s1.id)
	assert_eq(s0.transitions[0b11].next_id, s1.id)
	assert_eq(s0.transitions[0b00].next_id, FSMTransition.UNSET)
	# The copies must be independent objects.
	model.set_next_state(s0.id, 0b10, s0.id)
	assert_eq(s0.transitions[0b11].next_id, s1.id)


func test_removing_input_keeps_the_slice_where_it_was_zero() -> void:
	model.add_input("b", 1)
	var s0 := model.add_state()
	var s1 := model.add_state()
	model.set_next_state(s0.id, 0b10, s1.id)  # in0 = 1, b = 0
	model.set_next_state(s0.id, 0b11, s0.id)  # in0 = 1, b = 1
	model.remove_input(1)  # remove b
	assert_eq(s0.transitions.size(), 2)
	assert_eq(s0.transitions[1].next_id, s1.id)


func test_add_input_default_names() -> void:
	model.add_input()
	assert_eq(model.inputs[1].name, "in1")


func test_port_names_must_be_unique_across_inputs_and_outputs() -> void:
	assert_false(model.rename_input(0, "out0"))
	assert_true(model.rename_input(0, "x"))
	assert_eq(model.inputs[0].name, "x")
	assert_false(model.rename_output(0, ""))


# --- output ports ------------------------------------------------------------

func test_add_and_remove_output_resizes_every_output_list() -> void:
	var s0 := model.add_state()
	model.add_output("z", 4)
	assert_eq(s0.moore_output.size(), 2)
	assert_eq(s0.transitions[0].output.size(), 2)
	model.set_moore_output(s0.id, 1, 9)
	model.remove_output(0)
	assert_eq(s0.moore_output, [9] as Array[int])
	assert_eq(s0.transitions[1].output, [0] as Array[int])


func test_narrowing_output_clamps_values() -> void:
	var s0 := model.add_state()
	model.set_output_width(0, 3)
	model.set_moore_output(s0.id, 0, 6)
	model.set_output_width(0, 2)
	assert_eq(s0.moore_output[0], 3)


func test_output_width_is_capped() -> void:
	assert_false(model.set_output_width(0, FSMModel.MAX_OUTPUT_WIDTH + 1))
	assert_false(model.add_output("x", 0))


# --- save / load -------------------------------------------------------------

func test_save_and_load_round_trip() -> void:
	var path := "user://test_fsm_round_trip.tres"
	model.set_machine_type(FSMModel.MachineType.MEALY)
	model.add_output("z", 3)
	var s0 := model.add_state()
	var s1 := model.add_state()
	model.rename_state(s1.id, "DONE")
	model.set_next_state(s0.id, 1, s1.id)
	model.set_mealy_output(s0.id, 1, 1, 5)
	model.set_moore_output(s1.id, 0, 1)
	model.set_state_position(s1.id, Vector2(12, 34))
	model.set_initial_state(s1.id)

	assert_eq(model.save_to_file(path), OK)
	var loaded := FSMModel.load_from_file(path)
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_eq(loaded.machine_type, FSMModel.MachineType.MEALY)
	assert_eq(loaded.outputs.size(), 2)
	assert_eq(loaded.outputs[1].name, "z")
	assert_eq(loaded.outputs[1].width, 3)
	assert_eq(loaded.states.size(), 2)
	assert_eq(loaded.initial_state_id, s1.id)
	var l0 := loaded.get_state(s0.id)
	var l1 := loaded.get_state(s1.id)
	assert_eq(l1.name, "DONE")
	assert_eq(l1.position, Vector2(12, 34))
	assert_false(loaded.auto_layout)
	assert_eq(l1.moore_output, [1, 0] as Array[int])
	assert_eq(l0.transitions[1].next_id, s1.id)
	assert_eq(l0.transitions[1].output, [0, 5] as Array[int])
	# ids handed out after loading must not collide with existing ones
	assert_eq(loaded.add_state().id, 2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- loading safety and validation ------------------------------------------

const TEST_FILE := "user://test_fsm_load_checks.tres"


func after_each() -> void:
	if FileAccess.file_exists(TEST_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))


func _write_test_file(text: String) -> void:
	var f := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# Saves a small valid machine and returns the file's text, for tampering with.
func _saved_text() -> String:
	var s0 := model.add_state()
	model.set_next_state(s0.id, 1, s0.id)
	model.save_to_file(TEST_FILE)
	return FileAccess.get_file_as_string(TEST_FILE)


func test_valid_file_loads() -> void:
	_saved_text()
	assert_not_null(FSMModel.load_from_file(TEST_FILE), FSMModel.load_error)
	assert_eq(FSMModel.load_error, "")


func test_rejects_embedded_script() -> void:
	var text := _saved_text()
	text = text.replace("[resource]", """[sub_resource type="GDScript" id="evil"]
script/source = "extends Resource
func _init(): OS.shell_open(\\"https://example.com\\")"

[resource]""")
	_write_test_file(text)
	assert_null(FSMModel.load_from_file(TEST_FILE))
	assert_string_contains(FSMModel.load_error, "embedded GDScript")


func test_rejects_other_scripts() -> void:
	var text := _saved_text().replace("res://scripts/model/fsm_port.gd",
		"res://addons/gut/gut.gd")
	_write_test_file(text)
	assert_null(FSMModel.load_from_file(TEST_FILE))
	assert_string_contains(FSMModel.load_error, "isn't allowed")


func test_rejects_mismatched_uid() -> void:
	# Godot resolves external files by uid before path, so an allowed path
	# with some other script's uid must be refused. (Files we save don't
	# contain uids for scripts, but a crafted one could.)
	var gut_uid := ResourceUID.id_to_text(
		ResourceLoader.get_resource_uid("res://addons/gut/gut.gd"))
	var text := _saved_text().replace(
		'[ext_resource type="Script" path="res://scripts/model/fsm_port.gd"',
		'[ext_resource type="Script" uid="%s" path="res://scripts/model/fsm_port.gd"' % gut_uid)
	assert_true(text.contains(gut_uid), "uid injected")
	_write_test_file(text)
	assert_null(FSMModel.load_from_file(TEST_FILE))
	assert_string_contains(FSMModel.load_error, "doesn't match")


func test_accepts_matching_uid() -> void:
	var port_uid := ResourceUID.id_to_text(
		ResourceLoader.get_resource_uid("res://scripts/model/fsm_port.gd"))
	_write_test_file(_saved_text().replace(
		'[ext_resource type="Script" path="res://scripts/model/fsm_port.gd"',
		'[ext_resource type="Script" uid="%s" path="res://scripts/model/fsm_port.gd"' % port_uid))
	assert_not_null(FSMModel.load_from_file(TEST_FILE), FSMModel.load_error)


func test_rejects_non_fsm_resources() -> void:
	_write_test_file("[gd_resource type=\"Theme\" format=3]\n\n[resource]\n")
	assert_null(FSMModel.load_from_file(TEST_FILE))
	assert_eq(FSMModel.load_error, "This file isn't an FSM.")


func test_rejects_missing_and_wrong_type_files() -> void:
	assert_null(FSMModel.load_from_file("user://does_not_exist.tres"))
	assert_string_contains(FSMModel.load_error, "not found")
	assert_null(FSMModel.load_from_file("user://machine.json"))
	assert_string_contains(FSMModel.load_error, ".tres")


func test_rejects_inconsistent_data() -> void:
	# One state, but only one transition listed where two are needed.
	var text := _saved_text()
	var regex := RegEx.create_from_string(
		"transitions = Array\\[ExtResource\\(\"[^\"]+\"\\)\\]\\(\\[SubResource\\(\"[^\"]+\"\\), ")
	var m := regex.search(text)
	assert_not_null(m, "found the transitions list")
	if m == null:
		return
	_write_test_file(text.replace(m.get_string(), m.get_string().trim_suffix(
		m.get_string().get_slice("[SubResource", 1)).trim_suffix("[SubResource") + "["))
	assert_null(FSMModel.load_from_file(TEST_FILE))
	assert_string_contains(FSMModel.load_error, "wrong number of transitions")


func test_validate() -> void:
	var s0 := model.add_state()
	assert_eq(model.validate(), "")
	s0.transitions[0].next_id = 42
	assert_string_contains(model.validate(), "missing state")
	s0.transitions[0].next_id = FSMTransition.UNSET
	s0.moore_output[0] = 5
	assert_string_contains(model.validate(), "invalid outputs")
	s0.moore_output[0] = 0
	model.inputs[0].name = "out0"
	assert_string_contains(model.validate(), "used twice")
