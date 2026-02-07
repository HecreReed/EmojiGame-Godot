extends CanvasLayer

@onready var score_label: Label = $MarginContainer/VBoxContainer/ScoreLabel
@onready var wave_label: Label = $MarginContainer/VBoxContainer/WaveLabel
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthBar/HealthLabel
@onready var pause_menu: Control = $PauseMenu
@onready var game_over_screen: Control = $GameOverScreen
@onready var final_score_label: Label = $GameOverScreen/VBoxContainer/FinalScoreLabel

# Buttons
@onready var resume_button: Button = $PauseMenu/VBoxContainer/ResumeButton
@onready var pause_quit_button: Button = $PauseMenu/VBoxContainer/QuitButton
@onready var restart_button: Button = $GameOverScreen/VBoxContainer/RestartButton
@onready var gameover_quit_button: Button = $GameOverScreen/VBoxContainer/QuitButton

func _ready():
	# Connect to GameManager signals
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.health_changed.connect(_on_health_changed)
	GameManager.game_over.connect(_on_game_over)
	GameManager.game_paused.connect(_on_game_paused)
	GameManager.game_resumed.connect(_on_game_resumed)

	# Connect button signals
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if pause_quit_button:
		pause_quit_button.pressed.connect(_on_quit_pressed)
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if gameover_quit_button:
		gameover_quit_button.pressed.connect(_on_quit_pressed)

	# Hide menus initially
	pause_menu.hide()
	game_over_screen.hide()

	# Connect to enemy spawner for wave updates
	var spawner = get_node_or_null("/root/Main/EnemySpawner")
	if spawner:
		# We'll update wave label in _process instead
		pass

func _process(_delta):
	# Update wave label from enemy spawner
	var spawner = get_node_or_null("/root/Main/EnemySpawner")
	if spawner and wave_label:
		wave_label.text = "Wave: %d" % (spawner.wave_number + 1)

func _on_score_changed(new_score: int):
	if score_label:
		score_label.text = "Score: %d" % new_score

func _on_health_changed(current_health: int, max_health: int):
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	if health_label:
		health_label.text = "%d/%d" % [current_health, max_health]

func _on_game_over():
	game_over_screen.show()
	if final_score_label:
		final_score_label.text = "Final Score: %d" % GameManager.score

func _on_game_paused():
	pause_menu.show()

func _on_game_resumed():
	pause_menu.hide()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if GameManager.is_paused:
			GameManager.resume_game()
		else:
			GameManager.pause_game()
		get_viewport().set_input_as_handled()

func _on_resume_pressed():
	GameManager.resume_game()

func _on_restart_pressed():
	GameManager.restart_game()

func _on_quit_pressed():
	get_tree().quit()
