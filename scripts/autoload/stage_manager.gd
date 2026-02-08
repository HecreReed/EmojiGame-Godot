extends Node
## Stage/phase system (Python StageSystem parity)

signal stage_changed(new_stage: int)
signal phase_changed(new_phase: int)
signal midboss_changed(active: bool)
signal game_cleared

enum StagePhase { STAGE, BOSS, CLEAR, GAME_CLEAR }

@export var total_stages: int = 6
@export var stage_duration: float = 60.0
@export var stage_clear_delay: float = 3.0

var current_stage: int = 1
var current_phase: StagePhase = StagePhase.STAGE

var stage_elapsed: float = 0.0
var clear_elapsed: float = 0.0
var midboss_active: bool = false


func _ready() -> void:
	reset()


func _process(delta: float) -> void:
	# Python version freezes stage progression during time stop.
	if GameManager.time_stop_active:
		return

	match current_phase:
		StagePhase.STAGE:
			# Midboss segment: pause the stage timer until the midboss is defeated.
			if midboss_active:
				return
			stage_elapsed += delta
			if stage_elapsed >= stage_duration:
				enter_boss_phase()

		StagePhase.CLEAR:
			clear_elapsed += delta
			if clear_elapsed >= stage_clear_delay:
				next_stage()

		_:
			pass


func reset() -> void:
	current_stage = 1
	current_phase = StagePhase.STAGE
	stage_elapsed = 0.0
	clear_elapsed = 0.0
	midboss_active = false
	stage_changed.emit(current_stage)
	phase_changed.emit(current_phase)
	midboss_changed.emit(midboss_active)
	if AudioManager:
		AudioManager.play_bgm_file("bgm%d.mp3" % current_stage)


func set_midboss_active(active: bool) -> void:
	if midboss_active == active:
		return
	midboss_active = active
	midboss_changed.emit(midboss_active)


func enter_boss_phase() -> void:
	if current_phase != StagePhase.STAGE:
		return
	set_midboss_active(false)
	current_phase = StagePhase.BOSS
	phase_changed.emit(current_phase)
	if AudioManager:
		AudioManager.play_bgm_file("boss%d.mp3" % current_stage)


func on_boss_defeated() -> void:
	if current_phase != StagePhase.BOSS:
		return

	# Touhou-like cleanup: clear bullets/hazards and any boss-summoned enemies immediately.
	if not is_inside_tree():
		return
	var tree := get_tree()
	for b in tree.get_nodes_in_group("enemy_bullets"):
		if b and is_instance_valid(b):
			b.queue_free()
	# Clear slowdown zones / lingering hazards (e.g. Boss3 time bubbles).
	for z in tree.get_nodes_in_group("slow_zone"):
		if z and is_instance_valid(z):
			z.queue_free()
	for h in tree.get_nodes_in_group("boss_hazards"):
		if h and is_instance_valid(h):
			h.queue_free()
	for e in tree.get_nodes_in_group("enemies"):
		if e and is_instance_valid(e):
			e.queue_free()
	for p in tree.get_nodes_in_group("prevent"):
		if p and is_instance_valid(p):
			p.queue_free()

	# Python: bossdeathtimes increments on real boss death.
	GameManager.boss_death_times += 1

	# Last stage -> game clear
	if current_stage >= total_stages:
		current_phase = StagePhase.GAME_CLEAR
		phase_changed.emit(current_phase)
		game_cleared.emit()
		if AudioManager:
			AudioManager.stop_music()
		return

	# Start next stage assets immediately (Touhou-like: instant transition).
	var next_stage := clampi(current_stage + 1, 1, total_stages)
	if AudioManager:
		AudioManager.play_sfx_file("death.mp3")
		AudioManager.play_bgm_file("bgm%d.mp3" % next_stage)

	current_stage = next_stage
	stage_changed.emit(current_stage)

	current_phase = StagePhase.CLEAR
	stage_elapsed = 0.0
	clear_elapsed = 0.0
	phase_changed.emit(current_phase)


func next_stage() -> void:
	if current_phase != StagePhase.CLEAR:
		return
	current_phase = StagePhase.STAGE
	stage_elapsed = 0.0
	clear_elapsed = 0.0
	set_midboss_active(false)
	phase_changed.emit(current_phase)
	# BGM was already set in on_boss_defeated().


func is_game_cleared() -> bool:
	return current_phase == StagePhase.GAME_CLEAR


func get_stage_progress() -> int:
	if current_phase != StagePhase.STAGE:
		return 100
	return min(100, int((stage_elapsed / stage_duration) * 100.0))


func get_stage_remaining_time() -> int:
	if current_phase != StagePhase.STAGE:
		return 0
	return max(0, int(ceil(stage_duration - stage_elapsed)))


func get_stage_info() -> String:
	var phase_text := {
		StagePhase.STAGE: "道中",
		StagePhase.BOSS: "Boss战",
		StagePhase.CLEAR: "通过",
		StagePhase.GAME_CLEAR: "通关"
	}
	var label: String = str(phase_text.get(current_phase, ""))
	if current_phase == StagePhase.STAGE and midboss_active:
		label = "中Boss"
	return "Stage %d/%d - %s" % [current_stage, total_stages, label]
