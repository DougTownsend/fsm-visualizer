# A guided tour of FSM Designer (and of Godot)

This tour teaches Godot by walking through this project in an order that
builds up one idea at a time. Each stop says **what to open**, **what to
notice**, which **Godot concepts** it introduces, and ends with a small
**Try it** exercise. Most exercises take a few minutes.

You don't need any Godot experience. Some programming experience helps, and
the FSM itself assumes you know what a Mealy/Moore machine is.

Two companion documents:

- [GODOT_PRIMER.md](GODOT_PRIMER.md): a reference for every Godot concept
  mentioned here. When the tour says *(primer: Signals)*, look it up there
  for more detail.
- [ARCHITECTURE.md](ARCHITECTURE.md): the big-picture design: data flow,
  file map, every signal and who listens to it, and how to extend the app.

**The route:**

| Stop | Topic | Main files |
|---|---|---|
| 0 | Use the app | *(none)* |
| 1 | The Godot editor | `project.godot` |
| 2 | Nodes, scenes and scripts: the toolbar | `scenes/toolbar.tscn`, `toolbar.gd` |
| 3 | Building a layout from scenes | `scenes/main.tscn` |
| 4 | Data as Resources | `scripts/model/fsm_port.gd`, `fsm_transition.gd`, `fsm_state.gd` |
| 5 | The model and signals | `scripts/model/fsm_model.gd` |
| 6 | Watching signals with the debugger | *(debugger)* |
| 7 | The simulator | `scripts/model/fsm_simulator.gd` |
| 8 | Tests with GUT | `test/*.gd` |
| 9 | Tying it together: `main.gd` | `scenes/main.gd` |
| 10 | Nodes built from code | `scenes/cells/*.gd`, `scenes/ui_helpers.gd` |
| 11 | Building UI in code: the port editor | `scenes/port_editor.gd` |
| 12 | The transition table | `scenes/transition_table.gd` |
| 13 | The simulation panel | `scenes/sim_panel.gd` |
| 14 | Custom drawing and mouse input: the graph | `scenes/graph_view.gd` |
| 15 | Saving, loading, and not trusting files | `fsm_model.gd` (save/load section) |
| 16 | Where to go next: animation | *(your code)* |

> **Before you start experimenting:** make a git commit of the project as it
> is (`git add -A && git commit -m "Before tour"`). Then after any exercise,
> `git restore .` puts everything back.

---

## Stop 0: Use the app

**Goal:** know what the app does before looking at how.

Run it from the project folder with `godot --path .`, or open the project in
the Godot editor and press **F5**.

Build the classic **"11" sequence detector**, a Moore machine that outputs 1
once it has seen two 1s in a row:

1. Press **+ Add State** three times. You get S0, S1, S2 on the graph.
2. Click S2's name in the table, type `FOUND` and press Enter. The dropdowns
   and the graph update.
3. Fill in the table:

   | State | in0 = 0 | in0 = 1 | out0 |
   |---|---|---|---|
   | S0 | S0 | S1 | 0 |
   | S1 | S0 | FOUND | 0 |
   | FOUND | S0 | FOUND | **1** (click the 0) |

4. In **Simulation**, click the `in0` value to make it 1. Watch the orange arrow
   in the graph and the orange cell in the table: they show where the next
   clock goes. Press **Clock** (or the **C** key) a few times and watch the
   history fill up.
5. Switch **Machine type** to **Mealy**. Each cell becomes `next / output`.
6. Drag a state around the graph, then press **Arrange**.
7. **Save…** the machine, then open the `.tres` file in a text editor. You'll
   come back to this file at Stop 4.

---

## Stop 1: The Godot editor

**Goal:** find your way around the editor.

Open Godot, click **Import** (or pick it from the project list) and choose this
folder's `project.godot`. The main areas:

- **Scene dock** (top left): the tree of *nodes* in the scene you're editing.
- **FileSystem dock** (bottom left): the project's files. `res://` means "the
  project folder".
- **Inspector** (right): the properties of the selected node. Next to it are
  the **Signals** and **Groups** tabs.
- **Main view** (centre): the 2D view of the current scene, or the **Script**
  editor. Switch with the tabs along the top.
