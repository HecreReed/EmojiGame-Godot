extends Area2D
class_name PlayerBullet

@export var speed: float = 600.0
@export var damage: int = 10

var direction: Vector2 = Vector2.RIGHT

func _ready():
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	position += direction * speed * delta

	# Remove bullet if out of screen
	if position.x > 1300 or position.x < -100 or position.y > 800 or position.y < -100:
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("enemies"):
		if area.has_method("take_damage"):
			area.take_damage(damage)
		queue_free()

func _on_body_entered(body):
	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
