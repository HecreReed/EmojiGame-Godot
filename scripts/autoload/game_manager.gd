extends Node
## Global game manager singleton

signal score_changed(new_score: int)
signal health_changed(current_health: int, max_health: int)
signal money_changed(new_money: int)
signal power_changed(new_power: int)
signal combo_changed(combo: int, multiplier: float)
signal achievement_unlocked(name: String)
signal game_over
signal game_paused
signal game_resumed
signal player_hit
signal bomb_used
signal spellcard_declared(spell_name: String, bonus: int, is_final: bool)
signal spellcard_bonus_failed(spell_name: String)
signal spellcard_result(spell_name: String, captured: bool, timed_out: bool, bonus_awarded: int)

var score: int = 0
var high_score: int = 0
var money: int = 0
var power: int = 0  # 0-100
var is_paused: bool = false
var time_stop_active: bool = false
var time_stop_freeze_player: bool = false
var time_stop_freeze_boss: bool = true
var _time_stop_end_sec: float = 0.0
var boss_death_times: int = 1  # Python: bossdeathtimes (starts at 1, increments per boss defeat)

# Playfield bounds (exclude BottomBar HUD area)
const DEFAULT_BOTTOM_UI_HEIGHT: float = 120.0
var _playfield_bottom_override_y: float = 0.0

# Score multiplier system
var score_multiplier: float = 1.0
var multiplier_end_time: float = 0.0

# Combo system (Python GameSystems parity)
var combo: int = 0
var max_combo: int = 0
var combo_timeout: float = 3.0
var last_kill_time: float = 0.0

var combo_levels := {
	10: 1.5,
	25: 2.0,
	50: 3.0,
	100: 5.0,
	200: 10.0
}

# Runtime stats
var stats := {
	"total_kills": 0,
	"total_bosses_killed": 0,
	"total_bombs_used": 0,
	"total_supplies_collected": 0
}

# Achievement definitions
var achievements := {
	"first_blood": {"name": "首杀", "unlocked": false},
	"combo_10": {"name": "连击新手", "unlocked": false},
	"combo_50": {"name": "连击大师", "unlocked": false},
	"combo_100": {"name": "连击之神", "unlocked": false},
	"score_10k": {"name": "初出茅庐", "unlocked": false},
	"score_100k": {"name": "游戏高手", "unlocked": false},
	"score_1m": {"name": "传奇玩家", "unlocked": false},
	"boss_1": {"name": "Boss杀手", "unlocked": false},
	"boss_all": {"name": "Boss终结者", "unlocked": false},
	"bomb_master": {"name": "炸弹大师", "unlocked": false},
	"collector": {"name": "收集狂魔", "unlocked": false}
}

func _ready():
	load_high_score()
	reset_run_state()

func _process(_delta):
	# Check if score multiplier expired
	var now := Time.get_ticks_msec() / 1000.0
	if score_multiplier > 1.0 and now > multiplier_end_time:
		score_multiplier = 1.0

	if combo > 0 and now - last_kill_time > combo_timeout:
		combo = 0
		combo_changed.emit(combo, 1.0)

func add_score(amount: int, use_combo: bool = false):
	var actual_score := float(amount) * score_multiplier
	if use_combo:
		actual_score *= get_combo_multiplier()
	var score_to_add := int(round(actual_score))
	score += score_to_add
	if score > high_score:
		high_score = score
		save_high_score()
	score_changed.emit(score)
	check_score_achievements()

func register_enemy_kill(base_score: int = 100) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if combo > 0 and now - last_kill_time > combo_timeout:
		combo = 0
	combo += 1
	last_kill_time = now
	max_combo = max(max_combo, combo)
	stats["total_kills"] += 1
	combo_changed.emit(combo, get_combo_multiplier())
	add_score(base_score, true)
	check_combo_achievements()
	check_stat_achievements()

func register_boss_kill(base_score: int = 10000) -> void:
	register_enemy_kill(base_score)
	stats["total_bosses_killed"] += 1
	check_stat_achievements()

func register_bomb_used() -> void:
	stats["total_bombs_used"] += 1
	bomb_used.emit()
	check_stat_achievements()

func notify_player_hit() -> void:
	player_hit.emit()

func register_supply_collected() -> void:
	stats["total_supplies_collected"] += 1
	check_stat_achievements()

func report_health(current_health: int, max_health: int) -> void:
	health_changed.emit(current_health, max_health)

func get_combo_multiplier() -> float:
	var multiplier := 1.0
	var thresholds := combo_levels.keys()
	thresholds.sort()
	thresholds.reverse()
	for threshold in thresholds:
		if combo >= threshold:
			multiplier = combo_levels[threshold]
			break
	return multiplier

func unlock_achievement(id: String) -> void:
	if not achievements.has(id):
		return
	if achievements[id]["unlocked"]:
		return
	achievements[id]["unlocked"] = true
	achievement_unlocked.emit(achievements[id]["name"])

