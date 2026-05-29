# Music player widget — collapsed by default, expands on hover.
# Collapsed: title, seek bar, play/pause button, mute button.
# Expanded:  + [vol_icon | vol_slider | mute_btn] row, scrollable playlist.
class_name UserMusicPlayer
extends Panel

const PANEL_W       := 460.0
const COLLAPSED_H   := 200.0
const BTN_SIZE      := 50
const COLLAPSE_DELAY := 1.5
const SAVE_PATH     := "user://music_player.cfg"
const BTN_PATH    := "res://assets/sprites/ui/buttons/"
const YT_OEMBED   := "https://www.youtube.com/oembed?url=%s&format=json"
const YT_THUMB    := "https://img.youtube.com/vi/%s/mqdefault.jpg"

var max_expanded_h := 480.0
var _expanded      := false
var _hovering      := false
var _hover_timer   := 0.0
var _panel_style:  StyleBoxFlat

var _server: UserMusicServer
var _playing       := false
var _paused        := false
var _muted         := false
var _volume        := 1.0
var _loading       := false
var _load_t        := 0.0
var _playlist_mode := false
var _duration      := 0.0
var _cur_pos       := 0.0
var _playlist_pos  := -1
var _seeking       := false
var _upd_seek      := false

var _url_input:       LineEdit
var _title_lbl:       _MarqueeLabel
var _play_btn:        TextureButton
var _prev_btn:        TextureButton
var _next_btn:        TextureButton
var _shuffle_btn:     TextureButton
var _replay_btn:      TextureButton
var _mute_btn:        TextureButton
var _expand_btn:      TextureButton
var _vol_slider:      HSlider
var _vol_row:         HBoxContainer
var _ctrl_row:        HBoxContainer
var _ctrl_spacer:     Control
var _playlist_scroll: ScrollContainer
var _playlist_vbox:   VBoxContainer
var _status_lbl:      LineEdit
var _elapsed_lbl:     Label
var _remain_lbl:      Label
var _seek_bar:        HSlider

var _tex_play:           Texture2D
var _tex_pause:          Texture2D
var _tex_pause_pressed:  Texture2D
var _tex_prev:           Texture2D
var _tex_prev_pressed:   Texture2D
var _tex_next:           Texture2D
var _tex_next_pressed:   Texture2D
var _tex_shuffle:        Texture2D
var _tex_shuffle_pressed: Texture2D
var _tex_replay:         Texture2D
var _tex_replay_pressed: Texture2D
var _tex_vol:            Texture2D
var _tex_mute_pressed:   Texture2D
var _tex_expand:         Texture2D
var _tex_collapse:       Texture2D

var _http_title: HTTPRequest
var _http_thumb: HTTPRequest

signal thumbnail_ready(tex: ImageTexture)

var _youtube_mode           := false
var _game_music_was_playing := true
var _title_refresh_t        := 0.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_tex_play           = load(BTN_PATH + "music_play.png")
	_tex_pause          = load(BTN_PATH + "music_pause.png")
	_tex_pause_pressed  = load(BTN_PATH + "music_pause_pressed.png")
	_tex_prev           = load(BTN_PATH + "music_previous.png")
	_tex_prev_pressed   = load(BTN_PATH + "music_previous_pressed.png")
	_tex_next           = load(BTN_PATH + "music_next.png")
	_tex_next_pressed   = load(BTN_PATH + "music_next_pressed.png")
	_tex_shuffle        = load(BTN_PATH + "music_shuffle.png")
	_tex_shuffle_pressed = load(BTN_PATH + "music_shuffle_pressed.png")
	_tex_replay         = load(BTN_PATH + "music_replay.png")
	_tex_replay_pressed = load(BTN_PATH + "music_replay_pressed.png")
	_tex_vol            = load(BTN_PATH + "music_volume.png")
	_tex_mute_pressed   = load(BTN_PATH + "music_mute_pressed.png")
	_tex_expand         = load(BTN_PATH + "music_expand.png")
	_tex_collapse       = load(BTN_PATH + "music_collapse.png")

	custom_minimum_size = Vector2(PANEL_W, COLLAPSED_H)
	size = Vector2(PANEL_W, COLLAPSED_H)
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

	_http_thumb = HTTPRequest.new()
	add_child(_http_thumb)
	_http_thumb.request_completed.connect(_on_thumb_fetched)

	AudioManager.set_music_volume(_volume)
	_update_game_music_display()

	var saved_url := _load_url()
	if not saved_url.is_empty():
		_url_input.text = saved_url

