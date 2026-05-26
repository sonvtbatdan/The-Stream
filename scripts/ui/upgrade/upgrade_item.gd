extends Button

signal pressed_id(upgrade_id: String)

@onready var name_label: Label = %NameLabel
@onready var price_label: Label = %PriceLabel
@onready var desc_label: Label = %DescLabel
@onready var count_label: Label = %CountLabel

var upgrade_id: String = ""

func setup(id: String) -> void:
	upgrade_id = id
	var data: Dictionary = UpgradeManager.UPGRADES[id]
	name_label.text = data["name"]
	desc_label.text = String(data.get("desc", ""))
	# Affordability re-check on the non-noisy stable view total so the row
	# doesn't flicker enabled/disabled with the displayed counter's jitter.
	GameManager.stable_views_changed.connect(_on_stable_views_changed)
	pressed.connect(_on_pressed)
	_refresh_state()

# Single source of truth for the row's price label, count label, and disabled
# / dim state. Called on setup, on every affordability change, and after each
# successful purchase (which bumps both the count and the next price).
func _refresh_state() -> void:
	var price: int = UpgradeManager.get_current_price(upgrade_id)
	var cost_text := GameManager.format_count(price) + " views"
	if UpgradeManager.UPGRADES[upgrade_id].get("cost_type") == "per_credit":
		cost_text += "/credit"
	price_label.text = cost_text

	var count: int = UpgradeManager.get_owned_count(upgrade_id)
	count_label.text = "x%d" % count if count > 0 else ""

	var can_afford: bool = GameManager.stable_views >= price
	disabled = not can_afford
	# modulate cascades to children so the labels dim alongside the Button.
	modulate = Color.WHITE if can_afford else Color(0.5, 0.5, 0.5, 1.0)

func _on_stable_views_changed(_v: int) -> void:
	_refresh_state()

func _on_pressed() -> void:
	# DIAGNOSTIC — remove after click-doesn't-buy bug is identified.
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
