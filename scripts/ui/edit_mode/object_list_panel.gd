extends Panel

signal row_selected(canvas_obj: EditableObjectNode)
signal order_changed(from_idx: int, to_idx: int)
signal file_dropped(path: String)
signal z_indices_changed
# Emitted when the Group Layer eye is clicked — the owning EditMode applies
# the new visibility to every non-group-layer object in the group.
signal group_layer_visibility_toggled(group_id: String, visible: bool)

const ROW_HEIGHT := 56.0
const THUMB_SIZE := 48.0
const GROUP_LAYER_MARKER := "res://__group_layer__"

@onready var title_label: Label = $VBox/TitleLabel
@onready var item_vbox: VBoxContainer = $VBox/Scroll/ItemList

var current_group := ""
var _rows: Array = []       # [{row, canvas_obj}]
var _selected_row: Control = null
var _dragging_row: Control = null

# --- OS drag-drop (import) ---

func _can_drop_data(_pos: Vector2, data) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("files")

func _drop_data(_pos: Vector2, data) -> void:
	if typeof(data) == TYPE_DICTIONARY and data.has("files"):
		for path in data["files"]:
			file_dropped.emit(path)

# --- Public API ---

func set_group_label(group: String) -> void:
	current_group = group
	title_label.text = "OBJECT LIST  [%s]" % group.to_upper()

func refresh(placed_objects: Array) -> void:
	_clear()
	# Pin the Group Layer row at the top.
	var pinned: EditableObjectNode = null
	for obj in placed_objects:
		if is_instance_valid(obj) and _is_pinned(obj):
			pinned = obj
			break
	if pinned != null:
		_append_row(pinned)
	# Sort non-pinned by z_index descending so the list order always matches
	# the saved visual layer order, regardless of _placed[] array order.
	var non_pinned: Array = []
	for obj in placed_objects:
		if is_instance_valid(obj) and not _is_pinned(obj):
			non_pinned.append(obj)
	non_pinned.sort_custom(func(a, b): return a.z_index > b.z_index)
	for obj in non_pinned:
		_append_row(obj)
	_update_z_indices()

func add_placed_object(obj: EditableObjectNode) -> void:
	_append_row(obj)
	# Keep the pinned row at the top of the vbox if a non-pinned object was
	# just appended after it.
	if not _is_pinned(obj):
		_move_pinned_to_top()
	_update_z_indices()

func _is_pinned(obj: EditableObjectNode) -> bool:
	return obj != null and obj.source_path == GROUP_LAYER_MARKER

func _move_pinned_to_top() -> void:
	for i in _rows.size():
		var obj: EditableObjectNode = _rows[i]["canvas_obj"]
		if is_instance_valid(obj) and _is_pinned(obj) and i != 0:
			item_vbox.move_child(_rows[i]["row"], 0)
			var entry: Dictionary = _rows[i]
			_rows.remove_at(i)
			_rows.insert(0, entry)
			return

func remove_object(obj: EditableObjectNode) -> void:
	for i in _rows.size():
		if _rows[i]["canvas_obj"] == obj:
			_rows[i]["row"].queue_free()
			_rows.remove_at(i)
			break
	_update_z_indices()

func select_object(obj: EditableObjectNode) -> void:
	highlight_objects([obj])

func highlight_objects(objects: Array) -> void:
	for entry in _rows:
		_set_row_highlight(entry["row"], entry["canvas_obj"] in objects)
	_selected_row = null
	for entry in _rows:
		if entry["canvas_obj"] in objects:
			_selected_row = entry["row"]
			break

# --- Build rows ---

func _append_row(obj: EditableObjectNode) -> void:
	var tex: Texture2D = obj.texture_rect.texture if obj.texture_rect.texture else null
	var row := _make_row(obj, tex)
	item_vbox.add_child(row)
	var hbox_ref := row.get_child(0) as HBoxContainer
	var eye_ref := hbox_ref.get_child(hbox_ref.get_child_count() - 1) as Button
	_rows.append({"row": row, "canvas_obj": obj, "eye_btn": eye_ref})

