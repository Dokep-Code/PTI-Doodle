extends Control

@export var line_width: float = 10.0
@export var line_color: Color = Color.RED
@export var eraser_width: float = 20.0

var can_draw: bool = true
var is_drawing: bool = false
var is_erasing: bool = false
var canvas_image: Image
var canvas_texture: ImageTexture
var last_point: Vector2
var has_last_point: bool = false
var undo_stack: Array[Image] = []
var stroke_snapshot: Image
var shape_start_point: Vector2
var shape_overlay: Control
var preview_active: bool = false
var preview_to: Vector2
var score_label: Label
var win_label: Label
var coin_player: AudioStreamPlayer

# Selection system
enum SelectionState { NONE, CREATING, READY, MOVING }
var selection_state: SelectionState = SelectionState.NONE
var selection_mask: Image
var selection_bounds: Rect2i
var selection_start: Vector2
var selection_outline: PackedVector2Array
var lasso_points: PackedVector2Array
var floating_pixels: Image
var floating_texture: ImageTexture
var floating_offset: Vector2i
var move_grab_offset: Vector2
var ants_phase: float = 0.0

var last_stroke_time: float = 0.0
const STROKE_COOLDOWN: float = 0.2

@onready var canvas_rect: TextureRect = $MarginContainer/HBoxContainer/VBoxContainer2/Canvas/TextureRect
@onready var canvas_panel: Panel = $MarginContainer/HBoxContainer/VBoxContainer2/Canvas
@onready var draw_target_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/SideBar/VBoxContainer/ToDraw/Label
@onready var ai_guess_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/SideBar/VBoxContainer/WhatIThink/Label
var canvas_size: Vector2i

func _ready() -> void:
	await get_tree().process_frame
	canvas_size = Vector2i(canvas_rect.size)
	print("=== DRAWING BOARD INIT ===")
	print("canvas_size: ", canvas_size)
	print("canvas_rect size: ", canvas_rect.size)
	print("canvas_rect global_position: ", canvas_rect.global_position)
	print("canvas_rect visible: ", canvas_rect.visible)
	print("canvas_rect anchors: ", canvas_rect.anchor_left, ", ", canvas_rect.anchor_top, ", ", canvas_rect.anchor_right, ", ", canvas_rect.anchor_bottom)

	canvas_image = Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	canvas_image.fill(Color.TRANSPARENT)
	print("image created: ", canvas_image.get_size())

	canvas_texture = ImageTexture.create_from_image(canvas_image)
	canvas_rect.texture = canvas_texture
	canvas_rect.stretch_mode = TextureRect.STRETCH_KEEP
	print("texture assigned, size: ", canvas_texture.get_size())

	Global.draw_target = Global.possible_draw_targets.pick_random()

	score_label = $MarginContainer/HBoxContainer/VBoxContainer2/Canvas/ScoreLabel

	win_label = Label.new()
	win_label.text = "DOBRZE!"
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	win_label.add_theme_font_size_override("font_size", 200)
	win_label.add_theme_color_override("font_color", Color("92d15a"))
	win_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_label.visible = false
	canvas_panel.add_child(win_label)

	coin_player = AudioStreamPlayer.new()
	add_child(coin_player)
	_setup_coin_sound()

	selection_mask = Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_L8)
	selection_mask.fill(Color.BLACK)

	var undo_button := $MarginContainer/HBoxContainer/VBoxContainer2/Canvas/ActionButtons/UndoButton
	var clear_button := $MarginContainer/HBoxContainer/VBoxContainer2/Canvas/ActionButtons/ClearButton
	undo_button.pressed.connect(undo)
	clear_button.pressed.connect(clear_canvas)

	Global.GameWon.connect(_on_game_won)
	Global.ScoreChanged.connect(func(s: int): score_label.text = "PUNKTY: %d" % s)
	Global.AiResponseRecieved.connect(func(answer: String):
		ai_guess_label.text = answer if answer != "" else ".........................."
	)
	Global.SelectionCleared.connect(_finalize_and_clear_selection)

	draw_target_label.text = Global.draw_target

	shape_overlay = Control.new()
	shape_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	shape_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_rect.add_child(shape_overlay)
	shape_overlay.draw.connect(_draw_shape_preview)
	print("=== INIT DONE ===")

