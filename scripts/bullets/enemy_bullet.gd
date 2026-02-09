extends Area2D
class_name EnemyBullet

enum BulletType {
	NORMAL,      # 直线射击
	TRACKING,    # 朝向玩家（默认锁定一次；需要时可开启真追踪）
	CIRCLE,      # 圆形弹幕
	SAND,        # 散射
	RANDOM,      # 随机方向
	BUTTERFLY,   # 蝴蝶弹 - 正弦波曲线运动
	LASER,       # 激光 - 超高速直线
	SPIRAL,      # 螺旋弹 - 持续旋转方向
	SPLIT,       # 分裂弹 - 飞行一段时间后分裂
	ACCELERATE,  # 加速弹 - 持续加速
	DECELERATE,  # 减速弹 - 持续减速后停止
	BOUNCE,      # 弹跳弹 - 碰墙反弹
	HOMING,      # 追踪弹 - 持续追踪玩家
	WAVE_SINE,   # 正弦波弹
	WAVE_COS,    # 余弦波弹
	SINE_WAVE,   # 正弦波弹（兼容Boss脚本旧命名）
	CURVE        # 曲线弹（缓慢转向）
}

@export var speed: float = 400.0
@export var damage: int = 10
@export var bullet_type: BulletType = BulletType.NORMAL
@export var can_return: bool = false # Python: canReturn (bounce off walls)
@export var can_delete: bool = true # Python: canDelete (remove on hit)
@export var can_remove: bool = true # Python: canRemove (removed by Boss2 prevent barriers)
@export var ban_remove: bool = false # Python: banRemove (do not despawn when offscreen)
@export var rotate_with_direction: bool = true # Default: face movement direction
@export var spin_speed: float = 0.0 # Radians/sec, for spinning bullets (e.g. Boss1 star)
@export var turn_rate: float = 0.0 # Radians/sec, rotates movement direction over time
@export var start_delay: float = 0.0 # Seconds before the bullet starts moving
@export var acceleration: float = 0.0 # px/s^2, applied after start_delay

# Wave motion (Touhou-like): sinusoidal drift perpendicular to travel direction.
# If `wave_amplitude` or `wave_frequency` is 0, the wave motion is disabled.
@export var wave_amplitude: float = 0.0 # px
@export var wave_frequency: float = 0.0 # rad/sec
@export var wave_phase: float = 0.0 # rad

var direction: Vector2 = Vector2.LEFT
var target_position: Vector2 = Vector2.ZERO
var tracking_enabled: bool = false
var tan_value: float = 0.0
var rotation_angle: float = 0.0
var is_blown_away: bool = false
var _was_time_stop_active: bool = false
var _wave_time: float = 0.0
var _lifetime: float = 0.0  # 用于分裂弹等需要计时的类型
var _split_triggered: bool = false  # 分裂弹是否已分裂
var _butterfly_time: float = 0.0  # 蝴蝶弹计时器
var _homing_strength: float = 2.0  # 追踪强度
var _homing_duration: float = 1.0  # 追踪持续时间（秒）
var _homing_finished: bool = false  # 追踪是否结束
var _decel_stopped_time: float = -1.0  # 减速弹停止后的计时 (-1 = 还没停)
var _decel_initial_speed: float = 0.0  # 减速弹的初始速度（用于重新发射）
var _decel_re_aimed: bool = false  # 是否已经重新瞄准

# Orbit (Touhou-like gimmick): keep the bullet circling for a while, then optionally dash.
var orbit_center: Vector2 = Vector2.ZERO
var orbit_radius: float = 0.0
var orbit_angle: float = 0.0
var orbit_angular_speed: float = 0.0 # rad/s
var orbit_time_left: float = 0.0
var dash_after_orbit: bool = false
var dash_target: Vector2 = Vector2.ZERO
var dash_speed: float = 0.0

func _ready():
	add_to_group("enemy_bullets")  # 加入敌方子弹组，用于炸弹/清屏清除
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func set_sprite(texture_path: String) -> void:
	if texture_path == "":
		return
	var bullet_sprite := get_node_or_null("Sprite2D") as Sprite2D
	if not bullet_sprite:
		return
	var tex := load(texture_path) as Texture2D
	if tex:
		bullet_sprite.texture = tex

