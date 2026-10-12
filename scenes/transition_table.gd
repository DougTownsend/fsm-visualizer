## The state transition table: the main editing surface of the app.
##
## Layout (a GridContainer, filled left-to-right, top-to-bottom):
##
##   Moore:  Init | State | × | <input 0> | <input 1> | ... | out0 | out1 ...
##           (o)  | [S0 ] | × | [S1 v]    | [S0 v]    | ... | [0]  | [01]
##
##   Mealy:  Init | State | × | <input 0>          | <input 1>          ...
##           (o)  | [S0 ] | × | [S1 v] / [0] [01]  | [S0 v] / [1] [00]  ...
##
## One column per input combination (see FSMModel.combo_to_values). Each
## "next state" is a dropdown (OptionButton) listing all states; outputs use
## FSMBitToggle (1 bit) or FSMValueSpin (multi-bit).
##
## WHEN THE TABLE REBUILDS
## Only on the model's `structure_changed` signal (states added/removed, ports
## or machine type changed). Smaller changes (a rename, one cell, one output)
## are applied to the existing widgets in place, so the name field you're
## typing in or the SpinBox you're clicking isn't destroyed under you. The
## in-place updates also make the table correct when something other than the
## table edits the model (a script, a test, or later the graph view).
##
## GODOT CONCEPTS INTRODUCED HERE
## - GridContainer: lays children out in a grid with a fixed column count.
## - PanelContainer + StyleBoxFlat: a container that draws a background box
##   behind its child. Every cell is wrapped in one, so highlighting a cell
##   is just a matter of giving its panel a different StyleBox.
##
## SIMULATION HIGHLIGHTING
## The current state's row and the current input's column are tinted blue;
## the cell where they cross (the transition the next clock will take) is
## orange. It follows the simulator's `updated` signal.
##
## COPY TABLE
## The widgets don't make a good picture, so "Copy table" builds a separate,
## static version (text in a bordered grid, black on white, no Init/delete
## columns, no highlighting), draws it offscreen and copies it as a PNG.
## - ButtonGroup: makes a set of CheckBoxes behave like radio buttons.
## - Item metadata: OptionButton items can carry an arbitrary value
##   (set_item_metadata); we store each state's id there.
class_name FSMTransitionTable
extends VBoxContainer

const UNSET_TEXT := "—"
const ROW_COLUMN_COLOR := Color(0.25, 0.45, 0.85, 0.3)
const INTERSECTION_COLOR := Color(0.95, 0.6, 0.15, 0.6)
## Marks the initial state in the copied table.
const INITIAL_MARK := "→ "
## White space around the copied table, in pixels.
const PLAIN_PADDING := 16

## Emitted when "Copy table" fails, with a message for the user.
signal copy_failed(message: String)

var model: FSMModel
var simulator: FSMSimulator

## Background style shared by all cells when not highlighted.
var _normal_style := _make_cell_style(Color(0, 0, 0, 0))
var _row_column_style := _make_cell_style(ROW_COLUMN_COLOR)
var _intersection_style := _make_cell_style(INTERSECTION_COLOR)
## Cells currently given a highlight style, so they can be un-highlighted.
var _highlighted: Array[PanelContainer] = []
## Makes the "Init" CheckBoxes mutually exclusive. Recreated on each rebuild.
var _initial_group: ButtonGroup
## Widgets kept so small changes can be applied without rebuilding.
var _name_edits: Dictionary[int, LineEdit] = {}  # state id -> name field
var _initial_checks: Dictionary[int, CheckBox] = {}  # state id -> Init box
var _next_pickers: Array[OptionButton] = []  # every next-state dropdown
## state id -> [one OptionButton per input combo]
var _pickers_by_state: Dictionary[int, Array] = {}
## state id -> [per input combo: [one value editor per output port]] (Mealy)
var _mealy_editors: Dictionary[int, Array] = {}
## state id -> [one value editor per output port] (Moore)
var _moore_editors: Dictionary[int, Array] = {}
## Every cell's PanelContainer: _cells[row][column], row 0 = header row,
## row r + 1 = model.states[r]. Column 3 + combo = that input's column.
var _cells: Array[Array] = []

