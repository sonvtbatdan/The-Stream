extends CanvasLayer

const EditableObject := preload("res://scenes/ui/edit_mode/editable_object.tscn")
const LAYOUT_PATH := "user://layout.cfg"
const GROUPS := ["screen", "active", "passive", "stat"]
const SCREEN_FIT_W := 1440.0
const SCREEN_FIT_H := 780.0
const GROUP_FOLDERS := {
	"active": "upgrades/active",
	"passive": "upgrades/passive",
}

# Sentinel source_path for the synthetic Group Layer object.
# Pinned at the top of each group's list; moving/resizing it propagates to
# all other objects in the group. Texture is generated procedurally.
const GROUP_LAYER_MARKER := "res://__group_layer__"
const GROUP_LAYER_DEFAULT_SIZE := 120.0
const GROUP_LAYER_DEFAULT_POS := Vector2(20.0, 20.0)

@onready var objects_container: Control = $ObjectsContainer
@onready var dim_overlay: ColorRect = $DimOverlay
@onready var side_panel: Panel = $SidePanel
@onready var title_bar: Panel = $SidePanel/VBox/TitleBar
@onready var object_list_panel: Panel = $SidePanel/VBox/TopHBox/ObjectListPanel
@onready var file_dialog: FileDialog = $FileDialog
@onready var unsaved_dialog: Window = $UnsavedDialog

@onready var stat_template_edit: TextEdit = $SidePanel/VBox/StatInfoPanel/StatVBox/StatTemplateEdit

@onready var btn_screen: Button      = $SidePanel/VBox/TopHBox/ButtonsColumn/ScreenBtn
@onready var btn_upgrade: Button     = $SidePanel/VBox/TopHBox/ButtonsColumn/UpgradeBtn
@onready var btn_visual: Button      = $SidePanel/VBox/TopHBox/ButtonsColumn/VisualBtn
@onready var btn_stat: Button        = $SidePanel/VBox/TopHBox/ButtonsColumn/StatBtn
@onready var btn_user: Button        = $SidePanel/VBox/TopHBox/ButtonsColumn/UserBtn
@onready var btn_fit_screen: Button  = $SidePanel/VBox/TopHBox/ButtonsColumn/FitScreenBtn
@onready var btn_delete: Button      = $SidePanel/VBox/TopHBox/ButtonsColumn/DeleteBtn
@onready var transform_panel         = $SidePanel/VBox/TransformPanel

var _active_group := "screen"
var _user_panel: Node = null      # UserPanel sibling node
var _user_editing := false        # whether User edit mode is active
var _is_open := false
var _dirty := false
var _pending_object: Texture2D = null
var _pending_path := ""
var _selected_objects: Array = []

var _undo_stack: Array[Dictionary] = []
var _placed: Dictionary = {}  # group -> Array[EditableObjectNode]
var _group_layer_prev_state: Dictionary = {}  # group -> {pos, size}
var _group_drag_started: Dictionary = {}     # group -> bool

# SidePanel drag-to-move state. Started by clicking the TitleBar; the
# subsequent motion + release events are caught in _input() because they
# travel faster than the panel moves and won't always land on the title bar.
var _dragging_panel: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _selection_locked := false

var _canvas_dragging := false
var _canvas_drag_mouse_prev := Vector2.ZERO
var _canvas_drag_undo_pushed := false

func _ready() -> void:
	layer = 10
	for g in GROUPS:
		_placed[g] = []
	object_list_panel.row_selected.connect(_on_list_row_selected)
	object_list_panel.file_dropped.connect(_on_file_dropped)
	object_list_panel.z_indices_changed.connect(_sort_canvas_z_order)
	title_bar.gui_input.connect(_on_title_bar_input)
	_user_panel = get_parent().get_node_or_null("UserPanel")
	btn_fit_screen.pressed.connect(_fit_screen_group)
	stat_template_edit.text = GameManager.stat_template
	stat_template_edit.text_changed.connect(_on_stat_template_text_changed)
	transform_panel.connect("transform_changed", _on_transform_live)
	_set_edit_ui_visible(false)
	_load_layout()
	_auto_load_all_groups()