func _process(delta: float) -> void:
	if _loading and not _playlist_mode:
		_load_t += delta
		_status_lbl.text = "Connecting... (%.0fs)" % _load_t

	if not _youtube_mode:
		_title_refresh_t += delta
		if _title_refresh_t >= 0.25:
			_title_refresh_t = 0.0
			_update_game_music_display()

	# Hover glow + auto-collapse
	var over := Rect2(Vector2.ZERO, Vector2(PANEL_W, size.y)).has_point(get_local_mouse_position())
	if over != _hovering:
		_hovering = over
		_hover_timer = 0.0
		_panel_style.bg_color = Color(0.11, 0.14, 0.20, 0.97) if over else Color(0.07, 0.09, 0.13, 0.95)
	if not _hovering and _expanded:
		_hover_timer += delta
		if _hover_timer >= COLLAPSE_DELAY:
			_hover_timer = 0.0
			_set_expanded(false)

	# Smooth height animation
	var target_h := max_expanded_h if _expanded else COLLAPSED_H
	if absf(size.y - target_h) > 0.5:
		var new_h := lerpf(size.y, target_h, delta * 14.0)
		custom_minimum_size.y = new_h
		size.y = new_h
	elif size.y != target_h:
		custom_minimum_size.y = target_h
		size.y = target_h

func _set_expanded(val: bool) -> void:
	_expanded = val
	_vol_row.visible = val
	_playlist_scroll.visible = val
	if val:
		_expand_btn.texture_normal = _tex_collapse
		_ctrl_spacer.visible = false
		_mute_btn.reparent(_vol_row)
		_expand_btn.reparent(_vol_row)
		_update_queue_scroll()
	else:
		_expand_btn.texture_normal = _tex_expand
		_mute_btn.reparent(_ctrl_row)
		_expand_btn.reparent(_ctrl_row)
		_ctrl_spacer.visible = true

func _update_play_icon() -> void:
	_play_btn.texture_normal = _tex_play if _playing else _tex_pause_pressed

func _update_game_music_display() -> void:
	var am := AudioManager
	var mp := am.music_player
	_playing = mp.playing and not mp.stream_paused
	_update_play_icon()
	if am._playlist.size() > 0:
		var path: String = am._playlist[am._playlist_index % am._playlist.size()]
		_title_lbl.set_text(path.get_file().get_basename())
	if mp.stream != null:
		var pos := mp.get_playback_position()
		var dur := mp.stream.get_length()
		if dur > 0.0:
			_elapsed_lbl.text = _fmt_time(pos)
			_remain_lbl.text = "-" + _fmt_time(dur - pos)
			if not _seeking:
				_upd_seek = true
				_seek_bar.value = pos / dur
				_upd_seek = false
			return
	_elapsed_lbl.text = "--:--"
	_remain_lbl.text = "--:--"

# ── Style ─────────────────────────────────────────────────────────────────────

func _apply_style() -> void:
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color            = Color(0.07, 0.09, 0.13, 0.95)
	_panel_style.border_width_left   = 1
	_panel_style.border_width_right  = 1
	_panel_style.border_width_top    = 1
	_panel_style.border_width_bottom = 1
	_panel_style.border_color        = Color(0.35, 0.45, 0.65, 0.9)
	_panel_style.corner_radius_top_left     = 6
	_panel_style.corner_radius_top_right    = 6
	_panel_style.corner_radius_bottom_left  = 6
	_panel_style.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", _panel_style)

