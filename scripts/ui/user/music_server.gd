# Controls mpv as a hidden background process via JSON IPC over TCP.
# Requires mpv.exe + yt-dlp.exe + mpv-bridge.ps1 inside res://tools/.
# Bridge translates bidirectional TCP 12736 ↔ named pipe so Godot can talk to mpv.
class_name UserMusicServer
extends Node

const IPC_PORT      := 12736
const TOOLS_DIR     := "res://tools/"
const CONNECT_LIMIT := 15.0

var _mpv_pid          := -1
var _tcp              := StreamPeerTCP.new()
var _connected        := false
var _retry_t          := 0.0
var _total_t          := 0.0
var _running          := false
var _pending_url      := ""
var _pending_playlist: Array = []
var _fetch_thread:    Thread = null
var _recv_buf         := ""

var playlist_ids:    Array = []
var playlist_titles: Array = []

signal browser_connected
signal browser_disconnected
signal start_failed(reason: String)
signal playlist_loaded(ids: Array)
signal time_changed(pos: float)
signal duration_changed(dur: float)
signal playlist_pos_changed(idx: int)

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func start() -> void:
	if _running:
		return
	var tools       := ProjectSettings.globalize_path(TOOLS_DIR)
	var mpv_path    := tools + "mpv.exe"
	var ytdlp_path  := tools + "yt-dlp.exe"
	var bridge_path := tools + "mpv-bridge.ps1"
	if not FileAccess.file_exists(mpv_path):
		start_failed.emit("mpv.exe not found — place it in tools/")
		return
	if not FileAccess.file_exists(ytdlp_path):
		start_failed.emit("yt-dlp.exe not found — place it in tools/")
		return
	if not FileAccess.file_exists(bridge_path):
		start_failed.emit("mpv-bridge.ps1 not found — place it in tools/")
		return
	_mpv_pid = OS.create_process("powershell.exe", [
		"-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
		"-ExecutionPolicy", "Bypass", "-File", bridge_path,
		"-TcpPort", str(IPC_PORT),
	])
	if _mpv_pid == -1:
		start_failed.emit("Failed to launch mpv bridge (powershell.exe not found?)")
		return
	_running = true
	_retry_t = 0.0
	_total_t = 0.0

func stop() -> void:
	if not _running:
		return
	_ipc({"command": ["quit"]})
	_tcp.disconnect_from_host()
	_connected = false
	_running   = false
	_mpv_pid   = -1
	_pending_url = ""
	_pending_playlist = []

func _exit_tree() -> void:
	if not _running:
		return
	_ipc({"command": ["quit"]})
	_tcp.disconnect_from_host()
	if _mpv_pid != -1:
		# /T kills the bridge AND all its child processes (mpv)
		OS.execute("taskkill.exe", ["/F", "/T", "/PID", str(_mpv_pid)])

# ── Playback ──────────────────────────────────────────────────────────────────

func open_video(video_id: String) -> void:
	if not _running:
		start()
	if not _running:
		return
	playlist_ids    = []
	playlist_titles = []
	var url := "https://www.youtube.com/watch?v=" + video_id
	if _connected:
		_ipc({"command": ["loadfile", url, "replace"]})
	else:
		_pending_url = url

func seek_to(pos_sec: float) -> void:
	_ipc({"command": ["seek", pos_sec, "absolute"]})

func skip_to(playlist_idx: int) -> void:
	_ipc({"command": ["set_property", "playlist-pos", playlist_idx]})

func send(cmd: Dictionary) -> void:
	match cmd.get("cmd", ""):
		"play":   _ipc({"command": ["set_property", "pause", false]})
		"pause":  _ipc({"command": ["set_property", "pause", true]})
		"volume": _ipc({"command": ["set_property", "volume", float(cmd.get("v", 1.0)) * 100.0]})
		"mute":   _ipc({"command": ["set_property", "mute", true]})
		"unmute": _ipc({"command": ["set_property", "mute", false]})

# ── Playlist fetch ────────────────────────────────────────────────────────────

func fetch_playlist_async(list_url: String) -> void:
	if not _running:
		start()
	if not _running:
		return
	if _fetch_thread != null:
		_fetch_thread.wait_to_finish()
	_fetch_thread = Thread.new()
	_fetch_thread.start(_do_fetch_playlist.bind(list_url))

