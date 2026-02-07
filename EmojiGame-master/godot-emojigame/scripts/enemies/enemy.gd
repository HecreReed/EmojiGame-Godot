extends Area2D
class_name Enemy

@export var health: int = 50
@export var speed: float = 150.0
@export var damage: int = 10
@export var score_value: int = 100
@export var shoot_cooldown: float = 1.8
@export var bullet_scene: PackedScene

var direction: Vector2 = Vector2.LEFT
var can_shoot: bool = true
var max_health: int

@onready var sprite: Sprite2D = $Sprite2D
@onready var shoot_timer: Timer = $ShootTimer

# Shoot patterns
enum ShootPattern {
	NORMAL,
	TRACKING,
	RANDOM,
	SAND,
	CIRCLE
}

func _ready():
	add_to_group("enemies")
	max_health = health

	# Setup shoot timer
	if shoot_timer:
		shoot_timer.wait_time = shoot_cooldown
		shoot_timer.timeout.connect(_on_shoot_timer_timeout)
		shoot_timer.start()

	# Connect signals
	area_entered.connect(_on_area_entered)

	# Load bullet scene if not set
	if not bullet_scene:
		bullet_scene = load("res://scenes/bullets/enemy_bullet.tscn")

func _physics_process(delta):
	# Move enemy
	position += direction * speed * delta

	# Remove enemy if out of screen (left side)
	if position.x < -100:
		queue_free()

	# Shoot if can
	if can_shoot:
		shoot()

func shoot():
	# Choose random pattern based on enemy strength
	var pattern = choose_shoot_pattern()
	execute_shoot_pattern(pattern)
	can_shoot = false  # 防止连续射击

func choose_shoot_pattern() -> ShootPattern:
	var rand = randf()

	# More patterns for stronger enemies
	if health > 150:
		if rand < 0.25:
			return ShootPattern.TRACKING
		elif rand < 0.5:
			return ShootPattern.RANDOM
		elif rand < 0.75:
			return ShootPattern.SAND
		else:
			return ShootPattern.CIRCLE
	elif health > 100:
		if rand < 0.33:
			return ShootPattern.NORMAL
		elif rand < 0.67:
			return ShootPattern.TRACKING
		else:
			return ShootPattern.RANDOM
	else:
		if rand < 0.5:
			return ShootPattern.NORMAL
		else:
			return ShootPattern.TRACKING

func execute_shoot_pattern(pattern: ShootPattern):
	match pattern:
		ShootPattern.NORMAL:
			shoot_normal()
		ShootPattern.TRACKING:
			shoot_tracking()
		ShootPattern.RANDOM:
			shoot_random()
		ShootPattern.SAND:
			shoot_sand()
		ShootPattern.CIRCLE:
			shoot_circle()

func shoot_normal():
	spawn_bullet(Vector2.LEFT, 400.0, EnemyBullet.BulletType.NORMAL)

func shoot_tracking():
	spawn_bullet(Vector2.LEFT, 450.0, EnemyBullet.BulletType.TRACKING)

func shoot_random():
	var random_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	spawn_bullet(random_dir, 500.0, EnemyBullet.BulletType.RANDOM)

func shoot_sand():
	# 扇形散射：发射8颗子弹
	var base_angle = -PI / 2  # 向左
	var spread = PI / 5  # 散射角度

	for i in range(8):
		var angle_offset = -spread / 2 + (spread / 7) * i
		var angle = base_angle + angle_offset
		var dir = Vector2(cos(angle), sin(angle))
		spawn_bullet(dir, 400.0, EnemyBullet.BulletType.SAND)

func shoot_circle():
	# 圆形弹幕：发射12颗子弹
	var bullet_count = 12
	for i in range(bullet_count):
		var angle = (2 * PI / bullet_count) * i
		var dir = Vector2(cos(angle), sin(angle))
		spawn_bullet(dir, 350.0, EnemyBullet.BulletType.CIRCLE)

func spawn_bullet(dir: Vector2, bullet_speed: float, bullet_type: int):
	if not bullet_scene:
		return

	var bullet = bullet_scene.instantiate()
	bullet.global_position = global_position
	bullet.direction = dir
	bullet.speed = bullet_speed
	bullet.bullet_type = bullet_type
	get_parent().add_child(bullet)

func take_damage(amount: int):
	health -= amount

	# Visual feedback (flash)
	if sprite:
		sprite.modulate = Color(1, 0.5, 0.5)
		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(self):
			sprite.modulate = Color(1, 1, 1)

	if health <= 0:
		die()

func die():
	# Add score
	GameManager.add_score(score_value)

	# Spawn power-up with 20% chance
	spawn_powerup()

	queue_free()

func spawn_powerup():
	if randf() < 0.25:  # 25% 掉落概率
		var powerup_scene = load("res://scenes/powerups/powerup.tscn")
		if powerup_scene:
			var powerup = powerup_scene.instantiate()
			powerup.global_position = global_position

			# 根据概率选择道具类型
			var random_value = randf()
			if random_value < 0.3:
				# 30% 金币类
				powerup.power_up_type = [4, 5, 6].pick_random()
			elif random_value < 0.5:
				# 20% 生命类
				powerup.power_up_type = [1, 7, 14].pick_random()
			elif random_value < 0.65:
				# 15% 武器类
				powerup.power_up_type = [2, 3].pick_random()
			elif random_value < 0.8:
				# 15% 防御类
				powerup.power_up_type = [9, 10].pick_random()
			else:
				# 20% 特殊类
				powerup.power_up_type = [0, 8, 11, 12, 13, 15].pick_random()

			get_parent().add_child(powerup)

func _on_area_entered(area):
	if area.is_in_group("player"):
		if area.has_method("take_damage"):
			area.take_damage(damage)

func _on_shoot_timer_timeout():
	can_shoot = true
	if shoot_timer:
		shoot_timer.start()

func get_damage() -> int:
	return damage
