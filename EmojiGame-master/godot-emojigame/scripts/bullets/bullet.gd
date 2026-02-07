extends Area2D
class_name Bullet

@export var speed: float = 500.0
@export var damage: int = 10
@export var direction: Vector2 = Vector2.RIGHT

@onready var sprite: Sprite2D = $Sprite2D

func _ready():
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	position += direction * speed * delta

	# Remove bullet if out of screen
	if position.x > 1200 or position.x < -100 or position.y > 800 or position.y < -100:
		queue_free()

func _on_body_entered(body):
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
