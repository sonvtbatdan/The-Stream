extends Panel

signal message_submitted(text: String)

const MODEL_PATH      := "res://addons/godot_whisper/models/ggml-small.bin"
const AUDIO_CONFIG_PATH := "user://audio_config.cfg"
const CHAT_MEMORY_PATH  := "user://chat_memory.cfg"
const SCAN_WAIT_SEC   := 2.5
const SIGNAL_THRESHOLD := 0.005


@onready var bot_response: RichTextLabel = $VBox/BotResponseFrame/Scroll/BotResponseLabel
@onready var chat_input: LineEdit        = $VBox/InputFrame/HBox/ChatInput
@onready var mic_btn: Button             = $VBox/InputFrame/HBox/MicBtn
@onready var send_btn: Button            = $VBox/InputFrame/HBox/SendBtn
@onready var bot_response_frame: Panel   = $VBox/BotResponseFrame
@onready var input_frame: Panel          = $VBox/InputFrame
var _stt: Node = null
var _stt_ready  := false
var _recording  := false

# ── Chat memory ───────────────────────────────────────────────────────────────
var _mem_notes:   String = ""
var _mem_summary: String = ""

# ── Device auto-scan state ────────────────────────────────────────────────────
var _scan_active  := false
var _scan_devices: Array = []
var _scan_idx     := 0
var _scan_wait    := 0.0
var _bg_scan      := false

func _ready() -> void:
	_apply_style()
	_apply_inner_style(bot_response_frame)
	_apply_inner_style(input_frame)
	_setup_stt()
	call_deferred("_auto_scan_if_needed")
	chat_input.text_submitted.connect(_on_send)
	send_btn.pressed.connect(func(): _on_send(chat_input.text))
	mic_btn.pressed.connect(_toggle_recording)
	_load_memory()
	bot_response.selection_enabled = true

func _auto_scan_if_needed() -> void:
	if not _stt_ready or not _load_saved_device().is_empty():
		return
	print("MIC: no saved device — starting background scan")
	_bg_scan   = true
	_recording = true
	_stt.set("recording", true)
	_start_device_scan()

func _process(delta: float) -> void:
	if not _scan_active or not _recording:
		return
	_scan_wait += delta
	if _scan_wait >= SCAN_WAIT_SEC:
		_scan_wait = 0.0
		_scan_try_next()

# ── Styles ────────────────────────────────────────────────────────────────────

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.06, 0.08, 0.12, 0.88)
	s.border_width_left   = 2; s.border_width_right  = 2
	s.border_width_top    = 2; s.border_width_bottom = 2
	s.border_color        = Color(0.3, 0.4, 0.6, 0.9)
	s.corner_radius_top_left     = 8; s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8; s.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", s)

func _apply_inner_style(p: Panel) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.04, 0.05, 0.09, 0.95)
	s.border_width_left   = 1; s.border_width_right  = 1
	s.border_width_top    = 1; s.border_width_bottom = 1
	s.border_color        = Color(0.2, 0.3, 0.5, 0.7)
	s.corner_radius_top_left     = 4; s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4; s.corner_radius_bottom_right = 4
	p.add_theme_stylebox_override("panel", s)

func set_edit_mode(editing: bool) -> void:
	mouse_default_cursor_shape = CURSOR_MOVE if editing else CURSOR_ARROW
	if editing:
		var s := StyleBoxFlat.new()
		s.bg_color            = Color(0.06, 0.08, 0.12, 0.88)
		s.border_width_left   = 2; s.border_width_right  = 2
		s.border_width_top    = 2; s.border_width_bottom = 2
		s.border_color        = Color(1.0, 0.7, 0.2, 1.0)
		s.corner_radius_top_left     = 8; s.corner_radius_top_right    = 8
		s.corner_radius_bottom_left  = 8; s.corner_radius_bottom_right = 8
		add_theme_stylebox_override("panel", s)
	else:
		_apply_style()

# ── Game context ──────────────────────────────────────────────────────────────

