extends Panel

signal row_selected(canvas_obj: EditableObjectNode)
signal order_changed(from_idx: int, to_idx: int)
signal file_dropped(path: String)

const ROW_HEIGHT := 56.0
const THUMB_SIZE := 48.0

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
	for obj in placed_objects:
		if is_instance_valid(obj):
			_append_row(obj)
	_update_z_indices()

func add_placed_object(obj: EditableObjectNode) -> void:
	_append_row(obj)
	_update_z_indices()

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
	_rows.append({"row": row, "canvas_obj": obj})

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
	lbl.text = obj.source_path.get_file().get_basename() if obj.source_path != "" else "object"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

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
	var mouse_y := get_global_mouse_position().y

	if cur_idx > 0:
		var above_row: Control = _rows[cur_idx - 1]["row"]
		var center := above_row.global_position.y + above_row.size.y * 0.5
		if mouse_y < center:
			_swap(cur_idx, cur_idx - 1)
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

func _clear() -> void:
	for c in item_vbox.get_children():
		c.queue_free()
	_rows.clear()
	_selected_row = null
	_dragging_row = null