func _set_edit_ui_visible(v: bool) -> void:
	dim_overlay.visible = v
	side_panel.visible = v
	objects_container.visible = v
	if not v:
		_dragging_panel = false
		_canvas_dragging = false

func _on_stat_template_text_changed() -> void:
	GameManager.stat_template = stat_template_edit.text

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging_panel = true
		_drag_offset = side_panel.global_position - get_viewport().get_mouse_position()

func _input(event: InputEvent) -> void:
	if _dragging_panel:
		if event is InputEventMouseMotion:
			var new_pos: Vector2 = get_viewport().get_mouse_position() + _drag_offset
			var vp_size: Vector2 = get_viewport().get_visible_rect().size
			new_pos.x = clampf(new_pos.x, 32.0 - side_panel.size.x, vp_size.x - 32.0)
			new_pos.y = clampf(new_pos.y, 0.0, vp_size.y - 32.0)
			side_panel.position = new_pos
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_dragging_panel = false
		return

	if not _canvas_dragging:
		return
	if event is InputEventMouseMotion:
		var mouse_pos := get_viewport().get_mouse_position()
		var delta := mouse_pos - _canvas_drag_mouse_prev
		_canvas_drag_mouse_prev = mouse_pos
		if not _canvas_drag_undo_pushed:
			_canvas_drag_undo_pushed = true
			for obj in _selected_objects:
				if is_instance_valid(obj):
					if obj.is_group_layer():
						_push_undo_group_transform(obj.group_id)
					else:
						_push_undo_transform(obj)
		for obj in _selected_objects:
			if not is_instance_valid(obj):
				continue
			obj.position += delta
			if obj.is_group_layer():
				_propagate_group_layer(obj.group_id, delta, obj.size.x, obj.size.x)
				_group_layer_prev_state[obj.group_id] = {"pos": obj.position, "size": obj.size}
		transform_panel.refresh(_primary_selected())
		_dirty = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_canvas_dragging = false
		_canvas_drag_undo_pushed = false
		for obj in _selected_objects:
			if is_instance_valid(obj) and obj.is_group_layer():
				_group_drag_started[obj.group_id] = false

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event is InputEventKey and event.pressed:
		if not event.echo and event.keycode == KEY_Z and event.ctrl_pressed:
			_undo()
			get_viewport().set_input_as_handled()
			return
		if not event.echo and event.is_action_pressed("toggle_edit_mode"):
			_request_close()
			get_viewport().set_input_as_handled()
			return
		if not event.echo and event.keycode == KEY_DELETE and not _selected_objects.is_empty():
			for obj in _selected_objects.duplicate():
				_delete_object(obj)
			get_viewport().set_input_as_handled()
			return
		if not _selected_objects.is_empty():
			var dir := Vector2.ZERO
			match event.keycode:
				KEY_UP:    dir = Vector2(0.0, -1.0)
				KEY_DOWN:  dir = Vector2(0.0,  1.0)
				KEY_LEFT:  dir = Vector2(-1.0, 0.0)
				KEY_RIGHT: dir = Vector2( 1.0, 0.0)
			if dir != Vector2.ZERO:
				if not event.echo:
					for obj in _selected_objects:
						if obj is EditableObjectNode and (obj as EditableObjectNode).is_group_layer():
							_push_undo_group_transform(obj.group_id)
						else:
							_push_undo_transform(obj)
				for obj in _selected_objects:
					obj.position += dir
					if obj is EditableObjectNode and (obj as EditableObjectNode).is_group_layer():
						_propagate_group_layer(obj.group_id, dir, obj.size.x, obj.size.x)
						_group_layer_prev_state[obj.group_id] = {"pos": obj.position, "size": obj.size}
				transform_panel.refresh(_primary_selected())
				_dirty = true
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not side_panel.get_global_rect().has_point(event.position):
			_canvas_dragging = false
			_canvas_drag_undo_pushed = false
			_selection_locked = false
			_select_objects([])
			object_list_panel.highlight_objects([])
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not side_panel.get_global_rect().has_point(event.position):
			if _pending_object:
				var mp := objects_container.get_local_mouse_position()
				_place_object(_pending_object, mp, Vector2.ZERO, _pending_path)
				_pending_object = null
				_pending_path = ""
				get_viewport().set_input_as_handled()
			elif _selection_locked and not _selected_objects.is_empty():
				_canvas_dragging = true
				_canvas_drag_mouse_prev = get_viewport().get_mouse_position()
				_canvas_drag_undo_pushed = false
				get_viewport().set_input_as_handled()
			elif not _selection_locked:
				_select_objects([])
				object_list_panel.highlight_objects([])