func _make_row(obj: EditableObjectNode, tex: Texture2D) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	var thumb := TextureRect.new()
	thumb.texture = tex
	thumb.custom_minimum_size = Vector2(THUMB_SIZE, THUMB_SIZE)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(thumb)

	var lbl := Label.new()
	var _display_name: String
	if obj.source_path == GROUP_LAYER_MARKER:
		_display_name = "Group Layer"
	elif obj.source_path != "":
		_display_name = obj.source_path.get_file().get_basename()
	else:
		_display_name = "object"
	lbl.text = _display_name
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	var eye_btn := Button.new()
	eye_btn.toggle_mode = true
	eye_btn.button_pressed = obj.layer_visible
	eye_btn.text = "👁"
	eye_btn.flat = true
	eye_btn.custom_minimum_size = Vector2(30, 0)
	eye_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	eye_btn.modulate = Color.WHITE if obj.layer_visible else Color(1.0, 1.0, 1.0, 0.3)
	if obj.is_group_layer():
		eye_btn.toggled.connect(func(pressed: bool) -> void:
			obj.layer_visible = pressed
			eye_btn.modulate = Color.WHITE if pressed else Color(1.0, 1.0, 1.0, 0.3)
			group_layer_visibility_toggled.emit(obj.group_id, pressed)
		)
	else:
		eye_btn.toggled.connect(func(pressed: bool) -> void:
			obj.layer_visible = pressed
			obj.visible = pressed
			eye_btn.modulate = Color.WHITE if pressed else Color(1.0, 1.0, 1.0, 0.3)
		)
	hbox.add_child(eye_btn)

	panel.gui_input.connect(_on_row_gui_input.bind(panel))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return panel

# --- Drag reorder (tracked at Panel level so mouse can leave the row) ---

func _input(event: InputEvent) -> void:
	if not visible or _dragging_row == null:
		return
	if event is InputEventMouseMotion:
		_check_swap()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging_row = null

func _on_row_gui_input(event: InputEvent, row: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_start_drag(row)

func _start_drag(row: Control) -> void:
	_dragging_row = row
	# Select the canvas object
	var canvas_obj := _canvas_obj_for_row(row)
	if canvas_obj:
		_select_row_node(row)
		row_selected.emit(canvas_obj)

func _check_swap() -> void:
	var cur_idx := _row_index(_dragging_row)
	if cur_idx < 0:
		return
	# The pinned Group Layer row never moves and other rows cannot cross it.
	if _is_pinned(_rows[cur_idx]["canvas_obj"]):
		return
	var mouse_y := get_global_mouse_position().y

	if cur_idx > 0:
		var above_idx := cur_idx - 1
		if not _is_pinned(_rows[above_idx]["canvas_obj"]):
			var above_row: Control = _rows[above_idx]["row"]
			var center := above_row.global_position.y + above_row.size.y * 0.5
			if mouse_y < center:
				_swap(cur_idx, above_idx)
				return

	if cur_idx < _rows.size() - 1:
		var below_row: Control = _rows[cur_idx + 1]["row"]
		var center := below_row.global_position.y + below_row.size.y * 0.5
		if mouse_y > center:
			_swap(cur_idx, cur_idx + 1)

func _swap(a: int, b: int) -> void:
	item_vbox.move_child(_rows[a]["row"], b)
	var tmp: Dictionary = _rows[a]
	_rows[a] = _rows[b]
	_rows[b] = tmp
	_update_z_indices()
	order_changed.emit(a, b)

# --- Z-index sync ---

func _update_z_indices() -> void:
	var top := _rows.size() - 1
	for i in _rows.size():
		var obj: EditableObjectNode = _rows[i]["canvas_obj"]
		if is_instance_valid(obj):
			obj.z_index = top - i   # row 0 (top of list) = highest z
	z_indices_changed.emit()

# --- Selection highlight ---

func _select_row_node(row: Control) -> void:
	for entry in _rows:
		_set_row_highlight(entry["row"], entry["row"] == row)
	_selected_row = row

func _set_row_highlight(row: Control, active: bool) -> void:
	if active:
		row.add_theme_stylebox_override("panel", _highlight_style())
	else:
		row.remove_theme_stylebox_override("panel")

func _highlight_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.3, 0.6, 1.0, 0.35)
	return s

# --- Helpers ---

func _canvas_obj_for_row(row: Control) -> EditableObjectNode:
	for entry in _rows:
		if entry["row"] == row:
			return entry["canvas_obj"]
	return null

func _row_index(row: Control) -> int:
	for i in _rows.size():
		if _rows[i]["row"] == row:
			return i
	return -1

func get_selected_object() -> EditableObjectNode:
	if _selected_row == null:
		return null
	return _canvas_obj_for_row(_selected_row)

func update_visibility_buttons() -> void:
	for entry in _rows:
		var obj: EditableObjectNode = entry["canvas_obj"]
		if not is_instance_valid(obj):
			continue
		var btn: Button = entry.get("eye_btn")
		if btn == null or not is_instance_valid(btn):
			continue
		btn.button_pressed = obj.layer_visible
		btn.modulate = Color.WHITE if obj.layer_visible else Color(1.0, 1.0, 1.0, 0.3)

func _clear() -> void:
	for c in item_vbox.get_children():
		c.queue_free()
	_rows.clear()
	_selected_row = null
	_dragging_row = null