func _build_context() -> String:
	var now    := Time.get_datetime_dict_from_system()
	var time_s := "%02d:%02d" % [now.hour, now.minute]
	var date_s := "%02d/%02d/%d" % [now.day, now.month, now.year]

	var gm := GameManager
	var um := UpgradeManager
	var em := EquipmentManager
	var am := AudioManager

	var song_name  := "none"
	var song_pos_s := ""
	if am._playlist.size() > 0:
		var path: String = am._playlist[am._playlist_index % am._playlist.size()]
		song_name = path.get_file().get_basename()
		if am.music_player.stream != null:
			var _pos := am.music_player.get_playback_position()
			var _dur := am.music_player.stream.get_length()
			var _rem := _dur - _pos
			song_pos_s = " [%d:%02d elapsed, %d:%02d remaining, total %d:%02d]" % [
				int(_pos)/60, int(_pos)%60, int(_rem)/60, int(_rem)%60, int(_dur)/60, int(_dur)%60
			]

	var upgrades_parts: Array[String] = []
	for id in um.UPGRADES:
		var count := um.get_owned_count(id)
		if count > 0:
			upgrades_parts.append("%s x%d" % [um.UPGRADES[id]["name"], count])
	var upgrades_s := ", ".join(upgrades_parts) if upgrades_parts.size() > 0 else "none"

	var equip_parts: Array[String] = []
	for id in em.ITEMS:
		if em.get_owned(id) > 0:
			equip_parts.append(em.ITEMS[id]["name"])
	var equip_s := ", ".join(equip_parts) if equip_parts.size() > 0 else "none"

	var total_vps := int(gm.vps + gm.auto_click_rate * gm.click_power)

	var session_s := ""
	var clock := _get_weather_clock()
	if clock:
		var el := clock.get_session_elapsed()
		var re := clock.get_session_remaining()
		session_s = "%d:%02d elapsed, %d:%02d remaining (planned %d min)" % [
			int(el)/60, int(el)%60, int(re)/60, int(re)%60, int(clock.session_duration/60)
		]

	var todo_s := "empty"
	var todo_node := _get_todo_list()
	if todo_node:
		var tasks := todo_node.get_tasks()
		var tparts: Array[String] = []
		for i in tasks.size():
			if not tasks[i].is_empty():
				tparts.append("[%d] %s" % [i + 1, tasks[i]])
		if tparts.size() > 0:
			todo_s = "\n".join(tparts)

	var mem_s := ""
	if not _mem_summary.is_empty():
		mem_s = "\nPrevious session summary: " + _mem_summary
	if not _mem_notes.is_empty():
		mem_s += "\nUser notes: " + _mem_notes

	return """You are Lisa, a 22-year-old female hardcore streamer and the AI assistant in a streaming simulation game called "The Stream". You are energetic, playful, and love chatting with your audience. Always answer in the same language the user writes in (Vietnamese when they write in Vietnamese).

PERSONALITY: Witty, Gen-Z, loves to banter, uses streamer slang naturally, reacts with hype or sarcasm depending on context.

EXPERTISE (answer confidently):
- League of Legends: current meta, champions, abilities, item builds, roles, in-game terms (gank, farm, poke, peel, check map, baron call, etc.)
- Anime — Dragon Ball: Son Goku, Vegeta, all Super Saiyan forms (SSJ1/2/3/4, Blue, Ultra Instinct), story arcs, power scaling debates
- Anime — Sailor Moon: Usagi Tsukino, the Sailor Senshi, 90s anime aesthetic and nostalgia
- Streaming tech: OBS, Streamlabs, Stream Deck, ring lights, cameras, microphones, fixing frame drops, audio sync, stream lag
- Internet culture: latest memes, Gen-Z slang, Twitch/YouTube streaming community, how to hype up chat

CANNOT ANSWER — stay in character, laugh it off and redirect:
- Advanced chemistry, organic reactions, quantum mechanics, nuclear physics formulas
- Programming at code level: data structures, backend architecture, GPU rendering pipelines, low-level optimization
- Medical advice, clinical diagnosis, drug interactions
- Macroeconomics, central bank policy, advanced financial analysis
- Ancient history details, classical Western/Eastern philosophy, academic sociology theories

Current time: %s | Date: %s
Game stats: Views=%s | Subscribers=%s | Cash=$%s | Click power=%sx | VPS=%s/s
Now playing: %s
Owned upgrades: %s
Owned equipment: %s
Stream session: %s
To-Do List: %s%s

REMINDER RULE: Include [REMINDER:N:message] (N = minutes) when user asks for a reminder. Also, when adding a task that mentions a specific time (e.g., "stream 8pm", "họp lúc 3 giờ"), calculate minutes from now and automatically include a matching [REMINDER:N:message].

COMMAND RULES — you MUST embed these exact tags in your response when the action is requested. They are invisible to the user (stripped before display) but execute immediately. NEVER invent your own tag formats like [TASK 1] or similar.

[CMD:music_seek:SEC] — seek music to SEC seconds
[CMD:music_next] — skip to next track
[CMD:music_pause] — toggle play/pause
[CMD:music_volume:LEVEL] — set volume 0.0–1.0
[CMD:session_set:MINUTES] — set session duration
[CMD:session_extend:MINUTES] — extend session
[CMD:session_reset] — reset session timer
[CMD:todo_add:TEXT] — add task. Example: user says "thêm task học bài" → you write "[CMD:todo_add:học bài]" somewhere in your reply.
[CMD:todo_set:INDEX:TEXT] — overwrite task at slot 1–4. Example: "[CMD:todo_set:2:họp nhóm lúc 3h]"
[CMD:todo_clear:INDEX] — delete task at slot 1–4. Example: "[CMD:todo_clear:1]"

Only emit a command when the user explicitly requests that action.""" % [
		time_s, date_s,
		gm.format_count(gm.views), gm.format_count(gm.subs),
		gm.format_count(int(gm.cash)), str(gm.click_power),
		gm.format_count(total_vps), song_name + song_pos_s, upgrades_s, equip_s,
		session_s, todo_s, mem_s
	]