func toggle() -> void:
	if not _is_open:
		_is_open = true
		_set_edit_ui_visible(true)
		_set_group(_active_group)
	else:
		_request_close()

# --- Group ---

func _set_group(group: String) -> void:
	_selection_locked = false
	_active_group = group
	_auto_load_group(group)
	object_list_panel.set_group_label(group)
	object_list_panel.refresh(_placed[group])
	_update_group_buttons()
	_update_object_interactivity()
	_pending_object = null
	_select_objects([])

func _auto_load_all_groups() -> void:
	var prev := _active_group
	for g in GROUPS:
		_active_group = g
		_auto_load_group(g)
	_active_group = prev
	_init_group_z_indices()
	_update_object_interactivity()
	_sort_canvas_z_order()

# Assign z_indices so each group's Group Layer sits on top of its siblings.
# Called after auto-load when the object list panel hasn't set z_indices yet.
func _init_group_z_indices() -> void:
	for group in GROUPS:
		var objs: Array = _placed[group]
		var n := objs.size()
		var layer_idx := -1
		for i in n:
			if is_instance_valid(objs[i]) and objs[i].is_group_layer():
				layer_idx = i
				break
		if layer_idx < 0:
			continue
		objs[layer_idx].z_index = n - 1
		var z := 0
		for i in n:
			if i == layer_idx:
				continue
			if is_instance_valid(objs[i]):
				objs[i].z_index = z
				z += 1
	_undo_stack.clear()
	_dirty = false

func _ensure_group_layer(group: String) -> void:
	for obj in _placed[group]:
		if is_instance_valid(obj) and obj.is_group_layer():
			return
	var tex := _make_group_layer_texture()
	var prev := _active_group
	_active_group = group
	var sz := Vector2(GROUP_LAYER_DEFAULT_SIZE, GROUP_LAYER_DEFAULT_SIZE)
	var obj := _place_object(tex, Vector2.ZERO, sz, GROUP_LAYER_MARKER, true)
	obj.position = GROUP_LAYER_DEFAULT_POS
	_active_group = prev
	_group_layer_prev_state[group] = {"pos": obj.position, "size": obj.size}

# 3x3 grid glyph: nine rounded squares on a dark backdrop.
func _make_group_layer_texture() -> Texture2D:
	var side := 128
	var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var bg := Color(0.08, 0.10, 0.14, 1.0)
	var border := Color(0.55, 0.65, 0.85, 1.0)
	var cell_color := Color(0.85, 0.90, 1.0, 1.0)
	img.fill(bg)
	# Outer border (2px ring).
	for y in side:
		for x in side:
			if x < 2 or x >= side - 2 or y < 2 or y >= side - 2:
				img.set_pixel(x, y, border)
	# 3x3 inner cells. Inset 12px, gutter 6px between cells.
	var inset := 16
	var gutter := 6
	var inner := side - inset * 2
	var cell_size := (inner - gutter * 2) / 3
	for row in 3:
		for col in 3:
			var x0 := inset + col * (cell_size + gutter)
			var y0 := inset + row * (cell_size + gutter)
			for dy in cell_size:
				for dx in cell_size:
					img.set_pixel(x0 + dx, y0 + dy, cell_color)
	return ImageTexture.create_from_image(img)

func _auto_load_group(group: String) -> void:
	_ensure_group_layer(group)
	var folder := "res://assets/" + (GROUP_FOLDERS.get(group, group) as String) + "/"
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	var placed_paths: Dictionary = {}
	for obj in _placed[group]:
		if is_instance_valid(obj):
			placed_paths[obj.source_path] = true
	dir.list_dir_begin()
	var file := dir.get_next()
	var slot := 0
	while file != "":
		if not dir.current_is_dir():
			var ext := file.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "webp"]:
				var full_path := folder + file
				if not placed_paths.has(full_path):
					var tex := _load_tex(full_path)
					if tex:
						var col := slot % 4
						var row := slot / 4
						var pos := Vector2(20.0 + col * 220.0, 20.0 + row * 220.0)
						_place_object(tex, pos, Vector2.ZERO, full_path, true)
						slot += 1
		file = dir.get_next()
	dir.list_dir_end()

