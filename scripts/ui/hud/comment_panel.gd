extends PanelContainer

@onready var scroll: ScrollContainer = %ScrollContainer
@onready var comment_list: VBoxContainer = %CommentList

const MAX_COMMENTS := 30
const NEGATIVE_LIFETIME := 10.0

const POSITIVE_COMMENTS := [
	"poggers", "LUL", "ez clap", "GG", "W",
	"let's go!", "nice stream", "W streamer", "sub hype", "clip it",
	"PogChamp", "Pog", "KEKW", "hype", "insane",
	"+1", "nice one", "banger", "keep going", "love it",
]

const NEGATIVE_COMMENTS := [
	"zzz", "boring", "unsubbing", "trash", "bad stream",
	"F", "L", "nope", "meh", "yikes",
	"cringe", "ratio", "not funny", "mid", "reported",
]

var _clicked_positive: int = 0
var _ai_queue: Array = []
var _http: HTTPRequest = null
var _fetching := false
var _pool: Array[Button] = []

var _comment_font: SystemFont = null

var _tick := 0.0
var _comment_acc: float = 0.0
var _spawn_interval: float = 2.0

func _ready() -> void:
	_apply_style()
	_comment_font = SystemFont.new()
	_comment_font.font_names = PackedStringArray(["Myriad Pro"])
	GameManager.views_changed.connect(_on_views_changed)
	_setup_http()

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.06, 0.08, 0.12, 0.88)
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_width_top    = 2
	s.border_width_bottom = 2
	s.border_color        = Color(0.3, 0.4, 0.6, 0.9)
	s.corner_radius_top_left     = 8
	s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8
	s.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", s)

func _setup_http() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	_fetch_ai_comments()

