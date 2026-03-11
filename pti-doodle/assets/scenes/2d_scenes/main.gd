extends Node2D

@export var line_width: float = 10.0
@export var line_color: Color = Color.RED
@export var eraser_width: float = 20.0
@export var canvas_size: Vector2i = Vector2i(1280, 720)

var is_drawing: bool = false
var is_erasing: bool = false
var canvas_image: Image
var canvas_texture: ImageTexture
var last_point: Vector2
var has_last_point: bool = false
var undo_stack: Array[Image] = []
var stroke_snapshot: Image

var last_stroke_time: float = 0.0
const STROKE_COOLDOWN: float = 0.2

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	canvas_image = Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	canvas_image.fill(Color.TRANSPARENT)
	canvas_texture = ImageTexture.create_from_image(canvas_image)
	sprite.texture = canvas_texture
	sprite.centered = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				Global.brush_eraser_mode = false
				_begin_stroke()
			else:
				_end_stroke()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.is_pressed():
				Global.brush_eraser_mode = true
				_begin_stroke()
			else:
				_end_stroke()

	if event is InputEventMouseMotion and is_drawing:
		var pos := _get_canvas_pos(event.position)
		_draw_segment(pos)
		
		

	if Input.is_action_just_released("undo"):
		undo()

	if Input.is_action_just_released("send"):
		send_to_ai()

func _begin_stroke() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_stroke_time < STROKE_COOLDOWN:
		return
	last_stroke_time = now
	
	is_drawing = true
	is_erasing = Global.brush_eraser_mode
	has_last_point = false

	# Save snapshot for undo
	stroke_snapshot = Image.new()
	stroke_snapshot.copy_from(canvas_image)

func _end_stroke() -> void:
	if is_drawing:
		is_drawing = false
		has_last_point = false

		# Push snapshot to undo stack
		if stroke_snapshot:
			undo_stack.append(stroke_snapshot)
			stroke_snapshot = null

		send_to_ai()

func _draw_segment(pos: Vector2) -> void:
	var radius: float = (eraser_width if is_erasing else line_width) / 2.0
	var color: Color = Color.TRANSPARENT if is_erasing else line_color

	if has_last_point:
		_draw_line_on_image(last_point, pos, radius, color)
	else:
		_draw_circle_on_image(pos, radius, color)

	last_point = pos
	has_last_point = true
	canvas_texture.update(canvas_image)

func _draw_line_on_image(from: Vector2, to: Vector2, radius: float, color: Color) -> void:
	var dist := from.distance_to(to)
	var steps := maxi(int(dist), 1)

	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var point := from.lerp(to, t)
		_draw_circle_on_image(point, radius, color)

func _draw_circle_on_image(center: Vector2, radius: float, color: Color) -> void:
	var r_ceil := int(ceil(radius))
	var cx := int(center.x)
	var cy := int(center.y)
	var r_sq := radius * radius

	for dy in range(-r_ceil, r_ceil + 1):
		for dx in range(-r_ceil, r_ceil + 1):
			if dx * dx + dy * dy > r_sq:
				continue
			var px := cx + dx
			var py := cy + dy
			if px < 0 or px >= canvas_size.x or py < 0 or py >= canvas_size.y:
				continue
			if is_erasing:
				canvas_image.set_pixel(px, py, color)
			else:
				# Blend over existing
				var existing := canvas_image.get_pixel(px, py)
				var blended := _blend_over(existing, color)
				canvas_image.set_pixel(px, py, blended)

func _blend_over(dst: Color, src: Color) -> Color:
	var out_a := src.a + dst.a * (1.0 - src.a)
	if out_a < 0.001:
		return Color.TRANSPARENT
	var out_r := (src.r * src.a + dst.r * dst.a * (1.0 - src.a)) / out_a
	var out_g := (src.g * src.a + dst.g * dst.a * (1.0 - src.a)) / out_a
	var out_b := (src.b * src.a + dst.b * dst.a * (1.0 - src.a)) / out_a
	return Color(out_r, out_g, out_b, out_a)

func _get_canvas_pos(screen_pos: Vector2) -> Vector2:
	return screen_pos - sprite.global_position

func undo() -> void:
	if undo_stack.size() > 0 and not is_drawing:
		canvas_image.copy_from(undo_stack.pop_back())
		canvas_texture.update(canvas_image)

func send_to_ai() -> void:
	DoodleAi.recognize(canvas_image)

func _process(_delta: float) -> void:
	line_color = Global.brush_color
