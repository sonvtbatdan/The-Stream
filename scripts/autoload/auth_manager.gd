extends Node

# ─── Desktop app OAuth 2.0 — Authorization Code + PKCE + localhost redirect ──
const CLIENT_ID     := ""  # Set your Google OAuth Client ID here
const CLIENT_SECRET := ""  # Set your Google OAuth Client Secret here
# ─────────────────────────────────────────────────────────────────────────────

const SCOPE         := "openid email profile"
const AUTH_URL      := "https://accounts.google.com/o/oauth2/v2/auth"
const TOKEN_URL     := "https://oauth2.googleapis.com/token"
const SETTINGS_PATH := "user://settings.cfg"

enum _State { IDLE, WAITING_CALLBACK, EXCHANGING, REFRESHING }

signal auth_changed(logged_in: bool)
signal login_started()
signal login_error(message: String)

var access_token:  String = ""
var refresh_token: String = ""
var _expires_at:   int    = 0
var _state:        _State = _State.IDLE

var _code_verifier:  String = ""
var _redirect_port:  int    = 0

var _tcp_server:   TCPServer     = null
var _pending_conn: StreamPeerTCP = null
var _conn_buffer:  String        = ""
var _conn_timeout: float         = 0.0

var _http_token: HTTPRequest = null

func _ready() -> void:
	_http_token = HTTPRequest.new()
	_http_token.timeout = 30.0
	add_child(_http_token)
	_http_token.request_completed.connect(_on_token_response)
	_load_tokens()
	if not refresh_token.is_empty() and _is_token_expired():
		_state = _State.REFRESHING
		_send_refresh()

# ── Public API ────────────────────────────────────────────────────────────────

func is_logged_in() -> bool:
	return not access_token.is_empty() and not _is_token_expired()

func needs_refresh() -> bool:
	return access_token.is_empty() and not refresh_token.is_empty()

func get_token() -> String:
	return access_token

func start_login() -> void:
	if _state != _State.IDLE:
		return

	var pkce        := _generate_pkce()
	_code_verifier   = pkce["verifier"]
	_redirect_port   = _start_local_server()

	if _redirect_port < 0:
		login_error.emit("Không thể mở local server. Thử lại.")
		return

	var redirect_uri := "http://127.0.0.1:%d" % _redirect_port
	var url := AUTH_URL + "?" + _build_query({
		"client_id":             CLIENT_ID,
		"redirect_uri":          redirect_uri,
		"response_type":         "code",
		"scope":                 SCOPE,
		"code_challenge":        pkce["challenge"],
		"code_challenge_method": "S256",
		"access_type":           "offline",
		"prompt":                "consent"
	})

	OS.shell_open(url)
	_state = _State.WAITING_CALLBACK
	login_started.emit()

func cancel_login() -> void:
	_stop_server()
	_state = _State.IDLE

func logout() -> void:
	access_token  = ""
	refresh_token = ""
	_expires_at   = 0
	_state        = _State.IDLE
	_stop_server()
	_save_tokens()
	auth_changed.emit(false)

# ── Process: đọc callback từ browser ─────────────────────────────────────────

func _process(delta: float) -> void:
	if _state != _State.WAITING_CALLBACK:
		return

	if _tcp_server and _tcp_server.is_connection_available() and not _pending_conn:
		_pending_conn = _tcp_server.take_connection()
		_conn_buffer  = ""
		_conn_timeout = 10.0

	if _pending_conn:
		_conn_timeout -= delta
		if _conn_timeout <= 0.0:
			_pending_conn = null
			return
		if _pending_conn.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			var avail := _pending_conn.get_available_bytes()
			if avail > 0:
				_conn_buffer += _pending_conn.get_utf8_string(avail)
			if "\r\n\r\n" in _conn_buffer or _conn_buffer.length() > 4096:
				_handle_callback(_conn_buffer)

# ── OAuth callback handler ────────────────────────────────────────────────────

func _handle_callback(request: String) -> void:
	_stop_server()

	var code_rx := RegEx.new()
	code_rx.compile("[?&]code=([^&\\s]+)")
	var m := code_rx.search(request)

	if m:
		_send_browser_response(true)
		_exchange_code(m.get_string(1).uri_decode())
	else:
		var err_rx := RegEx.new()
		err_rx.compile("[?&]error=([^&\\s]+)")
		var em := err_rx.search(request)
		_send_browser_response(false)
		_pending_conn = null
		_state = _State.IDLE
		login_error.emit("Đăng nhập bị từ chối: " + (em.get_string(1) if em else "unknown"))

