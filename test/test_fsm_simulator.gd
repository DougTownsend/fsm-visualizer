# Unit tests for FSMSimulator (scripts/model/fsm_simulator.gd), using the
# classic "11" sequence detector: output 1 once the input has been 1 for two
# consecutive clock ticks.
extends GutTest

var model: FSMModel
var sim: FSMSimulator


func before_each() -> void:
	model = FSMModel.create_default()


# Moore version: S0 = seen nothing, S1 = seen one 1, S2 = seen two+ 1s (out=1).
func _build_moore_detector() -> Array[FSMState]:
	var s0 := model.add_state()
	var s1 := model.add_state()
	var s2 := model.add_state()
	for s in [s0, s1, s2]:
		model.set_next_state(s.id, 0, s0.id)
	model.set_next_state(s0.id, 1, s1.id)
	model.set_next_state(s1.id, 1, s2.id)
	model.set_next_state(s2.id, 1, s2.id)
	model.set_moore_output(s2.id, 0, 1)
	sim = FSMSimulator.new(model)
	return [s0, s1, s2]


# Mealy version: S0 = last input 0, S1 = last input 1; output 1 on 1 in S1.
func _build_mealy_detector() -> Array[FSMState]:
	model.set_machine_type(FSMModel.MachineType.MEALY)
	var s0 := model.add_state()
	var s1 := model.add_state()
	for s in [s0, s1]:
		model.set_next_state(s.id, 0, s0.id)
		model.set_next_state(s.id, 1, s1.id)
	model.set_mealy_output(s1.id, 1, 0, 1)
	sim = FSMSimulator.new(model)
	return [s0, s1]


# Applies each input, records the output *before* the clock edge, then clocks.
func _run(inputs: Array[int]) -> Array[int]:
	var outs: Array[int] = []
	for value in inputs:
		sim.set_input(0, value)
		outs.append(sim.current_output()[0])
		assert_true(sim.clock(), sim.last_error)
	return outs


func test_starts_in_initial_state() -> void:
	var s := _build_moore_detector()
	assert_eq(sim.current_state_id, s[0].id)
	assert_eq(sim.cycle, 0)


func test_moore_detector_sequence() -> void:
	_build_moore_detector()
	assert_eq(_run([1, 1, 1, 0, 1, 1] as Array[int]), [0, 0, 1, 1, 0, 0] as Array[int])


func test_mealy_detector_sequence() -> void:
	_build_mealy_detector()
	assert_eq(_run([1, 1, 1, 0, 1, 1] as Array[int]), [0, 1, 1, 0, 0, 1] as Array[int])


func test_next_state_follows_current_input() -> void:
	var s := _build_moore_detector()
	sim.set_input(0, 0)
	assert_eq(sim.next_state_id(), s[0].id)
	sim.set_input(0, 1)
	assert_eq(sim.next_state_id(), s[1].id)
	assert_eq(sim.current_combo(), 1)


func test_history_records_each_tick() -> void:
	_build_moore_detector()
	_run([1, 1] as Array[int])
	assert_eq(sim.history.size(), 2)
	assert_eq(sim.history[1], {
		"cycle": 1, "state": "S1", "input": "1", "output": "0", "next": "S2",
	})
	assert_eq(sim.cycle, 2)


func test_reset_returns_to_initial_and_clears_history() -> void:
	var s := _build_moore_detector()
	_run([1, 1] as Array[int])
	sim.reset()
	assert_eq(sim.current_state_id, s[0].id)
	assert_eq(sim.cycle, 0)
	assert_eq(sim.history.size(), 0)
	assert_eq(sim.input_values, [1] as Array[int], "reset keeps the inputs")


func test_clock_fails_on_unset_transition() -> void:
	model.add_state()
	sim = FSMSimulator.new(model)
	assert_false(sim.clock())
	assert_string_contains(sim.last_error, "no next state")
	assert_eq(sim.cycle, 0)


func test_clock_fails_without_states() -> void:
	sim = FSMSimulator.new(model)
	assert_false(sim.clock())
	assert_eq(sim.current_output(), [] as Array[int])


func test_current_follows_initial_until_first_clock() -> void:
	var s := _build_moore_detector()
	model.set_initial_state(s[2].id)
	assert_eq(sim.current_state_id, s[2].id)
	model.set_initial_state(s[0].id)
	sim.set_input(0, 1)
	sim.clock()
	model.set_initial_state(s[2].id)
	assert_eq(sim.current_state_id, s[1].id, "after clocking, initial changes don't move us")


func test_first_state_added_becomes_current() -> void:
	sim = FSMSimulator.new(model)
	var s0 := model.add_state()
	assert_eq(sim.current_state_id, s0.id)


func test_removing_current_state_falls_back_to_initial() -> void:
	var s := _build_moore_detector()
	_run([1] as Array[int])
	assert_eq(sim.current_state_id, s[1].id)
	model.remove_state(s[1].id)
	assert_eq(sim.current_state_id, s[0].id)


func test_inputs_follow_port_changes() -> void:
	_build_moore_detector()
	model.set_input_width(0, 2)
	sim.set_input(0, 7)
	assert_eq(sim.input_values, [3] as Array[int], "clamped to 2 bits")
	model.add_input("b", 1)
	assert_eq(sim.input_values.size(), 2)
	model.set_input_width(0, 1)
	assert_eq(sim.input_values[0], 1, "re-clamped when the port narrows")


func test_updated_signal() -> void:
	_build_moore_detector()
	watch_signals(sim)
	sim.set_input(0, 1)
	sim.clock()
	sim.reset()
	assert_signal_emit_count(sim, "updated", 3)


func test_model_edits_emit_updated() -> void:
	var s := _build_moore_detector()
	watch_signals(sim)
	model.set_next_state(s[0].id, 0, s[1].id)
	model.set_moore_output(s[0].id, 0, 1)
	model.rename_state(s[0].id, "IDLE")
	assert_signal_emit_count(sim, "updated", 3)