# ── UI build ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 12
	vbox.offset_top    = 8
	vbox.offset_right  = -12
	vbox.offset_bottom = -6
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# ── Title marquee ─────────────────────────────────────────────
	_title_lbl = _MarqueeLabel.new()
	_title_lbl.set_text("—")
	_title_lbl.set_style(Color(0.85, 0.92, 1.0), 22)
	_title_lbl.custom_minimum_size = Vector2(0, 30)
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_title_lbl)

	# ── Time row: elapsed | seekbar | remaining ───────────────────
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 4)
	vbox.add_child(time_row)

	_elapsed_lbl = Label.new()
	_elapsed_lbl.text = "--:--"
	_elapsed_lbl.custom_minimum_size = Vector2(60, 0)
	_elapsed_lbl.add_theme_font_size_override("font_size", 17)
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
	_remain_lbl.custom_minimum_size = Vector2(68, 0)
	_remain_lbl.add_theme_font_size_override("font_size", 17)
	_remain_lbl.add_theme_color_override("font_color", Color(0.45, 0.55, 0.75))
	_remain_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_remain_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_row.add_child(_remain_lbl)

	# ── Mute button (shared; starts in ctrl_row, moves to vol_row on expand) ──
	_mute_btn = TextureButton.new()
	_mute_btn.texture_normal  = _tex_vol
	_mute_btn.texture_pressed = _tex_mute_pressed
	_mute_btn.toggle_mode = true
	_mute_btn.ignore_texture_size = true
	_mute_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_mute_btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_mute_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mute_btn.toggled.connect(_on_mute_toggled)

	# ── Volume row (expanded only): [vol_icon] [slider] [mute_btn] ──
	_vol_row = HBoxContainer.new()
	_vol_row.visible = false
	_vol_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_vol_row)

	var vol_icon := TextureRect.new()
	vol_icon.texture = _tex_vol
	vol_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vol_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vol_icon.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	vol_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vol_row.add_child(vol_icon)

	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 1.0
	_vol_slider.step      = 0.01
	_vol_slider.value     = 1.0
	_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol_slider.value_changed.connect(_on_volume_changed)
	_vol_row.add_child(_vol_slider)
	# _mute_btn will be reparented here when expanded

	# ── Playlist scroll (expanded only) ──────────────────────────
	_playlist_scroll = ScrollContainer.new()
	_playlist_scroll.visible = false
	_playlist_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_playlist_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_playlist_scroll)

	_playlist_vbox = VBoxContainer.new()
	_playlist_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playlist_vbox.add_theme_constant_override("separation", 2)
	_playlist_scroll.add_child(_playlist_vbox)

	# ── URL input ─────────────────────────────────────────────────
	_url_input = LineEdit.new()
	_url_input.placeholder_text = "Paste YouTube link…"
	_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_input.add_theme_color_override("font_placeholder_color", Color(0.4, 0.4, 0.4))
	_url_input.add_theme_font_size_override("font_size", 18)
	var url_s := StyleBoxFlat.new()
	url_s.bg_color = Color(0.1, 0.12, 0.16, 1.0)
	url_s.border_width_left = 1; url_s.border_width_right  = 1
	url_s.border_width_top  = 1; url_s.border_width_bottom = 1
	url_s.border_color = Color(0.75, 0.78, 0.82, 0.9)
	url_s.corner_radius_top_left     = 4; url_s.corner_radius_top_right    = 4
	url_s.corner_radius_bottom_left  = 4; url_s.corner_radius_bottom_right = 4
	_url_input.add_theme_stylebox_override("normal",    url_s)
	_url_input.add_theme_stylebox_override("focus",     url_s)
	_url_input.add_theme_stylebox_override("read_only", url_s)
	_url_input.text_submitted.connect(_on_url_submitted)
	vbox.add_child(_url_input)

	# ── Controls row: [prev][play][next][shuffle][replay][spacer][mute] ──
	var btn_gap := Control.new()
	btn_gap.custom_minimum_size = Vector2(0, 5)
	vbox.add_child(btn_gap)

	_ctrl_row = HBoxContainer.new()
	_ctrl_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ctrl_row.add_theme_constant_override("separation", 6)
	vbox.add_child(_ctrl_row)

	_prev_btn = TextureButton.new()
	_prev_btn.texture_normal  = _tex_prev
	_prev_btn.texture_pressed = _tex_prev_pressed
	_prev_btn.ignore_texture_size = true
	_prev_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_prev_btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_prev_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prev_btn.pressed.connect(_on_prev_pressed)
	_ctrl_row.add_child(_prev_btn)

	_play_btn = TextureButton.new()
	_play_btn.texture_normal = _tex_play
	_play_btn.ignore_texture_size = true
	_play_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_play_btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_play_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_play_btn.pressed.connect(_on_play_pressed)
	_ctrl_row.add_child(_play_btn)

	_next_btn = TextureButton.new()
	_next_btn.texture_normal  = _tex_next
	_next_btn.texture_pressed = _tex_next_pressed
	_next_btn.ignore_texture_size = true
	_next_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_next_btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_next_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_next_btn.pressed.connect(_on_next_pressed)
	_ctrl_row.add_child(_next_btn)

	_shuffle_btn = TextureButton.new()
	_shuffle_btn.texture_normal  = _tex_shuffle
	_shuffle_btn.texture_pressed = _tex_shuffle_pressed
	_shuffle_btn.ignore_texture_size = true
	_shuffle_btn.toggle_mode = true
	_shuffle_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_shuffle_btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_shuffle_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_shuffle_btn.toggled.connect(_on_shuffle_toggled)
	_ctrl_row.add_child(_shuffle_btn)

	_replay_btn = TextureButton.new()
	_replay_btn.texture_normal  = _tex_replay
	_replay_btn.texture_pressed = _tex_replay_pressed
	_replay_btn.ignore_texture_size = true
	_replay_btn.toggle_mode = true
	_replay_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_replay_btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_replay_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_replay_btn.toggled.connect(_on_replay_toggled)
	_ctrl_row.add_child(_replay_btn)

	_ctrl_spacer = Control.new()
	_ctrl_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ctrl_row.add_child(_ctrl_spacer)

	_expand_btn = TextureButton.new()
	_expand_btn.texture_normal = _tex_expand
	_expand_btn.ignore_texture_size = true
	_expand_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_expand_btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	_expand_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_expand_btn.pressed.connect(_on_expand_pressed)

	_ctrl_row.add_child(_mute_btn)    # mute starts here in collapsed state
	_ctrl_row.add_child(_expand_btn)  # expand/collapse always beside mute

	# ── Status ────────────────────────────────────────────────────
	_status_lbl = LineEdit.new()
	_status_lbl.text = ""
	_status_lbl.editable = false
	_status_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_status_lbl.add_theme_font_size_override("font_size", 16)
	var es := StyleBoxEmpty.new()
	_status_lbl.add_theme_stylebox_override("normal",    es)
	_status_lbl.add_theme_stylebox_override("read_only", es)
	_status_lbl.add_theme_stylebox_override("focus",     es)
	vbox.add_child(_status_lbl)

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
	if dur > 0.0:
		_remain_lbl.text = "-" + _fmt_time(dur - _cur_pos)
		if not _seeking:
			_upd_seek = true
			_seek_bar.value = _cur_pos / dur
			_upd_seek = false

