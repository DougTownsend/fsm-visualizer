# UI tests for the transition table (scenes/transition_table.tscn).
#
# These instance the real scene, add it to the running scene tree (so _ready
# runs and @onready variables are filled), then poke its widgets the way a
# user would, by emitting the signals a click would emit, and check the
# model. add_child_autofree() frees the scene again after each test.
extends GutTest

var model: FSMModel
var table: FSMTransitionTable


func before_each() -> void:
	model = FSMModel.create_default()
	table = add_child_autofree(load("res://scenes/transition_table.tscn").instantiate())
	table.bind(model, FSMSimulator.new(model))


# Cells that are really part of the table (rebuilt-away ones are hidden and
# waiting to be freed at the end of the frame).
func _live_cells() -> Array[Node]:
	return table.grid.get_children().filter(
		func(c: Node) -> bool: return c.visible and not c.is_queued_for_deletion())


# The widget inside the cell at [row][column] (row 0 = header).
func _widget(row: int, column: int) -> Control:
	return table._cells[row][column].get_child(0)


func test_starts_empty() -> void:
	assert_true(table.empty_label.visible)
	assert_false(table.grid.visible)


func test_moore_layout() -> void:
	model.add_state()
	model.add_state()
	# Init, State, ×, 2 input columns, 1 output column
	assert_eq(table.grid.columns, 6)
	assert_eq(_live_cells().size(), 6 * 3, "header + 2 state rows")
	assert_is(_widget(1, 3), OptionButton)
	assert_is(_widget(1, 5), FSMBitToggle)


func test_mealy_layout() -> void:
	model.add_state()
	model.set_machine_type(FSMModel.MachineType.MEALY)
	assert_eq(table.grid.columns, 5, "no separate output column")
	var cell := _widget(1, 3)
	assert_is(cell, HBoxContainer)
	assert_is(cell.get_child(0), OptionButton)
	assert_eq((cell.get_child(1) as Label).text, "/")
	assert_is(cell.get_child(2), FSMBitToggle)


func test_columns_follow_inputs() -> void:
	model.add_state()
	model.add_input("b", 1)
	assert_eq(table.grid.columns, 3 + 4 + 1)
	assert_eq((_widget(0, 3 + 2) as Label).text, "1 0")


func test_picking_next_state_updates_model() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	var picker: OptionButton = _widget(1, 4)  # S0, input 1
	picker.select(2)  # item 0 is "—", item 2 is S1
	picker.item_selected.emit(2)
	assert_eq(s0.transitions[1].next_id, s1.id)
	picker.select(0)
	picker.item_selected.emit(0)
	assert_eq(s0.transitions[1].next_id, FSMTransition.UNSET)


func test_rename_updates_dropdowns_without_rebuild() -> void:
	model.add_state()
	var s1 := model.add_state()
	var cells_before := table._cells.duplicate()
	model.rename_state(s1.id, "BUSY")
	assert_eq(table._cells, cells_before, "table was not rebuilt")
	assert_eq(table._name_edits[s1.id].text, "BUSY")
	for picker in table._next_pickers:
		assert_eq(picker.get_item_text(2), "BUSY")


func test_rename_via_name_field() -> void:
	var s0 := model.add_state()
	model.add_state()
	var edit: LineEdit = table._name_edits[s0.id]
	edit.text = "IDLE"
	edit.text_submitted.emit("IDLE")
	assert_eq(s0.name, "IDLE")
	edit.text = "S1"  # duplicate: rejected and reverted
	edit.text_submitted.emit("S1")
	assert_eq(s0.name, "IDLE")
	assert_eq(edit.text, "IDLE")


func test_initial_checkbox() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	assert_true(table._initial_checks[s0.id].button_pressed)
	table._initial_checks[s1.id].button_pressed = true
	assert_eq(model.initial_state_id, s1.id)
	assert_false(table._initial_checks[s0.id].button_pressed, "radio behaviour")


func test_delete_button_removes_state() -> void:
	model.add_state()
	var s1 := model.add_state()
	(_widget(2, 2) as Button).pressed.emit()
	assert_eq(model.states.size(), 1)
	assert_null(model.get_state(s1.id))
	assert_eq(_live_cells().size(), 6 * 2)


func test_moore_output_toggle() -> void:
	var s0 := model.add_state()
	var toggle: FSMBitToggle = _widget(1, 5)
	toggle.pressed.emit()
	assert_eq(s0.moore_output[0], 1)
	assert_eq(toggle.text, "1")


func test_mealy_multibit_output_spin() -> void:
	var s0 := model.add_state()
	model.set_output_width(0, 3)
	model.set_machine_type(FSMModel.MachineType.MEALY)
	var spin: FSMValueSpin = _widget(1, 4).get_child(2)
	assert_eq(spin.max_value, 7.0)
	spin.value = 5
	assert_eq(s0.transitions[1].output[0], 5)


