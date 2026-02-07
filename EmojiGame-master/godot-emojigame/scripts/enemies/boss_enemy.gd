extends Enemy
class_name BossEnemy

@export var boss_health: int = 2000
@export var boss_id: int = 1  # 1-6 different boss types
@export var boss_speed: float = 100.0

# Boss6 phase system (5 phases)
var current_phase: int = 1
var is_phase_boss: bool = false

var current_pattern: int = 0
var pattern_timer: float = 0.0
var pattern_interval: float = 3.0
var is_boss: bool = true

# Boss specific movement
var movement_phase: int = 0
var movement_timer: float = 0.0

func _ready():
	super._ready()

	# Boss6有5倍血量（5阶段Boss）
	if boss_id == 6:
		boss_health = boss_health * 5
		is_phase_boss = true

	health = boss_health
	max_health = boss_health
	speed = boss_speed
	score_value = 1000
	damage = 20

	# Adjust shoot cooldown based on boss type
	match boss_id:
		1:
			shoot_cooldown = 0.6
		2:
			shoot_cooldown = 1.5
			pattern_interval = 5.0
		3:
			shoot_cooldown = 1.0
		4:
			shoot_cooldown = 1.8
		5:
			shoot_cooldown = 1.8
		6:
			shoot_cooldown = 1.2
			pattern_interval = 4.0
		_:
			shoot_cooldown = 1.0

	if shoot_timer:
		shoot_timer.wait_time = shoot_cooldown

func _physics_process(delta):
	# Boss6阶段更新
	if is_phase_boss and boss_id == 6:
		update_boss6_phase()

	# Boss specific movement patterns
	boss_movement(delta)

	# Pattern-based attacks
	pattern_timer += delta
	if pattern_timer >= pattern_interval:
		execute_boss_pattern()
		pattern_timer = 0.0

	# Regular shooting still happens via parent class

func update_boss6_phase():
	"""更新Boss6的阶段（5阶段）"""
	var health_percent = float(health) / float(max_health)
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

func boss_movement(delta):
	movement_timer += delta

	match boss_id:
		1:  # Boss 1: Vertical movement
			if movement_timer > 2.0:
				direction.y = -direction.y if direction.y != 0 else 1
				movement_timer = 0.0
			position.y += direction.y * speed * delta

		2:  # Boss 2: Comes from top, stops
			if position.y < 200:
				position.y += speed * delta
			else:
				position.y = 200

		3, 4, 5:  # Other bosses: Circular/wave movement
			position.y += sin(movement_timer * 2) * speed * delta * 0.5

		6:  # Boss6: 根据阶段改变移动模式
			match current_phase:
				1, 2:  # 阶段1-2: 波浪移动
					position.y += sin(movement_timer * 3) * speed * delta * 0.8
				3, 4:  # 阶段3-4: 圆形移动
					position.x += cos(movement_timer * 2) * speed * delta * 0.3
					position.y += sin(movement_timer * 2) * speed * delta * 0.8
				5:  # 阶段5: 快速随机移动
					if int(movement_timer * 2) % 2 == 0:
						position.y += sin(movement_timer * 5) * speed * delta * 1.5

	# Clamp boss position to screen
	position.x = clamp(position.x, 800, 1100)
	position.y = clamp(position.y, 50, 600)

func execute_boss_pattern():
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

	current_pattern = (current_pattern + 1) % 3

# Boss 1: Simple spiral pattern
func boss1_pattern():
	shoot_spiral_pattern(16, 2.0)

# Boss 2: Tracking bullets
func boss2_pattern():
	for i in range(3):
		await get_tree().create_timer(0.2).timeout
		shoot_tracking_burst()

# Boss 3: Triple shot + circle
func boss3_pattern():
	shoot_triple()
	await get_tree().create_timer(0.3).timeout
	shoot_circle()

# Boss 4: Dense spiral
func boss4_pattern():
	shoot_spiral_pattern(24, 1.5)

# Boss 5: Double spiral + tracking
func boss5_pattern():
	shoot_double_spiral()
	await get_tree().create_timer(0.5).timeout
	shoot_tracking_burst()

# Boss 6: 根据阶段使用不同的超强弹幕
func boss6_pattern():
	match current_phase:
		1:  # 阶段1: 三重螺旋
			shoot_triple_spiral()
		2:  # 阶段2: 密集追踪弹
			shoot_dense_tracking()
		3:  # 阶段3: 五芒星阵
			shoot_pentagram()
		4:  # 阶段4: 混合弹幕
			shoot_chaos_pattern()
		5:  # 阶段5: 终极弹幕
			shoot_ultimate_pattern()