func _physics_process(delta):
	var time_stop_now := GameManager.time_stop_active
	if _was_time_stop_active and not time_stop_now:
		_check_overlap_on_time_stop_resume()
	_was_time_stop_active = time_stop_now

	if not time_stop_now:
		# Start delay (telegraph): the bullet exists but doesn't move yet.
		if start_delay > 0.0:
			start_delay = maxf(0.0, start_delay - delta)
		elif orbit_time_left > 0.0:
			orbit_time_left = maxf(0.0, orbit_time_left - delta)
			orbit_angle += orbit_angular_speed * delta
			global_position = orbit_center + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius
			if orbit_time_left <= 0.0 and dash_after_orbit:
				var to_target := dash_target - global_position
				if to_target.length() > 0.0:
					direction = to_target.normalized()
				speed = dash_speed
				dash_after_orbit = false
		else:
			_lifetime += delta

			# 处理特殊子弹类型
			match bullet_type:
				BulletType.BUTTERFLY:
					_butterfly_time += delta
					var perp := Vector2(-direction.y, direction.x).normalized()
					var wave_offset := sin(_butterfly_time * 5.0) * 50.0
					position += direction * speed * delta + perp * wave_offset * delta

				BulletType.LASER:
					# 激光 - 超高速
					position += direction * speed * 2.0 * delta

				BulletType.SPIRAL:
					# 螺旋弹 - 持续旋转
					direction = direction.rotated(3.0 * delta).normalized()
					position += direction * speed * delta

				BulletType.SPLIT:
					# 分裂弹 - 1秒后分裂成3个
					if _lifetime > 1.0 and not _split_triggered:
						_split_triggered = true
						_spawn_split_bullets()
						queue_free()
					else:
						position += direction * speed * delta

				BulletType.ACCELERATE:
					# 加速弹
					speed += 100.0 * delta
					position += direction * speed * delta

				BulletType.DECELERATE:
					# 减速弹 - 停止后1秒重新瞄准玩家射击
					if not _decel_re_aimed:
						if _decel_initial_speed == 0.0:
							_decel_initial_speed = speed
						speed = maxf(0.0, speed - 150.0 * delta)
						if speed <= 0.0:
							if _decel_stopped_time < 0.0:
								_decel_stopped_time = 0.0
							_decel_stopped_time += delta
							if _decel_stopped_time >= 1.0:
								aim_at_player()
								speed = maxf(_decel_initial_speed * 0.8, 180.0)
								_decel_re_aimed = true
					position += direction * speed * delta

				BulletType.BOUNCE:
					# 弹跳弹
					position += direction * speed * delta
					_apply_wall_bounce()

				BulletType.HOMING:
					# 追踪弹 - 追踪一段时间后沿切线射击
					if not _homing_finished and _lifetime < _homing_duration:
						var player := get_tree().get_first_node_in_group("player") as Node2D
						if player and is_instance_valid(player):
							var to_player := (player.global_position - global_position).normalized()
							direction = direction.lerp(to_player, _homing_strength * delta).normalized()
					elif not _homing_finished:
						# 追踪结束，锁定当前方向
						_homing_finished = true
					position += direction * speed * delta

				BulletType.WAVE_SINE:
					# 正弦波弹
					_wave_time += delta
					var perp := Vector2(-direction.y, direction.x).normalized()
					var wave_offset := sin(_wave_time * 4.0) * 30.0
					position += direction * speed * delta + perp * wave_offset * delta

				BulletType.WAVE_COS:
					# 余弦波弹
					_wave_time += delta
					var perp := Vector2(-direction.y, direction.x).normalized()
					var wave_offset := cos(_wave_time * 4.0) * 30.0
					position += direction * speed * delta + perp * wave_offset * delta

				BulletType.SINE_WAVE:
					# 兼容Boss脚本的正弦波弹（更明显一些）
					_wave_time += delta
					var perp := Vector2(-direction.y, direction.x).normalized()
					var wave_offset := sin(_wave_time * 4.2) * 40.0
					position += direction * speed * delta + perp * wave_offset * delta

				BulletType.CURVE:
					# 曲线弹：持续缓慢转向（类似东方里“弧线”弹）
					var rate := turn_rate
					if rate == 0.0:
						rate = 1.2
					direction = direction.rotated(rate * delta).normalized()
					position += direction * speed * delta

				_:
					# 默认行为（NORMAL, TRACKING等）
					if tracking_enabled and bullet_type == BulletType.TRACKING:
						# 真·追踪（Boss2等需要）
						aim_at_player()

					if turn_rate != 0.0 and direction.length() > 0.0:
						direction = direction.rotated(turn_rate * delta).normalized()

					if acceleration != 0.0:
						speed = maxf(0.0, speed + acceleration * delta)

					position += direction * speed * delta
					_apply_wave(delta)

					if can_return:
						_apply_wall_bounce()

	# Visual rotation
	if rotate_with_direction and direction.length() > 0:
		rotation = direction.angle()
	if spin_speed != 0.0:
		rotation += spin_speed * delta

	# Remove bullet if out of screen
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	var extent_y := _get_vertical_extent()
	var bottom_limit := playfield_bottom - extent_y

	# BottomBar UI area is not part of the playfield.
	if position.y > bottom_limit:
		queue_free()
		return

	if not ban_remove and (position.x > viewport_size.x + 100 or position.x < -100 or position.y < -100):
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("player"):
		if GameManager and ("god_mode_enabled" in GameManager) and GameManager.god_mode_enabled:
			return
		if GameManager.time_stop_active:
			return
		if is_blown_away:
			return
		if area.has_method("take_damage"):
			area.take_damage(damage)
		if can_delete:
			queue_free()

