class_name Drifter
extends Control

signal clicked(drifter: Drifter)
signal reached_target(drifter: Drifter)

enum Kind { LIKE, DISLIKE, VIEW }

const REACH_DISTANCE := 28.0
const MIN_SCALE := 0.55
const MAX_SCALE := 1.0
const SCALE_FALLOFF := 240.0  # distance over which we lerp from MIN to MAX scale

var kind: int = Kind.LIKE
var speed: float = 80.0
var target_center: Vector2 = Vector2.ZERO
var _spawn_distance: float = 1.0
var _exploding := false
var _texture_rect: TextureRect

func setup(p_kind: int, tex: Texture2D, p_speed: float, p_target: Vector2, p_size: Vector2) -> void:
	kind = p_kind
	speed = p_speed
	target_center = p_target
	size = p_size
	pivot_offset = p_size / 2.0
	# Parent passes through; the Button child below handles clicks.
	mouse_filter = Control.MOUSE_FILTER_PASS

	_texture_rect = TextureRect.new()
	_texture_rect.texture = tex
	_texture_rect.position = Vector2.ZERO
	_texture_rect.size = p_size
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_texture_rect)

	# Transparent button covers the drifter rect and reliably reports clicks.
	# Explicit size/position (no anchors) so layout passes can't shrink it.
	var btn := Button.new()
	btn.position = Vector2.ZERO
	btn.size = p_size
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.add_theme_stylebox_override("disabled", empty)
	btn.pressed.connect(_on_button_pressed)
	add_child(btn)

	_spawn_distance = max(1.0, (_center() - target_center).length())
	_apply_zoom(MIN_SCALE)

func _process(delta: float) -> void:
	if _exploding:
		return
	var to_target := target_center - _center()
	var dist := to_target.length()
	if dist <= REACH_DISTANCE:
		emit_signal("reached_target", self)
		return
	position += to_target.normalized() * speed * delta
	# Zoom-in via TextureRect size (NOT Control scale) so the hit area stays
	# constant at the Drifter's full rect.
	var t: float = clamp(1.0 - dist / SCALE_FALLOFF, 0.0, 1.0)
	_apply_zoom(lerp(MIN_SCALE, MAX_SCALE, t))

func _apply_zoom(s: float) -> void:
	if _texture_rect == null:
		return
	var tex_size := size * s
	_texture_rect.size = tex_size
	_texture_rect.position = (size - tex_size) * 0.5

func _on_button_pressed() -> void:
	if _exploding:
		return
	emit_signal("clicked", self)

func explode_and_free() -> void:
	if _exploding:
		return
	_exploding = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "scale", scale * 1.6, 0.12)
	t.tween_property(self, "modulate:a", 0.0, 0.18)
	t.chain().tween_callback(queue_free)

func _center() -> Vector2:
	return position + size * 0.5

# Gentle separation: nudge away from another drifter, called by arena.
func separate_from(other: Drifter, min_dist: float, push: float) -> void:
	if _exploding or other._exploding:
		return
	var delta_vec := _center() - other._center()
	var d := delta_vec.length()
	if d <= 0.001 or d >= min_dist:
		return
	var amount: float = (min_dist - d) * push * 0.5
	position += delta_vec.normalized() * amount
