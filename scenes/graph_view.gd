## The state diagram: circles for states, arrows for transitions.
##
## Everything is drawn by hand in `_draw()` from the model's data; nothing
## here stores its own copy of the machine. When the model emits any change
## signal we just call `queue_redraw()` and Godot calls `_draw()` again.
##
## What gets drawn:
## - one circle per state at FSMState.position, with its name (and, for Moore
##   machines, its output underneath in green);
## - one arrow per (from, to) pair of states: all the input combinations that
##   make that move are merged into one label, e.g. "01, 11". Mealy labels
##   read "input/output". If every input goes the same way the label is "any";
## - arrows between a pair of states in both directions are curved apart so
##   they don't overlap; self-transitions are loops pointing away from the
##   middle of the diagram;
## - a short arrow into the initial state.
##
## Simulation highlighting: the current state is filled orange, and the arrow
## the next clock will take (for the current input) is drawn thicker in
## orange, with an orange outline on the state it leads to.
##
## Mouse: drag a state to move it (the position is saved in the model), drag
## empty space to pan, mouse wheel to zoom, "Fit" button to show everything.
##
## "Copy diagram" renders a second, `plain` copy of this view (black on white,
## no highlighting) into an offscreen SubViewport and copies it as a PNG.
##
## GODOT CONCEPTS INTRODUCED HERE
## - `_gui_input(event)`: called for mouse/keyboard events aimed at this
##   Control. `event` is an InputEvent subclass; check its type with `is`.
##   `accept_event()` marks it handled so it isn't passed on.
## - `draw_set_transform()`: shifts/scales everything drawn afterwards. We
##   draw the diagram in "model coordinates" (the ones stored in the states)
##   and let this transform apply the pan and zoom.
## - `_notification(what)`: a catch-all for engine notifications such as
##   NOTIFICATION_RESIZED or NOTIFICATION_MOUSE_EXIT.
## - Fonts: `get_theme_default_font()` returns a Font; Font can measure text
##   (`get_string_size`) so we can centre it ourselves.
class_name FSMGraphView
extends Control

const STATE_RADIUS := 32.0
## How far apart (at the middle) two opposite arrows between a pair bulge.
const EDGE_BEND := 36.0
const ARROW_LENGTH := 12.0
const ARROW_HALF_WIDTH := 5.5
const LINE_WIDTH := 2.0
const ACTIVE_LINE_WIDTH := 3.5
const NAME_FONT_SIZE := 16
const OUTPUT_FONT_SIZE := 13
const LABEL_FONT_SIZE := 13
## Edge labels wrap onto a new line after this many input combinations.
const LABEL_ITEMS_PER_LINE := 4
const INITIAL_ARROW_LENGTH := 34.0
const MIN_ZOOM := 0.25
const MAX_ZOOM := 2.5
## Extra room around the states when fitting the view (for loops and labels).
const FIT_MARGIN := 70.0

const COLOR_BACKGROUND := Color(0.12, 0.13, 0.15)
const COLOR_STATE_FILL := Color(0.19, 0.23, 0.29)
const COLOR_STATE_OUTLINE := Color(0.55, 0.65, 0.8)
const COLOR_STATE_HOVER := Color(0.92, 0.96, 1.0)
const COLOR_EDGE := Color(0.72, 0.75, 0.8)
const COLOR_TEXT := Color(0.95, 0.95, 0.95)
const COLOR_OUTPUT := Color(0.45, 0.95, 0.55)
const COLOR_LABEL_BACKGROUND := Color(0.12, 0.13, 0.15, 0.85)
const COLOR_HINT := Color(1, 1, 1, 0.35)
const COLOR_CURRENT_FILL := Color(0.93, 0.6, 0.15)
const COLOR_CURRENT_TEXT := Color(0.1, 0.08, 0.05)
const COLOR_ACTIVE := Color(1.0, 0.7, 0.25)
## Colours for a `plain` view (the copied image): black ink on white.
const PLAIN_BACKGROUND := Color.WHITE
const PLAIN_INK := Color.BLACK
const PLAIN_LABEL_BACKGROUND := Color.WHITE  # opaque: see render_plain_image()
## White space left around the diagram in the copied image, in pixels.
const PLAIN_PADDING := 16

