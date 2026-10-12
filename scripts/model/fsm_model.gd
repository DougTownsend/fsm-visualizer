## The complete finite state machine: its ports, states and transitions.
##
## This is the SINGLE SOURCE OF TRUTH for the app. The transition table edits
## it, the graph view draws it, and the simulator runs it. None of those talk
## to each other directly. Instead:
##
##   1. a view calls a method here, e.g. `model.rename_state(id, "IDLE")`
##   2. the method changes the data and EMITS A SIGNAL, e.g. `state_renamed`
##   3. every view that CONNECTED to that signal updates itself
##
## GODOT CONCEPTS INTRODUCED HERE
## - `signal`: Godot's built-in observer pattern. A script declares a signal,
##   other code calls `model.state_renamed.connect(some_function)`, and when
##   this script calls `state_renamed.emit(id)` every connected function runs.
##   The emitter doesn't need to know who is listening.
## - `enum`: a named set of integer constants, usable as a type.
## - `static func`: a function called on the class itself (FSMModel.foo())
##   rather than on an instance.
##
## RULE FOR EDITING THIS FILE: always change data through the methods below,
## never by poking at `states`/`inputs`/... from outside. The methods keep
## everything consistent (e.g. resizing every transition list when an input
## is widened) and emit the signals the views rely on.
class_name FSMModel
extends Resource

enum MachineType {
	## Outputs depend only on the current state (one output per row).
	MOORE,
	## Outputs depend on the current state AND the input (one per cell).
	MEALY,
}

## Cap on the total number of input bits. The table has one column per input
## combination, i.e. 2^bits columns, so 4 bits = 16 columns.
const MAX_INPUT_BITS := 4
## Widest allowed output port.
const MAX_OUTPUT_WIDTH := 32

# Automatic layout: states evenly spaced on a circle around the origin, about
# LAYOUT_SPACING apart, on a circle no smaller than LAYOUT_MIN_RADIUS.
const LAYOUT_SPACING := 130.0
const LAYOUT_MIN_RADIUS := 110.0
# When placing a state by hand-layout rules, keep it this far from others.
const LAYOUT_MIN_DISTANCE := 100.0

## States were added/removed, ports changed, or the machine type changed.
## Views should rebuild themselves completely.
signal structure_changed
## A state's name changed (nothing else did).
signal state_renamed(state_id: int)
## One table cell changed: next state and/or Mealy output.
signal transition_changed(state_id: int, combo: int)
## A state's Moore output changed.
signal moore_output_changed(state_id: int)
## A different state was marked as the initial (reset) state.
signal initial_state_changed
## A state's position in the graph view changed (it was dragged).
signal state_moved(state_id: int)

@export var machine_type: MachineType = MachineType.MOORE
@export var inputs: Array[FSMPort] = []
@export var outputs: Array[FSMPort] = []
@export var states: Array[FSMState] = []
## id of the state the machine starts in (and returns to on Reset), or -1.
@export var initial_state_id: int = -1
## Next id to hand out. Saved so ids stay unique after loading a file.
@export var next_free_id: int = 0
## True until the user moves a state by hand. While true, states are kept
## evenly spaced on a circle as states are added and removed.
@export var auto_layout: bool = true


## A new machine with one 1-bit input and one 1-bit output, and no states.
## (A plain FSMModel.new() has no ports at all.)
static func create_default() -> FSMModel:
	var m := FSMModel.new()
	m.add_input()
	m.add_output()
	return m


# ---------------------------------------------------------------------------
# Input combinations
#
# Each column of the table corresponds to one "combo": all input values
# concatenated into one number, first input in the most significant bits,
# exactly like Verilog's {in0, in1}. With in0 (1 bit) and in1 (2 bits):
#   combo 0b1_01 = 5  <->  in0 = 1, in1 = 0b01
# ---------------------------------------------------------------------------

func total_input_bits() -> int:
	var bits := 0
	for p in inputs:
		bits += p.width
	return bits


## Number of input combinations = number of next-state columns.
func input_combo_count() -> int:
	return 1 << total_input_bits()


