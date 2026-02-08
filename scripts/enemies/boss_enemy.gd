extends Enemy
class_name BossEnemy

@export var boss_health: int = 2000
@export var boss_id: int = 1  # 1-6
@export var boss_speed: float = 100.0
@export var boss_bullet_speed_scale: float = 0.80 # Leave reaction time; applies to this boss' bullets

enum PhaseKind { NONSPELL, SPELL, FINAL }
enum PatternPoolMode { CYCLE, RANDOM }

class BossPhaseDef:
	var kind: int = PhaseKind.NONSPELL
	var name: String = ""
	var max_hp: int = 1
	var time_limit_sec: float = 45.0
	var basic_shot_interval_sec: float = 0.8
	var pattern_interval_sec: float = 2.0
	var start_delay_sec: float = 0.8
	var pattern: Callable = Callable()
	var pattern_pool: Array[Callable] = []
	var pattern_pool_mode: int = PatternPoolMode.CYCLE
	var pattern_pool_index: int = 0

var current_phase: int = 1
var is_phase_boss: bool = false

var pattern_timer: float = 0.0
var pattern_interval: float = 3.0
var is_boss: bool = true
var _made_in_heaven_active: bool = false
var _boss2_attract_active: bool = false
var _boss2_prevent_ready: bool = false
var _boss2_prevent_nodes: Array[Node] = []
var _boss2_last_bounce_shot_sec: float = 0.0
var _boss1_portal_ref: Node = null

var movement_timer: float = 0.0
var _basic_shoot_suppressed_until: float = 0.0
var _move_target: Vector2 = Vector2.ZERO
var _move_next_change_sec: float = 0.0
var _move_token_seen: int = -1
var _move_teleport_next_sec: float = 0.0

# Boss5 heal mode (Python: Event.healtime)
var _boss5_heal_mode_active: bool = false
var _boss6_last_phase: int = 0

# Touhou-like phase system (normal/spell/final with time limits)
var phase_defs: Array[BossPhaseDef] = []
var phase_index: int = 0
var phase_kind: int = PhaseKind.NONSPELL
var phase_name: String = ""
var phase_time_left_sec: float = 0.0
var phase_time_limit_sec: float = 0.0
var phase_start_real_sec: float = 0.0
var _phase_token: int = 0
var _phase_transitioning: bool = false
var _pattern_running: bool = false
var _next_basic_shot_sec: float = 0.0
var _next_pattern_sec: float = 0.0

var spell_card_invulnerable_until: float = 0.0
var skill_invulnerable_until: float = 0.0

# Spellcard bonus system (Touhou-like)
var spell_bonus_start: int = 0
var spell_bonus_current: int = 0
var spell_bonus_valid: bool = false

# Boss enhancement parity
var shield_enabled: bool = false
var boss_shield_hp: int = 0
var boss_shield_hp_max: int = 0
var shield_regen_rate: float = 0.0
var shield_regen_delay: float = 5.0
var last_damage_time: float = 0.0

var absorb_hits_remaining: int = 0

var invincible_cycle_enabled: bool = false
var invincible_cycle_duration: float = 0.0
var invincible_cycle_interval: float = 0.0
var invincible_cycle_timer: float = 0.0
var invincible_cycle_elapsed: float = 0.0
var invincible_cycle_active: bool = false

var summon_enabled: bool = false
var summon_interval: float = 0.0
var summon_timer: float = 0.0
var summon_count: int = 0

var enrage_enabled: bool = false
var enraged: bool = false

var phase_transition_enabled: bool = false
var phase_thresholds: Array[float] = [0.75, 0.5, 0.25]
var phase_threshold_triggered: Dictionary = {}

func _ready() -> void:
	super._ready()
	add_to_group("boss")

	var stage: int = maxi(1, int(StageManager.current_stage))
	# Boss durability (Touhou-like): multiple bars should not melt instantly.
	var baseline_hp: int = 20000 + (stage - 1) * 15000
	if is_midboss:
		# Midboss should be chunky, but clearly below the stage boss.
		baseline_hp = 9000 + (stage - 1) * 6500
	var total_hp: int = maxi(int(boss_health), baseline_hp)
	if boss_id == 6 and not is_midboss:
		# Final boss gets a bit more total HP (5 bars).
		total_hp = int(round(float(total_hp) * 1.6))
		is_phase_boss = true

	boss_health = total_hp
	speed = boss_speed + float(stage - 1) * 12.0
	score_value = (4500 if is_midboss else 10000) + (stage - 1) * 1200
	damage = 20 + (stage - 1) * 2

	_apply_boss_visual()
	last_damage_time = Time.get_ticks_msec() / 1000.0

	# Disable base Enemy timer shooting; phase system schedules attacks.
	if shoot_timer:
		shoot_timer.stop()

	phase_defs = _build_midboss_phase_defs(total_hp) if is_midboss else _build_touhou_phase_defs(total_hp)
	_start_phase(0)

	# Spell Bonus invalidation hooks
	if GameManager and GameManager.has_signal("player_hit"):
		GameManager.player_hit.connect(_on_player_hit)
	if GameManager and GameManager.has_signal("bomb_used"):
		GameManager.bomb_used.connect(_on_bomb_used)

	if boss_id == 2:
		# Keep Boss2's "prevent" barriers for the whole fight.
		_boss2_ensure_prevent()

func _is_spellcard_phase() -> bool:
	return phase_kind == PhaseKind.SPELL or phase_kind == PhaseKind.FINAL

func _compute_spell_bonus_start(stage: int, kind: int, _index: int) -> int:
	var s := maxi(1, stage)
	# Touhou-like baseline (see Touhou Wiki "Spell Card Bonus" formula).
	# This project does not currently expose difficulty selection; treat as Normal (1).
	var difficulty_value := 1
	var base := 3000000 * s + 2000000 * difficulty_value
	# Final spell gets a bit more weight to feel like a "Last Spell".
	if kind == PhaseKind.FINAL:
		base += 1000000 * s
	return maxi(100000, base)

func _start_spellcard_bonus(def: BossPhaseDef) -> void:
	spell_bonus_start = 0
	spell_bonus_current = 0
	spell_bonus_valid = false

	if def.kind != PhaseKind.SPELL and def.kind != PhaseKind.FINAL:
		return

	var stage := 1
	if StageManager:
		stage = maxi(1, int(StageManager.current_stage))

	spell_bonus_start = _compute_spell_bonus_start(stage, def.kind, phase_index)
	spell_bonus_current = spell_bonus_start
	spell_bonus_valid = true

	if GameManager and GameManager.has_signal("spellcard_declared"):
		GameManager.spellcard_declared.emit(def.name, spell_bonus_start, def.kind == PhaseKind.FINAL)

func _update_spell_bonus() -> void:
	if not _is_spellcard_phase():
		spell_bonus_current = 0
		return
	if not spell_bonus_valid:
		spell_bonus_current = 0
		return
	if phase_time_limit_sec <= 0.0:
		spell_bonus_current = spell_bonus_start
		return
	# Touhou-like: bonus stays at start for 5s, then decreases at a constant rate,
	# ending at ~1/3 of the starting value at time out.
	var grace_sec := 5.0
	var now_sec := Time.get_ticks_msec() / 1000.0
	var elapsed := maxf(0.0, now_sec - phase_start_real_sec)
	if elapsed <= grace_sec or phase_time_limit_sec <= grace_sec:
		spell_bonus_current = spell_bonus_start
		return

	var denom := maxf(1.0, phase_time_limit_sec - grace_sec)
	var rate := (2.0 / 3.0) * float(spell_bonus_start) / denom
	var value := int(round(float(spell_bonus_start) - rate * (elapsed - grace_sec)))
	var min_value := int(round(float(spell_bonus_start) / 3.0))
	spell_bonus_current = clampi(value, min_value, spell_bonus_start)

func _on_player_hit() -> void:
	_invalidate_spell_bonus()

func _on_bomb_used() -> void:
	_invalidate_spell_bonus()

func _invalidate_spell_bonus() -> void:
	if not _is_spellcard_phase():
		return
	if not spell_bonus_valid:
		return
	spell_bonus_valid = false
	if GameManager and GameManager.has_signal("spellcard_bonus_failed"):
		GameManager.spellcard_bonus_failed.emit(phase_name)

func _setup_attack_timing() -> void:
	match boss_id:
		1:
			shoot_cooldown = 0.6
		2:
			# Python BossEnemies.py: sleepbumbtime = 5
			shoot_cooldown = 5.0
		3:
			# Python BossEnemies.py: sleepbumbtime = 1.5
			shoot_cooldown = 1.5
		4:
			shoot_cooldown = 1.8
		5:
			shoot_cooldown = 1.8
		6:
			# Python BossEnemies.py doesn't override sleepbumbtime for Boss6.
			shoot_cooldown = 0.6
		_:
			shoot_cooldown = 1.0

	# Skill cadence uses randomized 4-8s in Python (Boss6 varies by phase).
	pattern_interval = randf_range(4.0, 8.0)

func _apply_boss_visual() -> void:
	var texture_path: String = "res://assets/sprites/bossenemy-%d.png" % clampi(boss_id, 1, 6)
	var tex: Texture2D = load(texture_path)
	if sprite and tex:
		sprite.texture = tex
		sprite.scale = Vector2.ONE
		sprite.modulate = Color(1, 1, 1, 1)

	var body_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape and body_shape.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = body_shape.shape as RectangleShape2D
		rect_shape.size = Vector2(80, 80)

func _setup_enhancements() -> void:
	var difficulty: int = clampi(int(StageManager.current_stage), 1, 5)

	shield_enabled = true
	boss_shield_hp_max = int(round(float(max_health) * (0.2 + float(difficulty) * 0.1)))
	boss_shield_hp = boss_shield_hp_max
	shield_regen_rate = float(max_health) * (0.004 + 0.002 * float(difficulty))

	match difficulty:
		1:
			enrage_enabled = false
		2:
			enrage_enabled = true
		3:
			enrage_enabled = true
			summon_enabled = true
			summon_interval = 14.0
			summon_count = 2
			phase_transition_enabled = true
		4:
			enrage_enabled = true
			summon_enabled = true
			summon_interval = 12.0
			summon_count = 3
			phase_transition_enabled = true
			invincible_cycle_enabled = true
			invincible_cycle_duration = 2.5
			invincible_cycle_interval = 14.0
		5:
			enrage_enabled = true
			summon_enabled = true
			summon_interval = 10.0
			summon_count = 4
			phase_transition_enabled = true
			invincible_cycle_enabled = true
			invincible_cycle_duration = 3.2
			invincible_cycle_interval = 12.0
			absorb_hits_remaining = 15

func _physics_process(delta: float) -> void:
	if phase_defs.is_empty():
		return

	if GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
		# Touhou parity: spell bonus decreases in real time even if the boss is frozen.
		_update_spell_bonus()
		return

	# Phase timer
	var timer_delta := 0.0 if GameManager.time_stop_active else delta
	phase_time_left_sec = maxf(0.0, phase_time_left_sec - timer_delta)
	_update_spell_bonus()
	if phase_time_left_sec <= 0.0:
		_advance_phase(true)
		return

	var now_sec := Time.get_ticks_msec() / 1000.0

	current_phase = phase_index + 1
	boss_movement(delta)

	var def := phase_defs[phase_index]

	# Basic shooting (kept light; main difficulty comes from phase patterns).
	if def.basic_shot_interval_sec > 0.0 and now_sec >= _next_basic_shot_sec and now_sec >= _basic_shoot_suppressed_until:
		_next_basic_shot_sec = now_sec + def.basic_shot_interval_sec
		_phase_basic_shot()

	# Phase pattern (single-thread; no overlaps).
	var phase_pattern := _select_phase_pattern(def)
	if phase_pattern.is_valid() and not _pattern_running and now_sec >= _next_pattern_sec:
		_pattern_running = true
		_run_phase_pattern(_phase_token, phase_pattern)

