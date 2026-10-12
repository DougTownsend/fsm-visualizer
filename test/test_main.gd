# End-to-end tests of the main scene: saving, loading and New, checking that
# every view switches to the new model.
extends GutTest

const TEST_FILE := "user://test_main_save.tres"

var main: Node


func before_each() -> void:
	main = add_child_autofree(load("res://scenes/main.tscn").instantiate())


func after_each() -> void:
	if FileAccess.file_exists(TEST_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))


func test_save_then_load_restores_machine_and_rebinds_views() -> void:
	var m: FSMModel = main.model
	var s0 := m.add_state()
	var s1 := m.add_state()
	m.rename_state(s1.id, "DONE")
	m.set_next_state(s0.id, 1, s1.id)
	m.set_state_position(s1.id, Vector2(99, 42))
	assert_true(main.save_to(TEST_FILE))
	assert_eq(main.current_path, TEST_FILE)

	main.new_machine()
	assert_eq(main.model.states.size(), 0)
	assert_eq(main.current_path, "")

	assert_true(main.load_from(TEST_FILE))
	var loaded: FSMModel = main.model
	assert_ne(loaded, m, "a new model object")
	assert_eq(loaded.states.size(), 2)
	assert_eq(loaded.states[1].name, "DONE")
	assert_eq(loaded.states[1].position, Vector2(99, 42))
	# Views follow the loaded model: the table shows its states, and editing
	# the loaded model updates the table.
	var table: FSMTransitionTable = main.transition_table
	assert_eq(table.model, loaded)
	assert_eq(table._name_edits[s1.id].text, "DONE")
	loaded.add_state()
	assert_eq(table._name_edits.size(), 3)
	assert_eq(main.simulator.model, loaded)
	assert_eq(main.graph_view.model, loaded)


func test_old_model_no_longer_drives_views() -> void:
	var old_model: FSMModel = main.model
	main.new_machine()
	old_model.add_state()
	assert_eq(main.transition_table._name_edits.size(), 0,
		"views disconnected from the old model")


func test_save_adds_extension() -> void:
	var without_ext := TEST_FILE.trim_suffix(".tres")
	assert_true(main.save_to(without_ext))
	assert_eq(main.current_path, TEST_FILE)
	assert_true(FileAccess.file_exists(TEST_FILE))


func test_failed_load_keeps_current_machine() -> void:
	var m: FSMModel = main.model
	m.add_state()
	assert_false(main.load_from("user://no_such_file.tres"))
	assert_eq(main.model, m)
	assert_true(main.message_dialog.visible, "error shown to the user")


func test_new_asks_first_when_there_are_states() -> void:
	main.model.add_state()
	main.toolbar.new_requested.emit()
	assert_true(main.confirm_new_dialog.visible)
	assert_eq(main.model.states.size(), 1, "nothing discarded yet")
	main.confirm_new_dialog.confirmed.emit()
	assert_eq(main.model.states.size(), 0)


func test_title_shows_file_name() -> void:
	main.save_to(TEST_FILE)
	assert_string_contains(main.get_window().title, "test_main_save.tres")
