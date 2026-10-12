I want to make an interactive finite state machine GUI using Godot. I want it to have a graph view that shows the state diagram, and also a state transition table. I want the graph view to be controlled by the state transition table.

The FSM should have the ability to define multiple inputs and outputs, and the bit width of each input/output should be adjustable, similar to a verilog module.

The FSM should have a setting for whether it is a mealy machine or a moore machine, and that should change the options available in the state transition table.

The state transition table should start out empty, with an option to add more states. Each state should have the ability to be renamed, but default to S0, S1, S2, etc. Moore machines will have a next state column for each possible input, and an output column. Mealy machines should have the next state then a forward slash, then the output for each possible input. The next state should be a dropdown menu that allows choosing states. Renaming a state should update the name in the table. The outputs should be a toggleable 1 or 0 that gets toggled on click for 1 bit outputs, or a text box with up/down arrows for multibit outputs.

The graph view should update in real time as states are added, removed, or modified in the transition table. Eventually I will want to have these changes be animated, instead of having it instantly change, but instantly changing is sufficient for now.

I then want to be able to simulate the FSM. It should have the ability to set the input, then a button to act as the clock. The graph view should highlight the current state, and the edge pointing to the next state based on the currently selected input. The transition table should also highlight the row/column that corresponds to the current state and current input, and highlight the intersection of the two in a different color.

Part of what I want to do with this is learn how to use Godot to some extent, so try to document how everything works for someone who has never used godot before. Also, make sure to use plugins that may provide needed functionality when available instead of reinventing the wheel.