func _update_enhancements(delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0

	if not shield_enabled and boss_shield_hp < boss_shield_hp_max and now - last_damage_time > shield_regen_delay:
		boss_shield_hp = mini(boss_shield_hp_max, boss_shield_hp + int(round(shield_regen_rate * delta)))
		if boss_shield_hp >= boss_shield_hp_max:
			shield_enabled = true

	if invincible_cycle_enabled:
		if invincible_cycle_active:
			invincible_cycle_elapsed += delta
			if invincible_cycle_elapsed >= invincible_cycle_duration:
				invincible_cycle_active = false
				invincible_cycle_elapsed = 0.0
				invincible_cycle_timer = 0.0
		else:
			invincible_cycle_timer += delta
			if invincible_cycle_timer >= invincible_cycle_interval:
				invincible_cycle_active = true
				invincible_cycle_elapsed = 0.0
				invincible_cycle_timer = 0.0

	if summon_enabled:
		summon_timer += delta
		if summon_timer >= summon_interval:
			summon_timer = 0.0
			_summon_minions()

	if enrage_enabled and not enraged and float(health) / float(max_health) <= 0.3:
		enraged = true
		speed *= 1.5
		shoot_cooldown = maxf(0.18, shoot_cooldown / 2.0)
		pattern_interval = maxf(1.0, pattern_interval * 0.7)
		if shoot_timer:
			shoot_timer.wait_time = shoot_cooldown

	if phase_transition_enabled:
		var hp_ratio: float = float(health) / float(max_health)
		for i in range(phase_thresholds.size()):
			if not phase_threshold_triggered.get(i, false) and hp_ratio <= phase_thresholds[i]:
				phase_threshold_triggered[i] = true
				_on_phase_transition(i)
				break

func _on_phase_transition(phase_index: int) -> void:
	_clear_enemy_bullets()
	match phase_index:
		0:
			shoot_cooldown = maxf(0.2, shoot_cooldown * 0.8)
		1:
			speed *= 1.25
		2:
			shoot_cooldown = maxf(0.15, shoot_cooldown * 0.75)
			speed *= 1.2

	if shoot_timer:
		shoot_timer.wait_time = shoot_cooldown

func _summon_minions() -> void:
	var enemy_scene_ref: PackedScene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref or not get_parent():
		return

	var minion_pool: Array[int] = [
		EnemyKind.FAST,
		EnemyKind.TANK,
		EnemyKind.SUICIDE,
		EnemyKind.SNIPER
	]

	for _i in range(summon_count):
		var minion: Enemy = enemy_scene_ref.instantiate() as Enemy
		if not minion:
			continue
		minion.enemy_kind = minion_pool[randi_range(0, minion_pool.size() - 1)]
		minion.global_position = global_position + Vector2(randf_range(-120.0, 120.0), randf_range(-80.0, 80.0))
		get_parent().add_child(minion)

func _clear_enemy_bullets() -> void:
	var bullets: Array = get_tree().get_nodes_in_group("enemy_bullets")
	for bullet in bullets:
		if is_instance_valid(bullet):
			bullet.queue_free()

func _get_player_safe() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not player:
		return null
	if not is_instance_valid(player):
		return null
	if player.is_queued_for_deletion():
		return null
	return player


func _select_phase_pattern(def: BossPhaseDef) -> Callable:
	if not def:
		return Callable()
	if def.pattern_pool.is_empty():
		return def.pattern

	var size := def.pattern_pool.size()
	if size <= 0:
		return def.pattern

	if def.pattern_pool_mode == PatternPoolMode.RANDOM:
		return def.pattern_pool[randi_range(0, size - 1)]

	var idx := def.pattern_pool_index % size
	def.pattern_pool_index = (def.pattern_pool_index + 1) % size
	return def.pattern_pool[idx]

func _pattern_should_abort(token: int) -> bool:
	# Prevent long-running coroutines from continuing after phase changes or scene teardown.
	if token != _phase_token:
		return true
	if _phase_transitioning or not _pattern_running:
		return true
	if not is_instance_valid(self) or not is_inside_tree() or not get_parent():
		return true
	return false

func _is_invincible() -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	return now < spell_card_invulnerable_until or now < skill_invulnerable_until or invincible_cycle_active

func take_damage(amount: int) -> void:
	if _is_invincible():
		return

	# Python Boss5 heal mode: player bullets heal the boss instead of damaging it.
	if boss_id == 5 and _boss5_heal_mode_active and amount > 0:
		health = mini(max_health, health + amount)
		_flash_damage()
		return

	last_damage_time = Time.get_ticks_msec() / 1000.0
	var pending_damage: int = amount

	if absorb_hits_remaining > 0:
		absorb_hits_remaining -= 1
		pending_damage = 0

	if shield_enabled and boss_shield_hp > 0 and pending_damage > 0:
		boss_shield_hp -= pending_damage
		if boss_shield_hp <= 0:
			pending_damage = abs(boss_shield_hp)
			shield_enabled = false
		else:
			pending_damage = 0

	if pending_damage > 0:
		health -= pending_damage
		_flash_damage()

	if health <= 0:
		_advance_phase(false)

func _flash_damage() -> void:
	if not sprite:
		return
	sprite.modulate = Color(1.2, 0.7, 0.7, 1)
	await get_tree().create_timer(0.05).timeout
	if is_instance_valid(self):
		_apply_boss_visual()

func die() -> void:
	GameManager.register_boss_kill(score_value)
	_spawn_boss_rewards()
	_clear_enemy_bullets()
	_cleanup_boss_persistent_nodes()
	queue_free()

func _start_phase(new_index: int) -> void:
	if new_index < 0 or new_index >= phase_defs.size():
		return

	_phase_token += 1
	_phase_transitioning = false
	_pattern_running = false
	phase_index = new_index
	current_phase = phase_index + 1

	# Reset per-phase flags that should not bleed across patterns.
	_basic_shoot_suppressed_until = 0.0
	_boss2_attract_active = false
	_made_in_heaven_active = false
	_boss5_heal_mode_active = false

	var def := phase_defs[phase_index]
	def.pattern_pool_index = 0
	phase_kind = def.kind
	phase_name = def.name
	max_health = maxi(1, int(def.max_hp))
	health = max_health
	phase_time_limit_sec = maxf(1.0, def.time_limit_sec)
	phase_time_left_sec = phase_time_limit_sec

	var now_sec := Time.get_ticks_msec() / 1000.0
	phase_start_real_sec = now_sec
	_next_basic_shot_sec = now_sec + maxf(0.05, def.start_delay_sec)
	_next_pattern_sec = now_sec + maxf(0.05, def.start_delay_sec)

	# Phase transition invulnerability and bullet clear (Touhou-like).
	spell_card_invulnerable_until = now_sec + 1.0
	_clear_enemy_bullets()
	_start_spellcard_bonus(def)

	# Keep boss inside the playfield (do not enter BottomBar).
	var viewport_size: Vector2 = get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	global_position.x = clampf(global_position.x, viewport_size.x * 0.55, viewport_size.x - 90.0)
	global_position.y = clampf(global_position.y, 70.0, playfield_bottom - 80.0)

func _advance_phase(timed_out: bool) -> void:
	if _phase_transitioning:
		return
	if phase_defs.is_empty():
		return

	_phase_transitioning = true
	_phase_token += 1  # Cancels in-flight pattern coroutine.
	_pattern_running = false
	_clear_enemy_bullets()

	# Spell Bonus (Touhou-like): capture only if not timed out and the player didn't bomb/get hit.
	if _is_spellcard_phase():
		var captured := (not timed_out) and spell_bonus_valid
		var awarded := int(spell_bonus_current) if captured else 0
		if captured and GameManager and GameManager.has_method("add_score"):
			GameManager.add_score(awarded, false)
		if GameManager and GameManager.has_signal("spellcard_result"):
			GameManager.spellcard_result.emit(phase_name, captured, timed_out, awarded)

	if phase_index + 1 >= phase_defs.size():
		die()
		return

	_start_phase(phase_index + 1)
	_phase_transitioning = false

func _run_phase_pattern(token: int, pattern: Callable) -> void:
	@warning_ignore("redundant_await")
	await pattern.call()

	if token != _phase_token:
		return

	_pattern_running = false
	var now_sec := Time.get_ticks_msec() / 1000.0
	var interval := phase_defs[phase_index].pattern_interval_sec
	_next_pattern_sec = now_sec + maxf(0.0, interval)

func _cleanup_boss_persistent_nodes() -> void:
	# Boss2 "prevent" barriers should not survive boss death.
	for node in _boss2_prevent_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_boss2_prevent_nodes.clear()
	_boss2_prevent_ready = false

	# Boss1 portal should not leak between stages.
	if _boss1_portal_ref and is_instance_valid(_boss1_portal_ref):
		_boss1_portal_ref.queue_free()
	_boss1_portal_ref = null

func _phase_basic_shot() -> void:
	# Lightweight aimed shots per boss; phase patterns are responsible for "spellcard" density.
	match boss_id:
		1:
			_touhou_aimed_spread("res://assets/sprites/bossbullut-1.png", 8.0, 3, 18.0)
		2:
			_touhou_aimed_spread("res://assets/sprites/bossbullut-3.png", 8.0, 3, 14.0)
		3:
			_touhou_aimed_spread("res://assets/sprites/bossbullut-6.png", 10.0, 3, 20.0)
		4:
			_touhou_aimed_spread("res://assets/sprites/bossbullut-10.png", 10.0, 3, 18.0)
		5:
			_touhou_aimed_spread("res://assets/sprites/bossbullut-11.png", 9.0, 3, 16.0)
		6:
			_touhou_aimed_spread("res://assets/sprites/bossbullut-6.png", 11.0, 5, 26.0)
		_:
			_touhou_aimed_spread("res://assets/sprites/bossbullut-1.png", 9.0, 3, 18.0)

func _touhou_aimed_spread(texture_path: String, speed_tick: float, bullet_count: int, spread_deg: float) -> void:
	var player := _get_player_safe()
	if not player:
		return

	var dir := (player.global_position - global_position)
	if dir.length() == 0.0:
		dir = Vector2.LEFT
	var base_angle := dir.angle()

	var count := maxi(1, bullet_count)
	var half := spread_deg * 0.5
	for i in range(count):
		var t := 0.0
		if count > 1:
			t = float(i) / float(count - 1)
		var angle := base_angle + deg_to_rad((-half) + spread_deg * t)
		var d := Vector2(cos(angle), sin(angle))
		_spawn_bullet_at(global_position, d, speed_tick * 60.0, EnemyBullet.BulletType.NORMAL, texture_path)

func _alloc_phase_hp(total_hp: int, weights: Array[float]) -> Array[int]:
	var out: Array[int] = []
	var total := maxi(1, total_hp)
	var sum_w := 0.0
	for w in weights:
		sum_w += maxf(0.0, float(w))
	if sum_w <= 0.0:
		sum_w = 1.0

	var remaining := total
	for i in range(weights.size()):
		var hp := int(round(float(total) * (maxf(0.0, float(weights[i])) / sum_w)))
		hp = maxi(1, hp)
		if i == weights.size() - 1:
			hp = maxi(1, remaining)
		out.append(hp)
		remaining -= hp
	return out

func _make_phase(
	kind: int,
	name: String,
	max_hp_value: int,
	time_limit_sec_value: float,
	basic_shot_interval_sec_value: float,
	pattern_interval_sec_value: float,
	start_delay_sec_value: float,
	pattern_callable: Callable
) -> BossPhaseDef:
	var p := BossPhaseDef.new()
	p.kind = kind
	p.name = name
	p.max_hp = maxi(1, max_hp_value)
	p.time_limit_sec = maxf(1.0, time_limit_sec_value)
	p.basic_shot_interval_sec = maxf(0.0, basic_shot_interval_sec_value)
	p.pattern_interval_sec = maxf(0.0, pattern_interval_sec_value)
	p.start_delay_sec = maxf(0.0, start_delay_sec_value)
	p.pattern = pattern_callable
	return p

func _make_phase_mix(
	kind: int,
	name: String,
	max_hp_value: int,
	time_limit_sec_value: float,
	basic_shot_interval_sec_value: float,
	pattern_interval_sec_value: float,
	start_delay_sec_value: float,
	pattern_callable: Callable,
	pattern_pool_value: Array[Callable],
	pool_mode: int = PatternPoolMode.CYCLE
) -> BossPhaseDef:
	var p := _make_phase(
		kind,
		name,
		max_hp_value,
		time_limit_sec_value,
		basic_shot_interval_sec_value,
		pattern_interval_sec_value,
		start_delay_sec_value,
		pattern_callable
	)
	p.pattern_pool = pattern_pool_value
	p.pattern_pool_mode = pool_mode
	p.pattern_pool_index = 0
	return p

func _build_touhou_phase_defs(total_hp: int) -> Array[BossPhaseDef]:
	match boss_id:
		1:
			return _build_boss1_phases(total_hp)
		2:
			return _build_boss2_phases(total_hp)
		3:
			return _build_boss3_phases(total_hp)
		4:
			return _build_boss4_phases(total_hp)
		5:
			return _build_boss5_phases(total_hp)
		6:
			return _build_boss6_phases(total_hp)
		_:
			return _build_boss1_phases(total_hp)

func _build_midboss_phase_defs(total_hp: int) -> Array[BossPhaseDef]:
	# Two-bar midboss: NONSPELL -> SPELL.
	var hps := _alloc_phase_hp(total_hp, [0.56, 0.44])

	var nonspell_pool: Array[Callable] = []
	var spell_pool: Array[Callable] = []

	match boss_id:
		1:
			nonspell_pool = [
				Callable(self, "_boss1_nonspell_step"),
				Callable(self, "_boss1_sand_shoot"),
				Callable(self, "_boss1_shoot_aside")
			]
			spell_pool = [
				Callable(self, "_boss1_star_shoot"),
				Callable(self, "_boss1_lightning_chain"),
				Callable(self, "_boss1_mirror_shoot")
			]
		2:
			nonspell_pool = [
				Callable(self, "_boss2_nonspell_step"),
				Callable(self, "_boss2_generate_love"),
				Callable(self, "_boss2_heart_trap"),
				Callable(self, "_boss2_heart_orbit_dive")
			]
			spell_pool = [
				Callable(self, "_boss2_use_attract"),
				Callable(self, "_boss2_heart_rain"),
				Callable(self, "_boss2_reverse_time")
			]
		3:
			nonspell_pool = [
				Callable(self, "_boss3_nonspell_step"),
				Callable(self, "_boss3_super_shoot"),
				Callable(self, "_boss3_time_lock_ring")
			]
			spell_pool = [
				Callable(self, "_boss3_time_stop"),
				Callable(self, "_boss3_time_bubble"),
				Callable(self, "_boss3_golden_storm")
			]
		4:
			nonspell_pool = [
				Callable(self, "_boss4_light_single"),
				Callable(self, "_boss4_drag_shoot"),
				Callable(self, "_boss4_side_shoot")
			]
			spell_pool = [
				Callable(self, "_boss4_screen_static"),
				Callable(self, "_boss4_light_shoot"),
				Callable(self, "_boss4_orbital_strike")
			]
		5:
			nonspell_pool = [
				Callable(self, "_boss5_throw_tnt"),
				Callable(self, "_boss5_jump_shoot"),
				Callable(self, "_boss5_chain_explosion")
			]
			spell_pool = [
				Callable(self, "_boss5_gravity_sink"),
				Callable(self, "_boss5_heal_mode"),
				Callable(self, "_boss5_mirror_tnt")
			]
		6:
			nonspell_pool = [
				Callable(self, "_boss6_phase1_fire_rain"),
				Callable(self, "shoot_double_spiral"),
				Callable(self, "shoot_tracking_burst")
			]
			spell_pool = [
				Callable(self, "_boss6_spell1_spiral_fire"),
				Callable(self, "shoot_pentagram"),
				Callable(self, "shoot_chaos_pattern")
			]
		_:
			nonspell_pool = [Callable(self, "_boss1_nonspell_step")]
			spell_pool = [Callable(self, "_boss1_star_shoot")]

	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Mid Nonspell", hps[0], 35.0, 0.65, 0.50, 0.9, nonspell_pool[0], nonspell_pool),
		_make_phase_mix(PhaseKind.SPELL, "Mid Spell", hps[1], 45.0, 0.0, 0.40, 1.1, spell_pool[0], spell_pool)
	]