func _on_body_entered(body):
	if body.is_in_group("player"):
		if GameManager and ("god_mode_enabled" in GameManager) and GameManager.god_mode_enabled:
			return
		if GameManager.time_stop_active:
			return
		if is_blown_away:
			return
		if body.has_method("take_damage"):
			body.take_damage(damage)
		if can_delete:
			queue_free()

func get_damage() -> int:
	return damage

func blow_away():
	# Match Python "blow" skill: force straight right, disable tracking
	is_blown_away = true
	tracking_enabled = false
	bullet_type = BulletType.NORMAL
	direction = Vector2.RIGHT
	# Fully disable collisions so blown bullets can never hurt the player.
	collision_mask = 0
	collision_layer = 0

func aim_at_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and is_instance_valid(player) and not player.is_queued_for_deletion():
		direction = (player.global_position - global_position).normalized()

func _apply_wave(delta: float) -> void:
	if wave_amplitude == 0.0 or wave_frequency == 0.0:
		return
	if direction.length() == 0.0:
		return
	_wave_time += delta
	var perp := Vector2(-direction.y, direction.x).normalized()
	var lateral_speed := wave_amplitude * wave_frequency * cos(_wave_time * wave_frequency + wave_phase)
	position += perp * lateral_speed * delta

func _check_overlap_on_time_stop_resume() -> void:
	# Python parity: time stop renders bullets but does not process collisions.
	# When time stop ends, if the player is still overlapping a bullet, it should be able to hit.
	if GameManager and ("god_mode_enabled" in GameManager) and GameManager.god_mode_enabled:
		return
	if is_blown_away:
		return

	for area in get_overlapping_areas():
		if area and area.is_in_group("player"):
			if area.has_method("take_damage"):
				area.take_damage(damage)
			if can_delete:
				queue_free()
			return

func _apply_wall_bounce() -> void:
	# Python bounce behavior: reflect off left wall, and top/bottom borders.
	# Note: Python doesn't bounce off the right wall (bullets usually despawn there).
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	var extent_x := _get_horizontal_extent()
	var extent_y := _get_vertical_extent()

	if position.x <= extent_x and direction.x < 0.0:
		direction = direction.bounce(Vector2.RIGHT).normalized()
		position.x = extent_x + 1.0

	if position.y <= extent_y and direction.y < 0.0:
		direction = direction.bounce(Vector2.DOWN).normalized()
		position.y = extent_y + 1.0
	elif position.y >= playfield_bottom - extent_y and direction.y > 0.0:
		direction = direction.bounce(Vector2.UP).normalized()
		position.y = playfield_bottom - extent_y - 1.0

func _get_horizontal_extent() -> float:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs and cs.shape:
		var shape := cs.shape
		if shape is CircleShape2D:
			return (shape as CircleShape2D).radius
		if shape is RectangleShape2D:
			return (shape as RectangleShape2D).size.x * 0.5
	return 8.0

func _get_vertical_extent() -> float:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs and cs.shape:
		var shape := cs.shape
		if shape is CircleShape2D:
			return (shape as CircleShape2D).radius
		if shape is RectangleShape2D:
			return (shape as RectangleShape2D).size.y * 0.5
	return 8.0

func _spawn_split_bullets() -> void:
	# 分裂成3个子弹
	var angles = [-PI/4, 0, PI/4]  # 左、中、右
	for angle_offset in angles:
		var new_bullet = duplicate() as EnemyBullet
		if new_bullet:
			new_bullet.global_position = global_position
			new_bullet.direction = direction.rotated(angle_offset).normalized()
			new_bullet.bullet_type = BulletType.NORMAL  # 分裂后变成普通弹
			new_bullet._split_triggered = true  # 防止再次分裂
			new_bullet.speed = speed * 0.8
			get_parent().add_child(new_bullet)
