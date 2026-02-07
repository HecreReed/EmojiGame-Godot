extends Area2D
class_name Player

# Player stats
@export var max_health: int = 20
@export var speed: float = 300.0
@export var focused_speed: float = 120.0  # Shift精确移动速度
@export var shoot_cooldown: float = 0.325
@export var bullet_scene: PackedScene

# Player state
var current_health: int
var can_shoot: bool = true
var is_alive: bool = true
var is_focused: bool = false  # Shift精确移动模式

# Weapon and power
var weapon_grade: int = 1  # 1-4 (NORMAL, DOUBLE, TWINBLE, FINAL)
var damage: int = 10
var auto_shoot_enabled: bool = true

enum WeaponType { NORMAL, SPREAD, HOMING, LASER, PENETRATING, BOMBARDMENT, WAVE, SPIRAL }
var weapon_type: WeaponType = WeaponType.NORMAL
var spiral_shooter_angle_deg: float = 0.0

# Skills
var is_crazy_shooting: bool = false
var is_power_shooting: bool = false

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
var dash_speed: float = 1800.0

# Hitbox (东方风格判定点)
var hitbox_size: float = 4.0

# Slowdown zones (Python slowdown_effects parity, but robust with per-zone targets)
var _slow_zone_targets: Dictionary = {} # instance_id -> normal_speed_px_per_sec

# References
@onready var sprite: Sprite2D = $Sprite2D
@onready var shoot_timer: Timer = $ShootTimer
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var pickup_area: Area2D = $PickupArea

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

	# Touhou-like movement tuning:
	# - Focused (Shift) speed uses the current "speed"
	# - Unfocused speed is 2x
	var base_speed := speed
	focused_speed = base_speed
	speed = base_speed * 2.0

	# Connect signals
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

	if pickup_area:
		pickup_area.add_to_group("player_pickup")

	# Notify game manager
	if GameManager.has_method("report_health"):
		GameManager.report_health(current_health, max_health)
	else:
		GameManager.health_changed.emit(current_health, max_health)

	# Match Python version: initial damage is random 8-12
	randomize()
	damage = randi_range(8, 12)

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
	hitbox_visual.texture = _create_hitbox_texture(maxi(2, int(round(hitbox_size))))
	hitbox_visual.centered = true
	hitbox_visual.position = Vector2.ZERO
	hitbox_visual.z_index = 10
	hitbox_visual.scale = Vector2.ONE
	hitbox_visual.visible = false

func _create_hitbox_texture(radius: int) -> Texture2D:
	var outer_radius := radius + 1
	var diameter := outer_radius * 2 + 1
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var center := Vector2(float(outer_radius), float(outer_radius))
	for y in range(diameter):
		for x in range(diameter):
			var dist := Vector2(float(x), float(y)).distance_to(center)
			if dist <= float(radius):
				image.set_pixel(x, y, Color(1, 0, 0, 0.95))
			elif dist <= float(outer_radius):
				image.set_pixel(x, y, Color(1, 1, 1, 0.9))

	return ImageTexture.create_from_image(image)

func _physics_process(delta):
	if not is_alive:
		return
	if GameManager.time_stop_active and GameManager.time_stop_freeze_player:
		return

	is_focused = Input.is_action_pressed("focus")
	handle_focus_mode()
	handle_movement(delta)
	handle_shooting()
	handle_dash(delta)
	handle_bomb(delta)

	# Clamp position to screen bounds
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	position.x = clamp(position.x, 20, viewport_size.x - 20)
	position.y = clamp(position.y, 20, playfield_bottom - 20)

