extends Node

signal purchased(id: String)
signal order_changed

# Round-end upgrade catalog. Each entry has:
#   name   — display name shown on the buy card
#   cost   — gold cost (GameManager.gold)
#   params — gameplay tuning numbers. Edit these to balance.
#   desc   — display template; {placeholders} are filled from params at render time.
# Effect logic lives in StreamArena — this file owns data only.
const CATALOG := {
	"auto_lazer": {
		"name": "Auto Lazer",
		"cost": 5,
		"desc": "Zap the nearest drifter every {cooldown}s with a lightning arc.",
		"params": {
			"cooldown": 1,
		},
	},
	"nova": {
		"name": "Nova",
		"cost": 5,
		"desc": "Every {cooldown}s, blast a {radius}px electric wave that evaporates everything inside it.",
		"params": {
			"cooldown": 5.0,
			"radius": 300.0,
		},
	},
	"echo": {
		"name": "Echo",
		"cost": 5,
		"desc": "Each click-destroyed drifter drops a {duration}s, {radius}px-radius residual zone. Drifters with >={overlap_trigger_pct}% area overlap evaporate.",
		"params": {
			"duration": 1.0,
			"radius": 50.0,
			# 0.20 = 20% area overlap of a drifter with the zone triggers destruction.
			"overlap_trigger": 0.20,
		},
	},
}

var _owned: Dictionary = {}

# Owned tool ids in slot order. Mutated by try_purchase (append) and
# swap_slots (drag-reorder). The pad reads this to populate cells.
var _order: Array[String] = []

# Per-tool cooldown timers. Keys are tool ids; values are dicts of
# {remaining: float, total: float}. Absent ids are treated as ready (progress 0).
# Populated by start_cooldown, ticked in _process, removed when remaining <= 0.
var _cooldowns: Dictionary = {}

func is_owned(id: String) -> bool:
	return _owned.get(id, false)

func get_cost(id: String) -> int:
	if not CATALOG.has(id):
		return 0
	return int(CATALOG[id]["cost"])

# Read a tuning number. Returns `default` if the id or param name is missing.
func get_param(id: String, param_name: String, default: Variant = null) -> Variant:
	if not CATALOG.has(id):
		return default
	var params: Dictionary = CATALOG[id].get("params", {})
	return params.get(param_name, default)

# Returns the description with all {placeholders} substituted from the params dict.
# Also exposes `overlap_trigger_pct` as a convenience integer percent for desc strings.
func get_desc(id: String) -> String:
	if not CATALOG.has(id):
		return ""
	var template: String = CATALOG[id].get("desc", "")
	var params: Dictionary = CATALOG[id].get("params", {}).duplicate()
	if params.has("overlap_trigger"):
		params["overlap_trigger_pct"] = int(round(float(params["overlap_trigger"]) * 100.0))
	return template.format(params)

func try_purchase(id: String) -> bool:
	if not CATALOG.has(id):
		return false
	if is_owned(id):
		return false
	if not GameManager.spend_gold(get_cost(id)):
		return false
	_owned[id] = true
	_order.append(id)
	emit_signal("purchased", id)
	return true

func reset() -> void:
	_owned.clear()
	_order.clear()
	_cooldowns.clear()

func get_order() -> Array[String]:
	return _order.duplicate()

func start_cooldown(id: String, duration: float) -> void:
	if duration <= 0.0:
		return  # treat as "no cooldown"; caller should not pass zero
	_cooldowns[id] = {"remaining": duration, "total": duration}

func get_cooldown_progress(id: String) -> float:
	var entry: Dictionary = _cooldowns.get(id, {})
	if entry.is_empty():
		return 0.0
	var total: float = float(entry.get("total", 0.0))
	if total <= 0.0:
		return 0.0
	return clampf(float(entry.get("remaining", 0.0)) / total, 0.0, 1.0)

func swap_slots(i: int, j: int) -> void:
	if i == j:
		return
	if i < 0 or j < 0 or i >= _order.size() or j >= _order.size():
		return
	var tmp: String = _order[i]
	_order[i] = _order[j]
	_order[j] = tmp
	emit_signal("order_changed")

func _process(delta: float) -> void:
	if GameManager.paused:
		return
	if _cooldowns.is_empty():
		return
	# Snapshot keys so erasing entries during iteration is safe; entry is a
	# reference into _cooldowns[id], so mutating it updates the dict in place.
	for id: String in _cooldowns.keys():
		var entry: Dictionary = _cooldowns[id]
		var remaining: float = float(entry["remaining"]) - delta
		if remaining <= 0.0:
			_cooldowns.erase(id)
		else:
			entry["remaining"] = remaining
