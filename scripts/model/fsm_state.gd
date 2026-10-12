## One state of the machine: one row of the transition table, one circle in
## the graph view.
class_name FSMState
extends Resource

## Permanent unique number for this state. Never changes and is never reused,
## even if the state is renamed or other states are deleted. Everything that
## refers to a state (transitions, the initial state, the simulator) uses this.
@export var id: int = -1
## Display name, e.g. "S0" or "IDLE". Must be unique within the machine.
@export var name: String = ""
## Where the circle is drawn in the graph view. The graph view's origin (0, 0)
## is its centre. Saved with the file so a hand-arranged diagram is kept.
@export var position: Vector2 = Vector2.ZERO
## Moore output values, one int per output port. Kept in Mealy mode too.
@export var moore_output: Array[int] = []
## Outgoing transitions, one per input combination: transitions[combo].
## See FSMModel.combo_to_values() for how a combo number maps to input values.
@export var transitions: Array[FSMTransition] = []