const NO_EDGE := Vector2i(-1, -1)

## Emitted when "Copy diagram" fails, with a message for the user.
signal copy_failed(message: String)

## When true, draw for export: black on white, no simulation highlighting,
## no hint text and no buttons. Set before adding the view to the tree.
var plain := false
var model: FSMModel
var simulator: FSMSimulator

## View transform: screen = size / 2 + pan + model_position * zoom
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO

## While true, the view re-fits itself whenever states are added/removed or
## the view is resized. Turned off as soon as the user pans, zooms or drags;
## the Fit button turns it back on.
var _auto_fit := true
var _hover_id := -1  # state under the mouse, or -1
var _drag_id := -1  # state being dragged, or -1
var _drag_offset := Vector2.ZERO  # state position minus mouse position
var _panning := false


func _ready() -> void:
	if plain:
		return
	# A row of small buttons in the top-right corner, created in code.
	var buttons := HBoxContainer.new()
	var arrange_button := Button.new()
	arrange_button.text = "Arrange"
	arrange_button.tooltip_text = ("Space the states evenly on a circle.\n"
		+ "(Automatic until you drag a state; this turns it back on.)")
	arrange_button.pressed.connect(func() -> void:
		model.arrange_states()
		_auto_fit = true
		fit_view())
	buttons.add_child(arrange_button)
	var fit_button := Button.new()
	fit_button.text = "Fit"
	fit_button.tooltip_text = "Zoom and pan so the whole diagram is visible"
	fit_button.pressed.connect(func() -> void:
		_auto_fit = true
		fit_view())
	buttons.add_child(fit_button)
	var copy_button := Button.new()
	copy_button.text = "Copy diagram"
	copy_button.tooltip_text = ("Copy the diagram to the clipboard as a PNG\n"
		+ "(black on white, without simulation highlighting)")
	copy_button.pressed.connect(copy_to_clipboard)
	buttons.add_child(copy_button)
	add_child(buttons)
	# Anchor the row to the top-right corner, 8 px in from the edges.
	buttons.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT,
		Control.PRESET_MODE_MINSIZE, 8)


func bind(p_model: FSMModel, p_simulator: FSMSimulator) -> void:
	if model:
		model.structure_changed.disconnect(_on_structure_changed)
		for sig in _redraw_signals():
			sig.disconnect(_on_model_changed)
		simulator.updated.disconnect(queue_redraw)
	model = p_model
	simulator = p_simulator
	simulator.updated.connect(queue_redraw)
	model.structure_changed.connect(_on_structure_changed)
	for sig in _redraw_signals():
		sig.connect(_on_model_changed)
	_auto_fit = true
	_hover_id = -1
	_drag_id = -1
	fit_view()


## Model signals after which a redraw is all that's needed.
func _redraw_signals() -> Array[Signal]:
	return [model.state_renamed, model.transition_changed,
		model.moore_output_changed, model.initial_state_changed, model.state_moved]


# The model's signals pass 0, 1 or 2 arguments; default values let one
# handler accept all of them.
func _on_model_changed(_a: Variant = null, _b: Variant = null) -> void:
	queue_redraw()


func _on_structure_changed() -> void:
	if _auto_fit:
		fit_view()
	queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			if _auto_fit and model:
				fit_view()
		NOTIFICATION_MOUSE_EXIT:
			_set_hover(-1)


# ---------------------------------------------------------------------------
# Coordinates and view control
# ---------------------------------------------------------------------------

## Converts a point in model coordinates to a point on this Control.
func to_screen(model_pos: Vector2) -> Vector2:
	return size / 2 + pan + model_pos * zoom


## Converts a point on this Control to model coordinates.
func to_model(screen_pos: Vector2) -> Vector2:
	return (screen_pos - size / 2 - pan) / zoom


## The id of the state under a point on this Control, or -1. States drawn
## later are on top, so search from the end.
func state_at(screen_pos: Vector2) -> int:
	var p := to_model(screen_pos)
	for i in range(model.states.size() - 1, -1, -1):
		if p.distance_to(model.states[i].position) <= STATE_RADIUS:
			return model.states[i].id
	return -1


