extends Node

signal views_changed(new_views: int)
signal subs_changed(new_subs: int)
signal cash_changed(new_cash: float)
signal goal_reached(goal: int)

var views: int = 0
var subs: int = 0
var cash: float = 1000.0
var run: int = 1
var elapsed_time: float = 0.0
var current_goal: int = 100

# Passive view generation components (tracked separately for botupgrade)
var _non_bot_vps: float = 1.0
var _bot_base_vps: float = 0.0
var _bot_efficiency: float = 1.0
var _view_mult: float = 1.0
var _boost_mult: float = 1.0
var _boost_timer: float = 0.0
var _fractional_views: float = 0.0

var cash_per_view: float = 0.01  # 100 views = $1

var views_per_second: float:
	get: return (_non_bot_vps + _bot_base_vps * _bot_efficiency) * _view_mult * _boost_mult

func _process(delta: float) -> void:
	elapsed_time += delta
	if _boost_timer > 0.0:
		_boost_timer = maxf(0.0, _boost_timer - delta)
		if _boost_timer == 0.0:
			_boost_mult = 1.0
	_tick_passive_views(delta)

func _tick_passive_views(delta: float) -> void:
	var vps := views_per_second
	if vps > 0.0:
		_fractional_views += vps * delta
		var gained := int(_fractional_views)
		if gained > 0:
			_fractional_views -= float(gained)
			add_views(gained)

func add_views(amount: int) -> void:
	views += amount
	emit_signal("views_changed", views)
	add_cash(float(amount) * cash_per_view)
	var new_sub_total := views / 5
	if new_sub_total > subs:
		subs = new_sub_total
		emit_signal("subs_changed", subs)
	if views >= current_goal:
		emit_signal("goal_reached", current_goal)

func add_cash(amount: float) -> void:
	cash += amount
	emit_signal("cash_changed", cash)

func spend_cash(amount: float) -> bool:
	if cash < amount:
		return false
	cash -= amount
	emit_signal("cash_changed", cash)
	return true

func add_bonus_subs(amount: int) -> void:
	subs += amount
	emit_signal("subs_changed", subs)

func remove_subs(amount: int) -> void:
	subs = maxi(0, subs - amount)
	emit_signal("subs_changed", subs)

func add_non_bot_vps(amount: float) -> void:
	_non_bot_vps += amount

func add_bot_vps(amount: float) -> void:
	_bot_base_vps += amount

func add_bot_efficiency(extra: float) -> void:
	_bot_efficiency += extra

func apply_view_multiplier(pct: float) -> void:
	_view_mult *= (1.0 + pct)

func apply_boost(pct: float, duration: float) -> void:
	_boost_mult = 1.0 + pct
	_boost_timer = duration

func get_time_string() -> String:
	var minutes := int(elapsed_time) / 60
	var seconds := int(elapsed_time) % 60
	return "%02d:%02d" % [minutes, seconds]