@onready var caption: Label = %Caption
@onready var empty_label: Label = %EmptyLabel
@onready var grid: GridContainer = %Grid
@onready var add_state_button: Button = %AddStateButton
@onready var copy_button: Button = %CopyButton


func _ready() -> void:
	add_state_button.pressed.connect(func() -> void: model.add_state())
	copy_button.pressed.connect(copy_to_clipboard)


func bind(p_model: FSMModel, p_simulator: FSMSimulator) -> void:
	if model:
		model.structure_changed.disconnect(_rebuild)
		model.state_renamed.disconnect(_on_state_renamed)
		model.initial_state_changed.disconnect(_on_initial_state_changed)
		model.transition_changed.disconnect(_on_transition_changed)
		model.moore_output_changed.disconnect(_on_moore_output_changed)
		simulator.updated.disconnect(_apply_highlight)
	model = p_model
	simulator = p_simulator
	simulator.updated.connect(_apply_highlight)
	model.structure_changed.connect(_rebuild)
	model.state_renamed.connect(_on_state_renamed)
	model.initial_state_changed.connect(_on_initial_state_changed)
	model.transition_changed.connect(_on_transition_changed)
	model.moore_output_changed.connect(_on_moore_output_changed)
	_rebuild()


# ---------------------------------------------------------------------------
# Building the grid
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	_clear()
	var has_states := not model.states.is_empty()
	empty_label.visible = not has_states
	grid.visible = has_states
	caption.visible = has_states
	copy_button.disabled = not has_states
	if not has_states:
		return

	var is_moore := model.machine_type == FSMModel.MachineType.MOORE
	var combos := model.input_combo_count()
	var output_columns := model.outputs.size() if is_moore else 0
	grid.columns = 3 + combos + output_columns
	caption.text = _caption_text(is_moore)
	_initial_group = ButtonGroup.new()

	# Header row
	var header: Array[PanelContainer] = []
	for text in ["Init", "State", ""]:
		header.append(_add_cell(FSMUi.header_label(text)))
	for combo in combos:
		var label := FSMUi.header_label(_combo_header(combo))
		label.tooltip_text = _combo_tooltip(combo)
		# Labels ignore the mouse by default, which would hide the tooltip.
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		header.append(_add_cell(label))
	for port in output_columns:
		header.append(_add_cell(FSMUi.header_label(model.outputs[port].name)))
	_cells.append(header)

	# One row per state
	for s in model.states:
		_cells.append(_build_row(s, combos, is_moore))
	_apply_highlight()


func _build_row(s: FSMState, combos: int, is_moore: bool) -> Array[PanelContainer]:
	var row: Array[PanelContainer] = []

	# Init: radio button marking the initial (reset) state
	var check := CheckBox.new()
	check.button_group = _initial_group
	check.button_pressed = s.id == model.initial_state_id
	check.tooltip_text = "Initial state (where the machine starts and resets to)"
	check.toggled.connect(func(on: bool) -> void:
		if on:
			model.set_initial_state(s.id))
	_initial_checks[s.id] = check
	row.append(_add_cell(check))

	# State name
	var name_edit := LineEdit.new()
	name_edit.text = s.name
	name_edit.custom_minimum_size = Vector2(80, 0)
	name_edit.tooltip_text = "State name (must be unique). Press Enter to apply."
	name_edit.text_submitted.connect(
		func(_text: String) -> void: _commit_name(s.id, name_edit))
	name_edit.focus_exited.connect(func() -> void: _commit_name(s.id, name_edit))
	_name_edits[s.id] = name_edit
	row.append(_add_cell(name_edit))

	# Delete button
	var delete := Button.new()
	delete.text = "×"
	delete.flat = true
	delete.tooltip_text = "Delete this state"
	delete.pressed.connect(func() -> void: model.remove_state(s.id))
	row.append(_add_cell(delete))

	# One cell per input combination
	_pickers_by_state[s.id] = []
	_mealy_editors[s.id] = []
	for combo in combos:
		row.append(_add_cell(_build_transition_cell(s, combo, is_moore)))

	# Moore: the state's outputs
	if is_moore:
		_moore_editors[s.id] = []
		for port in model.outputs.size():
			var editor := FSMUi.value_editor(model.outputs[port].width,
				s.moore_output[port],
				func(v: int) -> void: model.set_moore_output(s.id, port, v))
			_moore_editors[s.id].append(editor)
			row.append(_add_cell(editor))
	return row


