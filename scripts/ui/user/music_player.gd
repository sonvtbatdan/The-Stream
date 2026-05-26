# Music player widget.
# Paste a YouTube URL → press Enter or ▶ to play (title fetched simultaneously).
class_name UserMusicPlayer
extends Panel

const PANEL_W  := 460.0
const PANEL_H  := 195.0
const YT_OEMBED := "https://www.youtube.com/oembed?url=%s&format=json"

var _server: UserMusicServer
var _playing  := false
var _muted    := false
var _volume   := 1.0
var _loading  := false
var _load_t   := 0.0

var _url_input:    LineEdit
var _title_lbl:    _MarqueeLabel
var _play_btn:     Button
var _mute_btn:     Button
var _vol_slider:   HSlider
var _status_lbl:   LineEdit

var _http_title: HTTPRequest

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = Vector2(PANEL_W, PANEL_H)
	_apply_style()
	_build_ui()

	_server = UserMusicServer.new()
	add_child(_server)
	_server.browser_connected.connect(_on_browser_connected)
	_server.browser_disconnected.connect(_on_browser_disconnected)
	_server.start_failed.connect(_on_start_failed)

	_http_title = HTTPRequest.new()
	add_child(_http_title)
	_http_title.request_completed.connect(_on_title_fetched)

func _process(delta: float) -> void:
	if not _loading:
		return
	_load_t += delta
	_status_lbl.text = "Connecting... (%.0fs)" % _load_t

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.07, 0.09, 0.13, 0.95)
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.border_color        = Color(0.35, 0.45, 0.65, 0.9)
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", s)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left   = 14
	root.offset_top    = 10
	root.offset_right  = -14
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# ── URL row ──────────────────────────────────────────────────
	_url_input = LineEdit.new()
	_url_input.placeholder_text = "Paste YouTube link…"
	_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_input.add_theme_color_override("font_placeholder_color", Color(0.45, 0.45, 0.45))
	_url_input.text_submitted.connect(_on_url_submitted)
	root.add_child(_url_input)

	# ── Scrolling song name ───────────────────────────────────────
	_title_lbl = _MarqueeLabel.new()
	_title_lbl.set_text("—")
	_title_lbl.set_style(Color(0.8, 0.9, 1.0), 12)
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_title_lbl)

	# ── Controls row ─────────────────────────────────────────────
	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 6)
	root.add_child(ctrl_row)

	_play_btn = Button.new()
	_play_btn.text = "▶"
	_play_btn.custom_minimum_size = Vector2(36, 36)
	_play_btn.pressed.connect(_on_play_pressed)
	ctrl_row.add_child(_play_btn)

	var vol_container := _build_vol_container()
	vol_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl_row.add_child(vol_container)

	_mute_btn = Button.new()
	_mute_btn.text = "🔇"
	_mute_btn.custom_minimum_size = Vector2(36, 36)
	_mute_btn.toggle_mode = true
	_mute_btn.toggled.connect(_on_mute_toggled)
	ctrl_row.add_child(_mute_btn)

	var test_btn := Button.new()
	test_btn.text = "♪"
	test_btn.custom_minimum_size = Vector2(28, 36)
	test_btn.tooltip_text = "Sound test (Godot audio)"
	test_btn.pressed.connect(_on_sound_test_pressed)
	ctrl_row.add_child(test_btn)

	# ── Status ────────────────────────────────────────────────────
	_status_lbl = LineEdit.new()
	_status_lbl.text = ""
	_status_lbl.editable = false
	_status_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_status_lbl.add_theme_font_size_override("font_size", 10)
	var _empty_style := StyleBoxEmpty.new()
	_status_lbl.add_theme_stylebox_override("normal",    _empty_style)
	_status_lbl.add_theme_stylebox_override("read_only", _empty_style)
	_status_lbl.add_theme_stylebox_override("focus",     _empty_style)
	root.add_child(_status_lbl)

func _build_vol_container() -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(0, 36)

	var triangle: Control = _TriangleDraw.new()
	triangle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	triangle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(triangle)

	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 1.0
	_vol_slider.step      = 0.01
	_vol_slider.value     = 1.0
	_vol_slider.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vol_slider.value_changed.connect(_on_volume_changed)
	container.add_child(_vol_slider)

	return container

# ── Callbacks ────────────────────────────────────────────────────────────────

func _on_url_submitted(url: String) -> void:
	url = url.strip_edges()
	if url.is_empty():
		return
	_url_input.text = url
	_fetch_title(url)
	if not _playing:
		_on_play_pressed()

func _fetch_title(url: String) -> void:
	_title_lbl.set_text("Fetching…")
	_http_title.cancel_request()
	_http_title.request(YT_OEMBED % url.uri_encode())

