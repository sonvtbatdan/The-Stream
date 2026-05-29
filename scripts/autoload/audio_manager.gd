extends Node

const MUSIC_DIR := "res://assets/audio/music/"

var music_volume: float = 1.0
var sfx_volume: float = 1.0

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer

var _playlist: Array[String] = []
var _playlist_index: int = 0
var _shuffle_enabled: bool = false
var _loop_current: bool = false

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	sfx_player = AudioStreamPlayer.new()
	add_child(sfx_player)
	music_player.finished.connect(_on_track_finished)
	_build_playlist()
	_play_current_track()

func _build_playlist() -> void:
	_playlist.clear()
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.get_extension().to_lower() in ["wav", "ogg", "mp3"]:
			_playlist.append(MUSIC_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	_playlist.shuffle()
	_playlist_index = 0

func _play_current_track() -> void:
	if _playlist.is_empty():
		return
	var tried := 0
	while tried < _playlist.size():
		var path: String = _playlist[_playlist_index]
		var stream := load(path) as AudioStream
		if stream != null:
			music_player.stream = stream
			music_player.volume_db = linear_to_db(music_volume)
			music_player.play()
			return
		push_warning("AudioManager: cannot load '%s', skipping" % path)
		_playlist_index = (_playlist_index + 1) % _playlist.size()
		tried += 1
	push_warning("AudioManager: no playable tracks in playlist")

func _on_track_finished() -> void:
	if _loop_current:
		_play_current_track()
		return
	_playlist_index = (_playlist_index + 1) % _playlist.size()
	if _playlist_index == 0 and _shuffle_enabled:
		_playlist.shuffle()
	_play_current_track()

func _advance_track() -> void:
	_playlist_index = (_playlist_index + 1) % _playlist.size()
	if _playlist_index == 0 and _shuffle_enabled:
		_playlist.shuffle()
	_play_current_track()

func prev_track() -> void:
	_playlist_index = (_playlist_index - 1 + _playlist.size()) % _playlist.size()
	_play_current_track()

func set_shuffle(enabled: bool) -> void:
	_shuffle_enabled = enabled
	if enabled:
		_playlist.shuffle()
		_playlist_index = 0

func set_loop(enabled: bool) -> void:
	_loop_current = enabled

func play_music(stream: AudioStream) -> void:
	music_player.stream = stream
	music_player.volume_db = linear_to_db(music_volume)
	music_player.play()

func play_sfx(stream: AudioStream) -> void:
	sfx_player.stream = stream
	sfx_player.volume_db = linear_to_db(sfx_volume)
	sfx_player.play()

func set_music_volume(value: float) -> void:
	music_volume = clamp(value, 0.0, 1.0)
	music_player.volume_db = linear_to_db(music_volume)

func set_sfx_volume(value: float) -> void:
	sfx_volume = clamp(value, 0.0, 1.0)
	sfx_player.volume_db = linear_to_db(sfx_volume)

func next_track() -> void:
	_advance_track()
