extends Control

const EYE_TEX_PATH      := "res://assets/screen/eye.png"
const LIKE_TEX_PATH     := "res://assets/screen/like.png"
const DISLIKE_TEX_PATH  := "res://assets/screen/dislike.png"
const VIEW_TEX_PATH     := "res://assets/screen/viewer.png"

const EYE_SIZE          := Vector2(56.0, 56.0)   # 40% of original 140
const HPBAR_SIZE        := Vector2(60.0, 6.0)
const HPBAR_GAP         := 6.0   # pixels above the eye
const VIEW_LABEL_BOTTOM_GAP := 24.0
const VIEW_LABEL_FONT   := 36

const DRIFTER_SIZE      := Vector2(80.0, 80.0)
const BASE_DRIFTER_SPEED := 150.0
const DRIFTER_EDGE_MARGIN := 40.0  # spawn just outside the visible arena rect
const BASE_SPAWN_INTERVAL := 0.6
# Per-round difficulty scalars: spawn rate × SPAWN_RATE_PER_ROUND each round,
# speed × SPEED_PER_ROUND each round. Both compound.
const SPAWN_RATE_PER_ROUND := 1.30
const SPEED_PER_ROUND := 1.05
const MIN_SPAWN_INTERVAL := 0.10
# Cumulative spawn weights: 0..LIKE = LIKE, LIKE..DISLIKE = DISLIKE, DISLIKE..1 = VIEW.
# 10% LIKE (green) / 50% DISLIKE (red) / 40% VIEW (white)
const SPAWN_RATIO_LIKE    := 0.10
const SPAWN_RATIO_DISLIKE := 0.60
const DISLIKE_DAMAGE    := 5

const SEPARATION_MIN    := 60.0
const SEPARATION_PUSH   := 2.0

# All upgrade tuning lives in Upgrades.CATALOG[*]["params"]. The arena reads
# values at point-of-use so editing the catalog is the single source of truth.

@onready var _eye: TextureRect = $Eye
@onready var _hp_bar: ProgressBar = $HPBar
@onready var _drifters: Control = $DrifterContainer
@onready var _spawn_timer: Timer = $SpawnTimer

var _like_tex: Texture2D
var _dislike_tex: Texture2D
var _view_tex: Texture2D
var _paused := false
var _stats_label: Label
var _spawn_interval: float = BASE_SPAWN_INTERVAL
var _drifter_speed: float = BASE_DRIFTER_SPEED

