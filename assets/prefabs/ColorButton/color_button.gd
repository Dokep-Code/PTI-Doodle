extends CustomButton
class_name ColorButton

@export var color: Color

@onready var color_rect: ColorRect = $ColorRect

func _ready() -> void:
	super()
	color_rect.color = color
	Global.BrushColorChanged.connect(_on_brush_color_changed)
	button_pressed = (Global.brush_color == color)

func _on_brush_color_changed(new_color: Color) -> void:
	button_pressed = (new_color == color)

func button_action() -> void:
	Global.brush_color = color