## Zooms and pans so every state (plus a margin) fits in the view. When
## fitting automatically we don't zoom in past 100%, so a lone state isn't huge.
func fit_view() -> void:
	if model == null or model.states.is_empty() or size.x <= 0 or size.y <= 0:
		zoom = 1.0
		pan = Vector2.ZERO
		queue_redraw()
		return
	var bounds := diagram_bounds()
	var fit_zoom := minf(size.x / bounds.size.x, size.y / bounds.size.y)
	zoom = clampf(fit_zoom, MIN_ZOOM, 1.0)
	pan = -bounds.get_center() * zoom
	queue_redraw()


## The area (in model coordinates) the diagram covers: every state plus a
## margin for loops and labels. The model must have at least one state.
func diagram_bounds() -> Rect2:
	var bounds := Rect2(model.states[0].position, Vector2.ZERO)
	for s in model.states:
		bounds = bounds.expand(s.position)
	return bounds.grow(STATE_RADIUS + FIT_MARGIN)


## Zooms by `factor`, keeping the point under the mouse where it is.
func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var anchor := to_model(screen_pos)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	pan = screen_pos - size / 2 - anchor * zoom
	_auto_fit = false
	queue_redraw()


# ---------------------------------------------------------------------------
# Mouse input
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if model == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_drag_id = state_at(mb.position)
					if _drag_id != -1:
						_drag_offset = model.get_state(_drag_id).position - to_model(mb.position)
					else:
						_panning = true
				else:
					_drag_id = -1
					_panning = false
				accept_event()
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_at(mb.position, 1.1)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_at(mb.position, 1 / 1.1)
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_id != -1:
			_auto_fit = false
			model.set_state_position(_drag_id, to_model(mm.position) + _drag_offset)
		elif _panning:
			_auto_fit = false
			pan += mm.relative
			queue_redraw()
		else:
			_set_hover(state_at(mm.position))


func _set_hover(state_id: int) -> void:
	if state_id == _hover_id:
		return
	_hover_id = state_id
	# The mouse cursor changes to a hand over a state, hinting it can be moved.
	mouse_default_cursor_shape = (Control.CURSOR_POINTING_HAND if state_id != -1
		else Control.CURSOR_ARROW)
	queue_redraw()


## The arrow the next clock will follow, as Vector2i(from id, to id), or
## NO_EDGE if there's no current state or its transition is unset.
func active_edge() -> Vector2i:
	if plain or simulator == null or simulator.current_state() == null:
		return NO_EDGE
	var next_id := simulator.next_state_id()
	if model.get_state(next_id) == null:
		return NO_EDGE
	return Vector2i(simulator.current_state_id, next_id)


# ---------------------------------------------------------------------------
# Edges: which arrows exist and what they're labelled
# ---------------------------------------------------------------------------

## One entry per arrow: {"from": id, "to": id, "combos": Array[int],
## "label": String}. Unset transitions don't produce arrows.
func collect_edges() -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	var by_pair: Dictionary[Vector2i, Dictionary] = {}
	for s in model.states:
		for combo in s.transitions.size():
			var next_id := s.transitions[combo].next_id
			if model.get_state(next_id) == null:
				continue
			var pair := Vector2i(s.id, next_id)
			if not by_pair.has(pair):
				by_pair[pair] = {"from": s.id, "to": next_id, "combos": [] as Array[int]}
				edges.append(by_pair[pair])
			by_pair[pair]["combos"].append(combo)
	for e in edges:
		e["label"] = edge_label(e["from"], e["combos"])
	return edges


