extends Node

const SYSTEM_PROMPT := "You are a doodle recognition engine. The user will send you a hand-drawn doodle image.
Identify the single object, animal, symbol, or concept depicted.
Respond with only its name in Polish — one or two words maximum, lowercase, no punctuation or explanation.
Examples: kot, pendrive, dom, sygnalizacja, znak stop."

signal response_received(reply: String, is_deep: bool)

var current_request_type: String = ""
var deep_timer: SceneTreeTimer
var fast_timer: SceneTreeTimer
var http_request: HTTPRequest
var is_awaiting_fast_response: bool = false
var is_awaiting_deep_response: bool = false

func _ready() -> void:
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func recognize(image: Image) -> void:
	http_request.cancel_request()

	fast_timer = get_tree().create_timer(0.3)
	fast_timer.timeout.connect(_send.bind(image, false))

	if deep_timer and deep_timer.timeout.is_connected(_send):
		deep_timer.timeout.disconnect(_send)

	deep_timer = get_tree().create_timer(3.0)
	deep_timer.timeout.connect(_send.bind(image, true))

func _send(image: Image, with_reasoning: bool) -> void:
	var type_label := "deep" if with_reasoning else "fast"
	print("DoodleAI: Sending %s request..." % type_label)

	if with_reasoning:
		is_awaiting_deep_response = true
	else:
		is_awaiting_fast_response = true

	var bg := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	bg.fill(Color.WHITE)
	bg.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)

	var png_bytes: PackedByteArray = bg.save_png_to_buffer()
	var base64_str: String = Marshalls.raw_to_base64(png_bytes)

	var body := {
		"model": "x-ai/grok-4.1-fast",
		"messages": [
			{
				"role": "system",
				"content": SYSTEM_PROMPT
			},
			{
				"role": "user",
				"content": [
					{
						"type": "image_url",
						"image_url": {
							"url": "data:image/png;base64," + base64_str
						}
					},
					{
						"type": "text",
						"text": "What is this?"
					}
				]
			}
		],
		"temperature": 0.7,
		"top_p": 0.95,
		"reasoning": {
			"enabled": with_reasoning
		}
	}

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + Global.API_KEY
	])

	current_request_type = type_label
	http_request.cancel_request()

	http_request.request(
		"https://openrouter.ai/api/v1/chat/completions",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

func _on_request_completed(
	_result: int, _response_code: int,
	_headers: PackedStringArray, body: PackedByteArray
) -> void:
	var is_deep := current_request_type == "deep"

	if is_deep:
		is_awaiting_deep_response = false
	else:
		is_awaiting_fast_response = false

	var body_str := body.get_string_from_utf8()

	var json := JSON.new()
	var err := json.parse(body_str)
	if err != OK:
		push_error("DoodleAI: JSON parse failed")
		return

	var data: Dictionary = json.data
	if data.has("error"):
		push_error("DoodleAI: API error — %s" % str(data["error"]))
		return

	var reply: String = data["choices"][0]["message"]["content"]
	print("DoodleAI (%s): %s" % [current_request_type, reply])
	Global.ai_response = reply
	response_received.emit(reply, is_deep)