func _build_boss1_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])

	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss1_nonspell_step"),
		Callable(self, "_boss1_sand_shoot"),
		Callable(self, "_boss1_shoot_aside"),
		Callable(self, "_pattern_aimed_burst").bind("res://assets/sprites/bossbullut-1.png", 8.5, 7, 30.0, 3, 0.25),
		Callable(self, "_pattern_ring_burst").bind("res://assets/sprites/bossbullut-2.png", 16, 6.5, 2, 0.4),
		Callable(self, "_pattern_spiral_stream").bind("res://assets/sprites/bossbullut-2.png", 6.0, 16, 12.0, 0.05, 2, 22.0, false)
	]

	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss1_star_shoot"),
		Callable(self, "_boss1_mirror_shoot"),
		Callable(self, "_boss1_lightning_chain"),
		Callable(self, "_pattern_curving_ring").bind("res://assets/sprites/bossbullut-2.png", 18, 6.2, 90.0, 2, 0.6),
		Callable(self, "_pattern_bouncy_star_stream").bind("res://assets/sprites/bossbullut-9.png", 4, 14.0, 0.6, 28.0, 240.0)
	]

	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss1_spiral_trap"),
		Callable(self, "_boss1_summon_teleport"),
		Callable(self, "_boss1_sand_shoot"),
		Callable(self, "_pattern_lane_wall").bind("res://assets/sprites/bossbullut-2.png", 7, 9.0, 2, 0.7),
		Callable(self, "_pattern_random_rain").bind("res://assets/sprites/bossbullut-1.png", 10, 7.0, 11.0, 2, 0.55, 90.0, 40.0)
	]

	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss1_black_hole"),
		Callable(self, "_boss1_lightning_chain"),
		Callable(self, "_boss1_mirror_shoot"),
		Callable(self, "_pattern_spiral_stream").bind("res://assets/sprites/bossbullut-9.png", 7.0, 18, 18.0, 0.045, 3, 42.0, true),
		Callable(self, "_pattern_ring_burst").bind("res://assets/sprites/bossbullut-3.png", 22, 5.0, 2, 0.8)
	]

	var final_pool: Array[Callable] = [
		Callable(self, "_boss1_black_hole"),
		Callable(self, "_boss1_spiral_trap"),
		Callable(self, "_boss1_lightning_chain"),
		Callable(self, "_pattern_curving_ring").bind("res://assets/sprites/bossbullut-3.png", 26, 6.8, 140.0, 2, 0.7),
		Callable(self, "_pattern_lane_wall").bind("res://assets/sprites/bossbullut-2.png", 9, 10.0, 2, 0.65),
		Callable(self, "_pattern_random_rain").bind("res://assets/sprites/bossbullut-1.png", 14, 7.0, 13.0, 2, 0.5, 110.0, 55.0)
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 1", hps[0], 38.0, 0.6, 0.45, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 1", hps[1], 55.0, 0.0, 0.35, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 2", hps[2], 38.0, 0.55, 0.45, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 2", hps[3], 60.0, 0.0, 0.35, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Final Spell", hps[4], 70.0, 0.45, 0.30, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _boss1_nonspell_step() -> void:
	# Simple Touhou-like opening: aimed spread + occasional ring.
	_touhou_aimed_spread("res://assets/sprites/bossbullut-1.png", 8.0, 5, 26.0)
	if randf() < 0.35:
		_touhou_ring("res://assets/sprites/bossbullut-2.png", 14, 6.5)

func _touhou_ring(texture_path: String, bullet_count: int, speed_tick: float) -> void:
	var count := maxi(6, bullet_count)
	for i in range(count):
		var angle := (TAU / float(count)) * float(i)
		var dir := Vector2(cos(angle), sin(angle))
		_spawn_bullet_at(global_position, dir, speed_tick * 60.0, EnemyBullet.BulletType.NORMAL, texture_path)

func _pattern_aimed_burst(
	texture_path: String,
	speed_tick: float,
	bullet_count: int,
	spread_deg: float,
	waves: int,
	wave_delay_sec: float
) -> void:
	var token := _phase_token
	var total := maxi(1, waves)
	var delay := maxf(0.03, wave_delay_sec)
	for _wave in range(total):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout
		_touhou_aimed_spread(texture_path, speed_tick, bullet_count, spread_deg)
		await get_tree().create_timer(delay).timeout

func _pattern_ring_burst(
	texture_path: String,
	bullet_count: int,
	speed_tick: float,
	waves: int,
	wave_delay_sec: float
) -> void:
	var token := _phase_token
	var total := maxi(1, waves)
	var delay := maxf(0.03, wave_delay_sec)
	for _wave in range(total):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout
		_touhou_ring(texture_path, bullet_count, speed_tick)
		await get_tree().create_timer(delay).timeout

func _pattern_spiral_stream(
	texture_path: String,
	speed_tick: float,
	steps: int,
	step_deg: float,
	step_delay_sec: float,
	bullets_per_step: int,
	spread_deg: float,
	aim_at_player: bool
) -> void:
	var token := _phase_token
	var step_total := maxi(1, steps)
	var delay := maxf(0.01, step_delay_sec)
	var per := maxi(1, bullets_per_step)
	var half := spread_deg * 0.5

	var base_angle := randf_range(0.0, TAU)
	if aim_at_player:
		var player := _get_player_safe()
		if not player:
			return
		var to_player := player.global_position - global_position
		if to_player.length() == 0.0:
			to_player = Vector2.LEFT
		base_angle = to_player.angle()

	var step_rad := deg_to_rad(step_deg)
	for i in range(step_total):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		for j in range(per):
			var t := 0.0
			if per > 1:
				t = float(j) / float(per - 1)
			var angle := base_angle + step_rad * float(i) + deg_to_rad((-half) + spread_deg * t)
			var dir := Vector2(cos(angle), sin(angle))
			_spawn_bullet_at(global_position, dir, speed_tick * 60.0, EnemyBullet.BulletType.NORMAL, texture_path)

		await get_tree().create_timer(delay).timeout

func _pattern_curving_ring(
	texture_path: String,
	bullet_count: int,
	speed_tick: float,
	turn_rate_deg_per_sec: float,
	waves: int,
	wave_delay_sec: float
) -> void:
	var token := _phase_token
	var total := maxi(1, waves)
	var delay := maxf(0.03, wave_delay_sec)
	var count := maxi(6, bullet_count)
	var turn_rate := deg_to_rad(turn_rate_deg_per_sec)
	for _wave in range(total):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		for i in range(count):
			var angle := (TAU / float(count)) * float(i)
			var dir := Vector2(cos(angle), sin(angle))
			var bullet := _spawn_bullet_at(global_position, dir, speed_tick * 60.0, EnemyBullet.BulletType.NORMAL, texture_path)
			if bullet:
				var sign := -1.0 if (i % 2) == 0 else 1.0
				bullet.turn_rate = turn_rate * sign

		await get_tree().create_timer(delay).timeout

func _pattern_lane_wall(
	texture_path: String,
	lanes: int,
	speed_tick: float,
	waves: int,
	wave_delay_sec: float
) -> void:
	var token := _phase_token
	var total := maxi(1, waves)
	var delay := maxf(0.03, wave_delay_sec)

	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var lane_total := maxi(3, lanes)
	var top := 80.0
	var bottom := maxf(top + 10.0, playfield_bottom - 120.0)
	var span := maxf(1.0, bottom - top)

	for wave in range(total):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var phase_offset := (span / float(lane_total)) * float(wave)
		for i in range(lane_total):
			var t := float(i) / float(maxi(1, lane_total - 1))
			var y := top + span * t
			y = wrapf(y + phase_offset, top, bottom)
			var spawn_pos := Vector2(viewport_size.x + 40.0, y)
			_spawn_bullet_at(spawn_pos, Vector2.LEFT, speed_tick * 60.0, EnemyBullet.BulletType.NORMAL, texture_path)

		await get_tree().create_timer(delay).timeout

func _pattern_random_rain(
	texture_path: String,
	bullets_per_wave: int,
	speed_tick_min: float,
	speed_tick_max: float,
	waves: int,
	wave_delay_sec: float,
	base_angle_deg: float,
	angle_spread_deg: float
) -> void:
	var token := _phase_token
	var total := maxi(1, waves)
	var delay := maxf(0.03, wave_delay_sec)

	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var count := maxi(1, bullets_per_wave)
	var s_min := minf(speed_tick_min, speed_tick_max)
	var s_max := maxf(speed_tick_min, speed_tick_max)
	var half := angle_spread_deg * 0.5

	for _wave in range(total):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		for _i in range(count):
			var x := randf_range(0.0, viewport_size.x)
			var y := randf_range(-60.0, maxf(-60.0, playfield_bottom * 0.25))
			var angle := deg_to_rad(base_angle_deg + randf_range(-half, half))
			var dir := Vector2.RIGHT.rotated(angle)
			var sp := randf_range(s_min, s_max)
			_spawn_bullet_at(Vector2(x, y), dir, sp * 60.0, EnemyBullet.BulletType.NORMAL, texture_path)

		await get_tree().create_timer(delay).timeout

func _pattern_bouncy_star_stream(
	texture_path: String,
	shots: int,
	speed_tick: float,
	delay_sec: float,
	collision_radius: float,
	spin_deg_per_sec: float
) -> void:
	var token := _phase_token
	var total := maxi(1, shots)
	var delay := maxf(0.03, delay_sec)
	var spin := deg_to_rad(spin_deg_per_sec)
	var radius := maxf(2.0, collision_radius)

	for _i in range(total):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return
		var d := (player.global_position - global_position).normalized()
		if d.length() == 0.0:
			d = Vector2.LEFT

		var b := _spawn_bullet_at(global_position, d, speed_tick * 60.0, EnemyBullet.BulletType.NORMAL, texture_path)
		if b:
			b.can_return = true
			b.can_delete = false
			b.rotate_with_direction = false
			b.spin_speed = spin

			var cs := b.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if cs:
				var circle := CircleShape2D.new()
				circle.radius = radius
				cs.shape = circle

		await get_tree().create_timer(delay).timeout

func _spawn_orbit_dash_ring(
	center: Vector2,
	target: Vector2,
	texture_path: String,
	bullet_count: int,
	orbit_radius: float,
	orbit_time_sec: float,
	orbit_speed_deg_per_sec: float,
	dash_speed_tick: float
) -> void:
	var count := maxi(4, bullet_count)
	var base_offset := randf_range(0.0, TAU)
	var omega := deg_to_rad(orbit_speed_deg_per_sec)
	var scale := clampf(boss_bullet_speed_scale, 0.05, 5.0)
	var dash_speed := dash_speed_tick * 60.0 * scale

	for i in range(count):
		var angle := base_offset + (TAU / float(count)) * float(i)
		var pos := center + Vector2(cos(angle), sin(angle)) * orbit_radius
		var bullet := _spawn_bullet_at(pos, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, texture_path)
		if not bullet:
			continue

		bullet.direction = Vector2.ZERO
		bullet.rotate_with_direction = false
		bullet.orbit_center = center
		bullet.orbit_radius = orbit_radius
		bullet.orbit_angle = angle
		bullet.orbit_angular_speed = omega
		bullet.orbit_time_left = maxf(0.0, orbit_time_sec)
		bullet.dash_after_orbit = true
		bullet.dash_target = target
		bullet.dash_speed = dash_speed

func _boss2_heart_orbit_dive() -> void:
	# Unique Boss2 pattern: hearts orbit briefly, then all converge on a single point.
	var token := _phase_token
	for wave in range(3):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return

		var viewport_size := get_viewport_rect().size
		var playfield_bottom := viewport_size.y
		if GameManager and GameManager.has_method("get_playfield_bottom_y"):
			playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

		# Pick a "kill zone" near the player but clamp into the playfield.
		var target := player.global_position + Vector2(randf_range(-60.0, 60.0), randf_range(-80.0, 80.0))
		target.x = clampf(target.x, 80.0, viewport_size.x - 80.0)
		target.y = clampf(target.y, 80.0, playfield_bottom - 80.0)

		_spawn_orbit_dash_ring(
			global_position,
			target,
			"res://assets/sprites/bossbullut-4.png",
			16 + wave * 2,
			110.0 + float(wave) * 20.0,
			1.1,
			220.0 if (wave % 2) == 0 else -220.0,
			10.0 + float(wave) * 0.6
		)

		await get_tree().create_timer(0.55).timeout

func _boss3_time_lock_ring() -> void:
	# Unique Boss3 pattern: a delayed "time lock" ring that collapses onto the player.
	var token := _phase_token
	var player := _get_player_safe()
	if not player:
		return

	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var center := player.global_position
	center.x = clampf(center.x, 80.0, viewport_size.x - 80.0)
	center.y = clampf(center.y, 80.0, playfield_bottom - 80.0)

	var rings: Array[float] = [110.0, 165.0, 220.0]
	for ring_radius_value in rings:
		var ring_radius := float(ring_radius_value)
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var count := 18
		var base_angle := randf_range(0.0, TAU)
		for i in range(count):
			var angle := base_angle + (TAU / float(count)) * float(i)
			var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * ring_radius
			var dir: Vector2 = (center - pos).normalized()
			var bullet := _spawn_bullet_at(pos, dir, 6.2 * 60.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-5.png")
			if bullet:
				bullet.start_delay = 0.75
				bullet.acceleration = 180.0
				bullet.rotate_with_direction = false

		await get_tree().create_timer(0.22).timeout

func _build_boss2_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss2_nonspell_step"),
		Callable(self, "_boss2_generate_love"),
		Callable(self, "_boss2_heart_trap"),
		Callable(self, "_pattern_aimed_burst").bind("res://assets/sprites/bossbullut-3.png", 8.0, 7, 26.0, 3, 0.22),
		Callable(self, "_pattern_ring_burst").bind("res://assets/sprites/bossbullut-4.png", 18, 5.6, 2, 0.55),
		Callable(self, "_boss2_heart_orbit_dive")
	]

	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss2_heart_rain"),
		Callable(self, "_boss2_use_attract"),
		Callable(self, "_boss2_heart_trap"),
		Callable(self, "_boss2_generate_love"),
		Callable(self, "_boss2_heart_orbit_dive"),
		Callable(self, "_boss2_split_bomb")
	]

	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss2_generate_love"),
		Callable(self, "_boss2_use_attract"),
		Callable(self, "_boss2_made_in_heaven"),
		Callable(self, "_pattern_aimed_burst").bind("res://assets/sprites/bossbullut-3.png", 9.0, 5, 18.0, 5, 0.16),
		Callable(self, "_boss2_heart_orbit_dive")
	]

	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss2_reverse_time"),
		Callable(self, "_boss2_use_attract"),
		Callable(self, "_boss2_heart_rain"),
		Callable(self, "_boss2_generate_love"),
		Callable(self, "_boss2_heart_orbit_dive"),
		Callable(self, "_boss2_heart_trap")
	]

	var final_pool: Array[Callable] = [
		Callable(self, "_boss2_split_bomb"),
		Callable(self, "_boss2_made_in_heaven"),
		Callable(self, "_boss2_reverse_time"),
		Callable(self, "_boss2_use_attract"),
		Callable(self, "_boss2_heart_rain"),
		Callable(self, "_boss2_heart_orbit_dive"),
		Callable(self, "_boss2_heart_trap")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 1", hps[0], 45.0, 0.65, 0.45, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 1", hps[1], 60.0, 0.0, 0.34, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 2", hps[2], 45.0, 0.6, 0.45, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 2", hps[3], 62.0, 0.0, 0.34, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Final Spell", hps[4], 78.0, 0.5, 0.28, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _boss2_nonspell_step() -> void:
	_touhou_aimed_spread("res://assets/sprites/bossbullut-3.png", 7.5, 5, 22.0)
	if randf() < 0.4:
		_touhou_ring("res://assets/sprites/bossbullut-4.png", 16, 5.0)

func _build_boss3_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss3_nonspell_step"),
		Callable(self, "_boss3_super_shoot"),
		Callable(self, "_boss3_time_lock_ring"),
		Callable(self, "_boss3_golden_storm"),
		Callable(self, "_boss3_coin_barrage")
	]

	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss3_golden_storm"),
		Callable(self, "_boss3_set_gold"),
		Callable(self, "_boss3_cut_body"),
		Callable(self, "_boss3_time_lock_ring"),
		Callable(self, "_boss3_time_bubble")
	]

	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss3_super_shoot"),
		Callable(self, "_boss3_coin_barrage"),
		Callable(self, "_boss3_time_lock_ring"),
		Callable(self, "_boss3_set_gold"),
		Callable(self, "_boss3_cut_body"),
		Callable(self, "_boss3_golden_storm")
	]

	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss3_time_bubble"),
		Callable(self, "_boss3_time_stop"),
		Callable(self, "_boss3_time_lock_ring"),
		Callable(self, "_boss3_golden_storm"),
		Callable(self, "_boss3_coin_barrage")
	]

	var final_pool: Array[Callable] = [
		Callable(self, "_boss3_coin_barrage"),
		Callable(self, "_boss3_time_bubble"),
		Callable(self, "_boss3_cut_body"),
		Callable(self, "_boss3_time_stop"),
		Callable(self, "_boss3_time_lock_ring"),
		Callable(self, "_boss3_golden_storm")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 1", hps[0], 45.0, 0.6, 0.45, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 1", hps[1], 62.0, 0.0, 0.34, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 2", hps[2], 45.0, 0.55, 0.45, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 2", hps[3], 65.0, 0.0, 0.34, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Final Spell", hps[4], 82.0, 0.5, 0.28, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _boss3_nonspell_step() -> void:
	_touhou_aimed_spread("res://assets/sprites/bossbullut-6.png", 9.5, 5, 24.0)
	if randf() < 0.25:
		_touhou_ring("res://assets/sprites/bossbullut-5.png", 18, 6.5)

func _build_boss4_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss4_light_shoot"),
		Callable(self, "_boss4_light_single"),
		Callable(self, "_boss4_drag_shoot"),
		Callable(self, "_boss4_side_shoot"),
		Callable(self, "_boss4_summon_ufo")
	]

	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss4_drag_shoot"),
		Callable(self, "_boss4_summon_ufo"),
		Callable(self, "_boss4_screen_static"),
		Callable(self, "_boss4_orbital_strike"),
		Callable(self, "_boss4_pixel_storm")
	]

	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss4_side_shoot"),
		Callable(self, "_boss4_light_shoot"),
		Callable(self, "_boss4_summon_ufo"),
		Callable(self, "_boss4_drag_shoot"),
		Callable(self, "_boss4_light_single")
	]

	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss4_pixel_storm"),
		Callable(self, "_boss4_screen_static"),
		Callable(self, "_boss4_orbital_strike"),
		Callable(self, "_boss4_drag_shoot"),
		Callable(self, "_boss4_side_shoot")
	]

	var final_pool: Array[Callable] = [
		Callable(self, "_boss4_orbital_strike"),
		Callable(self, "_boss4_pixel_storm"),
		Callable(self, "_boss4_summon_ufo"),
		Callable(self, "_boss4_screen_static"),
		Callable(self, "_boss4_drag_shoot"),
		Callable(self, "_boss4_side_shoot"),
		Callable(self, "_boss4_light_shoot")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 1", hps[0], 45.0, 0.6, 0.45, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 1", hps[1], 62.0, 0.0, 0.34, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 2", hps[2], 45.0, 0.55, 0.45, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 2", hps[3], 65.0, 0.0, 0.34, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Final Spell", hps[4], 85.0, 0.5, 0.28, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _build_boss5_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss5_throw_tnt"),
		Callable(self, "_boss5_jump_shoot"),
		Callable(self, "_boss5_chain_explosion"),
		Callable(self, "_boss5_gravity_sink"),
		Callable(self, "_boss5_mirror_tnt")
	]

	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss5_gravity_sink"),
		Callable(self, "_boss5_chain_explosion"),
		Callable(self, "_boss5_heal_mode"),
		Callable(self, "_boss5_mirror_tnt"),
		Callable(self, "_boss5_throw_tnt")
	]

	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss5_jump_shoot"),
		Callable(self, "_boss5_throw_tnt"),
		Callable(self, "_boss5_chain_explosion"),
		Callable(self, "_boss5_gravity_sink"),
		Callable(self, "_boss5_heal_mode")
	]

	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss5_chain_explosion"),
		Callable(self, "_boss5_heal_mode"),
		Callable(self, "_boss5_gravity_sink"),
		Callable(self, "_boss5_mirror_tnt"),
		Callable(self, "_boss5_throw_tnt")
	]

	var final_pool: Array[Callable] = [
		Callable(self, "_boss5_mirror_tnt"),
		Callable(self, "_boss5_chain_explosion"),
		Callable(self, "_boss5_gravity_sink"),
		Callable(self, "_boss5_heal_mode"),
		Callable(self, "_boss5_throw_tnt"),
		Callable(self, "_boss5_jump_shoot"),
		Callable(self, "_boss5_gravity_sink")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 1", hps[0], 45.0, 0.6, 0.45, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 1", hps[1], 62.0, 0.0, 0.34, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 2", hps[2], 45.0, 0.55, 0.45, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 2", hps[3], 68.0, 0.0, 0.34, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Final Spell", hps[4], 92.0, 0.5, 0.28, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _build_boss6_phases(total_hp: int) -> Array[BossPhaseDef]:
	# Boss6 in the original pygame project is a multi-phase "final boss".
	# Here we keep Touhou-like NONSPELL/SPELL alternation with 5 bars.
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss6_phase1_fire_rain"),
		Callable(self, "shoot_triple_spiral"),
		Callable(self, "shoot_double_spiral"),
		Callable(self, "_pattern_aimed_burst").bind("res://assets/sprites/bossbullut-6.png", 12.0, 7, 28.0, 3, 0.18),
		Callable(self, "_pattern_ring_burst").bind("res://assets/sprites/bossbullut-6.png", 26, 7.5, 2, 0.55),
		Callable(self, "_pattern_spiral_stream").bind("res://assets/sprites/bossbullut-6.png", 8.5, 28, 18.0, 0.035, 2, 32.0, false),
		Callable(self, "_pattern_lane_wall").bind("res://assets/sprites/bossbullut-6.png", 10, 12.0, 2, 0.6),
		Callable(self, "_pattern_random_rain").bind("res://assets/sprites/bossbullut-6.png", 16, 7.0, 16.0, 2, 0.4, 100.0, 70.0),
		Callable(self, "_pattern_curving_ring").bind("res://assets/sprites/bossbullut-6.png", 30, 8.0, 240.0, 2, 0.55),
		Callable(self, "_pattern_bouncy_star_stream").bind("res://assets/sprites/bossbullut-9.png", 5, 16.0, 0.5, 30.0, 280.0)
	]

	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss6_spell1_spiral_fire"),
		Callable(self, "shoot_pentagram"),
		Callable(self, "shoot_chaos_pattern"),
		Callable(self, "_pattern_spiral_stream").bind("res://assets/sprites/fire1.png", 9.0, 32, 22.0, 0.03, 2, 44.0, true),
		Callable(self, "_pattern_curving_ring").bind("res://assets/sprites/bossbullut-6.png", 34, 8.5, 300.0, 2, 0.55),
		Callable(self, "_pattern_lane_wall").bind("res://assets/sprites/bossbullut-6.png", 12, 12.5, 2, 0.55),
		Callable(self, "_pattern_random_rain").bind("res://assets/sprites/fire1.png", 18, 8.0, 18.0, 2, 0.38, 105.0, 75.0),
		Callable(self, "_pattern_ring_burst").bind("res://assets/sprites/bossbullut-3.png", 36, 6.8, 2, 0.75),
		Callable(self, "_pattern_aimed_burst").bind("res://assets/sprites/bossbullut-6.png", 13.0, 5, 18.0, 5, 0.14),
		Callable(self, "_pattern_bouncy_star_stream").bind("res://assets/sprites/bossbullut-9.png", 6, 17.0, 0.45, 34.0, 320.0)
	]

	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss6_phase3_cone_and_teleport"),
		Callable(self, "shoot_dense_tracking"),
		Callable(self, "shoot_tracking_burst"),
		Callable(self, "_pattern_aimed_burst").bind("res://assets/sprites/bossbullut-5.png", 13.0, 7, 22.0, 4, 0.16),
		Callable(self, "_pattern_spiral_stream").bind("res://assets/sprites/bossbullut-5.png", 8.5, 30, 22.0, 0.03, 2, 34.0, true),
		Callable(self, "_pattern_ring_burst").bind("res://assets/sprites/bossbullut-5.png", 32, 7.2, 2, 0.6),
		Callable(self, "_pattern_curving_ring").bind("res://assets/sprites/bossbullut-5.png", 30, 8.2, 260.0, 2, 0.55),
		Callable(self, "_pattern_lane_wall").bind("res://assets/sprites/bossbullut-5.png", 12, 13.0, 2, 0.55),
		Callable(self, "_pattern_random_rain").bind("res://assets/sprites/bossbullut-5.png", 18, 8.0, 18.0, 2, 0.38, 100.0, 80.0),
		Callable(self, "_pattern_bouncy_star_stream").bind("res://assets/sprites/bossbullut-9.png", 7, 18.0, 0.4, 32.0, 360.0)
	]

	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss6_spell2_cross_laser"),
		Callable(self, "shoot_ultimate_pattern"),
		Callable(self, "shoot_chaos_pattern"),
		Callable(self, "_pattern_spiral_stream").bind("res://assets/sprites/bossbullut-3.png", 9.0, 36, 24.0, 0.03, 3, 52.0, true),
		Callable(self, "_pattern_curving_ring").bind("res://assets/sprites/bossbullut-3.png", 38, 8.8, 360.0, 2, 0.55),
		Callable(self, "_pattern_lane_wall").bind("res://assets/sprites/bossbullut-3.png", 14, 13.5, 2, 0.55),
		Callable(self, "_pattern_random_rain").bind("res://assets/sprites/bossbullut-3.png", 22, 8.5, 20.0, 2, 0.36, 100.0, 85.0),
		Callable(self, "_pattern_ring_burst").bind("res://assets/sprites/bossbullut-3.png", 40, 7.5, 2, 0.6),
		Callable(self, "_pattern_aimed_burst").bind("res://assets/sprites/bossbullut-3.png", 14.0, 5, 16.0, 6, 0.12),
		Callable(self, "_pattern_bouncy_star_stream").bind("res://assets/sprites/bossbullut-9.png", 8, 18.5, 0.35, 36.0, 420.0)
	]

	var final_pool: Array[Callable] = [
		Callable(self, "_boss6_final_inferno"),
		Callable(self, "shoot_ultimate_pattern"),
		Callable(self, "shoot_triple_spiral"),
		Callable(self, "shoot_dense_tracking"),
		Callable(self, "_boss6_phase3_cone_and_teleport"),
		Callable(self, "_pattern_curving_ring").bind("res://assets/sprites/bossbullut-6.png", 46, 9.5, 520.0, 2, 0.5),
		Callable(self, "_pattern_spiral_stream").bind("res://assets/sprites/fire1.png", 10.0, 44, 28.0, 0.025, 3, 66.0, true),
		Callable(self, "_pattern_lane_wall").bind("res://assets/sprites/bossbullut-6.png", 16, 15.0, 2, 0.5),
		Callable(self, "_pattern_random_rain").bind("res://assets/sprites/fire1.png", 30, 9.0, 24.0, 2, 0.32, 105.0, 100.0),
		Callable(self, "_pattern_ring_burst").bind("res://assets/sprites/bossbullut-3.png", 52, 8.0, 2, 0.55),
		Callable(self, "_pattern_aimed_burst").bind("res://assets/sprites/bossbullut-6.png", 15.0, 5, 14.0, 8, 0.10),
		Callable(self, "_pattern_bouncy_star_stream").bind("res://assets/sprites/bossbullut-9.png", 12, 20.0, 0.28, 42.0, 600.0)
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 1", hps[0], 55.0, 0.5, 0.34, 1.0, nonspell_1_pool[0], nonspell_1_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 1", hps[1], 72.0, 0.0, 0.26, 1.2, spell_1_pool[0], spell_1_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.NONSPELL, "Nonspell 2", hps[2], 58.0, 0.45, 0.32, 1.0, nonspell_2_pool[0], nonspell_2_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.SPELL, "Spell Card 2", hps[3], 78.0, 0.0, 0.24, 1.2, spell_2_pool[0], spell_2_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.FINAL, "Final Spell", hps[4], 110.0, 0.4, 0.20, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _boss6_phase1_fire_rain() -> void:
	# Fire rain + occasional horizontal laser (warning -> beam).
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	for i in range(18):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		var angle_deg := randf_range(-60.0, 60.0)
		var dir := Vector2.LEFT.rotated(deg_to_rad(angle_deg))
		_spawn_fire_bullet(global_position, dir, randf_range(8.0, 15.0), "res://assets/sprites/fire1.png", 2.0)

		if i == 6 or i == 13:
			await _boss6_horizontal_laser(playfield_bottom)

		await get_tree().create_timer(0.2).timeout

func _boss6_spell1_spiral_fire() -> void:
	# Three-way spiral fire (Python BossSkillSixth.phase1_spiral_attack vibe).
	for rotation in range(0, 720, 15):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		for offset in [0, 120, 240]:
			var angle_deg := float(rotation + offset)
			var angle := deg_to_rad(angle_deg)
			var dir := Vector2(cos(angle), sin(angle))
			_spawn_fire_bullet(global_position, dir, 10.0, "res://assets/sprites/fire1.png", 2.0)

		await get_tree().create_timer(0.1).timeout

func _boss6_phase3_cone_and_teleport() -> void:
	# Teleport + repeated wide cones.
	_boss6_teleport()
	for _burst in range(10):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		_touhou_aimed_spread_scaled("res://assets/sprites/fire2.png", 10.0, 13, 70.0, 2.2)
		await get_tree().create_timer(0.28).timeout

func _boss6_spell2_cross_laser() -> void:
	# Cross laser (warning -> horizontal + vertical beams).
	var token := _phase_token
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var warn_nodes: Array[EnemyBullet] = []
	var warn_tex := "res://assets/sprites/error.png"
	var positions := [
		Vector2(global_position.x, 60.0),
		Vector2(global_position.x, playfield_bottom - 60.0),
		Vector2(60.0, global_position.y),
		Vector2(viewport_size.x - 60.0, global_position.y)
	]
	for p in positions:
		var w := _spawn_bullet_at(p, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, warn_tex)
		if w:
			w.ban_remove = true
			w.can_delete = false
			w.rotate_with_direction = false
			w.damage = 0
			w.collision_mask = 0
			w.collision_layer = 0
			w.direction = Vector2.ZERO
			w.speed = 0.0
			warn_nodes.append(w)

	await get_tree().create_timer(1.0).timeout
	while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
		if _pattern_should_abort(token):
			return
		await get_tree().create_timer(0.1).timeout
	if _pattern_should_abort(token):
		return

	for w in warn_nodes:
		if is_instance_valid(w):
			w.queue_free()

	# Horizontal beam at boss Y.
	var beam_h := _spawn_bullet_at(Vector2(viewport_size.x * 0.5, global_position.y), Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/light.png")
	if beam_h:
		_configure_laser_beam(beam_h, Vector2(viewport_size.x, 30.0), Vector2(viewport_size.x / 640.0, 1.0), 0.0, 14)
		_boss5_fade_and_free(beam_h, 1.5)

	# Vertical beam at boss X.
	var beam_v := _spawn_bullet_at(Vector2(global_position.x, playfield_bottom * 0.5), Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/light.png")
	if beam_v:
		# Collision is vertical; rotate only the sprite for visuals.
		_configure_laser_beam(beam_v, Vector2(30.0, playfield_bottom), Vector2(playfield_bottom / 640.0, 1.0), PI / 2.0, 14)
		_boss5_fade_and_free(beam_v, 1.5)

	# Follow-up: tracking burst.
	for _i in range(6):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout
		var dir := Vector2.LEFT
		var player := _get_player_safe()
		if player:
			dir = (player.global_position - global_position)
		var b := _spawn_bullet_at(global_position, dir, sqrt(12.0) * 60.0, EnemyBullet.BulletType.TRACKING, "res://assets/sprites/bossbullut-6.png")
		if b:
			b.tracking_enabled = true
		await get_tree().create_timer(0.18).timeout
		if _pattern_should_abort(token):
			return

func _boss6_final_inferno() -> void:
	# Final: pentagram + fire rings + tracking.
	_touhou_ring("res://assets/sprites/fire2.png", 28, 7.0)
	await get_tree().create_timer(0.2).timeout

	for rotation in range(0, 360, 12):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		for offset in [0, 72, 144, 216, 288]:
			var angle_deg := float(rotation + offset)
			var angle := deg_to_rad(angle_deg)
			var dir := Vector2(cos(angle), sin(angle))
			_spawn_fire_bullet(global_position, dir, 11.0, "res://assets/sprites/fire2.png", 2.4)

		if rotation % 60 == 0:
			_touhou_aimed_spread_scaled("res://assets/sprites/bossbullut-6.png", 12.0, 7, 26.0, 1.0)

		await get_tree().create_timer(0.08).timeout

func _boss6_teleport() -> void:
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	global_position = Vector2(
		randf_range(viewport_size.x * 0.60, viewport_size.x - 160.0),
		randf_range(120.0, maxf(120.0, playfield_bottom * 0.55))
	)
	skill_invulnerable_until = (Time.get_ticks_msec() / 1000.0) + 0.35

func _boss6_horizontal_laser(playfield_bottom: float) -> void:
	var viewport_size := get_viewport_rect().size
	var y := randf_range(120.0, maxf(120.0, playfield_bottom - 160.0))

	var warning := _spawn_bullet_at(Vector2(100.0, y), Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/attention.png")
	if warning:
		warning.ban_remove = true
		warning.can_delete = false
		warning.rotate_with_direction = false
		warning.damage = 0
		warning.collision_mask = 0
		warning.collision_layer = 0
		warning.direction = Vector2.ZERO
		warning.speed = 0.0
		var ws := warning.get_node_or_null("Sprite2D") as Sprite2D
		if ws:
			ws.scale = Vector2.ONE * 0.45

	await get_tree().create_timer(0.8).timeout
	while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
		await get_tree().create_timer(0.1).timeout

	if is_instance_valid(warning):
		warning.queue_free()

	var beam := _spawn_bullet_at(Vector2(viewport_size.x * 0.5, y), Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/light.png")
	if beam:
		_configure_laser_beam(beam, Vector2(viewport_size.x, 30.0), Vector2(viewport_size.x / 640.0, 1.0), 0.0, 14)
		_boss5_fade_and_free(beam, 1.2)

func _configure_laser_beam(beam: EnemyBullet, rect_size: Vector2, sprite_scale: Vector2, sprite_rotation: float, beam_damage: int) -> void:
	beam.ban_remove = true
	beam.can_delete = false
	beam.rotate_with_direction = false
	beam.direction = Vector2.ZERO
	beam.speed = 0.0
	beam.damage = beam_damage

	var cs := beam.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs:
		var rect := RectangleShape2D.new()
		rect.size = rect_size
		cs.shape = rect

	var spr := beam.get_node_or_null("Sprite2D") as Sprite2D
	if spr:
		spr.scale = sprite_scale
		spr.rotation = sprite_rotation

func _spawn_fire_bullet(spawn_pos: Vector2, dir: Vector2, speed_tick: float, texture_path: String, scale: float) -> void:
	var b := _spawn_bullet_at(spawn_pos, dir, speed_tick * 60.0, EnemyBullet.BulletType.NORMAL, texture_path)
	if not b:
		return
	var spr := b.get_node_or_null("Sprite2D") as Sprite2D
	if spr:
		spr.scale = Vector2.ONE * scale
	var cs := b.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs:
		var circle := CircleShape2D.new()
		circle.radius = 6.0
		cs.shape = circle

func _touhou_aimed_spread_scaled(texture_path: String, speed_tick: float, bullet_count: int, spread_deg: float, sprite_scale: float) -> void:
	var player := _get_player_safe()
	if not player:
		return

	var dir := (player.global_position - global_position)
	if dir.length() == 0.0:
		dir = Vector2.LEFT
	var base_angle := dir.angle()

	var count := maxi(1, bullet_count)
	var half := spread_deg * 0.5
	for i in range(count):
		var t := 0.0
		if count > 1:
			t = float(i) / float(count - 1)
		var angle := base_angle + deg_to_rad((-half) + spread_deg * t)
		var d := Vector2(cos(angle), sin(angle))
		var b := _spawn_bullet_at(global_position, d, speed_tick * 60.0, EnemyBullet.BulletType.NORMAL, texture_path)
		if b:
			var spr := b.get_node_or_null("Sprite2D") as Sprite2D
			if spr:
				spr.scale = Vector2.ONE * sprite_scale

func _spawn_boss_rewards() -> void:
	# Python parity (Event.bossDeath): drop generateSupply(1) 1-5 times.
	# Boss uses 80x80 sprites => Python top-left is center - (40,40).
	var boss_pos: Vector2 = global_position - Vector2(40.0, 40.0)
	for _i in range(randi_range(1, 5)):
		_generate_supply(1.0, boss_pos)

func update_boss6_phase() -> void:
	var health_percent: float = float(health) / float(max_health)
	if health_percent > 0.8:
		current_phase = 1
	elif health_percent > 0.6:
		current_phase = 2
	elif health_percent > 0.4:
		current_phase = 3
	elif health_percent > 0.2:
		current_phase = 4
	else:
		current_phase = 5

func boss_movement(delta: float) -> void:
	movement_timer += delta

	var now_sec := Time.get_ticks_msec() / 1000.0
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	# Keep bosses on the right side (horizontal shooter playfield).
	var x_min := viewport_size.x * 0.55
	var x_max := viewport_size.x - 90.0
	var y_min := 70.0
	var y_max := playfield_bottom - 80.0

	# Movement personality per boss (Touhou-like: roam between points, with some teleports).
	var change_min := 1.2
	var change_max := 2.2
	var move_factor := 1.0
	var teleport_chance := 0.0
	var teleport_cd_min := 6.0
	var teleport_cd_max := 10.0

	match boss_id:
		1:
			change_min = 1.3
			change_max = 2.3
			move_factor = 1.0
			teleport_chance = 0.0
		2:
			change_min = 1.0
			change_max = 1.9
			move_factor = 1.15
			teleport_chance = 0.0
		3:
			change_min = 1.0
			change_max = 1.7
			move_factor = 1.2
			teleport_chance = 0.25
		4:
			change_min = 0.9
			change_max = 1.5
			move_factor = 1.35
			teleport_chance = 0.15
		5:
			change_min = 1.2
			change_max = 2.1
			move_factor = 1.05
			teleport_chance = 0.10
		6:
			change_min = 0.75
			change_max = 1.35
			move_factor = 1.55
			teleport_chance = 0.55
			teleport_cd_min = 4.0
			teleport_cd_max = 7.0

	# Phase influence: spells tend to be steadier; finals are more violent.
	if phase_kind == PhaseKind.SPELL:
		change_min *= 1.2
		change_max *= 1.3
		teleport_chance *= 0.7
	elif phase_kind == PhaseKind.FINAL:
		change_min *= 0.9
		change_max *= 0.9
		teleport_chance = minf(1.0, teleport_chance + 0.15)

	# (Re)seed movement when phases change.
	if _move_token_seen != _phase_token or _move_target == Vector2.ZERO:
		_move_token_seen = _phase_token
		_move_target = Vector2(randf_range(x_min, x_max), randf_range(y_min, y_max))
		_move_next_change_sec = now_sec + randf_range(change_min, change_max)
		_move_teleport_next_sec = now_sec + randf_range(teleport_cd_min, teleport_cd_max)

	# Periodically pick a new destination (and sometimes teleport).
	if now_sec >= _move_next_change_sec:
		_move_target = Vector2(randf_range(x_min, x_max), randf_range(y_min, y_max))
		_move_next_change_sec = now_sec + randf_range(change_min, change_max)

		if now_sec >= _move_teleport_next_sec and randf() < teleport_chance:
			if boss_id == 6:
				_boss6_teleport()
			else:
				global_position = _move_target
				skill_invulnerable_until = now_sec + 0.25
			_move_teleport_next_sec = now_sec + randf_range(teleport_cd_min, teleport_cd_max)

	# Move towards the target with slight bobbing.
	var move_speed := clampf(speed * move_factor, 80.0, 1600.0)
	var bob := sin(movement_timer * (2.4 + float(boss_id) * 0.15)) * 18.0
	var desired := Vector2(_move_target.x, clampf(_move_target.y + bob, y_min, y_max))
	global_position = global_position.move_toward(desired, move_speed * delta)

	# Clamp after movement (avoid BottomBar area).
	global_position.x = clampf(global_position.x, x_min, x_max)
	global_position.y = clampf(global_position.y, y_min, y_max)

func _start_random_skill() -> void:
	# Python parity: bosses start a skill thread every N seconds; skills may overlap.
	match boss_id:
		1:
			boss1_pattern()
		2:
			boss2_pattern()
		3:
			boss3_pattern()
		4:
			boss4_pattern()
		5:
			boss5_pattern()
		6:
			boss6_pattern()

func boss1_pattern() -> void:
	# Python parity: Boss1 chooses one of 8 skills every 4-8s (12.5% each).
	var r := randf()
	if r < 0.125:
		await _boss1_sand_shoot()
	elif r < 0.25:
		await _boss1_summon_teleport()
	elif r < 0.375:
		await _boss1_shoot_aside()
	elif r < 0.5:
		await _boss1_star_shoot()
	elif r < 0.625:
		await _boss1_mirror_shoot()
	elif r < 0.75:
		await _boss1_black_hole()
	elif r < 0.875:
		await _boss1_lightning_chain()
	else:
		await _boss1_spiral_trap()

func _randomize_next_skill_interval() -> void:
	# Python bosses use random 4-8s (Boss6 varies by phase).
	match boss_id:
		6:
			match current_phase:
				1:
					pattern_interval = randf_range(4.0, 7.0)
				2:
					pattern_interval = randf_range(3.0, 6.0)
				3:
					pattern_interval = randf_range(4.0, 8.0)
				4:
					pattern_interval = randf_range(2.0, 4.0)
				5:
					pattern_interval = randf_range(3.0, 5.0)
				_:
					pattern_interval = randf_range(3.0, 7.0)
		_:
			pattern_interval = randf_range(4.0, 8.0)

func _spawn_python_bullet(
	origin: Vector2,
	tan_value: float,
	sample: int,
	speed_param: float,
	bullet_type: EnemyBullet.BulletType,
	texture_path: String
) -> EnemyBullet:
	# Convert Python movement params into a Godot direction+speed.
	# See Enemy._dir_from_tan_sample() and Enemy._python_bullet_speed_per_sec().
	var dir := _dir_from_tan_sample(tan_value, sample)
	var speed_px_per_sec := _python_bullet_speed_per_sec(speed_param, sample)

	var bullet := _spawn_bullet_at(origin, dir, speed_px_per_sec, bullet_type, texture_path)
	if bullet:
		bullet.tan_value = tan_value
	return bullet

func _boss1_sand_shoot() -> void:
	var token := _phase_token
	var wave_count := randi_range(3, 5)
	var origin := global_position

	for wave_index in range(wave_count):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return
		var player_pos := player.global_position
		var tan_sample := _calc_tan_and_sample(origin, player_pos)
		var base_tan := tan_sample.tan_value
		var sample := tan_sample.sample
		var artan := atan(base_tan)
		var rive := PI / 10.0
		var index := 0
		var timek := 0

		var times := wave_index + 1
		var bullet_count := 9 + times * 2
		for i in range(bullet_count):
			var tan_value := base_tan
			if i != 0:
				if index % 2 != 0:
					tan_value = tan(artan + float(timek) * rive)
				else:
					tan_value = tan(artan - float(timek) * rive)
					if index % 2 == 0:
						timek += 1

			var bullet := _spawn_python_bullet(
				origin,
				tan_value,
				sample,
				12.0,
				EnemyBullet.BulletType.SAND,
				"res://assets/sprites/bossbullut-2.png"
			)
			if bullet:
				bullet.damage = randi_range(8, 9)
			index += 1

		await get_tree().create_timer(0.5).timeout
		if _pattern_should_abort(token):
			return

func _boss1_star_shoot() -> void:
	var token := _phase_token
	var star_tex_path := "res://assets/sprites/bossbullut-9.png"
	for _i in range(5):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return
		var dir := (player.global_position - global_position).normalized()
		if dir.length() == 0.0:
			dir = Vector2.LEFT

		# Python: speed=20 (angled bullets use sqrt(speed) per tick).
		var bullet_speed := sqrt(20.0) * 60.0
		var bullet := _spawn_bullet_at(global_position, dir, bullet_speed, EnemyBullet.BulletType.NORMAL, star_tex_path)
		if bullet:
			bullet.can_return = true
			bullet.can_delete = false
			bullet.damage = randi_range(8, 9)
			bullet.rotate_with_direction = false
			bullet.spin_speed = deg_to_rad(200.0)

			var sprite := bullet.get_node_or_null("Sprite2D") as Sprite2D
			if sprite:
				sprite.scale = Vector2.ONE

			var cs := bullet.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if cs:
				var circle := CircleShape2D.new()
				circle.radius = 32.0
				cs.shape = circle

		await get_tree().create_timer(1.2).timeout
		if _pattern_should_abort(token):
			return

func _boss1_mirror_shoot() -> void:
	# Python: 3 waves, 180° symmetry pairs every 15 degrees, speed=10.
	var bullet_speed := sqrt(10.0) * 60.0
	for _wave in range(3):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		for deg in range(0, 180, 15):
			var angle := deg_to_rad(float(deg))
			var dir1 := Vector2(cos(angle), sin(angle))
			var dir2 := -dir1
			_spawn_bullet_at(global_position, dir1, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-2.png")
			_spawn_bullet_at(global_position, dir2, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-2.png")

		await get_tree().create_timer(0.8).timeout

func _boss1_black_hole() -> void:
	var token := _phase_token
	if not get_parent():
		return

	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	var hole_pos := Vector2(
		randf_range(300.0, maxf(300.0, viewport_size.x - 300.0)),
		randf_range(200.0, maxf(200.0, playfield_bottom - 200.0))
	)

	# Visual hole marker (uses EnemyBullet scene but with collision disabled).
	var hole := _spawn_bullet_at(hole_pos, Vector2.LEFT, 0.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-9.png")
	if hole:
		hole.damage = 0
		hole.can_delete = false
		hole.ban_remove = true
		hole.monitoring = false
		hole.monitorable = false
		hole.collision_mask = 0

		var sprite := hole.get_node_or_null("Sprite2D") as Sprite2D
		if sprite:
			sprite.scale = Vector2.ONE

	var start_sec := Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - start_sec < 3.0:
		if _pattern_should_abort(token):
			break
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				break
			await get_tree().create_timer(0.1).timeout
		if _pattern_should_abort(token):
			break

		var player := _get_player_safe()
		if player:
			var to_hole := hole_pos - player.global_position
			var dist := to_hole.length()
			if dist > 10.0:
				var pull_px_per_frame: float = minf(300.0 / dist, 3.0)
				player.global_position += to_hole.normalized() * pull_px_per_frame

		if randf() < 0.3:
			var angle_deg := randi_range(0, 359)
			var angle := deg_to_rad(float(angle_deg))
			var dir := Vector2(cos(angle), sin(angle))
			var bullet_speed := sqrt(8.0) * 60.0
			_spawn_bullet_at(hole_pos, dir, bullet_speed, EnemyBullet.BulletType.CIRCLE, "res://assets/sprites/bossbullut-3.png")

		await get_tree().create_timer(0.1).timeout
		if _pattern_should_abort(token):
			break

	if is_instance_valid(hole):
		hole.queue_free()

func _boss1_summon_teleport() -> void:
	# Python: tries to summon a Teleport portal; otherwise falls back to starShoot.
	if is_instance_valid(_boss1_portal_ref):
		await _boss1_star_shoot()
		return

	var enemy_scene_ref: PackedScene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref or not get_parent():
		await _boss1_star_shoot()
		return

	# Portal uses the Enemy scene, but we freeze movement/shooting and swap sprite.
	var portal := enemy_scene_ref.instantiate() as Enemy
	if not portal:
		await _boss1_star_shoot()
		return

	portal.enemy_kind = EnemyKind.BASE_1
	portal.global_position = global_position + Vector2(-120.0, 0.0)
	get_parent().add_child(portal)

	var portal_sprite := portal.get_node_or_null("Sprite2D") as Sprite2D
	var portal_tex: Texture2D = load("res://assets/sprites/teleport.png")
	if portal_sprite and portal_tex:
		portal_sprite.texture = portal_tex

	portal.speed = 0.0
	portal.can_change_move = false
	portal.can_shoot = false
	var portal_timer := portal.get_node_or_null("ShootTimer") as Timer
	if portal_timer:
		portal_timer.stop()

	portal.health = 100 * maxi(1, GameManager.boss_death_times)
	portal.max_health = portal.health

	_boss1_portal_ref = portal
	portal.tree_exited.connect(func():
		if _boss1_portal_ref == portal:
			_boss1_portal_ref = null
	)

	# Spawn minions while the portal exists.
	_boss1_portal_spawn_loop(portal)

func _boss1_portal_spawn_loop(portal: Enemy) -> void:
	if not is_instance_valid(portal):
		return

	var enemy_scene_ref: PackedScene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref:
		return

	while is_instance_valid(portal) and portal.is_inside_tree() and get_parent():
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		if not is_instance_valid(portal) or not portal.is_inside_tree() or not get_parent():
			return

		var minion := enemy_scene_ref.instantiate() as Enemy
		if minion:
			# Python SummonEnemies uses rint -1/-2; we map to FAST/TANK visuals.
			var boss_mult := maxi(1, GameManager.boss_death_times)
			var is_tank := randf() < 0.5
			minion.enemy_kind = EnemyKind.FAST if not is_tank else EnemyKind.TANK
			minion.global_position = portal.global_position
			get_parent().add_child(minion)

			# Override visuals to match enemy--1/--2 sprites.
			var tex_path := "res://assets/sprites/enemy--1.png" if not is_tank else "res://assets/sprites/enemy--2.png"
			var tex: Texture2D = load(tex_path)
			var spr := minion.get_node_or_null("Sprite2D") as Sprite2D
			if spr and tex:
				spr.texture = tex

			minion.health = (100 if not is_tank else 130) * boss_mult
			minion.max_health = minion.health
			minion.speed = 3.0 * 60.0
			minion.shoot_cooldown = 1.2

		await get_tree().create_timer(randf_range(3.0, 9.0)).timeout

func _boss1_shoot_aside() -> void:
	# Python: 35 iterations, two bullets offset by +/- PI/10, sleep 0.2.
	var token := _phase_token
	var bullet_speed := sqrt(13.0) * 60.0
	for _i in range(35):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return
		var base_dir := (player.global_position - global_position)
		if base_dir.length() == 0.0:
			base_dir = Vector2.LEFT
		var base_angle := base_dir.angle()

		var dir1 := Vector2(cos(base_angle + PI / 10.0), sin(base_angle + PI / 10.0))
		var dir2 := Vector2(cos(base_angle - PI / 10.0), sin(base_angle - PI / 10.0))
		_spawn_bullet_at(global_position, dir1, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-2.png")
		_spawn_bullet_at(global_position, dir2, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-2.png")

		await get_tree().create_timer(0.2).timeout
		if _pattern_should_abort(token):
			return

func _boss1_lightning_chain() -> void:
	# Python: 8 lightning strikes with a 0.5s warning.
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	for _i in range(8):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		var x_pos := randf_range(0.0, maxf(0.0, viewport_size.x - 50.0))
		var warning := _spawn_rect_hazard(Vector2(x_pos, 0.0), Vector2(50.0, playfield_bottom), Color(1, 1, 0), 0.4, 0, true)
		# Slightly longer telegraph to leave reaction time (more Touhou-like).
		await get_tree().create_timer(0.8).timeout
		if is_instance_valid(warning):
			warning.queue_free()

		var lightning := _spawn_rect_hazard(Vector2(x_pos, 0.0), Vector2(50.0, playfield_bottom), Color(1, 1, 0.4), 1.0, randi_range(8, 9), false)
		if lightning:
			var sprite := lightning.get_node_or_null("Sprite2D") as Sprite2D
			for alpha in range(255, 0, -30):
				while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
					await get_tree().create_timer(0.1).timeout
				if not is_instance_valid(lightning):
					break
				if sprite:
					sprite.modulate.a = float(alpha) / 255.0
				await get_tree().create_timer(0.05).timeout
			if is_instance_valid(lightning):
				lightning.queue_free()

func _boss1_spiral_trap() -> void:
	# Python: spiral trap centered on the player, shrinking radius.
	var player := _get_player_safe()
	if not player:
		return

	var center := player.global_position
	var bullet_speed := sqrt(5.0) * 60.0
	for radius in range(300, 50, -25):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		for arm in range(3):
			var base_angle_deg := float(arm * 120) + float(300 - radius) * 2.0
			for offset in range(0, 360, 30):
				var angle_deg := base_angle_deg + float(offset)
				var angle := deg_to_rad(angle_deg)
				var spawn_pos := center + Vector2(float(radius) * cos(angle), float(radius) * sin(angle))
				var dir := (center - spawn_pos).normalized()
				_spawn_bullet_at(spawn_pos, dir, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-2.png")

		await get_tree().create_timer(0.3).timeout

func _spawn_rect_hazard(
	top_left: Vector2,
	size: Vector2,
	color: Color,
	alpha: float,
	damage_value: int,
	is_warning: bool
) -> EnemyBullet:
	# Uses EnemyBullet for convenience (collision + lifetime managed by caller).
	var center := top_left + size * 0.5
	var hazard := _spawn_bullet_at(center, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "")
	if not hazard:
		return null

	hazard.ban_remove = true
	hazard.can_delete = false
	hazard.rotate_with_direction = false
	hazard.spin_speed = 0.0
	hazard.damage = damage_value

	if is_warning:
		hazard.collision_mask = 0

	var sprite := hazard.get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.texture = _create_solid_texture(int(round(size.x)), int(round(size.y)), Color(color.r, color.g, color.b, alpha))
		sprite.scale = Vector2.ONE

	var cs := hazard.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs:
		var rect := RectangleShape2D.new()
		rect.size = size
		cs.shape = rect

	return hazard

func _create_solid_texture(w: int, h: int, color: Color) -> Texture2D:
	var image := Image.create(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func _spawn_bullet_at(
	spawn_pos: Vector2,
	dir: Vector2,
	bullet_speed: float,
	bullet_type: EnemyBullet.BulletType,
	texture_path: String
) -> EnemyBullet:
	if not bullet_scene or not get_parent():
		return null

	var bullet := bullet_scene.instantiate() as EnemyBullet
	if not bullet:
		return null

	bullet.global_position = spawn_pos
	bullet.direction = dir.normalized() if dir.length() > 0.0 else Vector2.LEFT
	bullet.speed = bullet_speed * clampf(boss_bullet_speed_scale, 0.05, 5.0)
	bullet.bullet_type = bullet_type
	bullet.tracking_enabled = false
	bullet.damage = randi_range(8, 9)

	if texture_path != "":
		var bullet_sprite := bullet.get_node_or_null("Sprite2D") as Sprite2D
		var tex: Texture2D = load(texture_path)
		if bullet_sprite and tex:
			bullet_sprite.texture = tex

	get_parent().add_child(bullet)
	return bullet

func boss2_pattern() -> void:
	_boss2_ensure_prevent()

	var r := randf()
	if r > 0.75:
		await _boss2_generate_love()
	elif r > 0.625:
		await _boss2_use_attract()
	elif r > 0.5:
		await _boss2_made_in_heaven()
	elif r > 0.375:
		await _boss2_heart_rain()
	elif r > 0.25:
		await _boss2_reverse_time()
	elif r > 0.125:
		await _boss2_heart_trap()
	else:
		await _boss2_split_bomb()

func _boss2_ensure_prevent() -> void:
	# Python: createPrevent() is called whenever Boss2 starts a skill.
	# We spawn the 2 barriers once and keep them until the boss is truly defeated.
	if _boss2_prevent_ready:
		return
	if not get_parent():
		return

	var tex: Texture2D = load("res://assets/sprites/prevent.png")
	for top_left in [Vector2(400, 0), Vector2(400, 720)]:
		var area := Area2D.new()
		area.name = "Prevent"
		area.collision_layer = 4
		# Player (1) + player bullets (2) + enemy bullets (4).
		# The barriers act like a "forbidden gate" and should block bullets.
		area.collision_mask = 7
		area.add_to_group("prevent")

		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = true
		area.add_child(sprite)

		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(40, 120)
		shape.shape = rect
		area.add_child(shape)

		# Convert Python top-left (40x120) -> centered global position.
		area.global_position = top_left + Vector2(20.0, 60.0)

		# Prevent barriers should delete most enemy bullets on contact (Python: canRemove).
		area.area_entered.connect(func(other: Area2D) -> void:
			if not other or not is_instance_valid(other):
				return
			if other is EnemyBullet:
				var bullet := other as EnemyBullet
				if bullet and is_instance_valid(bullet) and bullet.can_remove:
					bullet.queue_free()
			elif other is PlayerBullet:
				(other as PlayerBullet).queue_free()
		)

		get_parent().add_child(area)
		_boss2_prevent_nodes.append(area)

	_boss2_prevent_ready = true

func _boss2_generate_love() -> void:
	# Python: a growing heart bullet that cannot be deleted on hit.
	var bullet := _spawn_bullet_at(
		global_position,
		Vector2.LEFT,
		13.0 * 60.0,
		EnemyBullet.BulletType.NORMAL,
		"res://assets/sprites/bossbullut-4.png"
	)
	if not bullet:
		return

	bullet.can_delete = false
	bullet.can_remove = false
	bullet.damage = randi_range(8, 9)

	var sprite := bullet.get_node_or_null("Sprite2D") as Sprite2D
	var cs := bullet.get_node_or_null("CollisionShape2D") as CollisionShape2D

	var size := 25.0
	var base_size := 30.0
	if sprite:
		sprite.scale = Vector2.ONE * (size / base_size)
	if cs:
		var circle := CircleShape2D.new()
		circle.radius = size * 0.5
		cs.shape = circle

	while is_instance_valid(bullet) and size <= 120.0:
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout
		size += 10.0
		if sprite:
			sprite.scale = Vector2.ONE * (size / base_size)
		if cs:
			var circle := CircleShape2D.new()
			circle.radius = size * 0.5
			cs.shape = circle
		await get_tree().create_timer(0.1).timeout

func _boss2_use_attract() -> void:
	# Python: pulls the player toward an attract point for 4 seconds.
	if _boss2_attract_active or _made_in_heaven_active:
		return
	if not get_parent():
		return

	var attract := Node2D.new()
	attract.name = "Attract"
	attract.add_to_group("boss_hazards")
	attract.global_position = global_position + Vector2(-50.0, 0.0)
	get_parent().add_child(attract)

	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/sprites/attract.png")
	sprite.centered = true
	attract.add_child(sprite)

	_boss2_attract_active = true
	var start_sec := Time.get_ticks_msec() / 1000.0
	var wiggle_phase := 0
	while Time.get_ticks_msec() / 1000.0 - start_sec < 4.0:
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(attract):
			break

		# Wiggle (attractMove)
		var offsets := [Vector2(5, 5), Vector2(-5, -5), Vector2(5, -5), Vector2(-5, 5)]
		attract.global_position += offsets[wiggle_phase % offsets.size()]
		wiggle_phase += 1

		# Pull player (attract)
		var player := _get_player_safe()
		if player:
			var to_attr := attract.global_position - player.global_position
			var dist := to_attr.length()
			if dist > 0.1:
				var step := minf(12.0, dist)
				player.global_position += to_attr.normalized() * step

		await get_tree().create_timer(0.05).timeout

	_boss2_attract_active = false
	if is_instance_valid(attract):
		attract.queue_free()

func _boss2_made_in_heaven() -> void:
	# Python: temporary boss speedup + invulnerability for 8s.
	if _made_in_heaven_active:
		return

	_made_in_heaven_active = true
	var original_speed := speed
	var original_shoot_cd := shoot_cooldown
	var original_tex = sprite.texture if sprite else null

	skill_invulnerable_until = (Time.get_ticks_msec() / 1000.0) + 8.0
	speed = 30.0 * 60.0
	shoot_cooldown = 1.0
	if shoot_timer:
		shoot_timer.wait_time = shoot_cooldown

	var made_tex: Texture2D = load("res://assets/sprites/madeinheaven.png")
	if sprite and made_tex:
		sprite.texture = made_tex

	await get_tree().create_timer(8.0).timeout
	if not is_instance_valid(self):
		return

	speed = original_speed
	shoot_cooldown = original_shoot_cd
	if shoot_timer:
		shoot_timer.wait_time = shoot_cooldown
	if sprite and original_tex:
		sprite.texture = original_tex

	_made_in_heaven_active = false

func _boss2_heart_rain() -> void:
	# Python intent: hearts fall from the top.
	var viewport_size := get_viewport_rect().size
	for _i in range(20):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		var x_pos := randf_range(100.0, maxf(100.0, viewport_size.x - 100.0))
		var spawn_pos := Vector2(x_pos, -50.0)
		var speed_tick := float(randi_range(6, 12))
		var bullet := _spawn_bullet_at(spawn_pos, Vector2.DOWN, speed_tick * 60.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-4.png")
		if bullet:
			bullet.can_return = true
		await get_tree().create_timer(0.15).timeout

func _boss2_reverse_time() -> void:
	# Python: reverse all enemy bullet directions.
	var bullets: Array = get_tree().get_nodes_in_group("enemy_bullets")
	for b in bullets:
		if not b or not is_instance_valid(b):
			continue
		if "direction" in b:
			b.direction = -b.direction
	await get_tree().create_timer(2.0).timeout

func _boss2_heart_trap() -> void:
	# Python: 3 rings of static hearts around the player, removed after 2s.
	var player := _get_player_safe()
	if not player:
		return
	var center := player.global_position

	var rings := [100.0, 150.0, 200.0]
	for radius in rings:
		for deg in range(0, 360, 20):
			var angle := deg_to_rad(float(deg))
			var pos := center + Vector2(radius * cos(angle), radius * sin(angle))
			var bullet := _spawn_bullet_at(pos, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-4.png")
			if bullet:
				bullet.direction = Vector2.ZERO
				bullet.rotate_with_direction = false
				bullet.ban_remove = true
				bullet.can_delete = false
				_queue_free_after(bullet, 2.0)
		await get_tree().create_timer(0.3).timeout

func _boss2_split_bomb() -> void:
	# Python: 5 tracking hearts, split into 8 bullets after 1s.
	var token := _phase_token
	for _i in range(5):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return
		var dir := (player.global_position - global_position).normalized()
		if dir.length() == 0.0:
			dir = Vector2.LEFT
		var bullet := _spawn_bullet_at(global_position, dir, sqrt(8.0) * 60.0, EnemyBullet.BulletType.TRACKING, "res://assets/sprites/bossbullut-4.png")
		if bullet:
			bullet.tracking_enabled = true
			_boss2_split_bomb_split_after(bullet)
		await get_tree().create_timer(0.8).timeout
		if _pattern_should_abort(token):
			return

func _boss2_split_bomb_split_after(bullet: EnemyBullet) -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(bullet) or not get_parent():
		return
	var pos := bullet.global_position
	bullet.queue_free()

	var bullet_speed := sqrt(10.0) * 60.0
	for deg in range(0, 360, 45):
		var angle := deg_to_rad(float(deg))
		var dir := Vector2(cos(angle), sin(angle))
		_spawn_bullet_at(pos, dir, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-3.png")

func _queue_free_after(node: Node, delay: float) -> void:
	if not node:
		return
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(node):
		node.queue_free()

func boss3_pattern() -> void:
	var r := randf()
	if r < 0.143:
		await _boss3_set_gold()
	elif r < 0.286:
		await _boss3_cut_body()
	elif r < 0.429:
		await _boss3_time_stop()
	elif r < 0.572:
		await _boss3_super_shoot()
	elif r < 0.715:
		await _boss3_golden_storm()
	elif r < 0.858:
		await _boss3_time_bubble()
	else:
		await _boss3_coin_barrage()

func _boss3_set_gold() -> void:
	# Python: a brief "gold" state (mostly visual).
	if not sprite:
		await get_tree().create_timer(5.0).timeout
		return
	var original := sprite.modulate
	sprite.modulate = Color(1.2, 1.1, 0.4, 1.0)
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(self) and sprite:
		sprite.modulate = original

func _boss3_cut_body() -> void:
	# Python: spawn 2 stationary clones (boss-like enemies).
	var enemy_scene_ref: PackedScene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref or not get_parent():
		return

	var boss_mult := maxi(1, GameManager.boss_death_times)
	var tex: Texture2D = load("res://assets/sprites/bossenemy-3.png")

	for _i in range(2):
		var clone := enemy_scene_ref.instantiate() as Enemy
		if not clone:
			continue
		clone.enemy_kind = EnemyKind.MINIBOSS
		clone.health = 65 * boss_mult
		clone.max_health = clone.health
		clone.speed = 0.0
		clone.can_change_move = false
		clone.shoot_cooldown = 3.0

		# Python spawn ranges are top-left; convert to centered 80x80.
		clone.global_position = Vector2(randf_range(400.0, 560.0) + 40.0, randf_range(0.0, 400.0) + 40.0)
		get_parent().add_child(clone)

		var spr := clone.get_node_or_null("Sprite2D") as Sprite2D
		if spr and tex:
			spr.texture = tex
			spr.scale = Vector2.ONE

		var cs := clone.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs:
			var rect := RectangleShape2D.new()
			rect.size = Vector2(80, 80)
			cs.shape = rect

		var timer := clone.get_node_or_null("ShootTimer") as Timer
		if timer:
			timer.wait_time = clone.shoot_cooldown

func _boss3_time_stop() -> void:
	var token := _phase_token
	if GameManager.has_method("start_time_stop"):
		# Boss3 (JoJo): stop time for the player, but the boss keeps acting.
		GameManager.start_time_stop(4.0, true, false)

	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	# During time stop: reposition and "plant" bullets (they will resume afterwards).
	for i in range(3):
		if _pattern_should_abort(token):
			return

		global_position = Vector2(
			randf_range(viewport_size.x * 0.60, viewport_size.x - 160.0),
			randf_range(120.0, maxf(120.0, playfield_bottom * 0.60))
		)
		skill_invulnerable_until = (Time.get_ticks_msec() / 1000.0) + 0.25

		_touhou_ring("res://assets/sprites/bossbullut-6.png", 22 + i * 4, 7.0 + float(i) * 0.4)
		_touhou_aimed_spread("res://assets/sprites/bossbullut-5.png", 10.0 + float(i), 5, 22.0)
		await get_tree().create_timer(0.45).timeout

	# Wait until time resumes.
	while GameManager.time_stop_active:
		if _pattern_should_abort(token):
			return
		await get_tree().create_timer(0.1).timeout

func _boss3_super_shoot() -> void:
	# Python: sweeping horizontal shots (16 bullets, y zig-zag), speed=5.
	var y := 10.0
	var dir_sign := 1
	for _i in range(16):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		var spawn_pos := Vector2(global_position.x, y)
		_spawn_bullet_at(spawn_pos, Vector2.LEFT, 5.0 * 60.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-5.png")

		if dir_sign == 1:
			y += 60.0
		else:
			y -= 60.0
		if y >= 450.0:
			dir_sign = -1

		await get_tree().create_timer(0.3).timeout

func _boss3_golden_storm() -> void:
	# Python: rotating 4-way bullet storm, speed=12.
	var bullet_speed := sqrt(12.0) * 60.0
	for rot in range(0, 720, 15):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		for offset in [0, 90, 180, 270]:
			var angle_deg := float(rot + offset)
			var angle := deg_to_rad(angle_deg)
			var dir := Vector2(cos(angle), sin(angle))
			_spawn_bullet_at(global_position, dir, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-5.png")

		await get_tree().create_timer(0.08).timeout

func _boss3_time_bubble() -> void:
	# Python: 4 slow bubbles (radius 75) lasting 4 seconds.
	if not get_parent():
		return

	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	for _i in range(4):
		if not is_instance_valid(self) or not get_parent():
			return

		var bubble_x := randf_range(200.0, maxf(200.0, viewport_size.x - 200.0))
		var bubble_y := randf_range(150.0, maxf(150.0, playfield_bottom - 150.0))
		_spawn_slow_bubble(Vector2(bubble_x, bubble_y), 75.0, 4.0, 2.0 * 60.0)
		await get_tree().create_timer(1.5).timeout

func _spawn_slow_bubble(center: Vector2, radius: float, duration: float, normal_speed_px_per_sec: float) -> void:
	var zone := Area2D.new()
	zone.name = "TimeBubble"
	zone.collision_layer = 4
	zone.collision_mask = 1
	zone.add_to_group("slow_zone")
	zone.set_meta("normal_speed_px_per_sec", normal_speed_px_per_sec)
	zone.global_position = center

	var sprite := Sprite2D.new()
	sprite.texture = _create_circle_texture(int(round(radius)), Color(1.0, 0.84, 0.0, 0.4), Color(1.0, 0.84, 0.0, 0.8), 3)
	sprite.centered = true
	zone.add_child(sprite)

	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	cs.shape = circle
	zone.add_child(cs)

	get_parent().add_child(zone)
	_queue_free_after(zone, duration)

func _create_circle_texture(radius: int, fill: Color, border: Color, border_px: int) -> Texture2D:
	var r := maxi(1, radius)
	var diameter := r * 2
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2(float(r), float(r))
	for y in range(diameter):
		for x in range(diameter):
			var dist := Vector2(float(x), float(y)).distance_to(center)
			if dist <= float(r):
				var col := fill
				if dist >= float(r - border_px):
					col = border
				image.set_pixel(x, y, col)
	return ImageTexture.create_from_image(image)

func _boss3_coin_barrage() -> void:
	# Python: repeated vertical coin walls moving left.
	for _i in range(10):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		for y_offset in range(-200, 700, 80):
			var pos := Vector2(global_position.x, global_position.y + float(y_offset))
			_spawn_bullet_at(pos, Vector2.LEFT, 6.0 * 60.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-5.png")
		await get_tree().create_timer(0.5).timeout

func boss4_pattern() -> void:
	var r := randf()
	if r < 0.143:
		_boss4_light_shoot()
	elif r < 0.286:
		await _boss4_drag_shoot()
	elif r < 0.429:
		await _boss4_summon_ufo()
	elif r < 0.572:
		await _boss4_side_shoot()
	elif r < 0.715:
		await _boss4_screen_static()
	elif r < 0.858:
		_boss4_orbital_strike()
	else:
		await _boss4_pixel_storm()

func _spawn_textured_rect_hazard(
	top_left: Vector2,
	size: Vector2,
	texture_path: String,
	damage_value: int,
	is_warning: bool,
	alpha: float = 1.0
) -> EnemyBullet:
	var center := top_left + size * 0.5
	var hazard := _spawn_bullet_at(center, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, texture_path)
	if not hazard:
		return null

	hazard.ban_remove = true
	hazard.can_delete = false
	hazard.rotate_with_direction = false
	hazard.spin_speed = 0.0
	hazard.direction = Vector2.ZERO
	hazard.speed = 0.0
	hazard.damage = damage_value

	if is_warning:
		hazard.collision_mask = 0

	var sprite := hazard.get_node_or_null("Sprite2D") as Sprite2D
	if sprite:
		sprite.modulate.a = alpha
		var tex := sprite.texture
		if tex:
			var ts := tex.get_size()
			if ts.x > 0 and ts.y > 0:
				sprite.scale = Vector2(size.x / ts.x, size.y / ts.y)

	var cs := hazard.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs:
		var rect := RectangleShape2D.new()
		rect.size = size
		cs.shape = rect

	return hazard

func _spawn_icon_hazard(pos: Vector2, texture_path: String, damage_value: int, warning_only: bool) -> EnemyBullet:
	var icon := _spawn_bullet_at(pos, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, texture_path)
	if not icon:
		return null
	icon.ban_remove = true
	icon.can_delete = false
	icon.rotate_with_direction = false
	icon.spin_speed = 0.0
	icon.direction = Vector2.ZERO
	icon.speed = 0.0
	icon.damage = damage_value
	if warning_only:
		icon.collision_mask = 0
	return icon

func _boss4_light_shoot() -> void:
	# Python: 5 warnings quickly; each spawns a laser after ~2s.
	for _i in range(5):
		if not is_instance_valid(self) or not get_parent():
			return
		_boss4_light_single()
		await get_tree().create_timer(0.2).timeout

func _boss4_light_single() -> void:
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	var y := randf_range(80.0, maxf(80.0, playfield_bottom - 80.0))
	var warn_pos := Vector2(randf_range(150.0, maxf(150.0, viewport_size.x - 30.0)), y)
	var warning := _spawn_icon_hazard(warn_pos, "res://assets/sprites/error.png", 0, true)

	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(self) or not get_parent():
		return

	if is_instance_valid(warning):
		warning.queue_free()

	var top_left := Vector2(0.0, y - 15.0)
	var laser := _spawn_textured_rect_hazard(top_left, Vector2(viewport_size.x, 30.0), "res://assets/sprites/light.png", randi_range(8, 9), false, 0.0)
	if not laser:
		return

	var sprite := laser.get_node_or_null("Sprite2D") as Sprite2D
	for a in range(0, 256, 20):
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(laser):
			return
		if sprite:
			sprite.modulate.a = float(a) / 255.0
		await get_tree().create_timer(0.05).timeout

	await get_tree().create_timer(0.3).timeout

	for a in range(255, -1, -20):
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(laser):
			return
		if sprite:
			sprite.modulate.a = float(a) / 255.0
		await get_tree().create_timer(0.05).timeout

	if is_instance_valid(laser):
		laser.queue_free()

func _boss4_drag_shoot() -> void:
	# Python: 20 fast "drag" bullets (bossbullut-10) at 0.2s intervals.
	var token := _phase_token
	for _i in range(20):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return
		var dir := (player.global_position - global_position)
		if dir.length() == 0.0:
			dir = Vector2.LEFT
		# Leave reaction time: still fast, but not instant.
		var bullet := _spawn_bullet_at(global_position, dir, sqrt(70.0) * 60.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-10.png")
		if bullet:
			bullet.turn_rate = (-6.0 if randf() < 0.5 else 6.0)
			bullet.ban_remove = true
		await get_tree().create_timer(0.2).timeout
		if _pattern_should_abort(token):
			return

func _boss4_summon_ufo() -> void:
	# Python: 12 aliens falling from the top.
	var enemy_scene_ref: PackedScene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref or not get_parent():
		return

	var boss_mult := maxi(1, GameManager.boss_death_times)
	var tex: Texture2D = load("res://assets/sprites/alien.png")
	var viewport_size := get_viewport_rect().size

	for _i in range(12):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		var ufo := enemy_scene_ref.instantiate() as Enemy
		if ufo:
			ufo.use_custom_setup = true
			ufo.auto_shoot_enabled = false
			ufo.enemy_kind = EnemyKind.BASE_1
			ufo.can_change_move = false
			ufo.move_direction = "down"
			ufo.global_position = Vector2(randf_range(300.0, 400.0) + 20.0, -40.0 + 20.0)
			ufo.health = 40 * boss_mult
			ufo.max_health = ufo.health
			ufo.speed = 4.0 * 60.0

			var spr := ufo.get_node_or_null("Sprite2D") as Sprite2D
			if spr and tex:
				spr.texture = tex
				spr.scale = Vector2.ONE

			# Ensure it stays inside X bounds.
			ufo.global_position.x = clampf(ufo.global_position.x, 60.0, viewport_size.x - 60.0)

			get_parent().add_child(ufo)

		await get_tree().create_timer(0.4).timeout

func _boss4_side_shoot() -> void:
	# Python: 4 TV turrets that fire straight-left streams.
	var player := _get_player_safe()
	if not player:
		return

	var turrets: Array[EnemyBullet] = []
	var base_x := global_position.x
	var y_player := player.global_position.y
	var positions := [
		Vector2(base_x, global_position.y),
		Vector2(base_x, global_position.y + 40.0),
		Vector2(base_x, y_player + 20.0),
		Vector2(base_x, y_player)
	]

	for pos in positions:
		var t := _spawn_icon_hazard(pos, "res://assets/sprites/tv.png", 0, true)
		if t:
			t.ban_remove = true
			turrets.append(t)

	_basic_shoot_suppressed_until = maxf(_basic_shoot_suppressed_until, (Time.get_ticks_msec() / 1000.0) + 5.0)

	# Move turrets apart (5 steps, 0.3s).
	for _step in range(5):
		if turrets.size() >= 4:
			turrets[0].global_position.y -= 8.0
			turrets[1].global_position.y += 8.0
			turrets[2].global_position.y -= 8.0
			turrets[3].global_position.y += 8.0
		await get_tree().create_timer(0.3).timeout

	# Wait until ~2 seconds since start.
	await get_tree().create_timer(0.5).timeout

	# Fire 25 bursts (0.1s), 4 bullets each.
	var bullet_speed := 11.5 * 60.0
	for _i in range(25):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		for t in turrets:
			if not is_instance_valid(t):
				continue
			var b := _spawn_bullet_at(t.global_position, Vector2.LEFT, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-10.png")
			if b:
				b.damage = randi_range(8, 9)
		await get_tree().create_timer(0.1).timeout

	for t in turrets:
		if is_instance_valid(t):
			t.queue_free()

func _boss4_screen_static() -> void:
	# Python: 3 static interference screens that slow the player and deal damage.
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	for _i in range(3):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		var top_left := Vector2(
			randf_range(200.0, maxf(200.0, viewport_size.x - 350.0)),
			randf_range(100.0, maxf(100.0, playfield_bottom - 250.0))
		)
		var hazard := _spawn_textured_rect_hazard(top_left, Vector2(150.0, 150.0), "res://assets/sprites/error.png", 5, false, 0.7)
		if hazard:
			hazard.add_to_group("slow_zone")
			hazard.set_meta("normal_speed_px_per_sec", 180.0)
			_boss4_static_flicker(hazard, 4.0)
			_queue_free_after(hazard, 4.0)

		await get_tree().create_timer(1.5).timeout

func _boss4_static_flicker(hazard: EnemyBullet, duration: float) -> void:
	var start := Time.get_ticks_msec() / 1000.0
	var sprite := hazard.get_node_or_null("Sprite2D") as Sprite2D
	while (Time.get_ticks_msec() / 1000.0) - start < duration:
		if not is_instance_valid(hazard):
			return
		if sprite:
			sprite.modulate = Color(randf_range(0.7, 1.2), randf_range(0.7, 1.2), randf_range(0.7, 1.2), sprite.modulate.a)
		await get_tree().create_timer(0.2).timeout

func _boss4_orbital_strike() -> void:
	# Python: 4 UFOs orbit the screen edges and fire at the player.
	if not get_parent():
		return
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	# Keep the orbit inside the playfield (not glued to the window edge / BottomBar).
	var left_bound := 140.0
	var right_bound := viewport_size.x - 120.0
	var top_bound := 120.0
	var bottom_bound := maxf(top_bound + 120.0, playfield_bottom - 140.0)

	var positions := [
		{"edge": "top", "pos": Vector2(randf_range(left_bound, right_bound), top_bound)},
		{"edge": "bottom", "pos": Vector2(randf_range(left_bound, right_bound), bottom_bound)},
		{"edge": "left", "pos": Vector2(left_bound, randf_range(top_bound, bottom_bound))},
		{"edge": "right", "pos": Vector2(right_bound, randf_range(top_bound, bottom_bound))}
	]

	var ufos: Array[EnemyBullet] = []
	for entry in positions:
		var ufo := _spawn_icon_hazard(entry["pos"], "res://assets/sprites/alien.png", 10, false)
		if not ufo:
			continue
		ufo.set_meta("edge", entry["edge"])
		ufo.ban_remove = true
		ufos.append(ufo)

	_boss4_orbital_move(ufos, left_bound, right_bound, top_bound, bottom_bound)
	_boss4_orbital_shoot(ufos)

func _boss4_orbital_move(ufos: Array[EnemyBullet], left_bound: float, right_bound: float, top_bound: float, bottom_bound: float) -> void:
	# 80 frames, step every 0.1s.
	for _frame in range(80):
		for ufo in ufos:
			if not is_instance_valid(ufo):
				continue
			var edge: String = str(ufo.get_meta("edge", "top"))
			var p := ufo.global_position
			match edge:
				"top":
					p.x += 8.0
					if p.x >= right_bound:
						edge = "right"
						p.y = top_bound
				"right":
					p.y += 8.0
					if p.y >= bottom_bound:
						edge = "bottom"
						p.x = right_bound
				"bottom":
					p.x -= 8.0
					if p.x <= left_bound:
						edge = "left"
						p.y = bottom_bound
				"left":
					p.y -= 8.0
					if p.y <= top_bound:
						edge = "top"
						p.x = left_bound
			ufo.global_position = p
			ufo.set_meta("edge", edge)
		await get_tree().create_timer(0.1).timeout

	for ufo in ufos:
		if is_instance_valid(ufo):
			ufo.queue_free()

func _boss4_orbital_shoot(ufos: Array[EnemyBullet]) -> void:
	var bullet_speed := sqrt(10.0) * 60.0
	for _i in range(30):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if player:
			for ufo in ufos:
				if not is_instance_valid(ufo):
					continue
				var dir := (player.global_position - ufo.global_position)
				if dir.length() == 0.0:
					dir = Vector2.LEFT
				_spawn_bullet_at(ufo.global_position, dir, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-10.png")

		await get_tree().create_timer(0.25).timeout

func _boss4_pixel_storm() -> void:
	# Python: pixel blocks spawn around the player then burst outward.
	var player := _get_player_safe()
	if not player:
		return
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var patterns: Array[Callable] = []
	patterns.append(func(cx: float, cy: float) -> Array[Vector2]:
		var pts: Array[Vector2] = []
		for dx in range(-5, 6):
			pts.append(Vector2(cx + float(dx) * 40.0, cy))
		for dy in range(-5, 6):
			pts.append(Vector2(cx, cy + float(dy) * 40.0))
		return pts
	)
	patterns.append(func(cx: float, cy: float) -> Array[Vector2]:
		var pts: Array[Vector2] = []
		for dx in range(-4, 5):
			for dy in range(-4, 5):
				pts.append(Vector2(cx + float(dx) * 50.0, cy + float(dy) * 50.0))
		return pts
	)
	patterns.append(func(cx: float, cy: float) -> Array[Vector2]:
		var pts: Array[Vector2] = []
		for d in range(-6, 7):
			pts.append(Vector2(cx + float(d) * 40.0, cy + float(d) * 40.0))
			pts.append(Vector2(cx + float(d) * 40.0, cy - float(d) * 40.0))
		return pts
	)

	var center := player.global_position
	var positions: Array[Vector2] = patterns[randi_range(0, patterns.size() - 1)].call(center.x, center.y)

	var pixels: Array[EnemyBullet] = []
	for p in positions:
		if p.x < 0.0 or p.x > viewport_size.x or p.y < 0.0 or p.y > playfield_bottom:
			continue
		var pixel := _spawn_bullet_at(p, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "")
		if not pixel:
			continue
		pixel.can_delete = false
		pixel.rotate_with_direction = false
		pixel.damage = randi_range(8, 9)

		var sprite := pixel.get_node_or_null("Sprite2D") as Sprite2D
		if sprite:
			var colors := [
				Color(1, 0.39, 0.39),
				Color(0.39, 1, 0.39),
				Color(0.39, 0.39, 1),
				Color(1, 1, 0.39),
				Color(1, 0.39, 1),
				Color(0.39, 1, 1)
			]
			sprite.texture = _create_solid_texture(15, 15, colors.pick_random())
			sprite.scale = Vector2.ONE

		var cs := pixel.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs:
			var rect := RectangleShape2D.new()
			rect.size = Vector2(15, 15)
			cs.shape = rect

		pixels.append(pixel)

	await get_tree().create_timer(0.8).timeout

	var out_speed := sqrt(12.0) * 60.0
	for pixel in pixels:
		if not is_instance_valid(pixel):
			continue
		var dir := (pixel.global_position - center)
		if dir.length() <= 5.0:
			continue
		pixel.direction = dir.normalized()
		pixel.speed = out_speed

func boss5_pattern() -> void:
	var r := randf()
	if r < 0.167:
		await _boss5_throw_tnt()
	elif r < 0.334:
		await _boss5_jump_shoot()
	elif r < 0.501:
		await _boss5_heal_mode()
	elif r < 0.668:
		await _boss5_chain_explosion()
	elif r < 0.835:
		await _boss5_gravity_sink()
	else:
		await _boss5_mirror_tnt()

func _boss5_throw_tnt() -> void:
	var token := _phase_token
	for _i in range(5):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var dir := Vector2.LEFT
		var player := _get_player_safe()
		if player:
			dir = (player.global_position - global_position).normalized()
			if dir.length() == 0.0:
				dir = Vector2.LEFT

		var tnt := _spawn_bullet_at(global_position, dir, sqrt(7.0) * 60.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-12.png")
		if tnt:
			_boss5_tnt_explode_after(tnt)

		await get_tree().create_timer(0.8).timeout
		if _pattern_should_abort(token):
			return

func _boss5_tnt_explode_after(tnt: EnemyBullet) -> void:
	await get_tree().create_timer(1.5).timeout
	if not is_instance_valid(tnt) or not get_parent():
		return

	var tnt_sprite := tnt.get_node_or_null("Sprite2D") as Sprite2D
	var red_tex: Texture2D = load("res://assets/sprites/bossbullut-14.png")
	if tnt_sprite and red_tex:
		tnt_sprite.texture = red_tex

	await get_tree().create_timer(1.0).timeout
	while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
		await get_tree().create_timer(0.1).timeout

	if not is_instance_valid(tnt) or not get_parent():
		return
	var pos := tnt.global_position
	tnt.queue_free()

	var explosion := _spawn_bullet_at(pos, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-13.png")
	if not explosion:
		return
	explosion.ban_remove = true
	explosion.can_delete = false
	explosion.rotate_with_direction = false
	explosion.damage = randi_range(8, 9)

	var sprite := explosion.get_node_or_null("Sprite2D") as Sprite2D
	var cs := explosion.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var circle := CircleShape2D.new()
	circle.radius = 35.0
	if cs:
		cs.shape = circle

	if sprite:
		sprite.scale = Vector2.ONE
		sprite.modulate.a = 240.0 / 255.0

	for i in range(10):
		if not is_instance_valid(explosion):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout
		circle.radius += 4.0
		if sprite:
			sprite.scale *= 1.06
			sprite.modulate.a = maxf(0.0, sprite.modulate.a - 0.08)
		await get_tree().create_timer(0.1).timeout

	if is_instance_valid(explosion):
		explosion.queue_free()

func _boss5_jump_shoot() -> void:
	# Python: 10 curving, bouncing shots.
	var token := _phase_token
	for _i in range(10):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return
		var dir := (player.global_position - global_position)
		if dir.length() == 0.0:
			dir = Vector2.LEFT
		var bullet := _spawn_bullet_at(global_position, dir, sqrt(13.0) * 60.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-6.png")
		if bullet:
			bullet.can_return = true
			bullet.turn_rate = (-6.0 if randf() < 0.5 else 6.0)
			bullet.ban_remove = false
		await get_tree().create_timer(0.2).timeout
		if _pattern_should_abort(token):
			return

func _boss5_heal_mode() -> void:
	_boss5_heal_mode_active = true
	var heal_tex: Texture2D = load("res://assets/sprites/lightboss1.png")
	if sprite and heal_tex:
		sprite.texture = heal_tex
	await get_tree().create_timer(3.0).timeout
	_boss5_heal_mode_active = false
	_apply_boss_visual()

func _boss5_chain_explosion() -> void:
	# Python: chain of 8 explosions that advances toward the player.
	var token := _phase_token
	var player := _get_player_safe()
	if not player:
		return
	var player_pos := player.global_position

	var points: Array[Vector2] = []
	var start := global_position
	points.append(start)
	for i in range(1, 8):
		var prev := points[i - 1]
		var dir := (player_pos - prev)
		if dir.length() == 0.0:
			dir = Vector2(randf_range(-1, 1), randf_range(-1, 1))
		points.append(prev + dir.normalized() * 120.0)

	for p in points:
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var warning := _spawn_icon_hazard(p, "res://assets/sprites/error.png", 0, true)
		if warning:
			var ws := warning.get_node_or_null("Sprite2D") as Sprite2D
			if ws:
				ws.modulate = Color(1, 1, 0, 0.75)
				ws.scale = Vector2(2.0, 2.0)
		await get_tree().create_timer(0.4).timeout
		if is_instance_valid(warning):
			warning.queue_free()

		var explosion := _spawn_bullet_at(p, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-13.png")
		if explosion:
			explosion.ban_remove = true
			explosion.can_delete = false
			explosion.rotate_with_direction = false
			explosion.damage = 12

			var es := explosion.get_node_or_null("Sprite2D") as Sprite2D
			if es:
				es.scale = Vector2(1.6, 1.6)

			var cs := explosion.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if cs:
				var circle := CircleShape2D.new()
				circle.radius = 50.0
				cs.shape = circle

			_boss5_fade_and_free(explosion, 0.6)

		var bullet_speed := sqrt(8.0) * 60.0
		for deg in range(0, 360, 45):
			var angle := deg_to_rad(float(deg))
			var dir := Vector2(cos(angle), sin(angle))
			_spawn_bullet_at(p, dir, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-6.png")

func _boss5_fade_and_free(node: EnemyBullet, duration: float) -> void:
	var sprite := node.get_node_or_null("Sprite2D") as Sprite2D
	var steps := 12
	for i in range(steps):
		if not is_instance_valid(node):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout
		if sprite:
			sprite.modulate.a = lerpf(1.0, 0.0, float(i) / float(steps - 1))
		await get_tree().create_timer(duration / float(steps)).timeout
	if is_instance_valid(node):
		node.queue_free()

func _boss5_gravity_sink() -> void:
	# Python: gravity well pulling player + random shots.
	var token := _phase_token
	if not get_parent():
		return

	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	var sink_pos := Vector2(
		randf_range(300.0, maxf(300.0, viewport_size.x - 300.0)),
		randf_range(250.0, maxf(250.0, playfield_bottom - 250.0))
	)

	var sink := _spawn_bullet_at(sink_pos, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "")
	if sink:
		sink.ban_remove = true
		sink.can_delete = false
		sink.rotate_with_direction = false
		sink.damage = 0
		sink.collision_mask = 0
		var sprite := sink.get_node_or_null("Sprite2D") as Sprite2D
		if sprite:
			sprite.texture = _create_circle_texture(60, Color(0.39, 0.2, 0.78, 0.2), Color(0.55, 0.3, 0.9, 0.8), 4)
			sprite.scale = Vector2.ONE

	var start := Time.get_ticks_msec() / 1000.0
	var bullet_speed := sqrt(10.0) * 60.0
	while (Time.get_ticks_msec() / 1000.0) - start < 5.0:
		if _pattern_should_abort(token):
			break
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				break
			await get_tree().create_timer(0.1).timeout
		if _pattern_should_abort(token):
			break

		var player := _get_player_safe()
		if player:
			var to_sink := sink_pos - player.global_position
			var dist := to_sink.length()
			if dist > 10.0:
				var pull := minf(250.0 / dist, 2.5)
				player.global_position += to_sink.normalized() * pull

		if randf() < 0.4:
			var angle := deg_to_rad(float(randi_range(0, 359)))
			var dir := Vector2(cos(angle), sin(angle))
			_spawn_bullet_at(sink_pos, dir, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-6.png")

		await get_tree().create_timer(0.15).timeout
		if _pattern_should_abort(token):
			break

	if is_instance_valid(sink):
		sink.queue_free()

func _boss5_mirror_tnt() -> void:
	for _i in range(4):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		var tnt := _spawn_bullet_at(global_position, Vector2.LEFT, sqrt(8.0) * 60.0, EnemyBullet.BulletType.TRACKING, "res://assets/sprites/bossbullut-12.png")
		if tnt:
			tnt.tracking_enabled = true
			_boss5_create_mirrors_and_explode(tnt)
		await get_tree().create_timer(1.2).timeout

func _boss5_create_mirrors_and_explode(main_tnt: EnemyBullet) -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(main_tnt) or not get_parent():
		return

	var center := main_tnt.global_position
	var offsets := [Vector2(0, -80), Vector2(0, 80), Vector2(-80, 0), Vector2(80, 0)]
	var mirrors: Array[EnemyBullet] = []

	for off in offsets:
		var m := _spawn_bullet_at(center + off, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-14.png")
		if m:
			m.ban_remove = true
			m.can_delete = false
			m.rotate_with_direction = false
			m.damage = randi_range(8, 9)
			mirrors.append(m)

	var red_tex: Texture2D = load("res://assets/sprites/bossbullut-14.png")
	var ms := main_tnt.get_node_or_null("Sprite2D") as Sprite2D
	if ms and red_tex:
		ms.texture = red_tex

	await get_tree().create_timer(0.8).timeout
	while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
		await get_tree().create_timer(0.1).timeout

	var all_tnts: Array[EnemyBullet] = mirrors.duplicate()
	all_tnts.append(main_tnt)
	var bullet_speed := sqrt(12.0) * 60.0

	for t in all_tnts:
		if not is_instance_valid(t) or not get_parent():
			continue
		var p := t.global_position
		t.queue_free()

		var explosion := _spawn_bullet_at(p, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-13.png")
		if explosion:
			explosion.ban_remove = true
			explosion.can_delete = false
			explosion.rotate_with_direction = false
			explosion.damage = 10

			var es := explosion.get_node_or_null("Sprite2D") as Sprite2D
			if es:
				es.scale = Vector2(1.2, 1.2)

			var cs := explosion.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if cs:
				var circle := CircleShape2D.new()
				circle.radius = 35.0
				cs.shape = circle

			_boss5_fade_and_free(explosion, 0.6)

		for deg in range(0, 360, 30):
			var angle := deg_to_rad(float(deg))
			var dir := Vector2(cos(angle), sin(angle))
			_spawn_bullet_at(p, dir, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-6.png")

func boss6_pattern() -> void:
	match current_phase:
		1:
			shoot_triple_spiral()
		2:
			await shoot_dense_tracking()
		3:
			shoot_pentagram()
		4:
			await shoot_chaos_pattern()
		5:
			await shoot_ultimate_pattern()

func shoot_spiral_pattern(bullet_count: int, rotation_speed: float) -> void:
	var base_angle: float = movement_timer * rotation_speed
	for i in range(bullet_count):
		var angle: float = base_angle + (2.0 * PI / bullet_count) * i
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		spawn_bullet(dir, 300.0, EnemyBullet.BulletType.NORMAL)

func shoot_double_spiral() -> void:
	var base_angle: float = movement_timer * 2.0
	for i in range(12):
		var angle1: float = base_angle + (2.0 * PI / 12.0) * i
		var angle2: float = -base_angle + (2.0 * PI / 12.0) * i
		var dir1: Vector2 = Vector2(cos(angle1), sin(angle1))
		var dir2: Vector2 = Vector2(cos(angle2), sin(angle2))
		spawn_bullet(dir1, 250.0, EnemyBullet.BulletType.NORMAL)
		spawn_bullet(dir2, 350.0, EnemyBullet.BulletType.NORMAL)

func shoot_tracking_burst() -> void:
	for _i in range(2):
		spawn_bullet(Vector2.LEFT, 500.0, EnemyBullet.BulletType.TRACKING)

func shoot_triple() -> void:
	spawn_bullet(Vector2.LEFT, 400.0, EnemyBullet.BulletType.NORMAL)
	spawn_bullet(Vector2.LEFT.rotated(0.2), 400.0, EnemyBullet.BulletType.NORMAL)
	spawn_bullet(Vector2.LEFT.rotated(-0.2), 400.0, EnemyBullet.BulletType.NORMAL)

func shoot_triple_spiral() -> void:
	var base_angle: float = movement_timer * 2.5
	for spiral in range(3):
		var spiral_offset: float = (2.0 * PI / 3.0) * spiral
		for i in range(8):
			var angle: float = base_angle + spiral_offset + (2.0 * PI / 8.0) * i
			var dir: Vector2 = Vector2(cos(angle), sin(angle))
			spawn_bullet(dir, 280.0, EnemyBullet.BulletType.NORMAL)

func shoot_dense_tracking() -> void:
	for i in range(5):
		spawn_bullet(Vector2.LEFT, 450.0 + i * 50.0, EnemyBullet.BulletType.TRACKING)
		await get_tree().create_timer(0.15).timeout

func shoot_pentagram() -> void:
	for i in range(5):
		var angle: float = (2.0 * PI / 5.0) * i - PI / 2.0
		for j in range(5):
			var spread_angle: float = angle + (j - 2) * 0.15
			var spread_dir: Vector2 = Vector2(cos(spread_angle), sin(spread_angle))
			spawn_bullet(spread_dir, 320.0, EnemyBullet.BulletType.SAND)

func shoot_chaos_pattern() -> void:
	shoot_spiral_pattern(20, 3.0)
	await get_tree().create_timer(0.2).timeout
	for _i in range(3):
		spawn_bullet(Vector2.LEFT, 500.0, EnemyBullet.BulletType.TRACKING)
	await get_tree().create_timer(0.2).timeout
	shoot_circle()

func shoot_ultimate_pattern() -> void:
	shoot_triple_spiral()
	await get_tree().create_timer(0.3).timeout
	var bullet_count: int = 24
	for i in range(bullet_count):
		var angle: float = (2.0 * PI / bullet_count) * i
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		spawn_bullet(dir, 300.0, EnemyBullet.BulletType.CIRCLE)
	await get_tree().create_timer(0.3).timeout
	for _i in range(6):
		spawn_bullet(Vector2.LEFT, 550.0, EnemyBullet.BulletType.TRACKING)

func _spawn_boss_bumb(
	texture_path: String,
	speed_value: float = 13.0,
	can_return_enabled: bool = false,
	tracking_enabled_now: bool = false
) -> EnemyBullet:
	# Python parity (BossBumb): aim once at the player using tan/sample.
	var player := _get_player_safe()
	if not player:
		return null

	var origin := global_position
	var tan_sample := _calc_tan_and_sample(origin, player.global_position)
	var bullet := _spawn_python_bullet(
		origin,
		tan_sample.tan_value,
		tan_sample.sample,
		speed_value,
		EnemyBullet.BulletType.TRACKING,
		texture_path
	)
	if bullet:
		bullet.can_return = can_return_enabled
		bullet.tracking_enabled = tracking_enabled_now
	return bullet

func _boss3_thshoot() -> void:
	# Python parity (BossEnemies.py thshoot): 2x (straight bullet + aimed bullet), spaced by 0.3s.
	for _i in range(2):
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			await get_tree().create_timer(0.1).timeout

		_spawn_python_bullet(
			global_position,
			0.0,
			0,
			float(randi_range(6, 8)),
			EnemyBullet.BulletType.NORMAL,
			"res://assets/sprites/bossbullut-5.png"
		)
		_spawn_boss_bumb("res://assets/sprites/bossbullut-6.png")

		await get_tree().create_timer(0.3).timeout

func _boss5_double_shoot() -> void:
	# Python parity (BossEnemies.py doubleshoot): 2 bullets, canReturn=true, spaced by 0.2s.
	_spawn_boss_bumb("res://assets/sprites/bossbullut-11.png", 13.0, true, false)
	await get_tree().create_timer(0.2).timeout
	if is_instance_valid(self):
		_spawn_boss_bumb("res://assets/sprites/bossbullut-11.png", 13.0, true, false)

func shoot() -> void:
	can_shoot = false
	match boss_id:
		1:
			_spawn_boss_bumb("res://assets/sprites/bossbullut-1.png")
		2:
			# Python parity: Boss2 main shot is a tracking bullet (speed=8, get=True).
			_spawn_boss_bumb("res://assets/sprites/bossbullut-3.png", 8.0, false, true)
		3:
			await _boss3_thshoot()
		4:
			_spawn_boss_bumb("res://assets/sprites/bossbullut-10.png")
		5:
			await _boss5_double_shoot()
		6:
			_spawn_boss_bumb("res://assets/sprites/bossbullut-1.png")
		_:
			_spawn_boss_bumb("res://assets/sprites/bossbullut-1.png")
