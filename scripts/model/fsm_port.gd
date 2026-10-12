## One input or output of the FSM, like a port on a Verilog module.
##
##   input  [1:0] mode;   ->   FSMPort.new("mode", 2)
##
## GODOT CONCEPTS INTRODUCED HERE
## - `class_name FSMPort` registers this script as a global type. Any other
##   script can now write `FSMPort.new()` or declare `var p: FSMPort` without
##   loading this file first.
## - `extends Resource`: a Resource is Godot's basic "data object". Resources
##   can be saved to / loaded from disk (.tres text files) automatically, and
##   the editor can show and edit them in the Inspector. We use Resources for
##   all FSM data so that saving a whole machine is a single function call.
## - `@export` marks a property as part of the saved data (and shows it in
##   the Inspector). Properties WITHOUT @export are not saved.
## - Lines starting with `##` are documentation comments: the Godot editor
##   shows them in its built-in help (press F1 and search "FSMPort").
class_name FSMPort
extends Resource

## The port's name, shown in table headers and the simulation panel.
@export var name: String = ""
## Number of bits. A width of 1 is a single wire; wider ports hold 0..2^width-1.
@export var width: int = 1


# `_init` is the constructor, called by `FSMPort.new(...)`.
# Resources must be constructible with NO arguments (Godot does that when it
# loads a saved file), so every parameter here needs a default value.
func _init(p_name: String = "", p_width: int = 1) -> void:
	name = p_name
	width = p_width


## Largest value this port can hold, e.g. 3 for a 2-bit port.
func max_value() -> int:
	return (1 << width) - 1