func _input(event):
	if GameManager.time_stop_active and GameManager.time_stop_freeze_player:
		return
	# X键 - 使用炸弹
	if event.is_action_pressed("use_bomb"):
		use_bomb()

	# C键 - 冲刺
	if event.is_action_pressed("dash"):
		var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input_dir.length() == 0:
			input_dir = Vector2.RIGHT
		start_dash(input_dir)

	# Skills (match Python: E/J/K/L)
	if event.is_action_pressed("skill_power"):
		use_power_shoot()
	if event.is_action_pressed("skill_crazy"):
		use_crazy_shoot()
	if event.is_action_pressed("skill_blow"):
		blow_enemy_bullets()
	if event.is_action_pressed("skill_timestop"):
		use_time_stop()

	# Weapon keys (temporary mapping: 1-4 -> weapon grade)
	if event.is_action_pressed("weapon_1"):
		switch_weapon(WeaponType.NORMAL)
	if event.is_action_pressed("weapon_2"):
		switch_weapon(WeaponType.SPREAD)
	if event.is_action_pressed("weapon_3"):
		switch_weapon(WeaponType.HOMING)
	if event.is_action_pressed("weapon_4"):
		switch_weapon(WeaponType.LASER)
	if event.is_action_pressed("weapon_5"):
		switch_weapon(WeaponType.PENETRATING)
	if event.is_action_pressed("weapon_6"):
		switch_weapon(WeaponType.BOMBARDMENT)
	if event.is_action_pressed("weapon_7"):
		switch_weapon(WeaponType.WAVE)
	if event.is_action_pressed("weapon_8"):
		switch_weapon(WeaponType.SPIRAL)

func switch_weapon(new_weapon: WeaponType) -> void:
	weapon_type = new_weapon

func get_weapon_name() -> String:
	match weapon_type:
		WeaponType.NORMAL:
			return "NORMAL"
		WeaponType.SPREAD:
			return "SPREAD"
		WeaponType.HOMING:
			return "HOMING"
		WeaponType.LASER:
			return "LASER"
		WeaponType.PENETRATING:
			return "PENETRATING"
		WeaponType.BOMBARDMENT:
			return "BOMBARDMENT"
		WeaponType.WAVE:
			return "WAVE"
		WeaponType.SPIRAL:
			return "SPIRAL"
		_:
			return "NORMAL"

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
		if not is_focused and not _slow_zone_targets.is_empty():
			current_speed = minf(current_speed, _get_slowed_normal_speed())
		position += input_dir * current_speed * delta
		# print("Moving: ", input_dir, " Speed: ", current_speed)

func _get_slowed_normal_speed() -> float:
	var target := speed
	for v in _slow_zone_targets.values():
		target = minf(target, float(v))
	return target

func _enter_slow_zone(zone: Area2D) -> void:
	if not zone:
		return
	var value = zone.get_meta("normal_speed_px_per_sec", null)
	if value == null:
		return
	_slow_zone_targets[zone.get_instance_id()] = float(value)

func _exit_slow_zone(zone: Area2D) -> void:
	if not zone:
		return
	_slow_zone_targets.erase(zone.get_instance_id())

func _teleport_from_prevent() -> void:
	# Python parity (Event.bossUseSkill): teleport when touching Boss2 prevent barriers.
	# Python uses top-left coords; our player position is centered (40x40 sprite).
	var half := 20.0
	global_position = Vector2(randf_range(0.0, 300.0) + half, randf_range(0.0, 440.0) + half)

func handle_shooting():
	# Match Python version: auto-shoot (no key required)
	if auto_shoot_enabled and can_shoot:
		shoot()
		can_shoot = false
		shoot_timer.wait_time = max(0.05, shoot_cooldown * _get_weapon_cooldown_factor())
		shoot_timer.start()

func _get_weapon_cooldown_factor() -> float:
	match weapon_type:
		WeaponType.HOMING:
			return 1.5
		WeaponType.LASER:
			return 0.5
		WeaponType.PENETRATING:
			return 1.2
		WeaponType.BOMBARDMENT:
			return 2.0
		WeaponType.SPIRAL:
			return 0.8
		_:
			return 1.0

func shoot():
	if not bullet_scene:
		return
	match weapon_type:
		WeaponType.NORMAL:
			_shoot_normal()
		WeaponType.SPREAD:
			_shoot_spread()
		WeaponType.HOMING:
			_shoot_homing()
		WeaponType.LASER:
			_shoot_laser()
		WeaponType.PENETRATING:
			_shoot_penetrating()
		WeaponType.BOMBARDMENT:
			_shoot_bombardment()
		WeaponType.WAVE:
			_shoot_wave()
		WeaponType.SPIRAL:
			_shoot_spiral()