func _process(delta: float) -> void:
	line_color = Global.brush_color
	if selection_state == SelectionState.READY or selection_state == SelectionState.MOVING:
		ants_phase = fmod(ants_phase + delta * 40.0, 20.0)
		shape_overlay.queue_redraw()

func _input(event: InputEvent) -> void:
	if Global.is_selection_mode:
		_handle_selection_input(event)
	else:
		_handle_drawing_input(event)

	if Input.is_action_just_released("undo"):
		undo()
	if Input.is_action_just_released("send"):
		send_to_ai()

func _handle_drawing_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				_begin_stroke(_get_canvas_pos(event.position))
			else:
				_end_stroke()

	if event is InputEventMouseMotion and is_drawing:
		var pos := _get_canvas_pos(event.position)
		var mode := Global.draw_mode
		if mode == Global.DrawMode.PEN or mode == Global.DrawMode.ERASER:
			_draw_segment(pos)
		else:
			preview_active = true
			preview_to = pos
			shape_overlay.queue_redraw()

func _handle_selection_input(event: InputEvent) -> void:
	if not can_draw:
		return

	if event is InputEventKey and event.physical_keycode == KEY_DELETE and event.is_pressed() and not event.is_echo():
		if selection_state == SelectionState.READY:
			_delete_selected_pixels()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := _get_canvas_pos(event.position)
		if event.is_pressed():
			match selection_state:
				SelectionState.NONE:
					_begin_selection_create(pos)
				SelectionState.READY:
					if _is_inside_selection(pos):
						_begin_selection_move(pos)
					else:
						_finalize_and_clear_selection()
						_begin_selection_create(pos)
		else:
			match selection_state:
				SelectionState.CREATING:
					_finish_selection_create(pos)
				SelectionState.MOVING:
					_finish_selection_move()

	if event is InputEventMouseMotion:
		var pos := _get_canvas_pos(event.position)
		match selection_state:
			SelectionState.CREATING:
				_update_selection_preview(pos)
			SelectionState.MOVING:
				_update_selection_move(pos)

func _begin_stroke(pos: Vector2) -> void:
	if not can_draw:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_stroke_time < STROKE_COOLDOWN:
		print("  -> blocked: cooldown (now=", now, " last=", last_stroke_time, ")")
		return
	last_stroke_time = now

	is_drawing = true
	is_erasing = (Global.draw_mode == Global.DrawMode.ERASER)
	has_last_point = false
	shape_start_point = pos
	preview_active = false

	stroke_snapshot = Image.new()
	stroke_snapshot.copy_from(canvas_image)

func _end_stroke() -> void:
	if is_drawing:
		is_drawing = false
		has_last_point = false

		if preview_active:
			var radius := line_width / 2.0
			match Global.draw_mode:
				Global.DrawMode.RECTANGLE:
					_draw_rect_outline(shape_start_point, preview_to, radius, line_color)
				Global.DrawMode.ELLIPSE:
					_draw_ellipse_outline(shape_start_point, preview_to, radius, line_color)
				Global.DrawMode.LINE:
					_draw_line_on_image(shape_start_point, preview_to, radius, line_color)
			canvas_texture.update(canvas_image)
			preview_active = false
			shape_overlay.queue_redraw()

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

func _draw_rect_outline(from: Vector2, to: Vector2, radius: float, color: Color) -> void:
	var tl := Vector2(min(from.x, to.x), min(from.y, to.y))
	var tr := Vector2(max(from.x, to.x), min(from.y, to.y))
	var bl := Vector2(min(from.x, to.x), max(from.y, to.y))
	var br := Vector2(max(from.x, to.x), max(from.y, to.y))
	_draw_line_on_image(tl, tr, radius, color)
	_draw_line_on_image(tr, br, radius, color)
	_draw_line_on_image(br, bl, radius, color)
	_draw_line_on_image(bl, tl, radius, color)

