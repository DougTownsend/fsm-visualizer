# Tests for the graph view's logic (scenes/graph_view.gd): which arrows exist,
# their labels, hit testing, and mouse dragging/panning/zooming. Drawing
# itself is checked by eye (screenshots), not here.
#
# Mouse input is simulated by building InputEvent objects and passing them
# straight to _gui_input(), exactly what Godot does for a real click.
extends GutTest

var model: FSMModel
var view: FSMGraphView


func before_each() -> void:
	model = FSMModel.create_default()
	view = add_child_autofree(FSMGraphView.new())
	view.size = Vector2(400, 400)
	view.bind(model, FSMSimulator.new(model))


# Puts the view at 100% zoom, centred on the model origin, with auto-fit off,
# so screen = (200, 200) + model position.
func _reset_view() -> void:
	view._auto_fit = false
	view.zoom = 1.0
	view.pan = Vector2.ZERO


func _mouse_button(pos: Vector2, pressed: bool,
		button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.pressed = pressed
	e.button_index = button
	return e


func _mouse_motion(pos: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.relative = relative
	return e


# Builds the Moore "11" detector: S0 -1-> S1 -1-> S2 -1-> S2, 0 -> S0.
func _build_detector() -> Array[FSMState]:
	var s0 := model.add_state()
	var s1 := model.add_state()
	var s2 := model.add_state()
	for s in [s0, s1, s2]:
		model.set_next_state(s.id, 0, s0.id)
	model.set_next_state(s0.id, 1, s1.id)
	model.set_next_state(s1.id, 1, s2.id)
	model.set_next_state(s2.id, 1, s2.id)
	return [s0, s1, s2]


func _find_edge(edges: Array[Dictionary], from_id: int, to_id: int) -> Dictionary:
	for e in edges:
		if e["from"] == from_id and e["to"] == to_id:
			return e
	return {}


# --- edges -------------------------------------------------------------------

func test_unset_transitions_have_no_edges() -> void:
	model.add_state()
	assert_eq(view.collect_edges().size(), 0)


func test_edges_and_labels() -> void:
	var s := _build_detector()
	var edges := view.collect_edges()
	assert_eq(edges.size(), 6)
	assert_eq(_find_edge(edges, s[0].id, s[0].id)["label"], "0")
	assert_eq(_find_edge(edges, s[0].id, s[1].id)["label"], "1")
	assert_eq(_find_edge(edges, s[2].id, s[2].id)["label"], "1")


func test_all_inputs_same_way_is_any() -> void:
	var s0 := model.add_state()
	model.set_next_state(s0.id, 0, s0.id)
	model.set_next_state(s0.id, 1, s0.id)
	var edges := view.collect_edges()
	assert_eq(edges.size(), 1, "both inputs merged into one arrow")
	assert_eq(edges[0]["label"], "any")
	assert_eq(edges[0]["combos"], [0, 1] as Array[int])


func test_mealy_labels_include_outputs() -> void:
	model.set_machine_type(FSMModel.MachineType.MEALY)
	var s0 := model.add_state()
	var s1 := model.add_state()
	model.set_next_state(s0.id, 0, s0.id)
	model.set_next_state(s0.id, 1, s1.id)
	model.set_mealy_output(s0.id, 1, 0, 1)
	model.set_next_state(s1.id, 0, s0.id)
	model.set_next_state(s1.id, 1, s0.id)
	var edges := view.collect_edges()
	assert_eq(_find_edge(edges, s0.id, s1.id)["label"], "1/1")
	assert_eq(_find_edge(edges, s1.id, s0.id)["label"], "any/0")
	model.set_mealy_output(s1.id, 1, 0, 1)
	edges = view.collect_edges()
	assert_eq(_find_edge(edges, s1.id, s0.id)["label"], "0/0, 1/1",
		"different outputs: can't say 'any'")


func test_long_labels_wrap() -> void:
	model.set_input_width(0, 3)
	var s0 := model.add_state()
	for combo in 6:
		model.set_next_state(s0.id, combo, s0.id)
	assert_eq(view.collect_edges()[0]["label"], "000, 001, 010, 011,\n100, 101")


# --- coordinates and hit testing -----------------------------------------------

func test_screen_model_round_trip() -> void:
	view.zoom = 1.7
	view.pan = Vector2(13, -40)
	var p := Vector2(55, -21)
	assert_almost_eq(view.to_model(view.to_screen(p)), p, Vector2(0.001, 0.001))


func test_state_at() -> void:
	var s0 := model.add_state()
	_reset_view()
	model.set_state_position(s0.id, Vector2(50, 0))
	assert_eq(view.state_at(Vector2(250, 0) + Vector2(0, 200)), s0.id)
	assert_eq(view.state_at(Vector2(250 + FSMGraphView.STATE_RADIUS + 1, 200)), -1)


func test_fit_view_shows_all_states() -> void:
	for i in 12:
		model.add_state()
	view.fit_view()
	for s in model.states:
		var p := view.to_screen(s.position)
		assert_true(Rect2(Vector2.ZERO, view.size).has_point(p), "%s visible" % s.name)


# --- mouse -------------------------------------------------------------------

func test_drag_state_moves_it_in_the_model() -> void:
	var s0 := model.add_state()
	_reset_view()
	model.set_state_position(s0.id, Vector2.ZERO)
	# Grab it slightly off-centre; it should keep that offset while dragged.
	view._gui_input(_mouse_button(Vector2(205, 200), true))
	view._gui_input(_mouse_motion(Vector2(255, 230), Vector2(50, 30)))
	view._gui_input(_mouse_button(Vector2(255, 230), false))
	assert_eq(s0.position, Vector2(50, 30))
	# After release, moving the mouse doesn't drag any more.
	view._gui_input(_mouse_motion(Vector2(300, 300), Vector2(45, 70)))
	assert_eq(s0.position, Vector2(50, 30))


func test_drag_background_pans() -> void:
	model.add_state()
	_reset_view()
	view._gui_input(_mouse_button(Vector2(10, 10), true))
	view._gui_input(_mouse_motion(Vector2(30, 5), Vector2(20, -5)))
	view._gui_input(_mouse_button(Vector2(30, 5), false))
	assert_eq(view.pan, Vector2(20, -5))


func test_wheel_zoom_keeps_point_under_mouse() -> void:
	model.add_state()
	_reset_view()
	var mouse := Vector2(300, 120)
	var before := view.to_model(mouse)
	view._gui_input(_mouse_button(mouse, true, MOUSE_BUTTON_WHEEL_UP))
	assert_gt(view.zoom, 1.0)
	assert_almost_eq(view.to_model(mouse), before, Vector2(0.001, 0.001))


# --- simulation highlighting -------------------------------------------------

func test_active_edge_follows_input_and_clock() -> void:
	var s := _build_detector()
	var sim := view.simulator
	assert_eq(view.active_edge(), Vector2i(s[0].id, s[0].id))
	sim.set_input(0, 1)
	assert_eq(view.active_edge(), Vector2i(s[0].id, s[1].id))
	sim.clock()
	assert_eq(view.active_edge(), Vector2i(s[1].id, s[2].id))


func test_no_active_edge_when_unset_or_empty() -> void:
	assert_eq(view.active_edge(), FSMGraphView.NO_EDGE)
	model.add_state()
	assert_eq(view.active_edge(), FSMGraphView.NO_EDGE)


# --- copy diagram ------------------------------------------------------------
# The image itself needs a real renderer (tests run headless), so these check
# the parts around it.

func test_plain_view_never_highlights() -> void:
	_build_detector()
	view.plain = true
	assert_eq(view.active_edge(), FSMGraphView.NO_EDGE)


func test_copy_with_no_states_reports_failure() -> void:
	watch_signals(view)
	assert_null(await view.render_plain_image())
	await view.copy_to_clipboard()
	assert_signal_emitted(view, "copy_failed")


func test_diagram_bounds_cover_every_state() -> void:
	var s := _build_detector()
	model.set_state_position(s[2].id, Vector2(500, -300))
	var bounds := view.diagram_bounds()
	for state in s:
		assert_true(bounds.grow(-FSMGraphView.STATE_RADIUS).has_point(state.position))


func test_sh_quote_escapes_single_quotes() -> void:
	assert_eq(FSMClipboard._sh_quote("it's"), "'it'\\''s'")
