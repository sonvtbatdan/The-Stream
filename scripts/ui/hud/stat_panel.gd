extends PanelContainer

@onready var template_label: Label = %TemplateLabel

func _ready() -> void:
	var font := load("res://fonts/GoodOldDOS.ttf") as FontFile
	if font:
		template_label.add_theme_font_override("font", font)
	GameManager.stat_template_changed.connect(_on_template_changed)
	GameManager.views_changed.connect(_on_value_changed)
	GameManager.subs_changed.connect(_on_value_changed)
	_refresh()

func _on_template_changed(_template: String) -> void:
	_refresh()

func _on_value_changed(_value: int) -> void:
	_refresh()

func _refresh() -> void:
	template_label.text = GameManager.render_stat_template()
