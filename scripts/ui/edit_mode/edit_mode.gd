extends CanvasLayer

signal opened_changed(is_open: bool)

const EditableObject := preload("res://scenes/ui/edit_mode/editable_object.tscn")
const LAYOUT_PATH := "user://layout.cfg"
const GROUPS := ["screen", "upgrade", "visual", "stat"]

# Filenames (lowercased) that the StreamArena now owns — never auto-place them
# as screen-group sprites. Keyed by group → set of basenames.
const SOURCE_BLOCKLIST := {
	"screen": { "girl": true, "screen": true, "view": true, "sub": true, "eye": true, "like": true, "dislike": true, "viewer": true },
}

# Auto-load layout per group: where new sprites land if no saved layout overrides them.
const GROUP_DEFAULTS := {
	"screen":  { "size": 200.0, "origin": Vector2(20.0, 20.0),    "spacing": Vector2(210.0, 210.0), "cols": 4 },
	"upgrade": { "size": 80.0,  "origin": Vector2(20.0, 525.0),   "spacing": Vector2(88.0, 88.0),   "cols": 9 },
	"visual":  { "size": 80.0,  "origin": Vector2(20.0, 620.0),   "spacing": Vector2(88.0, 88.0),   "cols": 9 },
	"stat":    { "size": 60.0,  "origin": Vector2(1030.0, 510.0), "spacing": Vector2(70.0, 70.0),   "cols": 3 },
}

@onready var objects_container: Control = $ObjectsContainer
@onready var dim_overlay: ColorRect = $DimOverlay
@onready var side_panel: Panel = $SidePanel
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
# Paths the user has explicitly deleted in F4. Persisted in layout.cfg under
# section [deleted] so _auto_load_group can skip them on the next launch.
# Re-uploading or undoing a delete clears the flag.
var _deleted_paths: Dictionary = {}  # group -> Dictionary(path -> true)

# Per-group master width. Only groups present here get an "All Icons" row in the list
# and have their sprites auto-sized to this width (height derived per-sprite from aspect).
var _all_icon_size: Dictionary = {}
var _all_icon_selected := false

func _ready() -> void:
	layer = 10
	for g in GROUPS:
		_placed[g] = []
		_deleted_paths[g] = {}
	_all_icon_size["upgrade"] = float(GROUP_DEFAULTS["upgrade"]["size"])
	object_list_panel.row_selected.connect(_on_list_row_selected)
	object_list_panel.file_dropped.connect(_on_file_dropped)
	object_list_panel.all_icon_selected.connect(_on_all_icon_selected)
	transform_panel.transform_changed.connect(_on_transform_live)
	transform_panel.apply_requested.connect(_on_transform_apply)
	transform_panel.all_icon_size_changed.connect(_on_all_icon_size_changed)

	btn_screen.pressed.connect(_set_group.bind("screen"))
	btn_upgrade.pressed.connect(_set_group.bind("upgrade"))
	btn_visual.pressed.connect(_set_group.bind("visual"))
	btn_stat.pressed.connect(_set_group.bind("stat"))
	btn_delete.pressed.connect(_on_delete_pressed)
	$SidePanel/VBox/TopHBox/ButtonsColumn/SaveBtn.pressed.connect(_on_save_pressed)
	$SidePanel/VBox/TopHBox/ButtonsColumn/UploadBtn.pressed.connect(_on_upload_pressed)

	file_dialog.file_selected.connect(_on_file_dropped)
	file_dialog.files_selected.connect(_on_file_dialog_files_selected)

	unsaved_dialog.close_requested.connect(_on_dialog_cancel)
	$UnsavedDialog/VBox/BtnRow/SaveBtn.pressed.connect(_on_dialog_save)
	$UnsavedDialog/VBox/BtnRow/DiscardBtn.pressed.connect(_on_dialog_discard)
	$UnsavedDialog/VBox/BtnRow/CancelBtn.pressed.connect(_on_dialog_cancel)

	_set_edit_ui_visible(false)
	_load_layout()
	_auto_load_all_groups()

func _set_edit_ui_visible(v: bool) -> void:
	dim_overlay.visible = v
	side_panel.visible = v

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event is InputEventKey and event.pressed:
		if not event.echo and event.keycode == KEY_S and event.ctrl_pressed:
			_save_layout()
			_flash_save_button()
			get_viewport().set_input_as_handled()
			return
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
				var sz := Vector2.ZERO
				if _all_icon_size.has(_active_group):
					var aspect := _pending_object.get_width() / float(_pending_object.get_height())
					var w: float = _all_icon_size[_active_group]
					sz = Vector2(w, w / aspect)
				_place_object(_pending_object, mp, sz, _pending_path)
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
		opened_changed.emit(true)
	else:
		_request_close()

# --- Group ---

func _set_group(group: String) -> void:
	_all_icon_selected = false
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
	_undo_stack.clear()
	_dirty = false

