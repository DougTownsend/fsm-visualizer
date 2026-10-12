# UI tests for the port editor (scenes/port_editor.tscn).
extends GutTest

var model: FSMModel
var editor: FSMPortEditor


func before_each() -> void:
	model = FSMModel.create_default()
	editor = add_child_autofree(load("res://scenes/port_editor.tscn").instantiate())
	editor.bind(model, FSMSimulator.new(model))


func test_shows_one_row_per_port() -> void:
	assert_eq(editor._input_rows.size(), 1)
	assert_eq(editor._output_rows.size(), 1)
	assert_eq(editor._input_rows[0]["name"].text, "in0")


func test_add_buttons() -> void:
	editor.add_input_button.pressed.emit()
	editor.add_output_button.pressed.emit()
	assert_eq(model.inputs.size(), 2)
	assert_eq(model.outputs.size(), 2)
	assert_eq(editor._input_rows.size(), 2)
	assert_eq(editor._output_rows[1]["name"].text, "out1")


func test_width_spin_changes_model_without_rebuilding_row() -> void:
	var spin: SpinBox = editor._input_rows[0]["width"]
	spin.value = 3
	assert_eq(model.inputs[0].width, 3)
	assert_eq(editor._input_rows[0]["width"], spin, "same widget, not rebuilt")


func test_input_width_spin_limited_by_bit_cap() -> void:
	model.add_input("b", 2)
	var spin: SpinBox = editor._input_rows[0]["width"]
	assert_eq(spin.max_value, float(FSMModel.MAX_INPUT_BITS - 2))


func test_add_input_disabled_at_cap() -> void:
	model.set_input_width(0, FSMModel.MAX_INPUT_BITS)
	assert_true(editor.add_input_button.disabled)
	model.set_input_width(0, 1)
	assert_false(editor.add_input_button.disabled)


func test_rename_rejects_duplicates() -> void:
	var edit: LineEdit = editor._output_rows[0]["name"]
	edit.text = "in0"
	edit.text_submitted.emit("in0")
	assert_eq(model.outputs[0].name, "out0")
	assert_eq(edit.text, "out0")
	edit.text = "z"
	edit.text_submitted.emit("z")
	assert_eq(model.outputs[0].name, "z")


func test_remove_button() -> void:
	model.add_input("b", 1)
	var row: HBoxContainer = editor._input_rows[0]["row"]
	(row.get_child(3) as Button).pressed.emit()
	assert_eq(model.inputs.size(), 1)
	assert_eq(model.inputs[0].name, "b")
	assert_eq(editor._input_rows[0]["name"].text, "b")