func _shoot_normal() -> void:
	# 原版4级火力
	match weapon_grade:
		1:  # NORMAL - 单发
			_spawn_normal_bullet(Vector2(-10, 10))
		2:  # DOUBLE - 双发
			_spawn_normal_bullet(Vector2(-10, 25))
			_spawn_normal_bullet(Vector2(-10, -5))
		3:  # TWINBLE - 三发
			_spawn_normal_bullet(Vector2(-10, 35))
			_spawn_normal_bullet(Vector2(-10, 10))
			_spawn_normal_bullet(Vector2(-10, -15))
		4:  # FINAL - 四发
			_spawn_normal_bullet(Vector2(-10, 40))
			_spawn_normal_bullet(Vector2(-10, 15))
			_spawn_normal_bullet(Vector2(-10, -10))
			_spawn_normal_bullet(Vector2(-10, -35))

func _spawn_normal_bullet(offset: Vector2) -> void:
	var bullet := bullet_scene.instantiate() as PlayerBullet
	if not bullet:
		return
	bullet.global_position = global_position + offset
	bullet.direction = Vector2.RIGHT
	# Match Python: damage has small random variance per shot
	bullet.damage = damage + randi_range(2, 4)
	get_parent().add_child(bullet)

func _spawn_special_bullet(offset: Vector2, dir: Vector2, dmg: int, bullet_speed: float = 1080.0) -> PlayerBullet:
	var bullet := bullet_scene.instantiate() as PlayerBullet
	if not bullet:
		return null
	bullet.global_position = global_position + offset
	bullet.direction = dir.normalized()
	bullet.damage = dmg
	bullet.speed = bullet_speed
	get_parent().add_child(bullet)
	return bullet

func _shoot_spread() -> void:
	var bullet_count := 3
	var angle_step := 15
	match weapon_grade:
		1:
			bullet_count = 3
			angle_step = 15
		2:
			bullet_count = 5
			angle_step = 12
		3:
			bullet_count = 7
			angle_step = 10
		_:
			bullet_count = 9
			angle_step = 8

	var start_angle: int = -int(((bullet_count - 1) * angle_step) / 2.0)
	for i in range(bullet_count):
		var angle_deg := float(start_angle + i * angle_step)
		var dir := Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
		_spawn_special_bullet(Vector2(-10, 10), dir, damage)

func _shoot_homing() -> void:
	var missile_count := 1
	match weapon_grade:
		1:
			missile_count = 1
		2:
			missile_count = 2
		3:
			missile_count = 3
		_:
			missile_count = 4

	for i in range(missile_count):
		var offset_y := (float(i) - float(missile_count) / 2.0 + 0.5) * 15.0
		var bullet := _spawn_special_bullet(Vector2(-10, 10.0 + offset_y), Vector2.RIGHT, damage * 2)
		if bullet:
			bullet.is_homing = true

func _shoot_laser() -> void:
	var laser_count := 3
	match weapon_grade:
		1:
			laser_count = 3
		2:
			laser_count = 5
		3:
			laser_count = 7
		_:
			laser_count = 10

	var laser_damage: int = maxi(1, int(float(damage) / 2.0))
	for i in range(laser_count):
		var offset_x := -10.0 + float(i) * 8.0
		_spawn_special_bullet(Vector2(offset_x, 10), Vector2.RIGHT, laser_damage, 1800.0)

func _shoot_penetrating() -> void:
	var bullet_count := 1
	var pcount := 2
	match weapon_grade:
		1:
			bullet_count = 1
			pcount = 2
		2:
			bullet_count = 2
			pcount = 3
		3:
			bullet_count = 3
			pcount = 4
		_:
			bullet_count = 4
			pcount = 5

	var pdamage: int = maxi(1, int(float(damage) * 1.5))
	for i in range(bullet_count):
		var offset_y := (float(i) - float(bullet_count) / 2.0 + 0.5) * 15.0
		var bullet := _spawn_special_bullet(Vector2(-10, 10.0 + offset_y), Vector2.RIGHT, pdamage)
		if bullet:
			bullet.can_penetrate = true
			bullet.penetrate_count = pcount

