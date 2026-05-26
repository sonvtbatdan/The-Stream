extends Node

# ---------------------------------------------------------------------------
# Signals (existing — signatures and names locked)
# ---------------------------------------------------------------------------

signal views_changed(new_views: int)          # emits displayed_views (noisy)
signal subs_changed(new_subs: int)
signal cash_changed(new_cash: float)
signal stat_template_changed(template: String)

# New signal: the non-noisy view count, useful for stable internal logic
# (e.g. unlocks, milestone triggers) that shouldn't react to display jitter.
signal stable_views_changed(v: int)

# ---------------------------------------------------------------------------
# Tunable constants
# ---------------------------------------------------------------------------

# Sub growth coefficient. Sub gain per second = K_SUB * log_5(max(stable, 5)).
const K_SUB: float = 0.04
# Click contribution decay. exp(-CLICK_DECAY_RATE * t) → 0.01 after ~900s
# (a 15-minute "half-life-ish" so click bursts fade gracefully into stable).
const CLICK_DECAY_RATE: float = 0.00512
# Ornstein-Uhlenbeck noise on the displayed view count. INERTIA close to 1
# = strong mean reversion (smooth wandering); STEP is the per-tick gaussian
# standard deviation; CLAMP bounds the percentage fluctuation.
const NOISE_INERTIA: float = 0.99
const NOISE_STEP: float = 0.02
const NOISE_CLAMP: float = 0.5
# Donation amount distribution: bounded Pareto on [L, H].
const DONATION_L: float = 1.0
const DONATION_H: float = 1_000_000.0
# Donation income target: target_per_sec(subs) = C_CONST * subs^K_EXP.
const K_EXP: float = 0.663
const C_CONST: float = 0.0181

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

# Float accumulators so sub-integer changes don't get truncated each tick.
var _subs: float = 0.0
# Decaying contribution from recent clicks. Adds to stable view count.
var _click_contribution: float = 0.0
# OU noise term applied as a multiplicative factor on displayed_views.
var _noise: float = 0.0
# Cached bounded-Pareto shape parameter for the donation distribution.
# Recomputed lazily when _subs moves >10% from when it was last solved.
var _donation_alpha: float = 5.0
var _last_alpha_subs: float = -1.0

# Last emitted integer/float values so we only emit signals on change.
var _last_displayed_views_int: int = 0
var _last_stable_views_int: int = 0
var _last_subs_int: int = 0
var _last_cash_emitted: float = 0.0

# ---------------------------------------------------------------------------
# Public state
# ---------------------------------------------------------------------------

# Cash accumulates from Poisson donation events in _process. Modify via
# spend_cash() or the donation tick only; direct external mutation will still
# eventually trigger cash_changed via the next _emit_if_changed.
var cash: float = 0.0

# Per-click contribution added to _click_contribution. Future upgrades raise it.
var click_power: float = 1.0

# Placeholder multiplier referenced by the {parasocial} stat template token.
# Currently inert in the math; will be wired into sub growth by a future task.
var parasocial: float = 1.0

# Player-editable stat display template. The setter emits stat_template_changed
# so consumers (stat_panel.gd) can re-render. Locked per the rewrite spec.
var stat_template: String = "Views: {views}\nSubs: {subs}\nClick: x{click_power}":
	set(value):
		if stat_template == value:
			return
		stat_template = value
		stat_template_changed.emit(value)

# ---------------------------------------------------------------------------
# Public read-only getters
# ---------------------------------------------------------------------------

# Compatibility view: the same noisy displayed number old consumers already saw.
var views: int:
	get: return int(displayed_views)
var subs: int:
	get: return int(_subs)
# Non-noisy view total — _subs + decaying click contribution.
var stable_views: int:
	get: return int(_subs + _click_contribution)
# Noisy display value driven by the OU noise term.
var displayed_views: int:
	get: return int((_subs + _click_contribution) * (1.0 + _noise))

