# Godot primer

A reference for the Godot concepts used in this project, each with a pointer
to where the project uses it. For a guided walk through the code in a
sensible order, follow [TOUR.md](TOUR.md); come here when you want more
detail on one idea.

Godot version: **4.7**. Language: **GDScript**. The official docs
(<https://docs.godotengine.org>) are excellent. Press **F1** in the editor to
search the built-in class reference.

**Contents:**
[Nodes and the scene tree](#nodes-and-the-scene-tree) ·
[Scenes](#scenes) ·
[Scripts](#scripts) ·
[GDScript essentials](#gdscript-essentials) ·
[Lifecycle callbacks](#lifecycle-callbacks) ·
[Signals](#signals) ·
[Object types and memory](#object-types-and-memory) ·
[Resources](#resources) ·
[Files and paths](#files-and-paths) ·
[UI: Controls and containers](#ui-controls-and-containers) ·
[UI: Themes and StyleBoxes](#ui-themes-and-styleboxes) ·
[UI: Dialogs](#ui-dialogs) ·
[Custom drawing](#custom-drawing) ·
[Input](#input) ·
[Tweens](#tweens) ·
[Coroutines and await](#coroutines-and-await) ·
[Debugging](#debugging) ·
[Testing with GUT](#testing-with-gut) ·
[Plugins](#plugins)

---

## Nodes and the scene tree

A **node** is the basic building block: a Button, a Label, a container, a
sprite, a timer. Each node type adds features to the one it inherits from
(`Button` → `BaseButton` → `Control` → `CanvasItem` → `Node`).

Nodes form a **tree**: each node has one parent and any number of children.
The running app's tree, the **SceneTree**, starts at a root `Window`. A node
only runs its callbacks (`_ready`, `_draw`, input...) while it's *in* the tree.

```gdscript
var label := Label.new()   # create (not in the tree yet)
label.text = "hi"
add_child(label)           # now it's in the tree, a child of this node
label.queue_free()         # delete it at the end of this frame
```

Finding nodes: `$Child/Grandchild` (path from this node), `%UniqueName`
(any node in this scene marked "Access as Unique Name"), `get_parent()`,
`get_children()`.

*In this project:* building rows in [port_editor.gd](../scenes/port_editor.gd)
(`_rebuild_rows`), `hide()` + `queue_free()` in `_clear_rows`.

## Scenes

A **scene** is a tree of nodes saved to a `.tscn` file, a readable text
format. Scenes are reusable: `main.tscn` contains an **instance** of
`toolbar.tscn`, which appears as one node (with a clapperboard icon) that
contains the whole toolbar. Edit the toolbar scene, and every instance
changes. Think of a sub-module instantiated in a parent module.

From code: `load("res://scenes/toolbar.tscn").instantiate()` returns the root
node of a fresh copy (the tests do this).

The **main scene** (`run/main_scene` in `project.godot`) is what runs on F5.

*In this project:* [main.tscn](../scenes/main.tscn) instancing
`toolbar.tscn`, `port_editor.tscn`, `transition_table.tscn`,
`sim_panel.tscn`.

## Scripts

A script is attached to one node and **extends** that node's type:

```gdscript
class_name FSMToolbar      # optional: a global name for this type
extends HBoxContainer      # this script IS an HBoxContainer, plus more
```

`class_name` lets other scripts use the type by name (`FSMToolbar`,
`FSMModel.new()`) and makes it show up in F1 help. Comments starting with
`##` become that help text.

A script doesn't have to be attached to a scene node: `FSMBitToggle.new()`
creates a Button with the script's behaviour, entirely from code.

## GDScript essentials

Python-like syntax, indentation-based.

```gdscript
const MAX_INPUT_BITS := 4                 # constant
var width: int = 1                        # typed variable
var name := "S0"                          # := infers the type (String)
var values: Array[int] = []               # typed array: ints only
var edits: Dictionary[int, LineEdit] = {} # typed dictionary (Godot 4.4+)
enum MachineType { MOORE, MEALY }         # named integer constants

func max_value() -> int:                  # typed return
	return (1 << width) - 1

static func format_value(value: int, width: int) -> String: ...  # no instance needed
static var load_error: String = ""        # one variable shared by the class
```

- **`@export`** puts a property in the Inspector and makes it part of the
  saved data (for Resources and scenes).
- **`@onready var x = %X`** runs the initialiser just before `_ready()`,
  when child nodes exist.
- **Setters:** `var value: int = 0:` followed by an indented `set(v): ...`
  block runs code on every assignment (see
  [bit_toggle.gd](../scenes/cells/bit_toggle.gd)).
- **Lambdas:** `func(x: int) -> void: print(x)` makes an anonymous function
  (a `Callable`) that captures the local variables it uses.
  `button.pressed.connect(func() -> void: model.remove_input(i))` remembers
  that row's `i`.
- **Callables:** functions are values: `button.pressed.connect(_on_pressed)`
  passes the method itself, and `signal_name.emit` is a Callable too.
- `is` checks a type (`if event is InputEventMouseButton`); `as` casts,
  giving `null` if the cast fails.
- **Underscore prefix:** `_helper()` is a convention for "private", and
  `_unused_param` tells Godot not to warn about an unused parameter.
- `match` is like `switch`.

Static typing is optional in GDScript, but this project uses it everywhere.
The editor then catches type errors before you run, and autocompletes better.

## Lifecycle callbacks

Functions Godot calls on your node. Only define the ones you need.

| Callback | When | Used in |
|---|---|---|
| `_init()` | object created (`.new()`), before it's in the tree | `bit_toggle.gd`, `fsm_simulator.gd` |
| `_ready()` | node and all its children entered the tree (once) | every view: connect signals, setup |
| `_process(delta)` | every frame | not used yet (see animation in ARCHITECTURE) |
| `_draw()` | Godot needs this CanvasItem's drawing | `graph_view.gd` |
| `_gui_input(event)` | input aimed at this Control | `graph_view.gd` |
| `_notification(what)` | catch-all engine notifications | `graph_view.gd` (resize, mouse exit) |

## Signals

Godot's observer pattern, and the backbone of this project.

```gdscript
signal state_renamed(state_id: int)          # declare
state_renamed.emit(id)                       # fire: calls every connected function
model.state_renamed.connect(_on_state_renamed)     # listen
model.state_renamed.disconnect(_on_state_renamed)  # stop listening
```

- Emitting is **synchronous**: `emit()` calls each connected function right
  away, in connection order, then returns.
- The emitter doesn't know or care who's listening, so components stay
  independent. Built-in nodes have many signals already: `Button.pressed`,
  `OptionButton.item_selected(index)`, `LineEdit.text_submitted(text)`,
  `SpinBox.value_changed(value)`.
- You can connect in the editor (Signals tab, saved in the `.tscn`) or in
  code (`connect()`). This project connects in code so every connection is
  visible in the scripts.
- **"Call down, signal up":** parents call methods on their children;
  children emit signals that parents listen to. See `toolbar.gd`'s
  `save_requested`, handled by `main.gd`.
- A function connected to a signal must accept its arguments. A trick used
  here: default values (`func _on_model_changed(_a = null, _b = null)`) let
  one handler accept signals with 0, 1 or 2 arguments.

*In this project:* the model's signals are listed in
[ARCHITECTURE.md](ARCHITECTURE.md#signals-who-emits-who-listens).

## Object types and memory

| Base type | Freed when | In scene tree? | Saved to disk? | Used for |
|---|---|---|---|---|
| `Node` (and Control etc.) | you call `queue_free()` (or its parent is freed) | yes | as part of a scene | all UI |
| `RefCounted` | nothing references it any more (automatic) | no | no | `FSMSimulator`, `FSMUi` |
| `Resource` (a RefCounted) | automatic, same as above | no | yes, `.tres`/`.res` | `FSMModel`, `FSMState`, `FSMTransition`, `FSMPort` |

Nodes that are removed from the tree but never freed are "orphans" (a memory
leak). GUT can warn about them.

## Resources

A Resource is a data object that Godot knows how to save, load, and show in
the Inspector. Its `@export` properties, including nested Resources and
typed arrays of them, are serialised automatically:

```gdscript
ResourceSaver.save(model, "user://my_fsm.tres")        # write
var m := ResourceLoader.load(path) as FSMModel          # read back
```

A `.tres` file is readable text: `[sub_resource]` blocks for nested objects,
then a `[resource]` block for the main one. Built-in examples of Resources
are textures, fonts, StyleBoxes and Themes.

⚠️ **Security:** a `.tres` can contain or reference *scripts*, which run when
loaded. Only load `.tres` files you trust, or check them first as
[fsm_model.gd](../scripts/model/fsm_model.gd)'s `_check_file_is_safe()` does.

## Files and paths

- `res://`: the project folder (read-only in an exported app).
- `user://`: a per-user writable folder for this app (on Linux,
  `~/.local/share/godot/app_userdata/<project name>/`).
- Absolute paths such as `/home/you/fsm.tres` also work with `FileAccess`,
  `ResourceSaver`, and a `FileDialog` whose *access* is *File System*.
- `.tscn` = scene, `.tres` = text resource, `.gd` = script, `.gd.uid` =
  the script's stable id (commit these), `.import` = import settings for
  assets like `icon.svg`. The `.godot/` folder is a cache: never commit it
  (it's in `.gitignore`).
- `project.godot`: project settings (edit via *Project → Project Settings*).

## UI: Controls and containers

Every UI node is a **Control**: it has a rectangle (`position`, `size`),
can receive mouse/keyboard input, and has a tooltip.

**Containers** are Controls that position their children for you:

| Container | Lays children out... | In this project |
|---|---|---|
| `VBoxContainer` / `HBoxContainer` | in a column / row | most panels |
| `GridContainer` | in a grid with N `columns` | the transition table |
| `MarginContainer` | with padding around | window margin |
| `PanelContainer` | with a background StyleBox behind | every table cell; the root |
| `HSplitContainer` / `VSplitContainer` | two, with a draggable divider | graph vs table; top vs sim panel |
| `ScrollContainer` | one, scrollable | the table |

Inside a container, a child's **size flags** say how it uses space: *Fill*
(stretch to the space given), *Expand* (ask for spare space),
*Shrink Center* (keep minimum size, centred). `custom_minimum_size` sets a
minimum. Outside containers, **anchors** pin edges to the parent (the root's
"Full Rect" preset fills the window).

A hidden child (`visible = false`) takes no space in a container.

## UI: Themes and StyleBoxes

A **Theme** provides fonts, colours, sizes and StyleBoxes for all Controls.
This project uses the default theme and overrides items per node:

```gdscript
label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
panel.add_theme_stylebox_override("panel", my_stylebox)
```

In a `.tscn` these look like `theme_override_colors/font_color = ...`.

A **StyleBoxFlat** is a box with background colour, border and rounded
corners. The table highlights a cell by giving its PanelContainer a
different StyleBoxFlat ([transition_table.gd](../scenes/transition_table.gd),
`_apply_highlight`).

## UI: Dialogs

`FileDialog`, `AcceptDialog` (a message with OK) and `ConfirmationDialog`
(OK/Cancel) are **Windows**. Put them in the scene hidden, and show them with
`popup_centered()`. They report back with signals: `file_selected(path)`,
`confirmed`. See [main.gd](../scenes/main.gd).

## Custom drawing

Any CanvasItem (Controls included) can draw itself by overriding `_draw()`:

```gdscript
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	draw_circle(Vector2(50, 50), 20, Color.ORANGE)
	draw_string(get_theme_default_font(), Vector2(10, 90), "S0")
```

Godot calls `_draw()` once and **caches** the result. Call
`queue_redraw()` when your data changes, and `_draw()` runs again before the
next frame (calling it many times per frame is fine: it only redraws once).
`draw_set_transform(offset, rotation, scale)` changes the coordinate system
for everything drawn after it, which is how the graph does pan and zoom.
Text is positioned by its **baseline**, not its centre; use
`Font.get_string_size()` / `get_ascent()` to centre it.

*In this project:* all of [graph_view.gd](../scenes/graph_view.gd).

## Input

Input arrives as **InputEvent** objects: `InputEventMouseButton` (press,
release, wheel), `InputEventMouseMotion` (with `relative` movement),
`InputEventKey`, and so on. A Control gets events aimed at it in
`_gui_input(event)`; call `accept_event()` to stop them from being passed on.
`mouse_default_cursor_shape` changes the cursor over a Control.

**Shortcuts:** `button.shortcut = some_shortcut` makes a key press click the
button, but only if the focused control didn't consume the key first.
`command_or_control_autoremap` makes Ctrl+S become Cmd+S on macOS.

Tests can build events and call `_gui_input()` directly, as
[test_graph_view.gd](../test/test_graph_view.gd) does.

## Tweens

A Tween animates properties over time:

```gdscript
var tween := create_tween()        # bound to this node
tween.tween_property(node, "modulate", Color.WHITE, 0.6)  # over 0.6 s
tween.tween_property(node, "position", target, 0.3) \
	.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
```

Steps run one after another by default (`tween.set_parallel()` runs them
together). `tween_method(callable, from, to, duration)` animates by calling a
function with interpolated values, useful when the thing you're animating
isn't a property.

*In this project:* `FSMUi.flash_error()` in [ui_helpers.gd](../scenes/ui_helpers.gd).

## Coroutines and await

`await` pauses the current function until a signal fires, then resumes it:

```gdscript
await get_tree().process_frame   # wait for the next frame
await get_tree().create_timer(1.0).timeout   # wait one second
```

The *caller* doesn't wait (unless it also uses `await` on the call). After
an `await`, the world may have changed: check that nodes still exist
(`is_instance_valid(node)`).

*In this project:* `_scroll_into_view()` in
[transition_table.gd](../scenes/transition_table.gd).

## Debugging

- `print(a, b)` writes to the **Output** panel; `push_error()` /
  `push_warning()` also show in the **Debugger → Errors** tab.
- **Breakpoints:** click in the script editor's gutter. When hit, the
  **Debugger** panel shows the call stack and variables; step with *Step
  Into* / *Step Over*, then *Continue*. The `breakpoint` keyword in code does
  the same.
- **Remote scene tree:** while the app runs, click **Remote** at the top of
  the Scene dock to browse the live nodes (including ones created by code)
  and inspect their properties.

## Testing with GUT

[GUT](https://github.com/bitwes/Gut) is a unit-testing plugin
(`addons/gut/`). A test script `extends GutTest`; each `func test_...()`
is a test.

```gdscript
extends GutTest

func before_each() -> void:     # runs before every test
	model = FSMModel.create_default()

func test_default_names() -> void:
	assert_eq(model.add_state().name, "S0")
```

Useful helpers: `assert_eq/ne/true/false/null/not_null`,
`assert_almost_eq`, `assert_string_contains`, `assert_is(obj, Class)`,
`watch_signals(obj)` + `assert_signal_emitted(obj, "name")` /
`assert_signal_emit_count`, `add_child_autofree(node)` (put a node in the
tree for this test, freed afterwards), `await wait_process_frames(n)`.

Run from a terminal with `godot --headless -s addons/gut/gut_cmdln.gd`
(configured by `.gutconfig.json`), or from the **GUT** panel in the editor.

## Plugins

Addons live in `addons/<name>/` and are enabled in *Project → Project
Settings → Plugins* (saved under `[editor_plugins]` in `project.godot`). You
can find them in the editor's **AssetLib** tab or on
<https://godotengine.org/asset-library>. This project uses one, GUT. Why
others weren't used is in [ARCHITECTURE.md](ARCHITECTURE.md#why-no-other-plugins).
