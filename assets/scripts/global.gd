extends Node

signal AiResponseRecieved(anwser: String)
signal GameWon()
signal BrushColorChanged(color: Color)
signal DrawModeChanged(mode: DrawMode)
signal ScoreChanged(new_score: int)
signal SelectionCleared()

enum DrawMode { PEN, ERASER, RECTANGLE, ELLIPSE, LINE, SELECT_RECT, SELECT_ELLIPSE, SELECT_LASSO }

var brush_color: Color:
	set(value):
		BrushColorChanged.emit(value)
		brush_color = value

var draw_mode: DrawMode = DrawMode.PEN:
	set(value):
		var was_selection := is_selection_mode
		draw_mode = value
		DrawModeChanged.emit(value)
		if was_selection and not is_selection_mode:
			SelectionCleared.emit()

var is_selection_mode: bool:
	get:
		return draw_mode in [DrawMode.SELECT_RECT, DrawMode.SELECT_ELLIPSE, DrawMode.SELECT_LASSO]

var brush_eraser_mode: bool:
	get:
		return draw_mode == DrawMode.ERASER
	set(value):
		draw_mode = DrawMode.ERASER if value else DrawMode.PEN

var API_KEY: String = FileAccess.open("res://key.txt", FileAccess.READ).get_line()

var ai_response: String:
	set(value):
		ai_response = value
		compare_draw_target_with_ai_response(value)
		AiResponseRecieved.emit(value)

var score: int = 0:
	set(value):
		score = value
		ScoreChanged.emit(value)

var possible_draw_targets: Array
var draw_target: String

func _ready() -> void:
	possible_draw_targets = get_all_items_from_file()

func get_all_items_from_file() -> Array:
	var result: Array
	var file = FileAccess.open("res://assets/resources/items.txt", FileAccess.READ)
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if not line.is_empty():
			result.append(line)
	return result

func compare_draw_target_with_ai_response(ai_response: String) -> bool:
	var target_words := draw_target.to_lower().split(" ", false)
	var response_words := ai_response.to_lower().strip_edges().strip_escapes().split(" ", false)

	for response_word in response_words:
		for target_word in target_words:
			if target_word.similarity(response_word) >= 0.7:
				GameWon.emit()
				return true
	return false

func pick_new_draw_target() -> void:
	var old_target := draw_target
	var new_target = possible_draw_targets.pick_random()
	while new_target == old_target and possible_draw_targets.size() > 1:
		new_target = possible_draw_targets.pick_random()
	draw_target = new_target