## Moore: just the next-state dropdown.
## Mealy: [next state v] / [output editors...]
func _build_transition_cell(s: FSMState, combo: int, is_moore: bool) -> Control:
	var t := s.transitions[combo]
	var picker := _make_next_picker(t.next_id)
	picker.item_selected.connect(func(index: int) -> void:
		model.set_next_state(s.id, combo, picker.get_item_metadata(index)))
	_pickers_by_state[s.id].append(picker)
	var editors: Array[Control] = []
	_mealy_editors[s.id].append(editors)
	if is_moore or model.outputs.is_empty():
		return picker

	var box := HBoxContainer.new()
	box.add_child(picker)
	var slash := Label.new()
	slash.text = "/"
	box.add_child(slash)
	for port in model.outputs.size():
		var editor := FSMUi.value_editor(model.outputs[port].width, t.output[port],
			func(v: int) -> void: model.set_mealy_output(s.id, combo, port, v))
		editors.append(editor)
		box.add_child(editor)
	return box


## A dropdown of all states, plus a "—" (unset) entry at the top.
func _make_next_picker(selected_id: int) -> OptionButton:
	var picker := OptionButton.new()
	picker.tooltip_text = "Next state"
	picker.add_item(UNSET_TEXT)
	picker.set_item_metadata(0, FSMTransition.UNSET)
	for st in model.states:
		picker.add_item(st.name)
		picker.set_item_metadata(picker.item_count - 1, st.id)
	# Item 0 is "—", so state number i is item i + 1. For UNSET, state_index
	# returns -1, which selects item 0. Neat.
	picker.select(model.state_index(selected_id) + 1)
	_next_pickers.append(picker)
	return picker


## Wraps `content` in a PanelContainer (for highlighting), adds it to the grid.
func _add_cell(content: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _normal_style)
	content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_child(content)
	grid.add_child(panel)
	return panel


func _clear() -> void:
	for child in grid.get_children():
		child.hide()  # vanish from the layout now...
		child.queue_free()  # ...and be deleted at the end of the frame
	_cells.clear()
	_highlighted.clear()
	_name_edits.clear()
	_initial_checks.clear()
	_next_pickers.clear()
	_pickers_by_state.clear()
	_mealy_editors.clear()
	_moore_editors.clear()


# ---------------------------------------------------------------------------
# Simulation highlighting
# ---------------------------------------------------------------------------

func _apply_highlight() -> void:
	for panel in _highlighted:
		panel.add_theme_stylebox_override("panel", _normal_style)
	_highlighted.clear()
	if _cells.is_empty():
		return
	# While the model is mid-change (e.g. an input was just widened) the
	# simulator can update before we rebuild, so check indices are in range;
	# the rebuild calls this again afterwards.
	var row := model.state_index(simulator.current_state_id) + 1  # 0 = none
	var column := 3 + simulator.current_combo()
	var column_ok := column < _cells[0].size()
	if column_ok:
		for r in _cells.size():
			_highlight(_cells[r][column], _row_column_style)
	if row > 0 and row < _cells.size():
		for panel in _cells[row]:
			_highlight(panel, _row_column_style)
		if column_ok:
			_highlight(_cells[row][column], _intersection_style)
			_scroll_into_view(_cells[row][column])


