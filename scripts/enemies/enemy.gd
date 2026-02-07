extends Area2D
class_name Enemy

const FPS: float = 60.0
const ENEMY_SIZE: float = 40.0
const HALF_SIZE: float = ENEMY_SIZE / 2.0

enum EnemyKind {
	BASE_1 = 1,
	BASE_2 = 2,
	BASE_3 = 3,
	BASE_4 = 4,
	BASE_5 = 5,
	BASE_6 = 6,
	BASE_7 = 7,
	FAST = 11,
	TANK = 12,
	SUICIDE = 13,
	SNIPER = 14,
	SHIELD = 15,
	SPLIT = 16,
	ELITE = 17,
	MINIBOSS = 18
}

@export var enemy_kind: int = EnemyKind.BASE_1
@export var bullet_scene: PackedScene

var health: int = 50
var max_health: int = 50
var speed: float = 90.0 # px/s
var damage: int = 10
var score_value: int = 50
var shoot_cooldown: float = 1.8

var direction: Vector2 = Vector2.LEFT # Used by BossEnemy patterns
var can_shoot: bool = false

# Python movement state
var spawn_time_sec: float = 0.0
var interval_time_sec: float = 0.0
var cotime_sec: float = 0.0
var move_direction: String = "left"
var can_change_move: bool = true

# Special spawns (e.g. Boss4 UFO) can bypass the kind-based setup logic.
var use_custom_setup: bool = false
var auto_shoot_enabled: bool = true

# Visual parity: new enemy types reuse a rolled base enemy sprite in Python (super().__init__).
var visual_enemy_id: int = 1

# Shield enemy
var has_shield: bool = false
var shield_hp_remaining: int = 0

# Split enemy
var is_child_split: bool = false

# Suicide enemy
var exploded: bool = false

# Fast enemy
var fast_move_pattern: String = ""
var fast_dash_start_sec: float = 0.0

# MiniBoss pattern state
var attack_pattern: int = 0
var pattern_change_time_sec: float = 0.0

# Midboss flag (used for HUD)
var is_midboss: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var shoot_timer: Timer = $ShootTimer


func _ready() -> void:
	add_to_group("enemies")
	area_entered.connect(_on_area_entered)

	if not bullet_scene:
		bullet_scene = load("res://scenes/bullets/enemy_bullet.tscn")

	spawn_time_sec = Time.get_ticks_msec() / 1000.0
	cotime_sec = spawn_time_sec

	if not use_custom_setup:
		_setup_by_kind()
		_apply_visual()
	else:
		max_health = maxi(max_health, health)

	# Midboss should show up in the boss UI, but must not affect StageManager.
	if is_midboss:
		add_to_group("boss")

	if auto_shoot_enabled:
		_setup_shoot_timer()
	else:
		can_shoot = false
		if shoot_timer:
			shoot_timer.stop()


func _physics_process(delta: float) -> void:
	if GameManager.time_stop_active:
		return

	var now_sec := Time.get_ticks_msec() / 1000.0
	interval_time_sec = now_sec - spawn_time_sec

	if enemy_kind != EnemyKind.FAST and enemy_kind != EnemyKind.SUICIDE:
		_update_python_random_direction(now_sec, 0.2)

	_move_by_kind(delta, now_sec)

	_remove_if_outside_screen()

	if can_shoot:
		shoot()