func _draw_ellipse_outline(from: Vector2, to: Vector2, radius: float, color: Color) -> void:
	var center := (from + to) / 2.0
	var rx = abs(to.x - from.x) / 2.0
	var ry = abs(to.y - from.y) / 2.0
	if rx < 1.0 and ry < 1.0:
		_draw_circle_on_image(center, radius, color)
		return
	var steps := maxi(int(max(rx, ry) * 2.0), 36)
	var prev_point := center + Vector2(rx, 0.0)
	for i in range(1, steps + 1):
		var angle := TAU * float(i) / float(steps)
		var point := center + Vector2(cos(angle) * rx, sin(angle) * ry)
		_draw_line_on_image(prev_point, point, radius, color)
		prev_point = point

func _draw_shape_preview() -> void:
	# Drawing tool previews
	if preview_active and not Global.is_selection_mode:
		var from := shape_start_point
		var to := preview_to
		match Global.draw_mode:
			Global.DrawMode.RECTANGLE:
				var rect := Rect2(
					Vector2(min(from.x, to.x), min(from.y, to.y)),
					Vector2(abs(to.x - from.x), abs(to.y - from.y))
				)
				shape_overlay.draw_rect(rect, line_color, false, line_width)
			Global.DrawMode.ELLIPSE:
				var center := (from + to) / 2.0
				var rx = abs(to.x - from.x) / 2.0
				var ry = abs(to.y - from.y) / 2.0
				var points := PackedVector2Array()
				for i in range(65):
					var angle := TAU * float(i) / 64.0
					points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
				if points.size() >= 2:
					shape_overlay.draw_polyline(points, line_color, line_width)
			Global.DrawMode.LINE:
				shape_overlay.draw_line(from, to, line_color, line_width)

	# Selection creation preview (dashed outline)
	if selection_state == SelectionState.CREATING and preview_active:
		var from := selection_start
		var to := preview_to
		match Global.draw_mode:
			Global.DrawMode.SELECT_RECT:
				var outline := PackedVector2Array([
					Vector2(min(from.x, to.x), min(from.y, to.y)),
					Vector2(max(from.x, to.x), min(from.y, to.y)),
					Vector2(max(from.x, to.x), max(from.y, to.y)),
					Vector2(min(from.x, to.x), max(from.y, to.y)),
					Vector2(min(from.x, to.x), min(from.y, to.y)),
				])
				_draw_dashed_polyline(outline, 0.0)
			Global.DrawMode.SELECT_ELLIPSE:
				var center := (from + to) / 2.0
				var rx = abs(to.x - from.x) / 2.0
				var ry = abs(to.y - from.y) / 2.0
				var points := PackedVector2Array()
				for i in range(65):
					var angle := TAU * float(i) / 64.0
					points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
				_draw_dashed_polyline(points, 0.0)
			Global.DrawMode.SELECT_LASSO:
				if lasso_points.size() >= 2:
					_draw_dashed_polyline(lasso_points, 0.0)

	# Selection ready / moving (marching ants)
	if (selection_state == SelectionState.READY or selection_state == SelectionState.MOVING) and selection_outline.size() >= 2:
		var offset := Vector2.ZERO
		if selection_state == SelectionState.MOVING:
			offset = Vector2(floating_offset - selection_bounds.position)
		var shifted := PackedVector2Array()
		for p in selection_outline:
			shifted.append(p + offset)
		_draw_dashed_polyline(shifted, ants_phase)

	# Floating pixels during move
	if selection_state == SelectionState.MOVING and floating_texture:
		shape_overlay.draw_texture(floating_texture, Vector2(floating_offset))

