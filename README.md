# FSM Designer

An interactive finite state machine editor and simulator, built with
**Godot 4.7** as a way to learn Godot.

- Define Verilog-style **inputs and outputs** with any bit width (inputs up
  to 4 bits in total).
- Choose a **Moore** or **Mealy** machine.
- Edit the **state transition table**. The **state diagram** redraws live
  from it, and you can drag states around.
- **Simulate:** set inputs, press **Clock**, and watch the current state,
  active transition and table cell highlight. Every tick is logged.
- **Save / load** machines as `.tres` files.
- **Copy diagram** / **Copy table** put the state diagram or transition table
  on the clipboard as a black-on-white PNG, without simulation highlighting.
  On Linux this needs `xclip` (X11) or `wl-clipboard` (Wayland).

## Run it

```sh
godot --path .            # run the app
godot -e --path .         # open the project in the editor (then press F5)
```

Keys: **C** clock, **R** reset, **Ctrl+N / Ctrl+S / Ctrl+O** new / save /
load. In the graph: drag states to move them, drag the background to pan,
and use the mouse wheel to zoom.

## Run the tests

```sh
godot --headless -s addons/gut/gut_cmdln.gd
```

Or use the **GUT** panel at the bottom of the editor.

## Learn how it works

New to Godot? Start with the **[guided tour](docs/TOUR.md)**. It walks
through the project one idea at a time, with a hands-on exercise at each
stop.

- [docs/TOUR.md](docs/TOUR.md): the guided tour (start here)
- [docs/GODOT_PRIMER.md](docs/GODOT_PRIMER.md): reference for the Godot
  concepts used
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): design, data flow, signals,
  how to extend
- [spec.md](spec.md): the original requirements; [PLAN.md](PLAN.md): the
  build plan and what was done in each step