func _shoot_bombardment() -> void:
	var bullet_count := 1
	var radius := 80.0
	var dmg_mult := 2.5
	match weapon_grade:
		1:
			bullet_count = 1
			radius = 80.0
			dmg_mult = 2.5
		2:
			bullet_count = 2
			radius = 100.0
			dmg_mult = 3.0
		3:
			bullet_count = 3
			radius = 120.0
			dmg_mult = 3.5
		_:
			bullet_count = 4
			radius = 150.0
			dmg_mult = 4.0

	var bdamage: int = maxi(1, int(float(damage) * dmg_mult))
	for i in range(bullet_count):
		var offset_y := (float(i) - float(bullet_count) / 2.0 + 0.5) * 20.0
		var bullet := _spawn_special_bullet(Vector2(-10, 10.0 + offset_y), Vector2.RIGHT, bdamage)
		if bullet:
			bullet.is_bomb = true
			bullet.explosion_radius = radius

func _shoot_wave() -> void:
	var bullet_count := 2
	var _amplitude := 25.0
	match weapon_grade:
		1:
			bullet_count = 2
			_amplitude = 25.0
		2:
			bullet_count = 3
			_amplitude = 30.0
		3:
			bullet_count = 4
			_amplitude = 35.0
		_:
			bullet_count = 5
			_amplitude = 40.0

	for i in range(bullet_count):
		var bullet := _spawn_special_bullet(Vector2(-10, 10.0 + float(i) * 12.0), Vector2.RIGHT, damage)
		if bullet:
			bullet.is_wave = true
			bullet.wave_frequency = 0.1
			bullet.wave_phase = float(i) * 60.0
			# Stored for future parity tweaks (Python stores wave_amplitude but doesn't use it in update)
			# bullet.wave_amplitude = amplitude

func _shoot_spiral() -> void:
	var spiral_radius := 40.0
	var angle_offsets: Array[int] = [0, 120, 240]
	match weapon_grade:
		1:
			spiral_radius = 40.0
			angle_offsets = [0, 120, 240]
		2:
			spiral_radius = 50.0
			angle_offsets = [0, 90, 180, 270]
		3:
			spiral_radius = 55.0
			angle_offsets = [0, 60, 120, 180, 240, 300]
		_:
			spiral_radius = 60.0
			angle_offsets = [0, 45, 90, 135, 180, 225, 270, 315]

	for off in angle_offsets:
		var angle_deg := spiral_shooter_angle_deg + float(off)
		var bullet := _spawn_special_bullet(Vector2(-10, 10), Vector2.RIGHT, damage)
		if bullet:
			bullet.is_spiral = true
			bullet.spiral_angle = deg_to_rad(angle_deg)
			bullet.spiral_radius = spiral_radius
			bullet.speed = 0.0

	spiral_shooter_angle_deg = fmod(spiral_shooter_angle_deg + 15.0, 360.0)

func handle_dash(_delta):
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
		# Enemy & enemy bullets use collision layer value=4 (mask layer index=3).
		set_collision_mask_value(3, false)
		await get_tree().create_timer(dash_duration).timeout
		if is_instance_valid(self):
			set_collision_mask_value(3, true)

func handle_bomb(_delta):
	if bomb_active:
		var elapsed = Time.get_ticks_msec() / 1000.0 - bomb_start_time
		if elapsed >= bomb_duration:
			bomb_active = false

func use_bomb():
	if bombs > 0 and not bomb_active:
		bombs -= 1
		bomb_active = true
		bomb_start_time = Time.get_ticks_msec() / 1000.0
		if GameManager.has_method("register_bomb_used"):
			GameManager.register_bomb_used()

		# 清除所有敌人子弹
		var bullets = get_tree().get_nodes_in_group("enemy_bullets")
		for bullet in bullets:
			bullet.queue_free()

		# 对所有敌人造成伤害
		var enemies = get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if enemy.has_method("take_damage"):
				enemy.take_damage(50)

		# 炸弹期间无敌
		set_collision_mask_value(3, false)
		await get_tree().create_timer(bomb_duration).timeout
		if is_instance_valid(self):
			set_collision_mask_value(3, true)
			bomb_active = false