## If the table is inside a ScrollContainer (it is, in main.tscn), scroll so
## `cell` is visible.
##
## GODOT CONCEPT: `await`. Right after a rebuild the new cells haven't been
## laid out yet (containers arrange their children later in the frame), so
## we can't know where the cell is. `await get_tree().process_frame` pauses
## this function until the next frame, then carries on from here; the caller
## doesn't wait for it.
func _scroll_into_view(cell: Control) -> void:
	var node := get_parent()
	while node and not node is ScrollContainer:
		node = node.get_parent()
	if node == null or not is_inside_tree():
		return
	await get_tree().process_frame
	# A lot can happen in a frame: the cell may have been rebuilt away.
	if is_instance_valid(cell) and cell.is_inside_tree() and cell.visible:
		(node as ScrollContainer).ensure_control_visible(cell)


func _highlight(panel: PanelContainer, style: StyleBoxFlat) -> void:
	panel.add_theme_stylebox_override("panel", style)
	_highlighted.append(panel)


# ---------------------------------------------------------------------------
# Header text
# ---------------------------------------------------------------------------

func _caption_text(is_moore: bool) -> String:
	var input_names := _port_names(model.inputs)
	if model.inputs.is_empty():
		input_names = "(no inputs)"
	if is_moore:
		return "Moore: next state for each input %s, then the state's outputs." % input_names
	if model.outputs.is_empty():
		return "Mealy: next state for each input %s." % input_names
	return "Mealy: each cell is next state / output %s for input %s." % [
		_port_names(model.outputs), input_names]


## "{in0, in1}" in Verilog concatenation style; just "in0" for a single port.
func _port_names(ports: Array[FSMPort]) -> String:
	var names: PackedStringArray = []
	for p in ports:
		names.append(p.name)
	return names[0] if names.size() == 1 else "{%s}" % ", ".join(names)


func _combo_header(combo: int) -> String:
	return model.combo_label(combo) if not model.inputs.is_empty() else "any"


## e.g. "in0 = 1, mode = 01"
func _combo_tooltip(combo: int) -> String:
	var values := model.combo_to_values(combo)
	var parts: PackedStringArray = []
	for i in model.inputs.size():
		parts.append("%s = %s" % [model.inputs[i].name,
			FSMModel.format_value(values[i], model.inputs[i].width)])
	return ", ".join(parts)


# ---------------------------------------------------------------------------
# Reacting to model changes without a rebuild
# ---------------------------------------------------------------------------

func _on_state_renamed(state_id: int) -> void:
	var new_name := model.state_name(state_id)
	var edit: LineEdit = _name_edits.get(state_id)
	if edit and not edit.has_focus():
		edit.text = new_name
	for picker in _next_pickers:
		for i in picker.item_count:
			if picker.get_item_metadata(i) == state_id:
				picker.set_item_text(i, new_name)


func _on_transition_changed(state_id: int, combo: int) -> void:
	if not _pickers_by_state.has(state_id):
		return
	var t := model.get_state(state_id).transitions[combo]
	# select() doesn't emit item_selected, so this can't loop back to the model.
	(_pickers_by_state[state_id][combo] as OptionButton).select(
		model.state_index(t.next_id) + 1)
	var editors: Array = _mealy_editors[state_id][combo]
	for port in editors.size():
		FSMUi.set_editor_value(editors[port], t.output[port])


func _on_moore_output_changed(state_id: int) -> void:
	var editors: Array = _moore_editors.get(state_id, [])
	var s := model.get_state(state_id)
	for port in editors.size():
		FSMUi.set_editor_value(editors[port], s.moore_output[port])


func _on_initial_state_changed() -> void:
	for state_id in _initial_checks:
		_initial_checks[state_id].set_pressed_no_signal(state_id == model.initial_state_id)


func _commit_name(state_id: int, edit: LineEdit) -> void:
	if model.get_state(state_id) == null:
		return  # the state was just deleted
	if edit.text == model.state_name(state_id):
		return
	if not model.rename_state(state_id, edit.text):
		FSMUi.flash_error(edit)
	edit.text = model.state_name(state_id)  # shows the trimmed or original name


