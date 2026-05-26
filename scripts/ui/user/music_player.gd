# Music player widget — shows now-playing title, time bar, next-4-songs queue,
# URL input, and playback controls at the bottom.
class_name UserMusicPlayer
extends Panel

const PANEL_W   := 460.0
const PANEL_H   := 255.0
const YT_OEMBED := "https://www.youtube.com/oembed?url=%s&format=json"

var _server: UserMusicServer
var _playing       := false
var _paused        := false   # true while paused (content still loaded in mpv)
var _muted         := false
var _volume        := 1.0
var _loading       := false
var _load_t        := 0.0
var _playlist_mode := false
var _duration      := 0.0
var _cur_pos       := 0.0
var _playlist_pos  := -1
var _seeking       := false
var _upd_seek      := false   # true while programmatically setting seek bar value

var _url_input:   LineEdit
var _title_lbl:   _MarqueeLabel
var _play_btn:    Button
var _mute_btn:    Button
var _vol_slider:  HSlider
var _status_lbl:  LineEdit
var _elapsed_lbl: Label
var _remain_lbl:  Label
var _seek_bar:    HSlider
var _song_btns:   Array = []   # Array[Button], 4 entries

var _http_title: HTTPRequest

# ── Lifecycle ─────────────────────────────────────────────────────────────────

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
	_server.playlist_loaded.connect(_on_playlist_loaded)
	_server.time_changed.connect(_on_time_changed)
	_server.duration_changed.connect(_on_duration_changed)
	_server.playlist_pos_changed.connect(_on_playlist_pos_changed)

	_http_title = HTTPRequest.new()
	add_child(_http_title)
	_http_title.request_completed.connect(_on_title_fetched)

func _process(delta: float) -> void:
	if _playlist_mode or not _loading:
		return
	_load_t += delta
	_status_lbl.text = "Connecting... (%.0fs)" % _load_t

# ── Style ─────────────────────────────────────────────────────────────────────

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

# ── UI build ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 14
	vbox.offset_top    = 8
	vbox.offset_right  = -14
	vbox.offset_bottom = -8
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# ── Current song title (marquee) ──────────────────────────────
	_title_lbl = _MarqueeLabel.new()
	_title_lbl.set_text("—")
	_title_lbl.set_style(Color(0.85, 0.92, 1.0), 13)
	_title_lbl.custom_minimum_size = Vector2(0, 20)
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_title_lbl)

	# ── Time row: elapsed | seek bar | remaining ──────────────────
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 4)
	vbox.add_child(time_row)

	_elapsed_lbl = Label.new()
	_elapsed_lbl.text = "--:--"
	_elapsed_lbl.custom_minimum_size = Vector2(36, 0)
	_elapsed_lbl.add_theme_font_size_override("font_size", 10)
	_elapsed_lbl.add_theme_color_override("font_color", Color(0.6, 0.72, 0.9))
	_elapsed_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_row.add_child(_elapsed_lbl)

	_seek_bar = HSlider.new()
	_seek_bar.min_value = 0.0
	_seek_bar.max_value = 1.0
	_seek_bar.step      = 0.0001
	_seek_bar.value     = 0.0
	_seek_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek_bar.value_changed.connect(_on_seek_changed)
	_seek_bar.gui_input.connect(_on_seek_input)
	time_row.add_child(_seek_bar)

	_remain_lbl = Label.new()
	_remain_lbl.text = "--:--"
	_remain_lbl.custom_minimum_size = Vector2(40, 0)
	_remain_lbl.add_theme_font_size_override("font_size", 10)
	_remain_lbl.add_theme_color_override("font_color", Color(0.45, 0.55, 0.75))
	_remain_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_remain_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_row.add_child(_remain_lbl)

	# ── Next 4 songs (flat buttons, hidden when not in playlist) ──
	for i in 4:
		var btn := Button.new()
		btn.flat = true
		btn.text = ""
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 20)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_color_override("font_color", Color(0.5, 0.62, 0.82, 0.85))
		btn.pressed.connect(_on_next_song_pressed.bind(i))
		btn.visible = false
		_song_btns.append(btn)
		vbox.add_child(btn)

	# ── Spacer — pushes controls to bottom ────────────────────────
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# ── URL input ─────────────────────────────────────────────────
	_url_input = LineEdit.new()
	_url_input.placeholder_text = "Paste YouTube link…"
	_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_input.add_theme_color_override("font_placeholder_color", Color(0.4, 0.4, 0.4))
	_url_input.add_theme_font_size_override("font_size", 11)
	_url_input.text_submitted.connect(_on_url_submitted)
	vbox.add_child(_url_input)

	# ── Controls row: ▶/⏸  [volume]  🔇 ─────────────────────────
	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 4)
	vbox.add_child(ctrl_row)

	_play_btn = Button.new()
	_play_btn.text = "▶"
	_play_btn.custom_minimum_size = Vector2(30, 30)
	_play_btn.pressed.connect(_on_play_pressed)
	ctrl_row.add_child(_play_btn)

	var vol_container := _build_vol_container()
	vol_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl_row.add_child(vol_container)

	_mute_btn = Button.new()
	_mute_btn.text = "🔇"
	_mute_btn.custom_minimum_size = Vector2(30, 30)
	_mute_btn.toggle_mode = true
	_mute_btn.toggled.connect(_on_mute_toggled)
	ctrl_row.add_child(_mute_btn)

	# ── Status ────────────────────────────────────────────────────
	_status_lbl = LineEdit.new()
	_status_lbl.text = ""
	_status_lbl.editable = false
	_status_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_status_lbl.add_theme_font_size_override("font_size", 10)
	var es := StyleBoxEmpty.new()
	_status_lbl.add_theme_stylebox_override("normal",    es)
	_status_lbl.add_theme_stylebox_override("read_only", es)
	_status_lbl.add_theme_stylebox_override("focus",     es)
	vbox.add_child(_status_lbl)