- **Bottom panel**: **Output** (where `print()` output goes), **Debugger**, and
  **GUT** (the test runner plugin this project uses).

Useful keys: **F5** runs the project, **F6** runs only the scene you're
editing, **F8** stops. In the script editor, **Ctrl+click** a name jumps to
its definition, and **F1** opens the built-in documentation. Our own classes
appear in that documentation too, because of their `##` comments.

Also open `project.godot` in a text editor. It's the project's settings file.
Look for `run/main_scene` (what F5 runs), the window size, and
`[editor_plugins]` (GUT is enabled there).

**Concepts:** `res://`, project settings. *(primer: Files and paths)*

**Try it:** In the editor, open **Project → Project Settings**, find
*Display → Window → Size*, and notice it matches `project.godot`. Change
the viewport width, run the app, then change it back.

---

## Stop 2: Nodes, scenes and scripts: the toolbar

**Goal:** understand Godot's basic building blocks using the simplest part of
the UI.

Double-click `scenes/toolbar.tscn` in the FileSystem dock.

**What to notice:**

- The Scene dock shows a **tree of nodes**: an `HBoxContainer` called
  `Toolbar` with children `TypeLabel`, `TypeOption`, `AddStateButton`, and so
  on. Every piece of a Godot app is a node, and every node has one parent.
- A **scene** (`.tscn`) is a saved tree of nodes that you can reuse. The
  toolbar is one scene, and `main.tscn` places a copy of it.
- The root node has a **script** attached (the scroll icon): `toolbar.gd`.
  A script *extends* the node's type, so `toolbar.gd` says
  `extends HBoxContainer` and adds behaviour to that node.
- Some nodes show a **%** icon. Right-click one: "Access as Unique Name" is
  ticked. That lets the script find it as `%TypeOption`, wherever it sits in
  the tree.
- Open `toolbar.tscn` in a text editor as well. It's a readable text file.
  Each `[node]` block is one node, and `parent="."` means "child of the root".

Now read [scenes/toolbar.gd](../scenes/toolbar.gd):

- `@onready var type_option: OptionButton = %TypeOption` fetches the node
  once the scene is ready. Before that, the children don't exist yet.
- `_ready()` is called once the node and all its children are in the tree.
  That's where it **connects signals**:
  `add_state_button.pressed.connect(_on_add_state_pressed)` means "when this
  button emits `pressed`, call my function".
- The toolbar also declares its own signals (`save_requested`, ...). It
  doesn't know how to show a file dialog, so it announces the request and lets
  its parent handle it. This is Godot's **"call down, signal up"** pattern.
- `bind()` is not a Godot function; it's this project's convention. Every
  view has a `bind(model, simulator)` that main.gd calls (Stop 9).

**Concepts:** Node, scene, script, `extends`, `_ready`, `@onready`, `%Name`,
signals, `connect`. *(primer: Nodes and the scene tree, Scenes, Scripts,
Signals, Lifecycle callbacks)*

**Try it: connect a signal in the editor.**
1. In `toolbar.tscn`, right-click `Toolbar` → **Add Child Node** → `Button`.
   In the Inspector, set its **Text** to `Hello`.
2. With the button selected, open the **Signals** tab (next to Inspector),
   double-click `pressed()`, choose the `Toolbar` node and press **Connect**.
   Godot adds a `_on_button_pressed()` function to `toolbar.gd`.
3. Make it `print("hello from ", name)`, run with **F5**, click the button, and
   look in the **Output** panel.
4. Notice the connection is saved in `toolbar.tscn` (a `[connection ...]`
   line). This project connects in code instead so you can read every
   connection in the script, but both ways work the same.
5. `git restore .` to undo.

---

## Stop 3: Building a layout from scenes

**Goal:** see how the whole window is put together, and how containers do
layout for you.

Open `scenes/main.tscn`. Its tree:

