## One cell of the state transition table: "from this state, on this input
## combination, go to `next_id`" (and, for a Mealy machine, "while in this
## state with this input, drive `output`").
##
## Transitions live inside their source state (see FSMState.transitions),
## indexed by input combination, so they don't store the source state or the
## input themselves.
class_name FSMTransition
extends Resource

## Sentinel meaning "no next state chosen yet" (a blank dropdown in the table).
const UNSET := -1

## The id (not the name!) of the next state, or UNSET. Using ids means that
## renaming a state never needs to touch any transitions.
@export var next_id: int = UNSET
## Mealy output values, one int per output port (same order as
## FSMModel.outputs). Kept even in Moore mode so switching modes loses nothing.
## `Array[int]` is a *typed array*: Godot will refuse to put a non-int in it.
@export var output: Array[int] = []


## Returns an independent copy (changing the copy won't affect this one).
## We write this by hand rather than using Resource.duplicate() so that it is
## obvious the `output` array is copied too, not shared.
func copy() -> FSMTransition:
	var t := FSMTransition.new()
	t.next_id = next_id
	t.output = output.duplicate()
	return t
