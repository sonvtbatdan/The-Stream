extends Panel

const SETTINGS_PATH := "user://settings.cfg"

const RESOLUTIONS: Array = [
	{"label": "720p\n1280×720",   "size": Vector2i(1280,  720)},
	{"label": "1080p\n1920×1080", "size": Vector2i(1920, 1080)},
	{"label": "2K\n2560×1440",    "size": Vector2i(2560, 1440)},
]

var _overlay_layer:    CanvasLayer   = null
var _overlay_rect:     ColorRect     = null
var _settings_panel:   Panel         = null
var _res_btns:     Array[Button] = []
var _music_slider: HSlider       = null
var _sfx_slider:   HSlider       = null

var _init_music_vol: float = 1.0
var _init_sfx_vol:   float = 1.0

func _ready() -> void:
	# Must stay active while game is paused so SETTING/QUIT buttons still work.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_style()
	_load_settings()
	_build_action_bar()
	call_deferred("_build_settings_panel")

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.06, 0.08, 0.12, 0.88)
	s.border_width_left   = 2; s.border_width_right  = 2
	s.border_width_top    = 2; s.border_width_bottom = 2
	s.border_color        = Color(0.3, 0.4, 0.6, 0.9)
	s.corner_radius_top_left     = 8; s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8; s.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", s)

# ── Action bar ────────────────────────────────────────────────────────────────

func _build_action_bar() -> void:
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 6; hbox.offset_right  = -6
	hbox.offset_top  = 4; hbox.offset_bottom = -4
	hbox.add_theme_constant_override("separation", 4)
	add_child(hbox)

	var setting_btn := _make_btn("SETTING")
	var quit_btn    := _make_btn("QUIT")
	hbox.add_child(setting_btn)
	hbox.add_child(quit_btn)
	setting_btn.pressed.connect(_toggle_settings)
	quit_btn.pressed.connect(_on_quit)

