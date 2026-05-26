extends Node

signal upgrade_purchased(upgrade_id: String)

var owned: Dictionary = {}

const UPGRADES := {
	"fanreact":   { "name": "Fan React",      "cost": 5.0,     "non_bot_vps": 1.0,                           "desc": "Permanently increases your view count by 1 view per second." },
	"fanview":    { "name": "Fan View",       "cost": 10.0,    "non_bot_vps": 5.0,                           "desc": "Permanently increases your view count by 5 views per second." },
	"botreact":   { "name": "Bot React",      "cost": 100.0,   "bot_vps": 50.0,                              "desc": "Permanently increases your view count by 50 views per second." },
	"botview":    { "name": "Bot View",       "cost": 500.0,   "bot_vps": 200.0,                             "desc": "Permanently increases your view count by 200 views per second." },
	"algorimth":  { "name": "Algorithm",      "cost": 5000.0,  "view_mult_bonus": 0.02,                      "desc": "Permanently increases your total view generation by 2%." },
	"ad":         { "name": "Advertisement",  "cost": 1000.0,  "boost_pct": 0.10, "boost_duration": 30.0,   "desc": "Temporarily boosts your total view generation by 10% for 30 seconds." },
	"botupgrade": { "name": "Bot Upgrade",    "cost": 10000.0, "bot_efficiency_bonus": 0.05,                 "desc": "Permanently increases the efficiency of Bot React and Bot View by 5%." },
}

func try_purchase(upgrade_id: String) -> bool:
	if not UPGRADES.has(upgrade_id):
		return false
	var data: Dictionary = UPGRADES[upgrade_id]
	if not GameManager.spend_views(int(data["cost"])):
		return false
	owned[upgrade_id] = owned.get(upgrade_id, 0) + 1
	_apply_upgrade(data)
	emit_signal("upgrade_purchased", upgrade_id)
	return true

func _apply_upgrade(data: Dictionary) -> void:
	if data.has("non_bot_vps"):
		GameManager.add_non_bot_vps(data["non_bot_vps"])
	if data.has("bot_vps"):
		GameManager.add_bot_vps(data["bot_vps"])
	if data.has("view_mult_bonus"):
		GameManager.apply_view_multiplier(data["view_mult_bonus"])
	if data.has("boost_pct"):
		GameManager.apply_boost(data["boost_pct"], data["boost_duration"])
	if data.has("bot_efficiency_bonus"):
		GameManager.add_bot_efficiency(data["bot_efficiency_bonus"])

func get_owned_count(upgrade_id: String) -> int:
	return owned.get(upgrade_id, 0)

func can_afford(upgrade_id: String) -> bool:
	if not UPGRADES.has(upgrade_id):
		return false
	return GameManager.stable_views >= int(UPGRADES[upgrade_id]["cost"])

func get_price(upgrade_id: String) -> float:
	if not UPGRADES.has(upgrade_id):
		return 0.0
	return UPGRADES[upgrade_id]["cost"]