## The text drawn on an arrow from state `from_id` taken for input `combos`.
func edge_label(from_id: int, combos: Array[int]) -> String:
	var s := model.get_state(from_id)
	var mealy := (model.machine_type == FSMModel.MachineType.MEALY
		and not model.outputs.is_empty())
	# Every input goes this way: say "any" instead of listing them all.
	if combos.size() == model.input_combo_count():
		if not mealy:
			return "any"
		var first := s.transitions[combos[0]].output
		if combos.all(func(c: int) -> bool: return s.transitions[c].output == first):
			return "any/" + model.output_label(first)
	var parts: PackedStringArray = []
	for c in combos:
		var text := model.combo_label(c) if not model.inputs.is_empty() else "any"
		if mealy:
			text += "/" + model.output_label(s.transitions[c].output)
		parts.append(text)
	# Wrap long lists: a few items per line.
	var lines: PackedStringArray = []
	for i in range(0, parts.size(), LABEL_ITEMS_PER_LINE):
		lines.append(", ".join(parts.slice(i, i + LABEL_ITEMS_PER_LINE)))
	return ",\n".join(lines)


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	# Background (in screen coordinates).
	# A plain view leaves the background transparent so render_plain_image()
	# can find the drawn area by its alpha.
	if not plain:
		draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	if model == null:
		return
	if model.states.is_empty():
		_draw_hint("No states yet. Add some in the transition table →", size / 2)
		return

	# From here on, draw in model coordinates.
	draw_set_transform(size / 2 + pan, 0.0, Vector2(zoom, zoom))
	var centre := _states_centre()
	var edges := collect_edges()
	var pairs: Dictionary[Vector2i, bool] = {}
	for e in edges:
		pairs[Vector2i(e["from"], e["to"])] = true

	# Edges first so the state circles cover their ends; labels last so
	# they're always readable. The active edge (and its label) is drawn after
	# the others so it's on top.
	var active := active_edge()
	var labels: Array[Dictionary] = []
	var active_label := {}
	var active_points := PackedVector2Array()
	for e in edges:
		var geometry: Dictionary
		if e["from"] == e["to"]:
			geometry = _loop_geometry(model.get_state(e["from"]).position, centre)
		else:
			var has_reverse := pairs.has(Vector2i(e["to"], e["from"]))
			geometry = _edge_geometry(model.get_state(e["from"]).position,
				model.get_state(e["to"]).position, EDGE_BEND if has_reverse else 0.0)
		var label := {"text": e["label"], "at": geometry["label_at"],
			"dir": geometry["label_dir"]}
		if Vector2i(e["from"], e["to"]) == active:
			active_points = geometry["points"]
			active_label = label
		else:
			_draw_arrow(geometry["points"], _ink(COLOR_EDGE))
			labels.append(label)
	if not active_points.is_empty():
		_draw_arrow(active_points, COLOR_ACTIVE, ACTIVE_LINE_WIDTH)
	_draw_initial_arrow(centre)
	for s in model.states:
		_draw_state(s, active)
	for l in labels:
		_draw_label(l["text"], l["at"], l["dir"], _ink(COLOR_TEXT))
	if not active_label.is_empty():
		_draw_label(active_label["text"], active_label["at"], active_label["dir"],
			COLOR_ACTIVE)

	# Back to screen coordinates for the overlay hint.
	draw_set_transform(Vector2.ZERO)
	if plain:
		return
	_draw_hint("Drag states to move · drag background to pan · wheel to zoom",
		Vector2(size.x / 2, size.y - 12))


## `active` is the active edge (see active_edge()): its source is the current
## state (filled orange) and its target is the next state (orange outline).
func _draw_state(s: FSMState, active: Vector2i) -> void:
	var is_current := not plain and simulator != null and s.id == simulator.current_state_id
	var is_next := s.id == active.y and not is_current
	var fill := COLOR_CURRENT_FILL if is_current else COLOR_STATE_FILL
	var outline := _ink(COLOR_STATE_OUTLINE)
	var outline_width := LINE_WIDTH
	if is_next:
		outline = COLOR_ACTIVE
		outline_width = ACTIVE_LINE_WIDTH
	if s.id == _hover_id or s.id == _drag_id:
		outline = COLOR_STATE_HOVER
	var text_color := COLOR_CURRENT_TEXT if is_current else _ink(COLOR_TEXT)
	var output_color := COLOR_CURRENT_TEXT if is_current else _ink(COLOR_OUTPUT)
	if plain:
		fill = PLAIN_BACKGROUND

	draw_circle(s.position, STATE_RADIUS, fill, true, -1.0, true)
	draw_arc(s.position, STATE_RADIUS, 0, TAU, 64, outline, outline_width, true)
	var max_width := STATE_RADIUS * 2 - 10
	if model.machine_type == FSMModel.MachineType.MOORE and not model.outputs.is_empty():
		_draw_centered_text(s.name, s.position + Vector2(0, -8), max_width,
			NAME_FONT_SIZE, text_color)
		_draw_centered_text(model.output_label(s.moore_output),
			s.position + Vector2(0, 12), max_width, OUTPUT_FONT_SIZE, output_color)
	else:
		_draw_centered_text(s.name, s.position, max_width, NAME_FONT_SIZE, text_color)