func _setup_by_kind() -> void:
	var mult := maxi(1, GameManager.boss_death_times)

	# Defaults match EmojiAll/Ememies.py
	has_shield = false
	shield_hp_remaining = 0
	exploded = false
	fast_move_pattern = ""
	fast_dash_start_sec = spawn_time_sec
	attack_pattern = 0
	pattern_change_time_sec = spawn_time_sec
	is_midboss = false

	match enemy_kind:
		EnemyKind.BASE_1, EnemyKind.BASE_2, EnemyKind.BASE_3, EnemyKind.BASE_4, EnemyKind.BASE_5, EnemyKind.BASE_6, EnemyKind.BASE_7:
			visual_enemy_id = enemy_kind
			var base_speed_tick := 0.8
			if enemy_kind == EnemyKind.BASE_3:
				base_speed_tick = 0.5
			elif enemy_kind == EnemyKind.BASE_2:
				base_speed_tick = 0.8
			elif enemy_kind == EnemyKind.BASE_1:
				base_speed_tick = 1.0

			var boost_tick := 2.0 * randf()
			speed = (base_speed_tick + boost_tick) * FPS
			shoot_cooldown = 1.8

			var base_hp := _get_base_enemy_hp(enemy_kind)
			health = base_hp * mult

		EnemyKind.FAST:
			visual_enemy_id = _roll_base_visual_enemy_id()
			speed = 6.0 * FPS
			shoot_cooldown = 0.4
			health = 20 * mult
			fast_move_pattern = ["zigzag", "dash"].pick_random()
			fast_dash_start_sec = spawn_time_sec

		EnemyKind.TANK:
			visual_enemy_id = _roll_base_visual_enemy_id()
			speed = 1.0 * FPS
			shoot_cooldown = 1.5
			health = 150 * mult

		EnemyKind.SUICIDE:
			visual_enemy_id = _roll_base_visual_enemy_id()
			speed = 4.0 * FPS
			# Note: Python sets canShoot=False but base Enemy.shoot() doesn't check it.
			# We keep base shoot behavior and only add the tracking+explode movement.
			shoot_cooldown = 1.8
			health = 30 * mult
			exploded = false

		EnemyKind.SNIPER:
			visual_enemy_id = _roll_base_visual_enemy_id()
			speed = 2.0 * FPS
			shoot_cooldown = 2.5
			health = 60 * mult

		EnemyKind.SHIELD:
			visual_enemy_id = _roll_base_visual_enemy_id()
			speed = 2.0 * FPS
			shoot_cooldown = 1.8
			health = 80 * mult
			has_shield = true
			shield_hp_remaining = 100 * mult

		EnemyKind.SPLIT:
			visual_enemy_id = _roll_base_visual_enemy_id()
			shoot_cooldown = 1.8
			if is_child_split:
				speed = 5.0 * FPS
				health = 20 * mult
			else:
				speed = 2.0 * FPS
				health = 100 * mult

		EnemyKind.ELITE:
			visual_enemy_id = _roll_base_visual_enemy_id()
			speed = 3.0 * FPS
			shoot_cooldown = 0.5
			health = 300 * mult

		EnemyKind.MINIBOSS:
			visual_enemy_id = _roll_base_visual_enemy_id()
			speed = 2.0 * FPS
			shoot_cooldown = 0.8
			health = 800 * mult
			attack_pattern = 0
			pattern_change_time_sec = spawn_time_sec
			is_midboss = true

		_:
			visual_enemy_id = 1
			speed = 0.8 * FPS
			shoot_cooldown = 1.8
			health = 50 * mult

	max_health = health
	score_value = max_health


func _apply_visual() -> void:
	if not sprite:
		return
	var tex: Texture2D = load("res://assets/sprites/enemy-%d.png" % clampi(visual_enemy_id, 1, 7))
	if tex:
		sprite.texture = tex
	sprite.scale = Vector2.ONE
	sprite.modulate = Color(1, 1, 1, 1)


func _setup_shoot_timer() -> void:
	if not shoot_timer:
		return
	shoot_timer.one_shot = true
	shoot_timer.autostart = false
	shoot_timer.wait_time = shoot_cooldown
	if not shoot_timer.timeout.is_connected(_on_shoot_timer_timeout):
		shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	can_shoot = false
	shoot_timer.start()


func _on_shoot_timer_timeout() -> void:
	can_shoot = true
	if shoot_timer:
		shoot_timer.wait_time = shoot_cooldown
		shoot_timer.start()


func _update_python_random_direction(now_sec: float, chance: float) -> void:
	if not can_change_move:
		return

	if interval_time_sec < 1.0:
		move_direction = "left"
		return

	# Python: only change direction every 0.5s.
	if now_sec - cotime_sec < 0.5:
		return
	cotime_sec = now_sec

	var r := randf()
	if r < chance:
		move_direction = "left"
	elif r < 2.0 * chance:
		move_direction = "right"
	elif r < 3.0 * chance:
		move_direction = "up"
	elif r <= 4.0 * chance:
		move_direction = "down"
	else:
		move_direction = "none"


func _move_by_kind(delta: float, now_sec: float) -> void:
	match enemy_kind:
		EnemyKind.FAST:
			_move_fast(delta, now_sec)
		EnemyKind.SUICIDE:
			_move_suicide(delta)
		_:
			_move_python_base(delta)


