class_name EditableObjectNode
extends Control

signal transform_ended(obj: Control)
signal object_clicked(obj: EditableObjectNode)

const HANDLE_VISUAL := 10.0
const HANDLE_HIT    := 22.0
const MIN_SIZE := Vector2(30.0, 30.0)
const ALL_UPGRADES_MARKER := "res://__all_upgrades__"

func is_all_upgrades() -> bool:
	return source_path == ALL_UPGRADES_MARKER

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
var _price_label: Label = null
var _counter_label: Label = null
var _hover_tween: Tween = null
var _desc_panel: PanelContainer = null

var selected := false:
	set(v):
		selected = v
		queue_redraw()

var group_id := ""
var source_path := ""

func _ready() -> void:
	_price_label = Label.new()
	_price_label.visible = false
	_price_label.z_index = 10
	_price_label.add_theme_color_override("font_color", Color.WHITE)
	_price_label.add_theme_font_size_override("font_size", 14)
	_price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_price_label)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func init(tex: Texture2D, pos: Vector2, sz := Vector2.ZERO) -> void:
	texture_rect.texture = tex
	_aspect_ratio = tex.get_width() / float(tex.get_height())
	if sz == Vector2.ZERO:
		sz = Vector2(200.0, 200.0 / _aspect_ratio)
	position = pos
	size = sz
	_sync_rect_size()
	_setup_counter_label()
	_setup_price_label()
	_setup_desc_panel()

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

func _setup_price_label() -> void:
	if group_id != "upgrade" or is_all_upgrades():
		return
	var upgrade_id := source_path.get_file().get_basename().to_lower()
	if UpgradeManager.UPGRADES.has(upgrade_id):
		var price: float = UpgradeManager.UPGRADES[upgrade_id]["cost"]
		_price_label.text = "$%.0f" % price
		_price_label.size = Vector2(size.x, 30.0)

func _setup_desc_panel() -> void:
	if group_id != "upgrade" or is_all_upgrades():
		return
	var upgrade_id := source_path.get_file().get_basename().to_lower()
	if not UpgradeManager.UPGRADES.has(upgrade_id):
		return
	var data: Dictionary = UpgradeManager.UPGRADES[upgrade_id]

	_desc_panel = PanelContainer.new()
	_desc_panel.visible = false
	_desc_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_panel.z_index = 100

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.12, 0.94)
	style.corner_radius_top_left    = 4
	style.corner_radius_top_right   = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left   = 7.0
	style.content_margin_right  = 7.0
	style.content_margin_top    = 6.0
	style.content_margin_bottom = 6.0
	_desc_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = data["name"]
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "$%.0f" % float(data["cost"])
	price_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45))
	price_lbl.add_theme_font_size_override("font_size", 11)
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(price_lbl)

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = data["desc"]
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.custom_minimum_size = Vector2(180.0, 0.0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)

	add_child(_desc_panel)
	_desc_panel.position = Vector2(size.x + 8.0, 0.0)

func set_gameplay_mode(v: bool) -> void:
	_gameplay_mode = v
	if _counter_label:
		_counter_label.visible = v
	if not v:
		_hide_hover_immediate()
	# Upgrade-group sprites (including the synthetic all_upgrades control) are
	# editor-only handles now — purchasing happens via the ToolsList in main.tscn,
	# so these are masked in gameplay but stay visible+placeable in edit mode.
	if group_id == "upgrade":
		visible = not v

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
	if _price_label:
		_price_label.size = Vector2(size.x, 30.0)
	if _counter_label:
		_counter_label.position = Vector2(size.x + 6, size.y * 0.5 - 12)
	if _desc_panel:
		_desc_panel.position = Vector2(size.x + 8.0, 0.0)
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

func _on_mouse_entered() -> void:
	if not _gameplay_mode or group_id != "upgrade" or is_all_upgrades():
		return
	var upgrade_id := source_path.get_file().get_basename().to_lower()
	if not UpgradeManager.UPGRADES.has(upgrade_id):
		return
	_show_hover()

func _on_mouse_exited() -> void:
	if not _gameplay_mode or group_id != "upgrade" or is_all_upgrades():
		return
	_hide_hover()

func _show_hover() -> void:
	if _hover_tween:
		_hover_tween.kill()
	pivot_offset = size / 2.0
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.12)
	_hover_tween.tween_property(texture_rect, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.12)
	if _desc_panel:
		_desc_panel.visible = true
		_desc_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_hover_tween.tween_property(_desc_panel, "modulate:a", 1.0, 0.18)

func _hide_hover() -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	_hover_tween.tween_property(texture_rect, "modulate", Color.WHITE, 0.1)
	if _desc_panel:
		_hover_tween.tween_property(_desc_panel, "modulate:a", 0.0, 0.1).finished.connect(
			func(): if is_instance_valid(_desc_panel): _desc_panel.visible = false
		)

func _hide_hover_immediate() -> void:
	if _hover_tween:
		_hover_tween.kill()
		_hover_tween = null
	scale = Vector2.ONE
	texture_rect.modulate = Color.WHITE
	if _price_label:
		_price_label.visible = false
	if _desc_panel:
		_desc_panel.visible = false

# --- Gameplay animations ---

func animate_screen_click() -> void:
	pivot_offset = size / 2.0
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.03, 1.03), 0.08)
	t.parallel().tween_property(texture_rect, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.08)
	t.tween_property(self, "scale", Vector2.ONE, 0.15)
	t.parallel().tween_property(texture_rect, "modulate", Color.WHITE, 0.15)

func animate_upgrade_result(success: bool) -> void:
	if success:
		var t := create_tween()
		t.tween_property(texture_rect, "modulate", Color(0.5, 1.0, 0.5, 1.0), 0.1)
		t.tween_property(texture_rect, "modulate", Color.WHITE, 0.3)
	else:
		var t := create_tween()
		t.tween_property(texture_rect, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.1)
		t.tween_property(texture_rect, "modulate", Color.WHITE, 0.3)

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
