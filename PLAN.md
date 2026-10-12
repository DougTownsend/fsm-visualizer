# Plan: Interactive FSM editor/simulator in Godot 4.7

## Context
`spec.md` describes an interactive finite-state-machine tool: a transition table (the source of truth) drives a live state-diagram graph view; Verilog-style multi-bit inputs/outputs; Mealy/Moore switch; clocked simulation with highlighting in both views. The user also wants to **learn Godot**, so code must be heavily explained, and existing plugins should be used where they genuinely fit.

The project is a fresh Godot 4.7.2 project (`project.godot`, `icon.svg` only; GL Compatibility renderer). Not a git repo yet.

Decisions made with the user:
- Total input bits capped (constant `MAX_INPUT_BITS = 4` → max 16 input columns), with a warning in the UI.
- Graph layout: new states auto-placed on a circle, user can drag them afterwards.
- Extras in v1: save/load, initial state + Reset, simulation history log, removing states.

### Plugin evaluation
- State-machine plugins (State Graph, Godot State Charts, XSM, LimboAI) are for driving *game logic* with node-based states; none render an arbitrary user-defined Mealy/Moore diagram from data. → not used.
- Table plugins (Dynamic Data Table, Godot DataTables, Resources-as-Sheets) don't support per-cell composite widgets (dropdown + "/" + bit toggles) or per-row/column/cell highlighting. → not used; built-in `GridContainer` + standard controls are a better fit and teach core Godot UI.
- Built-in `GraphEdit` is port-based node-editor UI (rectangles with sockets), not circles + curved arrows + self-loops. → custom `_draw()` Control instead.
- **Used: GUT (Godot Unit Test)** addon in `addons/gut/` for unit-testing the model and simulator headlessly.

## Architecture (model / view separation)

```
res://
  addons/gut/                     # GUT test plugin
  scripts/model/
    fsm_port.gd       FSMPort (Resource): name, width
    fsm_state.gd      FSMState (Resource): id, name, position, moore_output, transitions: Array[FSMTransition]
    fsm_transition.gd FSMTransition (Resource): next_id (-1 = UNSET), output: Array[int] (Mealy)
    fsm_model.gd     FSMModel (Resource): the whole machine + signals
    fsm_simulator.gd FSMSimulator (RefCounted): current state, input, clock/reset, history
  scenes/
    main.tscn / main.gd            layout + wiring
    toolbar.tscn                   Mealy/Moore, Add State, Save, Load
    port_editor.tscn               add/remove/rename inputs & outputs, width SpinBox
    transition_table.tscn/.gd      GridContainer-based table
    cells/bit_toggle.gd            Button that shows 0/1, toggles on click
    cells/value_spin.gd            SpinBox 0..2^w-1 for multi-bit values
    graph_view.gd                  Control with custom _draw + dragging
    sim_panel.tscn/.gd             input setters, Clock, Reset, history list
  test/  test_fsm_model.gd, test_fsm_simulator.gd
  docs/  TOUR.md, GODOT_PRIMER.md, ARCHITECTURE.md   (+ README.md at the root)
```

### FSMModel (single source of truth)
- `machine_type` (enum MOORE/MEALY), `inputs: Array[FSMPort]`, `outputs: Array[FSMPort]`, `states: Array[FSMState]` (each state owns its `transitions[combo]`), `initial_state_id`, `next_free_id`.
- *(As built: classes are `FSM`-prefixed to avoid global-name clashes; transitions live inside each state rather than in a separate dictionary.)*
- States referenced by **stable integer ids**, never by name, so renaming only touches the name.
- Input combo index = inputs concatenated MSB-first in declared order (Verilog `{a, b}`); helpers `input_combo_count()`, `combo_to_values(i)`, `combo_label(i)`.
- API: `add_state()` (default name `S<n>`, lowest unused number), `remove_state(id)` (transitions pointing to it → unset), `rename_state`, `set_next`, `set_output`, `set_moore_output`, `add/remove/resize port` (resizes transition arrays, clamps values), `set_machine_type`.
- Fine-grained signals so views don't rebuild while the user types: `structure_changed` (states added/removed, ports, machine type → table rebuild), `state_renamed(id)`, `transition_changed(id, combo)`, `moore_output_changed(id)`, `initial_state_changed`, `state_moved(id)`.
- Actual API names: `set_next_state`, `set_mealy_output`, `set_moore_output`, `add_input/remove_input/set_input_width/rename_input` (+ output equivalents), `save_to_file` / `FSMModel.load_from_file` (uses `CACHE_MODE_IGNORE`; `CACHE_MODE_IGNORE_DEEP` crashes Godot 4.7 by reloading the running script).
- Save/load via `ResourceSaver.save()` / `ResourceLoader.load()` to `.tres` (a good Godot lesson: custom Resources serialize for free), using `FileDialog`.