func _on_user_btn_pressed() -> void:
	_user_editing = not _user_editing
	btn_user.button_pressed = _user_editing
	if _user_panel and _user_panel.has_method("set_edit_mode"):
		_user_panel.set_edit_mode(_user_editing)
	# Deactivate any active sprite group when switching to User
	if _user_editing:
		btn_screen.button_pressed  = false
		btn_upgrade.button_pressed = false
		btn_visual.button_pressed  = false
		btn_stat.button_pressed    = false

func _update_group_buttons() -> void:
	btn_screen.button_pressed  = (_active_group == "screen")
	btn_upgrade.button_pressed = (_active_group == "active")
	btn_visual.button_pressed  = (_active_group == "passive")
	btn_stat.button_pressed    = (_active_group == "stat")
	btn_user.button_pressed    = false   # User is toggled independently
	btn_fit_screen.visible     = (_active_group == "screen")
	btn_delete.disabled = _selected_objects.is_empty()

func _update_object_interactivity() -> void:
	for group in GROUPS:
		for obj in _placed[group]:
			if not is_instance_valid(obj):
				continue
			if _is_open:
				obj.set_gameplay_mode(false)
				if group == _active_group or obj.is_group_layer():
					obj.mouse_filter = Control.MOUSE_FILTER_STOP
				else:
					obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				obj.set_gameplay_mode(true)
				var is_frame: bool = "frame" in obj.source_path.get_file().to_lower()
				if group in ["screen", "active"] and not is_frame:
					obj.mouse_filter = Control.MOUSE_FILTER_STOP
				else:
					obj.mouse_filter = Control.MOUSE_FILTER_IGNORE

# --- Object placement ---

func _on_list_row_selected(canvas_obj: EditableObjectNode) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		var new_sel := _selected_objects.duplicate()
		if canvas_obj in new_sel:
			new_sel.erase(canvas_obj)
		else:
			new_sel.append(canvas_obj)
		_select_objects(new_sel)
		object_list_panel.highlight_objects(new_sel)
	else:
		_select_objects([canvas_obj])
		object_list_panel.highlight_objects([canvas_obj])
	_selection_locked = true

func _on_canvas_object_clicked(obj: EditableObjectNode) -> void:
	if not _is_open:
		_handle_gameplay_click(obj)
		return
	if _selection_locked:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		var new_sel := _selected_objects.duplicate()
		if obj in new_sel:
			new_sel.erase(obj)
		else:
			new_sel.append(obj)
		_select_objects(new_sel)
		object_list_panel.highlight_objects(new_sel)
	else:
		_select_objects([obj])
		object_list_panel.select_object(obj)

func _handle_gameplay_click(obj: EditableObjectNode) -> void:
	match obj.group_id:
		"screen":
			# Any click on a screen-group sprite (Girl, Screen, view, sub, etc.)
			# grants click_power views. Frame sprites are mouse_filter = IGNORE
			# in gameplay mode so they don't reach here at all.
			GameManager.on_view_clicked()
			_animate_screen_objects()
		"active":
			var upgrade_id := obj.source_path.get_file().get_basename().to_lower()
			if UpgradeManager.UPGRADES.has(upgrade_id):
				var purchased := UpgradeManager.try_purchase(upgrade_id)
				obj.animate_upgrade_result(purchased)

func _animate_screen_objects() -> void:
	for obj in _placed["screen"]:
		if not is_instance_valid(obj) or obj.is_group_layer():
			continue
		var base: String = obj.source_path.get_file().get_basename().to_lower()
		if "frame" in base or base in ["view", "sub", "screen"]:
			continue
		obj.animate_screen_click()

func _primary_selected() -> EditableObjectNode:
	return _selected_objects[0] if not _selected_objects.is_empty() else null