## A short arrow pointing into the initial state from outside the diagram.
func _draw_initial_arrow(centre: Vector2) -> void:
	var s := model.get_state(model.initial_state_id)
	if s == null:
		return
	# Come in from the side, 90° round from where the self-loop would be.
	var dir := _outward(s.position, centre).rotated(-PI / 2)
	var tip := s.position + dir * STATE_RADIUS
	var tail := tip + dir * INITIAL_ARROW_LENGTH
	_draw_arrow(PackedVector2Array([tail, tip]), _ink(COLOR_EDGE))


## Draws a polyline ending in an arrowhead at its last point.
func _draw_arrow(points: PackedVector2Array, color: Color,
		width: float = LINE_WIDTH) -> void:
	var tip := points[points.size() - 1]
	var dir := (tip - points[points.size() - 2]).normalized()
	# Stop the line where the arrowhead starts so it doesn't poke through.
	var line := points.duplicate()
	line[line.size() - 1] = tip - dir * ARROW_LENGTH * 0.8
	draw_polyline(line, color, width, true)
	var back := tip - dir * ARROW_LENGTH
	var side := dir.orthogonal() * (ARROW_HALF_WIDTH + width - LINE_WIDTH)
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), color)


## Geometry of an arrow between two different states. `bend` pushes the
## middle of the curve sideways (0 = straight).
## Returns {"points", "label_at", "label_dir"}.
func _edge_geometry(from_pos: Vector2, to_pos: Vector2, bend: float) -> Dictionary:
	var dir := (to_pos - from_pos).normalized()
	if dir == Vector2.ZERO:  # two states in exactly the same spot
		dir = Vector2.RIGHT
	var normal := dir.orthogonal()
	# A quadratic Bézier curve: starts at one state, ends at the other, and is
	# pulled toward `control` in between.
	var control := (from_pos + to_pos) / 2 + normal * bend
	# Start/end on the circles' edges, aimed at the control point.
	var start := from_pos + (control - from_pos).normalized() * STATE_RADIUS
	var end := to_pos + (control - to_pos).normalized() * STATE_RADIUS
	# Same curve as a cubic Bézier (the form _bezier_points() draws).
	var c1 := start + (control - start) * 2.0 / 3.0
	var c2 := end + (control - end) * 2.0 / 3.0
	return {
		"points": _bezier_points(start, c1, c2, end),
		"label_at": _bezier_point(start, c1, c2, end, 0.5),
		"label_dir": normal,
	}


## Geometry of a self-loop: a teardrop leaving and re-entering the circle on
## the side facing away from the diagram's centre.
func _loop_geometry(pos: Vector2, centre: Vector2) -> Dictionary:
	var angle := _outward(pos, centre).angle()
	var spread := 0.45  # radians either side of `angle`
	var start := pos + Vector2.from_angle(angle - spread) * STATE_RADIUS
	var end := pos + Vector2.from_angle(angle + spread) * STATE_RADIUS
	var c1 := pos + Vector2.from_angle(angle - spread * 1.6) * STATE_RADIUS * 2.6
	var c2 := pos + Vector2.from_angle(angle + spread * 1.6) * STATE_RADIUS * 2.6
	return {
		"points": _bezier_points(start, c1, c2, end),
		"label_at": _bezier_point(start, c1, c2, end, 0.5),
		"label_dir": Vector2.from_angle(angle),
	}


