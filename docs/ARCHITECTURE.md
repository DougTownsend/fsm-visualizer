# Architecture

How FSM Designer is put together, and why. For a guided, step-by-step
introduction, start with [TOUR.md](TOUR.md); for Godot concepts, see
[GODOT_PRIMER.md](GODOT_PRIMER.md).

**Contents:** [Overview](#overview) ·
[Data flow](#data-flow) ·
[File map](#file-map) ·
[The model](#the-model) ·
[Signals: who emits, who listens](#signals-who-emits-who-listens) ·
[Views](#views) ·
[Saving and loading](#saving-and-loading) ·
[Testing](#testing) ·
[Design decisions](#design-decisions) ·
[Known limitations](#known-limitations) ·
[Extending](#extending)

---

## Overview

The app has three layers:

1. **Model** (`scripts/model/`): the machine definition (`FSMModel` and the
   Resources it contains) and the simulation state (`FSMSimulator`). Plain
   data and logic, no UI. Fully unit-tested.
2. **Views** (`scenes/`): the toolbar, port editor, transition table, graph
   and simulation panel. Each displays the model and turns user actions into
   model method calls.
3. **Wiring** (`scenes/main.gd`): creates the model and simulator, hands them
   to every view, and handles New/Save/Load.

The transition table is the main editor, as the spec asks: the graph is
drawn purely from the model, so it always reflects the table. The only thing
the graph edits is state positions.

## Data flow

```
                 ┌──────────────────────── main.gd ─────────────────────────┐
                 │  use_model(m): sim = FSMSimulator.new(m)                 │
                 │                for each view: view.bind(m, sim)          │
                 └──────────────────────────────────────────────────────────┘

   user action                 method call                     signals
 ┌─────────────┐          ┌──────────────────┐   structure_changed, state_renamed,
 │ Toolbar     │─────────▶│                  │   transition_changed, moore_output_changed,
 │ PortEditor  │─────────▶│     FSMModel     │── initial_state_changed, state_moved ──┐
 │ Table       │─────────▶│ (source of truth)│                                        │
 │ GraphView   │─(drag)──▶│                  │                                        │
 └─────────────┘          └──────────────────┘                                        │
        ▲                          ▲ reads                                            │
        │                 ┌──────────────────┐                                        │
        │  set_input,     │   FSMSimulator   │◀──── (listens to model) ───────────────┤
        │  clock, reset   │ current state,   │                                        │
 ┌─────────────┐─────────▶│ inputs, history  │── updated ──┐                          │
 │ SimPanel    │          └──────────────────┘             │                          │
 └─────────────┘                                           ▼                          ▼
                                             all views refresh / re-highlight / redraw
```

Rules that keep this working:

- **Views never talk to each other.** They call model/simulator methods and
  react to signals.
- **All changes go through `FSMModel` methods**, never by assigning to
  `model.states[...]` from outside. The methods keep the data consistent and
  emit the signals everyone relies on.
- **Views can be re-bound.** Every `bind()` disconnects from the previous
  model/simulator before connecting to the new one, which is what makes New
  and Load work.

## File map

```
project.godot              settings: main scene, window size, GUT plugin enabled
.gutconfig.json            GUT command-line settings (test dir, prefix)
scripts/model/
  fsm_port.gd              FSMPort (Resource): name, width
  fsm_transition.gd        FSMTransition (Resource): next_id, Mealy output[]
  fsm_state.gd             FSMState (Resource): id, name, position, moore_output[], transitions[]
  fsm_model.gd             FSMModel (Resource): the machine, its API and signals, save/load/validate
  fsm_simulator.gd         FSMSimulator (RefCounted): current state, inputs, clock/reset, history
scenes/
  main.tscn / main.gd      root layout, owns model + simulator, dialogs, New/Save/Load
  toolbar.tscn / .gd       Moore/Mealy, Add State, New/Save/Load (emits requests up to main)
  port_editor.tscn / .gd   input/output rows: name, width, remove; bit-cap readout
  transition_table.tscn/.gd  GridContainer table, in-place updates, simulation highlighting, Copy table
  graph_view.gd            custom-drawn state diagram, pan/zoom/drag, highlighting, Copy diagram
  sim_panel.tscn / .gd     input editors, status, Clock/Reset, history Tree
  ui_helpers.gd            FSMUi: value_editor(), set_editor_value(), flash_error(), header_label()
  clipboard.gd             FSMClipboard: render_control() offscreen; copy_image() via xclip / wl-copy / PowerShell / osascript
  cells/bit_toggle.gd      FSMBitToggle: 0/1 button
  cells/value_spin.gd      FSMValueSpin: SpinBox for multi-bit values
test/                      GUT tests, one file per component
addons/gut/                the GUT plugin (third-party, don't edit)
docs/                      TOUR.md, GODOT_PRIMER.md, this file
```

## The model

### Data

```
FSMModel
├─ machine_type: MOORE | MEALY
├─ inputs:  Array[FSMPort]         (name, width)
├─ outputs: Array[FSMPort]
├─ states:  Array[FSMState]        (table row order)
│    ├─ id            permanent, never reused
│    ├─ name          unique, shown everywhere
│    ├─ position      graph coordinates (origin = middle of the diagram)
│    ├─ moore_output  Array[int], one value per output port
│    └─ transitions   Array[FSMTransition], one per input combo
│         ├─ next_id  a state id, or UNSET (-1)
│         └─ output   Array[int], Mealy output per port
├─ initial_state_id
├─ next_free_id                    next id to hand out
└─ auto_layout                     keep states evenly spaced on a circle?
```

Both Moore and Mealy outputs are always stored, so switching machine type
never loses data.

### Invariants

These always hold between method calls; `FSMModel.validate()` checks them
after loading a file:

- every state has exactly `input_combo_count()` transitions;
- every output list (each `moore_output`, each transition `output`) has one
  value per output port, each within `0 .. 2^width - 1`;
- every `next_id` is `UNSET` or an existing state's id;
- state ids are unique and below `next_free_id`; state names are unique and
  non-empty; port names are unique across inputs *and* outputs;
- total input bits ≤ `MAX_INPUT_BITS` (4); output widths ≤ 32;
- `initial_state_id` is an existing state, or -1 when there are no states.

### Input combinations

A **combo** is the table column index: all input values concatenated, first
input in the most significant bits, like Verilog `{in0, mode}`. With `in0`
(1 bit) and `mode` (2 bits), combo `0b1_01 = 5` means `in0 = 1, mode = 01`.
`combo_to_values()`, `values_to_combo()` and `combo_label()` convert.

When inputs change, `_remap_transitions()` rebuilds every state's transition
list and keeps the user's work: a new input copies each old transition to
all of its values, a removed input keeps the slice where it was 0, and a
widened input leaves only the new values unset.

### Layout

While `auto_layout` is true, `add_state()` / `remove_state()` space all
states evenly on a circle (`circle_layout()`). The first
`set_state_position()` (a drag) turns it off, and new states then go to a
free spot (`_free_position()`). `arrange_states()` turns it back on.

## Signals: who emits, who listens

### FSMModel

| Signal | Emitted by | Listeners → response |
|---|---|---|
| `structure_changed` | add/remove state; add/remove/rename/resize a port; set machine type | Simulator `_on_structure_changed` (resize inputs, fall back to initial state, emit `updated`) · Toolbar `_refresh` · PortEditor `_refresh` · GraphView `_on_structure_changed` (auto-fit, redraw) · Table `_rebuild` · SimPanel `_rebuild_inputs` |
| `state_renamed(id)` | `rename_state` | Simulator → `updated` · GraphView redraw · Table `_on_state_renamed` (name field + dropdown texts) |
| `transition_changed(id, combo)` | `set_next_state`, `set_mealy_output` | Simulator → `updated` · GraphView redraw · Table `_on_transition_changed` (that cell) |
| `moore_output_changed(id)` | `set_moore_output` | Simulator → `updated` · GraphView redraw · Table `_on_moore_output_changed` |
| `initial_state_changed` | `set_initial_state` | Simulator `_on_initial_state_changed` (follows it before the first clock) · GraphView redraw · Table `_on_initial_state_changed` (radio buttons) |
| `state_moved(id)` | `set_state_position`, `arrange_states` | GraphView redraw |

Listeners run in connection order: the simulator first (it's created and
connected before the views bind), then Toolbar, PortEditor, GraphView,
Table, SimPanel.

### Others

| Signal | Emitter | Listener |
|---|---|---|
| `updated` | FSMSimulator: `reset`, `set_input`, `clock`, and relayed model edits | GraphView `queue_redraw` · Table `_apply_highlight` · SimPanel `_refresh` |
| `new_requested`, `save_requested`, `load_requested` | FSMToolbar buttons | main.gd |
| `edited(new_value)` | FSMBitToggle / FSMValueSpin | the callback passed to `FSMUi.value_editor()` |

### Rebuild vs patch

`structure_changed` means "the shape changed, rebuild". Every other signal
means "patch one thing in place". The table and port editor depend on this so
that the widget you're typing in or clicking isn't destroyed under you.
The port editor goes further and only rebuilds rows when the *number* of
ports changes. When a patch comes from the model, views update widgets
without emitting their own change signals (`set_value_no_signal`,
`FSMUi.set_editor_value`, `OptionButton.select`), so nothing loops.

## Views

| View | Rebuilds on | Patches on | Notes |
|---|---|---|---|
| Toolbar | `structure_changed` (type dropdown) | none | re-emits New/Save/Load |
| PortEditor | port count change | names, widths, bit readout | rejected edits flash red and revert |
| TransitionTable | `structure_changed` | rename, cell, Moore output, initial; `updated` → highlight | `_cells[row][col]` PanelContainers; `_scroll_into_view` |
| GraphView | never (redraws from scratch each `_draw`) | any signal → `queue_redraw()` | pan/zoom via `draw_set_transform`; `collect_edges()` merges parallel transitions |
| SimPanel | `structure_changed` (input editors) | `updated` → labels + history | Clock = C, Reset = R |

## Saving and loading

`FSMModel.save_to_file()` is `ResourceSaver.save(self, path)`: a `.tres`
text file with the ports, states and transitions as sub-resources and
references to the four model scripts.

`FSMModel.load_from_file()` defends against untrusted files, because Godot
executes scripts embedded in or referenced by a resource while loading it:

1. `_check_file_is_safe()` reads the file as text and allows only a
   `gd_resource` header with `script_class="FSMModel"`, `sub_resource`s of
   type `Resource`, and `ext_resource`s of type `Script` whose path is one of
   `ALLOWED_SCRIPTS` (and whose `uid`, if present, is that script's real uid,
   since Godot resolves by uid first). Any other section is rejected.
2. `ResourceLoader.load(path, "", CACHE_MODE_IGNORE)` loads it fresh.
   (`CACHE_MODE_IGNORE_DEEP` would also reload the model scripts while they
   are running, which crashes Godot 4.7.)
3. `validate()` checks the invariants above.

On failure it returns `null` and sets `FSMModel.load_error`. main.gd shows
that in a dialog and keeps the current machine. The file format depends on
the scripts' `res://` paths, so moving those files breaks old saves.

## Testing

`godot --headless -s addons/gut/gut_cmdln.gd` runs everything (about 100
tests, under a second).

| File | Covers |
|---|---|
| `test_fsm_model.gd` | combos, states, ports and remapping, layout, save/load round trip, load safety and validation |
| `test_fsm_simulator.gd` | Moore and Mealy "11" detectors, reset, errors, reacting to model edits |
| `test_port_editor.gd`, `test_transition_table.gd`, `test_sim_panel.gd` | the real scenes, driven by emitting widget signals; highlighting |
| `test_graph_view.gd` | edges and labels, coordinates, hit testing, simulated mouse drag/pan/zoom, active edge |
| `test_main.gd` | save → new → load end to end, re-binding, dialogs, title |

Drawing itself isn't unit-tested. It was checked by rendering screenshots
(a SceneTree script that loads `main.tscn`, builds a machine, waits a few
frames and saves `root.get_texture().get_image()` as a PNG).

## Design decisions

- **One model, many views, signals in between.** Views stay independent, and
  the graph can't drift out of sync with the table because it has no data of
  its own.
- **Stable integer ids for states.** Renames are free; transitions,
  dropdowns and the simulator never look anything up by name.
- **Fine-grained signals.** Needed so edits don't rebuild the widget being
  edited (see [Rebuild vs patch](#rebuild-vs-patch)).
- **Input bits capped at 4.** The table has one column per input combination
  (2^bits), so this keeps it readable. The cap is one constant,
  `FSMModel.MAX_INPUT_BITS`.
- **Built-in controls for the table** (GridContainer + PanelContainer cells)
  and **custom `_draw()` for the graph**, rather than plugins; see below.
- **Resources for the data**, so save/load is nearly free and the files are
  human-readable. The cost is the load-time safety check.

### Why no other plugins

The spec asks to prefer plugins where they fit. These were evaluated:

- *State machine plugins* (State Graph, Godot State Charts, XSM, LimboAI)
  run game logic as node-based state machines. None draws an arbitrary
  Mealy/Moore diagram from data.
- *Table plugins* (Dynamic Data Table, Godot DataTables, Edit Resources as
  Table) can't put composite widgets in a cell (dropdown + "/" + bit
  toggles) or highlight rows, columns and single cells independently.
- Godot's built-in *GraphEdit* is a node-editor (boxes with ports), not
  circles with curved arrows and self-loops.

**GUT** fitted well and is used for testing.

## Known limitations

- When the table scrolls sideways to the active cell, the state-name column
  scrolls out of view (there's no frozen first column).
- A merged arrow is highlighted as a whole, even though only one of its
  input combinations is active; the table shows the exact cell.
- Arrows are drawn straight through any state that happens to lie between
  two others; drag states to tidy up.
- No undo/redo, and no "unsaved changes" tracking (New always asks if there
  are states; closing the window doesn't ask).
- Moving `scripts/model/*.gd` breaks previously saved files (they reference
  the scripts by path).

## Extending

### Animating graph changes

Goal (from the spec): states glide to new positions instead of jumping.

1. In `graph_view.gd`, keep displayed positions separate from the model's:
   `var _shown: Dictionary[int, Vector2] = {}`, and a helper
   `func _pos(s: FSMState) -> Vector2: return _shown.get(s.id, s.position)`.
2. Use `_pos(s)` instead of `s.position` everywhere in drawing and in
   `state_at()`, `_states_centre()` and `fit_view()`.
3. Ease toward the target each frame:

   ```gdscript
   func _process(delta: float) -> void:
   	var moving := false
   	for s in model.states:
   		var shown: Vector2 = _shown.get(s.id, s.position)
   		shown = shown.lerp(s.position, 1.0 - exp(-12.0 * delta))
   		if shown.distance_to(s.position) < 0.5:
   			shown = s.position
   		else:
   			moving = true
   		_shown[s.id] = shown
   	queue_redraw()
   	set_process(moving)   # stop calling _process once everything arrived
   ```

4. Call `set_process(true)` from the handlers for `structure_changed` and
   `state_moved`, and remove ids of deleted states from `_shown`.
5. While **dragging**, set `_shown[_drag_id]` to the new position directly,
   so the state sticks to the mouse instead of lagging.
6. New states could also grow in: keep `_appear[id]` going 0 → 1 (with a
   Tween or in `_process`) and scale the circle radius by it.

Nothing outside the graph view needs to change. Tests that read positions
from the model are unaffected.

### Adding a field to the model

1. Add the `@export var` to the right Resource (it'll be saved
   automatically).
2. Change it only through a new `FSMModel` method that emits a signal
   (reuse one, or add one and list it in the table above).
3. Add a check to `validate()` if bad values could break something.
4. Update views to show it; add tests in `test_fsm_model.gd`.

### Adding a new view

1. Make a scene with a script that has `bind(model, simulator)`, which
   disconnects from any previous model/simulator first.
2. Add an instance to `main.tscn`, a `%Name` reference in `main.gd`, and
   include it in the list in `use_model()`.
3. Drive it from signals only. Copy the pattern from `sim_panel.gd` (small)
   or `transition_table.gd` (rebuild + patch).

### Other ideas

- **Export Verilog:** walk `model.states` and write a `case (state)` block
  with nested `case ({in0, mode})`: combo labels are already in Verilog bit
  order.
- **Undo/redo:** every change already goes through model methods; record
  inverse operations there, or use Godot's `UndoRedo` class.
- **Frozen state-name column:** split the table into two GridContainers (names
  | cells) with synced vertical scrolling.
