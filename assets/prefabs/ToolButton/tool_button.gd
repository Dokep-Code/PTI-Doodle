extends CustomButton
class_name ToolButton

@export_enum("Pen", "Eraser", "Rectangle", "Ellipse", "Line", "SelectRect", "SelectEllipse", "SelectLasso") var mode: int = 0

func _ready() -> void:
	super()
	Global.DrawModeChanged.connect(_on_draw_mode_changed)
	button_pressed = (Global.draw_mode == mode)

func _on_draw_mode_changed(new_mode: int) -> void:
	button_pressed = (new_mode == mode)

func button_action() -> void:
	Global.draw_mode = mode