## Splits a combo number into one value per input port.
func combo_to_values(combo: int) -> Array[int]:
	return _split_bits(combo, _widths(inputs))


## Joins one value per input port into a combo number (inverse of above).
func values_to_combo(values: Array[int]) -> int:
	return _join_bits(values, _widths(inputs))


## Human-readable input label for a combo, e.g. "1 01".
func combo_label(combo: int) -> String:
	return _format_values(combo_to_values(combo), inputs)


## Human-readable label for a list of output values, e.g. "0 11".
func output_label(values: Array[int]) -> String:
	return _format_values(values, outputs)


## Formats one value: binary (padded to the width) for up to 8 bits,
## decimal for anything wider, where binary would be unreadably long.
static func format_value(value: int, width: int) -> String:
	if width > 8:
		return str(value)
	var s := ""
	for bit in range(width - 1, -1, -1):
		s += "1" if (value >> bit) & 1 else "0"
	return s


# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------

## Returns the state with this id, or null.
func get_state(state_id: int) -> FSMState:
	for s in states:
		if s.id == state_id:
			return s
	return null


## Row number of the state with this id, or -1.
func state_index(state_id: int) -> int:
	for i in states.size():
		if states[i].id == state_id:
			return i
	return -1


## Name of the state with this id, or "" if there is none (e.g. UNSET).
func state_name(state_id: int) -> String:
	var s := get_state(state_id)
	return s.name if s else ""


## Adds a new state named S0, S1, ... (lowest unused number) with every
## transition unset and all outputs 0. The first state becomes the initial one.
func add_state() -> FSMState:
	var s := FSMState.new()
	s.id = next_free_id
	next_free_id += 1
	s.name = _unused_state_name()
	s.moore_output = _zero_outputs()
	for combo in input_combo_count():
		s.transitions.append(_new_transition())
	if not auto_layout:
		s.position = _free_position()
	states.append(s)
	if auto_layout:
		_apply_circle_layout()
	if initial_state_id == -1:
		initial_state_id = s.id
	structure_changed.emit()
	return s


## Deletes a state. Transitions that pointed at it become unset. If it was the
## initial state, the first remaining state (if any) becomes initial.
func remove_state(state_id: int) -> void:
	var index := state_index(state_id)
	if index == -1:
		return
	states.remove_at(index)
	for s in states:
		for t in s.transitions:
			if t.next_id == state_id:
				t.next_id = FSMTransition.UNSET
	if initial_state_id == state_id:
		initial_state_id = states[0].id if not states.is_empty() else -1
	if auto_layout:
		_apply_circle_layout()
	structure_changed.emit()


## Renames a state. Leading/trailing spaces are removed. Returns false (and
## changes nothing) if the name is empty or already used by another state.
func rename_state(state_id: int, new_name: String) -> bool:
	var s := get_state(state_id)
	new_name = new_name.strip_edges()
	if s == null or new_name.is_empty():
		return false
	for other in states:
		if other != s and other.name == new_name:
			return false
	if s.name != new_name:
		s.name = new_name
		state_renamed.emit(state_id)
	return true


## Sets the next state for one table cell. next_id may be FSMTransition.UNSET.
func set_next_state(state_id: int, combo: int, next_id: int) -> void:
	var s := get_state(state_id)
	if s == null or combo < 0 or combo >= s.transitions.size():
		return
	if next_id != FSMTransition.UNSET and get_state(next_id) == null:
		return
	s.transitions[combo].next_id = next_id
	transition_changed.emit(state_id, combo)


## Sets one Mealy output value in one table cell (clamped to the port width).
func set_mealy_output(state_id: int, combo: int, port: int, value: int) -> void:
	var s := get_state(state_id)
	if s == null or combo < 0 or combo >= s.transitions.size():
		return
	if port < 0 or port >= outputs.size():
		return
	s.transitions[combo].output[port] = clampi(value, 0, outputs[port].max_value())
	transition_changed.emit(state_id, combo)