func _on_title_fetched(_res: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
	if code == 200:
		var j: Variant = JSON.parse_string(body.get_string_from_utf8())
		if j is Dictionary:
			_title_lbl.set_text(j.get("title", "Unknown"))
	else:
		_title_lbl.set_text("Unknown title")

func _on_play_pressed() -> void:
	if not _playing:
		var url := _url_input.text.strip_edges()
		if url.is_empty():
			_status_lbl.text = "Enter a YouTube URL first."
			return
		var vid_id := _extract_video_id(url)
		if vid_id.is_empty():
			_status_lbl.text = "Invalid YouTube URL."
			return
		_fetch_title(url)
		_playing = true
		_loading = true
		_load_t  = 0.0
		_play_btn.text = "⏸"
		_server.open_video(vid_id)
	else:
		_playing = false
		_loading = false
		_play_btn.text = "▶"
		_server.send({"cmd": "pause"})
		_status_lbl.text = ""

func _on_mute_toggled(pressed: bool) -> void:
	_muted = pressed
	_server.send({"cmd": "mute" if _muted else "unmute"})

func _on_volume_changed(val: float) -> void:
	_volume = val
	_server.send({"cmd": "volume", "v": val})

func _on_browser_connected() -> void:
	_loading = false
	_status_lbl.text = ""
	_server.send({"cmd": "volume", "v": _volume})
	if _playing:
		_server.send({"cmd": "play"})

func _on_browser_disconnected() -> void:
	if _playing:
		_status_lbl.text = "Player disconnected."

func _on_start_failed(reason: String) -> void:
	_playing = false
	_loading = false
	_play_btn.text = "▶"
	_status_lbl.text = reason

func _on_sound_test_pressed() -> void:
	# Debug: show audio bus state
	var bus_count := AudioServer.get_bus_count()
	var master_vol := AudioServer.get_bus_volume_db(0)
	var master_mute := AudioServer.is_bus_mute(0)
	_status_lbl.text = "buses:%d master:%.0fdB mute:%s" % [bus_count, master_vol, master_mute]

	# Build a 440 Hz sine wave as PCM into AudioStreamWAV (no push_frame timing issues)
	var sample_rate := 44100
	var duration    := 0.6
	var n_samples   := int(sample_rate * duration)
	var data        := PackedByteArray()
	data.resize(n_samples * 2)  # 16-bit mono
	for i in n_samples:
		var t      := float(i) / sample_rate
		var env    := 1.0 - t / duration
		var sample := int(sin(TAU * 440.0 * t) * 0.8 * env * 32767.0)
		data[i * 2]     = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.data      = data
	wav.format    = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate  = sample_rate
	wav.stereo    = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED

	var player := AudioStreamPlayer.new()
	player.volume_db = 0.0
	player.bus = "Master"
	add_child(player)
	player.stream = wav
	player.play()

	await get_tree().create_timer(0.8).timeout
	player.queue_free()

# ── Helpers ──────────────────────────────────────────────────────────────────

func _extract_video_id(url: String) -> String:
	if "youtu.be/" in url:
		var parts := url.split("youtu.be/")
		if parts.size() >= 2:
			return parts[1].split("?")[0].split("&")[0]
	if "v=" in url:
		var after := url.split("v=")[1]
		return after.split("&")[0].split("#")[0]
	return ""

# ── Inner: scrolling label ────────────────────────────────────────────────────
class _MarqueeLabel extends Control:
	const SPEED := 50.0   # px / sec
	const PAUSE := 2.0    # sec pause at each end

	var _lbl:  Label
	var _ox    := 0.0
	var _dir   := -1.0
	var _wait  := PAUSE

	func _init() -> void:
		_lbl = Label.new()
		_lbl.position = Vector2.ZERO
		_lbl.clip_text = false

	func _ready() -> void:
		clip_contents = true
		add_child(_lbl)
		custom_minimum_size.y = max(18.0, _lbl.get_minimum_size().y)

	func set_text(t: String) -> void:
		_lbl.text = t
		_ox   = 0.0
		_dir  = -1.0
		_wait = PAUSE
		if is_node_ready():
			_lbl.position.x = 0.0

	func set_style(color: Color, font_size: int) -> void:
		_lbl.add_theme_color_override("font_color", color)
		_lbl.add_theme_font_size_override("font_size", font_size)

	func _process(delta: float) -> void:
		var text_w := _lbl.get_minimum_size().x
		if text_w <= size.x:
			_lbl.position.x = 0.0
			_ox = 0.0
			return
		if _wait > 0.0:
			_wait -= delta
			return
		_ox += SPEED * _dir * delta
		var max_off := -(text_w - size.x)
		if _ox <= max_off:
			_ox   = max_off
			_dir  = 1.0
			_wait = PAUSE
		elif _ox >= 0.0:
			_ox   = 0.0
			_dir  = -1.0
			_wait = PAUSE
		_lbl.position.x = _ox

# ── Inner: volume ramp triangle ───────────────────────────────────────────────
class _TriangleDraw extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, h),
			Vector2(w,   h * 0.25),
			Vector2(w,   h),
		]), Color(0.3, 0.45, 0.7, 0.45))