func _select_objects(objects: Array) -> void:
	for group in GROUPS:
		for obj in _placed[group]:
			if is_instance_valid(obj):
				obj.selected = (obj in objects)
	_selected_objects.clear()
	for obj in objects:
		if is_instance_valid(obj):
			_selected_objects.append(obj as EditableObjectNode)
	btn_delete.disabled = _selected_objects.is_empty()
	transform_panel.refresh(_primary_selected())

func _on_transform_live(pos: Vector2, sz: Vector2) -> void:
	var primary := _primary_selected()
	if not primary or not is_instance_valid(primary):
		return
	var prev_pos := primary.position
	var prev_sz  := primary.size
	primary.position = pos
	primary.size = sz
	primary._sync_rect_size()
	if primary.is_group_layer():
		_propagate_group_layer(primary.group_id, pos - prev_pos, prev_sz.x, sz.x)
		_group_layer_prev_state[primary.group_id] = {"pos": pos, "size": sz}
	_dirty = true

# Sync ObjectsContainer's tree order to match every object's z_index. Godot
# routes GUI input by tree order (later siblings get input first), not by
# z_index, so without this sync a visually-on-top object can be unclickable
# because an underneath sibling absorbs the click.
func _sort_canvas_z_order() -> void:
	var all_objs: Array = []
	for group in GROUPS:
		for obj in _placed[group]:
			if is_instance_valid(obj):
				all_objs.append(obj)
	all_objs.sort_custom(func(a, b): return a.z_index < b.z_index)
	for i in all_objs.size():
		objects_container.move_child(all_objs[i], i)

# Move and/or resize all non-group-layer objects in a group by the same delta/scale.
func _propagate_group_layer(group: String, delta_pos: Vector2, prev_w: float, new_w: float) -> void:
	var scale := new_w / prev_w if prev_w > 0.0 else 1.0
	for obj in _placed[group]:
		if not is_instance_valid(obj) or obj.is_group_layer():
			continue
		obj.position += delta_pos
		if scale != 1.0:
			obj.size = Vector2(obj.size.x * scale, obj.size.y * scale)
			obj._sync_rect_size()

func _on_transform_apply() -> void:
	_save_layout()

func _place_object(tex: Texture2D, pos: Vector2, sz := Vector2.ZERO, path := "", silent := false) -> EditableObjectNode:
	var obj: EditableObjectNode = EditableObject.instantiate()
	obj.transform_ended.connect(notify_transform_changed)
	obj.transform_motion.connect(_on_group_layer_motion)
	obj.object_clicked.connect(_on_canvas_object_clicked)
	objects_container.add_child(obj)
	obj.group_id = _active_group
	obj.source_path = path
	obj.mouse_filter = Control.MOUSE_FILTER_STOP if obj.group_id == _active_group else Control.MOUSE_FILTER_IGNORE
	var offset := Vector2(100.0, 100.0 / (tex.get_width() / float(tex.get_height()))) / 2.0
	obj.init(tex, pos - offset, sz)
	if tex.get_width() == 2754 and tex.get_height() == 1536 and sz == Vector2.ZERO:
		obj.position = Vector2(10.0, 7.0)
		obj.size = Vector2(767.0, 428.0)
		obj._sync_rect_size()
	_placed[_active_group].append(obj)
	if not silent:
		object_list_panel.add_placed_object(obj)
	_push_undo_add(obj)
	_dirty = true
	return obj

func notify_transform_changed(obj: Control) -> void:
	if obj is EditableObjectNode and (obj as EditableObjectNode).is_group_layer():
		var eobj := obj as EditableObjectNode
		_group_drag_started[eobj.group_id] = false
		_group_layer_prev_state[eobj.group_id] = {"pos": obj.position, "size": obj.size}
	else:
		_push_undo_transform(obj)
	_dirty = true
	if obj in _selected_objects:
		transform_panel.refresh(_primary_selected())

func _on_group_layer_motion(obj: EditableObjectNode) -> void:
	var group := obj.group_id
	if not _group_drag_started.get(group, false):
		_group_drag_started[group] = true
		_push_undo_group_transform(group)
		_group_layer_prev_state[group] = {"pos": obj.position, "size": obj.size}
		return
	if not _group_layer_prev_state.has(group):
		_group_layer_prev_state[group] = {"pos": obj.position, "size": obj.size}
		return
	var prev: Dictionary = _group_layer_prev_state[group]
	var delta_pos: Vector2 = obj.position - (prev["pos"] as Vector2)
	var prev_w: float = (prev["size"] as Vector2).x
	_propagate_group_layer(group, delta_pos, prev_w, obj.size.x)
	_group_layer_prev_state[group] = {"pos": obj.position, "size": obj.size}
	_dirty = true

