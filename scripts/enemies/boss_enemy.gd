extends Enemy
class_name BossEnemy

@export var boss_health: int = 2000
@export var boss_id: int = 1  # 1-6
@export var boss_speed: float = 100.0

var current_phase: int = 1
var is_phase_boss: bool = false

var current_pattern: int = 0
var pattern_timer: float = 0.0
var pattern_interval: float = 3.0
var is_boss: bool = true

var movement_timer: float = 0.0

# Spell card (Python parity: first death enters a stronger second phase)
var spell_card_active: bool = false
var spell_card_invulnerable_until: float = 0.0

# Boss enhancement parity
var shield_enabled: bool = false
var boss_shield_hp: int = 0
var boss_shield_hp_max: int = 0
var shield_regen_rate: float = 0.0
var shield_regen_delay: float = 5.0
var last_damage_time: float = 0.0

var absorb_hits_remaining: int = 0

var invincible_cycle_enabled: bool = false
var invincible_cycle_duration: float = 0.0
var invincible_cycle_interval: float = 0.0
var invincible_cycle_timer: float = 0.0
var invincible_cycle_elapsed: float = 0.0
var invincible_cycle_active: bool = false

var summon_enabled: bool = false
var summon_interval: float = 0.0
var summon_timer: float = 0.0
var summon_count: int = 0

var enrage_enabled: bool = false
var enraged: bool = false

var phase_transition_enabled: bool = false
var phase_thresholds: Array[float] = [0.75, 0.5, 0.25]
var phase_threshold_triggered: Dictionary = {}

func _ready() -> void:
	super._ready()

	var stage: int = maxi(1, int(StageManager.current_stage))
	var base_hp: int = maxi(int(boss_health), 1200 + (stage - 1) * 900)
	if boss_id == 6:
		base_hp *= 5
		is_phase_boss = true

	boss_health = base_hp
	health = boss_health
	max_health = boss_health
	speed = boss_speed + float(stage - 1) * 12.0
	score_value = 10000 + (stage - 1) * 1200
	damage = 20 + (stage - 1) * 2

	_setup_attack_timing()
	_apply_boss_visual()
	_setup_enhancements()
	last_damage_time = Time.get_ticks_msec() / 1000.0

	if shoot_timer:
		shoot_timer.wait_time = shoot_cooldown

func _setup_attack_timing() -> void:
	match boss_id:
		1:
			shoot_cooldown = 0.6
			pattern_interval = 3.0
		2:
			shoot_cooldown = 1.5
			pattern_interval = 5.0
		3:
			shoot_cooldown = 1.0
			pattern_interval = 3.5
		4:
			shoot_cooldown = 1.8
			pattern_interval = 4.0
		5:
			shoot_cooldown = 1.8
			pattern_interval = 4.0
		6:
			shoot_cooldown = 1.2
			pattern_interval = 3.8
		_:
			shoot_cooldown = 1.0
			pattern_interval = 3.0

func _apply_boss_visual() -> void:
	var texture_path: String = "res://assets/sprites/bossenemy-%d.png" % clampi(boss_id, 1, 6)
	var tex: Texture2D = load(texture_path)
	if sprite and tex:
		sprite.texture = tex
		sprite.scale = Vector2.ONE
		sprite.modulate = Color(1, 1, 1, 1)

	var body_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape and body_shape.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = body_shape.shape as RectangleShape2D
		rect_shape.size = Vector2(80, 80)

func _setup_enhancements() -> void:
	var difficulty: int = clampi(int(StageManager.current_stage), 1, 5)

	shield_enabled = true
	boss_shield_hp_max = int(round(float(max_health) * (0.2 + float(difficulty) * 0.1)))
	boss_shield_hp = boss_shield_hp_max
	shield_regen_rate = float(max_health) * (0.004 + 0.002 * float(difficulty))

	match difficulty:
		1:
			enrage_enabled = false
		2:
			enrage_enabled = true
		3:
			enrage_enabled = true
			summon_enabled = true
			summon_interval = 14.0
			summon_count = 2
			phase_transition_enabled = true
		4:
			enrage_enabled = true
			summon_enabled = true
			summon_interval = 12.0
			summon_count = 3
			phase_transition_enabled = true
			invincible_cycle_enabled = true
			invincible_cycle_duration = 2.5
			invincible_cycle_interval = 14.0
		5:
			enrage_enabled = true
			summon_enabled = true
			summon_interval = 10.0
			summon_count = 4
			phase_transition_enabled = true
			invincible_cycle_enabled = true
			invincible_cycle_duration = 3.2
			invincible_cycle_interval = 12.0
			absorb_hits_remaining = 15