## Sets one Moore output value of a state (clamped to the port width).
func set_moore_output(state_id: int, port: int, value: int) -> void:
	var s := get_state(state_id)
	if s == null or port < 0 or port >= outputs.size():
		return
	s.moore_output[port] = clampi(value, 0, outputs[port].max_value())
	moore_output_changed.emit(state_id)


func set_initial_state(state_id: int) -> void:
	if get_state(state_id) == null or state_id == initial_state_id:
		return
	initial_state_id = state_id
	initial_state_changed.emit()


## Moves a state (e.g. dragged in the graph view). This switches automatic
## layout off, so the user's arrangement is kept from now on.
func set_state_position(state_id: int, pos: Vector2) -> void:
	var s := get_state(state_id)
	if s == null:
		return
	auto_layout = false
	s.position = pos
	state_moved.emit(state_id)


## Spaces all states evenly on a circle and switches automatic layout back on.
func arrange_states() -> void:
	auto_layout = true
	_apply_circle_layout()
	for s in states:
		state_moved.emit(s.id)


func set_machine_type(type: MachineType) -> void:
	if type == machine_type:
		return
	machine_type = type
	structure_changed.emit()


## Positions for `count` states evenly spaced on a circle, the first at the
## top, going clockwise. The circle grows with the number of states.
static func circle_layout(count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if count == 1:
		positions.append(Vector2.ZERO)
		return positions
	var radius := maxf(LAYOUT_MIN_RADIUS, count * LAYOUT_SPACING / TAU)
	for i in count:
		positions.append(Vector2.from_angle(-PI / 2 + i * TAU / count) * radius)
	return positions


func _apply_circle_layout() -> void:
	var positions := circle_layout(states.size())
	for i in states.size():
		states[i].position = positions[i]


# ---------------------------------------------------------------------------
# Input ports
#
# Changing inputs changes the set of table columns, so every state's
# transition list is rebuilt by _remap_transitions(), which keeps as much of
# the user's work as possible (see that function for the rules).
# ---------------------------------------------------------------------------

## Adds an input port. Returns false if it would exceed MAX_INPUT_BITS.
func add_input(p_name: String = "", width: int = 1) -> bool:
	if width < 1 or total_input_bits() + width > MAX_INPUT_BITS:
		return false
	if p_name.is_empty():
		p_name = _unused_port_name("in", inputs)
	var old_widths := _widths(inputs)
	inputs.append(FSMPort.new(p_name, width))
	var mapping: Array[int] = []
	for i in old_widths.size():
		mapping.append(i)
	mapping.append(-1)  # the new port didn't exist before
	_remap_transitions(old_widths, mapping)
	structure_changed.emit()
	return true


func remove_input(index: int) -> void:
	if index < 0 or index >= inputs.size():
		return
	var old_widths := _widths(inputs)
	inputs.remove_at(index)
	var mapping: Array[int] = []
	for i in old_widths.size():
		if i != index:
			mapping.append(i)
	_remap_transitions(old_widths, mapping)
	structure_changed.emit()


## Changes an input's width. Returns false if it would exceed MAX_INPUT_BITS.
func set_input_width(index: int, width: int) -> bool:
	if index < 0 or index >= inputs.size() or width < 1:
		return false
	if total_input_bits() - inputs[index].width + width > MAX_INPUT_BITS:
		return false
	if width == inputs[index].width:
		return true
	var old_widths := _widths(inputs)
	inputs[index].width = width
	var mapping: Array[int] = []
	for i in old_widths.size():
		mapping.append(i)
	_remap_transitions(old_widths, mapping)
	structure_changed.emit()
	return true


## Renames an input. Returns false if the name is empty or already taken.
func rename_input(index: int, new_name: String) -> bool:
	return _rename_port(inputs, index, new_name)


# ---------------------------------------------------------------------------
# Output ports
#
# Outputs don't change the columns, only the length of every output list
# (each state's moore_output and each transition's Mealy output).
# ---------------------------------------------------------------------------

func add_output(p_name: String = "", width: int = 1) -> bool:
	if width < 1 or width > MAX_OUTPUT_WIDTH:
		return false
	if p_name.is_empty():
		p_name = _unused_port_name("out", outputs)
	outputs.append(FSMPort.new(p_name, width))
	for values in _all_output_lists():
		values.append(0)
	structure_changed.emit()
	return true


func remove_output(index: int) -> void:
	if index < 0 or index >= outputs.size():
		return
	outputs.remove_at(index)
	for values in _all_output_lists():
		values.remove_at(index)
	structure_changed.emit()


## Changes an output's width. Values too big for the new width are clamped.
func set_output_width(index: int, width: int) -> bool:
	if index < 0 or index >= outputs.size() or width < 1 or width > MAX_OUTPUT_WIDTH:
		return false
	outputs[index].width = width
	var max_value := outputs[index].max_value()
	for values in _all_output_lists():
		values[index] = mini(values[index], max_value)
	structure_changed.emit()
	return true


func rename_output(index: int, new_name: String) -> bool:
	return _rename_port(outputs, index, new_name)


# ---------------------------------------------------------------------------
# Saving and loading
#
# Because every class here is a Resource with @export properties, Godot can
# write the whole machine (including the nested states, transitions and
# ports) to a human-readable .tres text file with one call, and read it back
# with another. Open a saved .tres in a text editor to see the format.
# ---------------------------------------------------------------------------

## Saves to a path such as "user://my_fsm.tres". Returns OK or an error code.
## ("user://" is a per-user writable folder Godot manages for each project;
## "res://" is the project folder itself.)
func save_to_file(path: String) -> Error:
	return ResourceSaver.save(self, path)


## Why the last load_from_file() returned null ("" after a successful load).
## `static var` belongs to the class, not to any one instance.
static var load_error: String = ""

## The only scripts a saved FSM file may reference (see _check_file_is_safe).
const ALLOWED_SCRIPTS: Array[String] = [
	"res://scripts/model/fsm_model.gd",
	"res://scripts/model/fsm_port.gd",
	"res://scripts/model/fsm_state.gd",
	"res://scripts/model/fsm_transition.gd",
]


## Loads a machine saved by save_to_file(). Returns null on failure and puts
## the reason in FSMModel.load_error.
##
## SECURITY: a .tres file can contain or reference GDScript code, and Godot
## runs that code while loading it. So before handing the file to Godot we
## read it as plain text and refuse anything except plain data and our own
## four model scripts. After loading, validate() checks the data makes sense
## (right number of transitions, no dangling state ids...), so a damaged or
## hand-edited file can't crash the app later.
##
## CACHE_MODE_IGNORE makes Godot re-read the file (and the states, ports etc.
## embedded in it) instead of handing back a copy it already has in memory
## from an earlier load. External files it references, such as our scripts,
## are still shared. (Don't use CACHE_MODE_IGNORE_DEEP here: that also
## reloads the scripts, including this one while it is running, and crashes.)
static func load_from_file(path: String) -> FSMModel:
	load_error = _check_file_is_safe(path)
	if not load_error.is_empty():
		return null
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var loaded := res as FSMModel
	if loaded == null:
		load_error = "The file could not be read as an FSM."
		return null
	load_error = loaded.validate()
	return loaded if load_error.is_empty() else null


## Checks the machine is internally consistent. Returns "" if it is, or a
## description of the first problem found.
func validate() -> String:
	if machine_type not in MachineType.values():
		return "Unknown machine type."
	var port_names: Dictionary[String, bool] = {}
	for p in inputs + outputs:
		if p == null or p.name.strip_edges().is_empty():
			return "A port is missing or has no name."
		if port_names.has(p.name):
			return "Port name \"%s\" is used twice." % p.name
		port_names[p.name] = true
		if p.width < 1 or p.width > MAX_OUTPUT_WIDTH:
			return "Port \"%s\" has an invalid width." % p.name
	if total_input_bits() > MAX_INPUT_BITS:
		return "The inputs use more than %d bits." % MAX_INPUT_BITS

	var ids: Dictionary[int, bool] = {}
	var names: Dictionary[String, bool] = {}
	for s in states:
		if s == null or s.id < 0 or s.id >= next_free_id or ids.has(s.id):
			return "A state is missing or has an invalid id."
		if s.name.strip_edges().is_empty() or names.has(s.name):
			return "State names must be unique and not empty."
		ids[s.id] = true
		names[s.name] = true
	for s in states:
		if not _values_fit(s.moore_output, outputs):
			return "State %s has invalid outputs." % s.name
		if s.transitions.size() != input_combo_count():
			return "State %s has the wrong number of transitions." % s.name
		for t in s.transitions:
			if t == null or (t.next_id != FSMTransition.UNSET and not ids.has(t.next_id)):
				return "State %s has a transition to a missing state." % s.name
			if not _values_fit(t.output, outputs):
				return "State %s has invalid transition outputs." % s.name
	if states.is_empty() != (initial_state_id == -1):
		return "The initial state is missing."
	if initial_state_id != -1 and not ids.has(initial_state_id):
		return "The initial state is missing."
	return ""


## Reads a .tres file as text and returns "" if it only contains plain data
## and references to our own model scripts, or an error message otherwise.
static func _check_file_is_safe(path: String) -> String:
	if path.get_extension().to_lower() != "tres":
		return "Only .tres files can be loaded."
	if not FileAccess.file_exists(path):
		return "File not found: %s" % path
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return "Could not read the file (%s)." % error_string(FileAccess.get_open_error())

	# Every section header in a .tres file is a line starting with "[". Only
	# these four kinds are allowed, and each is checked further below.
	var header := RegEx.create_from_string(
		"^\\[(gd_resource|ext_resource|sub_resource|resource)( [^\\]]*)?\\]$")
	var attribute := RegEx.create_from_string("(\\w+)=\"([^\"]*)\"")
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if not line.begins_with("["):
			continue
		var m := header.search(line)
		if m == null:
			return "The file contains an unexpected section: %s" % line.left(60)
		var attrs: Dictionary[String, String] = {}
		for a in attribute.search_all(m.get_string(2)):
			attrs[a.get_string(1)] = a.get_string(2)
		match m.get_string(1):
			"gd_resource":
				if attrs.get("script_class") != "FSMModel":
					return "This file isn't an FSM."
			"sub_resource":
				# Plain data objects only: an embedded GDScript would be type="GDScript".
				if attrs.get("type") != "Resource":
					return "The file contains embedded %s data." % attrs.get("type", "unknown")
			"ext_resource":
				if attrs.get("type") != "Script" or attrs.get("path") not in ALLOWED_SCRIPTS:
					return "The file refers to another file that isn't allowed: %s" % attrs.get(
						"path", "?")
				# Godot finds external files by uid first and only uses the path as a
				# fallback, so a uid must also belong to the allowed script.
				if attrs.has("uid"):
					var real_uid := ResourceLoader.get_resource_uid(attrs["path"])
					if attrs["uid"] != ResourceUID.id_to_text(real_uid):
						return "The file's script reference doesn't match this program."
	return ""


static func _values_fit(values: Array[int], ports: Array[FSMPort]) -> bool:
	if values.size() != ports.size():
		return false
	for i in values.size():
		if values[i] < 0 or values[i] > ports[i].max_value():
			return false
	return true


# ---------------------------------------------------------------------------
# Internal helpers (the leading underscore is a convention for "private";
# GDScript doesn't enforce it)
# ---------------------------------------------------------------------------

func _new_transition() -> FSMTransition:
	var t := FSMTransition.new()
	t.output = _zero_outputs()
	return t


func _zero_outputs() -> Array[int]:
	var values: Array[int] = []
	values.resize(outputs.size())
	values.fill(0)
	return values


## Every list of output values in the machine, so a port change can be applied
## to all of them. Arrays are passed by reference, so changing one of the
## returned arrays changes the data in the model.
func _all_output_lists() -> Array[Array]:
	var lists: Array[Array] = []
	for s in states:
		lists.append(s.moore_output)
		for t in s.transitions:
			lists.append(t.output)
	return lists


## Rebuilds every state's transition list after the input ports changed.
##
## `old_widths` are the input widths before the change; `mapping[i]` says which
## old port new port i was (or -1 if it is brand new). For each new column
## we work out which old column "means the same thing" and copy it:
## - a brand-new port is ignored, so behaviour is copied for all its values
##   (the machine behaves as before, whatever the new input does);
## - a removed port is treated as having been 0;
## - a widened port has no old column for its new, larger values; those
##   cells start unset.
func _remap_transitions(old_widths: Array[int], mapping: Array[int]) -> void:
	var new_widths := _widths(inputs)
	var new_count := input_combo_count()
	for s in states:
		var old_transitions := s.transitions
		var new_transitions: Array[FSMTransition] = []
		for combo in new_count:
			var new_values := _split_bits(combo, new_widths)
			var old_values: Array[int] = []
			old_values.resize(old_widths.size())
			old_values.fill(0)
			var has_old_column := true
			for new_port in mapping.size():
				var old_port := mapping[new_port]
				if old_port == -1:
					continue
				if new_values[new_port] > (1 << old_widths[old_port]) - 1:
					has_old_column = false
					break
				old_values[old_port] = new_values[new_port]
			if has_old_column:
				var old_combo := _join_bits(old_values, old_widths)
				new_transitions.append(old_transitions[old_combo].copy())
			else:
				new_transitions.append(_new_transition())
		s.transitions = new_transitions


## A spot for a new state that doesn't sit on top of an existing one: the
## first free point on a spiral out from the middle of the existing states.
func _free_position() -> Vector2:
	var centre := Vector2.ZERO
	for s in states:
		centre += s.position
	if not states.is_empty():
		centre /= states.size()
	for step in 500:
		var angle := step * 0.8
		var candidate := centre + Vector2.from_angle(angle) * (step * 12.0)
		var clear := true
		for s in states:
			if s.position.distance_to(candidate) < LAYOUT_MIN_DISTANCE:
				clear = false
				break
		if clear:
			return candidate
	return centre


func _unused_state_name() -> String:
	var n := 0
	while _state_name_taken("S%d" % n):
		n += 1
	return "S%d" % n


func _state_name_taken(n: String) -> bool:
	for s in states:
		if s.name == n:
			return true
	return false


static func _unused_port_name(prefix: String, ports: Array[FSMPort]) -> String:
	var n := 0
	while _port_name_taken(ports, "%s%d" % [prefix, n]):
		n += 1
	return "%s%d" % [prefix, n]


static func _port_name_taken(ports: Array[FSMPort], n: String) -> bool:
	for p in ports:
		if p.name == n:
			return true
	return false


func _rename_port(ports: Array[FSMPort], index: int, new_name: String) -> bool:
	new_name = new_name.strip_edges()
	if index < 0 or index >= ports.size() or new_name.is_empty():
		return false
	if ports[index].name == new_name:
		return true
	# Input and output names share one namespace, like in a Verilog module.
	if _port_name_taken(inputs, new_name) or _port_name_taken(outputs, new_name):
		return false
	ports[index].name = new_name
	structure_changed.emit()
	return true


static func _widths(ports: Array[FSMPort]) -> Array[int]:
	var widths: Array[int] = []
	for p in ports:
		widths.append(p.width)
	return widths


## Splits `bits` into fields of the given widths, first field most significant.
static func _split_bits(bits: int, widths: Array[int]) -> Array[int]:
	var values: Array[int] = []
	values.resize(widths.size())
	for i in range(widths.size() - 1, -1, -1):
		values[i] = bits & ((1 << widths[i]) - 1)
		bits >>= widths[i]
	return values


## Inverse of _split_bits.
static func _join_bits(values: Array[int], widths: Array[int]) -> int:
	var bits := 0
	for i in widths.size():
		bits = (bits << widths[i]) | (values[i] & ((1 << widths[i]) - 1))
	return bits


static func _format_values(values: Array[int], ports: Array[FSMPort]) -> String:
	var parts: PackedStringArray = []
	for i in mini(values.size(), ports.size()):
		parts.append(format_value(values[i], ports[i].width))
	return " ".join(parts)
