extends Area2D
class_name EnemyBullet

enum BulletType {
	NORMAL,      # 直线射击
	TRACKING,    # 朝向玩家（默认锁定一次；需要时可开启真追踪）
	CIRCLE,      # 圆形弹幕
	SAND,        # 散射
	RANDOM       # 随机方向
}

@export var speed: float = 400.0
@export var damage: int = 10
@export var bullet_type: BulletType = BulletType.NORMAL
@export var can_return: bool = false # Python: canReturn (bounce off walls)
@export var can_delete: bool = true # Python: canDelete (remove on hit)
@export var ban_remove: bool = false # Python: banRemove (do not despawn when offscreen)
@export var rotate_with_direction: bool = true # Default: face movement direction
@export var spin_speed: float = 0.0 # Radians/sec, for spinning bullets (e.g. Boss1 star)
@export var turn_rate: float = 0.0 # Radians/sec, rotates movement direction over time

var direction: Vector2 = Vector2.LEFT
var target_position: Vector2 = Vector2.ZERO
var tracking_enabled: bool = false
var tan_value: float = 0.0
var rotation_angle: float = 0.0
var is_blown_away: bool = false
var _was_time_stop_active: bool = false

func _ready():
	add_to_group("enemy_bullets")  # 加入敌方子弹组，用于炸弹/清屏清除
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	var time_stop_now := GameManager.time_stop_active
	if _was_time_stop_active and not time_stop_now:
		_check_overlap_on_time_stop_resume()
	_was_time_stop_active = time_stop_now

	if not time_stop_now:
		if tracking_enabled and bullet_type == BulletType.TRACKING:
			# 真·追踪（Boss2等需要）
			aim_at_player()

		if turn_rate != 0.0 and direction.length() > 0.0:
			direction = direction.rotated(turn_rate * delta).normalized()

		position += direction * speed * delta

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

func _check_overlap_on_time_stop_resume() -> void:
	# Python parity: time stop renders bullets but does not process collisions.
	# When time stop ends, if the player is still overlapping a bullet, it should be able to hit.
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
