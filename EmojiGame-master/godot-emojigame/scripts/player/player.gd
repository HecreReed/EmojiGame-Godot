extends Area2D
class_name Player

# Player stats
@export var max_health: int = 100
@export var speed: float = 350.0
@export var focused_speed: float = 150.0  # Shift精确移动速度
@export var shoot_cooldown: float = 0.15
@export var bullet_scene: PackedScene

# Player state
var current_health: int
var can_shoot: bool = true
var is_alive: bool = true
var is_focused: bool = false  # Shift精确移动模式

# Weapon and power
var weapon_grade: int = 1  # 1-4 (NORMAL, DOUBLE, TWINBLE, FINAL)
var damage: int = 10

# Bomb system
var bombs: int = 3
var max_bombs: int = 8
var bomb_active: bool = false
var bomb_duration: float = 2.0
var bomb_start_time: float = 0.0

# Shield system
var shield: int = 0
var max_shield: int = 3

# Invincibility frames (受击间隔)
var is_invincible: bool = false
var invincibility_duration: float = 1.0
var last_hit_time: float = 0.0

# Dash system
var dash_available: bool = true
var dash_cooldown: float = 3.0
var last_dash_time: float = 0.0
var is_dashing: bool = false
var dash_start_time: float = 0.0
var dash_duration: float = 0.2
var dash_speed: float = 1000.0

# Hitbox (东方风格判定点)
var hitbox_size: float = 4.0

# References
@onready var sprite: Sprite2D = $Sprite2D
@onready var shoot_timer: Timer = $ShootTimer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var hitbox_visual: Sprite2D = null  # 判定点可视化（运行时创建）

# Screen bounds
var screen_size: Vector2

func _ready():
	add_to_group("player")
	current_health = max_health
	shoot_timer.wait_time = shoot_cooldown
	shoot_timer.timeout.connect(_on_shoot_timer_timeout)

	# Get screen size
	screen_size = get_viewport_rect().size

	print("Player ready! Position: ", position, " Screen size: ", screen_size)

	# Connect signals
	area_entered.connect(_on_area_entered)

	# Notify game manager
	GameManager.health_changed.emit(current_health, max_health)

	# Load bullet scene if not set
	if not bullet_scene:
		bullet_scene = load("res://scenes/bullets/player_bullet.tscn")

	# Setup hitbox visual
	setup_hitbox_visual()

func setup_hitbox_visual():
	# 创建判定点可视化（红色小点，仅在精确模式显示）
	hitbox_visual = Sprite2D.new()
	hitbox_visual.name = "HitboxVisual"
	add_child(hitbox_visual)
	hitbox_visual.modulate = Color(1, 0, 0, 0.8)
	hitbox_visual.scale = Vector2(hitbox_size * 2, hitbox_size * 2)
	hitbox_visual.visible = false

func _physics_process(delta):
	if not is_alive:
		return

	handle_focus_mode()
	handle_movement(delta)
	handle_shooting()
	handle_dash(delta)
	handle_bomb(delta)

	# Clamp position to screen bounds
	position.x = clamp(position.x, 20, screen_size.x - 20)
	position.y = clamp(position.y, 20, screen_size.y - 20)

func _input(event):
	# Shift - 精确移动模式
	if event.is_action_pressed("focus"):
		is_focused = true
		print("Focus ON")
		if hitbox_visual:
			hitbox_visual.visible = true
	elif event.is_action_released("focus"):
		is_focused = false
		print("Focus OFF")
		if hitbox_visual:
			hitbox_visual.visible = false

	# X键 - 使用炸弹
	if event.is_action_pressed("use_bomb"):
		print("Bomb pressed! Bombs: ", bombs)
		use_bomb()

	# C键 - 冲刺
	if event.is_action_pressed("dash"):
		var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input_dir.length() > 0:
			print("Dash!")
			start_dash(input_dir)

func handle_focus_mode():
	# 显示/隐藏判定点
	if hitbox_visual:
		hitbox_visual.visible = is_focused

func handle_movement(delta):
	if is_dashing:
		return  # 冲刺时不响应普通移动

	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir.length() > 0:
		var current_speed = focused_speed if is_focused else speed
		position += input_dir * current_speed * delta
		# print("Moving: ", input_dir, " Speed: ", current_speed)

func handle_shooting():
	if Input.is_action_pressed("shoot") and can_shoot:
		# print("Shooting!")
		shoot()
		can_shoot = false
		shoot_timer.start()