func _move_python_base(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	match move_direction:
		"left":
			if position.x >= viewport_size.x * 0.25 + HALF_SIZE:
				position.x -= speed * delta
		"right":
			if interval_time_sec < 18.0:
				if position.x <= viewport_size.x - HALF_SIZE:
					position.x += speed * delta
			else:
				position.x += speed * delta
		"up":
			if position.y >= HALF_SIZE:
				position.y -= speed * delta
		"down":
			if can_change_move:
				if position.y < playfield_bottom - HALF_SIZE:
					position.y = minf(position.y + speed * delta, playfield_bottom - HALF_SIZE)
			else:
				position.y += speed * delta
		_:
			pass


func _move_fast(delta: float, now_sec: float) -> void:
	var step := FPS * delta
	if fast_move_pattern == "zigzag":
		# Python: x -= speed; y += sin(x*0.1) * 5
		position.x -= 6.0 * step
		position.y += sin((position.x - HALF_SIZE) * 0.1) * 5.0 * step
		return

	# Dash pattern: 0-0.3s fast, 0.3-1s slow, repeat.
	var t := now_sec - fast_dash_start_sec
	if t > 1.0:
		fast_dash_start_sec = now_sec
		t = 0.0

	var dash_speed_tick := 15.0
	if t > 0.3:
		dash_speed_tick = 3.0
	position.x -= dash_speed_tick * step


func _move_suicide(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not player or not is_instance_valid(player) or player.is_queued_for_deletion():
		_move_python_base(delta)
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist > 5.0:
		global_position += to_player.normalized() * speed * delta
		return

	if not exploded:
		_explode_suicide()


func _explode_suicide() -> void:
	exploded = true
	var origin := _python_pos()
	for angle_deg in range(0, 360, 15):
		var angle_rad := deg_to_rad(float(angle_deg))
		var tan_value := _safe_tan(angle_rad)
		var sample := -1
		if angle_deg > 90 and angle_deg < 270:
			sample = 1
		_spawn_python_bullet(origin, tan_value, sample, 10.0, EnemyBullet.BulletType.CIRCLE, "")
	health = 0
	die()


func shoot() -> void:
	can_shoot = false

	match enemy_kind:
		EnemyKind.SNIPER:
			_shoot_sniper()
			return
		EnemyKind.ELITE:
			_shoot_elite()
			return
		EnemyKind.MINIBOSS:
			_shoot_miniboss()
			return
		_:
			pass

	var temp := randf()
	if enemy_kind == EnemyKind.BASE_6 or enemy_kind == EnemyKind.BASE_7:
		if temp < 0.25:
			_shoot_track()
		elif temp < 0.5:
			_shoot_random()
		elif temp < 0.75:
			_shoot_sand()
		else:
			_shoot_circle()
	elif enemy_kind == EnemyKind.BASE_4 or enemy_kind == EnemyKind.BASE_5:
		if temp < 0.25:
			_shoot_normal()
		elif temp < 0.5:
			_shoot_track()
		elif temp < 0.75:
			_shoot_random()
		else:
			_shoot_sand()
	else:
		if temp < 0.33:
			_shoot_normal()
		elif temp < 0.67:
			_shoot_track()
		else:
			_shoot_random()


func _shoot_normal() -> void:
	# EmemiesBumb: speed randint(6, 8), direction left (sample=0)
	var origin := _python_pos()
	var speed_tick := float(randi_range(6, 8))
	_spawn_python_bullet(origin, 0.0, 0, speed_tick, EnemyBullet.BulletType.NORMAL, "")


func _shoot_track() -> void:
	# BossBumb: aimed once at player, speed=23 (uses sqrt movement when sample != 0)
	var origin := _python_pos()
	var player_pos := _get_player_python_pos()
	var tan_sample := _calc_tan_and_sample(origin, player_pos)
	_spawn_python_bullet(origin, tan_sample.tan_value, tan_sample.sample, 23.0, EnemyBullet.BulletType.TRACKING, "")


func _shoot_random() -> void:
	# BossBumb: speed=30, tan random [-1.2, 1.2], sample based on player dx sign
	var origin := _python_pos()
	var player_pos := _get_player_python_pos()
	var dx := player_pos.x - origin.x
	var sample := 0
	if dx < 0.0:
		sample = -1
	elif dx > 0.0:
		sample = 1
	var tan_value := randf() * 2.4 - 1.2
	_spawn_python_bullet(origin, tan_value, sample, 30.0, EnemyBullet.BulletType.RANDOM, "")


func _shoot_sand() -> void:
	# BossBumb fan: 8 bullets, speed=8, tan offsets around player angle (EmojiAll/Ememies.py)
	var origin := _python_pos()
	var player_pos := _get_player_python_pos()
	var tan_sample := _calc_tan_and_sample(origin, player_pos)
	var base_tan := tan_sample.tan_value
	var sample := tan_sample.sample
	var artan := atan(base_tan)
	var rive := PI / 10.0
	var timek := 0
	var index := 0

	for i in range(8):
		var tan_value := base_tan
		if i != 0:
			if index % 2 != 0:
				tan_value = tan(artan + float(timek) * rive)
			else:
				tan_value = tan(artan - float(timek) * rive)
				timek += 1
		_spawn_python_bullet(origin, tan_value, sample, 8.0, EnemyBullet.BulletType.SAND, "")
		index += 1


func _shoot_circle() -> void:
	# BossBumb circle: 12 bullets in a ring, but all travel toward the player (EmojiAll/Ememies.py)
	var origin := _python_pos()
	var player_pos := _get_player_python_pos()
	var tan_sample := _calc_tan_and_sample(origin, player_pos)
	var tan_value := tan_sample.tan_value
	var sample := tan_sample.sample

	var lenth := 40.0
	var rive := PI / 3.0
	var artan := 0.0
	for _i in range(12):
		var spawn_pos := origin + Vector2(lenth * sin(artan), lenth * cos(artan))
		_spawn_python_bullet(spawn_pos, tan_value, sample, 7.0, EnemyBullet.BulletType.CIRCLE, "res://assets/sprites/bossbullut-8.png")
		artan += rive


func _shoot_sniper() -> void:
	# Python: 3 bullets, same aim, EmemiesBumb speed=15, sample is reversed (NewEnemyTypes.py)
	var origin := _python_pos()
	var player_pos := _get_player_python_pos()
	var dx := player_pos.x - origin.x
	var tan_value := 0.0
	if dx != 0.0:
		tan_value = (player_pos.y - origin.y) / dx
	var sample := 1 if dx < 0.0 else -1
	for _i in range(3):
		_spawn_python_bullet(origin, tan_value, sample, 15.0, EnemyBullet.BulletType.NORMAL, "")


func _shoot_elite() -> void:
	# Fan bullets -30..30 deg, EmemiesBumb speed=8 (NewEnemyTypes.py)
	var origin := _python_pos()
	for angle_deg in range(-30, 31, 15):
		var angle_rad := deg_to_rad(float(angle_deg))
		var tan_value := _safe_tan(angle_rad)
		var sample := -1 if angle_deg > -90 and angle_deg < 90 else 1
		_spawn_python_bullet(origin, tan_value, sample, 8.0, EnemyBullet.BulletType.SAND, "")


func _shoot_miniboss() -> void:
	# Pattern changes every 5 seconds (NewEnemyTypes.py)
	var now_sec := Time.get_ticks_msec() / 1000.0
	if now_sec - pattern_change_time_sec > 5.0:
		attack_pattern = (attack_pattern + 1) % 3
		pattern_change_time_sec = now_sec

	var origin := _python_pos()
	match attack_pattern:
		0:
			var offset_deg := fmod(now_sec * 100.0, 360.0)
			for angle_deg in range(0, 360, 30):
				var total_deg := float(angle_deg) + offset_deg
				var angle_rad := deg_to_rad(total_deg)
				var tan_value := _safe_tan(angle_rad)
				var mod_deg := fmod(total_deg, 360.0)
				if mod_deg < 0.0:
					mod_deg += 360.0
				var sample := 1 if mod_deg > 90.0 and mod_deg < 270.0 else -1
				_spawn_python_bullet(origin, tan_value, sample, 6.0, EnemyBullet.BulletType.CIRCLE, "")
		1:
			var player_pos := _get_player_python_pos()
			var dx := player_pos.x - origin.x
			var tan_value := 0.0
			if dx != 0.0:
				tan_value = (player_pos.y - origin.y) / dx
			var sample := -1 if dx > 0.0 else 1
			for _i in range(5):
				_spawn_python_bullet(origin, tan_value, sample, 8.0, EnemyBullet.BulletType.TRACKING, "")
		_:
			for _i in range(8):
				var speed_value := float(randi_range(5, 12))
				var tan_value := randf_range(-2.0, 2.0)
				var sample: int = (-1 if randf() < 0.5 else 1)
				_spawn_python_bullet(origin, tan_value, sample, speed_value, EnemyBullet.BulletType.RANDOM, "")


func _spawn_python_bullet(
	spawn_pos: Vector2,
	tan_value: float,
	sample: int,
	speed_value: float,
	bullet_type: EnemyBullet.BulletType,
	texture_path: String
) -> EnemyBullet:
	if not bullet_scene or not get_parent():
		return null
	var bullet := bullet_scene.instantiate() as EnemyBullet
	if not bullet:
		return null

	bullet.global_position = spawn_pos
	bullet.damage = randi_range(8, 9)
	bullet.bullet_type = bullet_type
	bullet.tracking_enabled = false
	bullet.direction = _dir_from_tan_sample(tan_value, sample)
	bullet.speed = _python_bullet_speed_per_sec(speed_value, sample)

	if texture_path != "":
		var bullet_sprite := bullet.get_node_or_null("Sprite2D") as Sprite2D
		var tex: Texture2D = load(texture_path)
		if bullet_sprite and tex:
			bullet_sprite.texture = tex

	get_parent().add_child(bullet)
	return bullet


# Compatibility helpers for BossEnemy (legacy patterns).
func spawn_bullet(dir: Vector2, bullet_speed: float, bullet_type: EnemyBullet.BulletType) -> void:
	if not bullet_scene or not get_parent():
		return
	var bullet := bullet_scene.instantiate() as EnemyBullet
	if not bullet:
		return
	bullet.global_position = global_position
	bullet.direction = dir.normalized()
	bullet.speed = bullet_speed
	bullet.bullet_type = bullet_type
	bullet.tracking_enabled = false
	bullet.damage = randi_range(8, 9)
	get_parent().add_child(bullet)


func shoot_normal() -> void:
	_shoot_normal()


func shoot_tracking() -> void:
	_shoot_track()


func shoot_random() -> void:
	_shoot_random()


func shoot_sand() -> void:
	_shoot_sand()


func shoot_circle() -> void:
	_shoot_circle()


func take_damage(amount: int) -> void:
	var pending := amount
	if has_shield and shield_hp_remaining > 0:
		shield_hp_remaining -= pending
		if shield_hp_remaining <= 0:
			has_shield = false
			pending = abs(shield_hp_remaining)
		else:
			pending = 0

	if pending > 0:
		health -= pending
		if sprite:
			sprite.modulate = Color(1.0, 0.5, 0.5, 1)
			await get_tree().create_timer(0.06).timeout
			if is_instance_valid(self):
				sprite.modulate = Color(1, 1, 1, 1)

	if health <= 0:
		die()


func die() -> void:
	if enemy_kind == EnemyKind.SPLIT and not is_child_split:
		_spawn_split_children()

	# Python parity (Event.emojiDeath): always drop Power(8) at x-20, y.
	var enemy_pos := _python_pos()
	_spawn_supply(8, enemy_pos + Vector2(-20.0, 0.0))

	var chance := _get_supply_chance()
	if chance > 0.0:
		_generate_supply(chance, enemy_pos)

	# New enemy types extra drops are implemented via on_death() methods in Python.
	if enemy_kind == EnemyKind.ELITE:
		_spawn_elite_supplies(enemy_pos)
	elif enemy_kind == EnemyKind.MINIBOSS:
		_spawn_miniboss_supplies(enemy_pos)

	GameManager.register_enemy_kill(score_value)
	queue_free()


func _get_supply_chance() -> float:
	# Match Event.emojiDeath drop chances.
	if enemy_kind == EnemyKind.BASE_1:
		return 0.2
	if enemy_kind == EnemyKind.BASE_2:
		return 0.3
	if enemy_kind >= 3:
		# rint == 8 is a special case in Python, not used here.
		return 0.5
	return 0.0


func _generate_supply(chance: float, enemy_pos: Vector2) -> void:
	# Match Event.generateSupply.
	var base_spawn := enemy_pos + Vector2(-20.0, 0.0)

	if randf() < chance:
		_spawn_supply(randi_range(1, 3), base_spawn)

	if is_equal_approx(chance, 1.0):
		_spawn_supply(6, base_spawn)
		_spawn_supply(6, base_spawn)
		_spawn_supply(6, base_spawn)
		_spawn_supply(0, base_spawn)
		_spawn_supply(7, base_spawn)
		return

	if randf() < chance * 1.7:
		_spawn_supply(4, base_spawn)
	elif randf() < chance:
		_spawn_supply(5, base_spawn)
	elif randf() < chance * 0.3:
		_spawn_supply(6, base_spawn)


func _spawn_elite_supplies(enemy_pos: Vector2) -> void:
	# Match NewEnemyTypes.EliteEnemy.on_death()
	var pool: Array[int] = [1, 2, 3, 4, 5, 9, 10]
	for i in range(3):
		var supply_type := pool[randi_range(0, pool.size() - 1)]
		_spawn_supply(supply_type, enemy_pos + Vector2(float(i) * 20.0, 0.0))


func _spawn_miniboss_supplies(enemy_pos: Vector2) -> void:
	# Match NewEnemyTypes.MiniBoss.on_death()
	var pool: Array[int] = [1, 2, 3, 5, 9, 10, 13, 14]
	for i in range(5):
		var supply_type := pool[randi_range(0, pool.size() - 1)]
		_spawn_supply(supply_type, enemy_pos + Vector2(float(i) * 25.0, 0.0))


func _spawn_supply(supply_type: int, spawn_pos: Vector2) -> void:
	# spawn_pos is Python top-left coordinates.
	var powerup_scene := load("res://scenes/powerups/powerup.tscn") as PackedScene
	if not powerup_scene or not get_parent():
		return

	var powerup := powerup_scene.instantiate() as PowerUp
	if not powerup:
		return

	powerup.power_up_type = supply_type
	powerup.global_position = spawn_pos + Vector2(10.0, 10.0)
	get_parent().add_child(powerup)


func _spawn_split_children() -> void:
	var enemy_scene_ref := load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref or not get_parent():
		return
	for _i in range(2):
		var child := enemy_scene_ref.instantiate() as Enemy
		if not child:
			continue
		child.enemy_kind = EnemyKind.SPLIT
		child.is_child_split = true
		child.global_position = global_position + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))
		get_parent().add_child(child)


