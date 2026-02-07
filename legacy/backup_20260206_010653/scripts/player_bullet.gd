class_name PlayerBullet
extends Area2D

var speed: float = 600.0
var damage: int = 10

func _ready():
	add_to_group("player_bullets")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta):
	position.y -= speed * delta
	
	# Remove if off screen
	if position.y < -20:
		queue_free()

func _on_body_entered(body):
	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("enemies"):
		if area.has_method("take_damage"):
			area.take_damage(damage)
		queue_free()