# ---------------------------------------------------------------------------
# Click handler (entry point name locked)
# ---------------------------------------------------------------------------

# Player clicked the on-screen view image. Adds click_power to the decaying
# click contribution; signal emission happens in _process on the next tick.
func on_view_clicked() -> void:
	_click_contribution += click_power

# ---------------------------------------------------------------------------
# Per-tick processing
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# 1. Click decay — exponential toward 0.
	if _click_contribution > 0.0:
		_click_contribution *= exp(-CLICK_DECAY_RATE * delta)
		if _click_contribution < 0.0001:
			_click_contribution = 0.0

	# 2. Sub growth — log-scaled in the stable (click-inclusive) view count.
	var stable: float = _subs + _click_contribution
	var sub_rate: float = K_SUB * (log(maxf(stable, 5.0)) / log(5.0))
	_subs += sub_rate * delta

	# 3. Noise — Ornstein-Uhlenbeck process drifting around 0, clamped.
	_noise = _noise * pow(NOISE_INERTIA, delta) + randfn(0.0, NOISE_STEP) * delta
	_noise = clampf(_noise, -NOISE_CLAMP, NOISE_CLAMP)

	# 4. Donation Poisson tick.
	_tick_donations(delta)

	# 5. Emit signals only when integer or cash values actually changed.
	_emit_if_changed()

# ---------------------------------------------------------------------------
# Bulk grants — kept for comment_panel.gd consumers
# ---------------------------------------------------------------------------

func add_bonus_subs(amount: int) -> void:
	if amount == 0:
		return
	_subs += float(amount)
	_invalidate_alpha_cache()
	_emit_if_changed()

func remove_subs(amount: int) -> void:
	if amount == 0:
		return
	_subs = maxf(0.0, _subs - float(amount))
	_invalidate_alpha_cache()
	_emit_if_changed()

# ---------------------------------------------------------------------------
# Donation logic
# ---------------------------------------------------------------------------

# Expected donation events per second at this sub count.
func _events_per_sec(s: float) -> float:
	return 0.1 * pow(maxf(s / 10.0, 1e-6), 0.4)

# Target $/sec at this sub count.
func _target_per_sec(s: float) -> float:
	return C_CONST * pow(maxf(s, 1.0), K_EXP)

# Bounded-Pareto mean E[X] for shape alpha on [L, H]. Uses the alpha→1 limit
# form to avoid the 0/0 case in the general formula.
func _pareto_mean(alpha: float, L: float, H: float) -> float:
	if absf(alpha - 1.0) < 0.001:
		return L * log(H / L) / (1.0 - L / H)
	var ratio: float = L / H
	return (alpha * L / (alpha - 1.0)) * (1.0 - pow(ratio, alpha - 1.0)) / (1.0 - pow(ratio, alpha))

# Pareto mean is monotonically decreasing in alpha on the bounded interval, so
# binary-search alpha to hit a target expected donation. 50 iterations on
# [0.1, 10.0] gives well under 1e-12 precision in alpha.
func _solve_alpha(target_mean: float) -> float:
	var lo: float = 0.1
	var hi: float = 10.0
	for i in 50:
		var mid: float = (lo + hi) * 0.5
		var m: float = _pareto_mean(mid, DONATION_L, DONATION_H)
		if m > target_mean:
			# Mean too big → need steeper distribution → higher alpha.
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

# Recompute _donation_alpha if subs moved >10% from the last solve, or if the
# cache was explicitly invalidated.
func _ensure_alpha_fresh() -> void:
	var stale: bool = _last_alpha_subs < 0.0
	if not stale and _last_alpha_subs > 0.0:
		stale = absf(_subs - _last_alpha_subs) / _last_alpha_subs > 0.1
	if not stale:
		return
	var rate: float = _events_per_sec(_subs)
	if rate <= 0.0:
		return
	var target_mean: float = _target_per_sec(_subs) / rate
	_donation_alpha = _solve_alpha(target_mean)
	_last_alpha_subs = _subs