func _draw_dashed_polyline(points: PackedVector2Array, phase: float) -> void:
	var dash := 8.0
	var gap := 6.0
	var cycle := dash + gap
	for i in range(points.size() - 1):
		var from := points[i]
		var to := points[i + 1]
		var dir := to - from
		var seg_len := dir.length()
		if seg_len < 0.1:
			continue
		var unit := dir / seg_len
		var d := fmod(-phase, cycle)
		if d < 0:
			d += cycle
		while d < seg_len:
			var start := from + unit * maxf(d, 0.0)
			var end := from + unit * minf(d + dash, seg_len)
			shape_overlay.draw_line(start, end, Color.WHITE, 2.0)
			shape_overlay.draw_line(start + Vector2(1, 1), end + Vector2(1, 1), Color.BLACK, 1.0)
			d += cycle

# --- Selection creation ---

func _begin_selection_create(pos: Vector2) -> void:
	selection_state = SelectionState.CREATING
	selection_start = pos
	preview_to = pos
	preview_active = true
	lasso_points.clear()
	lasso_points.append(pos)
	shape_overlay.queue_redraw()

func _update_selection_preview(pos: Vector2) -> void:
	preview_to = pos
	if Global.draw_mode == Global.DrawMode.SELECT_LASSO:
		if lasso_points.size() == 0 or lasso_points[lasso_points.size() - 1].distance_to(pos) > 3.0:
			lasso_points.append(pos)
	shape_overlay.queue_redraw()

func _finish_selection_create(pos: Vector2) -> void:
	preview_active = false
	match Global.draw_mode:
		Global.DrawMode.SELECT_RECT:
			_build_rect_mask(selection_start, pos)
		Global.DrawMode.SELECT_ELLIPSE:
			_build_ellipse_mask(selection_start, pos)
		Global.DrawMode.SELECT_LASSO:
			lasso_points.append(pos)
			_build_lasso_mask(lasso_points)

	if selection_bounds.size.x < 2 or selection_bounds.size.y < 2:
		_clear_selection()
	else:
		selection_state = SelectionState.READY
	shape_overlay.queue_redraw()

# --- Mask building ---

func _build_rect_mask(from: Vector2, to: Vector2) -> void:
	selection_mask.fill(Color.BLACK)
	var x0 := clampi(int(min(from.x, to.x)), 0, canvas_size.x - 1)
	var y0 := clampi(int(min(from.y, to.y)), 0, canvas_size.y - 1)
	var x1 := clampi(int(max(from.x, to.x)), 0, canvas_size.x - 1)
	var y1 := clampi(int(max(from.y, to.y)), 0, canvas_size.y - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			selection_mask.set_pixel(x, y, Color.WHITE)
	selection_bounds = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	selection_outline = PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1), Vector2(x0, y0)
	])

func _build_ellipse_mask(from: Vector2, to: Vector2) -> void:
	selection_mask.fill(Color.BLACK)
	var cx := (from.x + to.x) / 2.0
	var cy := (from.y + to.y) / 2.0
	var rx = abs(to.x - from.x) / 2.0
	var ry = abs(to.y - from.y) / 2.0
	var x0 := clampi(int(cx - rx), 0, canvas_size.x - 1)
	var y0 := clampi(int(cy - ry), 0, canvas_size.y - 1)
	var x1 := clampi(int(cx + rx), 0, canvas_size.x - 1)
	var y1 := clampi(int(cy + ry), 0, canvas_size.y - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var nx := (float(x) - cx) / maxf(rx, 0.001)
			var ny := (float(y) - cy) / maxf(ry, 0.001)
			if nx * nx + ny * ny <= 1.0:
				selection_mask.set_pixel(x, y, Color.WHITE)
	selection_bounds = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	var outline := PackedVector2Array()
	for i in 65:
		var angle := TAU * float(i) / 64.0
		outline.append(Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry))
	selection_outline = outline