func _on_area_entered(area: Area2D) -> void:
	if GameManager.time_stop_active:
		return
	if area.is_in_group("player") and area.has_method("take_damage"):
		area.take_damage(damage)


func _remove_if_outside_screen() -> void:
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var pos := _python_pos()
	if pos.x > viewport_size.x + 100.0 or pos.x < -100.0 or pos.y < -100.0:
		queue_free()
		return

	# Treat the BottomBar UI area as out-of-bounds for gameplay entities.
	if global_position.y > playfield_bottom - HALF_SIZE:
		queue_free()


func _python_pos() -> Vector2:
	# Convert centered Godot position -> Python top-left (40x40 sprites).
	return global_position - Vector2(HALF_SIZE, HALF_SIZE)


func _get_player_python_pos() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not player or not is_instance_valid(player) or player.is_queued_for_deletion():
		return Vector2.ZERO
	# Aim/tracking should target the player's center (Touhou-style hitpoint), not the pygame top-left.
	return player.global_position


class TanSample:
	var tan_value: float
	var sample: int


func _calc_tan_and_sample(from_pos: Vector2, to_pos: Vector2) -> TanSample:
	var out := TanSample.new()
	var dx := to_pos.x - from_pos.x
	var dy := to_pos.y - from_pos.y
	if dx != 0.0:
		out.tan_value = dy / dx
		out.sample = -1 if dx < 0.0 else 1
	else:
		out.tan_value = 0.0
		out.sample = 0
	return out


