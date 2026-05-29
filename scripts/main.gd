extends Control

@onready var edit_mode = $EditMode
@onready var visual_container: HBoxContainer = %VisualContainer

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	DisplayServer.window_set_current_screen(DisplayServer.get_primary_screen())
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	_apply_title_fonts()
	GameManager.load_game()
	UpgradeManager.load_game()
	GameManager.game_loaded.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameManager.save_game()
		UpgradeManager.save_game()
		get_tree().quit()

func _apply_title_fonts() -> void:
	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile
	if not font:
		return
	var titles: Array[Label] = [
		$ViewColumn/ViewTitle,
		$CommentColumn/CommentTitle,
		$EquipmentColumn/EquipTitle,
		$ChatbotPanel/VBox/TitleLabel,
	]
	for lbl in titles:
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 14)
	# Shift anchored titles 5 px down
	for lbl: Label in [$ViewColumn/ViewTitle, $CommentColumn/CommentTitle, $EquipmentColumn/EquipTitle]:
		lbl.offset_top = 5.0

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
