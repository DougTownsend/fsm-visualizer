## The root of the app: owns the FSM model and simulator, hands them to every
## view, and handles New / Save / Load.
##
## GODOT CONCEPTS INTRODUCED HERE
## - The main scene: project.godot's `run/main_scene` points at main.tscn, so
##   this is what Godot loads when you press Play (F5).
## - Scene instancing: main.tscn doesn't contain the toolbar's buttons itself.
##   It contains an *instance* of toolbar.tscn, a reusable scene, just like
##   placing a component in a schematic. Open toolbar.tscn to edit the
##   toolbar; every instance picks up the change.
## - Typed node references: FSMToolbar etc. are the `class_name`s declared in
##   each component's script, so the editor can autocomplete their methods.
## - Dialogs: FileDialog, AcceptDialog and ConfirmationDialog are Windows.
##   They sit in the scene hidden, and popup_centered() shows them. They report
##   back through signals (file_selected, confirmed).
##
## HOW DATA FLOWS
##   views --(call methods)--> FSMModel --(signals)--> views
##   views --(call methods)--> FSMSimulator --(`updated` signal)--> views
## main.gd only creates the model/simulator and calls `bind()` on each view;
## it never relays changes between views itself.
extends PanelContainer

const FILE_EXTENSION := "tres"
const APP_TITLE := "FSM Designer"

var model: FSMModel
var simulator: FSMSimulator
## The file the current machine was last saved to / loaded from, or "".
var current_path: String = ""

@onready var toolbar: FSMToolbar = %Toolbar
@onready var port_editor: FSMPortEditor = %PortEditor
@onready var graph_view: FSMGraphView = %GraphView
@onready var transition_table: FSMTransitionTable = %TransitionTable
@onready var sim_panel: FSMSimPanel = %SimPanel
@onready var file_dialog: FileDialog = %FileDialog
@onready var confirm_new_dialog: ConfirmationDialog = %ConfirmNewDialog
@onready var message_dialog: AcceptDialog = %MessageDialog


func _ready() -> void:
	toolbar.new_requested.connect(_on_new_requested)
	toolbar.save_requested.connect(_on_save_requested)
	toolbar.load_requested.connect(_on_load_requested)
	file_dialog.file_selected.connect(_on_file_selected)
	confirm_new_dialog.confirmed.connect(new_machine)
	graph_view.copy_failed.connect(func(message: String) -> void:
		_show_message("Could not copy diagram", message))
	transition_table.copy_failed.connect(func(message: String) -> void:
		_show_message("Could not copy table", message))
	# Start the file dialog somewhere sensible: the user's Documents folder.
	file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	use_model(FSMModel.create_default())


## Makes `new_model` the machine being edited, with a fresh simulator, and
## points every view at it.
func use_model(new_model: FSMModel) -> void:
	model = new_model
	simulator = FSMSimulator.new(model)
	for view in [toolbar, port_editor, graph_view, transition_table, sim_panel]:
		view.bind(model, simulator)
	_update_title()


## Replaces the current machine with a new, empty one.
func new_machine() -> void:
	current_path = ""
	use_model(FSMModel.create_default())


## Saves the current machine. Returns false (after showing why) on failure.
func save_to(path: String) -> bool:
	if path.get_extension().to_lower() != FILE_EXTENSION:
		path += "." + FILE_EXTENSION
	var err := model.save_to_file(path)
	if err != OK:
		_show_message("Could not save", "Saving to %s failed: %s." % [path, error_string(err)])
		return false
	current_path = path
	_update_title()
	return true


## Loads a machine and switches to it. Returns false (after showing why) on
## failure, leaving the current machine untouched.
func load_from(path: String) -> bool:
	var loaded := FSMModel.load_from_file(path)
	if loaded == null:
		_show_message("Could not open file", "%s\n\n%s" % [path, FSMModel.load_error])
		return false
	current_path = path
	use_model(loaded)
	return true


# ---------------------------------------------------------------------------
# Toolbar requests
# ---------------------------------------------------------------------------

func _on_new_requested() -> void:
	if model.states.is_empty():
		new_machine()
	else:
		confirm_new_dialog.popup_centered()


func _on_save_requested() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.title = "Save FSM"
	if not current_path.is_empty():
		file_dialog.current_path = current_path
	else:
		file_dialog.current_file = "my_fsm.%s" % FILE_EXTENSION
	file_dialog.popup_centered_ratio(0.6)


func _on_load_requested() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Open FSM"
	file_dialog.popup_centered_ratio(0.6)


# The same FileDialog is used for saving and opening; its mode says which.
func _on_file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		save_to(path)
	else:
		load_from(path)


func _show_message(title: String, text: String) -> void:
	message_dialog.title = title
	message_dialog.dialog_text = text
	message_dialog.popup_centered()


## Shows the file name in the window's title bar.
func _update_title() -> void:
	var file_name := current_path.get_file() if not current_path.is_empty() else "untitled"
	get_window().title = "%s — %s" % [APP_TITLE, file_name]
