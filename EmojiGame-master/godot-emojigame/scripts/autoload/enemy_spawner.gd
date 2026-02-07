extends Node

@export var enemy_scene: PackedScene
@export var boss_scene: PackedScene
@export var spawn_interval_min: float = 1.5
@export var spawn_interval_max: float = 3.0

var spawn_timer: float = 0.0
var current_spawn_interval: float = 2.0
var wave_number: int = 0
var enemies_spawned: int = 0
var enemies_per_wave: int = 20
var is_boss_active: bool = false
var spawn_enabled: bool = true

# Spawn positions (right side of screen)
var spawn_positions: Array[Vector2] = [
	Vector2(1200, 100),
	Vector2(1200, 200),
	Vector2(1200, 300),
	Vector2(1200, 400),
	Vector2(1200, 500),
	Vector2(1200, 600)
]

func _ready():
	# Load scenes if not set
	if not enemy_scene:
		enemy_scene = load("res://scenes/enemies/enemy.tscn")
	if not boss_scene:
		boss_scene = load("res://scenes/enemies/boss_enemy.tscn")

	# Set random spawn interval
	randomize_spawn_interval()

func _process(delta):
	if not spawn_enabled:
		return

	spawn_timer += delta

	if spawn_timer >= current_spawn_interval:
		spawn_enemy()
		spawn_timer = 0.0
		randomize_spawn_interval()

func spawn_enemy():
	if is_boss_active:
		return

	if not enemy_scene:
		return

	var enemy = enemy_scene.instantiate()

	# Random spawn position
	var spawn_pos = spawn_positions[randi() % spawn_positions.size()]
	enemy.global_position = spawn_pos

	# Scale difficulty with wave number
	enemy.health = int(enemy.health * (1 + wave_number * 0.5))
	enemy.speed += wave_number * 10

	# Add to scene
	get_parent().add_child(enemy)
	enemies_spawned += 1

	# Check if should spawn boss
	if enemies_spawned >= enemies_per_wave:
		spawn_boss()

func spawn_boss():
	if not boss_scene or is_boss_active:
		return

	# Stop regular spawning
	spawn_enabled = false
	is_boss_active = true

	# Wait a bit before spawning boss
	await get_tree().create_timer(2.0).timeout

	var boss = boss_scene.instantiate()
	boss.global_position = Vector2(1000, 300)

	# Set boss ID based on wave (1-5, cycling)
	boss.boss_id = (wave_number % 5) + 1

	# Scale boss health with wave
	boss.max_health = int(boss.max_health * (1 + wave_number * 0.3))
	boss.health = boss.max_health

	# Connect boss death signal
	boss.tree_exited.connect(_on_boss_defeated)

	get_parent().add_child(boss)

func _on_boss_defeated():
	# Boss defeated - start new wave
	is_boss_active = false
	wave_number += 1
	enemies_spawned = 0

	# Increase difficulty
	enemies_per_wave += 5

	# Resume spawning after delay
	await get_tree().create_timer(3.0).timeout
	spawn_enabled = true

func randomize_spawn_interval():
	current_spawn_interval = randf_range(spawn_interval_min, spawn_interval_max)

func stop_spawning():
	spawn_enabled = false

func start_spawning():
	spawn_enabled = true

func reset():
	wave_number = 0
	enemies_spawned = 0
	enemies_per_wave = 20
	is_boss_active = false
	spawn_enabled = true