```
Main (PanelContainer, main.gd)
└─ Margin (MarginContainer)
   └─ Layout (VBoxContainer)
      ├─ Toolbar            ← an instance of toolbar.tscn
      └─ VSplit (VSplitContainer)
         ├─ HSplit (HSplitContainer)
         │  ├─ GraphView (Control, graph_view.gd)
         │  └─ RightPanel (VBoxContainer)
         │     ├─ PortEditor        ← instance of port_editor.tscn
         │     ├─ HSeparator
         │     └─ TableScroll (ScrollContainer)
         │        └─ TransitionTable ← instance of transition_table.tscn
         └─ SimPanel        ← instance of sim_panel.tscn
FileDialog, ConfirmNewDialog, MessageDialog  (hidden pop-up windows)
```

**What to notice:**

- **Instances:** `Toolbar`, `PortEditor` and the others have a clapperboard
  icon. Each is a whole scene placed as one node. Click the icon to open that
  scene. It's like placing a sub-module in a schematic.
- **Containers** position their children for you: a `VBoxContainer` stacks
  them vertically, `HSplitContainer` puts two side by side with a draggable
  divider, `MarginContainer` adds padding, and `ScrollContainer` scrolls
  whatever is too big.
- **Size flags** (Inspector → *Layout → Container Sizing*) tell a container
  how to treat each child: *Expand* means "take spare space". `VSplit` expands
  vertically, which is why it fills the window under the toolbar.
- **Anchors** (the `Main` node's *Layout → Anchors Preset: Full Rect*) make the
  root fill the whole window when it's resized.

**Concepts:** instancing, Control, containers, size flags, anchors.
*(primer: UI: Controls and containers)*

**Try it:** Select `SimPanel` and change its *Custom Minimum Size* y from 190
to 300, then press **F6** to run just this scene. Then select `RightPanel`
and turn off *Expand* in its horizontal size flags. What happens to the
split? Undo both.

---

## Stop 4: Data as Resources

**Goal:** see how the FSM is stored, and why saving it is nearly free.

Read, in this order:
[fsm_port.gd](../scripts/model/fsm_port.gd) →
[fsm_transition.gd](../scripts/model/fsm_transition.gd) →
[fsm_state.gd](../scripts/model/fsm_state.gd).

**What to notice:**

- `class_name FSMPort` makes a global type name, so any script can write
  `FSMPort.new()` or `var p: FSMPort`.
- They all `extends Resource`. A **Resource** is Godot's data object: it
  isn't in the scene tree, and it can be **saved to and loaded from disk
  automatically**.
- `@export` marks the properties that get saved (and shown in the Inspector).
- Static typing: `var width: int = 1`, `Array[int]`, `-> int`. GDScript
  works without types, but with them the editor catches mistakes and
  autocompletes better. This project types everything.
- **States are referred to by `id`, never by name.** A transition stores
  `next_id`, so renaming a state touches nothing else. Similar in spirit to
  how a netlist refers to nets.
- Each state owns its transitions: `transitions[combo]`, one per table column.

Now open the `.tres` file you saved in Stop 0 in a text editor. You'll see
one `[sub_resource]` block per port, transition and state, then a `[resource]`
block for the FSMModel. Each block is exactly those `@export` variables.

**Concepts:** Resource, `class_name`, `@export`, typed variables and arrays.
*(primer: Resources, GDScript essentials)*

**Try it:** In the saved `.tres`, change a state's `name = "S1"` to
`name = "BUSY"` and **Load…** it in the app. Then change it to the same name
as another state and load again. You'll get a clear error (Stop 15 explains
where it comes from).

---

## Stop 5: The model and signals

**Goal:** understand the heart of the app. This is the most important stop.

Read [fsm_model.gd](../scripts/model/fsm_model.gd), top to bottom. It's long
but regular.

**What to notice:**

- **It's the single source of truth.** The table, graph and simulator never
  talk to each other. They all talk to the model:

  ```
  table ──calls──▶ model.set_next_state(...) ──emits──▶ transition_changed
                                                         ├─▶ table updates that cell
                                                         ├─▶ graph redraws
                                                         └─▶ simulator emits `updated`
  ```

- **Signals** are declared at the top (`signal state_renamed(state_id: int)`)
  and fired with `state_renamed.emit(id)`. The model has no idea who is
  listening. That's what keeps the views independent of each other.
