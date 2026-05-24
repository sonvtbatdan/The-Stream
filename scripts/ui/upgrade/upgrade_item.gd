extends PanelContainer

signal pressed(upgrade_id: String)

@onready var name_label: Label = %NameLabel
@onready var cost_label: Label = %CostLabel
@onready var count_label: Label = %CountLabel
@onready var buy_button: Button = %BuyButton

var upgrade_id: String = ""

func setup(id: String) -> void:
	upgrade_id = id
	var data: Dictionary = UpgradeManager.UPGRADES[id]
	name_label.text = data["name"]
	var cost_text := "$%.0f" % data["cost"]
	if data.get("cost_type") == "per_credit":
		cost_text += "/credit"
	cost_label.text = cost_text
	_refresh_count()
	GameManager.cash_changed.connect(_on_cash_changed)
	_on_cash_changed(GameManager.cash)

func _refresh_count() -> void:
	var count := UpgradeManager.get_owned_count(upgrade_id)
	count_label.text = str(count) if count > 0 else ""

func _on_cash_changed(_cash: float) -> void:
	var cost: float = UpgradeManager.UPGRADES[upgrade_id]["cost"]
	buy_button.disabled = GameManager.cash < cost

func _on_buy_button_pressed() -> void:
	if UpgradeManager.try_purchase(upgrade_id):
		_refresh_count()
		emit_signal("pressed", upgrade_id)
