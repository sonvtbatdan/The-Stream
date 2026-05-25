extends Node

signal views_changed(new_views: int)
signal subs_changed(new_subs: int)
signal eye_hp_changed(new_hp: int)
signal run_reset(new_run: int)
signal round_advanced(new_round: int)
signal gold_changed(new_gold: int)

const EYE_MAX_HP := 100
const ROUND_DURATION := 30.0
const GOLD_PER_ROUND := 5

var views: int = 0
var subs: int = 0
var run: int = 1
var elapsed_time: float = 0.0
var eye_hp: int = EYE_MAX_HP
var current_round: int = 1
var round_timer: float = 0.0
var gold: int = 0
# When true, _process is a no-op — freezes elapsed_time, round timer, and
# passive view generation. Toggled by StreamArena.set_paused().
var paused: bool = false

var _fractional_views: float = 0.0

# Passive view generation: subs become VPS directly. Upgrades that multiply
# this can be reintroduced later if needed.
var views_per_second: float:
	get: return float(subs)

func _process(delta: float) -> void:
	if paused:
		return
	elapsed_time += delta
	_tick_passive_views(delta)
	_tick_round(delta)

func _tick_round(delta: float) -> void:
	round_timer += delta
	if round_timer >= ROUND_DURATION:
		round_timer -= ROUND_DURATION
		current_round += 1
		add_gold(GOLD_PER_ROUND)
		emit_signal("round_advanced", current_round)

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

func add_bonus_subs(amount: int) -> void:
	subs += amount
	emit_signal("subs_changed", subs)

func remove_subs(amount: int) -> void:
	subs = maxi(0, subs - amount)
	emit_signal("subs_changed", subs)

func add_gold(amount: int) -> void:
	gold += amount
	emit_signal("gold_changed", gold)

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	emit_signal("gold_changed", gold)
	return true

func damage_eye(amount: int) -> void:
	eye_hp = maxi(0, eye_hp - amount)
	emit_signal("eye_hp_changed", eye_hp)
	if eye_hp <= 0:
		reset_run()

func heal_eye(amount: int) -> void:
	eye_hp = mini(EYE_MAX_HP, eye_hp + amount)
	emit_signal("eye_hp_changed", eye_hp)

func reset_run() -> void:
	run += 1
	views = 0
	subs = 0
	eye_hp = EYE_MAX_HP
	_fractional_views = 0.0
	current_round = 1
	round_timer = 0.0
	gold = 0
	emit_signal("views_changed", views)
	emit_signal("subs_changed", subs)
	emit_signal("eye_hp_changed", eye_hp)
	emit_signal("gold_changed", gold)
	emit_signal("run_reset", run)
	emit_signal("round_advanced", current_round)

func get_time_string() -> String:
	var minutes := int(elapsed_time) / 60
	var seconds := int(elapsed_time) % 60
	return "%02d:%02d" % [minutes, seconds]
