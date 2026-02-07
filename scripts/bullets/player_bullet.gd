extends Area2D
class_name PlayerBullet

@export var speed: float = 1080.0
@export var damage: int = 10

var direction: Vector2 = Vector2.RIGHT

# Python parity flags/properties
var remove_on_hit: bool = true  # WaterBumb.Remove (False for powerShoot)

# Penetrating bullets
var can_penetrate: bool = false
var penetrate_count: int = 0

# Bombardment bullets
var is_bomb: bool = false
var explosion_radius: float = 0.0

# Homing missiles
var is_homing: bool = false

# Wave bullets
var is_wave: bool = false
var wave_frequency: float = 0.1
var wave_phase: float = 0.0

# Spiral bullets
var is_spiral: bool = false
var spiral_angle: float = 0.0
var spiral_radius: float = 0.0
var spiral_ended: bool = false
var spiral_radius_shrink_per_sec: float = 120.0  # 2px/tick @60fps
var spiral_angle_speed: float = 12.0  # 0.2 rad/tick @60fps
var spiral_release_speed: float = 900.0  # 15px/tick @60fps

func _ready():
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	# Freeze bullets during time stop (Python: draw only, no movement update)
	if GameManager.time_stop_active:
		return

	# Spiral movement overrides normal movement until released.
	if is_spiral and not spiral_ended:
		_update_spiral(delta)
	else:
		# Homing adjusts direction each frame.
		if is_homing:
			_update_homing()

		position += direction * speed * delta

		# Wave bullets add a sinusoidal vertical drift (Python: y += sin(x*freq+phase)*2 each tick).
		if is_wave:
			position.y += sin(position.x * wave_frequency + wave_phase) * (120.0 * delta)  # 2px/tick @60fps

	# Remove bullet if out of screen
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	var bottom_limit := playfield_bottom - _get_vertical_extent()
	if position.y > bottom_limit:
		queue_free()
		return
	if position.x > viewport_size.x + 100 or position.x < -100 or position.y < -100:
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("enemies"):
		_apply_hit(area)

func _on_body_entered(body):
	if body.is_in_group("enemies"):
		_apply_hit(body)


func _apply_hit(enemy: Node) -> void:
	if enemy and enemy.has_method("take_damage"):
		enemy.take_damage(damage)

	if is_bomb and explosion_radius > 0.0:
		_explode()
		queue_free()
		return

	if can_penetrate:
		penetrate_count -= 1
		if penetrate_count <= 0:
			queue_free()
		return

	if remove_on_hit:
		queue_free()


func _explode() -> void:
	# BombardmentShot.explode(): damage falloff by distance.
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not enemy or not enemy.has_method("take_damage") or not (enemy is Node2D):
			continue
		var enemy_node := enemy as Node2D
		var dist: float = enemy_node.global_position.distance_to(global_position)
		if dist <= explosion_radius:
			var ratio: float = 1.0 - (dist / explosion_radius)
			var dmg: int = int(round(float(damage) * ratio))
			if dmg > 0:
				enemy.take_damage(dmg)


func _update_homing() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var closest: Node2D = null
	var min_dist := INF
	for e in enemies:
		if e is Node2D:
			var d := (e as Node2D).global_position.distance_to(global_position)
			if d < min_dist:
				min_dist = d
				closest = e as Node2D
	if closest:
		direction = (closest.global_position - global_position).normalized()


func _update_spiral(delta: float) -> void:
	spiral_radius = max(0.0, spiral_radius - spiral_radius_shrink_per_sec * delta)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and is_instance_valid(player) and not player.is_queued_for_deletion() and spiral_radius > 0.0:
		global_position = player.global_position + Vector2(cos(spiral_angle), sin(spiral_angle)) * spiral_radius
		spiral_angle += spiral_angle_speed * delta
		return

	# Release: convert current angle to a straight direction.
	if not spiral_ended:
		spiral_ended = true
		direction = Vector2(cos(spiral_angle), sin(spiral_angle)).normalized()
		speed = spiral_release_speed

func _get_vertical_extent() -> float:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs and cs.shape:
		var shape := cs.shape
		if shape is CircleShape2D:
			return (shape as CircleShape2D).radius
		if shape is RectangleShape2D:
			return (shape as RectangleShape2D).size.y * 0.5
	return 8.0