func _dir_from_tan_sample(tan_value: float, sample: int) -> Vector2:
	if sample == 0:
		return Vector2.LEFT
	return Vector2(float(sample), float(sample) * tan_value).normalized()


func _python_bullet_speed_per_sec(speed_value: float, sample: int) -> float:
	# Python Bumb.draw():
	# - sample == 0: moves by `speed` per tick.
	# - sample != 0: moves by sqrt(speed) per tick.
	if sample == 0:
		return speed_value * FPS
	return sqrt(speed_value) * FPS


func _safe_tan(angle_rad: float) -> float:
	var c := cos(angle_rad)
	if abs(c) < 0.00001:
		return 1000000.0 * float(sign(sin(angle_rad)))
	return tan(angle_rad)


func _get_base_enemy_hp(kind: int) -> int:
	match kind:
		EnemyKind.BASE_1:
			return 30
		EnemyKind.BASE_2:
			return 50
		EnemyKind.BASE_3:
			return 70
		EnemyKind.BASE_4:
			return 100
		EnemyKind.BASE_5:
			return 120
		EnemyKind.BASE_6:
			return 150
		EnemyKind.BASE_7:
			return 200
		_:
			return 50


func _roll_base_visual_enemy_id() -> int:
	# Python Enemy.__init__ roll based on bossdeathtimes.
	var boss_deaths := maxi(1, GameManager.boss_death_times)
	var max_base := 7
	if boss_deaths - 1 <= 3:
		max_base = 4 + (boss_deaths - 1)
	return randi_range(1, max_base)
