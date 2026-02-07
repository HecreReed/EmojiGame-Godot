extends Area2D
class_name EnemyBullet

enum BulletType {
	NORMAL,      # 直线射击
	TRACKING,    # 追踪玩家
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

func _ready():
	add_to_group("enemy_bullets")  # 加入敌方子弹组，用于炸弹/清屏清除
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

	# 根据子弹类型设置初始参数
	match bullet_type:
		BulletType.TRACKING:
			tracking_enabled = true
		BulletType.RANDOM:
			direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()

func _physics_process(delta):
	if tracking_enabled and bullet_type == BulletType.TRACKING:
		# 追踪玩家
		var player = get_tree().get_first_node_in_group("player")
		if player:
			direction = (player.global_position - global_position).normalized()

	position += direction * speed * delta

	# 旋转精灵以匹配方向
	if direction.length() > 0:
		rotation = direction.angle()

	# Remove bullet if out of screen
	if position.x > 1300 or position.x < -100 or position.y > 800 or position.y < -100:
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("player"):
		if area.has_method("take_damage"):
			area.take_damage(damage)
		queue_free()

func _on_body_entered(body):
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
