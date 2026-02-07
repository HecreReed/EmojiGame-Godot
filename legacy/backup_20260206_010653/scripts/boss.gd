class_name Boss
extends Area2D

# Boss stats
var max_hp: int = 1000
var current_hp: int = 1000
var speed: float = 150.0
var score_value: int = 10000
var is_time_stopped: bool = false

# Boss phases
var current_phase: int = 0
var phase_hp_thresholds: Array[int] = [800, 600, 400, 200]

# Movement
var movement_timer: float = 0.0
var target_position: Vector2 = Vector2(240, 150)

# Shooting patterns
var shoot_timer: float = 0.0
var shoot_interval: float = 0.5
var bullet_scene: PackedScene
var pattern_timer: float = 0.0

# Signals
signal boss_died(score: int)
signal phase_changed(new_phase: int)
signal hp_changed(current: int, maximum: int)

func _ready():
	add_to_group("enemies")
	add_to_group("bosses")
	bullet_scene = preload("res://scenes/enemy_bullet.tscn")
	position = Vector2(240, -50)
	area_entered.connect(_on_area_entered)

func _physics_process(delta):
	if not is_time_stopped:
		movement_timer += delta
		pattern_timer += delta
		update_movement(delta)
		update_shooting(delta)

func update_movement(delta):
	# Move to target position
	var direction = (target_position - position).normalized()
	if position.distance_to(target_position) > 5:
		position += direction * speed * delta
	else:
		# Change target position periodically
		if int(movement_timer) % 3 == 0:
			target_position = Vector2(
				randf_range(100, 380),
				randf_range(100, 200)
			)

func update_shooting(delta):
	shoot_timer -= delta
	if shoot_timer <= 0:
		shoot_pattern()
		shoot_timer = shoot_interval

func shoot_pattern():
	match current_phase:
		0:
			shoot_circle_pattern(8)
		1:
			shoot_spiral_pattern()
		2:
			shoot_aimed_burst()
		3:
			shoot_random_spread()
		_:
			shoot_final_pattern()

func shoot_circle_pattern(bullet_count: int):
	for i in range(bullet_count):
		var angle = (TAU / bullet_count) * i + pattern_timer
		var direction = Vector2(cos(angle), sin(angle))
		spawn_bullet(direction * 150)

func shoot_spiral_pattern():
	var angle = pattern_timer * 2
	for i in range(3):
		var offset_angle = angle + (TAU / 3) * i
		var direction = Vector2(cos(offset_angle), sin(offset_angle))
		spawn_bullet(direction * 200)

func shoot_aimed_burst():
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	var base_direction = (player.position - position).normalized()
	for i in range(-2, 3):
		var angle = atan2(base_direction.y, base_direction.x) + deg_to_rad(i * 15)
		var direction = Vector2(cos(angle), sin(angle))
		spawn_bullet(direction * 250)

func shoot_random_spread():
	for i in range(5):
		var angle = randf() * TAU
		var direction = Vector2(cos(angle), sin(angle))
		spawn_bullet(direction * randf_range(100, 300))

func shoot_final_pattern():
	# Combination of patterns
	shoot_circle_pattern(12)
	shoot_spiral_pattern()
	if int(pattern_timer * 10) % 3 == 0:
		shoot_aimed_burst()

func spawn_bullet(velocity: Vector2):
	var bullet = bullet_scene.instantiate()
	bullet.position = position
	bullet.velocity = velocity
	get_tree().get_first_node_in_group("bullets").add_child(bullet)

func take_damage(amount: int):
	current_hp -= amount
	hp_changed.emit(current_hp, max_hp)
	
	# Check phase transition
	for i in range(phase_hp_thresholds.size()):
		if current_hp <= phase_hp_thresholds[i] and current_phase == i:
			current_phase = i + 1
			phase_changed.emit(current_phase)
			shoot_interval = max(0.2, shoot_interval - 0.1)
			break
	
	# Flash effect
	modulate = Color.RED
	await get_tree().create_timer(0.1).timeout
	modulate = Color.WHITE
	
	if current_hp <= 0:
		die()

func die():
	boss_died.emit(score_value)
	# Clear all bullets
	var bullets = get_tree().get_nodes_in_group("enemy_bullets")
	for bullet in bullets:
		bullet.queue_free()
	queue_free()

func _on_area_entered(area):
	if area.is_in_group("player"):
		if area.has_method("take_damage"):
			area.take_damage(1)

func set_time_stopped(stopped: bool):
	is_time_stopped = stopped
