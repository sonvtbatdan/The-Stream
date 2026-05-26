extends Button

signal pressed_id(upgrade_id: String)

# Placeholder one-liners per tool id — short enough to fit a single row at the
# default ToolsColumn width. Real copy from the user replaces these later.
const PLACEHOLDER_DESCS := {
	"fanreact":   "Friends boost engagement.",
	"fanview":    "Friends watch idly.",
	"botreact":   "Bots spam reactions.",
	"botview":    "Bots pad your viewers.",
	"algorimth":  "Algorithm boosts reach.",
	"ad":         "Buy a brief view spike.",
	"botupgrade": "Smarter bots, more views.",
}

@onready var name_label: Label = %NameLabel
@onready var price_label: Label = %PriceLabel
@onready var desc_label: Label = %DescLabel
@onready var count_label: Label = %CountLabel

var upgrade_id: String = ""

func setup(id: String) -> void:
	upgrade_id = id
	var data: Dictionary = UpgradeManager.UPGRADES[id]
	name_label.text = data["name"]
	desc_label.text = PLACEHOLDER_DESCS.get(id, "Placeholder description.")
	_refresh_price()
	_refresh_count()
	# Affordability re-check on the non-noisy stable view total so the row
	# doesn't flicker enabled/disabled with the displayed counter's jitter.
	GameManager.stable_views_changed.connect(_on_stable_views_changed)
	_on_stable_views_changed(GameManager.stable_views)
	pressed.connect(_on_pressed)

func _refresh_price() -> void:
	var data: Dictionary = UpgradeManager.UPGRADES[upgrade_id]
	var cost_text := "%d views" % int(data["cost"])
	if data.get("cost_type") == "per_credit":
		cost_text += "/credit"
	price_label.text = cost_text

func _refresh_count() -> void:
	var count := UpgradeManager.get_owned_count(upgrade_id)
	count_label.text = "x%d" % count if count > 0 else ""

func _on_stable_views_changed(_v: int) -> void:
	var cost: int = int(UpgradeManager.UPGRADES[upgrade_id]["cost"])
	var can_afford: bool = GameManager.stable_views >= cost
	disabled = not can_afford
	# modulate cascades to all children, so the labels dim alongside the
	# Button's own rendering — gives the whole row a uniform grayed-out look.
	modulate = Color.WHITE if can_afford else Color(0.5, 0.5, 0.5, 1.0)

func _on_pressed() -> void:
	if UpgradeManager.try_purchase(upgrade_id):
		_refresh_count()
		_refresh_price()
		pressed_id.emit(upgrade_id)
