extends Node

var music_volume: float = 1.0
var sfx_volume: float = 1.0

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer

func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	sfx_player = AudioStreamPlayer.new()
	add_child(sfx_player)

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
