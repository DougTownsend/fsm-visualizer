## Editor for a multi-bit value: a SpinBox (a number field with up/down
## arrows) limited to 0 .. 2^width - 1.
##
## It offers the same `edited(new_value)` signal as FSMBitToggle, so code can
## treat both the same way (see FSMUi.value_editor()).
class_name FSMValueSpin
extends SpinBox

signal edited(new_value: int)


func _init() -> void:
	min_value = 0
	step = 1
	rounded = true
	custom_minimum_size = Vector2(70, 0)
	# SpinBox's own signal passes a float; convert and re-emit as an int.
	value_changed.connect(func(v: float) -> void: edited.emit(int(v)))


## Sets the bit width (which sets the maximum) and the value shown, without
## emitting `edited`.
func setup(width: int, initial_value: int) -> void:
	max_value = (1 << width) - 1
	tooltip_text = "%d-bit value (0 to %d)" % [width, max_value]
	set_value_no_signal(initial_value)
