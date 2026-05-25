extends CanvasLayer

const EditableObject := preload("res://scenes/ui/edit_mode/editable_object.tscn")
const LAYOUT_PATH := "user://layout.cfg"
const GROUPS := ["screen", "upgrade", "visual", "stat"]

# Sentinel source_path for the synthetic "all_upgrades" control object.
# Pinned at the top of the upgrade group's list; resizing it propagates to
# every other upgrade object. Texture is generated procedurally so no asset
# file is required.
const ALL_UPGRADES_MARKER := "res://__all_upgrades__"
const ALL_UPGRADES_DEFAULT_SIZE := 120.0
const ALL_UPGRADES_DEFAULT_POS := Vector2(20.0, 20.0)

@onready var objects_container: Control = $ObjectsContainer
@onready var dim_overlay: ColorRect = $DimOverlay
@onready var side_panel: Panel = $SidePanel
@onready var title_bar: Panel = $SidePanel/VBox/TitleBar
@onready var object_list_panel: Panel = $SidePanel/VBox/TopHBox/ObjectListPanel
@onready var file_dialog: FileDialog = $FileDialog
@onready var unsaved_dialog: Window = $UnsavedDialog

@onready var btn_screen: Button   = $SidePanel/VBox/TopHBox/ButtonsColumn/ScreenBtn
@onready var btn_upgrade: Button  = $SidePanel/VBox/TopHBox/ButtonsColumn/UpgradeBtn
@onready var btn_visual: Button   = $SidePanel/VBox/TopHBox/ButtonsColumn/VisualBtn
@onready var btn_stat: Button     = $SidePanel/VBox/TopHBox/ButtonsColumn/StatBtn
@onready var btn_delete: Button   = $SidePanel/VBox/TopHBox/ButtonsColumn/DeleteBtn
@onready var transform_panel      = $SidePanel/VBox/TransformPanel

var _active_group := "screen"
var _is_open := false
var _dirty := false
var _pending_object: Texture2D = null
var _pending_path := ""
var _selected_objects: Array = []

var _undo_stack: Array[Dictionary] = []
var _placed: Dictionary = {}  # group -> Array[EditableObjectNode]

# SidePanel drag-to-move state. Started by clicking the TitleBar; the
# subsequent motion + release events are caught in _input() because they
# travel faster than the panel moves and won't always land on the title bar.
var _dragging_panel: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	layer = 10
	for g in GROUPS:
		_placed[g] = []
	object_list_panel.row_selected.connect(_on_list_row_selected)
	object_list_panel.file_dropped.connect(_on_file_dropped)
	object_list_panel.z_indices_changed.connect(_sort_canvas_z_order)
	title_bar.gui_input.connect(_on_title_bar_input)
	transform_panel.connect("transform_changed", _on_transform_live)
	_set_edit_ui_visible(false)
	_load_layout()
	_auto_load_all_groups()

func _set_edit_ui_visible(v: bool) -> void:
	dim_overlay.visible = v
	side_panel.visible = v
	if not v:
		_dragging_panel = false   # never resume a drag after the panel hides

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging_panel = true
		_drag_offset = side_panel.global_position - get_viewport().get_mouse_position()

func _input(event: InputEvent) -> void:
	if not _dragging_panel:
		return
	if event is InputEventMouseMotion:
		var new_pos: Vector2 = get_viewport().get_mouse_position() + _drag_offset
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		# Keep at least 32 px of the title bar reachable on every side so the
		# panel can always be grabbed back if dragged near the edge.
		new_pos.x = clampf(new_pos.x, 32.0 - side_panel.size.x, vp_size.x - 32.0)
		new_pos.y = clampf(new_pos.y, 0.0, vp_size.y - 32.0)
		side_panel.position = new_pos
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging_panel = false

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
						_push_undo_transform(obj)
				for obj in _selected_objects:
					obj.position += dir
				transform_panel.refresh(_primary_selected())
				_dirty = true
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
			else:
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
	_update_object_interactivity()
	_sort_canvas_z_order()
	_undo_stack.clear()
	_dirty = false

func _ensure_all_upgrades(group: String) -> void:
	if group != "upgrade":
		return
	for obj in _placed["upgrade"]:
		if is_instance_valid(obj) and obj.source_path == ALL_UPGRADES_MARKER:
			return
	var tex := _make_all_upgrades_texture()
	var prev := _active_group
	_active_group = "upgrade"
	var sz := Vector2(ALL_UPGRADES_DEFAULT_SIZE, ALL_UPGRADES_DEFAULT_SIZE)
	# _place_object internally subtracts a (50, 50) centering offset from
	# `pos`; bypass that by setting the final position directly after creation.
	var obj := _place_object(tex, Vector2.ZERO, sz, ALL_UPGRADES_MARKER, true)
	obj.position = ALL_UPGRADES_DEFAULT_POS
	_active_group = prev