# Pattern implementations
func shoot_spiral_pattern(bullet_count: int, rotation_speed: float):
	var base_angle = movement_timer * rotation_speed
	for i in range(bullet_count):
		var angle = base_angle + (2 * PI / bullet_count) * i
		var dir = Vector2(cos(angle), sin(angle))
		spawn_bullet(dir, 300.0, EnemyBullet.BulletType.NORMAL)

func shoot_double_spiral():
	var base_angle = movement_timer * 2.0
	for i in range(12):
		var angle1 = base_angle + (2 * PI / 12) * i
		var angle2 = -base_angle + (2 * PI / 12) * i
		var dir1 = Vector2(cos(angle1), sin(angle1))
		var dir2 = Vector2(cos(angle2), sin(angle2))
		spawn_bullet(dir1, 250.0, EnemyBullet.BulletType.NORMAL)
		spawn_bullet(dir2, 350.0, EnemyBullet.BulletType.NORMAL)

func shoot_tracking_burst():
	for i in range(2):
		spawn_bullet(Vector2.LEFT, 500.0, EnemyBullet.BulletType.TRACKING)

func shoot_triple():
	# Three bullets with slight angle difference
	spawn_bullet(Vector2.LEFT, 400.0, EnemyBullet.BulletType.NORMAL)
	spawn_bullet(Vector2.LEFT.rotated(0.2), 400.0, EnemyBullet.BulletType.NORMAL)
	spawn_bullet(Vector2.LEFT.rotated(-0.2), 400.0, EnemyBullet.BulletType.NORMAL)

# ========== Boss6专属弹幕模式 ==========

func shoot_triple_spiral():
	"""三重螺旋弹幕"""
	var base_angle = movement_timer * 2.5
	for spiral in range(3):
		var spiral_offset = (2 * PI / 3) * spiral
		for i in range(8):
			var angle = base_angle + spiral_offset + (2 * PI / 8) * i
			var dir = Vector2(cos(angle), sin(angle))
			spawn_bullet(dir, 280.0, EnemyBullet.BulletType.NORMAL)

func shoot_dense_tracking():
	"""密集追踪弹"""
	for i in range(5):
		spawn_bullet(Vector2.LEFT, 450.0 + i * 50, EnemyBullet.BulletType.TRACKING)
		await get_tree().create_timer(0.15).timeout

func shoot_pentagram():
	"""五芒星阵弹幕"""
	# 五芒星的5个顶点
	for i in range(5):
		var angle = (2 * PI / 5) * i - PI / 2
		var dir = Vector2(cos(angle), sin(angle))
		# 从每个顶点发射扇形弹幕
		for j in range(5):
			var spread_angle = angle + (j - 2) * 0.15
			var spread_dir = Vector2(cos(spread_angle), sin(spread_angle))
			spawn_bullet(spread_dir, 320.0, EnemyBullet.BulletType.SAND)

func shoot_chaos_pattern():
	"""混合弹幕：螺旋+追踪+圆形"""
	# 螺旋
	shoot_spiral_pattern(20, 3.0)
	await get_tree().create_timer(0.2).timeout
	# 追踪
	for i in range(3):
		spawn_bullet(Vector2.LEFT, 500.0, EnemyBullet.BulletType.TRACKING)
	await get_tree().create_timer(0.2).timeout
	# 圆形
	shoot_circle()

func shoot_ultimate_pattern():
	"""终极弹幕：最强模式"""
	# 三重螺旋
	shoot_triple_spiral()
	await get_tree().create_timer(0.3).timeout
	# 密集圆形弹幕
	var bullet_count = 24
	for i in range(bullet_count):
		var angle = (2 * PI / bullet_count) * i
		var dir = Vector2(cos(angle), sin(angle))
		spawn_bullet(dir, 300.0, EnemyBullet.BulletType.CIRCLE)
	await get_tree().create_timer(0.3).timeout
	# 追踪弹群
	for i in range(6):
		spawn_bullet(Vector2.LEFT, 550.0, EnemyBullet.BulletType.TRACKING)

# Override shoot to use more complex patterns for bosses
func shoot():
	can_shoot = false  # 防止连续射击
	match boss_id:
		2:
			# Boss 2 shoots tracking bullets periodically
			shoot_tracking()
		3:
			# Boss 3 alternates between patterns
			if current_pattern == 0:
				shoot_triple()
			else:
				shoot_tracking()
		6:
			# Boss6 根据阶段改变常规射击
			match current_phase:
				1:
					shoot_tracking()
				2:
					shoot_sand()
				3, 4:
					shoot_circle()
				5:
					# 阶段5: 超强追踪+圆形
					shoot_tracking()
					shoot_circle()
		_:
			# Other bosses use parent patterns
			super.shoot()

func die():
	# Boss death - trigger special effects, level completion, etc.
	GameManager.add_score(score_value * 2)  # Double score for bosses

	# TODO: Boss death animation/effect
	# TODO: Spawn power-ups

	super.die()
