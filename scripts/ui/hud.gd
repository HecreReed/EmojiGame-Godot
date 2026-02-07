extends CanvasLayer

@onready var score_label: Label = $MarginContainer/VBoxContainer/ScoreLabel
@onready var money_label: Label = $MarginContainer/VBoxContainer/MoneyLabel
@onready var game_time_label: Label = $MarginContainer/VBoxContainer/GameTimeLabel
@onready var bomb_label: Label = $MarginContainer/VBoxContainer/BombLabel
@onready var shield_label: Label = $MarginContainer/VBoxContainer/ShieldLabel
@onready var weapon_label: Label = $MarginContainer/VBoxContainer/WeaponLabel
@onready var wave_label: Label = $MarginContainer/VBoxContainer/WaveLabel
@onready var boss_in_label: Label = $MarginContainer/VBoxContainer/BossInLabel
@onready var combo_label: Label = $MarginContainer/VBoxContainer/ComboLabel
@onready var achievement_label: Label = $AchievementLabel
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthBar/HealthLabel
@onready var power_bar: ProgressBar = $MarginContainer/VBoxContainer/PowerBar
@onready var pause_menu: Control = $PauseMenu
@onready var game_over_screen: Control = $GameOverScreen
@onready var final_score_label: Label = $GameOverScreen/VBoxContainer/FinalScoreLabel

# Buttons
@onready var resume_button: Button = $PauseMenu/VBoxContainer/ResumeButton
@onready var pause_quit_button: Button = $PauseMenu/VBoxContainer/QuitButton
@onready var restart_button: Button = $GameOverScreen/VBoxContainer/RestartButton
@onready var gameover_quit_button: Button = $GameOverScreen/VBoxContainer/QuitButton

var start_ticks_msec: int = 0
var enemy_spawner: Node = null
var achievement_hide_time: float = 0.0

func _ready():
	start_ticks_msec = Time.get_ticks_msec()

	# Connect to GameManager signals
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.health_changed.connect(_on_health_changed)
	GameManager.money_changed.connect(_on_money_changed)
	GameManager.power_changed.connect(_on_power_changed)
	GameManager.combo_changed.connect(_on_combo_changed)
	GameManager.achievement_unlocked.connect(_on_achievement_unlocked)
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
	if achievement_label:
		achievement_label.hide()

	# Connect to enemy spawner for wave updates
	enemy_spawner = get_node_or_null("/root/Main/EnemySpawner")

func _process(_delta):
	# Gametime (Python: show TIMESTOP during time stop)
	if game_time_label:
		if GameManager.time_stop_active:
			game_time_label.text = "Gametime: TIMESTOP"
		else:
			var elapsed := int((Time.get_ticks_msec() - start_ticks_msec) / 1000.0)
			game_time_label.text = "Gametime: %d" % elapsed

	# Stage info (Python StageSystem parity)
	if wave_label:
		var stage_text := StageManager.get_stage_info()
		if enemy_spawner and enemy_spawner.has_method("get_wave_number"):
			stage_text += " | Wave %d" % enemy_spawner.get_wave_number()
		wave_label.text = stage_text
	if boss_in_label:
		if StageManager.current_phase == StageManager.StagePhase.STAGE:
			boss_in_label.visible = true
			boss_in_label.text = "Boss in: %ds" % StageManager.get_stage_remaining_time()
		else:
			boss_in_label.visible = false

	if achievement_label and achievement_label.visible and Time.get_ticks_msec() / 1000.0 >= achievement_hide_time:
		achievement_label.hide()
		
	# Update bomb/shield values from player
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if bomb_label:
			bomb_label.text = "Bombs: %d" % player.bombs
		if shield_label:
			shield_label.text = "Shield: %d" % player.shield
		if weapon_label:
			if player.has_method("get_weapon_name"):
				weapon_label.text = "Weapon: %s" % player.get_weapon_name()
			elif "weapon_type" in player:
				weapon_label.text = "Weapon: %s" % str(player.weapon_type)

func _on_score_changed(new_score: int):
	if score_label:
		score_label.text = "Score: %d" % new_score

func _on_money_changed(new_money: int):
	if money_label:
		money_label.text = "Money: %d" % new_money

func _on_health_changed(current_health: int, max_health: int):
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	if health_label:
		health_label.text = "%d/%d" % [current_health, max_health]

func _on_power_changed(new_power: int):
	if power_bar:
		power_bar.max_value = 100
		power_bar.value = new_power

func _on_combo_changed(combo: int, multiplier: float):
	if not combo_label:
		return
	if combo <= 0:
		combo_label.text = "Combo: 0"
	else:
		combo_label.text = "Combo: %d (x%.1f)" % [combo, multiplier]

func _on_achievement_unlocked(achievement_name: String):
	if not achievement_label:
		return
	achievement_label.text = "Achievement Unlocked: %s" % achievement_name
	achievement_label.show()
	achievement_hide_time = Time.get_ticks_msec() / 1000.0 + 2.6

func _on_game_over():
	game_over_screen.show()
	if final_score_label:
		final_score_label.text = "Final Score: %d" % GameManager.score

func _on_game_paused():
	pause_menu.show()

func _on_game_resumed():
	pause_menu.hide()

func _input(event):
	if event.is_action_pressed("pause"):
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
