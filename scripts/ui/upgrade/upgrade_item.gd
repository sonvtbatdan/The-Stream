extends Button

signal pressed_id(upgrade_id: String)

@onready var icon_rect: TextureRect = %IconRect
@onready var name_label: Label      = %NameLabel
@onready var price_label: Label     = %PriceLabel
@onready var count_label: Label     = %CountLabel

var upgrade_id: String = ""
var _desc_popup: PanelContainer = null

func setup(id: String) -> void:
	upgrade_id = id
	var data: Dictionary = UpgradeManager.UPGRADES[id]
	name_label.text = data["name"]

	if data.has("icon"):
		var path: String = "res://assets/upgrades/active/" + String(data["icon"])
		var tex := load(path) as Texture2D
		if tex:
			icon_rect.texture = tex

	_build_desc_popup(String(data.get("desc", "")))
	_apply_styles()
	GameManager.stable_views_changed.connect(_on_stable_views_changed)
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_refresh_state()

func _build_desc_popup(text: String) -> void:
	if text.is_empty():
		return
	_desc_popup = PanelContainer.new()
	_desc_popup.visible = false
	_desc_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_popup.z_index = 100

	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.06, 0.10, 0.96)
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.3, 0.5, 0.7, 0.8)
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4
	s.corner_radius_bottom_right = 4
	s.content_margin_left   = 8.0
	s.content_margin_right  = 8.0
	s.content_margin_top    = 6.0
	s.content_margin_bottom = 6.0
	_desc_popup.add_theme_stylebox_override("panel", s)

	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.custom_minimum_size = Vector2(170.0, 0.0)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc_popup.add_child(lbl)
	# Added to root on first hover so ScrollContainer doesn't clip it

func _apply_styles() -> void:
	var _make := func(bg: Color, border: Color, corner: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_width_left   = 1
		s.border_width_right  = 1
		s.border_width_top    = 1
		s.border_width_bottom = 1
		s.border_color = border
		s.corner_radius_top_left     = corner
		s.corner_radius_top_right    = corner
		s.corner_radius_bottom_left  = corner
		s.corner_radius_bottom_right = corner
		return s

	# Normal — same as UserPanel child sub-panels
	add_theme_stylebox_override("normal",   _make.call(Color(0.07, 0.09, 0.13, 0.95), Color(0.35, 0.45, 0.65, 0.90), 6))
	# Hover — brighter border
	add_theme_stylebox_override("hover",    _make.call(Color(0.10, 0.13, 0.20, 0.95), Color(0.50, 0.65, 0.85, 0.95), 6))
	# Pressed — slightly darker bg
	add_theme_stylebox_override("pressed",  _make.call(Color(0.05, 0.07, 0.10, 0.95), Color(0.35, 0.45, 0.65, 0.80), 6))
	# Disabled — dim everything
	add_theme_stylebox_override("disabled", _make.call(Color(0.05, 0.06, 0.09, 0.70), Color(0.22, 0.28, 0.42, 0.45), 6))

func _on_mouse_entered() -> void:
	if _desc_popup == null:
		return
	if not _desc_popup.is_inside_tree():
		get_tree().root.add_child(_desc_popup)
	_desc_popup.global_position = global_position + Vector2(size.x + 4.0, 0.0)
	_desc_popup.visible = true

func _on_mouse_exited() -> void:
	if _desc_popup:
		_desc_popup.visible = false

func _exit_tree() -> void:
	if is_instance_valid(_desc_popup):
		_desc_popup.queue_free()
	_desc_popup = null

func _refresh_state() -> void:
	var price: int = UpgradeManager.get_current_price(upgrade_id)
	var cost_text := GameManager.format_views(price) + " views"
	if UpgradeManager.UPGRADES[upgrade_id].get("cost_type") == "per_credit":
		cost_text += "/credit"
	price_label.text = cost_text

	var count: int = UpgradeManager.get_owned_count(upgrade_id)
	count_label.text = "x%d" % count if count > 0 else ""

	var can_afford: bool = GameManager.stable_views >= price
	disabled = not can_afford

func _on_stable_views_changed(_v: int) -> void:
	_refresh_state()

func _on_pressed() -> void:
	print("[ToolsList] pressed id=%s disabled=%s price=%d stable_views=%d" % [
		upgrade_id, str(disabled),
		UpgradeManager.get_current_price(upgrade_id),
		GameManager.stable_views,
	])
	if UpgradeManager.try_purchase(upgrade_id):
		print("[ToolsList]   purchase OK")
		_refresh_state()
		pressed_id.emit(upgrade_id)
	else:
		print("[ToolsList]   purchase FAILED")
