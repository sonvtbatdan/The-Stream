# Controls mpv as a hidden background process via JSON IPC over TCP.
# Requires mpv.exe + yt-dlp.exe + mpv-bridge.ps1 inside res://tools/.
# mpv 2.0 on Windows only supports named-pipe IPC; the bridge script translates
# TCP 12736 → named pipe so Godot can talk to mpv without native pipe support.
class_name UserMusicServer
extends Node

const IPC_PORT      := 12736
const TOOLS_DIR     := "res://tools/"
const CONNECT_LIMIT := 15.0   # seconds before giving up (PS + mpv startup)

var _mpv_pid       := -1
var _tcp           := StreamPeerTCP.new()
var _connected     := false
var _retry_t       := 0.0
var _total_t       := 0.0
var _running       := false
var _pending_url   := ""

signal browser_connected
signal browser_disconnected
signal start_failed(reason: String)

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

	# mpv 2.0 on Windows uses named-pipe IPC only; launch the PS bridge that
	# translates TCP 12736 → named pipe and also starts mpv internally.
	_mpv_pid = OS.create_process("powershell.exe", [
		"-NoProfile",
		"-NonInteractive",
		"-WindowStyle", "Hidden",
		"-ExecutionPolicy", "Bypass",
		"-File", bridge_path,
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

func open_video(video_id: String) -> void:
	if not _running:
		start()
	if not _running:   # start() failed
		return
	var url := "https://www.youtube.com/watch?v=" + video_id
	if _connected:
		_ipc({"command": ["loadfile", url, "replace"]})
	else:
		_pending_url = url

func send(cmd: Dictionary) -> void:
	match cmd.get("cmd", ""):
		"play":
			_ipc({"command": ["set_property", "pause", false]})
		"pause":
			_ipc({"command": ["set_property", "pause", true]})
		"volume":
			_ipc({"command": ["set_property", "volume", float(cmd.get("v", 1.0)) * 100.0]})
		"mute":
			_ipc({"command": ["set_property", "mute", true]})
		"unmute":
			_ipc({"command": ["set_property", "mute", false]})

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
				_tcp.get_utf8_string(n)   # drain mpv JSON responses
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
				if not _pending_url.is_empty():
					_ipc({"command": ["loadfile", _pending_url, "replace"]})
					_pending_url = ""
				browser_connected.emit()
			StreamPeerTCP.STATUS_ERROR:
				_tcp     = StreamPeerTCP.new()
				_retry_t = 0.0
