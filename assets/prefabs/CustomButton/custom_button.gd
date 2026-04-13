extends Button
class_name CustomButton

func _ready() -> void:
	button_up.connect(button_action)

func button_action():
	assert(false, "button_action(): Needs to be overwritten in children class")
