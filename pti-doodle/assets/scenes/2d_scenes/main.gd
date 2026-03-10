extends Node2D

@export var is_drawing: bool
@export var line_width: float = 10.0
@export var line_color: Color = Color.RED

@onready var object_doodle_container: Node2D = $DoodleContainer

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			is_drawing = true
			current_line = Line2D.new()
			object_doodle_container.add_child(current_line)
		else:
			is_drawing = false

	if Input.is_action_just_released("undo"): 
		undo()

var current_line: Line2D

func _process(_delta: float) -> void:
	if is_drawing:
		current_line.add_point(get_global_mouse_position())
		current_line.width = line_width
		current_line.default_color = line_color
		current_line.joint_mode = Line2D.LINE_JOINT_ROUND
		current_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		current_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		current_line.antialiased = true

func undo() -> void:
	var all_childrens := object_doodle_container.get_children()
	if all_childrens.size() > 0 and not is_drawing:
		all_childrens[all_childrens.size() - 1].queue_free()
