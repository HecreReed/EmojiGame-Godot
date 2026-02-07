extends SceneTree

const REPORT_EVERY_FRAMES := 60
const TOTAL_FRAMES := 600

func _init() -> void:
	var main_scene := load("res://scenes/world/main.tscn") as PackedScene
	if not main_scene:
		push_error("Failed to load res://scenes/world/main.tscn")
		quit(1)
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)

	# Allow autoloads + scene _ready to run.
	await process_frame
	await process_frame

	var stage_manager := root.get_node_or_null("StageManager")
	if stage_manager and stage_manager.has_method("enter_boss_phase"):
		stage_manager.set("current_stage", 1)
		stage_manager.set("stage_duration", 0.1)
		stage_manager.call("enter_boss_phase")
	else:
		print("WARN: StageManager not found; continuing")

	for i in range(TOTAL_FRAMES):
		await process_frame
		if i % REPORT_EVERY_FRAMES == 0:
			var boss_count := get_nodes_in_group("boss").size()
			var bullet_count := get_nodes_in_group("enemy_bullets").size()
			print("frame=%d boss=%d enemy_bullets=%d" % [i, boss_count, bullet_count])

	quit(0)
