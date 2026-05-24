extends Control

@onready var edit_mode = $EditMode
@onready var visual_container: HBoxContainer = %VisualContainer

func _ready() -> void:
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_edit_mode"):
		edit_mode.toggle()
		get_viewport().set_input_as_handled()

func _on_upgrade_purchased(upgrade_id: String) -> void:
	var path := "res://assets/upgrade/" + upgrade_id + ".png"
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size = Vector2(36, 36)
	rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	visual_container.add_child(rect)