### Transition table (`GridContainer`)
- Columns: `[init radio] [name LineEdit] [delete]` + one column per input combo (+ one output column per output port for Moore).
- Moore cell: `OptionButton` of states. Mealy cell: `HBox[OptionButton, Label "/", output widgets]`.
- Output widget: width 1 → `BitToggle` (Button, click flips 0/1); width >1 → `SpinBox` (up/down arrows, range 0..2^w−1).
- Each cell wrapped in a `PanelContainer` whose `StyleBoxFlat` background is swapped for highlighting: current-state row, current-input column, intersection in a distinct colour.
- Rename → update only OptionButton item texts (no rebuild, so LineEdit keeps focus).
- "Add State" button below the table; empty on start.

### Graph view (custom `Control`)
- `_draw()` draws: state circles with name (Moore: `name / output` inside), initial-state arrow, edges as quadratic Béziers (curve offset when an A→B and B→A pair exists), self-loops as arcs above the circle, arrowheads, labels (`input` for Moore, `input/output` for Mealy). Multiple combos with same src→dst merge into one edge with comma-separated labels.
- Connects to model signals and calls `queue_redraw()` — real-time updates for free.
- `_gui_input()` handles click-drag of states (positions stored in `FSMState.position`, saved with the file).
- Highlight: current state fill + active edge (for current input) in accent colour.
- Positions stored in the model and drawing isolated in one function, so later animation = tween positions/colours.

### Simulator + sim panel
- `FSMSimulator`: `reset()` → initial state; `clock()` → follows transition for current input combo (no-op + message if unset), appends history entry `{cycle, state, input, output, next}`; `current_output()` (Moore: from state; Mealy: from current transition). Emits `stepped`.
- Panel: one widget per input port (BitToggle / SpinBox, same as table), live output readout, **Clock** and **Reset** buttons, history `ItemList`. Changing input re-highlights immediately (edge in graph, column in table).

### Documentation for a Godot newcomer
- Every script has a header comment explaining its role plus inline notes the first time a Godot concept appears (nodes & scene tree, scenes/`.tscn`, `_ready`, `@onready`, `@export`, signals & `connect`, `_draw`/`queue_redraw`, `_gui_input`, containers & size flags, Resources, `class_name`).
- `docs/GODOT_PRIMER.md`: editor tour, how to open/run the project, how scenes/nodes/scripts/signals fit together, using this project as examples.
- `docs/ARCHITECTURE.md`: data flow diagram (table → model → signals → graph/table/sim), file map, how to extend (e.g. adding animation).

## Implementation order (each step runnable)
1. ✅ **Done** — `git init`; install GUT into `addons/gut`, enable in project settings.
   - GUT 9.7.1 (the release targeting Godot 4.7) installed to `addons/gut/`, enabled under `[editor_plugins]` in `project.godot`.
   - `.gutconfig.json` points GUT at `res://test/`; `test/test_smoke.gd` passes via `godot --headless -s addons/gut/gut_cmdln.gd`.
