extends Node

## Regression probe:
## Ensure long-running boss patterns don't keep executing after the boss is freed.
## This prevents: "Invalid access to property or key 'global_position' on a base object of type 'previously freed'."

@export var boss_id: int = 6
@export var pattern_method: String = "_special_butterfly_swarm"
@export var free_after_sec: float = 0.05
@export var wait_after_free_sec: float = 1.0

var _pattern_state: Variant = null

func _ready() -> void:
	var boss_scene := load("res://scenes/enemies/boss_enemy.tscn") as PackedScene
	if not boss_scene:
		push_error("Failed to load res://scenes/enemies/boss_enemy.tscn")
		get_tree().quit(1)
		return

	var boss := boss_scene.instantiate()
	add_child(boss)

	if "boss_id" in boss:
		boss.boss_id = boss_id
	if "boss_health" in boss:
		boss.boss_health = 999999

	if boss is Node2D:
		(boss as Node2D).global_position = Vector2(900, 320)

	# Let boss initialize.
	await get_tree().process_frame
	await get_tree().process_frame

	print("[regression] start pattern=%s boss_id=%d" % [pattern_method, boss_id])
	if not boss.has_method(pattern_method):
		push_error("Boss has no method: %s" % pattern_method)
		get_tree().quit(1)
		return

	# Keep a reference to the coroutine state so it can resume after awaits.
	_pattern_state = boss.call(pattern_method)

	# Free the boss mid-pattern.
	await get_tree().create_timer(maxf(0.0, free_after_sec)).timeout
	print("[regression] queue_free boss")
	if is_instance_valid(boss):
		boss.queue_free()

	# Give time for any pending awaits to resume; if the pattern doesn't guard instance validity,
	# the engine will print a "previously freed" error during this window.
	await get_tree().create_timer(maxf(0.0, wait_after_free_sec)).timeout
	print("[regression] done")
	get_tree().quit(0)