func _build_vol_container() -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(0, 30)

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

# ── Time / seek callbacks ─────────────────────────────────────────────────────

func _on_time_changed(pos: float) -> void:
	_cur_pos = pos
	_elapsed_lbl.text = _fmt_time(pos)
	if _duration > 0.0:
		_remain_lbl.text = "-" + _fmt_time(_duration - pos)
		if not _seeking:
			_upd_seek = true
			_seek_bar.value = pos / _duration
			_upd_seek = false

func _on_duration_changed(dur: float) -> void:
	_duration = dur

func _on_seek_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_seeking = true
		else:
			_seeking = false
			if _duration > 0.0:
				_server.seek_to(_seek_bar.value * _duration)

func _on_seek_changed(val: float) -> void:
	if _upd_seek or _duration <= 0.0:
		return
	_elapsed_lbl.text = _fmt_time(val * _duration)
	_remain_lbl.text  = "-" + _fmt_time(_duration - val * _duration)

func _fmt_time(secs: float) -> String:
	if secs < 0.0:
		secs = 0.0
	var s := int(secs)
	return "%d:%02d" % [s / 60, s % 60]

# ── Playlist queue callbacks ──────────────────────────────────────────────────

func _on_playlist_pos_changed(idx: int) -> void:
	_playlist_pos = idx
	_duration = 0.0
	_cur_pos  = 0.0
	_elapsed_lbl.text = "--:--"
	_remain_lbl.text  = "--:--"
	_seek_bar.value   = 0.0
	if idx >= 0 and idx < _server.playlist_ids.size():
		_fetch_title("https://www.youtube.com/watch?v=" + _server.playlist_ids[idx])
	_update_queue_btns()

func _update_queue_btns() -> void:
	var t_arr := _server.playlist_titles
	var i_arr := _server.playlist_ids
	for i in 4:
		var btn: Button = _song_btns[i]
		var si := _playlist_pos + 1 + i
		if si >= 0 and si < i_arr.size():
			var title: String = t_arr[si] if si < t_arr.size() else i_arr[si]
			btn.text = "%d.  %s" % [si + 1, title]
			btn.visible = true
		else:
			btn.text = ""
			btn.visible = false

