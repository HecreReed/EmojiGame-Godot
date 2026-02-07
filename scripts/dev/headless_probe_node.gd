extends Node

@export var report_every_frames: int = 60
@export var total_frames: int = 600

var _frame: int = 0

func _ready() -> void:
	# Load and run the real main scene under this probe root.
	var main_scene := load("res://scenes/world/main.tscn") as PackedScene
	if not main_scene:
		push_error("Failed to load main.tscn")
		get_tree().quit(1)
		return

	add_child(main_scene.instantiate())

	# Allow nodes to initialize.
	await get_tree().process_frame
	await get_tree().process_frame

	# Default: force boss phase quickly for headless verification.
	# Use `--mode=stage` to test stage + midboss logic instead.
	var mode := "boss"
	var stage := 5
	var stage_duration_override := -1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.get_slice("=", 1)
		if arg.begins_with("--stage="):
			stage = maxi(1, int(arg.get_slice("=", 1)))
		if arg.begins_with("--stage-duration="):
			stage_duration_override = float(arg.get_slice("=", 1))
	StageManager.current_stage = stage

	if mode == "stage":
		StageManager.stage_duration = 1.0 if stage_duration_override <= 0.0 else stage_duration_override
		# Jump close to midboss spawn point so EnemySpawner can be exercised quickly.
		StageManager.stage_elapsed = StageManager.stage_duration * 0.60
	else:
		StageManager.stage_duration = 0.1 if stage_duration_override <= 0.0 else stage_duration_override
		StageManager.enter_boss_phase()

	set_process(true)

func _process(_delta: float) -> void:
	_frame += 1
	if _frame % report_every_frames == 0:
		var boss_count := get_tree().get_nodes_in_group("boss").size()
		var bullet_count := get_tree().get_nodes_in_group("enemy_bullets").size()
		print("frame=%d boss=%d enemy_bullets=%d stage_elapsed=%.2f midboss=%s" % [_frame, boss_count, bullet_count, StageManager.stage_elapsed, str(StageManager.midboss_active)])

	if _frame >= total_frames:
		get_tree().quit(0)
