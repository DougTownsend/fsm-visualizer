## Editor for the machine's input and output ports: add, remove, rename, and
## set each port's bit width, like editing a Verilog module's port list.
##
## Each port is one row: [name] width [n] [×]. Rows are only rebuilt when the
## NUMBER of ports changes. Other changes update the existing widgets in place,
## so a width SpinBox isn't destroyed while you're clicking its arrows.
##
## GODOT CONCEPTS INTRODUCED HERE
## - Building UI in code: `LineEdit.new()`, set properties, `add_child()`.
##   Nodes created this way are identical to ones placed in the editor.
## - Removing nodes: `queue_free()` deletes a node at the end of the current
##   frame (safe even from inside one of its own signals). We also hide() it
##   so it vanishes from the layout immediately.
## - Lambdas: `func(x): ...` written inline creates an anonymous function.
##   It captures the local variables it uses (e.g. the row index `i`), which
##   is how each row's buttons know which port they belong to.
class_name FSMPortEditor
extends VBoxContainer

const WARNING_COLOR := Color(1.0, 0.75, 0.3)
const INFO_COLOR := Color(0.7, 0.7, 0.7)

var model: FSMModel

# One entry per row: {"name": LineEdit, "width": SpinBox}
var _input_rows: Array[Dictionary] = []
var _output_rows: Array[Dictionary] = []

@onready var input_rows_box: VBoxContainer = %InputRows
@onready var output_rows_box: VBoxContainer = %OutputRows
@onready var add_input_button: Button = %AddInputButton
@onready var add_output_button: Button = %AddOutputButton
@onready var input_bits_label: Label = %InputBitsLabel


func _ready() -> void:
	add_input_button.pressed.connect(func() -> void: model.add_input())
	add_output_button.pressed.connect(func() -> void: model.add_output())


func bind(p_model: FSMModel, _simulator: FSMSimulator) -> void:
	if model:
		model.structure_changed.disconnect(_refresh)
	model = p_model
	# A new model means every row must be rebuilt, even if the counts match.
	_clear_rows(_input_rows)
	_clear_rows(_output_rows)
	model.structure_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _input_rows.size() != model.inputs.size():
		_rebuild_rows(true)
	if _output_rows.size() != model.outputs.size():
		_rebuild_rows(false)
	_update_rows(true)
	_update_rows(false)

	var bits := model.total_input_bits()
	input_bits_label.text = "%d of %d input bits used → %d table column(s)" % [
		bits, FSMModel.MAX_INPUT_BITS, model.input_combo_count()]
	var at_cap := bits >= FSMModel.MAX_INPUT_BITS
	input_bits_label.add_theme_color_override("font_color",
		WARNING_COLOR if at_cap else INFO_COLOR)
	add_input_button.disabled = at_cap
	add_input_button.tooltip_text = (
		"Input bits are capped at %d to keep the table readable." % FSMModel.MAX_INPUT_BITS
		if at_cap else "Add an input port")


func _rebuild_rows(is_input: bool) -> void:
	var rows := _input_rows if is_input else _output_rows
	var box := input_rows_box if is_input else output_rows_box
	var ports := model.inputs if is_input else model.outputs
	_clear_rows(rows)
	for i in ports.size():
		var row := HBoxContainer.new()

		var name_edit := LineEdit.new()
		name_edit.custom_minimum_size = Vector2(90, 0)
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.tooltip_text = "Port name (must be unique)"
		# Commit the rename when Enter is pressed or the field loses focus.
		name_edit.text_submitted.connect(
			func(_text: String) -> void: _commit_name(is_input, i, name_edit))
		name_edit.focus_exited.connect(
			func() -> void: _commit_name(is_input, i, name_edit))
		row.add_child(name_edit)

		var width_label := Label.new()
		width_label.text = "bits"
		row.add_child(width_label)

		var width_spin := SpinBox.new()
		width_spin.min_value = 1
		width_spin.rounded = true
		width_spin.value_changed.connect(
			func(v: float) -> void: _commit_width(is_input, i, int(v), width_spin))
		row.add_child(width_spin)

		var remove := Button.new()
		remove.text = "×"
		remove.flat = true
		remove.tooltip_text = "Remove this port"
		remove.pressed.connect(func() -> void:
			if is_input:
				model.remove_input(i)
			else:
				model.remove_output(i))
		row.add_child(remove)

		box.add_child(row)
		rows.append({"row": row, "name": name_edit, "width": width_spin})


## Copies the model's current names/widths into the existing widgets.
func _update_rows(is_input: bool) -> void:
	var rows := _input_rows if is_input else _output_rows
	var ports := model.inputs if is_input else model.outputs
	var spare_bits := FSMModel.MAX_INPUT_BITS - model.total_input_bits()
	for i in ports.size():
		var name_edit: LineEdit = rows[i]["name"]
		var width_spin: SpinBox = rows[i]["width"]
		if not name_edit.has_focus():  # don't overwrite what's being typed
			name_edit.text = ports[i].name
		# An input can grow by however many bits are still unused.
		width_spin.max_value = (ports[i].width + spare_bits if is_input
			else FSMModel.MAX_OUTPUT_WIDTH)
		width_spin.set_value_no_signal(ports[i].width)


func _commit_name(is_input: bool, index: int, name_edit: LineEdit) -> void:
	var ports := model.inputs if is_input else model.outputs
	if index >= ports.size() or name_edit.text == ports[index].name:
		return
	var ok := (model.rename_input(index, name_edit.text) if is_input
		else model.rename_output(index, name_edit.text))
	if not ok:
		FSMUi.flash_error(name_edit)
	name_edit.text = ports[index].name


func _commit_width(is_input: bool, index: int, width: int, spin: SpinBox) -> void:
	var ok := (model.set_input_width(index, width) if is_input
		else model.set_output_width(index, width))
	if not ok:
		var ports := model.inputs if is_input else model.outputs
		spin.set_value_no_signal(ports[index].width)
		FSMUi.flash_error(spin)


func _clear_rows(rows: Array[Dictionary]) -> void:
	for r in rows:
		r["row"].hide()
		r["row"].queue_free()
	rows.clear()