func _on_next_song_pressed(btn_idx: int) -> void:
	var si := _playlist_pos + 1 + btn_idx
	if si < _server.playlist_ids.size():
		_playlist_pos = si
		var titles := _server.playlist_titles
		_title_lbl.set_text(titles[si] if si < titles.size() else _server.playlist_ids[si])
		_update_queue_btns()
		_server.skip_to(si)

# ── URL / playback callbacks ──────────────────────────────────────────────────

func _on_url_submitted(url: String) -> void:
	url = url.strip_edges()
	if url.is_empty():
		return
	_url_input.text = url
	_fetch_title(url)
	_play_url(url)

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
	if _playing:
		_playing = false
		_paused  = true
		_play_btn.text = "▶"
		_server.send({"cmd": "pause"})
	elif _paused:
		_playing = true
		_paused  = false
		_play_btn.text = "⏸"
		_server.send({"cmd": "play"})
	else:
		var url := _url_input.text.strip_edges()
		_fetch_title(url)
		_play_url(url)

func _play_url(url: String) -> void:
	if url.is_empty():
		_status_lbl.text = "Enter a YouTube URL first."
		return
	_paused  = false
	_playing = true
	_play_btn.text = "⏸"
	_duration = 0.0
	_cur_pos  = 0.0
	_elapsed_lbl.text = "--:--"
	_remain_lbl.text  = "--:--"
	_seek_bar.value   = 0.0
	_playlist_pos = -1
	for btn in _song_btns:
		(btn as Button).visible = false
	if _is_playlist_url(url):
		_playlist_mode = true
		_loading = false
		_status_lbl.text = "Loading playlist…"
		_server.fetch_playlist_async(url)
	else:
		var vid_id := _extract_video_id(url)
		if vid_id.is_empty():
			_status_lbl.text = "Invalid YouTube URL."
			_playing = false
			_play_btn.text = "▶"
			return
		_playlist_mode = false
		_loading = not _server._connected
		_load_t  = 0.0
		_status_lbl.text = ""
		_server.open_video(vid_id)

func _is_playlist_url(url: String) -> bool:
	return "list=" in url and "start_radio=" in url

func _on_mute_toggled(pressed: bool) -> void:
	_muted = pressed
	_server.send({"cmd": "mute" if _muted else "unmute"})

func _on_volume_changed(val: float) -> void:
	_volume = val
	_server.send({"cmd": "volume", "v": val})

func _on_browser_connected() -> void:
	_loading = false
	_server.send({"cmd": "volume", "v": _volume})
	if _playing and not _playlist_mode:
		_server.send({"cmd": "play"})
		_status_lbl.text = ""

func _on_browser_disconnected() -> void:
	if _playing:
		_status_lbl.text = "Player disconnected."

func _on_start_failed(reason: String) -> void:
	_playing = false
	_loading = false
	_playlist_mode = false
	_play_btn.text = "▶"
	_status_lbl.text = reason

func _on_playlist_loaded(ids: Array) -> void:
	_playlist_mode = false
	_loading = false
	if ids.is_empty():
		_status_lbl.text = "Playlist failed to load."
		_playing = false
		_play_btn.text = "▶"
	else:
		_status_lbl.text = "%d songs queued" % ids.size()
		_playlist_pos = 0
		var titles := _server.playlist_titles
		if not titles.is_empty():
			_title_lbl.set_text(titles[0])
		_update_queue_btns()
		_server.send({"cmd": "volume", "v": _volume})
		_server.send({"cmd": "play"})

# ── Helpers ───────────────────────────────────────────────────────────────────

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
	const SPEED := 50.0
	const PAUSE := 2.0

	var _lbl:  Label
	var _ox    := 0.0
	var _dir   := -1.0
	var _wait  := PAUSE

	func _init() -> void:
		_lbl = Label.new()
		_lbl.position = Vector2.ZERO
		_lbl.clip_text = false
		_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
