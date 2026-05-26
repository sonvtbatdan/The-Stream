class_name UserTodoList
extends Panel

const SAVE_PATH  := "user://todo.cfg"
const NUM_TASKS  := 4
const PANEL_W    := 460.0
const PANEL_H    := 220.0

var _checks: Array[CheckBox] = []
var _inputs: Array[LineEdit] = []

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = Vector2(PANEL_W, PANEL_H)
	_apply_style()
	_build_ui()
	_load()

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.07, 0.09, 0.13, 0.95)
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.border_color        = Color(0.35, 0.45, 0.65, 0.9)
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", s)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left   = 14
	root.offset_top    = 10
	root.offset_right  = -14
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "To-Do List"
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var sep := HSeparator.new()
	root.add_child(sep)

	for i in NUM_TASKS:
		var row := HBoxContainer.new()
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		root.add_child(row)

		var chk := CheckBox.new()
		chk.custom_minimum_size = Vector2(24, 24)
		chk.toggled.connect(func(_p: bool) -> void: _save())
		row.add_child(chk)
		_checks.append(chk)

		var inp := LineEdit.new()
		inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inp.placeholder_text = "Task %d…" % (i + 1)
		inp.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
		inp.add_theme_color_override("font_placeholder_color", Color(0.45, 0.45, 0.45))
		inp.text_submitted.connect(func(_t: String) -> void: _save())
		inp.focus_exited.connect(_save)
		row.add_child(inp)
		_inputs.append(inp)

func _save() -> void:
	var cfg := ConfigFile.new()
	for i in NUM_TASKS:
		cfg.set_value("tasks", "check_%d" % i, _checks[i].button_pressed)
		cfg.set_value("tasks", "text_%d"  % i, _inputs[i].text)
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for i in NUM_TASKS:
		_checks[i].button_pressed = cfg.get_value("tasks", "check_%d" % i, false)
		_inputs[i].text           = cfg.get_value("tasks", "text_%d"  % i, "")