- The signals are **fine-grained on purpose.** `structure_changed` means
  "rebuild everything" (states added/removed, ports changed, Mealy/Moore
  switched). The others (`state_renamed`, `transition_changed`, ...) mean
  "patch one thing". That's why the text box you're typing a name into
  doesn't get destroyed and rebuilt under your cursor.
- **Input combinations** ("combos") are how columns are numbered: all
  inputs concatenated, first input most significant, just like Verilog
  `{in0, mode}`. See `combo_to_values()` / `values_to_combo()`.
- `_remap_transitions()` keeps your table intact when you change inputs.
  Read its comment for the rules.
- The rule at the top: **change data only through the model's methods.**
  They keep everything consistent and emit the right signals.

**Concepts:** signals (declare/emit/connect), `enum`, `static func`,
`const`. *(primer: Signals, GDScript essentials)*

**Try it:** Change `MAX_INPUT_BITS` from 4 to 5, run the app, and set in0
to 5 bits. The port editor's readout and the table (32 columns) both follow,
because they read the constant rather than hard-coding 4. Undo it.

---

## Stop 6: Watching signals with the debugger

**Goal:** *see* the model → signal → view flow happen, and learn the
debugger.

1. Open `fsm_model.gd` in Godot's script editor and find `add_state()`.
2. Click in the gutter left of the line `structure_changed.emit()` inside
   `add_state()` to set a **breakpoint** (a red dot).
3. Press **F5** and click **+ Add State** in the running app. The game pauses
   and the editor jumps to the breakpoint.
4. Look at the **Debugger → Stack Frames** list. It shows how you got here:
   the button's lambda in `transition_table.gd` called `add_state()`.
5. Press **Step Into** a few times. You'll step from `emit()` straight into
   the *listeners*: `FSMSimulator._on_structure_changed`, then
   `FSMToolbar._refresh`, then `FSMPortEditor._refresh`,
   `FSMGraphView._on_structure_changed`, `FSMTransitionTable._rebuild`...
   Emitting a signal is just calling each connected function in turn.
6. Look at the **Members/Locals** panel to inspect variables. Then press
   **Continue** and remove the breakpoint.

While the app is running, click **Remote** at the top of the Scene dock.
This is the *live* scene tree, including all the table cells created by
code. Click a node to see its live properties in the Inspector.

**Concepts:** breakpoints, stepping, call stack, remote scene tree.
*(primer: Debugging)*

**Try it:** Put a breakpoint in `FSMSimulator.clock()`, press Clock in the
app, and check `current_state_id` and `input_values` in the Locals panel
before stepping over the line that changes `current_state_id`.

---

## Stop 7: The simulator

**Goal:** see how the running state is kept separate from the machine's
definition.

Read [fsm_simulator.gd](../scripts/model/fsm_simulator.gd).

**What to notice:**

- It `extends RefCounted`: a plain object that frees itself when nothing
  refers to it any more. It's not saved (not a Resource) and not in the scene
  tree (not a Node). *(primer: Object types and memory)*
- It holds only simulation state: `current_state_id`, `input_values`,
  `cycle`, `history`.
- `set_input()` does **not** change state. It only changes which transition
  is *active*, which is why the highlight moves as soon as you flip an input.
  `clock()` is the rising edge.
- In `_init` it connects to the model's signals, so it can recover if you
  delete the current state, and so it can tell the views "something you
  display changed" by emitting its single `updated` signal.
- Before the first clock, the current state follows the initial state
  (`_on_initial_state_changed`).

**Try it:** Make `reset()` also set every input back to 0
(`input_values.fill(0)`). Run the tests (next stop) and see which test
disagrees with you, and read *why* it expects what it does. Then decide
which behaviour you prefer.

---

## Stop 8: Tests with GUT

**Goal:** learn to check your changes automatically.

This project uses the **GUT** plugin (Godot Unit Test), in `addons/gut/`.
Tests are in `test/`, and each file `extends GutTest`. Every function
starting with `test_` is one test.

Run them:

- **Terminal:** `godot --headless -s addons/gut/gut_cmdln.gd` (settings in
  `.gutconfig.json`).
