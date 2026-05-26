extends Node

signal upgrade_purchased(upgrade_id: String)

var owned: Dictionary = {}

# Tools the player can buy with views. Each entry has:
#   name — display name shown in the ToolsColumn
#   cost — base view price (n-th unit costs ceil(cost * PRICE_SCALE^(n-1)))
#   desc — short flavor line shown beneath the name
#   vps  — views per second added per owned unit (omit for non-VPS tools)
#   auto_click_rate — auto-clicks per second per owned unit (each tick adds
#                     click_power views). Omit unless this is an auto-clicker.
const UPGRADES := {
	"autoclicker": {
		"name": "Auto-clicker",
		"cost": 10.0,
		"auto_click_rate": 1.0,
		"desc": "Can't be clicking all the time."
	},
	"fanclub": {
		"name": "Fanclub",
		"cost": 200.0,
		"vps": 5.0,
		"desc": "The love of the fan is why I am doing this (not for money of course)."
	},
	"collaborators": {
		"name": "Collaborators",
		"cost": 4000.0,
		"vps": 40.0,
		"desc": "Tell your men that they work for me now."
	},
	"publishers": {
		"name": "Publishers",
		"cost": 80000.0,
		"vps": 287.0,
		"desc": "Can't get enough of your face."
	},
	"trojan": {
		"name": "Trojan",
		"cost": 1600000.0,
		"vps": 2016.0,
		"desc": "Run the stream in the background of all infected computers."
	},
	"satellite": {
		"name": "Satellite",
		"cost": 32000000.0,
		"vps": 14117.0,
		"desc": "Replace mainstream media with yourstream media."
	},
	"concentration_camp": {
		"name": "Concentration camp",
		"cost": 640000000.0,
		"vps": 98824.0,
		"desc": "There is nothing but the stream."
	},
	"animal_translator": {
		"name": "Animal-Language-Translator-inator",
		"cost": 12800000000.0,
		"vps": 691775.0,
		"desc": "Intelligent or not, they are watching the stream."
	},
	"the_vats": {
		"name": "The vats",
		"cost": 256000000000.0,
		"vps": 4842432.0,
		"desc": "Content-consumer creator."
	},
}

const PRICE_SCALE := 1.15   # each new unit costs 15% more than the previous

func try_purchase(upgrade_id: String) -> bool:
	if not UPGRADES.has(upgrade_id):
		return false
	var data: Dictionary = UPGRADES[upgrade_id]
	if not GameManager.spend_views(get_current_price(upgrade_id)):
		return false
	owned[upgrade_id] = owned.get(upgrade_id, 0) + 1
	_apply_upgrade(data)
	emit_signal("upgrade_purchased", upgrade_id)
	return true

# Cost of the next purchase: baseprice * 1.15^(units_already_owned).
# Owning 0 units → first unit at baseprice; owning 1 → next at baseprice*1.15.
func get_current_price(upgrade_id: String) -> int:
	if not UPGRADES.has(upgrade_id):
		return 0
	var base: float = float(UPGRADES[upgrade_id]["cost"])
	var n: int = get_owned_count(upgrade_id)
	return int(ceil(base * pow(PRICE_SCALE, n)))

func _apply_upgrade(data: Dictionary) -> void:
	if data.has("vps"):
		GameManager.vps += float(data["vps"])
	if data.has("auto_click_rate"):
		GameManager.auto_click_rate += float(data["auto_click_rate"])

func get_owned_count(upgrade_id: String) -> int:
	return owned.get(upgrade_id, 0)

func can_afford(upgrade_id: String) -> bool:
	if not UPGRADES.has(upgrade_id):
		return false
	return GameManager.stable_views >= get_current_price(upgrade_id)

func get_price(upgrade_id: String) -> float:
	if not UPGRADES.has(upgrade_id):
		return 0.0
	return UPGRADES[upgrade_id]["cost"]
