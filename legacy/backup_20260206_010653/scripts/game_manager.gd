class_name GameManager
extends Node

# Game state
var current_stage: int = 1
var max_stage: int = 6
var score: int = 0
var money: int = 0
var combo: int = 0
var combo_timer: float = 0.0
var combo_timeout: float = 2.0

# Stage management
var is_boss_battle: bool = false
var stage_timer: float = 0.0
var enemy_spawn_timer: float = 0.0
var enemy_spawn_interval: float = 2.0

# References
var player: Player
var enemy_scene: PackedScene
var boss_scenes: Array[PackedScene] = []

# Signals
signal score_changed(new_score: int)
signal money_changed(new_money: int)
signal combo_changed(new_combo: int)
signal stage_changed(new_stage: int)
signal boss_battle_started()
signal boss_battle_ended()
signal game_over()
signal game_won()

func _ready():
	add_to_group("game_manager")
	enemy_scene = preload("res://scenes/enemy.tscn")
	
	# Load boss scenes
	for i in range(6):
		boss_scenes.append(preload("res://scenes/boss.tscn"))
	
	# Find player
	player = get_tree().get_first_node_in_group("player")
	if player:
		player.player_died.connect(_on_player_died)

func _process(delta):
	stage_timer += delta
	
	# Update combo timer
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo = 0
			combo_changed.emit(combo)
	
	# Spawn enemies during normal stage
	if not is_boss_battle:
		enemy_spawn_timer -= delta
		if enemy_spawn_timer <= 0:
			spawn_enemy()
			enemy_spawn_timer = enemy_spawn_interval
		
		# Start boss battle after certain time
		if stage_timer > 30:
			start_boss_battle()

func spawn_enemy():
	var enemies_container = get_tree().get_first_node_in_group("enemies")
	if not enemies_container:
		return

	var enemy = enemy_scene.instantiate()
	enemy.position = Vector2(randf_range(50, 430), -20)
	enemy.movement_pattern = randi() % 4
	enemy.enemy_died.connect(_on_enemy_died)
	enemies_container.add_child(enemy)

func start_boss_battle():
	is_boss_battle = true
	boss_battle_started.emit()

	# Clear all enemies
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not enemy.is_in_group("bosses"):
			enemy.queue_free()

	# Spawn boss
	var boss_index = current_stage - 1
	if boss_index < boss_scenes.size():
		var enemies_container = get_tree().get_first_node_in_group("enemies")
		if enemies_container:
			var boss = boss_scenes[boss_index].instantiate()
			boss.boss_died.connect(_on_boss_died)
			enemies_container.add_child(boss)

func _on_enemy_died(score_value: int, pos: Vector2):
	add_score(score_value)
	increase_combo()

	# Random supply drop
	if randf() < 0.3:
		var supplies_container = get_tree().get_first_node_in_group("supplies")
		if supplies_container:
			var supply_type = randi() % 5
			var supply = Supply.spawn_supply(pos, supply_type, 1)
			supplies_container.add_child(supply)

func _on_boss_died(score_value: int):
	add_score(score_value)
	is_boss_battle = false
	boss_battle_ended.emit()
	
	# Next stage
	current_stage += 1
	if current_stage > max_stage:
		game_won.emit()
	else:
		stage_changed.emit(current_stage)
		stage_timer = 0.0

func add_score(amount: int):
	var multiplier = 1.0 + (float(combo) / 10.0)
	score += int(amount * multiplier)
	score_changed.emit(score)

func add_money(amount: int):
	money += amount
	money_changed.emit(money)

func increase_combo():
	combo += 1
	combo_timer = combo_timeout
	combo_changed.emit(combo)

func _on_player_died():
	game_over.emit()
	# Save high score
	save_game_data()

func save_game_data():
	var save_data = {
		"high_score": max(score, load_high_score()),
		"money": money
	}
	var file = FileAccess.open("user://save_data.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()

func load_high_score() -> int:
	if FileAccess.file_exists("user://save_data.json"):
		var file = FileAccess.open("user://save_data.json", FileAccess.READ)
		if file:
			var json = JSON.new()
			var parse_result = json.parse(file.get_as_text())
			file.close()
			if parse_result == OK:
				var data = json.get_data()
				return data.get("high_score", 0)
	return 0
