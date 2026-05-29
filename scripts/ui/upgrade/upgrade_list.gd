extends Panel

const UpgradeItem := preload("res://scenes/ui/upgrade/upgrade_item.tscn")

@onready var vbox: VBoxContainer   = $Scroll/UpgradeVBox
@onready var scroll: ScrollContainer = $Scroll

@export var only_tab: String = ""
@export var max_panel_h: float = 0.0

var _panel_style: StyleBoxFlat = null
var _current_tab: String = "view"
var _tab_view_btn: Button    = null
var _tab_comment_btn: Button = null

func _ready() -> void:
	_apply_panel_style()
	if only_tab != "":
		_current_tab = only_tab
	else:
		_build_tab_bar()
	_build_items(_current_tab)
	call_deferred("_fit_size")

func _apply_panel_style() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color            = Color(0.06, 0.08, 0.12, 0.88)
	_panel_style.border_width_left   = 2
	_panel_style.border_width_right  = 2
	_panel_style.border_width_top    = 2
	_panel_style.border_width_bottom = 2
	_panel_style.border_color        = Color(0.3, 0.4, 0.6, 0.9)
	_panel_style.corner_radius_top_left     = 8
	_panel_style.corner_radius_top_right    = 8
	_panel_style.corner_radius_bottom_left  = 8
	_panel_style.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", _panel_style)

func _build_tab_bar() -> void:
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hbox.offset_top    = 26.0
	hbox.offset_bottom = 48.0
	hbox.offset_left   = 4.0
	hbox.offset_right  = -4.0
	add_child(hbox)

	_tab_view_btn    = _make_tab_btn("VIEW")
	_tab_comment_btn = _make_tab_btn("COMMENT")
	hbox.add_child(_tab_view_btn)
	hbox.add_child(_tab_comment_btn)

	_tab_view_btn.pressed.connect(func(): _switch_tab("view"))
	_tab_comment_btn.pressed.connect(func(): _switch_tab("comment"))

	scroll.offset_top = 50.0
	_update_tab_buttons()

func _make_tab_btn(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	var s_normal := StyleBoxFlat.new()
	s_normal.bg_color   = Color(0.09, 0.12, 0.18, 0.9)
	s_normal.border_width_bottom = 1
	s_normal.border_color = Color(0.3, 0.4, 0.6, 0.6)
	btn.add_theme_stylebox_override("normal",   s_normal)
	btn.add_theme_stylebox_override("hover",    s_normal)
	btn.add_theme_stylebox_override("pressed",  s_normal)
	btn.add_theme_stylebox_override("focus",    s_normal)
	return btn

func _switch_tab(tab: String) -> void:
	if _current_tab == tab:
		return
	_current_tab = tab
	_build_items(tab)
	_update_tab_buttons()
	call_deferred("_fit_size")

func _update_tab_buttons() -> void:
	var active_col   := Color(0.4, 0.75, 1.0)
	var inactive_col := Color(0.45, 0.50, 0.60)
	_tab_view_btn.add_theme_color_override("font_color",
		active_col if _current_tab == "view" else inactive_col)
	_tab_comment_btn.add_theme_color_override("font_color",
		active_col if _current_tab == "comment" else inactive_col)

func _build_items(tab: String) -> void:
	for child in vbox.get_children():
		child.free()
	for id in UpgradeManager.UPGRADES:
		var data: Dictionary = UpgradeManager.UPGRADES[id]
		if data.get("tab", "view") != tab:
			continue
		var item: Control = UpgradeItem.instantiate()
		vbox.add_child(item)
		item.setup(id)

func _fit_size() -> void:
	var content_h: float = vbox.get_combined_minimum_size().y
	var needed_h: float = content_h + 58.0
	var max_h: float = max_panel_h if max_panel_h > 0.0 else (780.0 - position.y - 8.0)
	size = Vector2(250.0, minf(needed_h, max_h))

func set_edit_mode(active: bool) -> void:
	if _panel_style == null:
		return
	_panel_style.border_color = Color(0.2, 0.7, 0.8, 1.0) if active else Color(0.3, 0.4, 0.6, 0.9)
	_panel_style.border_width_left   = 3 if active else 2
	_panel_style.border_width_right  = 3 if active else 2
	_panel_style.border_width_top    = 3 if active else 2
	_panel_style.border_width_bottom = 3 if active else 2
