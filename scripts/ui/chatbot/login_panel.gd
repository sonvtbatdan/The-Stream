extends CanvasLayer

const PANEL_W      := 460
const PANEL_H      := 340
const SETTINGS_PATH := "user://settings.cfg"
const GEMINI_MODEL  := "gemini-3.1-flash-lite" # Hằng số định danh model mới để script khác có thể gọi

var _panel:         Panel    = null
var _key_input:     LineEdit = null
var _tavily_input:  LineEdit = null
var _save_btn:      Button   = null
var _skip_btn:      Button   = null
var _status_lbl:    Label    = null

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_load_existing_key()

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color         = Color(0.0, 0.0, 0.0, 0.78)
	backdrop.anchor_right  = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter  = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	var ps := StyleBoxFlat.new()
	ps.bg_color            = Color(0.06, 0.08, 0.14, 0.97)
	ps.border_width_left   = 2; ps.border_width_right  = 2
	ps.border_width_top    = 2; ps.border_width_bottom = 2
	ps.border_color        = Color(0.40, 0.55, 0.80, 0.90)
	ps.corner_radius_top_left     = 8; ps.corner_radius_top_right    = 8
	ps.corner_radius_bottom_left  = 8; ps.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override("panel", ps)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 24; vbox.offset_right  = -24
	vbox.offset_top  = 20; vbox.offset_bottom = -20
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	var title := _lbl("Stream Assistant — AI Chat", 16, Color(0.82, 0.92, 1.0), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := _lbl("Dán Google Gemini API Key để dùng AI chat miễn phí.\nLấy key tại: aistudio.google.com → Get API Key", 10, Color(0.6, 0.72, 0.9))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	_key_input = LineEdit.new()
	_key_input.placeholder_text = "Google API Key (AIza...) — bắt buộc"
	_key_input.add_theme_font_size_override("font_size", 11)
	_key_input.text_submitted.connect(func(_t: String): _on_save(_key_input.text))
	vbox.add_child(_key_input)

	var tavily_lbl := _lbl("Tavily API Key (tùy chọn — để Lisa tìm kiếm web / đọc tin tức)", 9, Color(0.55, 0.68, 0.85))
	vbox.add_child(tavily_lbl)

	_tavily_input = LineEdit.new()
	_tavily_input.placeholder_text = "Tavily Key (tvly-...) — lấy miễn phí tại app.tavily.com"
	_tavily_input.add_theme_font_size_override("font_size", 11)
	_tavily_input.text_submitted.connect(func(_t: String): _on_save(_key_input.text))
	vbox.add_child(_tavily_input)

	_status_lbl = _lbl("", 9, Color(1.0, 0.5, 0.4))
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_lbl.visible = false
	vbox.add_child(_status_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_save_btn = _make_btn("  Lưu & Bắt đầu  ")
	_save_btn.pressed.connect(func(): _on_save(_key_input.text))
	_skip_btn = _make_btn("Bỏ qua")
	_skip_btn.pressed.connect(_on_skip)
	row.add_child(_save_btn)
	row.add_child(_skip_btn)
	vbox.add_child(row)

	add_child(_panel)
	call_deferred("_center_panel")
	call_deferred("_focus_input")

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size
	_panel.position = ((vp - _panel.size) * 0.5).floor()

func _focus_input() -> void:
	_key_input.grab_focus()

func _load_existing_key() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	# Thay thế key đọc từ file config cũ sang gemini_api_key
	var k: String = cfg.get_value("ai", "gemini_api_key", "")
	if not k.is_empty():
		_key_input.text = k
	var t: String = cfg.get_value("ai", "tavily_api_key", "")
	if not t.is_empty():
		_tavily_input.text = t

func _on_save(key: String) -> void:
	key = key.strip_edges()
	if key.is_empty():
		_status_lbl.text    = "Vui lòng dán Google Gemini API Key trước."
		_status_lbl.visible = true
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	# Cập nhật key ghi vào file config thành gemini_api_key
	cfg.set_value("ai", "gemini_api_key", key)
	
	# Đồng thời lưu lại tên model chính xác để các thành phần core AI trong game tự lấy ra dùng
	cfg.set_value("ai", "gemini_model", GEMINI_MODEL)
	
	var tavily := _tavily_input.text.strip_edges()
	if not tavily.is_empty():
		cfg.set_value("ai", "tavily_api_key", tavily)
	cfg.save(SETTINGS_PATH)
	queue_free()

func _on_skip() -> void:
	queue_free()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _lbl(txt: String, sz: int, col: Color, _bold: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l

func _make_btn(txt: String) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.add_theme_font_size_override("font_size", 11)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	var mk := func(bg: Color, bc: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color            = bg
		s.border_width_left   = 1; s.border_width_right  = 1
		s.border_width_top    = 1; s.border_width_bottom = 1
		s.border_color        = bc
		s.corner_radius_top_left    = 4; s.corner_radius_top_right    = 4
		s.corner_radius_bottom_left = 4; s.corner_radius_bottom_right = 4
		s.content_margin_top = 6; s.content_margin_bottom = 6
		s.content_margin_left = 10; s.content_margin_right = 10
		return s
	btn.add_theme_stylebox_override("normal",  mk.call(Color(0.09, 0.14, 0.24, 0.9), Color(0.35, 0.50, 0.80, 0.8)))
	btn.add_theme_stylebox_override("hover",   mk.call(Color(0.14, 0.22, 0.38, 0.9), Color(0.55, 0.72, 1.00, 0.9)))
	btn.add_theme_stylebox_override("pressed", mk.call(Color(0.06, 0.10, 0.18, 0.9), Color(0.35, 0.50, 0.80, 0.8)))
	btn.add_theme_stylebox_override("focus",   mk.call(Color(0.09, 0.14, 0.24, 0.9), Color(0.35, 0.50, 0.80, 0.8)))
	return btn