# --- Delete ---

func _on_delete_pressed() -> void:
	for obj in _selected_objects.duplicate():
		_delete_object(obj)

func _delete_object(obj: EditableObjectNode) -> void:
	if not is_instance_valid(obj):
		return
	var group := obj.group_id
	_push_undo_delete(obj)
	_placed[group].erase(obj)
	object_list_panel.remove_object(obj)
	_selected_objects.erase(obj)
	obj.queue_free()
	btn_delete.disabled = _selected_objects.is_empty()
	transform_panel.refresh(_primary_selected())
	_dirty = true

# --- Undo ---

func _push_undo_add(obj: EditableObjectNode) -> void:
	_undo_stack.append({ "type": "add", "obj": obj, "group": _active_group })

func _push_undo_transform(obj: Control) -> void:
	_undo_stack.append({ "type": "transform", "obj": obj, "pos": obj.position, "size": obj.size })

func _push_undo_group_transform(group: String) -> void:
	var states: Array = []
	for obj in _placed[group]:
		if is_instance_valid(obj):
			states.append({ "obj": obj, "pos": obj.position, "size": obj.size })
	_undo_stack.append({ "type": "group_transform", "states": states })

func _push_undo_delete(obj: EditableObjectNode) -> void:
	_undo_stack.append({
		"type": "delete",
		"tex": obj.texture_rect.texture,
		"path": obj.source_path,
		"group": obj.group_id,
		"pos": obj.position,
		"size": obj.size,
	})

func _undo() -> void:
	if _undo_stack.is_empty():
		return
	var entry: Dictionary = _undo_stack.pop_back()
	match entry["type"]:
		"add":
			var obj: EditableObjectNode = entry["obj"]
			if is_instance_valid(obj):
				_placed[entry["group"]].erase(obj)
				object_list_panel.remove_object(obj)
				obj.queue_free()
			_selected_objects.erase(obj)
			btn_delete.disabled = _selected_objects.is_empty()
			transform_panel.refresh(_primary_selected())
		"transform":
			var obj = entry["obj"]
			if is_instance_valid(obj):
				obj.position = entry["pos"]
				obj.size = entry["size"]
				obj._sync_rect_size()
		"group_transform":
			for state in entry["states"]:
				var gobj = state["obj"]
				if is_instance_valid(gobj):
					gobj.position = state["pos"]
					gobj.size = state["size"]
					gobj._sync_rect_size()
			transform_panel.refresh(_primary_selected())
		"delete":
			var prev_group := _active_group
			_active_group = entry["group"]
			var restored := _place_object(entry["tex"], entry["pos"], entry["size"], entry["path"])
			_active_group = prev_group
			restored.position = entry["pos"]
			_update_object_interactivity()
	_dirty = not _undo_stack.is_empty()

# --- Upload ---

func _on_save_pressed() -> void:
	_save_layout()

func _on_upload_pressed() -> void:
	file_dialog.popup_centered(Vector2i(900, 600))

func _on_file_dialog_files_selected(paths: PackedStringArray) -> void:
	for path in paths:
		_on_file_dropped(path)

func _on_file_dropped(os_path: String) -> void:
	var ext := os_path.get_extension().to_lower()
	if ext not in ["png", "jpg", "jpeg", "webp"]:
		return
	var img := Image.load_from_file(os_path)
	if img == null:
		return
	var filename := os_path.get_file()
	var dest_dir := "res://assets/" + (GROUP_FOLDERS.get(_active_group, _active_group) as String) + "/"
	var dest_res := dest_dir + filename
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest_dir))
	img.save_png(ProjectSettings.globalize_path(dest_res))
	var tex := ImageTexture.create_from_image(img)
	_pending_object = tex
	_pending_path = dest_res

# --- Open/Close ---

func _request_close() -> void:
	if _dirty:
		unsaved_dialog.popup_centered()
	else:
		_close()