- **Editor:** open the **GUT** panel at the bottom and press **Run All**. (If
  it finds no tests, add `res://test/` to the directories in its settings.)

Read in this order:

1. [test_fsm_simulator.gd](../test/test_fsm_simulator.gd): the "11"
   detector as a test. `_run([1, 1, 1, 0, 1, 1])` checks the output
   sequence. Compare the Moore and Mealy expected outputs.
2. [test_fsm_model.gd](../test/test_fsm_model.gd): `watch_signals()` and
   `assert_signal_emitted()` check that the model emits the right signals.
3. [test_transition_table.gd](../test/test_transition_table.gd): UI tests.
   They load the real scene, add it to the tree with `add_child_autofree()`,
   and "click" by emitting the signal a click would emit
   (`button.pressed.emit()`).
4. [test_graph_view.gd](../test/test_graph_view.gd): builds fake mouse
   events (`InputEventMouseButton`) and feeds them to `_gui_input()`.

Several real bugs in this project were caught by these tests. For example, the
sim panel's "Next on clock" going stale after editing a table cell.

**Concepts:** GUT, `assert_*`, simulating input. *(primer: Testing with GUT)*

**Try it:** Write a test for a **Mealy parity checker** in
`test_fsm_simulator.gd`: two states EVEN/ODD, input 1 toggles state, and
output is 1 when the *new* parity would be odd. Use `_build_mealy_detector()`
as a model. Run it and watch it pass (or find out why not!).

---

## Stop 9: Tying it together: `main.gd`

**Goal:** see how the model, simulator and views get connected.

Read [scenes/main.gd](../scenes/main.gd).

**What to notice:**

- `use_model()` is the only place the pieces are wired together: it makes a
  simulator for the model, then calls `bind(model, simulator)` on every view.
- Every view's `bind()` **disconnects from the old model first**, then
  connects to the new one. That's what makes **Load** and **New** work: a
  new model is swapped in and every view re-attaches. (`test_main.gd` checks
  the old model can no longer affect the views.)
- The order matters a little: the simulator is created *before* the views
  bind, so it hears `structure_changed` first. `sim_panel.gd`'s `bind()`
  has a comment about why.
- Dialogs (`FileDialog`, `ConfirmationDialog`, `AcceptDialog`) are hidden
  nodes in `main.tscn`. `popup_centered()` shows them, and they answer with
  signals (`file_selected`, `confirmed`).

**Concepts:** dependency wiring, dialogs/Windows. *(primer: UI: Dialogs)*

**Try it:** Add a line at the end of `use_model()`:
`model.structure_changed.connect(func() -> void: print("structure changed"))`.
Run, add states, change ports, and watch the Output panel. Then press **New**
and add a state. It still prints exactly once per change, not twice. The new
model got its own connection from `use_model()`. The old model (and its
connection) is gone: nothing refers to it any more, so it was freed
automatically.

---

## Stop 10: Nodes built from code

**Goal:** see that a node doesn't need a `.tscn` file.

Read [bit_toggle.gd](../scenes/cells/bit_toggle.gd),
[value_spin.gd](../scenes/cells/value_spin.gd), then
[ui_helpers.gd](../scenes/ui_helpers.gd).

**What to notice:**

- `FSMBitToggle extends Button`, and `FSMBitToggle.new()` is a
  fully working button. `_init()` sets it up. It isn't in the tree yet, so no
  `_ready()` work is needed.
- **Property setters:** `var value: int = 0: set(v): ...` runs whenever
  `value` is assigned, keeping the button's text and colour in sync.
- `FSMBitToggle` and `FSMValueSpin` both have an `edited(new_value)`
  signal. So `FSMUi.value_editor()` can return either one and the caller
  doesn't care which. The table's outputs *and* the simulation panel's inputs
  use it.
- `FSMUi.set_editor_value()` updates the display **without** emitting
  `edited`. When a change comes *from* the model, it mustn't be sent back to
  the model. That would be a loop.
- `FSMUi.flash_error()` is your first **Tween**: animate a property
  (`modulate`) over time. Remember this for Stop 16.

