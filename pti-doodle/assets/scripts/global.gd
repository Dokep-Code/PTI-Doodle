extends Node

signal AiResponseRecieved(anwser: String)

var brush_color: Color
var brush_eraser_mode: bool = false

const API_KEY: String = "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"

var ai_response: String:
	set(value):
		ai_response = value
		AiResponseRecieved.emit(value)