func _physics_process(delta: float) -> void:
	if GameManager.time_stop_active:
		return

	_update_enhancements(delta)

	if is_phase_boss and boss_id == 6:
		update_boss6_phase()

	boss_movement(delta)

	pattern_timer += delta
	if pattern_timer >= pattern_interval:
		execute_boss_pattern()
		pattern_timer = 0.0

func _update_enhancements(delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0

	if not shield_enabled and boss_shield_hp < boss_shield_hp_max and now - last_damage_time > shield_regen_delay:
		boss_shield_hp = mini(boss_shield_hp_max, boss_shield_hp + int(round(shield_regen_rate * delta)))
		if boss_shield_hp >= boss_shield_hp_max:
			shield_enabled = true

	if invincible_cycle_enabled:
		if invincible_cycle_active:
			invincible_cycle_elapsed += delta
			if invincible_cycle_elapsed >= invincible_cycle_duration:
				invincible_cycle_active = false
				invincible_cycle_elapsed = 0.0
				invincible_cycle_timer = 0.0
		else:
			invincible_cycle_timer += delta
			if invincible_cycle_timer >= invincible_cycle_interval:
				invincible_cycle_active = true
				invincible_cycle_elapsed = 0.0
				invincible_cycle_timer = 0.0

	if summon_enabled:
		summon_timer += delta
		if summon_timer >= summon_interval:
			summon_timer = 0.0
			_summon_minions()

	if enrage_enabled and not enraged and float(health) / float(max_health) <= 0.3:
		enraged = true
		speed *= 1.5
		shoot_cooldown = maxf(0.18, shoot_cooldown / 2.0)
		pattern_interval = maxf(1.0, pattern_interval * 0.7)
		if shoot_timer:
			shoot_timer.wait_time = shoot_cooldown

	if phase_transition_enabled:
		var hp_ratio: float = float(health) / float(max_health)
		for i in range(phase_thresholds.size()):
			if not phase_threshold_triggered.get(i, false) and hp_ratio <= phase_thresholds[i]:
				phase_threshold_triggered[i] = true
				_on_phase_transition(i)
				break

func _on_phase_transition(phase_index: int) -> void:
	_clear_enemy_bullets()
	match phase_index:
		0:
			shoot_cooldown = maxf(0.2, shoot_cooldown * 0.8)
		1:
			speed *= 1.25
		2:
			shoot_cooldown = maxf(0.15, shoot_cooldown * 0.75)
			speed *= 1.2

	if shoot_timer:
		shoot_timer.wait_time = shoot_cooldown

func _summon_minions() -> void:
	var enemy_scene_ref: PackedScene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref or not get_parent():
		return

	var minion_pool: Array[int] = [
		EnemyKind.FAST,
		EnemyKind.TANK,
		EnemyKind.SUICIDE,
		EnemyKind.SNIPER
	]

	for _i in range(summon_count):
		var minion: Enemy = enemy_scene_ref.instantiate() as Enemy
		if not minion:
			continue
		minion.enemy_kind = minion_pool[randi_range(0, minion_pool.size() - 1)]
		minion.global_position = global_position + Vector2(randf_range(-120.0, 120.0), randf_range(-80.0, 80.0))
		get_parent().add_child(minion)

func _clear_enemy_bullets() -> void:
	var bullets: Array = get_tree().get_nodes_in_group("enemy_bullets")
	for bullet in bullets:
		if is_instance_valid(bullet):
			bullet.queue_free()

func _is_invincible() -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	return now < spell_card_invulnerable_until or invincible_cycle_active

func take_damage(amount: int) -> void:
	if _is_invincible():
		return

	last_damage_time = Time.get_ticks_msec() / 1000.0
	var pending_damage: int = amount

	if absorb_hits_remaining > 0:
		absorb_hits_remaining -= 1
		pending_damage = 0

	if shield_enabled and boss_shield_hp > 0 and pending_damage > 0:
		boss_shield_hp -= pending_damage
		if boss_shield_hp <= 0:
			pending_damage = abs(boss_shield_hp)
			shield_enabled = false
		else:
			pending_damage = 0

	if pending_damage > 0:
		health -= pending_damage
		_flash_damage()

	if health <= 0:
		die()

func _flash_damage() -> void:
	if not sprite:
		return
	sprite.modulate = Color(1.2, 0.7, 0.7, 1)
	await get_tree().create_timer(0.05).timeout
	if is_instance_valid(self):
		_apply_boss_visual()

func die() -> void:
	if not spell_card_active:
		_enter_spell_card_phase()
		return

	GameManager.register_boss_kill(score_value)
	_spawn_boss_rewards()
	_clear_enemy_bullets()
	queue_free()

func _enter_spell_card_phase() -> void:
	spell_card_active = true
	health = max_health
	shield_enabled = true
	boss_shield_hp = boss_shield_hp_max
	_clear_enemy_bullets()

	var viewport_size: Vector2 = get_viewport_rect().size
	global_position = Vector2(viewport_size.x - 320.0, 160.0)

	spell_card_invulnerable_until = (Time.get_ticks_msec() / 1000.0) + 1.0
	speed *= 1.2
	shoot_cooldown = maxf(0.15, shoot_cooldown * 0.75)
	pattern_interval = maxf(0.8, pattern_interval * 0.7)
	if shoot_timer:
		shoot_timer.wait_time = shoot_cooldown

func _spawn_boss_rewards() -> void:
	# Python parity (Event.bossDeath): drop generateSupply(1) 1-5 times.
	# Boss uses 80x80 sprites => Python top-left is center - (40,40).
	var boss_pos: Vector2 = global_position - Vector2(40.0, 40.0)
	for _i in range(randi_range(1, 5)):
		_generate_supply(1.0, boss_pos)

func update_boss6_phase() -> void:
	var health_percent: float = float(health) / float(max_health)
	if health_percent > 0.8:
		current_phase = 1
	elif health_percent > 0.6:
		current_phase = 2
	elif health_percent > 0.4:
		current_phase = 3
	elif health_percent > 0.2:
		current_phase = 4
	else:
		current_phase = 5

func boss_movement(delta: float) -> void:
	movement_timer += delta

	match boss_id:
		1:
			if movement_timer > 2.0:
				if direction.y != 0.0:
					direction.y = -direction.y
				else:
					direction.y = 1.0
				movement_timer = 0.0
			position.y += direction.y * speed * delta
		2:
			if position.y < 220:
				position.y += speed * delta
			else:
				position.y = 220
		3, 4, 5:
			position.y += sin(movement_timer * 2.0) * speed * delta * 0.5
		6:
			match current_phase:
				1, 2:
					position.y += sin(movement_timer * 3.0) * speed * delta * 0.8
				3, 4:
					position.x += cos(movement_timer * 2.0) * speed * delta * 0.3
					position.y += sin(movement_timer * 2.0) * speed * delta * 0.8
				5:
					if int(movement_timer * 2.0) % 2 == 0:
						position.y += sin(movement_timer * 5.0) * speed * delta * 1.5

	var viewport_size: Vector2 = get_viewport_rect().size
	position.x = clampf(position.x, viewport_size.x * 0.55, viewport_size.x - 90.0)
	position.y = clampf(position.y, 70.0, viewport_size.y - 80.0)

func execute_boss_pattern() -> void:
	match boss_id:
		1:
			boss1_pattern()
		2:
			boss2_pattern()
		3:
			boss3_pattern()
		4:
			boss4_pattern()
		5:
			boss5_pattern()
		6:
			boss6_pattern()

	if spell_card_active:
		shoot_circle()

	current_pattern = (current_pattern + 1) % 3

func boss1_pattern() -> void:
	shoot_spiral_pattern(16, 2.0)

func boss2_pattern() -> void:
	for _i in range(3):
		await get_tree().create_timer(0.2).timeout
		shoot_tracking_burst()

func boss3_pattern() -> void:
	shoot_triple()
	await get_tree().create_timer(0.3).timeout
	shoot_circle()

func boss4_pattern() -> void:
	shoot_spiral_pattern(24, 1.5)

func boss5_pattern() -> void:
	shoot_double_spiral()
	await get_tree().create_timer(0.5).timeout
	shoot_tracking_burst()

func boss6_pattern() -> void:
	match current_phase:
		1:
			shoot_triple_spiral()
		2:
			shoot_dense_tracking()
		3:
			shoot_pentagram()
		4:
			shoot_chaos_pattern()
		5:
			shoot_ultimate_pattern()

func shoot_spiral_pattern(bullet_count: int, rotation_speed: float) -> void:
	var base_angle: float = movement_timer * rotation_speed
	for i in range(bullet_count):
		var angle: float = base_angle + (2.0 * PI / bullet_count) * i
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		spawn_bullet(dir, 300.0, EnemyBullet.BulletType.NORMAL)

func shoot_double_spiral() -> void:
	var base_angle: float = movement_timer * 2.0
	for i in range(12):
		var angle1: float = base_angle + (2.0 * PI / 12.0) * i
		var angle2: float = -base_angle + (2.0 * PI / 12.0) * i
		var dir1: Vector2 = Vector2(cos(angle1), sin(angle1))
		var dir2: Vector2 = Vector2(cos(angle2), sin(angle2))
		spawn_bullet(dir1, 250.0, EnemyBullet.BulletType.NORMAL)
		spawn_bullet(dir2, 350.0, EnemyBullet.BulletType.NORMAL)

func shoot_tracking_burst() -> void:
	for _i in range(2):
		spawn_bullet(Vector2.LEFT, 500.0, EnemyBullet.BulletType.TRACKING)

func shoot_triple() -> void:
	spawn_bullet(Vector2.LEFT, 400.0, EnemyBullet.BulletType.NORMAL)
	spawn_bullet(Vector2.LEFT.rotated(0.2), 400.0, EnemyBullet.BulletType.NORMAL)
	spawn_bullet(Vector2.LEFT.rotated(-0.2), 400.0, EnemyBullet.BulletType.NORMAL)

func shoot_triple_spiral() -> void:
	var base_angle: float = movement_timer * 2.5
	for spiral in range(3):
		var spiral_offset: float = (2.0 * PI / 3.0) * spiral
		for i in range(8):
			var angle: float = base_angle + spiral_offset + (2.0 * PI / 8.0) * i
			var dir: Vector2 = Vector2(cos(angle), sin(angle))
			spawn_bullet(dir, 280.0, EnemyBullet.BulletType.NORMAL)

func shoot_dense_tracking() -> void:
	for i in range(5):
		spawn_bullet(Vector2.LEFT, 450.0 + i * 50.0, EnemyBullet.BulletType.TRACKING)
		await get_tree().create_timer(0.15).timeout

func shoot_pentagram() -> void:
	for i in range(5):
		var angle: float = (2.0 * PI / 5.0) * i - PI / 2.0
		for j in range(5):
			var spread_angle: float = angle + (j - 2) * 0.15
			var spread_dir: Vector2 = Vector2(cos(spread_angle), sin(spread_angle))
			spawn_bullet(spread_dir, 320.0, EnemyBullet.BulletType.SAND)

func shoot_chaos_pattern() -> void:
	shoot_spiral_pattern(20, 3.0)
	await get_tree().create_timer(0.2).timeout
	for _i in range(3):
		spawn_bullet(Vector2.LEFT, 500.0, EnemyBullet.BulletType.TRACKING)
	await get_tree().create_timer(0.2).timeout
	shoot_circle()

func shoot_ultimate_pattern() -> void:
	shoot_triple_spiral()
	await get_tree().create_timer(0.3).timeout
	var bullet_count: int = 24
	for i in range(bullet_count):
		var angle: float = (2.0 * PI / bullet_count) * i
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		spawn_bullet(dir, 300.0, EnemyBullet.BulletType.CIRCLE)
	await get_tree().create_timer(0.3).timeout
	for _i in range(6):
		spawn_bullet(Vector2.LEFT, 550.0, EnemyBullet.BulletType.TRACKING)

func shoot() -> void:
	can_shoot = false
	match boss_id:
		2:
			shoot_tracking()
		3:
			if current_pattern == 0:
				shoot_triple()
			else:
				shoot_tracking()
		6:
			match current_phase:
				1:
					shoot_tracking()
				2:
					shoot_sand()
				3, 4:
					shoot_circle()
				5:
					shoot_tracking()
					shoot_circle()
		_:
			super.shoot()
