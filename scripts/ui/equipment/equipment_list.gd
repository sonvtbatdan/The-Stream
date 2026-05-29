extends Panel

const EquipmentItem := preload("res://scenes/ui/equipment/equipment_item.tscn")

@onready var vbox: VBoxContainer = $Scroll/EquipmentVBox

var _panel_style: StyleBoxFlat = null

func _ready() -> void:
	_apply_panel_style()
	for child in vbox.get_children():
		child.free()
	for id in EquipmentManager.ITEMS:
		var item: Control = EquipmentItem.instantiate()
		vbox.add_child(item)
		item.setup(id)

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

func set_edit_mode(active: bool) -> void:
	if _panel_style == null:
		return
	_panel_style.border_color = Color(0.2, 0.7, 0.8, 1.0) if active else Color(0.3, 0.4, 0.6, 0.9)
	_panel_style.border_width_left   = 3 if active else 2
	_panel_style.border_width_right  = 3 if active else 2
	_panel_style.border_width_top    = 3 if active else 2
	_panel_style.border_width_bottom = 3 if active else 2