func _fetch_ai_comments() -> void:
	if _fetching:
		return
	_fetching = true
	var body := JSON.stringify({
		"model": "openai",
		"seed": randi() % 99999,
		"messages": [
			{
				"role": "system",
				"content": "You generate short Twitch chat messages. Output exactly 10 messages, one per line. Prefix positive/hype messages with +, negative/critical with -. No other text, no numbering, no explanation."
			},
			{
				"role": "user",
				"content": "10 Twitch chat reactions (1-5 words each): 7 positive (hype, GG, sub style) and 3 negative (bored, critical). One per line with + or - prefix only."
			}
		]
	})
	var err := _http.request(
		"https://text.pollinations.ai/openai",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		_fetching = false

func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_fetching = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var data = json.get_data()
	if not (data is Dictionary and data.has("choices")):
		return
	var content: String = data["choices"][0]["message"]["content"]
	for line: String in content.split("\n"):
		line = line.strip_edges()
		if line.length() < 2:
			continue
		if line[0] == "+":
			_ai_queue.append({"text": line.substr(1).strip_edges(), "positive": true})
		elif line[0] == "-":
			_ai_queue.append({"text": line.substr(1).strip_edges(), "positive": false})

func _process(delta: float) -> void:
	_tick += delta
	if _tick >= _spawn_interval:
		_tick = 0.0
		_spawn_comment()

	var rate := GameManager.comment_auto_click_rate
	if rate > 0.0:
		_comment_acc += rate * delta
		if _comment_acc >= 1.0:
			var clicks := int(_comment_acc)
			_comment_acc = fmod(_comment_acc, 1.0)
			_auto_dismiss_n(clicks)

func _spawn_comment() -> void:
	if GameManager.views == 0:
		return

	var text: String
	var is_positive: bool

	if not _ai_queue.is_empty():
		var entry: Dictionary = _ai_queue.pop_front()
		text = entry.get("text", "")
		is_positive = entry.get("positive", true)
		if text.is_empty():
			is_positive = randf() < 0.7
			text = _fallback_text(is_positive)
		if _ai_queue.size() < 5:
			_fetch_ai_comments()
	else:
		is_positive = randf() < 0.7
		text = _fallback_text(is_positive)

	_add_comment(text, is_positive)

func _fallback_text(is_positive: bool) -> String:
	if is_positive:
		return POSITIVE_COMMENTS[randi() % POSITIVE_COMMENTS.size()]
	return NEGATIVE_COMMENTS[randi() % NEGATIVE_COMMENTS.size()]

func _add_comment(text: String, is_positive: bool) -> void:
	var btn := _get_from_pool()
	_configure_button(btn, text, is_positive)
	var cb := _on_comment_pressed.bind(btn, is_positive)
	btn.set_meta("_cb", cb)
	btn.pressed.connect(cb)
	comment_list.add_child(btn)

	if not is_positive:
		_start_negative_timer(btn, btn.get_meta("_gen", 0))

	_trim_overflow()
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

func _get_from_pool() -> Button:
	if not _pool.is_empty():
		return _pool.pop_back()
	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn

func _configure_button(btn: Button, text: String, is_positive: bool) -> void:
	# Increment generation so stale timer/tween callbacks recognise this as a new use.
	btn.set_meta("_gen", btn.get_meta("_gen", 0) + 1)
	var color := Color(0.15, 1.0, 0.3) if is_positive else Color(1.0, 0.25, 0.25)
	btn.text = text
	btn.disabled = false
	btn.modulate.a = 1.0
	btn.set_meta("_positive", is_positive)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", color.lightened(0.2))
	btn.add_theme_color_override("font_pressed_color", color.darkened(0.15))
	btn.add_theme_color_override("font_focus_color", color)
	btn.add_theme_font_size_override("font_size", 13)
	if _comment_font:
		btn.add_theme_font_override("font", _comment_font)

func _trim_overflow() -> void:
	var children := comment_list.get_children()
	var over := children.size() - MAX_COMMENTS
	for i in over:
		_dismiss(children[i] as Button, true)

func _start_negative_timer(btn: Button, gen: int) -> void:
	await get_tree().create_timer(NEGATIVE_LIFETIME).timeout
	if is_instance_valid(btn) and not btn.disabled and btn.get_meta("_gen", -1) == gen:
		_on_comment_pressed(btn, false)
		GameManager.remove_subs(1)

func _auto_dismiss_n(n: int) -> void:
	# Collect all clickable buttons in one pass.
	var available: Array[Button] = []
	for child in comment_list.get_children():
		var btn := child as Button
		if btn and not btn.disabled:
			available.append(btn)

	# If clicks exceed what's on screen, skip tween animations (instant clear).
	var instant := n >= available.size()
	var to_process := mini(n, available.size())

	for i in to_process:
		var btn: Button = available[i]
		if instant:
			btn.disabled = true
			if btn.get_meta("_positive", true):
				_clicked_positive += 1
				if _clicked_positive >= 5:
					_clicked_positive -= 5
					GameManager.add_bonus_subs(1)
			_dismiss(btn, true)
		else:
			_on_comment_pressed(btn, btn.get_meta("_positive", true))

func _on_comment_pressed(btn: Button, is_positive: bool) -> void:
	btn.disabled = true
	_dismiss(btn, false)
	if is_positive:
		_clicked_positive += 1
		if _clicked_positive >= 5:
			_clicked_positive -= 5
			GameManager.add_bonus_subs(1)

func _dismiss(btn: Button, instant: bool) -> void:
	_kill_tween(btn)
	if instant:
		_return_to_pool(btn)
		return
	var t := btn.create_tween()
	btn.set_meta("_tween", t)
	t.tween_property(btn, "modulate:a", 0.0, 0.25)
	t.tween_callback(_on_fade_done.bind(btn))

func _kill_tween(btn: Button) -> void:
	if btn.has_meta("_tween"):
		var t: Tween = btn.get_meta("_tween")
		if is_instance_valid(t) and t.is_running():
			t.kill()
		btn.remove_meta("_tween")

func _on_fade_done(btn: Button) -> void:
	if btn.has_meta("_tween"):
		btn.remove_meta("_tween")
	_return_to_pool(btn)

func _return_to_pool(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	if btn.has_meta("_cb"):
		var cb: Callable = btn.get_meta("_cb")
		if btn.pressed.is_connected(cb):
			btn.pressed.disconnect(cb)
		btn.remove_meta("_cb")
	if btn.get_parent():
		btn.get_parent().remove_child(btn)
	_pool.append(btn)

func _on_views_changed(v: int) -> void:
	if v < 10:
		_spawn_interval = 3.0
	elif v < 100:
		_spawn_interval = 2.0
	elif v < 1000:
		_spawn_interval = 1.0
	elif v < 10000:
		_spawn_interval = 0.5
	else:
		_spawn_interval = 0.25