# --- Upgrade-driven effects ---
# Ownership of the upgrades themselves lives in the Upgrades autoload.
var _upgrade_screen: Control
var _effects_layer: Control      # holds lazer arcs, nova bursts
var _echo_zones: Control         # holds active echo zones
var _lazer_cooldown: float = 0.0
var _nova_cooldown: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

	var eye_tex: Texture2D = _safe_load(EYE_TEX_PATH)
	if eye_tex == null:
		eye_tex = _make_fallback_eye_texture(int(EYE_SIZE.x))
	_eye.texture = eye_tex
	_eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_eye.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_eye.size = EYE_SIZE
	# Eye is passive now — views come from clicking white VIEW drifters.
	_eye.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hp_bar.min_value = 0.0
	_hp_bar.max_value = float(GameManager.EYE_MAX_HP)
	_hp_bar.value = float(GameManager.eye_hp)
	_hp_bar.show_percentage = false
	_hp_bar.size = HPBAR_SIZE
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_drifters.mouse_filter = Control.MOUSE_FILTER_PASS

	_like_tex = _safe_load(LIKE_TEX_PATH)
	if _like_tex == null:
		_like_tex = _make_circle_texture(int(DRIFTER_SIZE.x), Color(0.20, 0.85, 0.30))
	_dislike_tex = _safe_load(DISLIKE_TEX_PATH)
	if _dislike_tex == null:
		_dislike_tex = _make_circle_texture(int(DRIFTER_SIZE.x), Color(0.95, 0.25, 0.25))
	_view_tex = _safe_load(VIEW_TEX_PATH)
	if _view_tex == null:
		_view_tex = _make_circle_texture(int(DRIFTER_SIZE.x), Color(0.95, 0.95, 0.95))

	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	_stats_label.anchor_left = 0.0
	_stats_label.anchor_right = 1.0
	_stats_label.anchor_top = 1.0
	_stats_label.anchor_bottom = 1.0
	_stats_label.offset_top = -VIEW_LABEL_BOTTOM_GAP - float(VIEW_LABEL_FONT)
	_stats_label.offset_bottom = -VIEW_LABEL_BOTTOM_GAP
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", VIEW_LABEL_FONT)
	_stats_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_stats_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_stats_label.add_theme_constant_override("outline_size", 4)
	_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stats_label)
	_refresh_stats_label()
	GameManager.views_changed.connect(func(_v: int) -> void: _refresh_stats_label())
	GameManager.subs_changed.connect(func(_s: int) -> void: _refresh_stats_label())

	GameManager.eye_hp_changed.connect(_on_eye_hp_changed)
	GameManager.run_reset.connect(_on_run_reset)
	GameManager.round_advanced.connect(_on_round_advanced)
	resized.connect(_layout)
	_layout()

	_echo_zones = Control.new()
	_echo_zones.name = "EchoZones"
	_echo_zones.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_echo_zones.anchor_right = 1.0
	_echo_zones.anchor_bottom = 1.0
	add_child(_echo_zones)

	_effects_layer = Control.new()
	_effects_layer.name = "EffectsLayer"
	_effects_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effects_layer.anchor_right = 1.0
	_effects_layer.anchor_bottom = 1.0
	add_child(_effects_layer)

	var screen_script := preload("res://scripts/ui/stream/upgrade_screen.gd")
	_upgrade_screen = Control.new()
	_upgrade_screen.set_script(screen_script)
	_upgrade_screen.name = "UpgradeScreen"
	add_child(_upgrade_screen)
	_upgrade_screen.screen_closed.connect(_on_upgrade_screen_closed)

	_spawn_timer.wait_time = _spawn_interval
	_spawn_timer.one_shot = false
	_spawn_timer.autostart = true
	if not _spawn_timer.timeout.is_connected(_on_spawn_tick):
		_spawn_timer.timeout.connect(_on_spawn_tick)

	# Spawn the first drifter as soon as layout has settled, so the screen isn't
	# empty for SPAWN_INTERVAL seconds after launch.
	await get_tree().process_frame
	_on_spawn_tick()

func _process(delta: float) -> void:
	if _paused:
		return
	_apply_separation()
	_refresh_stats_label()
	_tick_auto_lazer(delta)
	_tick_nova(delta)
	_apply_echo_zones()

func _refresh_stats_label() -> void:
	if not is_instance_valid(_stats_label):
		return
	var remaining: int = int(ceil(maxf(0.0, GameManager.ROUND_DURATION - GameManager.round_timer)))
	_stats_label.text = "ROUND %d  (%ds)     SUBS: %d     VIEWS: %d" % [
		GameManager.current_round, remaining, GameManager.subs, GameManager.views
	]

func set_paused(p: bool) -> void:
	_paused = p
	# DISABLED stops _process, _gui_input, AND timer ticks across the whole subtree.
	process_mode = Node.PROCESS_MODE_DISABLED if p else Node.PROCESS_MODE_INHERIT
	# Also freeze GameManager (autoload) so passive view generation, the round
	# timer, and elapsed_time don't tick while a modal or edit mode is open.
	GameManager.paused = p

func _layout() -> void:
	var center := size * 0.5
	_eye.position = center - EYE_SIZE * 0.5
	_hp_bar.position = Vector2(center.x - HPBAR_SIZE.x * 0.5, _eye.position.y - HPBAR_GAP - HPBAR_SIZE.y)
	_hp_bar.visible = GameManager.eye_hp < GameManager.EYE_MAX_HP

