class_name MusicManager
extends Node

var current_bgm: AudioStreamPlayer
var bgm_tracks: Dictionary = {}

func _ready():
	# Create audio player
	current_bgm = AudioStreamPlayer.new()
	add_child(current_bgm)

	# Load BGM tracks
	bgm_tracks["stage1"] = load("res://audio/bgm1.mp3")
	bgm_tracks["stage2"] = load("res://audio/bgm2.mp3")
	bgm_tracks["stage3"] = load("res://audio/bgm3.mp3")
	bgm_tracks["stage4"] = load("res://audio/bgm4.mp3")
	bgm_tracks["stage5"] = load("res://audio/bgm5.mp3")
	bgm_tracks["stage6"] = load("res://audio/bgm6.mp3")
	bgm_tracks["boss1"] = load("res://audio/boss1.mp3")
	bgm_tracks["boss2"] = load("res://audio/boss2.mp3")
	bgm_tracks["boss3"] = load("res://audio/boss3.mp3")
	bgm_tracks["boss4"] = load("res://audio/boss4.mp3")
	bgm_tracks["boss5"] = load("res://audio/boss5.mp3")
	bgm_tracks["boss6"] = load("res://audio/boss6.mp3")
	bgm_tracks["death"] = load("res://audio/death.mp3")
	bgm_tracks["theworld"] = load("res://audio/theworld.wav")
	bgm_tracks["timestop"] = load("res://audio/watertimestop.wav")
	bgm_tracks["gold"] = load("res://audio/gold.wav")

func play_bgm(track_name: String):
	if bgm_tracks.has(track_name):
		if current_bgm.stream != bgm_tracks[track_name]:
			current_bgm.stream = bgm_tracks[track_name]
			current_bgm.play()

func stop_bgm():
	current_bgm.stop()

func set_volume(volume: float):
	current_bgm.volume_db = volume
