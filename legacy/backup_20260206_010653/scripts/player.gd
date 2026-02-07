class_name Player
extends CharacterBody2D

# Player stats
var max_hp: int = 5
var current_hp: int = 5
var speed: float = 300.0
var slow_speed: float = 150.0
var power: int = 1
var max_power: int = 5
var bomb_count: int = 3
var time_stop_energy: float = 0.0
var max_time_stop_energy: float = 100.0

# Shooting
var shoot_timer: float = 0.0
var shoot_interval: float = 0.1
var bullet_scene: PackedScene

# State
var is_invincible: bool = false
var invincible_timer: float = 0.0
var invincible_duration: float = 2.0
var is_time_stopped: bool = false

# Signals
signal hp_changed(new_hp: int)
signal power_changed(new_power: int)
signal bomb_count_changed(new_count: int)
signal time_stop_energy_changed(new_energy: float)
signal player_died()

func _ready():
	position = Vector2(240, 600)
	bullet_scene = preload("res://scenes/player_bullet.tscn")

func _physics_process(delta):
	handle_movement(delta)
	handle_shooting(delta)
	update_invincibility(delta)
	
	# Regenerate time stop energy
	if time_stop_energy < max_time_stop_energy:
		time_stop_energy = min(time_stop_energy + 10 * delta, max_time_stop_energy)
		time_stop_energy_changed.emit(time_stop_energy)

func handle_movement(_delta):
	var input_vector = Vector2.ZERO
	
	if Input.is_action_pressed("ui_right"):
		input_vector.x += 1
	if Input.is_action_pressed("ui_left"):
		input_vector.x -= 1
	if Input.is_action_pressed("ui_down"):
		input_vector.y += 1
	if Input.is_action_pressed("ui_up"):
		input_vector.y -= 1
	
	input_vector = input_vector.normalized()
	
	# Slow mode when shift is pressed
	var current_speed = slow_speed if Input.is_action_pressed("ui_shift") else speed
	velocity = input_vector * current_speed
	
	move_and_slide()
	
	# Clamp position to screen bounds
	position.x = clamp(position.x, 20, 460)
	position.y = clamp(position.y, 20, 680)

func handle_shooting(delta):
	shoot_timer -= delta
	
	if Input.is_action_pressed("ui_accept") and shoot_timer <= 0:
		shoot()
		shoot_timer = shoot_interval

func shoot():
	var bullets_container = get_tree().get_first_node_in_group("bullets")
	if not bullets_container:
		return
	
	# Shoot pattern based on power level
	match power:
		1:
			spawn_bullet(position + Vector2(0, -20))
		2:
			spawn_bullet(position + Vector2(-10, -20))
			spawn_bullet(position + Vector2(10, -20))
		3:
			spawn_bullet(position + Vector2(-15, -20))
			spawn_bullet(position + Vector2(0, -20))
			spawn_bullet(position + Vector2(15, -20))
		4:
			spawn_bullet(position + Vector2(-20, -20))
			spawn_bullet(position + Vector2(-7, -20))
			spawn_bullet(position + Vector2(7, -20))
			spawn_bullet(position + Vector2(20, -20))
		_:
			spawn_bullet(position + Vector2(-25, -20))
			spawn_bullet(position + Vector2(-12, -20))
			spawn_bullet(position + Vector2(0, -20))
			spawn_bullet(position + Vector2(12, -20))
			spawn_bullet(position + Vector2(25, -20))

func spawn_bullet(pos: Vector2):
	var bullet = bullet_scene.instantiate()
	bullet.position = pos
	get_tree().get_first_node_in_group("bullets").add_child(bullet)

func take_damage(amount: int = 1):
	if is_invincible:
		return
	
	current_hp -= amount
	hp_changed.emit(current_hp)
	
	if current_hp <= 0:
		die()
	else:
		is_invincible = true
		invincible_timer = invincible_duration

func update_invincibility(delta):
	if is_invincible:
		invincible_timer -= delta
		if invincible_timer <= 0:
			is_invincible = false
		# Blink effect
		modulate.a = 0.5 if int(invincible_timer * 10) % 2 == 0 else 1.0
	else:
		modulate.a = 1.0

func die():
	player_died.emit()
	queue_free()

func heal(amount: int = 1):
	current_hp = min(current_hp + amount, max_hp)
	hp_changed.emit(current_hp)

func increase_power(amount: int = 1):
	power = min(power + amount, max_power)
	power_changed.emit(power)

func add_bomb(amount: int = 1):
	bomb_count += amount
	bomb_count_changed.emit(bomb_count)

func use_bomb():
	if bomb_count > 0:
		bomb_count -= 1
		bomb_count_changed.emit(bomb_count)
		# Clear all enemy bullets
		var enemy_bullets = get_tree().get_nodes_in_group("enemy_bullets")
		for bullet in enemy_bullets:
			bullet.queue_free()
		# Damage all enemies
		var enemies = get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if enemy.has_method("take_damage"):
				enemy.take_damage(50)

func use_time_stop(duration: float = 5.0):
	if time_stop_energy >= 50:
		time_stop_energy -= 50
		time_stop_energy_changed.emit(time_stop_energy)
		is_time_stopped = true
		get_tree().call_group("enemies", "set_time_stopped", true)
		get_tree().call_group("enemy_bullets", "set_time_stopped", true)
		await get_tree().create_timer(duration).timeout
		is_time_stopped = false
		get_tree().call_group("enemies", "set_time_stopped", false)
		get_tree().call_group("enemy_bullets", "set_time_stopped", false)