func _eye_center() -> Vector2:
	return _eye.position + EYE_SIZE * 0.5

# --- Spawning ---

func _on_spawn_tick() -> void:
	var r := randf()
	var kind: int
	if r < SPAWN_RATIO_LIKE:
		kind = Drifter.Kind.LIKE
	elif r < SPAWN_RATIO_DISLIKE:
		kind = Drifter.Kind.DISLIKE
	else:
		kind = Drifter.Kind.VIEW
	_spawn_drifter(kind)

func _tex_for(kind: int) -> Texture2D:
	match kind:
		Drifter.Kind.LIKE:    return _like_tex
		Drifter.Kind.DISLIKE: return _dislike_tex
		Drifter.Kind.VIEW:    return _view_tex
	return null

func _spawn_drifter(kind: int) -> void:
	var tex: Texture2D = _tex_for(kind)
	if tex == null:
		return
	if size.x <= 0.0 or size.y <= 0.0:
		return  # layout not settled yet
	var d: Drifter = Drifter.new()
	_drifters.add_child(d)
	# Spawn just outside one of the four arena edges so they enter the visible
	# area almost immediately.
	var m := DRIFTER_EDGE_MARGIN
	var start_center: Vector2
	match randi() % 4:
		0: start_center = Vector2(randf() * size.x, -m)             # top
		1: start_center = Vector2(size.x + m, randf() * size.y)     # right
		2: start_center = Vector2(randf() * size.x, size.y + m)     # bottom
		_: start_center = Vector2(-m, randf() * size.y)             # left
	d.position = start_center - DRIFTER_SIZE * 0.5
	d.setup(kind, tex, _drifter_speed, _eye_center(), DRIFTER_SIZE)
	d.clicked.connect(_on_drifter_clicked)
	d.reached_target.connect(_on_drifter_reached)

func _on_drifter_clicked(d: Drifter) -> void:
	var pos: Vector2 = d.position + d.size * 0.5
	_destroy_drifter(d)
	if Upgrades.is_owned("echo"):
		_spawn_echo_zone(pos)

func _on_drifter_reached(d: Drifter) -> void:
	if d.kind == Drifter.Kind.DISLIKE:
		GameManager.damage_eye(DISLIKE_DAMAGE)
		d.explode_and_free()
	else:
		# Uncaught LIKE or VIEW silently vanishes — missed opportunity.
		d.queue_free()

# Reward + explode. Used by clicks AND by upgrade effects (lazer/nova/echo).
func _destroy_drifter(d: Drifter) -> void:
	if d == null or not is_instance_valid(d) or d._exploding:
		return
	match d.kind:
		Drifter.Kind.LIKE:
			GameManager.add_bonus_subs(1)
		Drifter.Kind.VIEW:
			GameManager.add_views(1)
		Drifter.Kind.DISLIKE:
			pass
	d.explode_and_free()

# --- Separation ---

func _apply_separation() -> void:
	var list := _drifters.get_children()
	for i in list.size():
		var a := list[i] as Drifter
		if a == null:
			continue
		for j in range(i + 1, list.size()):
			var b := list[j] as Drifter
			if b == null:
				continue
			a.separate_from(b, SEPARATION_MIN, SEPARATION_PUSH)

# --- HP / Run ---

func _on_eye_hp_changed(new_hp: int) -> void:
	_hp_bar.value = float(new_hp)
	_hp_bar.visible = new_hp < GameManager.EYE_MAX_HP