func check_combo_achievements() -> void:
	if combo >= 10:
		unlock_achievement("combo_10")
	if combo >= 50:
		unlock_achievement("combo_50")
	if combo >= 100:
		unlock_achievement("combo_100")

func check_score_achievements() -> void:
	if score >= 10000:
		unlock_achievement("score_10k")
	if score >= 100000:
		unlock_achievement("score_100k")
	if score >= 1000000:
		unlock_achievement("score_1m")

func check_stat_achievements() -> void:
	if stats["total_kills"] >= 1:
		unlock_achievement("first_blood")
	if stats["total_bosses_killed"] >= 1:
		unlock_achievement("boss_1")
	if stats["total_bosses_killed"] >= 6:
		unlock_achievement("boss_all")
	if stats["total_bombs_used"] >= 10:
		unlock_achievement("bomb_master")
	if stats["total_supplies_collected"] >= 100:
		unlock_achievement("collector")

func reset_run_state() -> void:
	score = 0
	money = 0
	power = 0
	boss_death_times = 1
	score_multiplier = 1.0
	multiplier_end_time = 0.0
	combo = 0
	max_combo = 0
	last_kill_time = 0.0
	stats = {
		"total_kills": 0,
		"total_bosses_killed": 0,
		"total_bombs_used": 0,
		"total_supplies_collected": 0
	}
	for id in achievements.keys():
		achievements[id]["unlocked"] = false
	score_changed.emit(score)
	money_changed.emit(money)
	power_changed.emit(power)
	combo_changed.emit(combo, 1.0)

func add_money(amount: int):
	money = maxi(money + amount, 0)
	money_changed.emit(money)

func add_power(amount: int):
	power = clampi(power + amount, 0, 100)
	power_changed.emit(power)

func start_time_stop(duration: float = 2.0, freeze_player: bool = false, freeze_boss: bool = true):
	# Allows overlapping time stops by extending the end timestamp.
	var now := Time.get_ticks_msec() / 1000.0
	_time_stop_end_sec = maxf(_time_stop_end_sec, now + duration)

	if time_stop_active:
		time_stop_freeze_player = time_stop_freeze_player or freeze_player
		time_stop_freeze_boss = time_stop_freeze_boss or freeze_boss
		return

	time_stop_freeze_player = freeze_player
	time_stop_freeze_boss = freeze_boss
	time_stop_active = true
	while (Time.get_ticks_msec() / 1000.0) < _time_stop_end_sec:
		await get_tree().create_timer(0.05).timeout
	time_stop_active = false
	time_stop_freeze_player = false
	time_stop_freeze_boss = true

func set_playfield_bottom_override_y(y: float) -> void:
	# HUD may report BottomBar's top Y so gameplay never enters it.
	_playfield_bottom_override_y = maxf(0.0, y)

func get_viewport_size() -> Vector2:
	var tree := get_tree()
	if tree and tree.root:
		return tree.root.get_visible_rect().size
	return Vector2(1280, 960)

func get_playfield_bottom_y(viewport_size: Vector2 = Vector2.ZERO) -> float:
	var size := viewport_size
	if size == Vector2.ZERO:
		size = get_viewport_size()

	var bottom_y := size.y - DEFAULT_BOTTOM_UI_HEIGHT
	if _playfield_bottom_override_y > 0.0:
		bottom_y = minf(_playfield_bottom_override_y, size.y)
	return maxf(0.0, bottom_y)

func get_playfield_rect(viewport_size: Vector2 = Vector2.ZERO) -> Rect2:
	var size := viewport_size
	if size == Vector2.ZERO:
		size = get_viewport_size()
	return Rect2(Vector2.ZERO, Vector2(size.x, get_playfield_bottom_y(size)))

func activate_score_multiplier(multiplier: float, duration: float):
	score_multiplier = multiplier
	multiplier_end_time = Time.get_ticks_msec() / 1000.0 + duration

func reset_score():
	score = 0
	score_multiplier = 1.0
	combo = 0
	score_changed.emit(score)
	combo_changed.emit(combo, 1.0)

func pause_game():
	if not is_paused:
		is_paused = true
		get_tree().paused = true
		game_paused.emit()

func resume_game():
	if is_paused:
		is_paused = false
		get_tree().paused = false
		game_resumed.emit()

func trigger_game_over():
	game_over.emit()

func load_high_score():
	# Load from file or config
	if FileAccess.file_exists("user://highscore.save"):
		var file = FileAccess.open("user://highscore.save", FileAccess.READ)
		if file:
			high_score = file.get_32()
			file.close()

func save_high_score():
	var file = FileAccess.open("user://highscore.save", FileAccess.WRITE)
	if file:
		file.store_32(high_score)
		file.close()

func restart_game():
	reset_run_state()
	if StageManager:
		StageManager.reset()
	get_tree().paused = false
	is_paused = false
	get_tree().reload_current_scene()
