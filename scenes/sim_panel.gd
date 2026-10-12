## Simulation controls along the bottom of the window:
##
##   Inputs            | State / next / outputs    | History
##   in0   [1]         | Cycle 2 · State: S1       | Cycle State Input Output Next
##   mode  [01 ^v]     | Next on clock: FOUND      |   0    S0    1     0     S1
##                     | Outputs: out0 = 0         |   1    S1    1     0     FOUND
##                     | [Clock (C)] [Reset (R)]   |
##
## Changing an input only changes which transition is ACTIVE (the views
## highlight it straight away); the state changes when you press Clock, like
## a real synchronous circuit.
##
## GODOT CONCEPTS INTRODUCED HERE
## - Shortcuts: a Button's `shortcut` property makes a key press act like a
##   click. Shortcuts only fire if the key wasn't used by the control that has
##   keyboard focus, so typing "c" into a name field doesn't clock the machine.
## - Tree: a table/outline control. With `hide_root` and column titles it works
##   as a simple multi-column list. Rows are TreeItems made with create_item().
class_name FSMSimPanel
extends VBoxContainer

## Columns of the history list, and the simulator.history key each shows.
const HISTORY_COLUMNS := [
	["Cycle", "cycle"], ["State", "state"], ["Input", "input"],
	["Output", "output"], ["Next", "next"],
]
const ERROR_COLOR := Color(1.0, 0.65, 0.3)

var model: FSMModel
var simulator: FSMSimulator

## One value editor per input port, same order as model.inputs.
var _input_editors: Array[Control] = []
## How many history entries are already in the Tree.
var _history_shown := 0

@onready var input_rows: VBoxContainer = %InputRows
@onready var state_label: Label = %StateLabel
@onready var next_label: Label = %NextLabel
@onready var output_label: Label = %OutputLabel
@onready var clock_button: Button = %ClockButton
@onready var reset_button: Button = %ResetButton
@onready var error_label: Label = %ErrorLabel
@onready var history: Tree = %History


func _ready() -> void:
	clock_button.pressed.connect(func() -> void: simulator.clock())
	reset_button.pressed.connect(func() -> void: simulator.reset())
	clock_button.shortcut = _key_shortcut(KEY_C)
	reset_button.shortcut = _key_shortcut(KEY_R)
	error_label.add_theme_color_override("font_color", ERROR_COLOR)

	history.columns = HISTORY_COLUMNS.size()
	history.column_titles_visible = true
	history.hide_root = true
	for i in HISTORY_COLUMNS.size():
		history.set_column_title(i, HISTORY_COLUMNS[i][0])
		history.set_column_expand(i, i != 0)  # "Cycle" stays narrow


func bind(p_model: FSMModel, p_simulator: FSMSimulator) -> void:
	if simulator:
		simulator.updated.disconnect(_refresh)
		model.structure_changed.disconnect(_rebuild_inputs)
	model = p_model
	simulator = p_simulator
	# The simulator connected to structure_changed before we did (main.gd
	# creates it first), so by the time _rebuild_inputs runs the simulator
	# has already resized its input_values to match the new ports.
	model.structure_changed.connect(_rebuild_inputs)
	simulator.updated.connect(_refresh)
	_clear_history()
	_rebuild_inputs()
	_refresh()


## One row per input port: its name and a toggle (1 bit) or spin box.
func _rebuild_inputs() -> void:
	for child in input_rows.get_children():
		child.hide()
		child.queue_free()
	_input_editors.clear()
	if model.inputs.is_empty():
		var none := Label.new()
		none.text = "(no inputs)"
		input_rows.add_child(none)
		return
	for i in model.inputs.size():
		var port := model.inputs[i]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = port.name if port.width == 1 else "%s [%d:0]" % [port.name, port.width - 1]
		label.custom_minimum_size = Vector2(90, 0)
		row.add_child(label)
		var editor := FSMUi.value_editor(port.width, simulator.input_values[i],
			func(v: int) -> void: simulator.set_input(i, v))
		editor.tooltip_text = "Input value. Changing it shows which transition the next clock takes."
		row.add_child(editor)
		input_rows.add_child(row)
		_input_editors.append(editor)


## Copies the simulator's state into the labels, editors and history.
func _refresh() -> void:
	# Input editors may briefly be out of date while ports are changing (see
	# the note in bind()), so only touch the ones that match.
	for i in mini(_input_editors.size(), simulator.input_values.size()):
		FSMUi.set_editor_value(_input_editors[i], simulator.input_values[i])

	var s := simulator.current_state()
	clock_button.disabled = s == null
	if s == null:
		state_label.text = "State: —"
		next_label.text = "Add a state to start simulating."
		output_label.text = ""
	else:
		state_label.text = "Cycle %d · State: %s" % [simulator.cycle, s.name]
		var next_id := simulator.next_state_id()
		next_label.text = "Next on clock: %s" % (
			model.state_name(next_id) if next_id != FSMTransition.UNSET else "— (unset)")
		output_label.text = "Outputs: " + _outputs_text()

	error_label.text = simulator.last_error
	error_label.visible = not simulator.last_error.is_empty()
	_update_history()


## e.g. "out0 = 1, count = 101"
func _outputs_text() -> String:
	if model.outputs.is_empty():
		return "(none)"
	var values := simulator.current_output()
	var parts: PackedStringArray = []
	for i in model.outputs.size():
		parts.append("%s = %s" % [model.outputs[i].name,
			FSMModel.format_value(values[i], model.outputs[i].width)])
	return ", ".join(parts)


## Adds rows for new history entries (or starts over after a Reset).
func _update_history() -> void:
	if simulator.history.size() < _history_shown:
		_clear_history()
	var last: TreeItem = null
	for i in range(_history_shown, simulator.history.size()):
		var entry := simulator.history[i]
		last = history.create_item(history.get_root())
		for column in HISTORY_COLUMNS.size():
			last.set_text(column, str(entry[HISTORY_COLUMNS[column][1]]))
	_history_shown = simulator.history.size()
	if last:
		history.scroll_to_item(last)


func _clear_history() -> void:
	history.clear()
	history.create_item()  # the (hidden) root item that rows hang off
	_history_shown = 0


static func _key_shortcut(key: Key) -> Shortcut:
	var event := InputEventKey.new()
	event.keycode = key
	var shortcut := Shortcut.new()
	shortcut.events = [event]
	return shortcut