# Edits made directly on the model (not through the table's widgets) must
# show up in the existing widgets, without a rebuild.
func test_external_next_state_edit_updates_dropdown() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	var picker: OptionButton = _widget(1, 4)
	model.set_next_state(s0.id, 1, s1.id)
	assert_eq(_widget(1, 4), picker, "not rebuilt")
	assert_eq(picker.selected, 2)
	assert_eq(picker.get_item_text(picker.selected), "S1")


func test_external_output_edits_update_editors() -> void:
	var s0 := model.add_state()
	model.set_moore_output(s0.id, 0, 1)
	assert_eq((_widget(1, 5) as FSMBitToggle).value, 1)
	model.set_output_width(0, 3)
	model.set_machine_type(FSMModel.MachineType.MEALY)
	model.set_mealy_output(s0.id, 0, 0, 6)
	assert_eq((_widget(1, 3).get_child(2) as FSMValueSpin).value, 6.0)


# --- simulation highlighting -------------------------------------------------

func _style(row: int, column: int) -> StyleBox:
	return (table._cells[row][column] as PanelContainer).get_theme_stylebox("panel")


func test_highlights_current_row_column_and_intersection() -> void:
	model.add_state()
	model.add_state()
	var sim := table.simulator
	sim.set_input(0, 1)
	# current state S0 = row 1, input 1 = column 4
	assert_eq(_style(1, 4), table._intersection_style)
	assert_eq(_style(1, 1), table._row_column_style, "rest of the row")
	assert_eq(_style(0, 4), table._row_column_style, "column header")
	assert_eq(_style(2, 4), table._row_column_style, "rest of the column")
	assert_eq(_style(2, 3), table._normal_style)
	sim.set_input(0, 0)
	assert_eq(_style(1, 4), table._row_column_style, "old intersection now just row")
	assert_eq(_style(2, 4), table._normal_style, "old column cleared")
	assert_eq(_style(1, 3), table._intersection_style)


func test_highlight_follows_clock() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	model.set_next_state(s0.id, 0, s1.id)
	table.simulator.clock()
	assert_eq(_style(2, 3), table._intersection_style)
	assert_eq(_style(1, 1), table._normal_style)


func test_highlight_survives_structure_changes() -> void:
	model.add_state()
	table.simulator.set_input(0, 1)
	model.add_input("b", 1)  # columns change; highlight must be re-applied
	# input values {in0, b} = {1, 0} -> combo 0b10 = column 3 + 2
	assert_eq(_style(1, 5), table._intersection_style)


# --- copy table --------------------------------------------------------------
# The image itself needs a real renderer (tests run headless), so these check
# the plain table it's drawn from.

# The text of every cell in the plain table, row by row.
func _plain_texts(plain: Control) -> PackedStringArray:
	var grid: GridContainer = plain.find_children("*", "GridContainer", true, false)[0]
	var texts: PackedStringArray = []
	for cell in grid.get_children():
		texts.append((cell.get_child(0) as Label).text)
	plain.free()
	return texts


func test_copy_button_disabled_without_states() -> void:
	assert_true(table.copy_button.disabled)
	model.add_state()
	assert_false(table.copy_button.disabled)


func test_copy_with_no_states_reports_failure() -> void:
	watch_signals(table)
	await table.copy_to_clipboard()
	assert_signal_emitted(table, "copy_failed")


func test_plain_moore_table() -> void:
	var s0 := model.add_state()
	var s1 := model.add_state()
	model.set_next_state(s0.id, 1, s1.id)
	model.set_moore_output(s1.id, 0, 1)
	assert_eq(_plain_texts(table.build_plain_table()), PackedStringArray([
		"State", "in0 = 0", "in0 = 1", "out0",
		"→ S0", "—", "S1", "0",
		"S1", "—", "—", "1",
	]))


func test_plain_mealy_table_shows_outputs_in_cells() -> void:
	model.set_machine_type(FSMModel.MachineType.MEALY)
	var s0 := model.add_state()
	model.set_next_state(s0.id, 0, s0.id)
	model.set_mealy_output(s0.id, 1, 0, 1)
	assert_eq(_plain_texts(table.build_plain_table()), PackedStringArray([
		"State", "in0 = 0\nnext / out0", "in0 = 1\nnext / out0",
		"→ S0", "S0 / 0", "— / 1",
	]))


func test_plain_header_names_every_input() -> void:
	model.add_input("mode", 2)
	model.add_state()
	var texts := _plain_texts(table.build_plain_table())
	assert_eq(texts[1], "in0 = 0\nmode = 00")
	assert_eq(texts[8], "in0 = 1\nmode = 11")