func _auto_load_group(group: String) -> void:
	var folder := "res://assets/" + group + "/"
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	var d: Dictionary = GROUP_DEFAULTS[group]
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
				if _is_blocked(group, full_path) or _deleted_paths[group].has(full_path):
					file = dir.get_next()
					continue
				if not placed_paths.has(full_path):
					var tex := _load_tex(full_path)
					if tex:
						var cols: int = int(d["cols"])
						var col := slot % cols
						var row := slot / cols
						var aspect := tex.get_width() / float(tex.get_height())
						var base_w: float = _all_icon_size.get(group, float(d["size"]))
						var sz := Vector2(base_w, base_w / aspect)
						# _place_object centers on a 100-wide hit-box; compensate so the
						# top-left lands at the grid origin we computed here.
						var center_comp := Vector2(50.0, 50.0 / aspect)
						var pos: Vector2 = d["origin"] + Vector2(col * d["spacing"].x, row * d["spacing"].y) + center_comp
						_place_object(tex, pos, sz, full_path, true)
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
	if obj.group_id == "screen":
		_animate_screen_objects()
		GameManager.add_views(1)

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
	_all_icon_selected = false
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

func _on_all_icon_selected() -> void:
	_all_icon_selected = true
	# Clear sprite selection without going through _select_objects, which would
	# also reset the transform panel out of all-icon mode.
	for group in GROUPS:
		for obj in _placed[group]:
			if is_instance_valid(obj):
				obj.selected = false
	_selected_objects.clear()
	btn_delete.disabled = true
	transform_panel.refresh_all_icon(_all_icon_size.get(_active_group, 80.0))

func _on_all_icon_size_changed(new_size: float) -> void:
	if not _all_icon_size.has(_active_group):
		return
	_all_icon_size[_active_group] = new_size
	_bulk_resize_centered(_active_group, new_size)
	_dirty = true

func _bulk_resize_centered(group: String, new_w: float) -> void:
	for obj in _placed[group]:
		if not is_instance_valid(obj):
			continue
		var tex: Texture2D = obj.texture_rect.texture
		if tex == null:
			continue
		var aspect: float = tex.get_width() / float(tex.get_height())
		var new_size := Vector2(new_w, new_w / aspect)
		var center: Vector2 = obj.position + obj.size / 2.0
		obj.size = new_size
		obj.position = center - new_size / 2.0
		obj._sync_rect_size()

func _on_transform_live(pos: Vector2, sz: Vector2) -> void:
	var primary := _primary_selected()
	if not primary or not is_instance_valid(primary):
		return
	primary.position = pos
	primary.size = sz
	primary._sync_rect_size()
	_dirty = true

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
	# A path being placed again means it's no longer "user-deleted".
	if path != "" and _deleted_paths.has(_active_group):
		_deleted_paths[_active_group].erase(path)
	if not silent:
		object_list_panel.add_placed_object(obj)
	_push_undo_add(obj)
	_dirty = true
	return obj

func notify_transform_changed(obj: Control) -> void:
	_push_undo_transform(obj)
	_dirty = true
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
	if obj.source_path != "":
		_deleted_paths[group][obj.source_path] = true
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
	_flash_save_button()

func _flash_save_button() -> void:
	var btn: Button = $SidePanel/VBox/TopHBox/ButtonsColumn/SaveBtn
	if btn == null:
		return
	var prev_text := btn.text
	btn.text = "Saved!"
	await get_tree().create_timer(0.75).timeout
	if is_instance_valid(btn):
		btn.text = prev_text

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
	opened_changed.emit(false)

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
	for group in _all_icon_size:
		cfg.set_value("all_icon", group, _all_icon_size[group])
	for group in GROUPS:
		cfg.set_value("deleted", group, _deleted_paths[group].keys())
	cfg.save(LAYOUT_PATH)
	_dirty = false

func _is_blocked(group: String, path: String) -> bool:
	if not SOURCE_BLOCKLIST.has(group):
		return false
	var basename := path.get_file().get_basename().to_lower()
	return SOURCE_BLOCKLIST[group].has(basename)

func _load_tex(res_path: String) -> Texture2D:
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
	# Load all-icon master sizes first so that auto-load uses them.
	for group in _all_icon_size:
		if cfg.has_section_key("all_icon", group):
			_all_icon_size[group] = float(cfg.get_value("all_icon", group, _all_icon_size[group]))
	# Load deleted-path tombstones so auto-load skips them.
	for group in GROUPS:
		var deleted_list = cfg.get_value("deleted", group, [])
		for p in deleted_list:
			_deleted_paths[group][p] = true
	var prev_group := _active_group
	for group in GROUPS:
		var list = cfg.get_value("layout", group, [])
		_active_group = group
		for entry in list:
			if _is_blocked(group, entry["path"]):
				continue
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
		# Align scene-tree child order with z (Control mouse picking goes by tree order,
		# not z_index). Iterate from lowest z to highest so the final move_to_end puts
		# the highest-z item at the very end of the parent's children = picks clicks first.
		for i in range(n - 1, -1, -1):
			var obj: EditableObjectNode = _placed[group][i]
			if is_instance_valid(obj):
				var parent := obj.get_parent()
				if parent:
					parent.move_child(obj, parent.get_child_count() - 1)
	_active_group = prev_group
	_update_object_interactivity()
	_undo_stack.clear()
	_dirty = false