func _build_lasso_mask(points: PackedVector2Array) -> void:
	selection_mask.fill(Color.BLACK)
	if points.size() < 3:
		selection_bounds = Rect2i()
		selection_outline = PackedVector2Array()
		return
	var min_p := points[0]
	var max_p := points[0]
	for p in points:
		min_p = Vector2(min(min_p.x, p.x), min(min_p.y, p.y))
		max_p = Vector2(max(max_p.x, p.x), max(max_p.y, p.y))
	var x0 := clampi(int(min_p.x), 0, canvas_size.x - 1)
	var y0 := clampi(int(min_p.y), 0, canvas_size.y - 1)
	var x1 := clampi(int(max_p.x), 0, canvas_size.x - 1)
	var y1 := clampi(int(max_p.y), 0, canvas_size.y - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), points):
				selection_mask.set_pixel(x, y, Color.WHITE)
	selection_bounds = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	var outline := points.duplicate()
	outline.append(points[0])
	selection_outline = outline

# --- Selection operations ---

func _is_inside_selection(pos: Vector2) -> bool:
	var px := int(pos.x)
	var py := int(pos.y)
	if px < 0 or px >= canvas_size.x or py < 0 or py >= canvas_size.y:
		return false
	return selection_mask.get_pixel(px, py).r > 0.5

func _begin_selection_move(pos: Vector2) -> void:
	stroke_snapshot = Image.new()
	stroke_snapshot.copy_from(canvas_image)

	selection_state = SelectionState.MOVING
	floating_offset = selection_bounds.position
	move_grab_offset = pos - Vector2(floating_offset)

	floating_pixels = Image.create(selection_bounds.size.x, selection_bounds.size.y, false, Image.FORMAT_RGBA8)
	floating_pixels.fill(Color.TRANSPARENT)
	for y in range(selection_bounds.size.y):
		for x in range(selection_bounds.size.x):
			var gx := selection_bounds.position.x + x
			var gy := selection_bounds.position.y + y
			if gx >= 0 and gx < canvas_size.x and gy >= 0 and gy < canvas_size.y:
				if selection_mask.get_pixel(gx, gy).r > 0.5:
					floating_pixels.set_pixel(x, y, canvas_image.get_pixel(gx, gy))
					canvas_image.set_pixel(gx, gy, Color.TRANSPARENT)
	canvas_texture.update(canvas_image)
	floating_texture = ImageTexture.create_from_image(floating_pixels)

func _update_selection_move(pos: Vector2) -> void:
	floating_offset = Vector2i(pos - move_grab_offset)
	shape_overlay.queue_redraw()

func _finish_selection_move() -> void:
	for y in range(floating_pixels.get_height()):
		for x in range(floating_pixels.get_width()):
			var px := floating_offset.x + x
			var py := floating_offset.y + y
			if px < 0 or px >= canvas_size.x or py < 0 or py >= canvas_size.y:
				continue
			var src := floating_pixels.get_pixel(x, y)
			if src.a > 0.001:
				var dst := canvas_image.get_pixel(px, py)
				canvas_image.set_pixel(px, py, _blend_over(dst, src))
	canvas_texture.update(canvas_image)

	var delta := floating_offset - selection_bounds.position
	var new_mask := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_L8)
	new_mask.fill(Color.BLACK)
	var new_outline := PackedVector2Array()
	for p in selection_outline:
		new_outline.append(p + Vector2(delta))
	for y in range(selection_bounds.size.y):
		for x in range(selection_bounds.size.x):
			var old_gx := selection_bounds.position.x + x
			var old_gy := selection_bounds.position.y + y
			if old_gx >= 0 and old_gx < canvas_size.x and old_gy >= 0 and old_gy < canvas_size.y:
				if selection_mask.get_pixel(old_gx, old_gy).r > 0.5:
					var new_gx := old_gx + delta.x
					var new_gy := old_gy + delta.y
					if new_gx >= 0 and new_gx < canvas_size.x and new_gy >= 0 and new_gy < canvas_size.y:
						new_mask.set_pixel(new_gx, new_gy, Color.WHITE)
	selection_mask = new_mask
	selection_outline = new_outline
	selection_bounds = Rect2i(
		clampi(selection_bounds.position.x + delta.x, 0, canvas_size.x),
		clampi(selection_bounds.position.y + delta.y, 0, canvas_size.y),
		selection_bounds.size.x, selection_bounds.size.y
	)

	floating_pixels = null
	floating_texture = null
	selection_state = SelectionState.READY

	if stroke_snapshot:
		undo_stack.append(stroke_snapshot)
		stroke_snapshot = null
	send_to_ai()

