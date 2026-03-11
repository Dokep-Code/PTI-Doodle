extends CanvasLayer
class_name Toolbar

@onready var object_ai_guess_label: Label = $AiGuess
@onready var object_ai_guess_label_animation_player: AnimationPlayer = $AiGuess/AnimationPlayer


func _ready() -> void:
	DoodleAi.response_received.connect(func(reply, _is_deep):
		object_ai_guess_label.text = reply
	)

func _process(_delta: float) -> void:
	if DoodleAi.is_awaiting_fast_response:
		#object_ai_guess_label.add_theme_font_size_override("font_size", randi_range(10, 60))
		object_ai_guess_label_animation_player.play("fast_response")
	elif DoodleAi.is_awaiting_deep_response:
		#object_ai_guess_label.add_theme_font_size_override("font_size", randi_range(60, 120))
		object_ai_guess_label_animation_player.play("deep_response")
	else:
		#object_ai_guess_label.add_theme_font_size_override("font_size", 64)
		object_ai_guess_label_animation_player.play("RESET")