**Concepts:** script-only nodes, `_init`, setters, Tween. *(primer:
GDScript essentials, Tweens)*

**Try it:** Make 1s show as `H` and 0s as `L` in `FSMBitToggle`. Run the
tests: some fail because they check for "1". That's the tests doing their
job. Undo.

---

## Stop 11: Building UI in code: the port editor

**Goal:** create and destroy UI dynamically.

Read [port_editor.gd](../scenes/port_editor.gd) next to
[port_editor.tscn](../scenes/port_editor.tscn). The scene holds the fixed
parts (titles, "+ Input" buttons, empty `InputRows` box), and the script
fills in one row per port.

**What to notice:**

- `LineEdit.new()`, set properties, `add_child()`. That's all it takes to
  build UI in code.
- **Lambdas capture variables:** in `_rebuild_rows()`, each row's
  `func() -> void: model.remove_input(i)` remembers its own `i`.
- **Removing nodes:** `hide()` + `queue_free()`. `queue_free()` deletes at the
  end of the frame, which is safe even from inside that node's own signal
  (the × button deletes its own row!), and `hide()` makes it vanish from the
  layout immediately.
- **Rebuild only when the count changes:** width and name changes update the
  existing widgets. Otherwise clicking a width SpinBox's arrow would destroy
  the SpinBox mid-click.
- Rejected edits (duplicate name, too many bits) flash red and revert.

**Concepts:** dynamic UI, lambdas, `queue_free`. *(primer: GDScript
essentials, Nodes and the scene tree)*

**Try it:** Add a tooltip to each row's name field that shows the Verilog
declaration, e.g. `input [1:0] mode;`. Hint: set `tooltip_text` in
`_update_rows()` so it stays correct when the width changes.

---

## Stop 12: The transition table

**Goal:** the most involved UI in the app, using everything so far.

Read [transition_table.gd](../scenes/transition_table.gd). Its header
comment has an ASCII picture of the Moore and Mealy layouts.

**What to notice:**

- A **GridContainer** with `columns = 3 + combos (+ outputs)`: you add
  children left to right, top to bottom, and it wraps them into rows.
- Every cell is wrapped in a **PanelContainer** by `_add_cell()`. A
  PanelContainer draws a **StyleBox** behind its child, so highlighting a
  cell = swapping its StyleBox (`_apply_highlight()`). `_cells[row][col]`
  keeps them all addressable.
- **Rebuild vs patch:** `_rebuild()` only runs on `structure_changed`.
  `_on_state_renamed()`, `_on_transition_changed()` and friends patch single
  widgets. That's what the fine-grained model signals from Stop 5 are for.
- **ButtonGroup** turns the "Init" CheckBoxes into radio buttons.
- **Item metadata:** each dropdown item stores the state id, so the dropdown
  never has to look states up by name.
- `_scroll_into_view()` uses **`await`**: it waits one frame for the new
  cells to be laid out before scrolling to one.

**Concepts:** GridContainer, StyleBox, ButtonGroup, `await`. *(primer: UI:
Themes and StyleBoxes, Coroutines and await)*

**Try it:** While the app is running, use the **Remote** scene tree (Stop 6) to
find the table's `Grid` and expand it: one PanelContainer per cell. Then
change `INTERSECTION_COLOR` to a green and run again.

---

## Stop 13: The simulation panel

**Goal:** a small view that pulls together signals, shortcuts and a Tree.

Read [sim_panel.gd](../scenes/sim_panel.gd).

**What to notice:**

- It listens to one simulator signal, `updated`, and redraws its labels in
  `_refresh()`.
- **Shortcuts:** `clock_button.shortcut = _key_shortcut(KEY_C)`. Shortcuts
  only fire if the focused control didn't use the key, so typing "c" in a
  name field doesn't clock the machine.
- **Tree** as a multi-column list: `hide_root`, column titles, one
  `TreeItem` per history entry. Only new entries are appended
  (`_update_history()`).

**Try it:** Add **Space** as a second Clock key. A Shortcut can hold several
events (`shortcut.events = [event_c, event_space]`). Then find out what
happens when a button has keyboard focus and you press Space. (Buttons use
Space themselves, so the shortcut never sees it.)