func _on_seek_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_seeking = true
		else:
			_seeking = false
			if _youtube_mode:
				if _duration > 0.0:
					_server.seek_to(_seek_bar.value * _duration)
			else:
				var mp := AudioManager.music_player
				if mp.stream != null:
					var dur := mp.stream.get_length()
					if dur > 0.0:
						mp.seek(_seek_bar.value * dur)

func _on_seek_changed(val: float) -> void:
	if _upd_seek:
		return
	var dur := _duration
	if not _youtube_mode:
		var mp := AudioManager.music_player
		if mp.stream != null:
			dur = mp.stream.get_length()
	if dur <= 0.0:
		return
	_elapsed_lbl.text = _fmt_time(val * dur)
	_remain_lbl.text  = "-" + _fmt_time(dur - val * dur)

func _fmt_time(secs: float) -> String:
	if secs < 0.0:
		secs = 0.0
	var s := int(secs)
	return "%d:%02d" % [s / 60, s % 60]

# ── Playlist ──────────────────────────────────────────────────────────────────

func _on_playlist_pos_changed(idx: int) -> void:
	_playlist_pos = idx
	_duration = 0.0
	_cur_pos  = 0.0
	_elapsed_lbl.text = "--:--"
	_remain_lbl.text  = "--:--"
	_seek_bar.value   = 0.0
	if idx >= 0 and idx < _server.playlist_ids.size():
		_fetch_thumbnail(_server.playlist_ids[idx])
		_fetch_title("https://www.youtube.com/watch?v=" + _server.playlist_ids[idx])
	if _expanded:
		_update_queue_scroll()

