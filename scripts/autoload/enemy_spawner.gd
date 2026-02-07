extends Node

@export var enemy_scene: PackedScene
@export var boss_scene: PackedScene

var is_boss_active: bool = false

# Python-like spawn control (EmojiGame-master/emojigame/main.py)
var game_start_time: float = 0.0
var last_spawn_time: float = 0.0
var randomkis: float = 0.0
var max_enemies: int = 2
var current_wave: int = 1


func _ready() -> void:
	randomize()

	if not enemy_scene:
		enemy_scene = load("res://scenes/enemies/enemy.tscn")
	if not boss_scene:
		boss_scene = load("res://scenes/enemies/boss_enemy.tscn")

	game_start_time = Time.get_ticks_msec() / 1000.0
	last_spawn_time = game_start_time
	randomkis = 55.0 + 10.0 * randf()
	max_enemies = 2
	current_wave = 1


func _process(_delta: float) -> void:
	if GameManager.time_stop_active:
		return
	if StageManager.is_game_cleared():
		return

	match StageManager.current_phase:
		StageManager.StagePhase.STAGE:
			_process_stage()
		StageManager.StagePhase.BOSS:
			_process_boss()
		_:
			pass


func _process_stage() -> void:
	if is_boss_active:
		return

	var now := Time.get_ticks_msec() / 1000.0
	var elapsed := now - game_start_time

	# Python: maxEmemies increases slowly until ~55-65s, then stops.
	if elapsed <= randomkis:
		max_enemies = maxi(2, int(2.0 + (elapsed / 15.0)))

	var stage_enemies_count := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if ("is_boss" in e) and e.is_boss:
			continue
		stage_enemies_count += 1

	var interval := now - last_spawn_time
	# Python: interval >= 10 * random.random()
	if interval >= 10.0 * randf() and stage_enemies_count < max_enemies:
		_spawn_primary_enemy()
		last_spawn_time = now

		# Python: wave count increments per spawn, and waves drive elite/miniboss injections.
		current_wave += 1
		_spawn_wave_extras()


func _process_boss() -> void:
	if not is_boss_active:
		spawn_boss()


func _spawn_primary_enemy() -> void:
	if not enemy_scene:
		return

	var enemy := enemy_scene.instantiate() as Enemy
	if not enemy:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var half := 20.0

	# Match Python: 60% chance to use new enemy types when available.
	# Note: In Python, createEnemy reads the current_wave value *before* the increment in main.py.
	var use_new_types := randf() < 0.6
	if use_new_types:
		var kind: int = Enemy.EnemyKind.FAST
		if current_wave % 5 == 0 and randf() < 0.3:
			kind = Enemy.EnemyKind.ELITE
		elif randf() < 0.2:
			kind = Enemy.EnemyKind.SUICIDE
		else:
			var pool: Array[int] = [
				Enemy.EnemyKind.FAST,
				Enemy.EnemyKind.TANK,
				Enemy.EnemyKind.SNIPER,
				Enemy.EnemyKind.SPLIT
			]
			kind = pool[randi_range(0, pool.size() - 1)]

		enemy.enemy_kind = kind
		enemy.global_position = Vector2(
			viewport_size.x + randf_range(0.0, 100.0) + half,
			randf_range(50.0, max(50.0, viewport_size.y - 100.0)) + half
		)
	else:
		# Original enemy rint selection depends on bossdeathtimes.
		var boss_deaths := maxi(1, GameManager.boss_death_times)
		var max_base := 7
		if boss_deaths - 1 <= 3:
			max_base = 4 + (boss_deaths - 1)
		enemy.enemy_kind = randi_range(1, max_base)
		enemy.global_position = Vector2(
			viewport_size.x + half,
			randf_range(0.0, max(0.0, viewport_size.y - 80.0)) + half
		)

	get_parent().add_child(enemy)


func _spawn_wave_extras() -> void:
	if not enemy_scene:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var half := 20.0

	# Python wave system (main.py): every 10 waves -> 1 miniboss, every 5 waves -> 2 elite.
	if current_wave % 10 == 0:
		_spawn_enemy_with_kind(
			Enemy.EnemyKind.MINIBOSS,
			Vector2(
				viewport_size.x + randf_range(50.0, 150.0) + half,
				randf_range(100.0, max(100.0, viewport_size.y - 100.0)) + half
			)
		)
	elif current_wave % 5 == 0:
		for i in range(2):
			_spawn_enemy_with_kind(
				Enemy.EnemyKind.ELITE,
				Vector2(
					viewport_size.x + float(i) * 150.0 + half,
					randf_range(100.0, max(100.0, viewport_size.y - 100.0)) + half
				)
			)


func _spawn_enemy_with_kind(kind: int, pos: Vector2) -> void:
	var enemy := enemy_scene.instantiate() as Enemy
	if not enemy:
		return
	enemy.enemy_kind = kind
	enemy.global_position = pos
	get_parent().add_child(enemy)


func spawn_boss() -> void:
	if not boss_scene or is_boss_active:
		return

	is_boss_active = true

	# Remove stage enemies (Python: fade-out removeNormal).
	for e in get_tree().get_nodes_in_group("enemies"):
		if ("is_boss" in e) and e.is_boss:
			continue
		if e and e.is_inside_tree():
			e.queue_free()

	var viewport_size := get_viewport().get_visible_rect().size
	var boss := boss_scene.instantiate()
	if not boss:
		is_boss_active = false
		return

	if "boss_id" in boss:
		boss.boss_id = StageManager.current_stage

	# Python initial positions (BossEnemies.py)
	var half := 40.0
	var y := randf_range(0.0, max(0.0, viewport_size.y - 80.0))
	var boss_id := int(boss.get("boss_id")) if "boss_id" in boss else StageManager.current_stage
	if boss_id == 2:
		boss.global_position = Vector2(randf_range(800.0, 1100.0) + half, -80.0 + half)
	elif boss_id == 4 or boss_id == 5:
		boss.global_position = Vector2(randf_range(600.0, 800.0) + half, y + half)
	else:
		boss.global_position = Vector2(viewport_size.x + half, y + half)

	boss.tree_exited.connect(_on_boss_defeated)
	get_parent().add_child(boss)


func _on_boss_defeated() -> void:
	is_boss_active = false
	StageManager.on_boss_defeated()


func get_wave_number() -> int:
	return current_wave
