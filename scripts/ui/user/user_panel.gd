# UserPanel — 500×780 overlay panel containing the streamer utility widgets.
# Lives on CanvasLayer 5 (above game, below Edit Mode at layer 10).
# In edit mode: shows a teal drag-handle bar; dragging it repositions the panel.
extends CanvasLayer

const SAVE_PATH    := "user://user_panel.cfg"
const PANEL_W      := 500.0
const PANEL_H      := 780.0
const PANEL_SCALE  := 0.5
const HANDLE_H     := 28.0
const PAD          := 20.0
const BOX_SIZE     := Vector2(200.0, 200.0)
const TODO_H       := 220.0   # must match TodoListScript.PANEL_H
const MUSIC_H      := 200.0   # matches UserMusicPlayer.COLLAPSED_H

var _root:       Panel
var _handle:     Panel
var _todo:       UserTodoList
var _music:      UserMusicPlayer
var _weather:    UserWeatherClock
var _empty_box:  Panel
var _thumb_rect: TextureRect = null

# Edit-mode drag state
var _edit_mode  := false
var _dragging   := false
var _drag_off   := Vector2.ZERO

signal position_changed(pos: Vector2)

func _ready() -> void:
	layer = 5
	_build()
	_load_position()
	set_edit_mode(false)

func _build() -> void:
	_root = Panel.new()
	_root.size = Vector2(PANEL_W, PANEL_H)
	_root.scale = Vector2(PANEL_SCALE, PANEL_SCALE)
	_apply_root_style()
	add_child(_root)

	# ── USER title label (always visible) ───────────────────────
	var title_lbl := Label.new()
	title_lbl.position = Vector2(0, 10)
	title_lbl.size = Vector2(PANEL_W, HANDLE_H)
	title_lbl.text = "USER"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _gf := load("res://assets/fonts/Gameplay.ttf") as FontFile
	if _gf:
		title_lbl.add_theme_font_override("font", _gf)
	_root.add_child(title_lbl)

	# ── Drag handle (edit mode only) ─────────────────────────────
	_handle = Panel.new()
	_handle.position = Vector2.ZERO
	_handle.size = Vector2(PANEL_W, HANDLE_H)
	_handle.mouse_default_cursor_shape = Control.CURSOR_DRAG
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.2, 0.6, 0.7, 0.85)
	_handle.add_theme_stylebox_override("panel", hs)
	_root.add_child(_handle)

	var hlbl := Label.new()
	hlbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hlbl.text = "≡  USER PANEL  —  drag to move"
	hlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hlbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	hlbl.add_theme_font_size_override("font_size", 11)
	hlbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_handle.add_child(hlbl)

	_handle.gui_input.connect(_on_handle_input)

	# ── Content ──────────────────────────────────────────────────
	var content_top: float = HANDLE_H + PAD

	_todo = UserTodoList.new()
	_todo.position = Vector2(PAD, content_top)
	_root.add_child(_todo)

	var todo_bottom: float = content_top + TODO_H
	var music_y:     float = todo_bottom + PAD
	var music_bottom: float = music_y + MUSIC_H
	var box_y:       float = music_bottom + PAD

	# Weather and thumbnail added FIRST so music (added last) draws on top when expanded
	_weather = UserWeatherClock.new()
	_weather.position = Vector2(PAD, box_y)
	_root.add_child(_weather)

	_empty_box = _make_empty_box()
	_empty_box.position = Vector2(PAD + BOX_SIZE.x + PAD, box_y)
	_root.add_child(_empty_box)

	_thumb_rect = TextureRect.new()
	_thumb_rect.position = Vector2(4, 4)
	_thumb_rect.size = Vector2(BOX_SIZE.x - 8, BOX_SIZE.y - 8)
	_thumb_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_empty_box.add_child(_thumb_rect)

	# Music added LAST — renders on top of weather/thumbnail when expanded
	_music = UserMusicPlayer.new()
	_music.position = Vector2(PAD, music_y)
	_music.max_expanded_h = PANEL_H - music_y - PAD * 0.5
	_root.add_child(_music)

	_music.thumbnail_ready.connect(func(tex: ImageTexture) -> void:
		if is_instance_valid(_thumb_rect):
			_thumb_rect.texture = tex)

func _apply_root_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.06, 0.08, 0.12, 0.88)
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_width_top    = 2
	s.border_width_bottom = 2
	s.border_color        = Color(0.3, 0.4, 0.6, 0.9)
	s.corner_radius_top_left     = 8
	s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8
	s.corner_radius_bottom_right = 8
	_root.add_theme_stylebox_override("panel", s)

func _make_empty_box() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = BOX_SIZE
	p.size = BOX_SIZE
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
	p.add_theme_stylebox_override("panel", s)
	return p

# ── Edit mode ────────────────────────────────────────────────────────────────

func set_edit_mode(active: bool) -> void:
	_edit_mode = active
	_handle.visible = active
	# In edit mode highlight the outer border
	var s := _root.get_theme_stylebox("panel") as StyleBoxFlat
	if s:
		s.border_color = Color(0.2, 0.7, 0.8, 1.0) if active else Color(0.3, 0.4, 0.6, 0.9)
		s.border_width_left   = 3 if active else 2
		s.border_width_right  = 3 if active else 2
		s.border_width_top    = 3 if active else 2
		s.border_width_bottom = 3 if active else 2

# ── Drag ─────────────────────────────────────────────────────────────────────

func _on_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_off = _root.global_position - get_viewport().get_mouse_position()
		else:
			_dragging = false
			_save_position()

func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		var vp  := get_viewport().get_visible_rect().size
		var mp  := get_viewport().get_mouse_position()
		var np  := mp + _drag_off
		np.x = clampf(np.x, 0.0, vp.x - PANEL_W * PANEL_SCALE)
		np.y = clampf(np.y, 0.0, vp.y - PANEL_H * PANEL_SCALE)
		_root.position = np
		position_changed.emit(np)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		_save_position()

# ── Persistence ──────────────────────────────────────────────────────────────

func _save_position() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("panel", "pos", _root.position)
	cfg.save(SAVE_PATH)

func _load_position() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_root.position = cfg.get_value("panel", "pos", Vector2(980.0, 8.0))
	else:
		_root.position = Vector2(980.0, 8.0)

func get_display_rect() -> Rect2:
	if _root:
		return Rect2(_root.position, _root.size * _root.scale)
	return Rect2(Vector2(20.0, 20.0), Vector2(PANEL_W * PANEL_SCALE, PANEL_H * PANEL_SCALE))
