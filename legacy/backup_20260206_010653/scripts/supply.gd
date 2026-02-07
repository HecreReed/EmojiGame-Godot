class_name Supply
extends Area2D

enum SupplyType {
	HEAL,
	POWER,
	BOMB,
	MONEY,
	SCORE
}

var supply_type: SupplyType = SupplyType.MONEY
var fall_speed: float = 150.0
var value: int = 1
var is_attracted: bool = false
var attraction_speed: float = 400.0

func _ready():
	add_to_group("supplies")
	area_entered.connect(_on_area_entered)

func _physics_process(delta):
	var player = get_tree().get_first_node_in_group("player")
	
	if player and is_attracted:
		# Move towards player
		var direction = (player.position - position).normalized()
		position += direction * attraction_speed * delta
	else:
		# Fall down
		position.y += fall_speed * delta
		
		# Check if player is nearby for auto-attraction
		if player and position.distance_to(player.position) < 100:
			is_attracted = true
	
	# Remove if off screen
	if position.y > 720:
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("player"):
		apply_effect(area)
		queue_free()

func apply_effect(player):
	match supply_type:
		SupplyType.HEAL:
			if player.has_method("heal"):
				player.heal(value)
		SupplyType.POWER:
			if player.has_method("increase_power"):
				player.increase_power(value)
		SupplyType.BOMB:
			if player.has_method("add_bomb"):
				player.add_bomb(value)
		SupplyType.MONEY:
			# Add money to game manager
			var game_manager = get_tree().get_first_node_in_group("game_manager")
			if game_manager and game_manager.has_method("add_money"):
				game_manager.add_money(value)
		SupplyType.SCORE:
			# Add score to game manager
			var game_manager = get_tree().get_first_node_in_group("game_manager")
			if game_manager and game_manager.has_method("add_score"):
				game_manager.add_score(value)

static func spawn_supply(pos: Vector2, type: SupplyType, val: int = 1):
	var supply_scene = preload("res://scenes/supply.tscn")
	var supply = supply_scene.instantiate()
	supply.position = pos
	supply.supply_type = type
	supply.value = val
	return supply
