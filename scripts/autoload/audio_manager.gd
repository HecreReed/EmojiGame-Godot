extends Node
## Audio manager for game sounds and music

@onready var music_player: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var sfx_player: AudioStreamPlayer = AudioStreamPlayer.new()

# Audio settings
var music_volume: float = 0.7
var sfx_volume: float = 0.8
var music_enabled: bool = true
var sfx_enabled: bool = true

var bgm_streams: Dictionary = {}
var sfx_streams: Dictionary = {}
var current_bgm: String = ""

func _ready():
	# Add audio players to scene
	add_child(music_player)
	add_child(sfx_player)

	# Set initial volumes
	music_player.volume_db = linear_to_db(music_volume)
	sfx_player.volume_db = linear_to_db(sfx_volume)

	# Music should loop
	music_player.finished.connect(_on_music_finished)

	# Load audio files (add paths to your audio files here)
	load_audio_files()

func load_audio_files():
	# Stage/Boss BGM (Python parity)
	for i in range(1, 7):
		_load_bgm("bgm%d.mp3" % i)
		_load_bgm("boss%d.mp3" % i)

	# Sound effects
	var sfx_files := ["death.mp3", "gold.wav", "madeinheaven.wav", "theworld.wav", "watertimestop.wav"]
	for sfx_file in sfx_files:
		_load_sfx(sfx_file)

func _load_bgm(file_name: String) -> void:
	var path := "res://assets/audio/music/" + file_name
	if FileAccess.file_exists(path):
		var stream: AudioStream = load(path)
		if stream:
			bgm_streams[file_name] = stream

func _load_sfx(file_name: String) -> void:
	var path := "res://assets/audio/music/" + file_name
	if FileAccess.file_exists(path):
		var stream: AudioStream = load(path)
		if stream:
			sfx_streams[file_name] = stream

func play_bgm_file(file_name: String) -> void:
	if not music_enabled:
		return
	if current_bgm == file_name and music_player.playing:
		return
	if bgm_streams.has(file_name):
		music_player.stream = bgm_streams[file_name]
		music_player.play()
		current_bgm = file_name

func play_sfx_file(file_name: String) -> void:
	if not sfx_enabled:
		return
	if sfx_streams.has(file_name):
		sfx_player.stream = sfx_streams[file_name]
		sfx_player.play()

# Backward compatible wrappers
func play_music(music_name: String) -> void:
	play_bgm_file(music_name)

func play_sfx(sfx_name: String) -> void:
	play_sfx_file(sfx_name)

func stop_music():
	music_player.stop()

func stop_sfx():
	sfx_player.stop()

func set_music_volume(volume: float):
	music_volume = clamp(volume, 0.0, 1.0)
	music_player.volume_db = linear_to_db(music_volume)

func set_sfx_volume(volume: float):
	sfx_volume = clamp(volume, 0.0, 1.0)
	sfx_player.volume_db = linear_to_db(sfx_volume)

func toggle_music():
	music_enabled = not music_enabled
	if not music_enabled:
		stop_music()

func toggle_sfx():
	sfx_enabled = not sfx_enabled

func _on_music_finished():
	# Loop music or play next track
	if music_enabled and music_player.stream:
		music_player.play()
