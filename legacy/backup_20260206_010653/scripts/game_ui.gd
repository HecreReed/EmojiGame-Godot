class_name GameUI
extends CanvasLayer

# UI Elements
@onready var score_label: Label
@onready var combo_label: Label
@onready var stage_label: Label
@onready var hp_bar: ProgressBar
@onready var power_label: Label
@onready var bomb_label: Label
@onready var time_stop_bar: ProgressBar
@onready var boss_hp_bar: ProgressBar

func _ready():
	# Create UI elements
	create_ui()
	
	# Connect to game manager
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager:
		game_manager.score_changed.connect(_on_score_changed)
		game_manager.combo_changed.connect(_on_combo_changed)
		game_manager.stage_changed.connect(_on_stage_changed)
		game_manager.boss_battle_started.connect(_on_boss_battle_started)
		game_manager.boss_battle_ended.connect(_on_boss_battle_ended)
	
	# Connect to player
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.hp_changed.connect(_on_hp_changed)
		player.power_changed.connect(_on_power_changed)
		player.bomb_count_changed.connect(_on_bomb_count_changed)
		player.time_stop_energy_changed.connect(_on_time_stop_energy_changed)

func create_ui():
	# Score label
	score_label = Label.new()
	score_label.position = Vector2(10, 10)
	score_label.text = "Score: 0"
	add_child(score_label)
	
	# Combo label
	combo_label = Label.new()
	combo_label.position = Vector2(10, 40)
	combo_label.text = "Combo: 0"
	add_child(combo_label)
	
	# Stage label
	stage_label = Label.new()
	stage_label.position = Vector2(10, 70)
	stage_label.text = "Stage: 1"
	add_child(stage_label)
	
	# HP bar
	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(10, 100)
	hp_bar.size = Vector2(200, 20)
	hp_bar.max_value = 5
	hp_bar.value = 5
	add_child(hp_bar)
	
	# Power label
	power_label = Label.new()
	power_label.position = Vector2(10, 130)
	power_label.text = "Power: 1/5"
	add_child(power_label)
	
	# Bomb label
	bomb_label = Label.new()
	bomb_label.position = Vector2(10, 160)
	bomb_label.text = "Bombs: 3"
	add_child(bomb_label)
	
	# Time stop bar
	time_stop_bar = ProgressBar.new()
	time_stop_bar.position = Vector2(10, 190)
	time_stop_bar.size = Vector2(200, 20)
	time_stop_bar.max_value = 100
	time_stop_bar.value = 0
	add_child(time_stop_bar)
	
	# Boss HP bar (hidden by default)
	boss_hp_bar = ProgressBar.new()
	boss_hp_bar.position = Vector2(140, 650)
	boss_hp_bar.size = Vector2(200, 30)
	boss_hp_bar.visible = false
	add_child(boss_hp_bar)

func _on_score_changed(new_score: int):
	score_label.text = "Score: " + str(new_score)

func _on_combo_changed(new_combo: int):
	combo_label.text = "Combo: " + str(new_combo)
	if new_combo > 0:
		combo_label.modulate = Color(1, 1, 0)
	else:
		combo_label.modulate = Color(1, 1, 1)

func _on_stage_changed(new_stage: int):
	stage_label.text = "Stage: " + str(new_stage)

func _on_hp_changed(new_hp: int):
	hp_bar.value = new_hp

func _on_power_changed(new_power: int):
	power_label.text = "Power: " + str(new_power) + "/5"

func _on_bomb_count_changed(new_count: int):
	bomb_label.text = "Bombs: " + str(new_count)

func _on_time_stop_energy_changed(new_energy: float):
	time_stop_bar.value = new_energy

func _on_boss_battle_started():
	boss_hp_bar.visible = true
	# Find boss and connect to its hp_changed signal
	await get_tree().create_timer(0.1).timeout
	var bosses = get_tree().get_nodes_in_group("bosses")
	if bosses.size() > 0:
		var boss = bosses[0]
		boss_hp_bar.max_value = boss.max_hp
		boss_hp_bar.value = boss.current_hp
		boss.hp_changed.connect(_on_boss_hp_changed)

func _on_boss_battle_ended():
	boss_hp_bar.visible = false

func _on_boss_hp_changed(current: int, _maximum: int):
	boss_hp_bar.value = current