func _close() -> void:
	_selection_locked = false
	if _user_editing:
		_user_editing = false
		if _user_panel and _user_panel.has_method("set_edit_mode"):
			_user_panel.set_edit_mode(false)
	_is_open = false
	_set_edit_ui_visible(false)
	_pending_object = null
	_select_objects([])
	_update_object_interactivity()

func _on_dialog_save() -> void:
	_save_layout()
	unsaved_dialog.hide()
	_close()

func _on_dialog_discard() -> void:
	_dirty = false
	unsaved_dialog.hide()
	_close()

func _on_dialog_cancel() -> void:
	unsaved_dialog.hide()

# --- Persistence ---

func _save_layout() -> void:
	var cfg := ConfigFile.new()
	for group in GROUPS:
		var list: Array[Dictionary] = []
		for obj in _placed[group]:
			if is_instance_valid(obj):
				list.append(obj.get_state())
		cfg.set_value("layout", group, list)
	cfg.save(LAYOUT_PATH)
	_dirty = false

func _fit_screen_group() -> void:
	var objs: Array = _placed["screen"]
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	var has := false
	for obj in objs:
		if not is_instance_valid(obj) or obj.is_group_layer():
			continue
		min_p = min_p.min(obj.position)
		max_p = max_p.max(obj.position + obj.size)
		has = true
	if not has:
		return
	var cur_w := max_p.x - min_p.x
	var cur_h := max_p.y - min_p.y
	if cur_w <= 0.0 or cur_h <= 0.0:
		return
	_push_undo_group_transform("screen")
	var vp := get_viewport().get_visible_rect().size
	var tx := (vp.x - SCREEN_FIT_W) / 2.0
	var ty := (vp.y - SCREEN_FIT_H) / 2.0
	var sx := SCREEN_FIT_W / cur_w
	var sy := SCREEN_FIT_H / cur_h
	for obj in objs:
		if not is_instance_valid(obj) or obj.is_group_layer():
			continue
		var rel: Vector2 = obj.position - min_p
		obj.position = Vector2(tx + rel.x * sx, ty + rel.y * sy)
		obj.size = Vector2(obj.size.x * sx, obj.size.y * sy)
		obj._sync_rect_size()
	for obj in objs:
		if is_instance_valid(obj) and obj.is_group_layer():
			obj.position = Vector2(tx, ty)
			obj.size = Vector2(SCREEN_FIT_W, SCREEN_FIT_H)
			obj._sync_rect_size()
			_group_layer_prev_state["screen"] = {"pos": obj.position, "size": obj.size}
			break
	transform_panel.refresh(_primary_selected())
	_dirty = true

func _load_tex(res_path: String) -> Texture2D:
	if res_path == GROUP_LAYER_MARKER:
		return _make_group_layer_texture()
	var tex := load(res_path) as Texture2D
	if tex:
		return tex
	var abs_path := ProjectSettings.globalize_path(res_path)
	var img := Image.load_from_file(abs_path)
	if img:
		return ImageTexture.create_from_image(img)
	return null

func _load_layout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) != OK:
		return
	var prev_group := _active_group
	for group in GROUPS:
		var list = cfg.get_value("layout", group, [])
		_active_group = group
		for entry in list:
			var tex := _load_tex(entry["path"])
			if tex:
				var obj := _place_object(tex, Vector2.ZERO, entry["size"], entry["path"], true)
				obj.position = entry["pos"]
				obj.z_index = entry.get("z_index", 0)
				obj.layer_visible = entry.get("layer_visible", true)
				obj.visible = obj.layer_visible
		_placed[group].sort_custom(func(a, b): return a.z_index > b.z_index)
		var n: int = _placed[group].size()
		for i in n:
			if is_instance_valid(_placed[group][i]):
				_placed[group][i].z_index = n - 1 - i
	_active_group = prev_group
	for group in GROUPS:
		for obj in _placed[group]:
			if is_instance_valid(obj) and obj.is_group_layer():
				_group_layer_prev_state[group] = {"pos": obj.position, "size": obj.size}
	_update_object_interactivity()
	_sort_canvas_z_order()
	_undo_stack.clear()
	_dirty = false
