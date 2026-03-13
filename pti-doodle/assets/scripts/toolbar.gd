extends CanvasLayer
class_name Toolbar

@onready var object_ai_guess_label: Label = $VBoxContainer/AiGuessWrapper/AiGuess
@onready var object_certainity_label: Label = $Control/HBoxContainer/Certainity

var _wobble_time: float = 0.0

const FAST_WOBBLE_SPEED: float = 12.0
const FAST_WOBBLE_AMOUNT: float = 4.0
const FAST_WOBBLE_ROTATION: float = 0.03

const DEEP_WOBBLE_SPEED: float = 6.0
const DEEP_WOBBLE_AMOUNT: float = 8.0
const DEEP_WOBBLE_ROTATION: float = 0.05

func _ready() -> void:
	DoodleAi.response_received.connect(func(reply, _is_deep):
		object_ai_guess_label.text = "Czy to: " + reply + "?"
	)
	DoodleAi.certainty_changed.connect(func(color: Color):
		match color:
			Color("d94c4c"):
				object_certainity_label.text = "Niska"
				object_certainity_label.add_theme_color_override("font_color", Color("d94c4c"))
			Color("92d15a"):
				object_certainity_label.text = "Wysoka"
				object_certainity_label.add_theme_color_override("font_color", Color("92d15a"))
			_:
				object_certainity_label.text = "Brak pewności"
				object_certainity_label.add_theme_color_override("font_color", Color("333333"))
	)
	object_certainity_label.text = "Brak pewności"
	object_certainity_label.add_theme_color_override("font_color", Color("333333"))

func _process(delta: float) -> void:
	if DoodleAi.is_awaiting_fast_response:
		_wobble_time += delta * FAST_WOBBLE_SPEED
		_apply_wobble(FAST_WOBBLE_AMOUNT, FAST_WOBBLE_ROTATION)
	elif DoodleAi.is_awaiting_deep_response:
		_wobble_time += delta * DEEP_WOBBLE_SPEED
		_apply_wobble(DEEP_WOBBLE_AMOUNT, DEEP_WOBBLE_ROTATION)
	else:
		_wobble_time = 0.0
		object_ai_guess_label.position = Vector2.ZERO
		object_ai_guess_label.rotation = 0.0

func _apply_wobble(amount: float, rot_amount: float) -> void:
	object_ai_guess_label.pivot_offset = object_ai_guess_label.size / 2.0
	object_ai_guess_label.position = Vector2(
		sin(_wobble_time) * amount,
		cos(_wobble_time * 1.3) * amount
	)
	object_ai_guess_label.rotation = sin(_wobble_time * 0.7) * rot_amount