# ── Reminder / command parser ─────────────────────────────────────────────────

func _process_bot_text(text: String) -> String:
	var r_rem := RegEx.new()
	r_rem.compile("\\[REMINDER:(\\d+):([^\\]]+)\\]")
	for m in r_rem.search_all(text):
		_set_reminder(m.get_string(1).to_int(), m.get_string(2).strip_edges())
		text = text.replace(m.get_string(), "")
	var r_cmd := RegEx.new()
	r_cmd.compile("\\[CMD:(\\w+)(?::([^\\]]+))?\\]")
	for m in r_cmd.search_all(text):
		_execute_cmd(m.get_string(1), m.get_string(2).strip_edges())
		text = text.replace(m.get_string(), "")
	return text.strip_edges()

func _get_weather_clock() -> UserWeatherClock:
	return get_parent().get_node_or_null("UserPanel/Panel/UserWeatherClock") as UserWeatherClock

func _get_todo_list() -> UserTodoList:
	return get_parent().get_node_or_null("UserPanel/Panel/UserTodoList") as UserTodoList

func _execute_cmd(action: String, param: String) -> void:
	var mp := AudioManager.music_player
	match action:
		"music_seek":
			if mp.stream != null:
				mp.seek(clampf(param.to_float(), 0.0, mp.stream.get_length()))
		"music_next":
			AudioManager.next_track()
		"music_pause":
			if mp.stream_paused:
				mp.stream_paused = false
			elif mp.playing:
				mp.stream_paused = true
		"music_volume":
			AudioManager.set_music_volume(clampf(param.to_float(), 0.0, 1.0))
		"session_set":
			var clock := _get_weather_clock()
			if clock and param.to_float() > 0.0:
				clock.session_duration = param.to_float() * 60.0
				clock.reset_session()
		"session_extend":
			var clock := _get_weather_clock()
			if clock and param.to_float() > 0.0:
				clock.extend_session(param.to_float() * 60.0)
		"session_reset":
			var clock := _get_weather_clock()
			if clock:
				clock.reset_session()
		"todo_add":
			var todo := _get_todo_list()
			if todo and not param.is_empty():
				todo.add_task(param)
		"todo_set":
			var todo := _get_todo_list()
			if todo and ":" in param:
				var idx := param.get_slice(":", 0).to_int() - 1
				var txt := param.substr(param.find(":") + 1).strip_edges()
				if not txt.is_empty():
					todo.set_task(idx, txt)
		"todo_clear":
			var todo := _get_todo_list()
			if todo:
				todo.clear_task(param.to_int() - 1)