func _on_run_reset(_new_run: int) -> void:
	for child in _drifters.get_children():
		child.queue_free()
	if _echo_zones:
		for z in _echo_zones.get_children():
			z.queue_free()
	if _effects_layer:
		for e in _effects_layer.get_children():
			e.queue_free()
	Upgrades.reset()
	# Cooldowns start at 0 so the first tick after a future purchase fires immediately.
	_lazer_cooldown = 0.0
	_nova_cooldown = 0.0
	# Reset per-round scaling back to base difficulty.
	_spawn_interval = BASE_SPAWN_INTERVAL
	_drifter_speed = BASE_DRIFTER_SPEED
	_spawn_timer.wait_time = _spawn_interval
	if _upgrade_screen:
		_upgrade_screen.visible = false

func _on_round_advanced(new_round: int) -> void:
	_spawn_interval = maxf(MIN_SPAWN_INTERVAL, _spawn_interval / SPAWN_RATE_PER_ROUND)
	_drifter_speed *= SPEED_PER_ROUND
	_spawn_timer.wait_time = _spawn_interval
	# Skip the modal on round 1 — it fires once at startup via reset_run.
	if new_round <= 1:
		return
	set_paused(true)
	_upgrade_screen.show_for_round(new_round - 1)

func _on_upgrade_screen_closed() -> void:
	set_paused(false)

func _safe_load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

# Solid colored circle with a dark outline. Used as fallback for like/dislike
# when assets/screen/like.png and dislike.png haven't been provided yet.
func _make_circle_texture(diameter: int, color: Color) -> Texture2D:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var center := Vector2(diameter * 0.5, diameter * 0.5)
	var radius: float = diameter * 0.48
	for y in diameter:
		for x in diameter:
			var d: float = (Vector2(x, y) - center).length()
			var c: Color
			if d > radius:
				c = Color(0, 0, 0, 0)
			elif d > radius - 2.0:
				c = Color(0, 0, 0, 1)
			else:
				c = color
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# --- Auto Lazer ---

func _tick_auto_lazer(delta: float) -> void:
	if not Upgrades.is_owned("auto_lazer"):
		return
	_lazer_cooldown -= delta
	if _lazer_cooldown <= 0.0:
		_lazer_cooldown = float(Upgrades.get_param("auto_lazer", "cooldown", 0.5))
		Upgrades.start_cooldown("auto_lazer", _lazer_cooldown)
		_fire_lazer()

func _fire_lazer() -> void:
	var target := _find_nearest_drifter()
	if target == null:
		return
	var end_pos: Vector2 = target.position + target.size * 0.5
	_spawn_lightning(_eye_center(), end_pos)
	_destroy_drifter(target)

func _find_nearest_drifter() -> Drifter:
	var best: Drifter = null
	var best_d2 := INF
	var origin := _eye_center()
	for child in _drifters.get_children():
		var d := child as Drifter
		if d == null or d._exploding:
			continue
		var c: Vector2 = d.position + d.size * 0.5
		var d2: float = origin.distance_squared_to(c)
		if d2 < best_d2:
			best_d2 = d2
			best = d
	return best