func _delete_selected_pixels() -> void:
	stroke_snapshot = Image.new()
	stroke_snapshot.copy_from(canvas_image)

	for y in range(selection_bounds.size.y):
		for x in range(selection_bounds.size.x):
			var gx := selection_bounds.position.x + x
			var gy := selection_bounds.position.y + y
			if gx >= 0 and gx < canvas_size.x and gy >= 0 and gy < canvas_size.y:
				if selection_mask.get_pixel(gx, gy).r > 0.5:
					canvas_image.set_pixel(gx, gy, Color.TRANSPARENT)
	canvas_texture.update(canvas_image)

	undo_stack.append(stroke_snapshot)
	stroke_snapshot = null
	_clear_selection()
	send_to_ai()

func _finalize_and_clear_selection() -> void:
	if selection_state == SelectionState.MOVING and floating_pixels:
		_finish_selection_move()
	_clear_selection()

func _clear_selection() -> void:
	selection_state = SelectionState.NONE
	if selection_mask:
		selection_mask.fill(Color.BLACK)
	selection_bounds = Rect2i()
	selection_outline = PackedVector2Array()
	floating_pixels = null
	floating_texture = null
	lasso_points.clear()
	preview_active = false
	shape_overlay.queue_redraw()

func _get_canvas_pos(screen_pos: Vector2) -> Vector2:
	return screen_pos - canvas_rect.global_position

func undo() -> void:
	if not can_draw or is_drawing:
		return
	if selection_state == SelectionState.MOVING:
		if stroke_snapshot:
			canvas_image.copy_from(stroke_snapshot)
			canvas_texture.update(canvas_image)
			stroke_snapshot = null
		_clear_selection()
		return
	if selection_state != SelectionState.NONE:
		_clear_selection()
		return
	if undo_stack.size() > 0:
		canvas_image.copy_from(undo_stack.pop_back())
		canvas_texture.update(canvas_image)
		send_to_ai()

func clear_canvas() -> void:
	if not can_draw or is_drawing:
		return
	_finalize_and_clear_selection()
	undo_stack.append(canvas_image.duplicate())
	canvas_image.fill(Color.TRANSPARENT)
	canvas_texture.update(canvas_image)
	send_to_ai()

func send_to_ai() -> void:
	DoodleAi.recognize(canvas_image)

func _on_game_won() -> void:
	Global.score += 1
	coin_player.play()

	can_draw = false
	is_drawing = false
	has_last_point = false
	stroke_snapshot = null
	_clear_selection()
	canvas_image.fill(Color.TRANSPARENT)
	canvas_texture.update(canvas_image)
	undo_stack.clear()

	win_label.visible = true
	win_label.modulate = Color.WHITE

	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.tween_property(win_label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func():
		win_label.visible = false
		Global.pick_new_draw_target()
		draw_target_label.text = Global.draw_target
		Global.ai_response = ""
		can_draw = true
	)

func _setup_coin_sound() -> void:
	if ResourceLoader.exists("res://assets/audio/coin.wav"):
		coin_player.stream = load("res://assets/audio/coin.wav")
		return

	var sample_rate := 22050
	var duration := 0.15
	var samples := int(sample_rate * duration * 2)
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false

	var data := PackedByteArray()
	data.resize(samples * 2)
	var half := samples / 2
	for i in samples:
		var freq := 880.0 if i < half else 1320.0
		var t := float(i) / float(sample_rate)
		var envelope := 1.0 - (float(i % half) / float(half))
		var value := sin(t * freq * TAU) * envelope * 0.5
		var sample_16 := int(clampf(value, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample_16)

	audio.data = data
	coin_player.stream = audio