# 3x3 grid glyph: nine rounded squares on a dark backdrop. 1:1 aspect so
# editing width and height in the transform panel propagate symmetrically.
func _make_all_upgrades_texture() -> Texture2D:
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
	_ensure_all_upgrades(group)
	var folder := "res://assets/" + group + "/"
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

func _update_group_buttons() -> void:
	btn_screen.button_pressed  = (_active_group == "screen")
	btn_upgrade.button_pressed = (_active_group == "upgrade")
	btn_visual.button_pressed  = (_active_group == "visual")
	btn_stat.button_pressed    = (_active_group == "stat")
	btn_delete.disabled = _selected_objects.is_empty()

func _update_object_interactivity() -> void:
	for group in GROUPS:
		for obj in _placed[group]:
			if not is_instance_valid(obj):
				continue
			if _is_open:
				obj.set_gameplay_mode(false)
				obj.mouse_filter = Control.MOUSE_FILTER_STOP if group == _active_group else Control.MOUSE_FILTER_IGNORE
			else:
				obj.set_gameplay_mode(true)
				var is_frame: bool = "frame" in obj.source_path.get_file().to_lower()
				if group in ["screen", "upgrade"] and not is_frame:
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

func _on_canvas_object_clicked(obj: EditableObjectNode) -> void:
	if not _is_open:
		_handle_gameplay_click(obj)
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
		"upgrade":
			var upgrade_id := obj.source_path.get_file().get_basename().to_lower()
			if UpgradeManager.UPGRADES.has(upgrade_id):
				var purchased := UpgradeManager.try_purchase(upgrade_id)
				obj.animate_upgrade_result(purchased)

func _animate_screen_objects() -> void:
	for obj in _placed["screen"]:
		if not is_instance_valid(obj):
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
	primary.position = pos
	primary.size = sz
	primary._sync_rect_size()
	if primary.is_all_upgrades():
		_propagate_all_upgrades_size(sz)
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

# When the synthetic all_upgrades control is resized, every other upgrade
# object adopts the new width; each object's height is then derived from its
# own aspect ratio so individual upgrade assets don't distort.
func _propagate_all_upgrades_size(target_size: Vector2) -> void:
	for obj in _placed["upgrade"]:
		if not is_instance_valid(obj) or obj.is_all_upgrades():
			continue
		var new_w: float = target_size.x
		var aspect: float = obj._aspect_ratio if obj._aspect_ratio > 0.0 else 1.0
		obj.size = Vector2(new_w, new_w / aspect)
		obj._sync_rect_size()

func _on_transform_apply() -> void:
	_save_layout()

func _place_object(tex: Texture2D, pos: Vector2, sz := Vector2.ZERO, path := "", silent := false) -> EditableObjectNode:
	var obj: EditableObjectNode = EditableObject.instantiate()
	obj.transform_ended.connect(notify_transform_changed)
	obj.object_clicked.connect(_on_canvas_object_clicked)
	objects_container.add_child(obj)
	obj.group_id = _active_group
	obj.source_path = path
	obj.mouse_filter = Control.MOUSE_FILTER_STOP if obj.group_id == _active_group else Control.MOUSE_FILTER_IGNORE
	var offset := Vector2(100.0, 100.0 / (tex.get_width() / float(tex.get_height()))) / 2.0
	obj.init(tex, pos - offset, sz)
	_placed[_active_group].append(obj)
	if not silent:
		object_list_panel.add_placed_object(obj)
	_push_undo_add(obj)
	_dirty = true
	return obj

func notify_transform_changed(obj: Control) -> void:
	_push_undo_transform(obj)
	_dirty = true
	if obj is EditableObjectNode and (obj as EditableObjectNode).is_all_upgrades():
		_propagate_all_upgrades_size(obj.size)
	if obj in _selected_objects:
		transform_panel.refresh(_primary_selected())

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
	var dest_dir := "res://assets/" + _active_group + "/"
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

func _load_tex(res_path: String) -> Texture2D:
	if res_path == ALL_UPGRADES_MARKER:
		return _make_all_upgrades_texture()
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
		_placed[group].sort_custom(func(a, b): return a.z_index > b.z_index)
		var n: int = _placed[group].size()
		for i in n:
			if is_instance_valid(_placed[group][i]):
				_placed[group][i].z_index = n - 1 - i
	_active_group = prev_group
	_update_object_interactivity()
	_sort_canvas_z_order()
	_undo_stack.clear()
	_dirty = false