## A text label beside `at`, pushed out in direction `dir` far enough that its
## box doesn't sit on the line, with a translucent background.
func _draw_label(text: String, at: Vector2, dir: Vector2, color: Color) -> void:
	var font := get_theme_default_font()
	var lines := text.split("\n")
	var line_height := font.get_height(LABEL_FONT_SIZE)
	var box := Vector2(0, line_height * lines.size())
	for line in lines:
		box.x = maxf(box.x, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1,
			LABEL_FONT_SIZE).x)
	var distance := 6.0 + absf(dir.x) * box.x / 2 + absf(dir.y) * box.y / 2
	var top_left := at + dir * distance - box / 2
	draw_rect(Rect2(top_left, box).grow(2),
		PLAIN_LABEL_BACKGROUND if plain else COLOR_LABEL_BACKGROUND)
	for i in lines.size():
		var baseline := top_left.y + font.get_ascent(LABEL_FONT_SIZE) + i * line_height
		draw_string(font, Vector2(top_left.x, baseline), lines[i],
			HORIZONTAL_ALIGNMENT_CENTER, box.x, LABEL_FONT_SIZE, color)


## Draws one line of text centred on `centre`, shrinking the font if needed
## to fit within `max_width` (for long state names).
func _draw_centered_text(text: String, centre: Vector2, max_width: float,
		font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	while width > max_width and font_size > 8:
		font_size -= 1
		width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# draw_string positions the text's baseline, not its middle.
	var baseline := centre.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2
	draw_string(font, Vector2(centre.x - width / 2, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## `color` on screen, or black in a plain view.
func _ink(color: Color) -> Color:
	return PLAIN_INK if plain else color


## Faint help text centred horizontally on `at` (screen coordinates).
func _draw_hint(text: String, at: Vector2) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size() - 2
	draw_string(font, Vector2(0, at.y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x,
		font_size, COLOR_HINT)


# ---------------------------------------------------------------------------
# Copying the diagram as an image
# ---------------------------------------------------------------------------

## Renders the whole diagram, black on white and without simulation
## highlighting, and returns it as an Image (null if there are no states).
##
## A coroutine (see FSMClipboard.render_control()): callers must `await` it.
func render_plain_image() -> Image:
	if model == null or model.states.is_empty():
		return null
	# Render with room to spare (long labels can stick out past the bounds)
	# on a transparent background, then crop to what was actually drawn.
	# (Anything translucent would come out too dark, because it's blended over
	# transparent *black*; so plain views only draw opaque colours.)
	var bounds := diagram_bounds().grow(FIT_MARGIN * 2)
	var copy := FSMGraphView.new()
	copy.plain = true
	copy.model = model  # just reads it; no bind(), so no signal connections
	copy.zoom = 1.0
	copy.pan = -bounds.get_center()
	copy._auto_fit = false
	var drawn := await FSMClipboard.render_control(copy, self,
		Vector2i(bounds.size.ceil()), true)
	drawn.convert(Image.FORMAT_RGBA8)
	var used := drawn.get_used_rect()  # the smallest box holding non-transparent pixels
	var image := Image.create_empty(used.size.x + PLAIN_PADDING * 2,
		used.size.y + PLAIN_PADDING * 2, false, Image.FORMAT_RGBA8)
	image.fill(PLAIN_BACKGROUND)
	image.blend_rect(drawn, used, Vector2i(PLAIN_PADDING, PLAIN_PADDING))
	return image


## Copies the plain diagram to the system clipboard as a PNG, emitting
## `copy_failed` with the reason if that isn't possible.
func copy_to_clipboard() -> void:
	var image := await render_plain_image()
	if image == null:
		copy_failed.emit("There's no diagram to copy yet: add some states first.")
		return
	var error := FSMClipboard.copy_image(image)
	if not error.is_empty():
		copy_failed.emit(error)


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

## Average position of all states.
func _states_centre() -> Vector2:
	var sum := Vector2.ZERO
	for s in model.states:
		sum += s.position
	return sum / model.states.size()


## Unit vector from the diagram's centre towards `pos` (up if they coincide).
static func _outward(pos: Vector2, centre: Vector2) -> Vector2:
	var dir := pos - centre
	return dir.normalized() if dir.length() > 1.0 else Vector2.UP


## Points along a cubic Bézier curve, for draw_polyline().
static func _bezier_points(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		segments: int = 24) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments + 1:
		points.append(_bezier_point(p0, p1, p2, p3, float(i) / segments))
	return points


## One point on a cubic Bézier curve (t from 0 at p0 to 1 at p3).
## Godot's built-in Vector2.bezier_interpolate() does the maths.
static func _bezier_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		t: float) -> Vector2:
	return p0.bezier_interpolate(p1, p2, p3, t)
