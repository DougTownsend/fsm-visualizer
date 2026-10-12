## Editor for a 1-bit value: a small button showing 0 or 1 that flips when
## clicked. Used for 1-bit outputs in the table and 1-bit inputs in the
## simulation panel.
##
## GODOT CONCEPTS INTRODUCED HERE
## - A node built entirely from a script, with no .tscn: `FSMBitToggle.new()`
##   creates a Button with this behaviour, ready to add_child() anywhere.
## - `_init()` in a Node: runs when the object is created, before it is in the
##   scene tree. Fine for setting its own properties, but child nodes and the
##   tree aren't available yet (that's what `_ready()` is for).
## - Property setters: `var value: int = 0: set(v): ...` runs that code every
##   time `value` is assigned, which keeps the button's text in sync.
class_name FSMBitToggle
extends Button

## Emitted when the user clicks (not when `value` is set from code).
signal edited(new_value: int)

const ONE_COLOR := Color(0.45, 0.95, 0.55)
const ZERO_COLOR := Color(0.7, 0.7, 0.7)

var value: int = 0:
	set(v):
		value = v & 1
		text = str(value)
		# A button has different font colours per visual state; override them
		# all so the colour always reflects the value.
		var color := ONE_COLOR if value else ZERO_COLOR
		for theme_item in ["font_color", "font_hover_color", "font_pressed_color",
				"font_focus_color", "font_hover_pressed_color"]:
			add_theme_color_override(theme_item, color)


func _init() -> void:
	custom_minimum_size = Vector2(30, 0)
	tooltip_text = "Click to toggle"
	value = 0  # runs the setter so the text and colour are initialised
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	value = 1 - value
	edited.emit(value)
