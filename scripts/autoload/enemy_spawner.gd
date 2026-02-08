extends Node

@export var enemy_scene: PackedScene
@export var boss_scene: PackedScene

@export var midboss_enabled: bool = true
@export var midboss_spawn_ratio: float = 0.55 # 0..1 of stage_duration
@export var stage_script_enabled: bool = true

var is_boss_active: bool = false
var is_midboss_active: bool = false
var _midboss_spawned_this_stage: bool = false

# Python-like spawn control (EmojiGame-master/emojigame/main.py)
var game_start_time: float = 0.0
var last_spawn_time: float = 0.0
var randomkis: float = 0.0
var max_enemies: int = 2
var current_wave: int = 1

class StageAction:
	var t: float = 0.0
	var action: Callable = Callable()

var _stage_actions: Array[StageAction] = []
var _stage_action_index: int = 0

func _make_stage_action(t: float, action: Callable) -> StageAction:
	var a := StageAction.new()
	a.t = maxf(0.0, t)
	a.action = action
	return a


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
	is_midboss_active = false
	_midboss_spawned_this_stage = false
	_rebuild_stage_script()

	if StageManager and StageManager.has_signal("phase_changed"):
		StageManager.phase_changed.connect(_on_stage_phase_changed)


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
	if is_midboss_active:
		return

	if midboss_enabled and not _midboss_spawned_this_stage:
		var ratio := clampf(midboss_spawn_ratio, 0.05, 0.95)
		if StageManager.stage_elapsed >= StageManager.stage_duration * ratio:
			_spawn_midboss()
			return

	if stage_script_enabled:
		_process_stage_script()
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

func _on_stage_phase_changed(new_phase: int) -> void:
	if new_phase != StageManager.StagePhase.STAGE:
		return
	_reset_stage_state()

func _reset_stage_state() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	game_start_time = now
	last_spawn_time = now
	randomkis = 55.0 + 10.0 * randf()
	max_enemies = 2
	current_wave = 1
	is_midboss_active = false
	_midboss_spawned_this_stage = false
	_rebuild_stage_script()
	if StageManager and StageManager.has_method("set_midboss_active"):
		StageManager.set_midboss_active(false)

func _rebuild_stage_script() -> void:
	_stage_actions = []
	_stage_action_index = 0
	if not stage_script_enabled:
		return
	if not StageManager:
		return
	_stage_actions = _build_stage_actions(int(StageManager.current_stage))

func _process_stage_script() -> void:
	if _stage_actions.is_empty():
		return
	while _stage_action_index < _stage_actions.size():
		var a := _stage_actions[_stage_action_index]
		if StageManager.stage_elapsed < a.t:
			return
		if a.action.is_valid():
			a.action.call()
		_stage_action_index += 1
		current_wave += 1

func _build_stage_actions(stage: int) -> Array[StageAction]:
	var s := clampi(stage, 1, 6)
	var actions: Array[StageAction] = []

	# Touhou-like: scripted formations on a timeline (stage_elapsed seconds).
	# Keep it deterministic; difficulty is driven by stage number and formations.
	var t := 0.6
	var gap := 2.8
	for wave in range(14):
		var kind := _pick_stage_enemy_kind(s, wave)
		match wave % 4:
			0:
				actions.append(_make_stage_action(t, Callable(self, "_spawn_line").bind(kind, 6, Enemy.ScriptedMoveMode.STRAIGHT_LEFT)))
			1:
				actions.append(_make_stage_action(t, Callable(self, "_spawn_v").bind(kind, 5, Enemy.ScriptedMoveMode.SINE_LEFT, 70.0, 2.4)))
			2:
				actions.append(_make_stage_action(t, Callable(self, "_spawn_pair_stoppers").bind(Enemy.EnemyKind.SNIPER, 900.0, 2.2)))
			_:
				actions.append(_make_stage_action(t, Callable(self, "_spawn_divers").bind(kind, 4)))

		t += gap

	# Late stage push (before boss): a few denser formations.
	actions.append(_make_stage_action(44.0, Callable(self, "_spawn_line").bind(_pick_stage_enemy_kind(s, 99), 8, Enemy.ScriptedMoveMode.SINE_LEFT)))
	actions.append(_make_stage_action(49.0, Callable(self, "_spawn_divers").bind(_pick_stage_enemy_kind(s, 100), 6)))
	return actions