func _do_fetch_playlist(list_url: String) -> void:
	var tools := ProjectSettings.globalize_path(TOOLS_DIR)
	var ytdlp  := tools + "yt-dlp.exe"
	var output: Array = []
	OS.execute(ytdlp, [
		"--flat-playlist", "--print", "%(id)s\t%(title)s",
		"--extractor-args", "youtube:player_client=android",
		"--no-warnings", "--", list_url
	], output)
	var ids: Array = []
	var titles: Array = []
	if not output.is_empty():
		for raw_line in (output[0] as String).split("\n"):
			var line: String = (raw_line as String).strip_edges()
			if line.is_empty():
				continue
			var parts := line.split("\t", false, 1)
			var vid_id: String = parts[0] if parts.size() > 0 else ""
			if vid_id.is_empty():
				continue
			ids.append(vid_id)
			titles.append(parts[1] if parts.size() > 1 else vid_id)
			if ids.size() >= 50:
				break
	call_deferred("_on_playlist_fetched", ids, titles)

func _on_playlist_fetched(ids: Array, titles: Array) -> void:
	if _fetch_thread:
		_fetch_thread.wait_to_finish()
		_fetch_thread = null
	playlist_ids    = ids.duplicate()
	playlist_titles = titles.duplicate()
	if _connected:
		_queue_playlist(ids)
	elif not ids.is_empty():
		_pending_playlist = ids.duplicate()
	playlist_loaded.emit(ids)

func _queue_playlist(ids: Array) -> void:
	if ids.is_empty():
		return
	_ipc({"command": ["loadfile", "https://www.youtube.com/watch?v=" + ids[0], "replace"]})
	for i in range(1, ids.size()):
		_ipc({"command": ["loadfile", "https://www.youtube.com/watch?v=" + ids[i], "append"]})

# ── IPC / TCP ─────────────────────────────────────────────────────────────────

func _ipc(obj: Dictionary) -> void:
	if not _connected:
		return
	_tcp.put_data((JSON.stringify(obj) + "\n").to_utf8_buffer())

func _process(dt: float) -> void:
	if not _running:
		return
	_tcp.poll()
	var st := _tcp.get_status()
	if _connected:
		if st != StreamPeerTCP.STATUS_CONNECTED:
			_connected = false
			browser_disconnected.emit()
		else:
			var n := _tcp.get_available_bytes()
			if n > 0:
				_recv_buf += _tcp.get_utf8_string(n)
				_drain_recv()
	else:
		_total_t += dt
		if _total_t >= CONNECT_LIMIT:
			_running = false
			_tcp.disconnect_from_host()
			start_failed.emit("Timeout — bridge or mpv failed to start (check tools/ has mpv.exe, yt-dlp.exe, mpv-bridge.ps1)")
			return
		_retry_t += dt
		match st:
			StreamPeerTCP.STATUS_NONE:
				if _retry_t >= 0.4:
					_retry_t = 0.0
					_tcp.connect_to_host("127.0.0.1", IPC_PORT)
			StreamPeerTCP.STATUS_CONNECTED:
				_connected = true
				_retry_t   = 0.0
				_total_t   = 0.0
				if not _pending_playlist.is_empty():
					_queue_playlist(_pending_playlist)
					_pending_playlist = []
				elif not _pending_url.is_empty():
					_ipc({"command": ["loadfile", _pending_url, "replace"]})
					_pending_url = ""
				browser_connected.emit()
			StreamPeerTCP.STATUS_ERROR:
				_tcp     = StreamPeerTCP.new()
				_retry_t = 0.0

func _drain_recv() -> void:
	var nl := _recv_buf.find("\n")
	while nl >= 0:
		var line := _recv_buf.substr(0, nl).strip_edges()
		_recv_buf = _recv_buf.substr(nl + 1)
		if not line.is_empty():
			_parse_mpv(line)
		nl = _recv_buf.find("\n")

func _parse_mpv(line: String) -> void:
	var j: Variant = JSON.parse_string(line)
	if not (j is Dictionary):
		return
	if j.get("event", "") == "property-change":
		var data: Variant = j.get("data", null)
		match j.get("name", ""):
			"time-pos":
				if data != null:
					time_changed.emit(float(data))
			"duration":
				if data != null:
					duration_changed.emit(float(data))
			"playlist-pos":
				if data != null:
					playlist_pos_changed.emit(int(data))
