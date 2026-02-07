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

var direction: Vector2 = Vector2.LEFT
var target_position: Vector2 = Vector2.ZERO
var tracking_enabled: bool = false
var tan_value: float = 0.0
var rotation_angle: float = 0.0
var is_blown_away: bool = false

func _ready():
	add_to_group("enemy_bullets")  # 加入敌方子弹组，用于炸弹/清屏清除
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	if not GameManager.time_stop_active:
		if tracking_enabled and bullet_type == BulletType.TRACKING:
			# 真·追踪（Boss2等需要）
			aim_at_player()

		position += direction * speed * delta

	# 旋转精灵以匹配方向
	if direction.length() > 0:
		rotation = direction.angle()

	# Remove bullet if out of screen
	var viewport_size := get_viewport_rect().size
	if position.x > viewport_size.x + 100 or position.x < -100 or position.y > viewport_size.y + 100 or position.y < -100:
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("player"):
		if is_blown_away:
			return
		if area.has_method("take_damage"):
			area.take_damage(damage)
		queue_free()

func _on_body_entered(body):
	if body.is_in_group("player"):
		if is_blown_away:
			return
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()

func get_damage() -> int:
	return damage

func blow_away():
	# Match Python "blow" skill: force straight right, disable tracking
	is_blown_away = true
	tracking_enabled = false
	bullet_type = BulletType.NORMAL
	direction = Vector2.RIGHT
	set_collision_mask_value(1, false)

func aim_at_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		direction = (player.global_position - global_position).normalized()
