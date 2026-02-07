class_name Enemy
extends Area2D

# Enemy stats
var max_hp: int = 50
var current_hp: int = 50
var speed: float = 100.0
var score_value: int = 100
var is_time_stopped: bool = false

# Movement pattern
enum MovementPattern {
	STRAIGHT_DOWN,
	ZIGZAG,
	CIRCLE,
	SINE_WAVE
}
var movement_pattern: MovementPattern = MovementPattern.STRAIGHT_DOWN
var movement_timer: float = 0.0

# Shooting
var shoot_timer: float = 0.0
var shoot_interval: float = 1.0
var bullet_scene: PackedScene

# Signals
signal enemy_died(score: int, position: Vector2)

func _ready():
	add_to_group("enemies")
	bullet_scene = preload("res://scenes/enemy_bullet.tscn")
	area_entered.connect(_on_area_entered)

func _physics_process(delta):
	if not is_time_stopped:
		movement_timer += delta
		update_movement(delta)
		update_shooting(delta)
	
	# Remove if off screen
	if position.y > 720:
		queue_free()

func update_movement(delta):
	match movement_pattern:
		MovementPattern.STRAIGHT_DOWN:
			position.y += speed * delta
		MovementPattern.ZIGZAG:
			position.y += speed * delta
			position.x += sin(movement_timer * 3) * 100 * delta
		MovementPattern.CIRCLE:
			var radius = 50
			position.x += cos(movement_timer * 2) * radius * delta
			position.y += sin(movement_timer * 2) * radius * delta + speed * delta
		MovementPattern.SINE_WAVE:
			position.y += speed * delta
			position.x += cos(movement_timer * 2) * 150 * delta

func update_shooting(delta):
	shoot_timer -= delta
	if shoot_timer <= 0:
		shoot()
		shoot_timer = shoot_interval

func shoot():
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	var bullet = bullet_scene.instantiate()
	bullet.position = position
	
	# Aim at player
	var direction = (player.position - position).normalized()
	bullet.velocity = direction * 200
	
	get_tree().get_first_node_in_group("bullets").add_child(bullet)

func take_damage(amount: int):
	current_hp -= amount
	
	# Flash effect
	modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	modulate = Color.WHITE
	
	if current_hp <= 0:
		die()

func die():
	enemy_died.emit(score_value, position)
	queue_free()

func _on_area_entered(area):
	if area.is_in_group("player"):
		if area.has_method("take_damage"):
			area.take_damage(1)
		die()

func set_time_stopped(stopped: bool):
	is_time_stopped = stopped