func _update_queue_scroll() -> void:
	for c in _playlist_vbox.get_children():
		c.free()
	var t_arr := _server.playlist_titles
	var i_arr := _server.playlist_ids
	for si in range(_playlist_pos + 1, i_arr.size()):
		var title: String = t_arr[si] if si < t_arr.size() else i_arr[si]

		var btn := Button.new()
		btn.flat = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 26)

		var normal_s := StyleBoxFlat.new()
		normal_s.bg_color = Color(0, 0, 0, 0)
		var hover_s := StyleBoxFlat.new()
		hover_s.bg_color = Color(0.2, 0.35, 0.6, 0.35)
		hover_s.corner_radius_top_left     = 3
		hover_s.corner_radius_top_right    = 3
		hover_s.corner_radius_bottom_left  = 3
		hover_s.corner_radius_bottom_right = 3
		btn.add_theme_stylebox_override("normal",  normal_s)
		btn.add_theme_stylebox_override("hover",   hover_s)
		btn.add_theme_stylebox_override("pressed", hover_s)
		btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())

		var marquee := _MarqueeLabel.new()
		marquee.hover_only = true
		marquee.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		marquee.set_text("%d.  %s" % [si + 1, title])
		marquee.set_style(Color(0.5, 0.62, 0.82, 0.85), 17)
		marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(marquee)

		btn.mouse_entered.connect((func(m): m.set_hovered(true)).bind(marquee))
		btn.mouse_exited.connect((func(m): m.set_hovered(false)).bind(marquee))
		btn.pressed.connect((func(idx): _on_playlist_btn_pressed(idx)).bind(si))

		_playlist_vbox.add_child(btn)

func _on_playlist_btn_pressed(abs_idx: int) -> void:
	if abs_idx < _server.playlist_ids.size():
		var titles := _server.playlist_titles
		_title_lbl.set_text(titles[abs_idx] if abs_idx < titles.size() else _server.playlist_ids[abs_idx])
		_server.skip_to(abs_idx)

# ── URL / playback callbacks ──────────────────────────────────────────────────

func _on_url_submitted(url: String) -> void:
	url = url.strip_edges()
	if url.is_empty():
		return
	_url_input.text = url
	_save_url(url)
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

func _fetch_thumbnail(video_id: String) -> void:
	if video_id.is_empty():
		return
	_http_thumb.cancel_request()
	_http_thumb.request(YT_THUMB % video_id)

