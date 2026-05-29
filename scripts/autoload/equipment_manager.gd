extends Node

signal item_purchased(id: String)
signal items_reset

const SAVE_PATH := "user://equipment.cfg"
const FOLDER    := "res://assets/upgrades/equipment/"

# id -> {name, icon, cost, owned}
var ITEMS: Dictionary = {}

func _ready() -> void:
	_scan_folder()
	_load_save()

func _scan_folder() -> void:
	var dir := DirAccess.open(FOLDER)
	if dir == null:
		return
	dir.list_dir_begin()
	var idx := 0
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir():
			var ext := file.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "webp"]:
				var id := file.get_basename().to_lower()
				ITEMS[id] = {
					"name":  _format_name(file.get_basename()),
					"icon":  file,
					"cost":  _default_cost(idx),
					"owned": 0,
				}
				idx += 1
		file = dir.get_next()
	dir.list_dir_end()

func _format_name(stem: String) -> String:
	if stem.is_empty():
		return stem
	# Insert space at every digit↔letter boundary
	var spaced := ""
	for i in stem.length():
		var c := stem[i]
		if i > 0:
			var p := stem[i - 1]
			var c_dig := (c >= "0" and c <= "9")
			var p_dig := (p >= "0" and p <= "9")
			if c_dig != p_dig:
				spaced += " "
		spaced += c
	# Capitalize first letter of each word
	var result := ""
	for word in spaced.split(" "):
		if word.is_empty():
			continue
		if result != "":
			result += " "
		result += word.substr(0, 1).to_upper() + word.substr(1)
	return result

func _default_cost(index: int) -> float:
	return roundf(20.0 * pow(1.6, float(index)))

func try_purchase(id: String) -> bool:
	if not ITEMS.has(id):
		return false
	if int(ITEMS[id]["owned"]) >= 1:
		return false
	var cost := float(ITEMS[id]["cost"])
	if not GameManager.spend_cash(cost):
		return false
	ITEMS[id]["owned"] = 1
	_save()
	item_purchased.emit(id)
	return true

func get_owned(id: String) -> int:
	return int(ITEMS.get(id, {}).get("owned", 0))

func reset_all() -> void:
	for id in ITEMS:
		ITEMS[id]["owned"] = 0
	_save()
	items_reset.emit()

func _save() -> void:
	var cfg := ConfigFile.new()
	for id in ITEMS:
		cfg.set_value("owned", id, ITEMS[id]["owned"])
	cfg.save(SAVE_PATH)

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for id in ITEMS:
		ITEMS[id]["owned"] = cfg.get_value("owned", id, 0)
