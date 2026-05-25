class_name EditableObjectNode
extends Control

signal transform_ended(obj: Control)
signal object_clicked(obj: EditableObjectNode)

const HANDLE_VISUAL := 10.0
const HANDLE_HIT    := 22.0
const MIN_SIZE := Vector2(30.0, 30.0)

@onready var texture_rect: TextureRect = $TextureRect

var _aspect_ratio := 1.0
var _dragging := false
var _drag_start_mouse := Vector2.ZERO
var _drag_start_pos := Vector2.ZERO
var _resizing := false
var _resize_handle := -1
var _resize_start_mouse := Vector2.ZERO
var _resize_start_rect := Rect2()

var _gameplay_mode := false
var _counter_label: Label = null

var selected := false:
	set(v):
		selected = v
		queue_redraw()

var group_id := ""
var source_path := ""

func init(tex: Texture2D, pos: Vector2, sz := Vector2.ZERO) -> void:
	texture_rect.texture = tex
	_aspect_ratio = tex.get_width() / float(tex.get_height())
	if sz == Vector2.ZERO:
		sz = Vector2(200.0, 200.0 / _aspect_ratio)
	position = pos
	size = sz
	_sync_rect_size()
	_setup_counter_label()

func _setup_counter_label() -> void:
	if group_id != "screen":
		return
	var base := source_path.get_file().get_basename().to_lower()
	var initial := ""
	if base == "view":
		initial = str(GameManager.views)
		GameManager.views_changed.connect(func(v: int) -> void:
			if is_instance_valid(_counter_label): _counter_label.text = str(v))
	elif base == "sub":
		initial = str(GameManager.subs)
		GameManager.subs_changed.connect(func(v: int) -> void:
			if is_instance_valid(_counter_label): _counter_label.text = str(v))
	else:
		return
	_counter_label = Label.new()
	_counter_label.text = initial
	_counter_label.visible = false
	_counter_label.add_theme_color_override("font_color", Color.WHITE)
	_counter_label.add_theme_font_size_override("font_size", 18)
	_counter_label.add_theme_constant_override("outline_size", 3)
	_counter_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_counter_label.position = Vector2(size.x + 6, size.y * 0.5 - 12)
	var font := load("res://fonts/GoodOldDOS.ttf") as FontFile
	if font:
		_counter_label.add_theme_font_override("font", font)
	add_child(_counter_label)

func set_gameplay_mode(v: bool) -> void:
	_gameplay_mode = v
	if _counter_label:
		_counter_label.visible = v

func get_state() -> Dictionary:
	return { "path": source_path, "group": group_id, "pos": position, "size": size, "z_index": z_index }

func apply_state(state: Dictionary) -> void:
	position = state["pos"]
	size = state["size"]
	_sync_rect_size()

func _sync_rect_size() -> void:
	texture_rect.position = Vector2.ZERO
	texture_rect.size = size
	custom_minimum_size = MIN_SIZE
	if _counter_label:
		_counter_label.position = Vector2(size.x + 6, size.y * 0.5 - 12)
	queue_redraw()

func _draw() -> void:
	if not selected or _gameplay_mode:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, 0.9), false, 2.0)
	for r in _handle_rects():
		draw_rect(r, Color.WHITE, true)
		draw_rect(r, Color(0.2, 0.2, 0.2), false, 1.0)

func _handle_rects() -> Array:
	var h := HANDLE_VISUAL
	var h2 := h / 2.0
	var w := size.x
	var ht := size.y
	return [
		Rect2(-h2, -h2, h, h),
		Rect2(w - h2, -h2, h, h),
		Rect2(-h2, ht - h2, h, h),
		Rect2(w - h2, ht - h2, h, h),
	]

func _hit_handle(local_pos: Vector2) -> int:
	var h := HANDLE_HIT
	var h2 := h / 2.0
	var w := size.x
	var ht := size.y
	var hit_rects := [
		Rect2(-h2, -h2, h, h),
		Rect2(w - h2, -h2, h, h),
		Rect2(-h2, ht - h2, h, h),
		Rect2(w - h2, ht - h2, h, h),
	]
	for i in hit_rects.size():
		if hit_rects[i].has_point(local_pos):
			return i
	return -1

func _gui_input(event: InputEvent) -> void:
	if _gameplay_mode:
		_handle_gameplay_input(event)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			get_viewport().set_input_as_handled()
			var lp := get_local_mouse_position()
			_resize_handle = _hit_handle(lp)
			if _resize_handle >= 0:
				_resizing = true
				_resize_start_mouse = get_global_mouse_position()
				_resize_start_rect = Rect2(position, size)
			else:
				_dragging = true
				_drag_start_mouse = get_global_mouse_position()
				_drag_start_pos = position
			selected = true
			object_clicked.emit(self)
		else:
			if _dragging or _resizing:
				transform_ended.emit(self)
			_dragging = false
			_resizing = false

	elif event is InputEventMouseMotion:
		if _dragging:
			position = _drag_start_pos + (get_global_mouse_position() - _drag_start_mouse)
		elif _resizing:
			_apply_resize()
			queue_redraw()

func _handle_gameplay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		object_clicked.emit(self)

func animate_screen_click() -> void:
	pivot_offset = size / 2.0
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.03, 1.03), 0.08)
	t.parallel().tween_property(texture_rect, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.08)
	t.tween_property(self, "scale", Vector2.ONE, 0.15)
	t.parallel().tween_property(texture_rect, "modulate", Color.WHITE, 0.15)

func _apply_resize() -> void:
	var delta := get_global_mouse_position() - _resize_start_mouse
	var sr := _resize_start_rect
	var new_w: float
	var new_h: float
	match _resize_handle:
		0:  # TL — bottom-right fixed
			new_w = max(sr.size.x - delta.x, MIN_SIZE.x)
			new_h = new_w / _aspect_ratio
			position = Vector2(sr.end.x - new_w, sr.end.y - new_h)
		1:  # TR — bottom-left fixed
			new_w = max(sr.size.x + delta.x, MIN_SIZE.x)
			new_h = new_w / _aspect_ratio
			position = Vector2(sr.position.x, sr.end.y - new_h)
		2:  # BL — top-right fixed
			new_w = max(sr.size.x - delta.x, MIN_SIZE.x)
			new_h = new_w / _aspect_ratio
			position = Vector2(sr.end.x - new_w, sr.position.y)
		3:  # BR — top-left fixed
			new_w = max(sr.size.x + delta.x, MIN_SIZE.x)
			new_h = new_w / _aspect_ratio
			position = sr.position
	size = Vector2(new_w, new_h)
	_sync_rect_size()
