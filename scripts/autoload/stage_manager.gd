extends Node
## Stage/phase system (Python StageSystem parity)

signal stage_changed(new_stage: int)
signal phase_changed(new_phase: int)
signal game_cleared

enum StagePhase { STAGE, BOSS, CLEAR, GAME_CLEAR }

@export var total_stages: int = 6
@export var stage_duration: float = 60.0
@export var stage_clear_delay: float = 3.0

var current_stage: int = 1
var current_phase: StagePhase = StagePhase.STAGE

var stage_elapsed: float = 0.0
var clear_elapsed: float = 0.0


func _ready() -> void:
	reset()


func _process(delta: float) -> void:
	# Python version freezes stage progression during time stop.
	if GameManager.time_stop_active:
		return

	match current_phase:
		StagePhase.STAGE:
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
	stage_changed.emit(current_stage)
	phase_changed.emit(current_phase)
	if AudioManager:
		AudioManager.play_bgm_file("bgm%d.mp3" % current_stage)


func enter_boss_phase() -> void:
	if current_phase != StagePhase.STAGE:
		return
	current_phase = StagePhase.BOSS
	phase_changed.emit(current_phase)
	if AudioManager:
		AudioManager.play_bgm_file("boss%d.mp3" % current_stage)


func on_boss_defeated() -> void:
	if current_phase != StagePhase.BOSS:
		return

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

	if AudioManager:
		AudioManager.play_sfx_file("death.mp3")
		# Python: during CLEAR delay, start next stage BGM immediately.
		AudioManager.play_bgm_file("bgm%d.mp3" % (current_stage + 1))

	current_phase = StagePhase.CLEAR
	clear_elapsed = 0.0
	phase_changed.emit(current_phase)


func next_stage() -> void:
	if current_phase != StagePhase.CLEAR:
		return
	current_stage = clamp(current_stage + 1, 1, total_stages)
	current_phase = StagePhase.STAGE
	stage_elapsed = 0.0
	clear_elapsed = 0.0
	stage_changed.emit(current_stage)
	phase_changed.emit(current_phase)
	if AudioManager:
		AudioManager.play_bgm_file("bgm%d.mp3" % current_stage)


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
	return "Stage %d/%d - %s" % [current_stage, total_stages, phase_text.get(current_phase, "")]
