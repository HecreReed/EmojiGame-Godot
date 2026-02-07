extends Node
## Audio manager for game sounds and music

@onready var music_player: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var sfx_player: AudioStreamPlayer = AudioStreamPlayer.new()

# Audio settings
var music_volume: float = 0.7
var sfx_volume: float = 0.8
var music_enabled: bool = true
var sfx_enabled: bool = true

# Preloaded sounds (to be configured)
var sounds: Dictionary = {}

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
	# Background music
	var music_files = ["Aleph.mp3", "Boardline.mp3", "temp.mp3"]
	for music_file in music_files:
		var path = "res://assets/audio/music/" + music_file
		if FileAccess.file_exists(path):
			var stream = load(path)
			if stream:
				sounds["music_" + music_file] = stream

	# Sound effects
	var sfx_files = ["death.mp3", "gold.wav", "madeinheaven.wav", "theworld.wav", "watertimestop.wav"]
	for sfx_file in sfx_files:
		var path = "res://assets/audio/music/" + sfx_file
		if FileAccess.file_exists(path):
			var stream = load(path)
			if stream:
				sounds["sfx_" + sfx_file] = stream

func play_music(music_name: String):
	if not music_enabled:
		return

	var full_name = "music_" + music_name
	if sounds.has(full_name):
		music_player.stream = sounds[full_name]
		music_player.play()

func play_sfx(sfx_name: String):
	if not sfx_enabled:
		return

	var full_name = "sfx_" + sfx_name
	if sounds.has(full_name):
		sfx_player.stream = sounds[full_name]
		sfx_player.play()

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