func _invalidate_alpha_cache() -> void:
	_last_alpha_subs = -1.0

# Inverse-CDF sample from bounded Pareto[DONATION_L, DONATION_H, alpha].
func _sample_donation() -> int:
	var u: float = randf()
	var ratio_alpha: float = pow(DONATION_L / DONATION_H, _donation_alpha)
	var x: float = DONATION_L * pow(1.0 - u * (1.0 - ratio_alpha), -1.0 / _donation_alpha)
	return clampi(int(round(x)), 1, int(DONATION_H))

# Sample a count from a Poisson distribution with given rate (events per tick).
# Knuth's multiplicative algorithm is fast for small rates; for rate >= 30 the
# normal approximation N(rate, sqrt(rate)) is both faster and accurate.
func _poisson_sample(rate: float) -> int:
	if rate <= 0.0:
		return 0
	if rate >= 30.0:
		return maxi(0, int(round(randfn(rate, sqrt(rate)))))
	var L: float = exp(-rate)
	var k: int = 0
	var p: float = 1.0
	while true:
		k += 1
		p *= randf()
		if p < L:
			return k - 1
	return k - 1  # unreachable

# Sample n donations this tick and credit them to cash.
func _tick_donations(delta: float) -> void:
	var rate: float = _events_per_sec(_subs) * delta
	if rate <= 0.0:
		return
	var n_events: int = _poisson_sample(rate)
	if n_events <= 0:
		return
	_ensure_alpha_fresh()
	var total: float = 0.0
	for i in n_events:
		total += float(_sample_donation())
	if total > 0.0:
		cash += total

# ---------------------------------------------------------------------------
# Signal emission guard
# ---------------------------------------------------------------------------

func _emit_if_changed() -> void:
	var dv := displayed_views
	if dv != _last_displayed_views_int:
		_last_displayed_views_int = dv
		views_changed.emit(dv)
	var sv := stable_views
	if sv != _last_stable_views_int:
		_last_stable_views_int = sv
		stable_views_changed.emit(sv)
	var s := subs
	if s != _last_subs_int:
		_last_subs_int = s
		subs_changed.emit(s)
	if absf(cash - _last_cash_emitted) > 0.0001:
		_last_cash_emitted = cash
		cash_changed.emit(cash)

# ---------------------------------------------------------------------------
# Inspection helpers — for future UI / debug overlays
# ---------------------------------------------------------------------------

func get_vps_estimate() -> float:
	return K_SUB * (log(maxf(_subs + _click_contribution, 5.0)) / log(5.0))

func get_donation_rate_estimate() -> float:
	return C_CONST * pow(maxf(_subs, 1.0), K_EXP)

# ---------------------------------------------------------------------------
# Stat template renderer (signature locked)
# ---------------------------------------------------------------------------

func render_stat_template() -> String:
	return stat_template \
		.replace("{views}", str(views)) \
		.replace("{subs}", str(subs)) \
		.replace("{click_power}", str(click_power)) \
		.replace("{parasocial}", str(parasocial)) \
		.replace("{cash}", str(int(cash))) \
		.replace("{goal}", str(current_goal)) \
		.replace("{run}", str(run)) \
		.replace("{time}", get_time_string())

# ---------------------------------------------------------------------------
# Legacy compatibility shims
#
# Still required by the old HUD scripts (stat_panel.gd template placeholders,
# comment_panel.gd, upgrade_item.gd) and upgrade_manager.gd. spend_cash() is
# now backed by the real cash field so old upgrade purchases actually deduct
# money (their effects remain no-ops until parasocial multipliers and upgrade
# wiring land in the next task). Delete this block once those scripts/scenes
# are removed or ported.
# ---------------------------------------------------------------------------

var current_goal: int = 100
var run: int = 1

func get_time_string() -> String:
	return "00:00"

func spend_cash(amount: float) -> bool:
	if cash < amount:
		return false
	cash -= amount
	return true

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
