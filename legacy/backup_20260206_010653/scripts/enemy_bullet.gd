class_name EnemyBullet
extends Area2D

var velocity: Vector2 = Vector2(0, 200)
var damage: int = 1
var is_time_stopped: bool = false

func _ready():
	add_to_group("enemy_bullets")
	area_entered.connect(_on_area_entered)

func _physics_process(delta):
	if not is_time_stopped:
		position += velocity * delta
	
	# Remove if off screen
	if position.y > 720 or position.y < -20 or position.x < -20 or position.x > 500:
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("player"):
		if area.has_method("take_damage"):
			area.take_damage(damage)
		queue_free()

func set_time_stopped(stopped: bool):
	is_time_stopped = stopped