---

## Stop 14: Custom drawing and mouse input: the graph

**Goal:** draw anything you like and respond to the mouse.

Read [graph_view.gd](../scenes/graph_view.gd).

**What to notice:**

- **`_draw()`** is where all drawing happens: `draw_circle`, `draw_arc`,
  `draw_polyline`, `draw_string`... Godot calls it once and caches the result.
  When the data changes we call **`queue_redraw()`**, and every model signal
  is connected to something that does.
- **`draw_set_transform()`** applies pan and zoom, so everything is drawn in
  "model coordinates" (the positions stored in each FSMState).
  `to_screen()` / `to_model()` convert between the two.
- **Edges** are computed fresh on each draw by `collect_edges()`: all
  transitions between the same two states merge into one arrow.
  `_edge_geometry()` makes a Bézier curve, bent when there's an arrow going
  the other way, and `_loop_geometry()` makes self-loops.
- **`_gui_input(event)`** handles the mouse: `InputEventMouseButton` for
  presses and the wheel, `InputEventMouseMotion` for drags. `accept_event()`
  says "handled".
- Dragging calls `model.set_state_position()`. The graph doesn't move the
  circle itself: it tells the model, the model emits `state_moved`, and the
  graph redraws. Same flow as everything else.
- `active_edge()` + the simulator's `updated` signal give the orange
  highlight.

**Concepts:** `_draw`, `queue_redraw`, transforms, `_gui_input`,
InputEvents, `_notification`. *(primer: Custom drawing, Input)*

**Try it:** Draw Moore states whose output is non-zero as a **double
circle** (the textbook "accepting state" style). In `_draw_state()`, after
`draw_arc(...)`, add a second `draw_arc` with radius `STATE_RADIUS - 5`
when `s.moore_output.any(func(v): return v != 0)`.

---

## Stop 15: Saving, loading, and not trusting files

**Goal:** see how Resources serialize, and why loading needs care.

Read the "Saving and loading" section of
[fsm_model.gd](../scripts/model/fsm_model.gd), then `load_from()` /
`save_to()` in [main.gd](../scenes/main.gd).

**What to notice:**

- Saving is one line: `ResourceSaver.save(self, path)`. Every `@export`
  property of the model and its nested resources is written out.
- **Loading is where the care goes.** A `.tres` file can contain GDScript
  code, and Godot *runs* it while loading. So `load_from_file()` first reads
  the file as plain text (`_check_file_is_safe()`) and allows only plain data
  and our four model scripts. Then `validate()` checks the data is
  consistent, so a damaged file gives an error message instead of a crash
  later.
- `static var load_error` is a variable on the class itself, used to report
  why loading failed.
- `CACHE_MODE_IGNORE` makes Godot re-read the file each time. The comment
  explains why the "DEEP" variant must *not* be used.
- `test_fsm_model.gd` has one test per kind of bad file. Read
  `test_rejects_embedded_script` to see what an attack looks like.

**Concepts:** ResourceSaver/ResourceLoader, `user://`, `static var`, RegEx.
*(primer: Resources, Files and paths)*

**Try it:** In a copy of a saved file, change one `next_id` to a state id
that doesn't exist and load it. Find the line in `validate()` that caught it.

---

## Stop 16: Where to go next: animation

The spec asks for graph changes to be **animated** eventually. Everything is
set up for it:

- State positions live in the model and all drawing goes through
  `_draw_state()` / `_draw_arrow()`, so the graph view can keep its own
  *displayed* positions and ease them toward the model's positions.
- You met Tweens in Stop 10. Alternatively, use `_process(delta)` to move
  displayed positions a little each frame and call `queue_redraw()` until
  they arrive.

[ARCHITECTURE.md → Extending](ARCHITECTURE.md#extending) has a step-by-step
sketch. It's a good first feature to build on your own.

Other ideas, roughly easiest first: a Space-bar clock (Stop 13); a
"double circle" style (Stop 14); an **Export Verilog** button that writes a
`case` statement from the model; undo/redo (hint: every change already goes
through model methods); a frozen first column so state names stay visible
when the table scrolls sideways.