func _pick_stage_enemy_kind(stage: int, wave: int) -> int:
	match stage:
		1:
			var pool1: Array[int] = [Enemy.EnemyKind.BASE_1, Enemy.EnemyKind.BASE_2, Enemy.EnemyKind.FAST, Enemy.EnemyKind.SNIPER]
			return pool1[wave % pool1.size()]
		2:
			var pool2: Array[int] = [Enemy.EnemyKind.BASE_4, Enemy.EnemyKind.BASE_5, Enemy.EnemyKind.SHIELD, Enemy.EnemyKind.SPLIT, Enemy.EnemyKind.FAST]
			return pool2[wave % pool2.size()]
		3:
			var pool3: Array[int] = [Enemy.EnemyKind.TANK, Enemy.EnemyKind.SUICIDE, Enemy.EnemyKind.SNIPER, Enemy.EnemyKind.BASE_6]
			return pool3[wave % pool3.size()]
		4:
			var pool4: Array[int] = [Enemy.EnemyKind.FAST, Enemy.EnemyKind.ELITE, Enemy.EnemyKind.SHIELD, Enemy.EnemyKind.BASE_7]
			return pool4[wave % pool4.size()]
		5:
			var pool5: Array[int] = [Enemy.EnemyKind.ELITE, Enemy.EnemyKind.TANK, Enemy.EnemyKind.SUICIDE, Enemy.EnemyKind.SPLIT]
			return pool5[wave % pool5.size()]
		6:
			var pool6: Array[int] = [Enemy.EnemyKind.ELITE, Enemy.EnemyKind.SUICIDE, Enemy.EnemyKind.SNIPER, Enemy.EnemyKind.SHIELD]
			return pool6[wave % pool6.size()]
		_:
			return Enemy.EnemyKind.BASE_1

func _spawn_enemy_scripted(kind: int, pos: Vector2, move_mode: int, sine_amp: float, sine_freq: float) -> void:
	if not enemy_scene or not get_parent():
		return
	var enemy := enemy_scene.instantiate() as Enemy
	if not enemy:
		return
	enemy.enemy_kind = kind
	enemy.scripted_move_mode = move_mode
	enemy.scripted_sine_amplitude = sine_amp
	enemy.scripted_sine_frequency = sine_freq
	enemy.global_position = pos
	get_parent().add_child(enemy)

func _playfield_bottom() -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	return playfield_bottom

func _spawn_line(kind: int, count: int, move_mode: int) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var playfield_bottom := _playfield_bottom()
	var n := maxi(1, count)
	var top := 80.0
	var bottom := maxf(top + 40.0, playfield_bottom - 140.0)
	var span := maxf(1.0, bottom - top)

	for i in range(n):
		var t := float(i) / float(maxi(1, n - 1))
		var y := top + span * t
		var x := viewport_size.x + 80.0 + float(i) * 55.0
		_spawn_enemy_scripted(kind, Vector2(x, y), move_mode, 60.0, 2.2)