2. ✅ **Done** — Model resources + simulator + GUT tests.
   - `scripts/model/`: `fsm_port.gd`, `fsm_transition.gd`, `fsm_state.gd`, `fsm_model.gd`, `fsm_simulator.gd`, all heavily commented for Godot newcomers.
   - Input changes remap existing transitions (new input → behaviour copied for all its values; removed input → slice where it was 0; widened → new values unset).
   - `test/test_fsm_model.gd` (28 tests) + `test/test_fsm_simulator.gd` (13 tests, Moore and Mealy "11" detectors): 41/41 passing, including save→load round trip. Placeholder smoke test removed.
3. ✅ **Done** — Main scene layout (toolbar, HSplit: graph | port editor + table, sim panel at bottom); set as main scene.
   - `scenes/main.tscn` + `main.gd`: owns model/simulator, `use_model()` calls `bind(model, simulator)` on every view (re-bindable, ready for Load in step 7). Window 1280×800.
   - Layout: Toolbar / VSplit[ HSplit[ GraphView | PortEditor + ScrollContainer(TransitionTable) ] , SimPanel ].
   - Toolbar is functional (Moore/Mealy dropdown, Add State); Save/Load disabled until step 7. Port editor, table, graph and sim panel are live-updating placeholders to be replaced in steps 4–6.
4. ✅ **Done** — Port editor + transition table (Moore then Mealy), rename/remove/initial.
   - `scenes/cells/bit_toggle.gd` (FSMBitToggle), `scenes/cells/value_spin.gd` (FSMValueSpin), `scenes/ui_helpers.gd` (FSMUi: `value_editor()`, `set_editor_value()`, `flash_error()` tween, `header_label()`).
   - Port editor: side-by-side Inputs/Outputs rows (name, bits SpinBox, ×), "+ Input"/"+ Output", input-bit usage readout; add disabled and width SpinBox max limited at the 4-bit cap. Rows rebuild only when port count changes.
   - Transition table: GridContainer, every cell wrapped in a PanelContainer (`_cells[row][col]`, ready for step 6 highlighting). Init radio (ButtonGroup), name LineEdit (rejected renames flash red and revert), × delete, next-state OptionButtons with "—" = unset; Moore output columns; Mealy `next / outputs` cells. Header tooltips show `in0 = 1, mode = 01`.
   - Rebuild only on `structure_changed`; renames, cell edits, output edits and initial-state changes update widgets in place (also correct for edits made outside the table).
   - `test/test_transition_table.gd` (13) + `test/test_port_editor.gd` (7) drive real widgets: 61/61 tests passing.
5. ✅ **Done** — Graph view drawing, then dragging.
   - `scenes/graph_view.gd` (FSMGraphView): custom `_draw()` in model coordinates via `draw_set_transform()` (pan + zoom). States as circles (Moore output in green under the name; long names shrink to fit), initial-state arrow, straight arrows, curved pairs for A⇄B, self-loops pointing away from the diagram centre. Parallel transitions merged into one arrow with a wrapped label (`1`, `0 1/0 000`, `any`, `any/0`).
   - Mouse: drag state (writes `FSMState.position` via `model.set_state_position`), drag background / middle-drag to pan, wheel zooms about the cursor, hover outline + hand cursor. "Fit" and "Arrange" buttons; view auto-fits until the user pans/zooms/drags.
   - Model change: `FSMModel.auto_layout` (saved) keeps states evenly spaced on a circle as they're added/removed, until the user drags one; then new states go to a free spot. `arrange_states()` re-enables it. (Replaced the fixed 8-per-ring slots, which bunched small machines on one side.)
   - `collect_edges()`, `edge_label()`, `state_at()`, `to_screen()/to_model()`, `fit_view()`, `zoom_at()` are public so step 6 highlighting can reuse them.
   - `test/test_graph_view.gd` (11) + 3 new layout tests in `test_fsm_model.gd`: 75/75 passing.
