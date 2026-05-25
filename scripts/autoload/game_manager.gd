extends Node

signal views_changed(new_views: int)
signal subs_changed(new_subs: int)

# Internal storage is float so passive sub growth can accumulate fractionally
# below 1 sub/sec without ever appearing to "tick" at integer-only resolution.
# Signals still emit ints so existing label code (str(v) on the signal arg)
# is unchanged.
var _views: float = 0.0
var _subs: float = 0.0
var _last_views_int: int = 0
var _last_subs_int: int = 0

var views: int:
	get: return int(_views)
var subs: int:
	get: return int(_subs)

# Per-click view yield. Increased by future upgrades.
var click_power: float = 1.0

# Multiplier on the passive sub-growth rate. Future upgrades raise this.
var parasocial: float = 1.0

func _process(delta: float) -> void:
	# Log-scaled passive sub growth so the rate doesn't explode at very high
	# view counts. Calibration points:
	#   100 views  → ~0.05 subs/sec  (1 sub every ~20s)
	#   10k views  → ~0.20 subs/sec  (1 sub every ~5s)
	#   1M views   → ~0.60 subs/sec
	var sub_rate: float = 0.05 * log(maxf(_views, 1.0)) / log(10.0) * parasocial
	_subs += sub_rate * delta
	_emit_if_changed()

# Player clicked the on-screen view image. Single source of click-reward truth.
func on_view_clicked() -> void:
	_views += click_power
	_emit_if_changed()

# Bulk view adds (e.g. arena drifters destroyed by the streamer pad). Kept as
# a public method so callers other than the click handler can still grant views.
func add_views(amount: int) -> void:
	if amount == 0:
		return
	_views += float(amount)
	_emit_if_changed()

# Event-driven sub gain (e.g. LIKE drifter destroyed). Bypasses the log-rate
# accumulator so the gain is immediate and visible.
func add_bonus_subs(amount: int) -> void:
	if amount == 0:
		return
	_subs += float(amount)
	_emit_if_changed()

func _emit_if_changed() -> void:
	var vi := int(_views)
	var si := int(_subs)
	if vi != _last_views_int:
		_last_views_int = vi
		views_changed.emit(vi)
	if si != _last_subs_int:
		_last_subs_int = si
		subs_changed.emit(si)


# ---------------------------------------------------------------------------
# Legacy compatibility shims — inert no-ops that keep the old HUD scripts
# (stat_panel.gd, comment_panel.gd, upgrade_item.gd) and upgrade_manager.gd
# from crashing at load time. These are dead-code references in scripts that
# main.tscn still instances; remove this whole block once those scripts/scenes
# are deleted or ported to the new GameManager API.
# ---------------------------------------------------------------------------

signal cash_changed(new_cash: float)

var cash: float = 0.0
var current_goal: int = 100
var run: int = 1

func get_time_string() -> String:
	return "00:00"

func spend_cash(_amount: float) -> bool:
	return false

func add_non_bot_vps(_amount: float) -> void:
	pass

func add_bot_vps(_amount: float) -> void:
	pass

func apply_view_multiplier(_pct: float) -> void:
	pass

func apply_boost(_pct: float, _duration: float) -> void:
	pass

func add_bot_efficiency(_extra: float) -> void:
	pass

func remove_subs(_amount: int) -> void:
	pass