func _send_browser_response(success: bool) -> void:
	if not _pending_conn or _pending_conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var html := ""
	if success:
		html = "<html><head><meta charset='utf-8'><style>body{font-family:sans-serif;text-align:center;padding:60px;background:#0a0e14;color:#e0eeff}</style></head><body><h2>✅ Đăng nhập thành công!</h2><p>Quay lại game.</p></body></html>"
	else:
		html = "<html><head><meta charset='utf-8'><style>body{font-family:sans-serif;text-align:center;padding:60px;background:#0a0e14;color:#e0eeff}</style></head><body><h2>❌ Đăng nhập thất bại</h2><p>Quay lại game và thử lại.</p></body></html>"
	var resp := "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [html.length(), html]
	_pending_conn.put_data(resp.to_utf8_buffer())
	_pending_conn = null

# ── Code exchange ─────────────────────────────────────────────────────────────

func _exchange_code(code: String) -> void:
	_state = _State.EXCHANGING
	var redirect_uri := "http://127.0.0.1:%d" % _redirect_port
	var body := "code=%s&client_id=%s&client_secret=%s&redirect_uri=%s&grant_type=authorization_code&code_verifier=%s" % [
		code.uri_encode(),
		CLIENT_ID.uri_encode(),
		CLIENT_SECRET.uri_encode(),
		redirect_uri.uri_encode(),
		_code_verifier.uri_encode()
	]
	_http_token.request(
		TOKEN_URL,
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),
		HTTPClient.METHOD_POST,
		body
	)

func _send_refresh() -> void:
	var body := "client_id=%s&client_secret=%s&refresh_token=%s&grant_type=refresh_token" % [
		CLIENT_ID.uri_encode(), CLIENT_SECRET.uri_encode(), refresh_token.uri_encode()
	]
	_http_token.request(
		TOKEN_URL,
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),
		HTTPClient.METHOD_POST,
		body
	)

func _on_token_response(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var j: Variant = JSON.parse_string(body.get_string_from_utf8())

	if _state == _State.REFRESHING:
		_state = _State.IDLE
		if code == 200 and j is Dictionary and j.has("access_token"):
			_apply_token(j)
		else:
			access_token  = ""
			refresh_token = ""
			_save_tokens()
			auth_changed.emit(false)
		return

	if _state == _State.EXCHANGING:
		_state = _State.IDLE
		if code == 200 and j is Dictionary and j.has("access_token"):
			_apply_token(j)
		else:
			var raw := body.get_string_from_utf8()
			var detail := ""
			if j is Dictionary and j.has("error"):
				detail = str(j.get("error", "")) + ": " + str(j.get("error_description", ""))
			else:
				detail = raw.left(120)
			print("AUTH exchange error HTTP %d: %s" % [code, raw.left(300)])
			login_error.emit("HTTP %d — %s" % [code, detail])

func _apply_token(j: Dictionary) -> void:
	access_token = j.get("access_token", "")
	if j.has("refresh_token"):
		refresh_token = j.get("refresh_token", "")
	var expires_in: int = j.get("expires_in", 3600)
	_expires_at = int(Time.get_unix_time_from_system()) + expires_in - 120
	_save_tokens()
	auth_changed.emit(true)

# ── PKCE ──────────────────────────────────────────────────────────────────────

func _generate_pkce() -> Dictionary:
	const CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var verifier := ""
	for i in range(64):
		verifier += CHARS[rng.randi() % CHARS.length()]

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(verifier.to_utf8_buffer())
	var digest := ctx.finish()

	# base64url: no padding, + → -, / → _
	var challenge := Marshalls.raw_to_base64(digest)
	challenge = challenge.replace("+", "-").replace("/", "_").replace("=", "")

	return {"verifier": verifier, "challenge": challenge}

# ── Local TCP server (loopback redirect) ──────────────────────────────────────

func _start_local_server() -> int:
	_tcp_server = TCPServer.new()
	for port in range(49152, 49200):
		if _tcp_server.listen(port, "127.0.0.1") == OK:
			return port
	return -1

func _stop_server() -> void:
	if _tcp_server:
		_tcp_server.stop()
		_tcp_server = null

# ── Helpers ───────────────────────────────────────────────────────────────────

func _build_query(params: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in params.keys():
		parts.append("%s=%s" % [key, str(params[key]).uri_encode()])
	return "&".join(parts)

func _is_token_expired() -> bool:
	return int(Time.get_unix_time_from_system()) >= _expires_at

func _save_tokens() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("auth", "access_token",  access_token)
	cfg.set_value("auth", "refresh_token", refresh_token)
	cfg.set_value("auth", "expires_at",    _expires_at)
	cfg.save(SETTINGS_PATH)

func _load_tokens() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	access_token  = cfg.get_value("auth", "access_token",  "")
	refresh_token = cfg.get_value("auth", "refresh_token", "")
	_expires_at   = cfg.get_value("auth", "expires_at",    0)
	if _is_token_expired():
		access_token = ""
