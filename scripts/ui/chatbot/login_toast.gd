extends CanvasLayer

# Spawned when the browser opens for OAuth.
# Silently frees on success; shows bottom-right toast on error.

const PANEL_W := 380
const PANEL_H := 56

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	AuthManager.auth_changed.connect(_on_done)
	AuthManager.login_error.connect(_on_error)

func _on_done(_logged_in: bool) -> void:
	queue_free()

func _on_error(msg: String) -> void:
	_build_toast(msg)
	var t := Timer.new()
	t.wait_time = 6.0
	t.one_shot  = true
	add_child(t)
	t.timeout.connect(queue_free)
	t.start()

func _build_toast(detail: String = "") -> void:
	var panel := Panel.new()
	panel.size = Vector2(PANEL_W, PANEL_H)
	var ps := StyleBoxFlat.new()
	ps.bg_color            = Color(0.12, 0.05, 0.05, 0.96)
	ps.border_width_left   = 2; ps.border_width_right  = 2
	ps.border_width_top    = 2; ps.border_width_bottom = 2
	ps.border_color        = Color(0.85, 0.30, 0.30, 0.9)
	ps.corner_radius_top_left     = 6; ps.corner_radius_top_right    = 6
	ps.corner_radius_bottom_left  = 6; ps.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var lbl := Label.new()
	lbl.text = "Đăng nhập thất bại — " + detail if not detail.is_empty() else "Đăng nhập không thành công, vui lòng thử lại ở Setting"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.75))
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.offset_left = 12; lbl.offset_right  = -12
	lbl.offset_top  =  8; lbl.offset_bottom =  -8
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(lbl)

	call_deferred("_position_panel", panel)

func _position_panel(panel: Panel) -> void:
	var vp := get_viewport().get_visible_rect().size
	panel.position = Vector2(vp.x - PANEL_W - 16, vp.y - PANEL_H - 16)
