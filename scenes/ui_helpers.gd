## Small UI helper functions shared by several views.
##
## Everything here is `static`, so call it on the class: FSMUi.flash_error(x).
## (Extending RefCounted is just the lightest base class; nobody creates
## instances of this.)
class_name FSMUi
extends RefCounted

const ERROR_COLOR := Color(1.0, 0.4, 0.4)


## Creates the right editor for a value of the given bit width: an
## FSMBitToggle for 1 bit, an FSMValueSpin for more. `on_edited` is called
## with the new int value whenever the user changes it.
static func value_editor(width: int, value: int, on_edited: Callable) -> Control:
	if width == 1:
		var toggle := FSMBitToggle.new()
		toggle.value = value
		toggle.edited.connect(on_edited)
		return toggle
	var spin := FSMValueSpin.new()
	spin.setup(width, value)
	spin.edited.connect(on_edited)
	return spin


## Shows `value` in an editor made by value_editor(), WITHOUT emitting
## `edited` (the change came from the model, so don't send it back).
static func set_editor_value(editor: Control, value: int) -> void:
	if editor is FSMBitToggle:
		editor.value = value  # the setter only updates the display
	elif editor is FSMValueSpin:
		editor.set_value_no_signal(value)


## Briefly tints a control red and fades it back, e.g. when a rename is
## rejected.
##
## GODOT CONCEPT: a Tween animates a property over time. create_tween() makes
## one tied to the node (it stops if the node is freed), and tween_property()
## says "take `modulate` to white over 0.6 seconds". `modulate` multiplies the
## colour of the node and its children. We'll use tweens again for animating
## the graph later.
static func flash_error(control: Control) -> void:
	control.modulate = ERROR_COLOR
	var tween := control.create_tween()
	tween.tween_property(control, "modulate", Color.WHITE, 0.6)


## A plain label styled as a table/section header.
static func header_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
	return label