6. ✅ **Done** — Simulation panel + highlighting in both views + history.
   - `scenes/sim_panel.tscn/.gd`: per-input toggles/spin boxes (reusing FSMUi.value_editor), "Cycle n · State", "Next on clock", "Outputs: out0 = 1, …", Clock (key C) and Reset (key R) via Button shortcuts, error line for unset transitions, history as a 5-column Tree that appends rows and auto-scrolls.
   - Table: current row + input column (incl. header) tinted blue, intersection orange; re-applied after rebuilds; scrolls the active cell into view (one-frame `await` so layout is done).
   - Graph: current state filled orange, active edge thick orange with orange label drawn on top, next state outlined orange. `active_edge()` public.
   - Bug found by tests and fixed: FSMSimulator now emits `updated` on transition/output/rename edits too, so "Next on clock"/outputs never go stale.
   - `test/test_sim_panel.gd` (8) + highlight tests in table (3) and graph (2) + simulator (1): 89/89 passing.
   - Known limitation: when the table scrolls sideways to the active cell, the state-name column scrolls out of view (no frozen first column).
7. ✅ **Done** — Save/load.
   - Toolbar: New / Save… / Load… buttons (Ctrl+N / Ctrl+S / Ctrl+O) emit `new_requested` / `save_requested` / `load_requested` ("call down, signal up"); `main.gd` owns a FileDialog (filesystem access, `*.tres` filter, starts in Documents), a ConfirmationDialog for New (only when there are states), and an AcceptDialog for errors. `save_to()` / `load_from()` / `new_machine()`; window title shows the file name; project renamed "FSM Designer".
   - **Security:** `.tres` files can embed/reference GDScript that runs on load, so `FSMModel.load_from_file()` first scans the file text: only `gd_resource` with `script_class="FSMModel"`, `sub_resource type="Resource"`, and `ext_resource` pointing at the four model scripts (uid, if present, must match) are allowed. Then `FSMModel.validate()` checks consistency (port names/widths, bit cap, unique ids/names, transition counts, dangling next ids, output ranges, initial state). Failure → `FSMModel.load_error`, shown in a dialog; the current machine is kept.
   - Tests: 10 new load-safety/validation tests in `test_fsm_model.gd` (embedded GDScript, foreign script path, mismatched uid, non-FSM resource, missing file, inconsistent data) + `test/test_main.gd` (6: save→new→load rebinds every view, old model disconnected, extension added, failed load keeps machine, New confirmation, title). 104/104 passing.
8. ✅ **Done** — Docs pass.
   - `docs/TOUR.md`: guided tour in 17 stops (0–16), ordered to build up one idea at a time: use the app → editor → nodes/scenes/scripts/signals (toolbar) → layout (main.tscn) → Resources → model & signals → debugger (watch a signal fan out) → simulator → GUT tests → main.gd wiring → code-built nodes → port editor → table → sim panel → graph drawing/input → save/load security → animation next steps. Each stop: files, what to notice, concepts (linked to the primer), and a hands-on "Try it" exercise.
   - `docs/GODOT_PRIMER.md`: concept reference (nodes, scenes, scripts, GDScript, lifecycle, signals, memory, Resources, paths, Controls/containers, themes, dialogs, drawing, input, Tweens, await, debugging, GUT, plugins), each pointing at where the project uses it.
   - `docs/ARCHITECTURE.md`: layers, data-flow diagram, file map, model data + invariants, combo encoding, full signal emit/listen tables, rebuild-vs-patch policy, save/load security, testing, design decisions (incl. plugin evaluation), known limitations, and extension recipes (step-by-step graph animation sketch, new model field, new view, Verilog export, undo).
   - `README.md` at the root: what it is, how to run/test, where the docs are.
   - Checked: all doc links/anchors resolve; every project function the docs name exists.

## Verification
- Unit tests headless: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit` (combo encoding, add/remove/rename, port resize clamping, Mealy/Moore switch, clock/reset, save→load round trip).
- Parse/run check: `godot --headless --quit` to catch script errors; launch `godot` to exercise manually: build a Moore sequence detector (e.g. "11" detector), then the Mealy version; confirm graph updates live, renames propagate to dropdowns, highlights follow Clock/input changes, save/reload restores everything including positions.