func shoot():
	if not bullet_scene:
		return

	# 根据武器等级发射不同数量的子弹
	match weapon_grade:
		1:  # NORMAL - 单发
			spawn_bullet(Vector2(20, 0))
		2:  # DOUBLE - 双发
			spawn_bullet(Vector2(20, -10))
			spawn_bullet(Vector2(20, 10))
		3:  # TWINBLE - 三发
			spawn_bullet(Vector2(20, -15))
			spawn_bullet(Vector2(20, 0))
			spawn_bullet(Vector2(20, 15))
		4:  # FINAL - 四发
			spawn_bullet(Vector2(20, -20))
			spawn_bullet(Vector2(20, -7))
			spawn_bullet(Vector2(20, 7))
			spawn_bullet(Vector2(20, 20))

func spawn_bullet(offset: Vector2):
	var bullet = bullet_scene.instantiate()
	bullet.global_position = global_position + offset
	bullet.direction = Vector2.RIGHT
	bullet.damage = damage
	get_parent().add_child(bullet)

func handle_dash(delta):
	if is_dashing:
		var elapsed = Time.get_ticks_msec() / 1000.0 - dash_start_time
		if elapsed >= dash_duration:
			is_dashing = false
		# 冲刺移动在start_dash中已经处理

func start_dash(direction: Vector2):
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_dash_time >= dash_cooldown:
		is_dashing = true
		dash_start_time = current_time
		last_dash_time = current_time

		# 冲刺移动
		position += direction.normalized() * dash_speed * dash_duration

		# 冲刺期间无敌
		set_collision_mask_value(4, false)
		await get_tree().create_timer(dash_duration).timeout
		if is_instance_valid(self):
			set_collision_mask_value(4, true)

func handle_bomb(delta):
	if bomb_active:
		var elapsed = Time.get_ticks_msec() / 1000.0 - bomb_start_time
		if elapsed >= bomb_duration:
			bomb_active = false

func use_bomb():
	if bombs > 0 and not bomb_active:
		bombs -= 1
		bomb_active = true
		bomb_start_time = Time.get_ticks_msec() / 1000.0

		# 清除所有敌人子弹
		var bullets = get_tree().get_nodes_in_group("enemy_bullets")
		for bullet in bullets:
			bullet.queue_free()

		# 对所有敌人造成伤害
		var enemies = get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if enemy.has_method("take_damage"):
				enemy.take_damage(200)

		# 炸弹期间无敌
		set_collision_mask_value(4, false)
		await get_tree().create_timer(bomb_duration).timeout
		if is_instance_valid(self):
			set_collision_mask_value(4, true)
			bomb_active = false

func take_damage(amount: int):
	if not is_alive or bomb_active or is_dashing or is_invincible:
		return  # 炸弹/冲刺/受击间隔期间无敌

	# 先扣护盾
	if shield > 0:
		shield -= 1
		# 护盾被击破也需要无敌帧
		activate_invincibility()
		return

	current_health -= amount
	GameManager.health_changed.emit(current_health, max_health)

	# 受击后激活无敌帧
	activate_invincibility()

	if current_health <= 0:
		die()

func activate_invincibility():
	"""激活受击无敌帧"""
	is_invincible = true
	last_hit_time = Time.get_ticks_msec() / 1000.0

	# 视觉反馈：闪烁效果
	start_flashing()

	# 无敌时间结束
	await get_tree().create_timer(invincibility_duration).timeout
	if is_instance_valid(self):
		is_invincible = false
		stop_flashing()

func start_flashing():
	"""开始闪烁效果"""
	var flash_count = int(invincibility_duration / 0.1)
	for i in range(flash_count):
		if not is_instance_valid(self) or not is_invincible:
			break
		sprite.modulate.a = 0.3
		await get_tree().create_timer(0.05).timeout
		if not is_instance_valid(self):
			break
		sprite.modulate.a = 1.0
		await get_tree().create_timer(0.05).timeout

func stop_flashing():
	"""停止闪烁，恢复正常"""
	if sprite:
		sprite.modulate.a = 1.0

func heal(amount: int):
	current_health = min(current_health + amount, max_health)
	GameManager.health_changed.emit(current_health, max_health)

func upgrade_weapon():
	weapon_grade = min(weapon_grade + 1, 4)

func add_shield():
	shield = min(shield + 1, max_shield)

func add_bomb():
	bombs = min(bombs + 1, max_bombs)

func die():
	if not is_alive:
		return

	is_alive = false
	GameManager.trigger_game_over()
	queue_free()

func _on_shoot_timer_timeout():
	can_shoot = true

func _on_area_entered(area):
	if area.is_in_group("enemies") or area.is_in_group("enemy_bullets"):
		var damage_amount = 10
		if area.has_method("get_damage"):
			damage_amount = area.get_damage()
		take_damage(damage_amount)
