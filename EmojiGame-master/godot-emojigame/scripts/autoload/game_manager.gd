extends Node
## Global game manager singleton

signal score_changed(new_score: int)
signal health_changed(current_health: int, max_health: int)
signal game_over
signal game_paused
signal game_resumed

var score: int = 0
var high_score: int = 0
var is_paused: bool = false

# Score multiplier system
var score_multiplier: float = 1.0
var multiplier_end_time: float = 0.0

func _ready():
	load_high_score()

func _process(delta):
	# Check if score multiplier expired
	if score_multiplier > 1.0 and Time.get_ticks_msec() / 1000.0 > multiplier_end_time:
		score_multiplier = 1.0

func add_score(amount: int):
	var actual_score = int(amount * score_multiplier)
	score += actual_score
	if score > high_score:
		high_score = score
		save_high_score()
	score_changed.emit(score)

func activate_score_multiplier(multiplier: float, duration: float):
	score_multiplier = multiplier
	multiplier_end_time = Time.get_ticks_msec() / 1000.0 + duration

func reset_score():
	score = 0
	score_multiplier = 1.0
	score_changed.emit(score)

func pause_game():
	if not is_paused:
		is_paused = true
		get_tree().paused = true
		game_paused.emit()

func resume_game():
	if is_paused:
		is_paused = false
		get_tree().paused = false
		game_resumed.emit()

func trigger_game_over():
	game_over.emit()

func load_high_score():
	# Load from file or config
	if FileAccess.file_exists("user://highscore.save"):
		var file = FileAccess.open("user://highscore.save", FileAccess.READ)
		if file:
			high_score = file.get_32()
			file.close()

func save_high_score():
	var file = FileAccess.open("user://highscore.save", FileAccess.WRITE)
	if file:
		file.store_32(high_score)
		file.close()

func restart_game():
	reset_score()
	get_tree().paused = false
	is_paused = false
	get_tree().reload_current_scene()
