extends Control

signal screen_closed

const PANEL_SIZE := Vector2(680.0, 480.0)

var _title_label: Label
var _gold_label: Label
var _card_vbox: VBoxContainer
var _continue_btn: Button

func _ready() -> void:
	visible = false
	# Modal stays interactive even though the parent arena is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_right = 1.0
	anchor_bottom = 1.0

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	vbox.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	margin.add_child(inner)

	_title_label = Label.new()
	_title_label.text = "ROUND COMPLETE"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	inner.add_child(_title_label)

	_gold_label = Label.new()
	_gold_label.text = "GOLD: 0"
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	inner.add_child(_gold_label)

	var sep := HSeparator.new()
	inner.add_child(sep)

	_card_vbox = VBoxContainer.new()
	_card_vbox.add_theme_constant_override("separation", 10)
	_card_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(_card_vbox)

	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.custom_minimum_size = Vector2(160, 36)
	_continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_btn.pressed.connect(_on_continue_pressed)
	inner.add_child(_continue_btn)

	GameManager.gold_changed.connect(_on_gold_changed)
	Upgrades.purchased.connect(_on_upgrade_purchased)

func show_for_round(round_just_ended: int) -> void:
	_title_label.text = "ROUND %d COMPLETE" % round_just_ended
	_refresh_cards()
	_on_gold_changed(GameManager.gold)
	visible = true

func _refresh_cards() -> void:
	for c in _card_vbox.get_children():
		c.queue_free()
	for id in Upgrades.CATALOG:
		var card := _make_card(id, Upgrades.CATALOG[id])
		_card_vbox.add_child(card)

func _make_card(id: String, data: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(margin)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	margin.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = data["name"]
	name_lbl.add_theme_font_size_override("font_size", 18)
	info.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = Upgrades.get_desc(id)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(460, 0)
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96))
	info.add_child(desc_lbl)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120, 40)
	if Upgrades.is_owned(id):
		btn.text = "OWNED"
		btn.disabled = true
	else:
		var cost: int = int(data["cost"])
		btn.text = "BUY (%dg)" % cost
		btn.disabled = GameManager.gold < cost
		btn.pressed.connect(_on_buy_pressed.bind(id))
	hbox.add_child(btn)

	return panel

func _on_buy_pressed(id: String) -> void:
	Upgrades.try_purchase(id)
	# Refresh handled by _on_upgrade_purchased + _on_gold_changed signals.

func _on_continue_pressed() -> void:
	visible = false
	emit_signal("screen_closed")

func _on_gold_changed(new_gold: int) -> void:
	_gold_label.text = "GOLD: %d" % new_gold
	if visible:
		_refresh_cards()

func _on_upgrade_purchased(_id: String) -> void:
	if visible:
		_refresh_cards()