func _spawn_lightning(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.points = _jagged_path(from, to, 5, 12.0)
	line.width = 3.0
	line.default_color = Color(0.75, 0.92, 1.0, 1.0)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	_effects_layer.add_child(line)
	var t := line.create_tween()
	t.tween_property(line, "modulate:a", 0.0, 0.18)
	t.tween_callback(line.queue_free)

func _jagged_path(from: Vector2, to: Vector2, segments: int, jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(from)
	var dir := to - from
	var perp := Vector2(-dir.y, dir.x).normalized()
	for i in range(1, segments):
		var t := i / float(segments)
		var p := from + dir * t + perp * randf_range(-jitter, jitter)
		pts.append(p)
	pts.append(to)
	return pts

# --- Nova ---

func _tick_nova(delta: float) -> void:
	if not Upgrades.is_owned("nova"):
		return
	_nova_cooldown -= delta
	if _nova_cooldown <= 0.0:
		_nova_cooldown = float(Upgrades.get_param("nova", "cooldown", 5.0))
		Upgrades.start_cooldown("nova", _nova_cooldown)
		_fire_nova()

func _fire_nova() -> void:
	var origin := _eye_center()
	var radius: float = float(Upgrades.get_param("nova", "radius", 200.0))
	_spawn_nova_burst(origin, radius)
	# Destroy every drifter whose CENTER is inside the radius.
	for child in _drifters.get_children():
		var d := child as Drifter
		if d == null or d._exploding:
			continue
		var c: Vector2 = d.position + d.size * 0.5
		if origin.distance_to(c) <= radius:
			_destroy_drifter(d)

func _spawn_nova_burst(origin: Vector2, max_radius: float) -> void:
	var diameter := 64
	var tex := _make_circle_texture(diameter, Color(0.4, 0.85, 1.0, 0.7))
	var rect := TextureRect.new()
	rect.texture = tex
	rect.size = Vector2(diameter, diameter)
	rect.position = origin - Vector2(diameter, diameter) * 0.5
	rect.pivot_offset = Vector2(diameter, diameter) * 0.5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_effects_layer.add_child(rect)
	var target_scale: float = (max_radius * 2.0) / float(diameter)
	var t := rect.create_tween().set_parallel(true)
	t.tween_property(rect, "scale", Vector2(target_scale, target_scale), 0.32)
	t.tween_property(rect, "modulate:a", 0.0, 0.32)
	t.chain().tween_callback(rect.queue_free)

# --- Echo ---

func _spawn_echo_zone(center: Vector2) -> void:
	var radius: float = float(Upgrades.get_param("echo", "radius", 50.0))
	var duration: float = float(Upgrades.get_param("echo", "duration", 1.0))
	var diameter := int(radius * 2.0)
	var tex := _make_circle_texture(diameter, Color(0.7, 0.35, 1.0, 0.4))
	var rect := TextureRect.new()
	rect.texture = tex
	rect.size = Vector2(diameter, diameter)
	rect.position = center - Vector2(diameter, diameter) * 0.5
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_echo_zones.add_child(rect)
	var t := rect.create_tween()
	t.tween_property(rect, "modulate:a", 0.0, duration)
	t.tween_callback(rect.queue_free)

func _apply_echo_zones() -> void:
	if _echo_zones == null or _echo_zones.get_child_count() == 0:
		return
	# Read params once per tick instead of per pair.
	var radius: float = float(Upgrades.get_param("echo", "radius", 50.0))
	var overlap: float = float(Upgrades.get_param("echo", "overlap_trigger", 0.20))
	for zone in _echo_zones.get_children():
		var z := zone as Control
		if z == null:
			continue
		var zc: Vector2 = z.position + z.size * 0.5
		for child in _drifters.get_children():
			var d := child as Drifter
			if d == null or d._exploding:
				continue
			var dc: Vector2 = d.position + d.size * 0.5
			# Trigger when drifter center is within (zone_radius + (1-overlap)*drifter_half).
			# Roughly equates to `overlap` area overlap for similar-sized shapes.
			var trigger_dist: float = radius + d.size.x * 0.5 * (1.0 - overlap)
			if zc.distance_to(dc) <= trigger_dist:
				_destroy_drifter(d)

# Simple programmatic eye used when assets/screen/eye.png is missing.
# White sclera + blue iris + black pupil, transparent corners.
func _make_fallback_eye_texture(diameter: int) -> Texture2D:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var center := Vector2(diameter * 0.5, diameter * 0.5)
	var sclera_r: float = diameter * 0.48
	var iris_r:   float = diameter * 0.22
	var pupil_r:  float = diameter * 0.10
	for y in diameter:
		for x in diameter:
			var d: float = (Vector2(x, y) - center).length()
			var c: Color
			if d > sclera_r:
				c = Color(0, 0, 0, 0)
			elif d > iris_r:
				c = Color(1, 1, 1, 1)
			elif d > pupil_r:
				c = Color(0.18, 0.55, 0.95, 1)
			else:
				c = Color(0, 0, 0, 1)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
