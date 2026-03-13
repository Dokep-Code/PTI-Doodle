extends Node

signal AiResponseRecieved(anwser: String)

var brush_color: Color
var brush_eraser_mode: bool = false

var API_KEY: String = FileAccess.open("res://key.txt", FileAccess.READ).get_line()

var ai_response: String:
	set(value):
		ai_response = value
		AiResponseRecieved.emit(value)