func _set_reminder(minutes: int, message: String) -> void:
	var t := Timer.new()
	t.wait_time = float(max(minutes, 1)) * 60.0
	t.one_shot  = true
	add_child(t)
	t.timeout.connect(func():
		_append_message("Lisa", "⏰ " + message, Color(1.0, 1.0, 0.3))
		t.queue_free()
	)
	t.start()

# ── Device config persistence ─────────────────────────────────────────────────

func _load_saved_device() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(AUDIO_CONFIG_PATH) != OK:
		return ""
	var saved: String = cfg.get_value("audio", "input_device", "")
	if saved.is_empty() or not AudioServer.get_input_device_list().has(saved):
		return ""
	return saved

func _save_device(device: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "input_device", device)
	cfg.save(AUDIO_CONFIG_PATH)

# ── Record bus helpers ────────────────────────────────────────────────────────

func _rebuild_record_bus() -> void:
	var idx := AudioServer.get_bus_index("Record")
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Record")
		AudioServer.set_bus_mute(idx, true)
	else:
		for i in range(AudioServer.get_bus_effect_count(idx) - 1, -1, -1):
			AudioServer.remove_bus_effect(idx, i)
	AudioServer.add_bus_effect(idx, AudioEffectCapture.new())

# ── Whisper STT ───────────────────────────────────────────────────────────────

func _setup_stt() -> void:
	if not ClassDB.class_exists("SpeechToText"):
		mic_btn.tooltip_text = "Whisper plugin not active"
		return
	var model: Resource = ResourceLoader.load(MODEL_PATH, "WhisperResource")
	if model == null:
		model = load(MODEL_PATH)
	if model == null:
		mic_btn.tooltip_text = "Whisper model not loaded"
		return
	var saved := _load_saved_device()
	if not saved.is_empty():
		AudioServer.input_device = saved
	_rebuild_record_bus()
	_stt = load("res://addons/godot_whisper/capture_stream_to_text.gd").new()
	_stt.set("language_model", model)
	_stt.set("record_bus", "Record")
	_stt.set("recording", false)
	_stt.set("emit_partial_results", true)
	_stt.connect("transcribed_msg", _on_transcribed)
	_stt.connect("status_changed", _on_stt_status)
	_stt.connect("input_level_changed", _on_stt_level)
	add_child(_stt)
	_stt_ready = true
	mic_btn.tooltip_text = "Click: record voice (Whisper)"

func _toggle_recording() -> void:
	if not _stt_ready:
		return
	if _bg_scan:
		_bg_scan = false
		_scan_active = false
	_recording = not _recording
	_stt.set("recording", _recording)
	if _recording:
		mic_btn.text     = "⏹"
		mic_btn.modulate = Color.RED
		chat_input.placeholder_text = "Listening..."
		if _load_saved_device().is_empty():
			_start_device_scan()
	else:
		mic_btn.text     = "🎤"
		mic_btn.modulate = Color.WHITE
		chat_input.placeholder_text = "Type a message..."
		_scan_active = false

func _on_transcribed(is_complete: bool, text: String) -> void:
	if _bg_scan:
		return
	text = text.strip_edges()
	if text.is_empty():
		return
	if is_complete:
		_scan_active = false
		chat_input.text = text
		chat_input.placeholder_text = "Type a message..."
		chat_input.grab_focus()
		_recording = false
		_stt.set("recording", false)
		mic_btn.text     = "🎤"
		mic_btn.modulate = Color.WHITE
	else:
		chat_input.placeholder_text = text + "..."

# ── Device auto-scan ──────────────────────────────────────────────────────────

