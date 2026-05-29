extends Button

signal pressed_id(item_id: String)

@onready var icon_rect:   TextureRect = %IconRect
@onready var name_label:  Label       = %NameLabel
@onready var price_label: Label       = %PriceLabel
@onready var count_label: Label       = %CountLabel

var item_id: String = ""

func setup(id: String) -> void:
	item_id = id
	var data: Dictionary = EquipmentManager.ITEMS[id]
	name_label.text = data["name"]

	var icon_path: String = "res://assets/upgrades/equipment/" + String(data["icon"])
	var tex := load(icon_path) as Texture2D
	if tex:
		icon_rect.texture = tex

	_apply_styles()
	GameManager.cash_changed.connect(_on_cash_changed)
	EquipmentManager.items_reset.connect(_refresh_state)
	pressed.connect(_on_pressed)
	_refresh_state()

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
	add_theme_stylebox_override("normal",   _make.call(Color(0.07, 0.09, 0.13, 0.95), Color(0.35, 0.45, 0.65, 0.90), 6))
	add_theme_stylebox_override("hover",    _make.call(Color(0.10, 0.13, 0.20, 0.95), Color(0.50, 0.65, 0.85, 0.95), 6))
	add_theme_stylebox_override("pressed",  _make.call(Color(0.05, 0.07, 0.10, 0.95), Color(0.35, 0.45, 0.65, 0.80), 6))
	add_theme_stylebox_override("disabled", _make.call(Color(0.05, 0.06, 0.09, 0.70), Color(0.22, 0.28, 0.42, 0.45), 6))

func _refresh_state() -> void:
	var count: int = EquipmentManager.get_owned(item_id)
	if count >= 1:
		price_label.text = ""
		count_label.text = "Bought"
		disabled = true
		modulate = Color(0.55, 0.55, 0.55, 0.75)
	else:
		var cost: float = float(EquipmentManager.ITEMS[item_id]["cost"])
		price_label.text = "$%.0f" % cost
		count_label.text = ""
		disabled = not (GameManager.cash >= cost)
		modulate = Color.WHITE

func _on_cash_changed(_c: float) -> void:
	_refresh_state()

func _on_pressed() -> void:
	if EquipmentManager.try_purchase(item_id):
		_refresh_state()
		pressed_id.emit(item_id)
