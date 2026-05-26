extends PanelContainer

@onready var template_label: Label = %TemplateLabel

func _ready() -> void:
	var font := load("res://fonts/GoodOldDOS.ttf") as FontFile
	if font:
		template_label.add_theme_font_override("font", font)
	GameManager.stat_template_changed.connect(_on_template_changed)
	GameManager.views_changed.connect(_on_value_changed)
	GameManager.subs_changed.connect(_on_value_changed)
	GameManager.cash_changed.connect(_on_cash_changed)
	# VPS jumps on tool purchase — refresh so {vps} updates immediately.
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	_refresh()

func _on_template_changed(_template: String) -> void:
	_refresh()

func _on_value_changed(_value: int) -> void:
	_refresh()

func _on_cash_changed(_cash: float) -> void:
	_refresh()

func _on_upgrade_purchased(_id: String) -> void:
	_refresh()

func _refresh() -> void:
	template_label.text = GameManager.render_stat_template()