func _on_thumb_fetched(_res: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var img := Image.new()
	if img.load_jpg_from_buffer(body) != OK:
		return
	var w := img.get_width()
	var h := img.get_height()
	var sq := mini(w, h)
	img = img.get_region(Rect2i((w - sq) / 2, (h - sq) / 2, sq, sq))
	thumbnail_ready.emit(ImageTexture.create_from_image(img))

func _on_play_pressed() -> void:
	if _youtube_mode:
		if _playing:
			_playing = false
			_paused  = true
			_update_play_icon()
			_server.send({"cmd": "pause"})
		elif _paused:
			_playing = true
			_paused  = false
			_update_play_icon()
			_server.send({"cmd": "play"})
		else:
			var url := _url_input.text.strip_edges()
			_fetch_title(url)
			_play_url(url)
	else:
		var mp := AudioManager.music_player
		if mp.playing and not mp.stream_paused:
			mp.stream_paused = true
			_playing = false
			_update_play_icon()
			_status_lbl.text = "Paused"
		else:
			mp.stream_paused = false
			if not mp.playing:
				AudioManager._play_current_track()
			_playing = true
			_update_play_icon()
			_status_lbl.text = ""

func _play_url(url: String) -> void:
	if url.is_empty():
		_status_lbl.text = "Enter a YouTube URL first."
		return
	var mp := AudioManager.music_player
	_game_music_was_playing = mp.playing and not mp.stream_paused
	mp.stream_paused = true
	_youtube_mode = true
	_paused  = false
	_playing = true
	_update_play_icon()
	_duration = 0.0
	_cur_pos  = 0.0
	_elapsed_lbl.text = "--:--"
	_remain_lbl.text  = "--:--"
	_seek_bar.value   = 0.0
	_playlist_pos = -1
	if _is_playlist_url(url):
		_playlist_mode = true
		_status_lbl.text = "Loading playlist…"
		var first_vid := _extract_video_id(url)
		if not first_vid.is_empty():
			_loading = not _server._connected
			_load_t  = 0.0
			_fetch_thumbnail(first_vid)
			_fetch_title("https://www.youtube.com/watch?v=" + first_vid)
			_server.open_video(first_vid)
		else:
			_loading = false
		_server.fetch_playlist_async(url, not first_vid.is_empty())
	else:
		var vid_id := _extract_video_id(url)
		if vid_id.is_empty():
			_status_lbl.text = "Invalid YouTube URL."
			_playing = false
			_update_play_icon()
			return
		_playlist_mode = false
		_loading = not _server._connected
		_load_t  = 0.0
		_status_lbl.text = ""
		_fetch_thumbnail(vid_id)
		_server.open_video(vid_id)

func _is_playlist_url(url: String) -> bool:
	return "list=" in url

func _on_expand_pressed() -> void:
	_set_expanded(not _expanded)

func _on_mute_toggled(pressed: bool) -> void:
	_muted = pressed
	_server.send({"cmd": "mute" if _muted else "unmute"})
	if pressed:
		AudioManager.music_player.volume_db = -80.0
	else:
		AudioManager.set_music_volume(_volume)

func _on_prev_pressed() -> void:
	if _youtube_mode:
		if _playlist_pos > 0:
			_server.skip_to(_playlist_pos - 1)
	else:
		AudioManager.prev_track()
		_update_game_music_display()

func _on_next_pressed() -> void:
	if _youtube_mode:
		var next := _playlist_pos + 1
		if next < _server.playlist_ids.size():
			_server.skip_to(next)
	else:
		AudioManager.next_track()
		_update_game_music_display()

func _on_shuffle_toggled(pressed: bool) -> void:
	_server.send({"cmd": "shuffle_on" if pressed else "shuffle_off"})
	if not _youtube_mode:
		AudioManager.set_shuffle(pressed)

func _on_replay_toggled(pressed: bool) -> void:
	_server.send({"cmd": "loop_on" if pressed else "loop_off"})
	if not _youtube_mode:
		AudioManager.set_loop(pressed)

func _on_volume_changed(val: float) -> void:
	_volume = val
	_server.send({"cmd": "volume", "v": val})
	if not _muted:
		AudioManager.set_music_volume(val)

func _on_browser_connected() -> void:
	_loading = false
	_server.send({"cmd": "volume", "v": _volume})
	if _playing:
		_server.send({"cmd": "play"})
		if not _playlist_mode:
			_status_lbl.text = ""

func _on_browser_disconnected() -> void:
	if _playing:
		_status_lbl.text = "Player disconnected."
	_youtube_mode = false
	_playing = false
	_paused  = false
	_update_play_icon()
	var mp := AudioManager.music_player
	if _game_music_was_playing:
		mp.stream_paused = false
		if not mp.playing:
			AudioManager._play_current_track()
	_update_game_music_display()

func _on_start_failed(reason: String) -> void:
	_playing = false
	_loading = false
	_playlist_mode = false
	_youtube_mode  = false
	_update_play_icon()
	_status_lbl.text = reason
	var mp := AudioManager.music_player
	if _game_music_was_playing:
		mp.stream_paused = false
		if not mp.playing:
			AudioManager._play_current_track()
	_update_game_music_display()

func _on_playlist_loaded(ids: Array) -> void:
	_playlist_mode = false
	_loading = false
	if ids.is_empty():
		_status_lbl.text = "Playlist failed to load."
		if not _playing:
			_update_play_icon()
	else:
		_status_lbl.text = "%d songs queued" % ids.size()
		_playlist_pos = 0
		var titles := _server.playlist_titles
		if not titles.is_empty():
			_title_lbl.set_text(titles[0])
		if _expanded:
			_update_queue_scroll()
		_server.send({"cmd": "volume", "v": _volume})

# ── Helpers ───────────────────────────────────────────────────────────────────

func _save_url(url: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("music", "last_url", url)
	cfg.save(SAVE_PATH)

func _load_url() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return cfg.get_value("music", "last_url", "")
	return ""

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

	var hover_only := false

	var _lbl:    Label
	var _ox      := 0.0
	var _dir     := -1.0
	var _wait    := PAUSE
	var _hovered := false

	func _init() -> void:
		_lbl = Label.new()
		_lbl.position = Vector2.ZERO
		_lbl.clip_text = false
		_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		clip_contents = true
		add_child(_lbl)
		custom_minimum_size.y = max(18.0, _lbl.get_minimum_size().y)

	func set_hovered(h: bool) -> void:
		_hovered = h
		if not h:
			_reset_scroll()

	func _reset_scroll() -> void:
		_ox   = 0.0
		_dir  = -1.0
		_wait = PAUSE
		if is_node_ready():
			_lbl.position.x = 0.0

	func set_text(t: String) -> void:
		_lbl.text = t
		_reset_scroll()

	func set_style(color: Color, font_size: int) -> void:
		_lbl.add_theme_color_override("font_color", color)
		_lbl.add_theme_font_size_override("font_size", font_size)

	func _process(delta: float) -> void:
		if hover_only and not _hovered:
			return
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