func _spawn_v(kind: int, count: int, move_mode: int, sine_amp: float, sine_freq: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var playfield_bottom := _playfield_bottom()
	var center_y := clampf(playfield_bottom * 0.5, 140.0, playfield_bottom - 160.0)
	var n := maxi(3, count)
	var half := int(floor(float(n) / 2.0))
	for i in range(n):
		var offset := float(i - half) * 70.0
		var y := clampf(center_y + offset, 80.0, playfield_bottom - 140.0)
		var x := viewport_size.x + 60.0 + float(i) * 60.0
		_spawn_enemy_scripted(kind, Vector2(x, y), move_mode, sine_amp, sine_freq)

func _spawn_pair_stoppers(kind: int, stop_x: float, stop_duration: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var playfield_bottom := _playfield_bottom()
	var ys := [140.0, maxf(140.0, playfield_bottom - 220.0)]
	for i in range(ys.size()):
		if not enemy_scene or not get_parent():
			return
		var enemy := enemy_scene.instantiate() as Enemy
		if not enemy:
			continue
		enemy.enemy_kind = kind
		enemy.scripted_move_mode = Enemy.ScriptedMoveMode.STOP_AND_GO
		enemy.scripted_stop_x = stop_x
		enemy.scripted_stop_duration = stop_duration
		enemy.global_position = Vector2(viewport_size.x + 120.0 + float(i) * 120.0, float(ys[i]))
		get_parent().add_child(enemy)

func _spawn_divers(kind: int, count: int) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var playfield_bottom := _playfield_bottom()
	var n := maxi(1, count)
	for i in range(n):
		var y := randf_range(90.0, maxf(90.0, playfield_bottom - 140.0))
		var x := viewport_size.x + 80.0 + float(i) * 80.0
		_spawn_enemy_scripted(kind, Vector2(x, y), Enemy.ScriptedMoveMode.DIVE_AT_PLAYER, 0.0, 0.0)

func _spawn_midboss() -> void:
	if not enemy_scene:
		return
	if not get_parent():
		return

	_midboss_spawned_this_stage = true
	is_midboss_active = true
	if StageManager and StageManager.has_method("set_midboss_active"):
		StageManager.set_midboss_active(true)

	# Clear stage enemies/bullets for a clean midboss segment (Touhou-like).
	for e in get_tree().get_nodes_in_group("enemies"):
		if e and is_instance_valid(e) and e.is_inside_tree():
			e.queue_free()
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	for z in get_tree().get_nodes_in_group("slow_zone"):
		if z and is_instance_valid(z):
			z.queue_free()
	for h in get_tree().get_nodes_in_group("boss_hazards"):
		if h and is_instance_valid(h):
			h.queue_free()

	var viewport_size := get_viewport().get_visible_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	# Prefer a real BossEnemy so the midboss has proper spellcard phases.
	var midboss: Node = null
	if boss_scene:
		midboss = boss_scene.instantiate()

	if midboss and ("is_midboss" in midboss):
		midboss.is_midboss = true
	if midboss and ("boss_id" in midboss):
		midboss.boss_id = int(StageManager.current_stage)

	if midboss and (midboss is Node2D):
		var half := 40.0
		(midboss as Node2D).global_position = Vector2(
			viewport_size.x + randf_range(40.0, 160.0) + half,
			randf_range(120.0, max(120.0, playfield_bottom - 180.0)) + half
		)
		midboss.tree_exited.connect(_on_midboss_defeated)
		get_parent().add_child(midboss)
		return

	# Fallback: legacy MINIBOSS enemy.
	var legacy := enemy_scene.instantiate() as Enemy
	if not legacy:
		is_midboss_active = false
		if StageManager and StageManager.has_method("set_midboss_active"):
			StageManager.set_midboss_active(false)
		return
	legacy.enemy_kind = Enemy.EnemyKind.MINIBOSS
	var legacy_half := 20.0
	legacy.global_position = Vector2(
		viewport_size.x + randf_range(0.0, 100.0) + legacy_half,
		randf_range(80.0, max(80.0, playfield_bottom - 120.0)) + legacy_half
	)
	legacy.tree_exited.connect(_on_midboss_defeated)
	get_parent().add_child(legacy)

func _on_midboss_defeated() -> void:
	is_midboss_active = false
	if StageManager and StageManager.has_method("set_midboss_active"):
		StageManager.set_midboss_active(false)
	# Cleanup any lingering bullets/hazards from the midboss segment.
	if not is_inside_tree():
		return
	var tree := get_tree()
	for b in tree.get_nodes_in_group("enemy_bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	for z in tree.get_nodes_in_group("slow_zone"):
		if z and is_instance_valid(z):
			z.queue_free()
	for h in tree.get_nodes_in_group("boss_hazards"):
		if h and is_instance_valid(h):
			h.queue_free()
	for p in tree.get_nodes_in_group("prevent"):
		if p and is_instance_valid(p):
			p.queue_free()
	last_spawn_time = Time.get_ticks_msec() / 1000.0


func _spawn_primary_enemy() -> void:
	if not enemy_scene:
		return

	var enemy := enemy_scene.instantiate() as Enemy
	if not enemy:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
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
			randf_range(50.0, max(50.0, playfield_bottom - 100.0)) + half
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
			randf_range(0.0, max(0.0, playfield_bottom - 80.0)) + half
		)

	get_parent().add_child(enemy)


func _spawn_wave_extras() -> void:
	if not enemy_scene:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	var half := 20.0

	# Python wave system (main.py): every 10 waves -> 1 miniboss, every 5 waves -> 2 elite.
	if current_wave % 10 == 0:
		_spawn_enemy_with_kind(
			Enemy.EnemyKind.MINIBOSS,
			Vector2(
				viewport_size.x + randf_range(50.0, 150.0) + half,
				randf_range(100.0, max(100.0, playfield_bottom - 100.0)) + half
			)
		)
	elif current_wave % 5 == 0:
		for i in range(2):
			_spawn_enemy_with_kind(
				Enemy.EnemyKind.ELITE,
				Vector2(
					viewport_size.x + float(i) * 150.0 + half,
					randf_range(100.0, max(100.0, playfield_bottom - 100.0)) + half
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
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	var y := randf_range(0.0, max(0.0, playfield_bottom - 80.0))
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