# ---------------------------------------------------------------------------
# Copying the table as an image
# ---------------------------------------------------------------------------

## Builds the static, black-on-white version of the table that "Copy table"
## draws: a bordered grid with a header row and one row per state. The initial state's name is marked with INITIAL_MARK.
func build_plain_table() -> Control:
	var is_moore := model.machine_type == FSMModel.MachineType.MOORE
	var combos := model.input_combo_count()
	var output_columns := model.outputs.size() if is_moore else 0
	var bold := FontVariation.new()
	bold.base_font = get_theme_default_font()
	bold.variation_embolden = 0.8

	var grid := GridContainer.new()
	grid.columns = 1 + combos + output_columns
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	# Header row
	var headers: PackedStringArray = ["State"]
	for combo in combos:
		headers.append(_plain_combo_header(combo, is_moore))
	for port in output_columns:
		headers.append(model.outputs[port].name)
	for text in headers:
		grid.add_child(_plain_cell(text, bold))
	# One row per state
	for s in model.states:
		var mark := INITIAL_MARK if s.id == model.initial_state_id else ""
		grid.add_child(_plain_cell(mark + s.name, bold))
		for combo in combos:
			var t := s.transitions[combo]
			var next := model.get_state(t.next_id)
			var text := next.name if next else UNSET_TEXT
			if not is_moore and not model.outputs.is_empty():
				text += " / " + model.output_label(t.output)
			grid.add_child(_plain_cell(text))
		for port in output_columns:
			grid.add_child(_plain_cell(FSMModel.format_value(s.moore_output[port],
				model.outputs[port].width)))

	# Each cell draws its right and bottom border; this frame adds the
	# left and top ones, so every line is 1 px thick.
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _make_border_style(1, 1, 0, 0))
	frame.add_child(grid)

	var page := PanelContainer.new()
	var background := StyleBoxFlat.new()
	background.bg_color = Color.WHITE
	background.set_content_margin_all(PLAIN_PADDING)
	page.add_theme_stylebox_override("panel", background)
	page.add_child(frame)
	return page


## The plain table has no tooltips or caption, so an input column's header
## names the inputs, one per line: "in0 = 1". Mealy headers add a last line
## saying what the cells hold: "next / out0 out1".
func _plain_combo_header(combo: int, is_moore: bool) -> String:
	var lines: PackedStringArray = []
	var values := model.combo_to_values(combo)
	for i in model.inputs.size():
		lines.append("%s = %s" % [model.inputs[i].name,
			FSMModel.format_value(values[i], model.inputs[i].width)])
	if lines.is_empty():
		lines.append("any")
	if not is_moore and not model.outputs.is_empty():
		var names: PackedStringArray = []
		for port in model.outputs:
			names.append(port.name)
		lines.append("next / " + " ".join(names))
	return "\n".join(lines)


## Copies the plain table to the system clipboard as a PNG, emitting
## `copy_failed` with the reason if that isn't possible.
func copy_to_clipboard() -> void:
	if model.states.is_empty():
		copy_failed.emit("There's no table to copy yet: add some states first.")
		return
	var image := await FSMClipboard.render_control(build_plain_table(), self)
	var error := FSMClipboard.copy_image(image)
	if not error.is_empty():
		copy_failed.emit(error)


## One cell of the plain table: centred black text with a right and bottom
## border. `font` is null for the theme's normal font.
static func _plain_cell(text: String, font: Font = null) -> PanelContainer:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.BLACK)
	if font:
		label.add_theme_font_override("font", font)
	var style := _make_border_style(0, 0, 1, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", style)
	cell.add_child(label)
	return cell


## A transparent box with black borders of the given widths.
static func _make_border_style(left: int, top: int, right: int,
		bottom: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = Color.BLACK
	style.border_width_left = left
	style.border_width_top = top
	style.border_width_right = right
	style.border_width_bottom = bottom
	return style


static func _make_cell_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style