func _make_btn(txt: String) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	var mk := func(bg: Color, bc: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_width_left = 1; s.border_width_right  = 1
		s.border_width_top  = 1; s.border_width_bottom = 1
		s.border_color = bc
		s.corner_radius_top_left    = 3; s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left = 3; s.corner_radius_bottom_right = 3
		s.content_margin_top = 4; s.content_margin_bottom = 4
		return s
	btn.add_theme_stylebox_override("normal",  mk.call(Color(0.09, 0.12, 0.18, 0.9), Color(0.30, 0.40, 0.60, 0.7)))
	btn.add_theme_stylebox_override("hover",   mk.call(Color(0.14, 0.18, 0.28, 0.9), Color(0.50, 0.65, 0.90, 0.9)))
	btn.add_theme_stylebox_override("pressed", mk.call(Color(0.06, 0.08, 0.13, 0.9), Color(0.30, 0.40, 0.60, 0.7)))
	btn.add_theme_stylebox_override("focus",   mk.call(Color(0.09, 0.12, 0.18, 0.9), Color(0.30, 0.40, 0.60, 0.7)))
	return btn

# ── Settings overlay ──────────────────────────────────────────────────────────

func _build_settings_panel() -> void:
	# CanvasLayer at layer 100 — always on top of all game content.
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer        = 100
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay_layer.visible      = false

	# Semi-transparent dark backdrop. MOUSE_FILTER_STOP blocks clicks to game.
	_overlay_rect = ColorRect.new()
	_overlay_rect.color        = Color(0.0, 0.0, 0.0, 0.60)
	_overlay_rect.anchor_right  = 1.0
	_overlay_rect.anchor_bottom = 1.0
	_overlay_rect.mouse_filter  = Control.MOUSE_FILTER_STOP
	_overlay_layer.add_child(_overlay_rect)

	# Settings panel itself.
	_settings_panel = Panel.new()
	_settings_panel.z_index = 1
	_settings_panel.size    = Vector2(310, 320)
	_settings_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var ps := StyleBoxFlat.new()
	ps.bg_color            = Color(0.06, 0.08, 0.14, 0.97)
	ps.border_width_left   = 2; ps.border_width_right  = 2
	ps.border_width_top    = 2; ps.border_width_bottom = 2
	ps.border_color        = Color(0.40, 0.55, 0.80, 0.90)
	ps.corner_radius_top_left     = 8; ps.corner_radius_top_right    = 8
	ps.corner_radius_bottom_left  = 8; ps.corner_radius_bottom_right = 8
	_settings_panel.add_theme_stylebox_override("panel", ps)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12; vbox.offset_right  = -12
	vbox.offset_top  = 12; vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 8)
	_settings_panel.add_child(vbox)

	var title := _make_lbl("SETTINGS", 14, Color(0.82, 0.92, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# ── Resolution ──
	vbox.add_child(_make_lbl("Resolution", 11, Color(0.60, 0.75, 0.90)))
	var res_hbox := HBoxContainer.new()
	res_hbox.add_theme_constant_override("separation", 4)
	_res_btns.clear()
	for r in RESOLUTIONS:
		var btn := Button.new()
		btn.text = r["label"]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 10)
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		btn.pressed.connect(_on_res_selected.bind(r["size"]))
		_res_btns.append(btn)
		res_hbox.add_child(btn)
	vbox.add_child(res_hbox)
	vbox.add_child(HSeparator.new())

	# ── Volume ──
	vbox.add_child(_make_lbl("Volume", 11, Color(0.60, 0.75, 0.90)))
	_music_slider = _add_slider_row(vbox, "Music", _init_music_vol)
	_sfx_slider   = _add_slider_row(vbox, "SFX",   _init_sfx_vol)

	_music_slider.value_changed.connect(func(v: float) -> void:
		AudioManager.set_music_volume(v)
		_save_settings())
	_sfx_slider.value_changed.connect(func(v: float) -> void:
		AudioManager.set_sfx_volume(v)
		_save_settings())

	vbox.add_child(HSeparator.new())
	var close_btn := _make_btn("CLOSE")
	close_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	close_btn.pressed.connect(_close_settings)
	vbox.add_child(close_btn)

	_overlay_layer.add_child(_settings_panel)
	get_tree().root.add_child(_overlay_layer)
	_center_settings()
	_update_res_btns()

func _make_lbl(txt: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l

func _add_slider_row(parent: VBoxContainer, label_text: String, initial: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl := _make_lbl(label_text, 10, Color(0.75, 0.82, 0.95))
	lbl.custom_minimum_size = Vector2(88, 0)
	lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step      = 0.02
	slider.value     = clampf(initial, 0.0, 1.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.process_mode          = Node.PROCESS_MODE_ALWAYS

	var pct := _make_lbl("%d%%" % int(initial * 100.0), 10, Color(0.60, 0.70, 0.88))
	pct.custom_minimum_size    = Vector2(34, 0)
	pct.horizontal_alignment   = HORIZONTAL_ALIGNMENT_RIGHT
	pct.vertical_alignment     = VERTICAL_ALIGNMENT_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % int(v * 100.0))

	row.add_child(lbl)
	row.add_child(slider)
	row.add_child(pct)
	parent.add_child(row)
	return slider

func _toggle_settings() -> void:
	if not is_instance_valid(_overlay_layer):
		return
	if _overlay_layer.visible:
		_close_settings()
	else:
		_open_settings()

func _open_settings() -> void:
	_update_res_btns()
	_center_settings()
	_overlay_layer.visible = true
	get_tree().paused = true

func _close_settings() -> void:
	if is_instance_valid(_overlay_layer):
		_overlay_layer.visible = false
	get_tree().paused = false

func _center_settings() -> void:
	if not is_instance_valid(_settings_panel):
		return
	var vp := get_viewport().get_visible_rect().size
	_settings_panel.position = ((vp - _settings_panel.size) * 0.5).floor()

# Allow Escape key to close settings while paused.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and is_instance_valid(_overlay_layer) and _overlay_layer.visible:
			_close_settings()
			get_viewport().set_input_as_handled()

# ── Resolution ────────────────────────────────────────────────────────────────

func _on_res_selected(res: Vector2i) -> void:
	DisplayServer.window_set_size(res)
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen - res) / 2)
	_update_res_btns()
	_save_settings()

func _update_res_btns() -> void:
	if _res_btns.is_empty():
		return
	var cur := DisplayServer.window_get_size()
	for i in _res_btns.size():
		var target: Vector2i = RESOLUTIONS[i]["size"]
		_res_btns[i].add_theme_color_override("font_color",
			Color(0.35, 0.88, 1.0) if cur == target else Color(0.72, 0.78, 0.90))

# ── Quit ──────────────────────────────────────────────────────────────────────

func _on_quit() -> void:
	get_tree().paused = false
	GameManager.save_game()
	UpgradeManager.save_game()
	get_tree().quit()

# ── Persistence ───────────────────────────────────────────────────────────────

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	var res := DisplayServer.window_get_size()
	cfg.set_value("display", "width",  res.x)
	cfg.set_value("display", "height", res.y)
	cfg.set_value("audio", "music_vol", AudioManager.music_volume)
	cfg.set_value("audio", "sfx_vol",   AudioManager.sfx_volume)
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var w: int = cfg.get_value("display", "width",  1280)
	var h: int = cfg.get_value("display", "height",  720)
	DisplayServer.window_set_size(Vector2i(w, h))
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen - Vector2i(w, h)) / 2)

	_init_music_vol = cfg.get_value("audio", "music_vol", 1.0)
	_init_sfx_vol   = cfg.get_value("audio", "sfx_vol",   1.0)
	AudioManager.set_music_volume(_init_music_vol)
	AudioManager.set_sfx_volume(_init_sfx_vol)

