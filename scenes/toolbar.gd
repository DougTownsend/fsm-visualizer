## The strip of controls across the top of the window.
##
## GODOT CONCEPTS INTRODUCED HERE
## - A script attached to a node in a scene: this file is attached to the root
##   node of toolbar.tscn (an HBoxContainer), so `extends HBoxContainer`.
## - `@onready var x = %Name`: `%Name` finds the node in this scene that was
##   marked "Access as Unique Name" (unique_name_in_owner in the .tscn file).
##   `@onready` delays the lookup until the node is ready, because child nodes
##   don't exist yet when the script's variables are first initialised.
## - Connecting to a built-in signal of a built-in node: Buttons emit
##   `pressed`, OptionButtons emit `item_selected(index)`.
## - "Call down, signal up": the toolbar doesn't know how to show a file
##   dialog or swap the whole model, that's main.gd's job. So for New / Save /
##   Load it just emits its OWN signals, and main.gd (its parent) connects to
##   them. Children announce; parents decide.
class_name FSMToolbar
extends HBoxContainer

signal new_requested
signal save_requested
signal load_requested

var model: FSMModel

@onready var type_option: OptionButton = %TypeOption
@onready var add_state_button: Button = %AddStateButton
@onready var new_button: Button = %NewButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton


# `_ready()` runs once, after this node and all its children have entered the
# scene tree. It's the usual place to connect signals and do setup.
func _ready() -> void:
	type_option.item_selected.connect(_on_type_selected)
	add_state_button.pressed.connect(_on_add_state_pressed)
	# Re-emit the button presses as the toolbar's own signals.
	new_button.pressed.connect(new_requested.emit)
	save_button.pressed.connect(save_requested.emit)
	load_button.pressed.connect(load_requested.emit)
	new_button.shortcut = _ctrl_shortcut(KEY_N)
	save_button.shortcut = _ctrl_shortcut(KEY_S)
	load_button.shortcut = _ctrl_shortcut(KEY_O)


## Called by main.gd to hand this view the machine it should control.
## May be called again later (e.g. after loading a file) with a new model.
func bind(p_model: FSMModel, _simulator: FSMSimulator) -> void:
	if model:
		model.structure_changed.disconnect(_refresh)
	model = p_model
	model.structure_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	# Keep the dropdown in sync with the model (matters after loading a file).
	# The OptionButton item indices were set up to match the enum values.
	type_option.select(model.machine_type)


func _on_type_selected(index: int) -> void:
	model.set_machine_type(index as FSMModel.MachineType)


func _on_add_state_pressed() -> void:
	model.add_state()


## Ctrl+key (Cmd+key on macOS, thanks to command_or_control_autoremap).
static func _ctrl_shortcut(key: Key) -> Shortcut:
	var event := InputEventKey.new()
	event.keycode = key
	event.command_or_control_autoremap = true
	var shortcut := Shortcut.new()
	shortcut.events = [event]
	return shortcut
