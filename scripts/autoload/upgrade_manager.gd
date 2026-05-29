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
	# ---- VIEW tab ----
	"autoclicker": {
		"name": "Auto-clicker",
		"icon": "autoclicker.png",
		"cost": 10.0,
		"tab": "view",
		"auto_click_rate": 1.0,
		"desc": "Can't be clicking all the time."
	},
	"fanclub": {
		"name": "Fanclub",
		"icon": "Fan.png",
		"cost": 200.0,
		"tab": "view",
		"vps": 5.0,
		"desc": "The love of the fan is why I am doing this (not for money of course)."
	},
	"collaborators": {
		"name": "Collaborators",
		"icon": "collab.png",
		"cost": 4000.0,
		"tab": "view",
		"vps": 40.0,
		"desc": "Tell your men that they work for me now."
	},
	"publishers": {
		"name": "Publishers",
		"icon": "Publisher.png",
		"cost": 80000.0,
		"tab": "view",
		"vps": 287.0,
		"desc": "Can't get enough of your face."
	},
	"trojan": {
		"name": "Trojan",
		"icon": "Troy.png",
		"cost": 1600000.0,
		"tab": "view",
		"vps": 2016.0,
		"desc": "Run the stream in the background of all infected computers."
	},
	"satellite": {
		"name": "Satellite",
		"icon": "satellite.png",
		"cost": 32000000.0,
		"tab": "view",
		"vps": 14117.0,
		"desc": "Replace mainstream media with yourstream media."
	},
	"concentration_camp": {
		"name": "Concentration camp",
		"icon": "camp.png",
		"cost": 640000000.0,
		"tab": "view",
		"vps": 98824.0,
		"desc": "There is nothing but the stream."
	},
	"animal_translator": {
		"name": "Animal-Language-Translator-inator",
		"icon": "Animal.png",
		"cost": 12800000000.0,
		"tab": "view",
		"vps": 691775.0,
		"desc": "Intelligent or not, they are watching the stream."
	},
	"the_vats": {
		"name": "The vats",
		"icon": "vats.png",
		"cost": 256000000000.0,
		"tab": "view",
		"vps": 4842432.0,
		"desc": "Content-consumer creator."
	},
	# ---- COMMENT tab ----
	"comment_react": {
		"name": "Comment React",
		"icon": "comment_react.png",
		"cost": 100.0,
		"tab": "comment",
		"comment_click_rate": 1.0,
		"desc": "An agency who reacts for you."
	},
	"reaction_bot": {
		"name": "Reaction Bot",
		"icon": "reaction_bot.png",
		"cost": 500.0,
		"tab": "comment",
		"comment_click_rate": 5.0,
		"desc": "Write a script for react."
	},
	"reaction_machine": {
		"name": "Reaction Machine",
		"icon": "reaction_machine.png",
		"cost": 10000.0,
		"tab": "comment",
		"comment_click_rate": 50.0,
		"desc": "A machine full of bots."
	},
	"reaction_farm": {
		"name": "Reaction Farm",
		"icon": "reaction_farm.png",
		"cost": 50000.0,
		"tab": "comment",
		"comment_click_rate": 200.0,
		"desc": "A farm of react machines."
	},
	"reaction_factory": {
		"name": "Reaction Factory",
		"icon": "reaction_factory.png",
		"cost": 500000.0,
		"tab": "comment",
		"factory": true,
		"desc": "Produce reaction machine: +1 machine every 5 seconds."
	},
	"reaction_industry": {
		"name": "Reaction Industry",
		"icon": "reaction_industry.png",
		"cost": 2000000.0,
		"tab": "comment",
		"comment_click_rate": 1000.0,
		"desc": "Hire an industrial park to place factories."
	},
	"reaction_economic_zone": {
		"name": "Reaction Economic Zone",
		"icon": "reaction_economic_zone.png",
		"cost": 5000000.0,
		"tab": "comment",
		"comment_click_rate": 3000.0,
		"desc": "There is an ecosystem."
	},
}

const PRICE_SCALE := 1.15   # each new unit costs 15% more than the previous

# Reaction Factory state: virtual machines produced over time.
var _virtual_machines: int = 0
var _factory_acc: float    = 0.0

func _process(delta: float) -> void:
	var factories: int = get_owned_count("reaction_factory")
	if factories <= 0:
		return
	_factory_acc += delta * float(factories)
	while _factory_acc >= 5.0:
		_factory_acc -= 5.0
		_virtual_machines += 1
		GameManager.comment_auto_click_rate += float(UPGRADES["reaction_machine"]["comment_click_rate"])

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
	if data.has("comment_click_rate"):
		GameManager.comment_auto_click_rate += float(data["comment_click_rate"])

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

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

const SAVE_PATH := "user://upgrades_save.cfg"

func save_game() -> void:
	var cfg := ConfigFile.new()
	for id in owned:
		cfg.set_value("owned", id, owned[id])
	cfg.set_value("factory", "virtual_machines", _virtual_machines)
	cfg.save(SAVE_PATH)

func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	# Reset derived GameManager stats so re-applying upgrades doesn't double them.
	GameManager.vps                    = 0.0
	GameManager.auto_click_rate        = 0.0
	GameManager.comment_auto_click_rate = 0.0
	_virtual_machines = cfg.get_value("factory", "virtual_machines", 0)
	_factory_acc = 0.0
	owned.clear()
	if not cfg.has_section("owned"):
		return
	for key in cfg.get_section_keys("owned"):
		var count: int = cfg.get_value("owned", key, 0)
		if count > 0 and UPGRADES.has(key):
			owned[key] = count
			for _i in count:
				_apply_upgrade(UPGRADES[key])
	# Re-apply accumulated virtual machines from factories.
	GameManager.comment_auto_click_rate += float(_virtual_machines) * float(UPGRADES["reaction_machine"]["comment_click_rate"])
