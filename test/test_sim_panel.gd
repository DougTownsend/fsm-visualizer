# UI tests for the simulation panel (scenes/sim_panel.tscn), using the Moore
# "11" detector.
extends GutTest

var model: FSMModel
var sim: FSMSimulator
var panel: FSMSimPanel
var states: Array[FSMState] = []


func before_each() -> void:
	model = FSMModel.create_default()
	states.clear()
	for i in 3:
		states.append(model.add_state())
	for s in states:
		model.set_next_state(s.id, 0, states[0].id)
	model.set_next_state(states[0].id, 1, states[1].id)
	model.set_next_state(states[1].id, 1, states[2].id)
	model.set_next_state(states[2].id, 1, states[2].id)
	model.set_moore_output(states[2].id, 0, 1)
	sim = FSMSimulator.new(model)
	panel = add_child_autofree(load("res://scenes/sim_panel.tscn").instantiate())
	panel.bind(model, sim)


func _history_rows() -> int:
	return panel.history.get_root().get_child_count()


func test_shows_current_state_next_and_outputs() -> void:
	assert_eq(panel.state_label.text, "Cycle 0 · State: S0")
	assert_eq(panel.next_label.text, "Next on clock: S0")
	assert_eq(panel.output_label.text, "Outputs: out0 = 0")


func test_input_toggle_sets_simulator_input() -> void:
	var toggle: FSMBitToggle = panel._input_editors[0]
	toggle.pressed.emit()
	assert_eq(sim.input_values, [1] as Array[int])
	assert_eq(panel.next_label.text, "Next on clock: S1")


func test_clock_and_history() -> void:
	sim.set_input(0, 1)
	panel.clock_button.pressed.emit()
	panel.clock_button.pressed.emit()
	assert_eq(sim.current_state_id, states[2].id)
	assert_eq(panel.state_label.text, "Cycle 2 · State: S2")
	assert_eq(panel.output_label.text, "Outputs: out0 = 1")
	assert_eq(_history_rows(), 2)
	var row := panel.history.get_root().get_child(1)
	assert_eq([row.get_text(0), row.get_text(1), row.get_text(2), row.get_text(3),
		row.get_text(4)], ["1", "S1", "1", "0", "S2"])


func test_reset_clears_history() -> void:
	sim.set_input(0, 1)
	panel.clock_button.pressed.emit()
	panel.reset_button.pressed.emit()
	assert_eq(sim.current_state_id, states[0].id)
	assert_eq(_history_rows(), 0)
	panel.clock_button.pressed.emit()
	assert_eq(_history_rows(), 1, "history starts again after a reset")


func test_error_shown_for_unset_transition() -> void:
	model.set_next_state(states[0].id, 0, FSMTransition.UNSET)
	assert_eq(panel.next_label.text, "Next on clock: — (unset)")
	assert_false(panel.error_label.visible)
	panel.clock_button.pressed.emit()
	assert_true(panel.error_label.visible)
	assert_string_contains(panel.error_label.text, "no next state")


func test_inputs_follow_ports() -> void:
	model.add_input("mode", 2)
	assert_eq(panel._input_editors.size(), 2)
	assert_is(panel._input_editors[1], FSMValueSpin)
	(panel._input_editors[1] as FSMValueSpin).value = 3
	assert_eq(sim.input_values, [0, 3] as Array[int])


func test_clock_disabled_without_states() -> void:
	for s in states:
		model.remove_state(s.id)
	assert_true(panel.clock_button.disabled)


func test_keyboard_shortcuts_are_set() -> void:
	assert_not_null(panel.clock_button.shortcut)
	assert_not_null(panel.reset_button.shortcut)
