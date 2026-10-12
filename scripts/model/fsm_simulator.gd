## Runs an FSMModel one clock tick at a time.
##
## Holds the simulation state that is NOT part of the machine definition: the
## current state, the input values currently applied, and a history of ticks.
## The views read from it to decide what to highlight.
##
## GODOT CONCEPTS INTRODUCED HERE
## - `extends RefCounted`: a plain object that frees itself automatically once
##   nothing references it any more. Use it for data/logic that doesn't need
##   to be saved to disk (a Resource) or to live in the scene tree (a Node).
## - Connecting to another object's signals in code, with `signal.connect()`.
class_name FSMSimulator
extends RefCounted

## Emitted whenever anything the views might highlight changed: current state,
## inputs, history, or the machine structure the simulator depends on.
signal updated

var model: FSMModel
## id of the state the machine is in now, or -1 if it has no states.
var current_state_id: int = -1
## The value applied to each input port, same order as model.inputs.
var input_values: Array[int] = []
## Number of clock ticks since the last reset.
var cycle: int = 0
## One entry per tick: {cycle, state, input, output, next}; names and labels
## are captured as text at the time of the tick.
var history: Array[Dictionary] = []
## Why the last clock() failed, or "" if it succeeded.
var last_error: String = ""


func _init(p_model: FSMModel) -> void:
	model = p_model
	# When the machine is edited, the simulator may need to adjust.
	model.structure_changed.connect(_on_structure_changed)
	model.initial_state_changed.connect(_on_initial_state_changed)
	# Edits to a transition, an output or a name don't change the simulation
	# state, but they do change what "next state" and "current output" mean
	# (or how they're displayed), so tell the views to refresh.
	model.transition_changed.connect(_on_model_edited)
	model.moore_output_changed.connect(_on_model_edited)
	model.state_renamed.connect(_on_model_edited)
	_sync_inputs()
	reset()


## Returns to the initial state and clears the history. Inputs are kept.
func reset() -> void:
	current_state_id = model.initial_state_id
	cycle = 0
	history.clear()
	last_error = ""
	updated.emit()


## Sets the value applied to one input port (clamped to its width).
func set_input(port: int, value: int) -> void:
	if port < 0 or port >= input_values.size():
		return
	input_values[port] = clampi(value, 0, model.inputs[port].max_value())
	updated.emit()


## The current input combination, i.e. which table column is active.
func current_combo() -> int:
	return model.values_to_combo(input_values)


func current_state() -> FSMState:
	return model.get_state(current_state_id)


## The table cell that is active right now (current state + current input),
## or null if there is no current state.
func current_transition() -> FSMTransition:
	var s := current_state()
	if s == null:
		return null
	return s.transitions[current_combo()]


## The state the next clock tick will move to, or FSMTransition.UNSET.
func next_state_id() -> int:
	var t := current_transition()
	return t.next_id if t else FSMTransition.UNSET


## The outputs being driven right now: from the state (Moore) or from the
## active table cell (Mealy). Empty if there is no current state.
func current_output() -> Array[int]:
	var s := current_state()
	if s == null:
		return []
	if model.machine_type == FSMModel.MachineType.MOORE:
		return s.moore_output.duplicate()
	return current_transition().output.duplicate()


## One clock edge: record this cycle in the history and move to the next
## state. Returns false (and sets last_error) if the move isn't possible.
func clock() -> bool:
	last_error = ""
	var s := current_state()
	if s == null:
		last_error = "There is no current state. Add a state first."
		updated.emit()
		return false
	var next_id := next_state_id()
	if next_id == FSMTransition.UNSET:
		last_error = "State %s has no next state for input %s." % [
			s.name, model.combo_label(current_combo())]
		updated.emit()
		return false
	history.append({
		"cycle": cycle,
		"state": s.name,
		"input": model.combo_label(current_combo()),
		"output": model.output_label(current_output()),
		"next": model.state_name(next_id),
	})
	current_state_id = next_id
	cycle += 1
	updated.emit()
	return true


# Keep one input value per input port, each within its port's width.
func _sync_inputs() -> void:
	input_values.resize(model.inputs.size())
	for i in input_values.size():
		input_values[i] = clampi(input_values[i], 0, model.inputs[i].max_value())


func _on_structure_changed() -> void:
	_sync_inputs()
	# If the current state was deleted (or there wasn't one yet), fall back
	# to the initial state.
	if current_state() == null:
		current_state_id = model.initial_state_id
	updated.emit()


# Signals pass 1 or 2 arguments; default values let one handler take both.
func _on_model_edited(_a: Variant = null, _b: Variant = null) -> void:
	updated.emit()


func _on_initial_state_changed() -> void:
	# Before the first clock tick, "current" simply follows the initial state,
	# so the highlight moves when the user picks a different initial state.
	if cycle == 0:
		current_state_id = model.initial_state_id
		updated.emit()
