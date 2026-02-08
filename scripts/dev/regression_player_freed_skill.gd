extends Node

## Regression probe:
## Player skill coroutines must stop cleanly when the player is freed.
## Prevents: "Invalid access to property or key 'global_position' on a base object of type 'previously freed'."

@export var free_after_sec: float = 0.12
@export var wait_after_free_sec: float = 0.6

var _state: Variant = null

func _ready() -> void:
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	if not player_scene:
		push_error("Failed to load res://scenes/player/player.tscn")
		get_tree().quit(1)
		return

	var player := player_scene.instantiate()
	add_child(player)

	# Allow player _ready to initialize bullet_scene and timers.
	await get_tree().process_frame
	await get_tree().process_frame

	if not is_instance_valid(player):
		get_tree().quit(1)
		return

	print("[regression] start use_crazy_shoot()")
	if player.has_method("use_crazy_shoot"):
		_state = player.call("use_crazy_shoot")

	await get_tree().create_timer(maxf(0.0, free_after_sec)).timeout
	print("[regression] queue_free player")
	if is_instance_valid(player):
		player.queue_free()

	await get_tree().create_timer(maxf(0.0, wait_after_free_sec)).timeout
	print("[regression] done")
	get_tree().quit(0)