func _start_device_scan() -> void:
	_scan_devices = AudioServer.get_input_device_list()
	_scan_idx    = 0
	_scan_wait   = 0.0
	_scan_active = true
	_scan_apply_current()

func _scan_try_next() -> void:
	_scan_idx += 1
	if _scan_idx >= _scan_devices.size():
		_scan_active = false
		if _bg_scan:
			_bg_scan   = false
			_recording = false
			_stt.set("recording", false)
		else:
			chat_input.placeholder_text = "No active mic found"
			_append_message("Lisa", "Không tìm thấy micro nào có tín hiệu.", Color(1.0, 0.6, 0.3))
		return
	_scan_apply_current()

func _scan_apply_current() -> void:
	var dev: String = _scan_devices[_scan_idx]
	AudioServer.input_device = dev
	_rebuild_record_bus()
	if _stt and _recording:
		_stt.call("restart_recording")
	if not _bg_scan:
		var short := dev.left(30) + ("…" if dev.length() > 30 else "")
		chat_input.placeholder_text = "[%d/%d] Testing: %s" % [_scan_idx+1, _scan_devices.size(), short]

func _on_stt_status(message: String, _is_error: bool) -> void:
	if not _recording:
		return
	if not _scan_active and ("signal is silent" in message or "No audio frames" in message):
		_start_device_scan()
		return
	if not _scan_active and not _bg_scan:
		chat_input.placeholder_text = message

func _on_stt_level(peak: float, _rms: float) -> void:
	if not _recording:
		return
	if _scan_active:
		if peak > SIGNAL_THRESHOLD:
			var found: String = AudioServer.input_device
			_scan_active = false
			_save_device(found)
			if _bg_scan:
				_bg_scan   = false
				_recording = false
				_stt.set("recording", false)
			else:
				var short := found.left(30) + ("…" if found.length() > 30 else "")
				_append_message("Lisa", "Micro tự động phát hiện: %s" % short, Color(0.5, 1.0, 0.5))
		return
	var bars    := int(clamp(peak * 10.0, 0.0, 10.0))
	var bar_str := "█".repeat(bars) + "░".repeat(10 - bars)
	chat_input.placeholder_text = bar_str + " %.0f%%" % (peak * 100.0)

# ── Send & Gemini ─────────────────────────────────────────────────────────────

func _on_send(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	_append_message("You", text, Color(0.63, 0.78, 1.0))
	chat_input.clear()
	chat_input.placeholder_text = "Type a message..."
	emit_signal("message_submitted", text)

# ── Chat memory ───────────────────────────────────────────────────────────────

func _load_memory() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CHAT_MEMORY_PATH) != OK:
		return
	_mem_notes   = cfg.get_value("identity", "notes",        "")
	_mem_summary = cfg.get_value("history",  "last_summary", "")

func _save_memory() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CHAT_MEMORY_PATH)
	cfg.set_value("identity", "notes",        _mem_notes)
	cfg.set_value("history",  "last_summary", _mem_summary)
	cfg.save(CHAT_MEMORY_PATH)

func save_chat_summary() -> void:
	var text := bot_response.get_parsed_text().strip_edges()
	if text.is_empty():
		return
	if text.length() > 800:
		text = text.right(800)
	_mem_summary = "[%s]\n%s" % [Time.get_datetime_string_from_system(), text]
	_save_memory()

func update_memory_notes(notes: String) -> void:
	_mem_notes = notes
	_save_memory()

func get_memory_notes() -> String:
	return _mem_notes

# ── Display ───────────────────────────────────────────────────────────────────

func _append_message(sender: String, text: String, color: Color) -> void:
	var hex := "#%02x%02x%02x" % [int(color.r*255), int(color.g*255), int(color.b*255)]
	bot_response.append_text("\n[color=%s][b]%s:[/b][/color] %s" % [hex, sender, text])
	_scroll_to_bottom()

func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	var scroll := $VBox/BotResponseFrame/Scroll as ScrollContainer
	if scroll:
		scroll.scroll_vertical = 999999