func take_damage(amount: int):
	if GameManager.time_stop_active:
		return
	if not is_alive or bomb_active or is_dashing or is_invincible:
		return  # 炸弹/冲刺/受击间隔期间无敌

	# 先扣护盾
	if shield > 0:
		shield -= 1
		if GameManager and GameManager.has_method("notify_player_hit"):
			GameManager.notify_player_hit()
		# 护盾被击破也需要无敌帧
		activate_invincibility()
		return

	current_health -= amount
	if GameManager.has_method("report_health"):
		GameManager.report_health(current_health, max_health)
	else:
		GameManager.health_changed.emit(current_health, max_health)

	if GameManager and GameManager.has_method("notify_player_hit"):
		GameManager.notify_player_hit()

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
	if GameManager.has_method("report_health"):
		GameManager.report_health(current_health, max_health)
	else:
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
	if area and area.is_in_group("slow_zone"):
		_enter_slow_zone(area)
		# Some hazards (e.g. Boss4 static screens) should both slow and deal damage,
		# so we don't early-return here.

	if area and area.is_in_group("prevent"):
		_teleport_from_prevent()
		return

	if area.is_in_group("enemies") or area.is_in_group("enemy_bullets"):
		if GameManager.time_stop_active:
			return
		# Match Python: blown-away bullets never hurt the player.
		if area is EnemyBullet and area.is_blown_away:
			return

		var damage_amount = 10
		if area.has_method("get_damage"):
			damage_amount = area.get_damage()
		take_damage(damage_amount)

func _on_area_exited(area) -> void:
	if area and area.is_in_group("slow_zone"):
		_exit_slow_zone(area)

func use_crazy_shoot():
	if is_crazy_shooting:
		return
	is_crazy_shooting = true
	await _crazy_shoot_impl()
	is_crazy_shooting = false

func _crazy_shoot_impl():
	if not bullet_scene:
		return

	var viewport_height := int(get_viewport_rect().size.y)
	for _wave in range(20):
		for y in range(0, viewport_height, 40):
			var bullet = bullet_scene.instantiate()
			bullet.global_position = Vector2(global_position.x - 10, float(y) + 10.0)
			bullet.direction = Vector2.RIGHT
			bullet.damage = damage
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.1).timeout

func use_power_shoot():
	if is_power_shooting:
		return
	if GameManager.power < 100:
		return

	is_power_shooting = true
	auto_shoot_enabled = false
	GameManager.power = 0
	GameManager.power_changed.emit(GameManager.power)

	var special_texture: Texture2D = load("res://assets/sprites/waterbullut2.png")
	for _wave in range(30):
		for y_offset in [50, 25, 0, -25]:
			var bullet := _spawn_special_bullet(
				Vector2(-10, float(y_offset) - 10.0),
				Vector2.RIGHT,
				int(round(float(damage) / 1.8))
			)
			if not bullet:
				continue
			# Match Python: powerShoot bullets do not disappear on hit (Remove = False)
			bullet.remove_on_hit = false
			var bullet_sprite := bullet.get_node_or_null("Sprite2D") as Sprite2D
			if bullet_sprite and special_texture:
				bullet_sprite.texture = special_texture
		await get_tree().create_timer(0.1).timeout

	auto_shoot_enabled = true
	is_power_shooting = false

func blow_enemy_bullets():
	var bullets = get_tree().get_nodes_in_group("enemy_bullets")
	for bullet in bullets:
		if bullet.has_method("blow_away"):
			bullet.blow_away()
		elif "direction" in bullet:
			bullet.direction = Vector2.RIGHT

func use_time_stop():
	if GameManager.time_stop_active:
		return
	if AudioManager:
		AudioManager.play_sfx_file("watertimestop.wav")
	if GameManager.has_method("start_time_stop"):
		GameManager.start_time_stop(2.0)
