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

	# Touhou-like: spell bonus decreases from the start at a constant rate.
	# We clamp to a non-zero minimum so timeouts still award a small remainder.
	var now_sec := Time.get_ticks_msec() / 1000.0
	var elapsed := maxf(0.0, now_sec - phase_start_real_sec)

	var ratio := clampf(elapsed / maxf(0.01, phase_time_limit_sec), 0.0, 1.0)
	# End at ~1/7 of the starting value at time-out (common Touhou baseline).
	var value := int(round(float(spell_bonus_start) * (1.0 - (6.0 / 7.0) * ratio)))
	var min_value := int(round(float(spell_bonus_start) / 7.0))
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
	# Midboss should be shorter than the stage boss and have at most 2 spell cards.
	var stage := 1
	if StageManager:
		stage = maxi(1, int(StageManager.current_stage))
	var spell_count := 1
	if stage >= 4:
		spell_count = 2

	var hp_weights: Array[float] = [0.56, 0.44]
	if spell_count >= 2:
		hp_weights = [0.50, 0.25, 0.25]
	var hps := _alloc_phase_hp(total_hp, hp_weights)

	var nonspell_pool: Array[Callable] = []
	var spell1_pool: Array[Callable] = []
	var spell2_pool: Array[Callable] = []

	match boss_id:
		1:
			nonspell_pool = [
				Callable(self, "_boss1_nonspell_step"),
				Callable(self, "_boss1_sand_shoot"),
				Callable(self, "_boss1_shoot_aside"),
				Callable(self, "_boss1_dune_wave"),
				Callable(self, "_boss1_mirage_burst"),
				Callable(self, "_special_wave_wall")
			]
			spell1_pool = [
				Callable(self, "_boss1_star_shoot"),
				Callable(self, "_boss1_lightning_chain"),
				Callable(self, "_boss1_mirror_shoot"),
				Callable(self, "_boss1_desert_storm"),
				Callable(self, "_boss1_sandstorm_vortex"),
				Callable(self, "_special_spiral_madness")
			]
			spell2_pool = [
				Callable(self, "_boss1_black_hole"),
				Callable(self, "_boss1_spiral_trap"),
				Callable(self, "_boss1_lightning_chain"),
				Callable(self, "_boss1_star_constellation"),
				Callable(self, "_boss1_desert_storm"),
				Callable(self, "_special_accelerate_burst")
			]
		2:
			nonspell_pool = [
				Callable(self, "_boss2_nonspell_step"),
				Callable(self, "_boss2_generate_love"),
				Callable(self, "_boss2_heart_trap"),
				Callable(self, "_boss2_heart_orbit_dive"),
				Callable(self, "_boss2_love_rain"),
				Callable(self, "_special_butterfly_swarm")
			]
			spell1_pool = [
				Callable(self, "_boss2_use_attract"),
				Callable(self, "_boss2_heart_rain"),
				Callable(self, "_boss2_reverse_time"),
				Callable(self, "_boss2_love_explosion"),
				Callable(self, "_boss2_cupid_arrows"),
				Callable(self, "_special_homing_hell")
			]
			spell2_pool = [
				Callable(self, "_boss2_split_bomb"),
				Callable(self, "_boss2_heart_orbit_dive"),
				Callable(self, "_boss2_use_attract"),
				Callable(self, "_boss2_passion_spiral"),
				Callable(self, "_boss2_heart_constellation"),
				Callable(self, "_special_split_bomb")
			]
		3:
			nonspell_pool = [
				Callable(self, "_boss3_nonspell_step"),
				Callable(self, "_boss3_super_shoot"),
				Callable(self, "_boss3_time_lock_ring"),
				Callable(self, "_boss3_temporal_grid"),
				Callable(self, "_special_decelerate_trap")
			]
			spell1_pool = [
				Callable(self, "_boss3_time_stop"),
				Callable(self, "_boss3_time_bubble"),
				Callable(self, "_boss3_golden_storm"),
				Callable(self, "_boss3_time_spiral"),
				Callable(self, "_boss3_clock_burst"),
				Callable(self, "_special_spiral_madness")
			]
			spell2_pool = [
				Callable(self, "_boss3_time_bubble"),
				Callable(self, "_boss3_time_lock_ring"),
				Callable(self, "_boss3_coin_barrage"),
				Callable(self, "_boss3_golden_galaxy"),
				Callable(self, "_boss3_time_freeze_pattern"),
				Callable(self, "_special_accelerate_burst")
			]
		4:
			nonspell_pool = [
				Callable(self, "_boss4_light_single"),
				Callable(self, "_boss4_drag_shoot"),
				Callable(self, "_boss4_side_shoot"),
				Callable(self, "_boss4_pixel_burst"),
				Callable(self, "_special_wave_wall")
			]
			spell1_pool = [
				Callable(self, "_boss4_screen_static"),
				Callable(self, "_boss4_light_shoot"),
				Callable(self, "_boss4_orbital_strike"),
				Callable(self, "_boss4_laser_cross"),
				Callable(self, "_boss4_screen_sweep"),
				Callable(self, "_special_laser_cross")
			]
			spell2_pool = [
				Callable(self, "_boss4_pixel_storm"),
				Callable(self, "_boss4_orbital_strike"),
				Callable(self, "_boss4_screen_static"),
				Callable(self, "_boss4_digital_rain"),
				Callable(self, "_boss4_light_prism"),
				Callable(self, "_special_bounce_chaos")
			]
		5:
			nonspell_pool = [
				Callable(self, "_boss5_throw_tnt"),
				Callable(self, "_boss5_jump_shoot"),
				Callable(self, "_boss5_chain_explosion"),
				Callable(self, "_boss5_demolition_wave"),
				Callable(self, "_special_accelerate_burst")
			]
			spell1_pool = [
				Callable(self, "_boss5_gravity_sink"),
				Callable(self, "_boss5_heal_mode"),
				Callable(self, "_boss5_mirror_tnt"),
				Callable(self, "_boss5_mega_explosion"),
				Callable(self, "_boss5_firework_show"),
				Callable(self, "_special_split_bomb")
			]
			spell2_pool = [
				Callable(self, "_boss5_chain_explosion"),
				Callable(self, "_boss5_gravity_sink"),
				Callable(self, "_boss5_throw_tnt"),
				Callable(self, "_boss5_chain_reaction"),
				Callable(self, "_boss5_tnt_barrage"),
				Callable(self, "_special_bounce_chaos")
			]
		6:
			nonspell_pool = [
				Callable(self, "_boss6_phase1_fire_rain"),
				Callable(self, "shoot_double_spiral"),
				Callable(self, "shoot_tracking_burst"),
				Callable(self, "_boss6_ultimate_spiral"),
				Callable(self, "_boss6_divine_cross"),
				Callable(self, "_special_butterfly_swarm"),
				Callable(self, "_special_wave_wall")
			]
			spell1_pool = [
				Callable(self, "_boss6_spell1_spiral_fire"),
				Callable(self, "shoot_pentagram"),
				Callable(self, "shoot_chaos_pattern"),
				Callable(self, "_boss6_galaxy_burst"),
				Callable(self, "_boss6_final_judgment"),
				Callable(self, "_special_spiral_madness"),
				Callable(self, "_special_split_bomb"),
				Callable(self, "_special_homing_hell")
			]
			spell2_pool = [
				Callable(self, "_boss6_spell2_cross_laser"),
				Callable(self, "shoot_ultimate_pattern"),
				Callable(self, "shoot_dense_tracking"),
				Callable(self, "_boss6_chaos_dimension"),
				Callable(self, "_boss6_eternal_spiral"),
				Callable(self, "_boss6_apocalypse"),
				Callable(self, "_special_laser_cross"),
				Callable(self, "_special_accelerate_burst"),
				Callable(self, "_special_bounce_chaos"),
				Callable(self, "_special_ultimate_chaos")
			]
		_:
			nonspell_pool = [Callable(self, "_boss1_nonspell_step")]
			spell1_pool = [Callable(self, "_boss1_star_shoot")]
			spell2_pool = [Callable(self, "_boss1_black_hole")]

	if nonspell_pool.is_empty():
		nonspell_pool = [Callable(self, "_boss1_nonspell_step")]
	if spell1_pool.is_empty():
		spell1_pool = [Callable(self, "_boss1_star_shoot")]
	if spell2_pool.is_empty():
		spell2_pool = spell1_pool

	var phases: Array[BossPhaseDef] = []
	phases.append(_make_phase_mix(PhaseKind.NONSPELL, "Mid Nonspell", hps[0], 35.0, 0.65, 0.50, 0.9, nonspell_pool[0], nonspell_pool))
	phases.append(_make_phase_mix(PhaseKind.SPELL, "Mid Spell 1", hps[1], 45.0, 0.0, 0.40, 1.1, spell1_pool[0], spell1_pool))
	if spell_count >= 2 and hps.size() >= 3:
		phases.append(_make_phase_mix(PhaseKind.SPELL, "Mid Spell 2", hps[2], 48.0, 0.0, 0.38, 1.2, spell2_pool[0], spell2_pool, PatternPoolMode.CYCLE))
	return phases

func _build_boss1_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])

	# Nonspell 1: Desert Opening - 5 unique skills
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss1_sandstorm_prelude"),
		Callable(self, "_boss1_desert_wind"),
		Callable(self, "_boss1_sand_ripples"),
		Callable(self, "_boss1_dune_cascade"),
		Callable(self, "_boss1_mirage_shimmer")
	]

	# Spell 1: Lightning Storm - 5 unique skills (keep lightning_chain)
	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss1_lightning_chain"),
		Callable(self, "_boss1_thunder_spiral"),
		Callable(self, "_boss1_storm_vortex"),
		Callable(self, "_boss1_electric_web"),
		Callable(self, "_boss1_plasma_burst")
	]

	# Nonspell 2: Sand Serpents - 5 unique skills (keep sand_snakes)
	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss1_sand_snakes"),
		Callable(self, "_boss1_serpent_coil"),
		Callable(self, "_boss1_viper_strike"),
		Callable(self, "_boss1_cobra_dance"),
		Callable(self, "_boss1_python_crush")
	]

	# Spell 2: Gravity Manipulation - 5 unique skills (keep black_hole)
	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss1_black_hole"),
		Callable(self, "_boss1_gravity_lens"),
		Callable(self, "_boss1_event_horizon_ring"),
		Callable(self, "_boss1_spacetime_tear"),
		Callable(self, "_boss1_singularity_burst")
	]

	# Final: Ultimate Combinations - 5 unique skills
	var final_pool: Array[Callable] = [
		Callable(self, "_boss1_desert_apocalypse"),
		Callable(self, "_boss1_cosmic_mirage"),
		Callable(self, "_boss1_eternal_storm"),
		Callable(self, "_boss1_void_serpent"),
		Callable(self, "_boss1_cataclysm")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Sandstorm Prelude", hps[0], 38.0, 0.6, 0.45, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Chain Lightning", hps[1], 55.0, 0.0, 0.35, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Mirage Snakes", hps[2], 38.0, 0.55, 0.45, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Singularity Pull", hps[3], 60.0, 0.0, 0.35, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Event Horizon", hps[4], 70.0, 0.45, 0.30, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _boss1_nonspell_step() -> void:
	# Simple Touhou-like opening: aimed spread + occasional ring.
	_touhou_aimed_spread("res://assets/sprites/bossbullut-1.png", 8.0, 5, 26.0)
	if randf() < 0.35:
		_touhou_ring("res://assets/sprites/bossbullut-2.png", 14, 6.5)

func _boss1_sand_snakes() -> void:
	# Boss1 signature: curving "sand snakes" with wave drift.
	var token := _phase_token
	var bullet_speed := 7.0 * 60.0
	for i in range(30):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return
		var to_player := player.global_position - global_position
		if to_player.length() == 0.0:
			to_player = Vector2.LEFT
		var base_angle := to_player.angle()
		var angle := base_angle + deg_to_rad(randf_range(-18.0, 18.0))
		var dir := Vector2(cos(angle), sin(angle))

		var b := _spawn_bullet_at(global_position, dir, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-2.png")
		if b:
			b.rotate_with_direction = false
			b.turn_rate = deg_to_rad(randf_range(90.0, 140.0)) * (-1.0 if (i % 2) == 0 else 1.0)
			b.wave_amplitude = 22.0
			b.wave_frequency = 8.0
			b.wave_phase = randf_range(0.0, TAU)
			b.spin_speed = deg_to_rad(220.0) * (-1.0 if (i % 2) == 0 else 1.0)

		await get_tree().create_timer(0.08).timeout

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

	# Nonspell 1: Love Opening - 5 unique skills
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss2_heartbeat_pulse"),
		Callable(self, "_boss2_cupid_arrows_aimed"),
		Callable(self, "_boss2_love_shower"),
		Callable(self, "_boss2_affection_wave"),
		Callable(self, "_boss2_romance_spiral")
	]

	# Spell 1: Attraction Field - 5 unique skills
	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss2_attraction_field"),
		Callable(self, "_boss2_magnetic_hearts"),
		Callable(self, "_boss2_gravity_embrace"),
		Callable(self, "_boss2_love_vortex"),
		Callable(self, "_boss2_passion_pull")
	]

	# Nonspell 2: Heart Rain - 5 unique skills (keep heart_rain)
	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss2_heart_rain"),
		Callable(self, "_boss2_valentine_storm"),
		Callable(self, "_boss2_love_letter_cascade"),
		Callable(self, "_boss2_rose_petal_fall"),
		Callable(self, "_boss2_confession_barrage")
	]

	# Spell 2: Time Reversal - 5 unique skills (keep reverse_time)
	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss2_reverse_time"),
		Callable(self, "_boss2_time_rewind_spiral"),
		Callable(self, "_boss2_temporal_echo"),
		Callable(self, "_boss2_causality_break"),
		Callable(self, "_boss2_paradox_loop")
	]

	# Final: Ultimate Love - 5 unique skills (keep made_in_heaven)
	var final_pool: Array[Callable] = [
		Callable(self, "_boss2_made_in_heaven"),
		Callable(self, "_boss2_eternal_love"),
		Callable(self, "_boss2_heaven_ascension"),
		Callable(self, "_boss2_divine_romance"),
		Callable(self, "_boss2_love_transcendent")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Heartbeat Barrage", hps[0], 45.0, 0.65, 0.45, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Attraction Field", hps[1], 60.0, 0.0, 0.34, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Heaven's Pulse", hps[2], 45.0, 0.6, 0.45, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Reverse Romance", hps[3], 62.0, 0.0, 0.34, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Made in Heaven", hps[4], 78.0, 0.5, 0.28, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _boss2_nonspell_step() -> void:
	_touhou_aimed_spread("res://assets/sprites/bossbullut-3.png", 7.5, 5, 22.0)
	if randf() < 0.4:
		_touhou_ring("res://assets/sprites/bossbullut-4.png", 16, 5.0)

func _boss2_heart_sine_lanes() -> void:
	# Boss2 signature: heart lanes with sine-wave drift (love beats).
	var token := _phase_token
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var lanes := 7
	var top := 90.0
	var bottom := maxf(top + 40.0, playfield_bottom - 150.0)
	var span := maxf(1.0, bottom - top)
	var lane_total := maxi(3, lanes)

	var waves := 6
	var speed_tick := 9.0
	var wave_amp := 44.0
	var wave_freq := 4.4

	for w in range(waves):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var phase_offset := (span / float(lane_total)) * float(w) * 0.8
		for i in range(lane_total):
			var t := float(i) / float(maxi(1, lane_total - 1))
			var y := top + span * t
			y = wrapf(y + phase_offset, top, bottom)
			var spawn_pos := Vector2(viewport_size.x + 60.0, y)
			var b := _spawn_bullet_at(spawn_pos, Vector2.LEFT, speed_tick * 60.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-4.png")
			if b:
				b.rotate_with_direction = false
				b.wave_amplitude = wave_amp
				b.wave_frequency = wave_freq
				b.wave_phase = randf_range(0.0, TAU)

		await get_tree().create_timer(0.55).timeout

func _build_boss3_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])

	# Nonspell 1: Clockwork Opening - 5 unique skills
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss3_clockwork_tick"),
		Callable(self, "_boss3_second_hand_sweep"),
		Callable(self, "_boss3_minute_markers"),
		Callable(self, "_boss3_hour_chime"),
		Callable(self, "_boss3_pendulum_swing")
	]

	# Spell 1: Golden Storm - 5 unique skills (keep golden_storm)
	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss3_golden_storm"),
		Callable(self, "_boss3_treasure_rain"),
		Callable(self, "_boss3_wealth_spiral"),
		Callable(self, "_boss3_fortune_wheel"),
		Callable(self, "_boss3_jackpot_burst")
	]

	# Nonspell 2: Time Lock - 5 unique skills (keep time_lock_ring)
	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss3_time_lock_ring"),
		Callable(self, "_boss3_stasis_field"),
		Callable(self, "_boss3_temporal_prison"),
		Callable(self, "_boss3_frozen_moment"),
		Callable(self, "_boss3_time_dilation")
	]

	# Spell 2: Time Stop - 5 unique skills (keep time_stop)
	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss3_time_stop"),
		Callable(self, "_boss3_world_freeze"),
		Callable(self, "_boss3_stopped_time_knives"),
		Callable(self, "_boss3_time_erase"),
		Callable(self, "_boss3_king_crimson")
	]

	# Final: Ultimate Time - 5 unique skills
	var final_pool: Array[Callable] = [
		Callable(self, "_boss3_time_collapse"),
		Callable(self, "_boss3_temporal_singularity"),
		Callable(self, "_boss3_chronos_wrath"),
		Callable(self, "_boss3_eternity_end"),
		Callable(self, "_boss3_omega_timeline")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Clockwork Prelude", hps[0], 45.0, 0.6, 0.45, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Golden Storm", hps[1], 62.0, 0.0, 0.34, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Coin Barrage", hps[2], 45.0, 0.55, 0.45, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "ZA WARUDO", hps[3], 65.0, 0.0, 0.34, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Time Collapse", hps[4], 82.0, 0.5, 0.28, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _boss3_nonspell_step() -> void:
	_touhou_aimed_spread("res://assets/sprites/bossbullut-6.png", 9.5, 5, 24.0)
	if randf() < 0.25:
		_touhou_ring("res://assets/sprites/bossbullut-5.png", 18, 6.5)

func _boss3_time_lock_mines() -> void:
	# Boss3 signature: bullets "freeze" in place, then dash (time lock mines).
	var token := _phase_token
	var player := _get_player_safe()
	if not player:
		return

	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var scale := clampf(boss_bullet_speed_scale, 0.05, 5.0)
	var dash_speed := 12.5 * 60.0 * scale

	for ring_idx in range(3):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		player = _get_player_safe()
		if not player:
			return
		var center := player.global_position

		var radius := 150.0 + float(ring_idx) * 75.0
		var count := 18 + ring_idx * 4
		var base := randf_range(0.0, TAU)
		for i in range(count):
			var angle := base + (TAU / float(count)) * float(i)
			var pos := center + Vector2(cos(angle), sin(angle)) * radius

			var target := center + Vector2(randf_range(-90.0, 90.0), randf_range(-90.0, 90.0))
			target.x = clampf(target.x, 70.0, viewport_size.x - 70.0)
			target.y = clampf(target.y, 70.0, playfield_bottom - 70.0)

			var b := _spawn_bullet_at(pos, Vector2.ZERO, 0.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-6.png")
			if b:
				b.direction = Vector2.ZERO
				b.rotate_with_direction = false
				b.spin_speed = deg_to_rad(randf_range(-360.0, 360.0))
				# Reuse orbit mechanic with radius=0 to "hold" the bullet in place.
				b.orbit_center = pos
				b.orbit_radius = 0.0
				b.orbit_angle = 0.0
				b.orbit_angular_speed = 0.0
				b.orbit_time_left = randf_range(0.55, 1.75)
				b.dash_after_orbit = true
				b.dash_target = target
				b.dash_speed = dash_speed * randf_range(0.85, 1.15)

		await get_tree().create_timer(0.35).timeout

func _build_boss4_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])

	# Nonspell 1: Tech Opening - 5 unique skills
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss4_warning_beams"),
		Callable(self, "_boss4_scan_lines"),
		Callable(self, "_boss4_pixel_grid"),
		Callable(self, "_boss4_screen_flicker"),
		Callable(self, "_boss4_static_noise")
	]

	# Spell 1: Signal Interference - 5 unique skills
	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss4_signal_interference"),
		Callable(self, "_boss4_glitch_cascade"),
		Callable(self, "_boss4_corrupted_data"),
		Callable(self, "_boss4_buffer_overflow"),
		Callable(self, "_boss4_packet_storm")
	]

	# Nonspell 2: UFO Patrol - 5 unique skills (keep ufo_patrol if exists, or use summon_ufo)
	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss4_summon_ufo"),
		Callable(self, "_boss4_drone_swarm"),
		Callable(self, "_boss4_satellite_orbit"),
		Callable(self, "_boss4_probe_scan"),
		Callable(self, "_boss4_alien_formation")
	]

	# Spell 2: Orbital Strike - 5 unique skills (keep orbital_strike)
	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss4_orbital_strike"),
		Callable(self, "_boss4_satellite_laser"),
		Callable(self, "_boss4_space_bombardment"),
		Callable(self, "_boss4_ion_cannon"),
		Callable(self, "_boss4_plasma_rain")
	]

	# Final: Ultimate Tech - 5 unique skills
	var final_pool: Array[Callable] = [
		Callable(self, "_boss4_pixel_apocalypse"),
		Callable(self, "_boss4_system_crash"),
		Callable(self, "_boss4_digital_armageddon"),
		Callable(self, "_boss4_singularity_upload"),
		Callable(self, "_boss4_matrix_collapse")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Warning Beams", hps[0], 45.0, 0.6, 0.45, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Signal Interference", hps[1], 62.0, 0.0, 0.34, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "UFO Patrol", hps[2], 45.0, 0.55, 0.45, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Orbital Strike", hps[3], 65.0, 0.0, 0.34, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Pixel Apocalypse", hps[4], 85.0, 0.5, 0.28, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _build_boss5_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])

	# Nonspell 1: TNT Opening - 5 unique skills
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss5_tnt_toss"),
		Callable(self, "_boss5_firecracker_spray"),
		Callable(self, "_boss5_sparkler_spin"),
		Callable(self, "_boss5_cherry_bomb_bounce"),
		Callable(self, "_boss5_smoke_screen")
	]

	# Spell 1: Gravity Sink - 5 unique skills (keep gravity_sink)
	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss5_gravity_sink"),
		Callable(self, "_boss5_implosion_burst"),
		Callable(self, "_boss5_vacuum_bomb"),
		Callable(self, "_boss5_singularity_det"),
		Callable(self, "_boss5_collapse_nova")
	]

	# Nonspell 2: Chain Explosion - 5 unique skills (keep chain_explosion)
	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss5_chain_explosion"),
		Callable(self, "_boss5_domino_blast"),
		Callable(self, "_boss5_cascade_detonation"),
		Callable(self, "_boss5_sympathetic_det"),
		Callable(self, "_boss5_avalanche_boom")
	]

	# Spell 2: Mirror TNT - 5 unique skills (keep mirror_tnt)
	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss5_mirror_tnt"),
		Callable(self, "_boss5_kaleidoscope_blast"),
		Callable(self, "_boss5_reflection_bomb"),
		Callable(self, "_boss5_prism_burst"),
		Callable(self, "_boss5_fractal_detonation")
	]

	# Final: Ultimate Explosion - 5 unique skills (keep bakuretsu_finale)
	var final_pool: Array[Callable] = [
		Callable(self, "_boss5_bakuretsu_finale"),
		Callable(self, "_boss5_nuclear_option"),
		Callable(self, "_boss5_armageddon_blast"),
		Callable(self, "_boss5_supernova"),
		Callable(self, "_boss5_big_bang")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "TNT Parade", hps[0], 45.0, 0.6, 0.45, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Gravity Sink", hps[1], 62.0, 0.0, 0.34, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Chain Detonation", hps[2], 45.0, 0.55, 0.45, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Cursed Regeneration", hps[3], 68.0, 0.0, 0.34, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Bakuretsu Finale", hps[4], 92.0, 0.5, 0.28, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _build_boss6_phases(total_hp: int) -> Array[BossPhaseDef]:
	# Boss6 in the original pygame project is a multi-phase "final boss".
	# Here we keep Touhou-like NONSPELL/SPELL alternation with 5 bars.
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss6_phase1_fire_rain"),
		Callable(self, "_boss6_ultimate_spiral"),
		Callable(self, "_boss6_hellfire_rain"),
		Callable(self, "_boss6_inferno_spiral"),
		Callable(self, "_boss6_flame_wheel"),
		Callable(self, "_boss6_ember_scatter"),
		Callable(self, "_boss6_blaze_wave"),
		Callable(self, "_boss6_fire_serpent"),
		Callable(self, "_boss6_magma_burst"),
		Callable(self, "_boss6_volcanic_eruption"),
		Callable(self, "_boss6_heat_haze"),
		Callable(self, "_boss6_pyroclastic_flow")
	]

	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss6_spell1_spiral_fire"),
		Callable(self, "_boss6_galaxy_burst"),
		Callable(self, "_boss6_pentagram_seal"),
		Callable(self, "_boss6_hexagram_bind"),
		Callable(self, "_boss6_sacred_geometry"),
		Callable(self, "_boss6_runic_circle"),
		Callable(self, "_boss6_sigil_storm"),
		Callable(self, "_boss6_arcane_web"),
		Callable(self, "_boss6_mystic_spiral"),
		Callable(self, "_boss6_enchant_ring"),
		Callable(self, "_boss6_spell_weave"),
		Callable(self, "_boss6_grimoire_page")
	]

	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss6_phase3_cone_and_teleport"),
		Callable(self, "_boss6_chaos_dimension"),
		Callable(self, "_boss6_convergence_beam"),
		Callable(self, "_boss6_cross_fire"),
		Callable(self, "_boss6_pincer_attack"),
		Callable(self, "_boss6_encirclement"),
		Callable(self, "_boss6_vortex_pull"),
		Callable(self, "_boss6_dimension_rift"),
		Callable(self, "_boss6_gravity_well"),
		Callable(self, "_boss6_time_warp_bullets"),
		Callable(self, "_boss6_mirror_dimension"),
		Callable(self, "_boss6_phase_shift")
	]

	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss6_spell2_cross_laser"),
		Callable(self, "_boss6_divine_cross"),
		Callable(self, "_boss6_cathedral_pillars"),
		Callable(self, "_boss6_stained_glass"),
		Callable(self, "_boss6_holy_cross"),
		Callable(self, "_boss6_divine_judgment_aimed"),
		Callable(self, "_boss6_angel_wings"),
		Callable(self, "_boss6_heaven_gate"),
		Callable(self, "_boss6_sacred_arrow"),
		Callable(self, "_boss6_blessing_rain"),
		Callable(self, "_boss6_choir_of_light"),
		Callable(self, "_boss6_sanctuary_seal")
	]

	var final_pool: Array[Callable] = [
		Callable(self, "_boss6_final_inferno"),
		Callable(self, "_boss6_final_judgment"),
		Callable(self, "_boss6_eternal_spiral"),
		Callable(self, "_boss6_apocalypse"),
		Callable(self, "_boss6_ragnarok"),
		Callable(self, "_boss6_genesis_wave"),
		Callable(self, "_boss6_void_collapse"),
		Callable(self, "_boss6_cosmic_storm"),
		Callable(self, "_boss6_eternal_flame"),
		Callable(self, "_boss6_omega_burst"),
		Callable(self, "_boss6_armageddon_rain"),
		Callable(self, "_boss6_final_revelation")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Inferno Overture", hps[0], 55.0, 0.5, 0.34, 1.0, nonspell_1_pool[0], nonspell_1_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.SPELL, "Pentagram Blaze", hps[1], 72.0, 0.0, 0.26, 1.2, spell_1_pool[0], spell_1_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.NONSPELL, "Teleport Convergence", hps[2], 58.0, 0.45, 0.32, 1.0, nonspell_2_pool[0], nonspell_2_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.SPELL, "Cross Laser Cathedral", hps[3], 78.0, 0.0, 0.24, 1.2, spell_2_pool[0], spell_2_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.FINAL, "Apocalypse Symphony", hps[4], 110.0, 0.4, 0.20, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
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
		var b := _spawn_bullet_at(global_position, dir, sqrt(12.0) * 60.0, EnemyBullet.BulletType.HOMING, "res://assets/sprites/bossbullut-6.png")
		if b:
			b._homing_strength = 2.5
			b._homing_duration = 1.0
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
		var bullet := _spawn_bullet_at(global_position, dir, sqrt(8.0) * 60.0, EnemyBullet.BulletType.HOMING, "res://assets/sprites/bossbullut-4.png")
		if bullet:
			bullet._homing_strength = 2.5
			bullet._homing_duration = 1.0
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
		await _boss4_light_shoot()
	elif r < 0.286:
		await _boss4_drag_shoot()
	elif r < 0.429:
		await _boss4_summon_ufo()
	elif r < 0.572:
		await _boss4_side_shoot()
	elif r < 0.715:
		await _boss4_screen_static()
	elif r < 0.858:
		await _boss4_orbital_strike()
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

func _boss4_glitch_packets() -> void:
	# Boss4 signature: glitch packets (high-frequency wave drift).
	var token := _phase_token
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	for _burst in range(8):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		for _i in range(10):
			var y := randf_range(90.0, maxf(90.0, playfield_bottom - 140.0))
			var x := viewport_size.x + randf_range(20.0, 140.0)
			var dir := Vector2.LEFT.rotated(deg_to_rad(randf_range(-12.0, 12.0)))
			var b := _spawn_bullet_at(Vector2(x, y), dir, 8.0 * 60.0, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/error.png")
			if b:
				b.rotate_with_direction = false
				b.spin_speed = deg_to_rad(randf_range(-720.0, 720.0))
				b.wave_amplitude = randf_range(10.0, 26.0)
				b.wave_frequency = randf_range(14.0, 22.0)
				b.wave_phase = randf_range(0.0, TAU)
				b.turn_rate = deg_to_rad(randf_range(-70.0, 70.0)) * 0.35
				b.damage = randi_range(7, 9)

		await get_tree().create_timer(0.32).timeout

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
			var t0 := turrets[0]
			var t1 := turrets[1]
			var t2 := turrets[2]
			var t3 := turrets[3]
			# Phase transitions can clear enemy bullets; guard against freed turret nodes.
			if is_instance_valid(t0):
				t0.global_position.y -= 8.0
			if is_instance_valid(t1):
				t1.global_position.y += 8.0
			if is_instance_valid(t2):
				t2.global_position.y -= 8.0
			if is_instance_valid(t3):
				t3.global_position.y += 8.0
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
	var token := _phase_token
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

	# Move+shoot in one coroutine to avoid "fire and forget" coroutine pitfalls.
	# 80 frames @0.1s ~= 8s, shooting every 0.25s ~= 30 volleys.
	var bullet_speed := sqrt(10.0) * 60.0
	var shoot_accum := 0.0
	for _frame in range(80):
		if _pattern_should_abort(token):
			break
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				break
			await get_tree().create_timer(0.1).timeout
		if _pattern_should_abort(token):
			break

		# Move along the playfield bounds.
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

		# Shoot every 0.25s.
		shoot_accum += 0.1
		if shoot_accum >= 0.25:
			shoot_accum = 0.0
			var player := _get_player_safe()
			if player:
				for ufo in ufos:
					if not is_instance_valid(ufo):
						continue
					var dir := (player.global_position - ufo.global_position)
					if dir.length() == 0.0:
						dir = Vector2.LEFT
					_spawn_bullet_at(ufo.global_position, dir, bullet_speed, EnemyBullet.BulletType.NORMAL, "res://assets/sprites/bossbullut-10.png")

		await get_tree().create_timer(0.1).timeout

	# Cleanup
	for ufo in ufos:
		if is_instance_valid(ufo):
			ufo.queue_free()

func _boss4_orbital_move(token: int, ufos: Array[EnemyBullet], left_bound: float, right_bound: float, top_bound: float, bottom_bound: float) -> void:
	# 80 frames, step every 0.1s.
	for _frame in range(80):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

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

func _boss4_orbital_shoot(token: int, ufos: Array[EnemyBullet]) -> void:
	var bullet_speed := sqrt(10.0) * 60.0
	for _i in range(30):
		if _pattern_should_abort(token):
			return
		if not is_instance_valid(self) or not get_parent():
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
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

		var tnt := _spawn_bullet_at(global_position, Vector2.LEFT, sqrt(8.0) * 60.0, EnemyBullet.BulletType.HOMING, "res://assets/sprites/bossbullut-12.png")
		if tnt:
			tnt._homing_strength = 2.5
			tnt._homing_duration = 1.0
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

# ============================================================================
# 东方Project风格的花哨弹幕模式
# ============================================================================

# 花瓣弹幕 - 环形散射
func _danmaku_flower_pattern(bullet_count: int = 16, radius: float = 0.0, speed: float = 10.0, sprite: String = "res://assets/sprites/bossbullut-1.png") -> void:
	var angle_step = TAU / bullet_count
	for i in range(bullet_count):
		var angle = angle_step * i
		var spawn_pos = global_position
		if radius > 0:
			spawn_pos += Vector2(cos(angle), sin(angle)) * radius
		_spawn_python_bullet(spawn_pos, angle, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)

# 螺旋弹幕
func _danmaku_spiral(arms: int = 3, bullets_per_arm: int = 8, angle_offset: float = 0.0, speed: float = 8.0, sprite: String = "res://assets/sprites/bossbullut-3.png") -> void:
	var angle_step = TAU / arms
	for arm in range(arms):
		for bullet in range(bullets_per_arm):
			var angle = angle_step * arm + angle_offset + (bullet * 0.2)
			_spawn_python_bullet(global_position, angle, 0, speed + bullet * 0.5, EnemyBullet.BulletType.NORMAL, sprite)
			await get_tree().create_timer(0.05).timeout

# 米字弹幕 - 8方向直线
func _danmaku_cross_pattern(lines: int = 8, bullets_per_line: int = 5, spacing: float = 30.0, speed: float = 9.0, sprite: String = "res://assets/sprites/bossbullut-5.png") -> void:
	var angle_step = TAU / lines
	for i in range(lines):
		var angle = angle_step * i
		for j in range(bullets_per_line):
			var offset = Vector2(cos(angle), sin(angle)) * spacing * j
			_spawn_python_bullet(global_position + offset, angle, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)

# 扇形弹幕
func _danmaku_fan(bullet_count: int = 12, spread_angle: float = PI/2, direction: float = PI/2, speed: float = 10.0, sprite: String = "res://assets/sprites/bossbullut-6.png") -> void:
	var start_angle = direction - spread_angle / 2
	var angle_step = spread_angle / (bullet_count - 1) if bullet_count > 1 else 0
	for i in range(bullet_count):
		var angle = start_angle + angle_step * i
		_spawn_python_bullet(global_position, angle, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)

# 波浪墙弹幕
func _danmaku_wave_wall(waves: int = 3, bullets_per_wave: int = 10, wave_delay: float = 0.15, speed: float = 7.0, sprite: String = "res://assets/sprites/bossbullut-10.png") -> void:
	for wave in range(waves):
		var angle_offset = wave * 0.3
		for i in range(bullets_per_wave):
			var angle = PI/2 + sin(i * 0.5 + angle_offset) * 0.5
			var x_offset = (i - bullets_per_wave / 2.0) * 40
			_spawn_python_bullet(global_position + Vector2(x_offset, 0), angle, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)
		await get_tree().create_timer(wave_delay).timeout

# 随机散射弹幕
func _danmaku_random_spray(bullet_count: int = 20, speed_min: float = 6.0, speed_max: float = 12.0, sprite: String = "res://assets/sprites/bossbullut-1.png") -> void:
	for i in range(bullet_count):
		var angle = randf() * TAU
		var speed = randf_range(speed_min, speed_max)
		_spawn_python_bullet(global_position, angle, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)
		await get_tree().create_timer(0.03).timeout

# 旋转螺旋塔
func _danmaku_rotating_spiral_tower(rotations: int = 3, bullets_per_rotation: int = 12, rotation_speed: float = 0.3, speed: float = 8.0, sprite: String = "res://assets/sprites/bossbullut-3.png") -> void:
	var total_bullets = rotations * bullets_per_rotation
	var angle_step = (TAU * rotations) / total_bullets
	for i in range(total_bullets):
		var angle = angle_step * i
		_spawn_python_bullet(global_position, angle, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)
		await get_tree().create_timer(rotation_speed / bullets_per_rotation).timeout

# 双螺旋
func _danmaku_double_helix(bullets: int = 20, rotation_offset: float = PI, speed: float = 9.0, sprite: String = "res://assets/sprites/bossbullut-5.png") -> void:
	var angle_step = TAU / bullets
	for i in range(bullets):
		var angle1 = angle_step * i
		var angle2 = angle1 + rotation_offset
		_spawn_python_bullet(global_position, angle1, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)
		_spawn_python_bullet(global_position, angle2, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)
		await get_tree().create_timer(0.05).timeout

# 爆炸环形弹幕
func _danmaku_explosion_ring(rings: int = 3, bullets_per_ring: int = 12, ring_delay: float = 0.2, speed_multiplier: float = 1.0, sprite: String = "res://assets/sprites/bossbullut-6.png") -> void:
	for ring in range(rings):
		var speed = 8.0 + ring * 2.0 * speed_multiplier
		_danmaku_flower_pattern(bullets_per_ring, 0, speed, sprite)
		await get_tree().create_timer(ring_delay).timeout

# 五芒星弹幕
func _danmaku_pentagram(size: float = 100.0, bullets_per_line: int = 8, speed: float = 10.0, sprite: String = "res://assets/sprites/bossbullut-10.png") -> void:
	var points = []
	for i in range(5):
		var angle = (TAU / 5) * i - PI/2
		points.append(global_position + Vector2(cos(angle), sin(angle)) * size)

	for i in range(5):
		var start = points[i]
		var end = points[(i + 2) % 5]
		var direction = (end - start).normalized()
		var angle = direction.angle()

		for j in range(bullets_per_line):
			var t = float(j) / bullets_per_line
			var pos = start.lerp(end, t)
			_spawn_python_bullet(pos, angle, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)
		await get_tree().create_timer(0.1).timeout

# 追踪扇形弹幕
func _danmaku_aimed_fan(bullet_count: int = 9, spread: float = PI/3, speed: float = 11.0, sprite: String = "res://assets/sprites/bossbullut-11.png") -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var direction = (player.global_position - global_position).angle()
	_danmaku_fan(bullet_count, spread, direction, speed, sprite)

# 蝴蝶弹幕 - 曲线运动（使用追踪模拟）
func _danmaku_butterfly(pairs: int = 5, speed: float = 8.0, sprite: String = "res://assets/sprites/bossbullut-3.png") -> void:
	for i in range(pairs):
		var angle_left = PI/2 - 0.5 + i * 0.2
		var angle_right = PI/2 + 0.5 - i * 0.2
		_spawn_boss_bumb(sprite, speed, false, true)
		_spawn_boss_bumb(sprite, speed, false, true)
		await get_tree().create_timer(0.15).timeout

# 激光扫射（密集直线）
func _danmaku_laser_sweep(start_angle: float = 0.0, end_angle: float = PI, sweep_time: float = 2.0, bullets_per_frame: int = 3, speed: float = 15.0, sprite: String = "res://assets/sprites/bossbullut-5.png") -> void:
	var steps = int(sweep_time / 0.05)
	var angle_step = (end_angle - start_angle) / steps
	for i in range(steps):
		var angle = start_angle + angle_step * i
		for j in range(bullets_per_frame):
			_spawn_python_bullet(global_position, angle, 0, speed + j * 2, EnemyBullet.BulletType.NORMAL, sprite)
		await get_tree().create_timer(0.05).timeout

# 心形弹幕
func _danmaku_heart(bullets: int = 30, size: float = 80.0, speed: float = 9.0, sprite: String = "res://assets/sprites/bossbullut-1.png") -> void:
	for i in range(bullets):
		var t = (float(i) / bullets) * TAU
		var x = size * (16 * pow(sin(t), 3))
		var y = -size * (13 * cos(t) - 5 * cos(2*t) - 2 * cos(3*t) - cos(4*t))
		var pos = global_position + Vector2(x, y) / 16.0
		var direction = (pos - global_position).normalized()
		_spawn_python_bullet(pos, direction.angle(), 0, speed, EnemyBullet.BulletType.NORMAL, sprite)
		await get_tree().create_timer(0.05).timeout

# 网格弹幕
func _danmaku_grid(rows: int = 5, cols: int = 8, spacing: float = 40.0, speed: float = 7.0, sprite: String = "res://assets/sprites/bossbullut-6.png") -> void:
	var start_x = -(cols - 1) * spacing / 2
	var start_y = -100
	for row in range(rows):
		for col in range(cols):
			var pos = global_position + Vector2(start_x + col * spacing, start_y)
			_spawn_python_bullet(pos, PI/2, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)
		await get_tree().create_timer(0.2).timeout

# 螺旋星爆
func _danmaku_spiral_starburst(waves: int = 5, bullets_per_wave: int = 16, rotation_per_wave: float = 0.3, speed: float = 10.0, sprite: String = "res://assets/sprites/bossbullut-10.png") -> void:
	for wave in range(waves):
		var rotation = wave * rotation_per_wave
		_danmaku_flower_pattern(bullets_per_wave, 0, speed + wave, sprite)
		await get_tree().create_timer(0.15).timeout

# 交叉激光
func _danmaku_cross_laser(arms: int = 4, length: int = 10, speed: float = 12.0, sprite: String = "res://assets/sprites/bossbullut-5.png") -> void:
	var angle_step = TAU / arms
	for i in range(arms):
		var angle = angle_step * i
		for j in range(length):
			var offset = Vector2(cos(angle), sin(angle)) * j * 20
			_spawn_python_bullet(global_position + offset, angle, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)
		await get_tree().create_timer(0.1).timeout

# 随机追踪弹雨
func _danmaku_tracking_rain(bullet_count: int = 15, delay: float = 0.1, speed: float = 10.0, sprite: String = "res://assets/sprites/bossbullut-11.png") -> void:
	for i in range(bullet_count):
		var x_offset = randf_range(-200, 200)
		_spawn_boss_bumb(sprite, speed, false, true)
		await get_tree().create_timer(delay).timeout

# 旋转方阵
func _danmaku_rotating_square(size: float = 100.0, bullets_per_side: int = 6, rotation_speed: float = 1.0, speed: float = 8.0, sprite: String = "res://assets/sprites/bossbullut-3.png") -> void:
	var half_size = size / 2
	var positions = [
		Vector2(-half_size, -half_size),
		Vector2(half_size, -half_size),
		Vector2(half_size, half_size),
		Vector2(-half_size, half_size)
	]

	for side in range(4):
		var start_pos = positions[side]
		var end_pos = positions[(side + 1) % 4]
		for i in range(bullets_per_side):
			var t = float(i) / bullets_per_side
			var pos = global_position + start_pos.lerp(end_pos, t)
			var direction = (pos - global_position).normalized()
			_spawn_python_bullet(pos, direction.angle(), 0, speed, EnemyBullet.BulletType.NORMAL, sprite)
		await get_tree().create_timer(0.15).timeout

# 花瓣爆发
func _danmaku_petal_burst(layers: int = 3, petals_per_layer: int = 8, speed_base: float = 8.0, sprite: String = "res://assets/sprites/bossbullut-1.png") -> void:
	for layer in range(layers):
		var rotation_offset = (layer % 2) * (PI / petals_per_layer)
		var speed = speed_base + layer * 2
		var angle_step = TAU / petals_per_layer
		for i in range(petals_per_layer):
			var angle = angle_step * i + rotation_offset
			_spawn_python_bullet(global_position, angle, 0, speed, EnemyBullet.BulletType.NORMAL, sprite)
		await get_tree().create_timer(0.1).timeout

# 螺旋追踪组合
func _danmaku_spiral_tracking_combo(spirals: int = 2, tracking_bullets: int = 5, sprite: String = "res://assets/sprites/bossbullut-11.png") -> void:
	for i in range(spirals):
		_danmaku_spiral(3, 6, i * PI/3, 9.0, sprite)
		await get_tree().create_timer(0.3).timeout
	for i in range(tracking_bullets):
		_spawn_boss_bumb(sprite, 11.0, false, true)
		await get_tree().create_timer(0.15).timeout

# ============================================================================
# Boss 1 新技能 - 沙漠主题弹幕
# ============================================================================

func _boss1_desert_storm() -> void:
	# 沙漠风暴 - 旋转螺旋塔
	await _danmaku_rotating_spiral_tower(4, 16, 0.4, 9.0, "res://assets/sprites/bossbullut-1.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_flower_pattern(20, 0, 11.0, "res://assets/sprites/bossbullut-3.png")

func _boss1_sandstorm_vortex() -> void:
	# 沙尘漩涡 - 双螺旋
	await _danmaku_double_helix(25, PI, 10.0, "res://assets/sprites/bossbullut-5.png")
	await get_tree().create_timer(0.2).timeout
	await _danmaku_spiral_starburst(4, 12, 0.4, 9.0, "res://assets/sprites/bossbullut-1.png")

func _boss1_mirage_burst() -> void:
	# 幻影爆发 - 爆炸环形
	await _danmaku_explosion_ring(4, 16, 0.25, 1.2, "res://assets/sprites/bossbullut-6.png")

func _boss1_dune_wave() -> void:
	# 沙丘波浪
	await _danmaku_wave_wall(4, 12, 0.2, 8.0, "res://assets/sprites/bossbullut-10.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_aimed_fan(11, PI/2, 12.0, "res://assets/sprites/bossbullut-11.png")

func _boss1_star_constellation() -> void:
	# 星座弹幕 - 五芒星
	await _danmaku_pentagram(120.0, 10, 11.0, "res://assets/sprites/bossbullut-10.png")
	await get_tree().create_timer(0.2).timeout
	await _danmaku_flower_pattern(24, 0, 10.0, "res://assets/sprites/bossbullut-3.png")

# ============================================================================
# Boss 1 Additional Skills - Nonspell 1 (Desert Opening)
# ============================================================================

func _boss1_sandstorm_prelude() -> void:
	# Opening aimed spread with occasional ring
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	# Aimed spread
	for i in range(5):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for j in range(7):
			var spread_angle = angle_to_player + (j - 3) * 0.3
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout
		# Occasional ring
		if i % 2 == 0:
			for k in range(16):
				var ring_angle = (TAU / 16) * k
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(ring_angle), sin(ring_angle))
				bullet.speed = 120.0
				bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(bullet)

func _boss1_desert_wind() -> void:
	# Horizontal sweeping bullets with wave motion
	if not bullet_scene or not get_parent():
		return
	for wave in range(3):
		for i in range(20):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position + Vector2(-400 + i * 40, -200)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 150.0
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.05).timeout
		await get_tree().create_timer(0.8).timeout

func _boss1_sand_ripples() -> void:
	# Expanding concentric rings
	if not bullet_scene or not get_parent():
		return
	for ring in range(5):
		var ring_count = 12 + ring * 4
		for i in range(ring_count):
			var angle = (TAU / ring_count) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 100.0 + ring * 20.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

func _boss1_dune_cascade() -> void:
	# Falling bullets from top with lateral drift
	if not bullet_scene or not get_parent():
		return
	for wave in range(4):
		for i in range(15):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(100 + i * 50, 50)
			var drift = sin(wave * PI / 2)
			bullet.direction = Vector2(drift * 0.3, 1).normalized()
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.08).timeout
		await get_tree().create_timer(0.6).timeout

func _boss1_mirage_shimmer() -> void:
	# Random direction bullets with acceleration
	if not bullet_scene or not get_parent():
		return
	for i in range(30):
		var angle = randf() * TAU
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 80.0
		bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.1).timeout

# ============================================================================
# Boss 1 Additional Skills - Spell 1 (Lightning Storm)
# ============================================================================

func _boss1_thunder_spiral() -> void:
	# Spiral lightning bolts
	if not bullet_scene or not get_parent():
		return
	var base_angle = 0.0
	for i in range(40):
		var angle = base_angle + i * 0.3
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 220.0
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout

func _boss1_storm_vortex() -> void:
	# Rotating spiral with lightning branches
	if not bullet_scene or not get_parent():
		return
	for rotation in range(3):
		var base_angle = rotation * TAU / 3
		for i in range(12):
			var angle = base_angle + i * 0.4
			# Main spiral
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
			# Branch
			var branch = bullet_scene.instantiate() as EnemyBullet
			branch.global_position = global_position
			branch.direction = Vector2(cos(angle + 0.5), sin(angle + 0.5))
			branch.speed = 150.0
			branch.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(branch)
			await get_tree().create_timer(0.1).timeout

func _boss1_electric_web() -> void:
	# Grid pattern with connecting lines
	if not bullet_scene or not get_parent():
		return
	# Vertical lines
	for x in range(8):
		for y in range(10):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(150 + x * 100, 100 + y * 50)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 120.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout
	# Horizontal lines
	for y in range(6):
		for x in range(12):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(100 + x * 60, 150 + y * 80)
			bullet.direction = Vector2(1, 0)
			bullet.speed = 120.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss1_plasma_burst() -> void:
	# Dense aimed burst with split bullets
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for burst in range(5):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for i in range(12):
			var spread_angle = angle_to_player + (i - 5.5) * 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 250.0
			bullet.bullet_type = EnemyBullet.BulletType.SPLIT
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

# ============================================================================
# Boss 1 Additional Skills - Nonspell 2 (Sand Serpents)
# ============================================================================

func _boss1_serpent_coil() -> void:
	# Tightening spiral snakes
	if not bullet_scene or not get_parent():
		return
	for coil in range(4):
		var start_angle = coil * TAU / 4
		for i in range(30):
			var angle = start_angle + i * 0.4 - i * 0.05
			var radius = 300 - i * 8
			var spawn_pos = global_position + Vector2(cos(angle), sin(angle)) * radius
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = Vector2(cos(angle + PI/2), sin(angle + PI/2))
			bullet.speed = 140.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.05).timeout

func _boss1_viper_strike() -> void:
	# Fast aimed snakes with homing
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for strike in range(6):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for i in range(15):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle_to_player), sin(angle_to_player))
			bullet.speed = 280.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 2.0
			bullet._homing_duration = 0.5
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.06).timeout
		await get_tree().create_timer(0.4).timeout

func _boss1_cobra_dance() -> void:
	# Alternating left/right wave snakes
	if not bullet_scene or not get_parent():
		return
	for wave in range(8):
		var direction = 1 if wave % 2 == 0 else -1
		for i in range(20):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			var angle = PI/2 + direction * (i * 0.15)
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 160.0
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.05).timeout
		await get_tree().create_timer(0.3).timeout

func _boss1_python_crush() -> void:
	# Slow thick snakes that split
	if not bullet_scene or not get_parent():
		return
	for snake in range(4):
		var angle = (TAU / 4) * snake
		for i in range(25):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle + i * 0.1), sin(angle + i * 0.1))
			bullet.speed = 100.0
			bullet.bullet_type = EnemyBullet.BulletType.SPLIT
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.08).timeout
		await get_tree().create_timer(0.5).timeout

# ============================================================================
# Boss 1 Additional Skills - Spell 2 (Gravity Manipulation)
# ============================================================================

func _boss1_gravity_lens() -> void:
	# Bullets curve around center
	if not bullet_scene or not get_parent():
		return
	for wave in range(4):
		for i in range(24):
			var angle = (TAU / 24) * i + wave * 0.3
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss1_event_horizon_ring() -> void:
	# Expanding rings with gravity pull
	if not bullet_scene or not get_parent():
		return
	for ring in range(6):
		var bullet_count = 20 + ring * 4
		for i in range(bullet_count):
			var angle = (TAU / bullet_count) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 80.0 + ring * 15.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss1_spacetime_tear() -> void:
	# Random teleporting bullets
	if not bullet_scene or not get_parent():
		return
	for i in range(40):
		var angle = randf() * TAU
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position + Vector2(randf() * 400 - 200, randf() * 300 - 150)
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 180.0
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss1_singularity_burst() -> void:
	# Explosion from center with spiral
	if not bullet_scene or not get_parent():
		return
	# Initial burst
	for i in range(32):
		var angle = (TAU / 32) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 250.0
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.3).timeout
	# Spiral follow-up
	for i in range(50):
		var angle = i * 0.5
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 200.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout

# ============================================================================
# Boss 1 Additional Skills - Final Phase (Ultimate Combinations)
# ============================================================================

func _boss1_desert_apocalypse() -> void:
	# Combined sandstorm + lightning
	if not bullet_scene or not get_parent():
		return
	# Sandstorm base
	for wave in range(3):
		for i in range(20):
			var angle = randf() * TAU
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 150.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		# Lightning strikes
		for j in range(8):
			var lightning_angle = (TAU / 8) * j
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(lightning_angle), sin(lightning_angle))
			bullet.speed = 300.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

func _boss1_cosmic_mirage() -> void:
	# Teleporting black holes with snakes
	if not bullet_scene or not get_parent():
		return
	for combo in range(4):
		# Black hole ring
		for i in range(16):
			var angle = (TAU / 16) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 120.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout
		# Snake pattern
		for i in range(15):
			var snake_angle = combo * TAU / 4 + i * 0.3
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(snake_angle), sin(snake_angle))
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.05).timeout
		await get_tree().create_timer(0.4).timeout

func _boss1_eternal_storm() -> void:
	# Dense spiral with lightning and gravity
	if not bullet_scene or not get_parent():
		return
	for rotation in range(60):
		# Spiral bullets
		for i in range(3):
			var angle = rotation * 0.3 + i * TAU / 3
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		# Gravity bullets
		if rotation % 5 == 0:
			for j in range(12):
				var grav_angle = (TAU / 12) * j
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(grav_angle), sin(grav_angle))
				bullet.speed = 100.0
				bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
				bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout

func _boss1_void_serpent() -> void:
	# Giant curving snake made of bullets
	if not bullet_scene or not get_parent():
		return
	for snake in range(3):
		var base_angle = (TAU / 3) * snake
		for i in range(80):
			var angle = base_angle + sin(i * 0.2) * 0.8
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0 - i * 1.5
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.03).timeout
		await get_tree().create_timer(0.2).timeout

func _boss1_cataclysm() -> void:
	# All patterns combined in sequence
	if not bullet_scene or not get_parent():
		return
	# Sandstorm
	for i in range(30):
		var angle = randf() * TAU
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 160.0
		bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.3).timeout
	# Lightning spiral
	for i in range(24):
		var angle = i * 0.5
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 250.0
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.3).timeout
	# Snake wave
	for i in range(40):
		var angle = i * 0.3
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 180.0
		bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
		bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.3).timeout
	# Black hole burst
	for i in range(32):
		var angle = (TAU / 32) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 200.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)

# ============================================================================
# Boss 2 新技能 - 爱心主题弹幕
# ============================================================================

func _boss2_love_explosion() -> void:
	# 爱的爆发 - 心形弹幕
	await _danmaku_heart(35, 100.0, 10.0, "res://assets/sprites/bossbullut-1.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_flower_pattern(16, 0, 9.0, "res://assets/sprites/bossbullut-3.png")

func _boss2_cupid_arrows() -> void:
	# 丘比特之箭 - 追踪扇形
	for i in range(3):
		await _danmaku_aimed_fan(7, PI/4, 13.0, "res://assets/sprites/bossbullut-11.png")
		await get_tree().create_timer(0.4).timeout

func _boss2_passion_spiral() -> void:
	# 激情螺旋
	await _danmaku_spiral_tracking_combo(3, 8, "res://assets/sprites/bossbullut-11.png")

func _boss2_heart_constellation() -> void:
	# 心之星座 - 五芒星+心形
	await _danmaku_pentagram(100.0, 8, 10.0, "res://assets/sprites/bossbullut-6.png")
	await get_tree().create_timer(0.5).timeout
	await _danmaku_heart(30, 90.0, 9.0, "res://assets/sprites/bossbullut-1.png")

func _boss2_love_rain() -> void:
	# 爱之雨 - 追踪弹雨
	await _danmaku_tracking_rain(20, 0.12, 11.0, "res://assets/sprites/bossbullut-11.png")

# ============================================================================
# Boss 2 Additional Skills - Love/Heart Theme
# ============================================================================

# Nonspell 1: Love Opening
func _boss2_heartbeat_pulse() -> void:
	# Rhythmic expanding rings
	if not bullet_scene or not get_parent():
		return
	for pulse in range(6):
		var ring_count = 16 + pulse * 2
		for i in range(ring_count):
			var angle = (TAU / ring_count) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 140.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss2_cupid_arrows_aimed() -> void:
	# Aimed arrows with slight homing
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for volley in range(8):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for i in range(5):
			var spread_angle = angle_to_player + (i - 2) * 0.25
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 220.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 1.5
			bullet._homing_duration = 0.4
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

func _boss2_love_shower() -> void:
	# Falling heart-shaped patterns
	if not bullet_scene or not get_parent():
		return
	for wave in range(4):
		for i in range(12):
			var x_pos = 150 + i * 60
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50)
			bullet.direction = Vector2(sin(i * 0.5) * 0.3, 1).normalized()
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.08).timeout
		await get_tree().create_timer(0.5).timeout

func _boss2_affection_wave() -> void:
	# Sine wave horizontal sweep
	if not bullet_scene or not get_parent():
		return
	for sweep in range(3):
		for i in range(25):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			var angle = PI/2 + sin(i * 0.3) * 0.6
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 160.0
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.06).timeout
		await get_tree().create_timer(0.7).timeout

func _boss2_romance_spiral() -> void:
	# Gentle rotating spiral
	if not bullet_scene or not get_parent():
		return
	for i in range(60):
		var angle = i * 0.4
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 150.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout

# Spell 1: Attraction Field
func _boss2_attraction_field() -> void:
	# Bullets curve toward player then away
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for wave in range(5):
		for i in range(20):
			var angle = (TAU / 20) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 3.0
			bullet._homing_duration = 0.6
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.7).timeout

func _boss2_magnetic_hearts() -> void:
	# Orbiting bullets that suddenly shoot
	if not bullet_scene or not get_parent():
		return
	for orbit in range(4):
		for i in range(16):
			var angle = (TAU / 16) * i + orbit * 0.3
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 100.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss2_gravity_embrace() -> void:
	# Bullets spiral inward then burst out
	if not bullet_scene or not get_parent():
		return
	for cycle in range(3):
		# Inward spiral
		for i in range(30):
			var angle = i * 0.5
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.04).timeout
		await get_tree().create_timer(0.3).timeout
		# Burst out
		for i in range(24):
			var angle = (TAU / 24) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 250.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

func _boss2_love_vortex() -> void:
	# Rotating spiral with attraction
	if not bullet_scene or not get_parent():
		return
	for i in range(80):
		var angle = i * 0.3
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 170.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout

func _boss2_passion_pull() -> void:
	# Dense aimed burst with gravity
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for burst in range(6):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for i in range(15):
			var spread_angle = angle_to_player + (i - 7) * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 240.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 2.5
			bullet._homing_duration = 0.5
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

# Nonspell 2: Heart Rain (keep heart_rain, add variations)
func _boss2_valentine_storm() -> void:
	# Dense heart rain with patterns
	if not bullet_scene or not get_parent():
		return
	for storm in range(4):
		for i in range(20):
			var x_pos = 100 + randf() * 700
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 200.0 + randf() * 50.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss2_love_letter_cascade() -> void:
	# Falling with horizontal drift
	if not bullet_scene or not get_parent():
		return
	for wave in range(5):
		var drift_dir = 1 if wave % 2 == 0 else -1
		for i in range(15):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(150 + i * 50, 50)
			bullet.direction = Vector2(drift_dir * 0.4, 1).normalized()
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.08).timeout
		await get_tree().create_timer(0.5).timeout

func _boss2_rose_petal_fall() -> void:
	# Gentle falling with wave motion
	if not bullet_scene or not get_parent():
		return
	for petal in range(50):
		var x_pos = 100 + randf() * 700
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = Vector2(x_pos, 50)
		bullet.direction = Vector2(0, 1)
		bullet.speed = 140.0
		bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss2_confession_barrage() -> void:
	# Fast falling with acceleration
	if not bullet_scene or not get_parent():
		return
	for barrage in range(4):
		for i in range(18):
			var x_pos = 150 + i * 45
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 150.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.06).timeout
		await get_tree().create_timer(0.7).timeout

# Spell 2: Time Reversal (keep reverse_time, add variations)
func _boss2_time_rewind_spiral() -> void:
	# Spiral that reverses
	if not bullet_scene or not get_parent():
		return
	for i in range(60):
		var angle = i * 0.4
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 180.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
	# Reverse all bullets
	await get_tree().create_timer(1.0).timeout
	var bullets = get_tree().get_nodes_in_group("enemy_bullets")
	for b in bullets:
		if b is EnemyBullet:
			b.direction = -b.direction

func _boss2_temporal_echo() -> void:
	# Bullets leave trails that become real
	if not bullet_scene or not get_parent():
		return
	for echo in range(5):
		for i in range(16):
			var angle = (TAU / 16) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

func _boss2_causality_break() -> void:
	# Bullets appear before being shot
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for break_event in range(6):
		# Spawn bullets ahead of time
		for i in range(12):
			var angle = (TAU / 12) * i
			var spawn_distance = 300.0
			var spawn_pos = global_position + Vector2(cos(angle), sin(angle)) * spawn_distance
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = (player.global_position - spawn_pos).normalized()
			bullet.speed = 220.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss2_paradox_loop() -> void:
	# Bullets circle then reverse
	if not bullet_scene or not get_parent():
		return
	for loop in range(4):
		for i in range(20):
			var angle = (TAU / 20) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 160.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(1.0).timeout

# Final: Ultimate Love (keep made_in_heaven, add variations)
func _boss2_eternal_love() -> void:
	# All patterns combined with time effects
	if not bullet_scene or not get_parent():
		return
	# Heart spiral
	for i in range(40):
		var angle = i * 0.5
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 190.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.5).timeout
	# Time reversal ring
	for i in range(24):
		var angle = (TAU / 24) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 220.0
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.8).timeout

func _boss2_heaven_ascension() -> void:
	# Spiraling upward then diving
	if not bullet_scene or not get_parent():
		return
	for ascend in range(3):
		# Upward spiral
		for i in range(30):
			var angle = i * 0.4
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle) - 0.3).normalized()
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.05).timeout
		await get_tree().create_timer(0.4).timeout
		# Diving bullets
		for i in range(20):
			var x_pos = 150 + i * 40
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 250.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss2_divine_romance() -> void:
	# Heart patterns with time reversal
	if not bullet_scene or not get_parent():
		return
	for divine in range(4):
		# Heart burst
		for i in range(20):
			var angle = (TAU / 20) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout
		# Reverse effect
		var bullets = get_tree().get_nodes_in_group("enemy_bullets")
		for b in bullets:
			if b is EnemyBullet and randf() < 0.3:
				b.direction = -b.direction
		await get_tree().create_timer(0.4).timeout

func _boss2_love_transcendent() -> void:
	# Dense omnidirectional with attraction
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for transcend in range(5):
		# Dense ring
		for i in range(32):
			var angle = (TAU / 32) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 2.0
			bullet._homing_duration = 0.7
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.7).timeout

# ============================================================================
# Boss 3 新技能 - 时间主题弹幕
# ============================================================================

func _boss3_time_spiral() -> void:
	# 时间螺旋
	await _danmaku_rotating_spiral_tower(5, 14, 0.35, 10.0, "res://assets/sprites/bossbullut-3.png")
	await get_tree().create_timer(0.2).timeout
	await _danmaku_double_helix(20, PI, 11.0, "res://assets/sprites/bossbullut-5.png")

func _boss3_clock_burst() -> void:
	# 时钟爆发 - 米字弹幕
	await _danmaku_cross_pattern(12, 6, 35.0, 10.0, "res://assets/sprites/bossbullut-5.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_flower_pattern(24, 0, 9.0, "res://assets/sprites/bossbullut-10.png")

func _boss3_temporal_grid() -> void:
	# 时空网格
	await _danmaku_grid(6, 10, 45.0, 8.0, "res://assets/sprites/bossbullut-6.png")

func _boss3_golden_galaxy() -> void:
	# 黄金银河 - 螺旋星爆
	await _danmaku_spiral_starburst(6, 20, 0.35, 11.0, "res://assets/sprites/bossbullut-10.png")

func _boss3_time_freeze_pattern() -> void:
	# 时间冻结模式 - 旋转方阵
	await _danmaku_rotating_square(120.0, 8, 1.0, 9.0, "res://assets/sprites/bossbullut-3.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_explosion_ring(3, 16, 0.2, 1.0, "res://assets/sprites/bossbullut-6.png")

# ============================================================================
# Boss 3 Additional Skills - Time Theme
# ============================================================================

# Nonspell 1: Clockwork Opening
func _boss3_clockwork_tick() -> void:
	# Rhythmic aimed bursts
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for tick in range(12):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for i in range(6):
			var spread_angle = angle_to_player + (i - 2.5) * 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss3_second_hand_sweep() -> void:
	# Rotating line of bullets
	if not bullet_scene or not get_parent():
		return
	for rotation in range(60):
		var angle = (TAU / 60) * rotation
		for i in range(8):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 120.0 + i * 15.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout

func _boss3_minute_markers() -> void:
	# 12-direction burst
	if not bullet_scene or not get_parent():
		return
	for burst in range(5):
		for i in range(12):
			var angle = (TAU / 12) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss3_hour_chime() -> void:
	# Expanding rings at intervals
	if not bullet_scene or not get_parent():
		return
	for chime in range(6):
		var ring_count = 16 + chime * 2
		for i in range(ring_count):
			var angle = (TAU / ring_count) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 130.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.7).timeout

func _boss3_pendulum_swing() -> void:
	# Alternating left/right sweeps
	if not bullet_scene or not get_parent():
		return
	for swing in range(8):
		var direction = 1 if swing % 2 == 0 else -1
		for i in range(15):
			var angle = PI/2 + direction * (i * 0.2)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 190.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.06).timeout
		await get_tree().create_timer(0.4).timeout

# Spell 1: Golden Storm (keep golden_storm, add variations)
func _boss3_treasure_rain() -> void:
	# Falling coins with patterns
	if not bullet_scene or not get_parent():
		return
	for wave in range(5):
		for i in range(18):
			var x_pos = 120 + i * 45
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50)
			bullet.direction = Vector2(sin(i * 0.4) * 0.2, 1).normalized()
			bullet.speed = 190.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.07).timeout
		await get_tree().create_timer(0.5).timeout

func _boss3_wealth_spiral() -> void:
	# Spiraling coins
	if not bullet_scene or not get_parent():
		return
	for i in range(70):
		var angle = i * 0.45
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 170.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout

func _boss3_fortune_wheel() -> void:
	# Rotating coin ring
	if not bullet_scene or not get_parent():
		return
	for rotation in range(4):
		var base_angle = rotation * TAU / 4
		for i in range(20):
			var angle = base_angle + (TAU / 20) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 150.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

func _boss3_jackpot_burst() -> void:
	# Dense coin explosion
	if not bullet_scene or not get_parent():
		return
	for burst in range(3):
		for i in range(36):
			var angle = (TAU / 36) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 220.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

# Nonspell 2: Time Lock (keep time_lock_ring, add variations)
func _boss3_stasis_field() -> void:
	# Slow-moving bullets that accelerate
	if not bullet_scene or not get_parent():
		return
	for field in range(5):
		for i in range(24):
			var angle = (TAU / 24) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 80.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.7).timeout

func _boss3_temporal_prison() -> void:
	# Grid of slow bullets
	if not bullet_scene or not get_parent():
		return
	for y in range(8):
		for x in range(10):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(150 + x * 70, 100 + y * 60)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 90.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss3_frozen_moment() -> void:
	# Bullets pause then continue
	if not bullet_scene or not get_parent():
		return
	for moment in range(4):
		for i in range(20):
			var angle = (TAU / 20) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(1.0).timeout

func _boss3_time_dilation() -> void:
	# Bullets with varying speeds
	if not bullet_scene or not get_parent():
		return
	for dilation in range(6):
		for i in range(16):
			var angle = (TAU / 16) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 100.0 + (i % 4) * 50.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

# Spell 2: Time Stop (keep time_stop, add variations)
func _boss3_world_freeze() -> void:
	# All bullets stop then resume
	if not bullet_scene or not get_parent():
		return
	# Spawn bullets
	for i in range(32):
		var angle = (TAU / 32) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 180.0
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.5).timeout
	# Freeze effect (simulated by spawning more bullets)
	for i in range(24):
		var angle = (TAU / 24) * i + 0.2
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 220.0
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)

func _boss3_stopped_time_knives() -> void:
	# Bullets appear during time stop
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for knife in range(8):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for i in range(10):
			var spread_angle = angle_to_player + (i - 4.5) * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 280.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout

func _boss3_time_erase() -> void:
	# Bullets disappear and reappear
	if not bullet_scene or not get_parent():
		return
	for erase in range(5):
		for i in range(20):
			var angle = (TAU / 20) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 190.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.7).timeout

func _boss3_king_crimson() -> void:
	# Bullets skip forward in time
	if not bullet_scene or not get_parent():
		return
	for skip in range(4):
		for i in range(24):
			var angle = (TAU / 24) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

# Final: Ultimate Time
func _boss3_time_collapse() -> void:
	# All time effects combined
	if not bullet_scene or not get_parent():
		return
	# Clockwork burst
	for i in range(12):
		var angle = (TAU / 12) * i
		for j in range(5):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 150.0 + j * 20.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
	await get_tree().create_timer(0.5).timeout
	# Time stop effect
	for i in range(32):
		var angle = (TAU / 32) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 220.0
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)

func _boss3_temporal_singularity() -> void:
	# Time spirals inward
	if not bullet_scene or not get_parent():
		return
	for i in range(80):
		var angle = i * 0.4
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 180.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout

func _boss3_chronos_wrath() -> void:
	# Dense time-manipulated patterns
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for wrath in range(5):
		# Aimed burst
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for i in range(12):
			var spread_angle = angle_to_player + (i - 5.5) * 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 240.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout
		# Ring
		for i in range(20):
			var angle = (TAU / 20) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 160.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss3_eternity_end() -> void:
	# Infinite time loop patterns
	if not bullet_scene or not get_parent():
		return
	for loop in range(4):
		for i in range(28):
			var angle = i * 0.5
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 190.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.06).timeout
		await get_tree().create_timer(0.4).timeout

func _boss3_omega_timeline() -> void:
	# Ultimate time manipulation
	if not bullet_scene or not get_parent():
		return
	# Combined pattern
	for omega in range(3):
		# Spiral
		for i in range(40):
			var angle = i * 0.4
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout
		# Burst
		for i in range(32):
			var angle = (TAU / 32) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 250.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

# ============================================================================
# Boss 4 新技能 - 光/像素主题弹幕
# ============================================================================

func _boss4_pixel_burst() -> void:
	# 像素爆发 - 随机散射
	await _danmaku_random_spray(30, 7.0, 14.0, "res://assets/sprites/bossbullut-1.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_flower_pattern(16, 0, 10.0, "res://assets/sprites/bossbullut-5.png")

func _boss4_laser_cross() -> void:
	# 激光十字 - 交叉激光
	await _danmaku_cross_laser(8, 12, 13.0, "res://assets/sprites/bossbullut-5.png")

func _boss4_screen_sweep() -> void:
	# 屏幕扫射 - 激光扫射
	await _danmaku_laser_sweep(0.0, PI, 2.5, 4, 16.0, "res://assets/sprites/bossbullut-5.png")

func _boss4_digital_rain() -> void:
	# 数字雨 - 网格+追踪
	await _danmaku_grid(5, 9, 40.0, 9.0, "res://assets/sprites/bossbullut-6.png")
	await get_tree().create_timer(0.5).timeout
	await _danmaku_tracking_rain(12, 0.1, 12.0, "res://assets/sprites/bossbullut-11.png")

func _boss4_light_prism() -> void:
	# 光棱镜 - 扇形+螺旋
	await _danmaku_aimed_fan(13, PI/2.5, 12.0, "res://assets/sprites/bossbullut-11.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_spiral(4, 8, 0.0, 10.0, "res://assets/sprites/bossbullut-3.png")

# ============================================================================
# Boss 4 Additional Skills - Light/Pixel Theme
# ============================================================================

# Nonspell 1: Tech Opening
func _boss4_warning_beams() -> void:
	# Laser warnings then fire
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for beam in range(6):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		# Warning phase (visual only, no actual bullets)
		await get_tree().create_timer(0.3).timeout
		# Fire phase
		for i in range(8):
			var spread_angle = angle_to_player + (i - 3.5) * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 280.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss4_scan_lines() -> void:
	# Horizontal sweeping lasers
	if not bullet_scene or not get_parent():
		return
	for scan in range(5):
		for i in range(20):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(100 + i * 40, 100 + scan * 100)
			bullet.direction = Vector2(1, 0)
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

func _boss4_pixel_grid() -> void:
	# Grid pattern bullets
	if not bullet_scene or not get_parent():
		return
	for y in range(8):
		for x in range(12):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(120 + x * 60, 100 + y * 60)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 140.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss4_screen_flicker() -> void:
	# Random appearing bullets
	if not bullet_scene or not get_parent():
		return
	for flicker in range(50):
		var x_pos = 100 + randf() * 700
		var y_pos = 100 + randf() * 400
		var angle = randf() * TAU
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = Vector2(x_pos, y_pos)
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 180.0
		bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout

func _boss4_static_noise() -> void:
	# Random spray with glitch effect
	if not bullet_scene or not get_parent():
		return
	for noise in range(4):
		for i in range(25):
			var angle = randf() * TAU
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 150.0 + randf() * 100.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

# Spell 1: Signal Interference
func _boss4_signal_interference() -> void:
	# Wavy distorted patterns
	if not bullet_scene or not get_parent():
		return
	for wave in range(5):
		for i in range(30):
			var angle = i * 0.4 + sin(i * 0.3) * 0.5
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 170.0
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.05).timeout
		await get_tree().create_timer(0.4).timeout

func _boss4_glitch_cascade() -> void:
	# Falling glitchy bullets
	if not bullet_scene or not get_parent():
		return
	for cascade in range(6):
		for i in range(15):
			var x_pos = 150 + i * 50 + randf() * 20 - 10
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50)
			bullet.direction = Vector2(randf() * 0.4 - 0.2, 1).normalized()
			bullet.speed = 190.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.06).timeout
		await get_tree().create_timer(0.5).timeout

func _boss4_corrupted_data() -> void:
	# Random teleporting bullets
	if not bullet_scene or not get_parent():
		return
	for corrupt in range(5):
		for i in range(20):
			var angle = (TAU / 20) * i
			var spawn_offset = Vector2(randf() * 200 - 100, randf() * 200 - 100)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position + spawn_offset
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.7).timeout

func _boss4_buffer_overflow() -> void:
	# Dense expanding burst
	if not bullet_scene or not get_parent():
		return
	for overflow in range(4):
		for i in range(40):
			var angle = (TAU / 40) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 220.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

func _boss4_packet_storm() -> void:
	# Fast aimed packets
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for storm in range(8):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for i in range(8):
			var spread_angle = angle_to_player + (i - 3.5) * 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.35).timeout

# Nonspell 2: UFO Patrol (keep ufo_patrol, add variations)
func _boss4_drone_swarm() -> void:
	# Multiple small UFOs
	if not bullet_scene or not get_parent():
		return
	for swarm in range(4):
		for i in range(6):
			var angle = (TAU / 6) * i
			var spawn_pos = global_position + Vector2(cos(angle), sin(angle)) * 200
			# Spawn bullets in formation
			for j in range(12):
				var bullet_angle = (TAU / 12) * j
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = spawn_pos
				bullet.direction = Vector2(cos(bullet_angle), sin(bullet_angle))
				bullet.speed = 160.0
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(1.0).timeout

func _boss4_satellite_orbit() -> void:
	# Orbiting UFOs that shoot
	if not bullet_scene or not get_parent():
		return
	for orbit in range(5):
		var orbit_angle = orbit * TAU / 5
		for i in range(20):
			var angle = orbit_angle + i * 0.3
			var orbit_pos = global_position + Vector2(cos(angle), sin(angle)) * 250
			# Shoot from orbit position
			for j in range(8):
				var shoot_angle = (TAU / 8) * j
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = orbit_pos
				bullet.direction = Vector2(cos(shoot_angle), sin(shoot_angle))
				bullet.speed = 180.0
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
			await get_tree().create_timer(0.15).timeout

func _boss4_probe_scan() -> void:
	# UFOs sweep across screen
	if not bullet_scene or not get_parent():
		return
	for scan in range(4):
		var start_x = 100 if scan % 2 == 0 else 800
		var direction = 1 if scan % 2 == 0 else -1
		for i in range(15):
			var x_pos = start_x + i * direction * 50
			var y_pos = 150 + scan * 100
			# Shoot downward
			for j in range(10):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = Vector2(x_pos, y_pos)
				bullet.direction = Vector2(0, 1)
				bullet.speed = 170.0
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
			await get_tree().create_timer(0.12).timeout
		await get_tree().create_timer(0.5).timeout

func _boss4_alien_formation() -> void:
	# UFOs in geometric patterns
	if not bullet_scene or not get_parent():
		return
	for formation in range(3):
		# Triangle formation
		for i in range(3):
			var angle = (TAU / 3) * i
			var spawn_pos = global_position + Vector2(cos(angle), sin(angle)) * 200
			for j in range(16):
				var bullet_angle = (TAU / 16) * j
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = spawn_pos
				bullet.direction = Vector2(cos(bullet_angle), sin(bullet_angle))
				bullet.speed = 190.0
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(1.2).timeout

# Spell 2: Orbital Strike (keep orbital_strike, add variations)
func _boss4_satellite_laser() -> void:
	# Multiple orbital lasers
	if not bullet_scene or not get_parent():
		return
	for laser in range(6):
		for i in range(12):
			var x_pos = 150 + i * 60
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 250.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss4_space_bombardment() -> void:
	# Dense falling lasers
	if not bullet_scene or not get_parent():
		return
	for bombard in range(5):
		for i in range(25):
			var x_pos = 100 + randf() * 700
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 280.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.05).timeout
		await get_tree().create_timer(0.6).timeout

func _boss4_ion_cannon() -> void:
	# Thick slow laser with spread
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for cannon in range(5):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for i in range(15):
			var spread_angle = angle_to_player + (i - 7) * 0.1
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.7).timeout

func _boss4_plasma_rain() -> void:
	# Falling laser bullets
	if not bullet_scene or not get_parent():
		return
	for rain in range(6):
		for i in range(20):
			var x_pos = 120 + i * 40
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50)
			bullet.direction = Vector2(sin(i * 0.5) * 0.3, 1).normalized()
			bullet.speed = 240.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.06).timeout
		await get_tree().create_timer(0.5).timeout

# Final: Ultimate Tech
func _boss4_pixel_apocalypse() -> void:
	# All patterns combined
	if not bullet_scene or not get_parent():
		return
	# Grid
	for i in range(20):
		var angle = (TAU / 20) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 180.0
		bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.4).timeout
	# Lasers
	for i in range(15):
		var x_pos = 150 + i * 50
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = Vector2(x_pos, 50)
		bullet.direction = Vector2(0, 1)
		bullet.speed = 260.0
		bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.4).timeout
	# UFO burst
	for i in range(24):
		var angle = (TAU / 24) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 200.0
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)

func _boss4_system_crash() -> void:
	# Chaotic glitch patterns
	if not bullet_scene or not get_parent():
		return
	for crash in range(4):
		for i in range(30):
			var angle = randf() * TAU
			var spawn_offset = Vector2(randf() * 300 - 150, randf() * 200 - 100)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position + spawn_offset
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 150.0 + randf() * 100.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss4_digital_armageddon() -> void:
	# Dense omnidirectional tech
	if not bullet_scene or not get_parent():
		return
	for armageddon in range(3):
		for i in range(48):
			var angle = (TAU / 48) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 210.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

func _boss4_singularity_upload() -> void:
	# Spiraling digital patterns
	if not bullet_scene or not get_parent():
		return
	for i in range(90):
		var angle = i * 0.35
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 190.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout

func _boss4_matrix_collapse() -> void:
	# Grid dissolving into chaos
	if not bullet_scene or not get_parent():
		return
	# Grid phase
	for y in range(6):
		for x in range(10):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(150 + x * 70, 120 + y * 70)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 120.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
	await get_tree().create_timer(0.5).timeout
	# Chaos phase
	for i in range(50):
		var angle = randf() * TAU
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 200.0
		bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout

# ============================================================================
# Boss 5 新技能 - 爆炸主题弹幕
# ============================================================================

func _boss5_mega_explosion() -> void:
	# 超级爆炸 - 爆炸环形
	await _danmaku_explosion_ring(5, 18, 0.18, 1.3, "res://assets/sprites/bossbullut-6.png")

func _boss5_firework_show() -> void:
	# 烟花秀 - 花瓣爆发
	await _danmaku_petal_burst(4, 12, 9.0, "res://assets/sprites/bossbullut-1.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_random_spray(25, 8.0, 13.0, "res://assets/sprites/bossbullut-3.png")

func _boss5_chain_reaction() -> void:
	# 连锁反应 - 螺旋星爆
	await _danmaku_spiral_starburst(5, 16, 0.4, 10.0, "res://assets/sprites/bossbullut-10.png")
	await get_tree().create_timer(0.2).timeout
	await _danmaku_flower_pattern(20, 0, 11.0, "res://assets/sprites/bossbullut-6.png")

func _boss5_tnt_barrage() -> void:
	# TNT弹幕 - 网格+爆炸
	await _danmaku_grid(4, 8, 50.0, 8.0, "res://assets/sprites/bossbullut-6.png")
	await get_tree().create_timer(0.4).timeout
	await _danmaku_explosion_ring(3, 14, 0.2, 1.1, "res://assets/sprites/bossbullut-10.png")

func _boss5_demolition_wave() -> void:
	# 爆破波 - 波浪墙
	await _danmaku_wave_wall(5, 11, 0.18, 9.0, "res://assets/sprites/bossbullut-10.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_aimed_fan(9, PI/3, 13.0, "res://assets/sprites/bossbullut-11.png")

# ============================================================================
# Boss 5 Additional Skills - Explosion Theme
# ============================================================================

# Nonspell 1: TNT Opening
func _boss5_tnt_toss() -> void:
	# Simple TNT throws
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for toss in range(10):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for i in range(3):
			var spread_angle = angle_to_player + (i - 1) * 0.3
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

func _boss5_firecracker_spray() -> void:
	# Small rapid explosions
	if not bullet_scene or not get_parent():
		return
	for spray in range(6):
		for i in range(20):
			var angle = randf() * TAU
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 160.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.04).timeout
		await get_tree().create_timer(0.5).timeout

func _boss5_sparkler_spin() -> void:
	# Rotating explosion trails
	if not bullet_scene or not get_parent():
		return
	for i in range(70):
		var angle = i * 0.4
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 170.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout

func _boss5_cherry_bomb_bounce() -> void:
	# Bouncing explosives
	if not bullet_scene or not get_parent():
		return
	for bounce in range(8):
		for i in range(12):
			var angle = (TAU / 12) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 150.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss5_smoke_screen() -> void:
	# Obscuring explosion patterns
	if not bullet_scene or not get_parent():
		return
	for screen in range(5):
		for i in range(24):
			var angle = (TAU / 24) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 130.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.7).timeout

# Spell 1: Gravity Sink (keep gravity_sink, add variations)
func _boss5_implosion_burst() -> void:
	# Inward then outward
	if not bullet_scene or not get_parent():
		return
	for implosion in range(3):
		# Inward phase
		for i in range(32):
			var angle = (TAU / 32) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout
		# Outward burst
		for i in range(40):
			var angle = (TAU / 40) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 250.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

func _boss5_vacuum_bomb() -> void:
	# Sucks bullets then explodes
	if not bullet_scene or not get_parent():
		return
	for vacuum in range(4):
		# Vacuum phase
		for i in range(24):
			var angle = (TAU / 24) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

func _boss5_singularity_det() -> void:
	# Black hole explosion
	if not bullet_scene or not get_parent():
		return
	for singularity in range(3):
		for i in range(36):
			var angle = (TAU / 36) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 100.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.9).timeout

func _boss5_collapse_nova() -> void:
	# Spiraling implosion
	if not bullet_scene or not get_parent():
		return
	for i in range(80):
		var angle = -i * 0.4
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 190.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout

# Nonspell 2: Chain Explosion (keep chain_explosion, add variations)
func _boss5_domino_blast() -> void:
	# Sequential explosions
	if not bullet_scene or not get_parent():
		return
	for domino in range(8):
		var x_pos = 150 + domino * 80
		for i in range(16):
			var angle = (TAU / 16) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 200)
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout

func _boss5_cascade_detonation() -> void:
	# Branching explosions
	if not bullet_scene or not get_parent():
		return
	for cascade in range(4):
		var base_angle = (TAU / 4) * cascade
		for i in range(20):
			var angle = base_angle + i * 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
			# Branch bullets
			if i % 4 == 0:
				for j in range(8):
					var branch_angle = angle + (TAU / 8) * j
					var branch = bullet_scene.instantiate() as EnemyBullet
					branch.global_position = global_position
					branch.direction = Vector2(cos(branch_angle), sin(branch_angle))
					branch.speed = 160.0
					branch.set_sprite("res://assets/sprites/bossbullut-1.png")
					get_parent().add_child(branch)
			await get_tree().create_timer(0.08).timeout
		await get_tree().create_timer(0.4).timeout

func _boss5_sympathetic_det() -> void:
	# Explosions trigger more
	if not bullet_scene or not get_parent():
		return
	for sympathy in range(5):
		# Initial explosion
		for i in range(20):
			var angle = (TAU / 20) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 170.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout
		# Secondary explosions
		for i in range(4):
			var sec_angle = (TAU / 4) * i
			var sec_pos = global_position + Vector2(cos(sec_angle), sin(sec_angle)) * 150
			for j in range(12):
				var bullet_angle = (TAU / 12) * j
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = sec_pos
				bullet.direction = Vector2(cos(bullet_angle), sin(bullet_angle))
				bullet.speed = 190.0
				bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss5_avalanche_boom() -> void:
	# Expanding explosion wave
	if not bullet_scene or not get_parent():
		return
	for wave in range(6):
		var ring_count = 16 + wave * 4
		for i in range(ring_count):
			var angle = (TAU / ring_count) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 140.0 + wave * 15.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

# Spell 2: Mirror TNT (keep mirror_tnt, add variations)
func _boss5_kaleidoscope_blast() -> void:
	# Symmetrical explosions
	if not bullet_scene or not get_parent():
		return
	for kaleidoscope in range(4):
		for symmetry in range(6):
			var base_angle = (TAU / 6) * symmetry
			for i in range(10):
				var angle = base_angle + i * 0.2
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(angle), sin(angle))
				bullet.speed = 190.0
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

func _boss5_reflection_bomb() -> void:
	# Explosions reflect off walls
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for reflect in range(6):
		var angle_to_player = global_position.direction_to(player.global_position).angle()
		for i in range(16):
			var spread_angle = angle_to_player + (i - 7.5) * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = 210.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss5_prism_burst() -> void:
	# Explosions split into colors
	if not bullet_scene or not get_parent():
		return
	for prism in range(5):
		# Main burst
		for i in range(24):
			var angle = (TAU / 24) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.SPLIT
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.7).timeout

func _boss5_fractal_detonation() -> void:
	# Self-similar explosion patterns
	if not bullet_scene or not get_parent():
		return
	for fractal in range(3):
		# Large ring
		for i in range(32):
			var angle = (TAU / 32) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout
		# Medium rings
		for j in range(4):
			var offset_angle = (TAU / 4) * j
			var offset_pos = global_position + Vector2(cos(offset_angle), sin(offset_angle)) * 120
			for i in range(16):
				var angle = (TAU / 16) * i
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = offset_pos
				bullet.direction = Vector2(cos(angle), sin(angle))
				bullet.speed = 160.0
				bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

# Final: Ultimate Explosion (keep bakuretsu_finale, add variations)
func _boss5_nuclear_option() -> void:
	# Massive central explosion
	if not bullet_scene or not get_parent():
		return
	for nuke in range(2):
		# Dense burst
		for i in range(60):
			var angle = (TAU / 60) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 230.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout
		# Shockwave
		for i in range(48):
			var angle = (TAU / 48) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 280.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(1.2).timeout

func _boss5_armageddon_blast() -> void:
	# All explosion types combined
	if not bullet_scene or not get_parent():
		return
	# Chain explosions
	for i in range(5):
		var x_pos = 200 + i * 120
		for j in range(16):
			var angle = (TAU / 16) * j
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 200)
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 190.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(0.3).timeout
	# Implosion
	for i in range(32):
		var angle = (TAU / 32) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 200.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)

func _boss5_supernova() -> void:
	# Expanding explosion rings
	if not bullet_scene or not get_parent():
		return
	for nova in range(8):
		var ring_count = 20 + nova * 3
		for i in range(ring_count):
			var angle = (TAU / ring_count) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 150.0 + nova * 20.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.35).timeout

func _boss5_big_bang() -> void:
	# Creation-level explosion patterns
	if not bullet_scene or not get_parent():
		return
	# Initial singularity
	for i in range(40):
		var angle = i * 0.5
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 100.0
		bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.5).timeout
	# Expansion
	for wave in range(4):
		for i in range(36):
			var angle = (TAU / 36) * i + wave * 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 220.0 + wave * 30.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

# ============================================================================
# Boss 6 新技能 - 终极主题弹幕
# ============================================================================

func _boss6_ultimate_spiral() -> void:
	# 终极螺旋 - 双螺旋+螺旋塔
	await _danmaku_double_helix(30, PI, 11.0, "res://assets/sprites/bossbullut-5.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_rotating_spiral_tower(5, 18, 0.3, 10.0, "res://assets/sprites/bossbullut-3.png")

func _boss6_galaxy_burst() -> void:
	# 银河爆发 - 螺旋星爆+五芒星
	await _danmaku_spiral_starburst(6, 20, 0.3, 12.0, "res://assets/sprites/bossbullut-10.png")
	await get_tree().create_timer(0.4).timeout
	await _danmaku_pentagram(130.0, 12, 11.0, "res://assets/sprites/bossbullut-10.png")

func _boss6_final_judgment() -> void:
	# 最终审判 - 激光扫射+追踪雨
	await _danmaku_laser_sweep(0.0, TAU, 3.0, 5, 17.0, "res://assets/sprites/bossbullut-5.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_tracking_rain(25, 0.08, 13.0, "res://assets/sprites/bossbullut-11.png")

func _boss6_chaos_dimension() -> void:
	# 混沌次元 - 随机散射+网格+爆炸环
	await _danmaku_random_spray(35, 6.0, 15.0, "res://assets/sprites/bossbullut-1.png")
	await get_tree().create_timer(0.4).timeout
	await _danmaku_grid(6, 10, 40.0, 9.0, "res://assets/sprites/bossbullut-6.png")
	await get_tree().create_timer(0.4).timeout
	await _danmaku_explosion_ring(4, 20, 0.2, 1.4, "res://assets/sprites/bossbullut-10.png")

func _boss6_divine_cross() -> void:
	# 神圣十字 - 交叉激光+米字弹幕
	await _danmaku_cross_laser(12, 15, 14.0, "res://assets/sprites/bossbullut-5.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_cross_pattern(16, 8, 30.0, 11.0, "res://assets/sprites/bossbullut-5.png")

func _boss6_eternal_spiral() -> void:
	# 永恒螺旋 - 螺旋追踪组合
	await _danmaku_spiral_tracking_combo(4, 12, "res://assets/sprites/bossbullut-11.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_rotating_square(140.0, 10, 1.2, 10.0, "res://assets/sprites/bossbullut-3.png")

func _boss6_apocalypse() -> void:
	# 天启 - 所有模式组合
	await _danmaku_flower_pattern(24, 0, 12.0, "res://assets/sprites/bossbullut-10.png")
	await get_tree().create_timer(0.2).timeout
	await _danmaku_heart(25, 80.0, 11.0, "res://assets/sprites/bossbullut-1.png")
	await get_tree().create_timer(0.2).timeout
	await _danmaku_pentagram(110.0, 10, 12.0, "res://assets/sprites/bossbullut-10.png")
	await get_tree().create_timer(0.2).timeout
	await _danmaku_explosion_ring(5, 20, 0.15, 1.5, "res://assets/sprites/bossbullut-6.png")

# ============================================================================
# 特殊子弹类型技能
# ============================================================================

func _special_butterfly_swarm() -> void:
	# 蝴蝶弹群
	if not bullet_scene or not get_parent():
		return
	for i in range(12):
		var angle = (TAU / 12) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 150.0
		bullet.bullet_type = EnemyBullet.BulletType.BUTTERFLY
		bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.1).timeout

func _special_laser_cross() -> void:
	# 激光十字
	if not bullet_scene or not get_parent():
		return
	var directions = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
	for dir in directions:
		for i in range(8):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position + dir * i * 30
			bullet.direction = dir
			bullet.speed = 300.0
			bullet.bullet_type = EnemyBullet.BulletType.LASER
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _special_split_bomb() -> void:
	# 分裂弹幕
	if not bullet_scene or not get_parent():
		return
	for i in range(8):
		var angle = (TAU / 8) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 180.0
		bullet.bullet_type = EnemyBullet.BulletType.SPLIT
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(1.5).timeout

func _special_spiral_madness() -> void:
	# 螺旋狂舞
	if not bullet_scene or not get_parent():
		return
	for i in range(16):
		var angle = (TAU / 16) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 120.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout

func _special_homing_hell() -> void:
	# 追踪地狱
	if not bullet_scene or not get_parent():
		return
	for i in range(15):
		var angle = randf() * TAU
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 100.0
		bullet.bullet_type = EnemyBullet.BulletType.HOMING
		bullet._homing_strength = 3.0
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _special_wave_wall() -> void:
	# 波浪墙
	if not bullet_scene or not get_parent():
		return
	for wave in range(3):
		for i in range(10):
			var x_offset = (i - 5) * 50
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position + Vector2(x_offset, -100)
			bullet.direction = Vector2.DOWN
			bullet.speed = 150.0
			bullet.bullet_type = EnemyBullet.BulletType.WAVE_SINE if wave % 2 == 0 else EnemyBullet.BulletType.WAVE_COS
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout

func _special_accelerate_burst() -> void:
	# 加速爆发
	if not bullet_scene or not get_parent():
		return
	for i in range(12):
		var angle = (TAU / 12) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 50.0
		bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.5).timeout

func _special_decelerate_trap() -> void:
	# 减速陷阱
	if not bullet_scene or not get_parent():
		return
	for i in range(16):
		var angle = (TAU / 16) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 250.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.5).timeout

func _special_bounce_chaos() -> void:
	# 弹跳混沌
	if not bullet_scene or not get_parent():
		return
	for i in range(20):
		var angle = randf() * TAU
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 200.0
		bullet.bullet_type = EnemyBullet.BulletType.BOUNCE
		bullet.can_return = true
		bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.1).timeout

func _special_ultimate_chaos() -> void:
	# 终极混沌 - 所有特殊子弹类型组合
	if not bullet_scene or not get_parent():
		return
	# 蝴蝶弹
	for i in range(6):
		var angle = (TAU / 6) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 150.0
		bullet.bullet_type = EnemyBullet.BulletType.BUTTERFLY
		bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
		get_parent().add_child(bullet)

	await get_tree().create_timer(0.3).timeout

	# 螺旋弹
	for i in range(8):
		var angle = (TAU / 8) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 120.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(bullet)

	await get_tree().create_timer(0.3).timeout

	# 追踪弹
	for i in range(5):
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(randf() * 2 - 1, randf() * 2 - 1).normalized()
		bullet.speed = 100.0
		bullet.bullet_type = EnemyBullet.BulletType.HOMING
		bullet._homing_strength = 4.0
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.2).timeout

	await get_tree().create_timer(0.3).timeout

	# 分裂弹
	for i in range(6):
		var angle = (TAU / 6) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 180.0
		bullet.bullet_type = EnemyBullet.BulletType.SPLIT
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)

# =============================================================================
# NONSPELL 1 - Opening Inferno (10 skills)
# =============================================================================

func _boss6_hellfire_rain() -> void:
	# Dense fire rain from the top of the screen
	if not bullet_scene or not get_parent():
		return
	for wave in range(5):
		for i in range(12):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(
				global_position.x + randf_range(-300.0, 300.0),
				global_position.y - 40.0
			)
			var angle = PI / 2.0 + randf_range(-0.3, 0.3)
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = randf_range(140.0, 220.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout

func _boss6_inferno_spiral() -> void:
	# Triple interleaving fire spirals
	if not bullet_scene or not get_parent():
		return
	for step in range(36):
		for arm in range(3):
			var base_angle = step * 0.175 + arm * (TAU / 3.0)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(base_angle), sin(base_angle))
			bullet.speed = 160.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout

func _boss6_flame_wheel() -> void:
	# Rotating fire wheel that expands outward
	if not bullet_scene or not get_parent():
		return
	for rotation in range(8):
		var offset_angle = rotation * 0.25
		for spoke in range(16):
			var angle = spoke * (TAU / 16.0) + offset_angle
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 130.0 + rotation * 10.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.25).timeout

func _boss6_ember_scatter() -> void:
	# Random ember spray in a wide cone toward the player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var aim_angle = global_position.direction_to(player.global_position).angle()
	for burst in range(6):
		for i in range(10):
			var spread = randf_range(-0.6, 0.6)
			var angle = aim_angle + spread
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = randf_range(120.0, 260.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.2).timeout

func _boss6_blaze_wave() -> void:
	# Horizontal fire waves sweeping left and right
	if not bullet_scene or not get_parent():
		return
	for wave in range(6):
		var direction_sign = 1.0 if wave % 2 == 0 else -1.0
		for i in range(15):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(
				global_position.x + direction_sign * -200.0,
				global_position.y + i * 20.0 - 140.0
			)
			bullet.direction = Vector2(direction_sign, 0.15 * sin(i * 0.5))
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

func _boss6_fire_serpent() -> void:
	# Curving fire snakes that weave toward the player
	if not bullet_scene or not get_parent():
		return
	for serpent in range(4):
		var player := _get_player_safe()
		if not player:
			return
		var base_angle := global_position.direction_to(player.global_position).angle()
		base_angle += serpent * 0.4 - 0.6
		for segment in range(12):
			if not is_instance_valid(self) or not is_inside_tree() or not get_parent():
				return
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			var wobble = sin(segment * 0.8) * 0.3
			bullet.direction = Vector2(cos(base_angle + wobble), sin(base_angle + wobble))
			bullet.speed = 150.0 + segment * 5.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.05).timeout
		await get_tree().create_timer(0.2).timeout

func _boss6_magma_burst() -> void:
	# Explosive magma rings that expand in staggered layers
	if not bullet_scene or not get_parent():
		return
	for ring in range(5):
		var bullet_count = 16 + ring * 4
		var ring_offset = ring * 0.1
		for i in range(bullet_count):
			var angle = i * (TAU / bullet_count) + ring_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 100.0 + ring * 30.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.35).timeout

func _boss6_volcanic_eruption() -> void:
	# Bullets shoot upward then arc downward like volcanic debris
	if not bullet_scene or not get_parent():
		return
	for burst in range(4):
		for i in range(14):
			var spread_angle = -PI / 2.0 + randf_range(-0.8, 0.8)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = randf_range(200.0, 300.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss6_heat_haze() -> void:
	# Wavy distorted fire bullets in sine wave patterns
	if not bullet_scene or not get_parent():
		return
	for wave in range(8):
		for i in range(8):
			var angle = wave * 0.15 + i * (TAU / 8.0)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 140.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.2).timeout

func _boss6_pyroclastic_flow() -> void:
	# Dense flowing fire that fills the lower screen
	if not bullet_scene or not get_parent():
		return
	for wave in range(6):
		for i in range(18):
			var x_offset = i * 40.0 - 340.0
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(global_position.x + x_offset, global_position.y)
			var angle = PI / 2.0 + sin(i * 0.3 + wave * 0.5) * 0.4
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = randf_range(100.0, 180.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout

# =============================================================================
# SPELL 1 - Pentagram Patterns (10 skills)
# =============================================================================

func _boss6_pentagram_seal() -> void:
	# Five-pointed star burst
	if not bullet_scene or not get_parent():
		return
	for rotation in range(5):
		for point in range(5):
			var base_angle = (TAU / 5) * point + rotation * 0.2
			for i in range(10):
				var angle = base_angle + (i - 4.5) * 0.08
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(angle), sin(angle))
				bullet.speed = 180.0 + i * 5.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss6_hexagram_bind() -> void:
	# Six-pointed star pattern
	if not bullet_scene or not get_parent():
		return
	for rotation in range(4):
		# Triangle 1
		for point in range(3):
			var angle = (TAU / 3) * point + rotation * 0.15
			for i in range(8):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(angle + i * 0.1), sin(angle + i * 0.1))
				bullet.speed = 170.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
		# Triangle 2 (inverted)
		for point in range(3):
			var angle = (TAU / 3) * point + PI / 3 + rotation * 0.15
			for i in range(8):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(angle + i * 0.1), sin(angle + i * 0.1))
				bullet.speed = 170.0
				bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.7).timeout

func _boss6_sacred_geometry() -> void:
	# Geometric patterns - concentric polygons
	if not bullet_scene or not get_parent():
		return
	for polygon in range(4):
		var sides = 3 + polygon
		var bullets_per_side = 8
		for side in range(sides):
			var start_angle = (TAU / sides) * side
			var end_angle = (TAU / sides) * (side + 1)
			for i in range(bullets_per_side):
				var t = float(i) / bullets_per_side
				var angle = lerp(start_angle, end_angle, t)
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(angle), sin(angle))
				bullet.speed = 150.0 + polygon * 20.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss6_runic_circle() -> void:
	# Circular rune patterns
	if not bullet_scene or not get_parent():
		return
	for circle in range(3):
		var radius = 100.0 + circle * 80.0
		var count = 24 + circle * 8
		for i in range(count):
			var angle = (TAU / count) * i
			var spawn_pos = global_position + Vector2(cos(angle), sin(angle)) * radius
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = Vector2(cos(angle + PI/2), sin(angle + PI/2))
			bullet.speed = 160.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss6_sigil_storm() -> void:
	# Multiple sigil bursts
	if not bullet_scene or not get_parent():
		return
	for sigil in range(6):
		var sigil_pos = global_position + Vector2(randf() * 300 - 150, randf() * 200 - 100)
		for i in range(20):
			var angle = (TAU / 20) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = sigil_pos
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss6_arcane_web() -> void:
	# Web of magic bullets
	if not bullet_scene or not get_parent():
		return
	for layer in range(5):
		# Radial lines
		for i in range(12):
			var angle = (TAU / 12) * i + layer * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 160.0 + layer * 10.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		# Connecting arcs
		for i in range(24):
			var angle = (TAU / 24) * i + layer * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 140.0 + layer * 10.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss6_mystic_spiral() -> void:
	# Magic spiral with dual arms
	if not bullet_scene or not get_parent():
		return
	for i in range(80):
		for arm in range(2):
			var angle = i * 0.35 + arm * PI
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout

func _boss6_enchant_ring() -> void:
	# Enchanted expanding rings with rotation
	if not bullet_scene or not get_parent():
		return
	for ring in range(8):
		var count = 20 + ring * 2
		var offset = ring * 0.3
		for i in range(count):
			var angle = (TAU / count) * i + offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 120.0 + ring * 15.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.35).timeout

func _boss6_spell_weave() -> void:
	# Interlocking spell patterns
	if not bullet_scene or not get_parent():
		return
	for weave in range(6):
		# Pattern A: clockwise
		for i in range(16):
			var angle = (TAU / 16) * i + weave * 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 170.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.2).timeout
		# Pattern B: counter-clockwise
		for i in range(16):
			var angle = (TAU / 16) * i - weave * 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 190.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout

func _boss6_grimoire_page() -> void:
	# Page-like bullet walls
	if not bullet_scene or not get_parent():
		return
	for page in range(4):
		var direction = 1 if page % 2 == 0 else -1
		for row in range(8):
			for col in range(6):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = Vector2(
					global_position.x + direction * (-200 + col * 60),
					global_position.y - 100 + row * 30
				)
				bullet.direction = Vector2(direction, 0.1 * sin(col * 0.5))
				bullet.speed = 180.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

# =============================================================================
# NONSPELL 2 - Convergence Patterns (10 skills)
# =============================================================================

func _boss6_convergence_beam() -> void:
	# Converging beams from multiple angles
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for beam in range(6):
		for source in range(4):
			var source_angle = (TAU / 4) * source
			var source_pos = global_position + Vector2(cos(source_angle), sin(source_angle)) * 300
			var aim_dir = (player.global_position - source_pos).normalized()
			for i in range(8):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = source_pos
				bullet.direction = aim_dir.rotated((i - 3.5) * 0.1)
				bullet.speed = 220.0
				bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss6_cross_fire() -> void:
	# Cross-shaped fire patterns
	if not bullet_scene or not get_parent():
		return
	for cross in range(5):
		# Horizontal
		for i in range(20):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(1, 0).rotated(cross * 0.15)
			bullet.speed = 150.0 + i * 5.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
			var bullet2 = bullet_scene.instantiate() as EnemyBullet
			bullet2.global_position = global_position
			bullet2.direction = Vector2(-1, 0).rotated(cross * 0.15)
			bullet2.speed = 150.0 + i * 5.0
			bullet2.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet2)
		# Vertical
		for i in range(20):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(0, 1).rotated(cross * 0.15)
			bullet.speed = 150.0 + i * 5.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
			var bullet2 = bullet_scene.instantiate() as EnemyBullet
			bullet2.global_position = global_position
			bullet2.direction = Vector2(0, -1).rotated(cross * 0.15)
			bullet2.speed = 150.0 + i * 5.0
			bullet2.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet2)
		await get_tree().create_timer(0.7).timeout

func _boss6_pincer_attack() -> void:
	# Bullets from multiple angles simultaneously
	if not bullet_scene or not get_parent():
		return
	for pincer in range(5):
		# Left side
		for i in range(12):
			var angle = -PI/4 + i * 0.1
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(100, 200 + i * 30)
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		# Right side
		for i in range(12):
			var angle = PI + PI/4 - i * 0.1
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(800, 200 + i * 30)
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss6_encirclement() -> void:
	# Surrounding bullet rings that close in
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for ring in range(4):
		var center = player.global_position
		var radius = 350.0 - ring * 50.0
		var count = 28 + ring * 4
		for i in range(count):
			var angle = (TAU / count) * i
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * radius
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = (center - spawn_pos).normalized()
			bullet.speed = 120.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

func _boss6_vortex_pull() -> void:
	# Pulling vortex pattern
	if not bullet_scene or not get_parent():
		return
	for vortex in range(3):
		for i in range(40):
			var angle = i * 0.5
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.04).timeout
		await get_tree().create_timer(0.5).timeout

func _boss6_dimension_rift() -> void:
	# Bullets from random positions
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for rift in range(8):
		var rift_pos = Vector2(150 + randf() * 600, 100 + randf() * 400)
		var aim_dir = (player.global_position - rift_pos).normalized()
		for i in range(10):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = rift_pos
			bullet.direction = aim_dir.rotated((i - 4.5) * 0.15)
			bullet.speed = 210.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

func _boss6_gravity_well() -> void:
	# Gravity-affected bullets
	if not bullet_scene or not get_parent():
		return
	for well in range(5):
		for i in range(28):
			var angle = (TAU / 28) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss6_time_warp_bullets() -> void:
	# Speed-varying bullets
	if not bullet_scene or not get_parent():
		return
	for warp in range(6):
		for i in range(24):
			var angle = (TAU / 24) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 100.0 + (i % 6) * 40.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss6_mirror_dimension() -> void:
	# Mirrored patterns
	if not bullet_scene or not get_parent():
		return
	for mirror in range(5):
		for i in range(20):
			var angle = i * 0.3
			# Original
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
			# Mirror
			var mirror_bullet = bullet_scene.instantiate() as EnemyBullet
			mirror_bullet.global_position = global_position
			mirror_bullet.direction = Vector2(cos(-angle), sin(-angle))
			mirror_bullet.speed = 180.0
			mirror_bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(mirror_bullet)
			await get_tree().create_timer(0.06).timeout
		await get_tree().create_timer(0.4).timeout

func _boss6_phase_shift() -> void:
	# Alternating pattern phases
	if not bullet_scene or not get_parent():
		return
	for shift in range(6):
		if shift % 2 == 0:
			# Phase A: rings
			for i in range(24):
				var angle = (TAU / 24) * i
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(angle), sin(angle))
				bullet.speed = 190.0
				bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(bullet)
		else:
			# Phase B: aimed
			var player = get_tree().get_first_node_in_group("player")
			if player:
				var aim = global_position.direction_to(player.global_position).angle()
				for i in range(12):
					var spread = aim + (i - 5.5) * 0.2
					var bullet = bullet_scene.instantiate() as EnemyBullet
					bullet.global_position = global_position
					bullet.direction = Vector2(cos(spread), sin(spread))
					bullet.speed = 230.0
					bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
					get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

# =============================================================================
# SPELL 2 - Cathedral Patterns (10 skills)
# =============================================================================

func _boss6_cathedral_pillars() -> void:
	# Vertical laser pillars
	if not bullet_scene or not get_parent():
		return
	for pillar in range(6):
		var x_pos = 150 + pillar * 120
		for i in range(15):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50 + i * 5)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 250.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

func _boss6_stained_glass() -> void:
	# Colorful geometric patterns
	if not bullet_scene or not get_parent():
		return
	var sprites = [
		"res://assets/sprites/bossbullut-1.png",
		"res://assets/sprites/bossbullut-3.png",
		"res://assets/sprites/bossbullut-5.png",
		"res://assets/sprites/bossbullut-6.png",
		"res://assets/sprites/bossbullut-9.png",
		"res://assets/sprites/bossbullut-11.png"
	]
	for pattern in range(4):
		for i in range(36):
			var angle = (TAU / 36) * i + pattern * 0.1
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 170.0
			bullet.set_sprite(sprites[i % sprites.size()])
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss6_holy_cross() -> void:
	# Cross-shaped laser pattern
	if not bullet_scene or not get_parent():
		return
	for cross in range(4):
		var rotation = cross * PI / 8
		# Horizontal arm
		for i in range(25):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(rotation), sin(rotation))
			bullet.speed = 100.0 + i * 8.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
			var bullet2 = bullet_scene.instantiate() as EnemyBullet
			bullet2.global_position = global_position
			bullet2.direction = Vector2(cos(rotation + PI), sin(rotation + PI))
			bullet2.speed = 100.0 + i * 8.0
			bullet2.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet2)
		# Vertical arm
		for i in range(25):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(rotation + PI/2), sin(rotation + PI/2))
			bullet.speed = 100.0 + i * 8.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
			var bullet2 = bullet_scene.instantiate() as EnemyBullet
			bullet2.global_position = global_position
			bullet2.direction = Vector2(cos(rotation + 3*PI/2), sin(rotation + 3*PI/2))
			bullet2.speed = 100.0 + i * 8.0
			bullet2.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet2)
		await get_tree().create_timer(0.8).timeout

func _boss6_divine_judgment_aimed() -> void:
	# Aimed divine beams
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for judgment in range(8):
		var aim = global_position.direction_to(player.global_position).angle()
		for i in range(15):
			var spread = aim + (i - 7) * 0.12
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

func _boss6_angel_wings() -> void:
	# Wing-shaped bullet fans
	if not bullet_scene or not get_parent():
		return
	for wing in range(4):
		# Left wing
		for i in range(15):
			var angle = PI + PI/6 + i * 0.08
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0 + i * 3.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		# Right wing
		for i in range(15):
			var angle = -PI/6 - i * 0.08
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0 + i * 3.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.7).timeout

func _boss6_heaven_gate() -> void:
	# Gate-like bullet walls
	if not bullet_scene or not get_parent():
		return
	for gate in range(4):
		# Left pillar
		for i in range(12):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(global_position.x - 150, global_position.y - 100 + i * 20)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		# Right pillar
		for i in range(12):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(global_position.x + 150, global_position.y - 100 + i * 20)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		# Arch
		for i in range(16):
			var angle = PI + (TAU / 32) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position + Vector2(0, -100)
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 160.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

func _boss6_sacred_arrow() -> void:
	# Divine aimed arrows
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for arrow in range(10):
		var aim = global_position.direction_to(player.global_position).angle()
		# Arrow head
		for i in range(5):
			var spread = aim + (i - 2) * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 250.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 2.0
			bullet._homing_duration = 0.4
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		# Arrow trail
		for i in range(8):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(aim), sin(aim))
			bullet.speed = 230.0 - i * 10.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.35).timeout

func _boss6_blessing_rain() -> void:
	# Dense divine rain
	if not bullet_scene or not get_parent():
		return
	for rain in range(6):
		for i in range(25):
			var x_pos = 100 + randf() * 700
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50)
			bullet.direction = Vector2(sin(i * 0.3) * 0.2, 1).normalized()
			bullet.speed = 220.0 + randf() * 40.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.03).timeout
		await get_tree().create_timer(0.4).timeout

func _boss6_choir_of_light() -> void:
	# Rhythmic light bursts
	if not bullet_scene or not get_parent():
		return
	for choir in range(8):
		var count = 16 + (choir % 3) * 4
		for i in range(count):
			var angle = (TAU / count) * i + choir * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

func _boss6_sanctuary_seal() -> void:
	# Sealing ring patterns
	if not bullet_scene or not get_parent():
		return
	for seal in range(3):
		# Inner ring
		for i in range(20):
			var angle = (TAU / 20) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 140.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.2).timeout
		# Middle ring
		for i in range(28):
			var angle = (TAU / 28) * i + 0.1
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 170.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.2).timeout
		# Outer ring
		for i in range(36):
			var angle = (TAU / 36) * i + 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.8).timeout

# =============================================================================
# FINAL - Apocalypse (8 skills)
# =============================================================================

func _boss6_ragnarok() -> void:
	# All elements combined
	if not bullet_scene or not get_parent():
		return
	# Fire spiral
	for i in range(30):
		var angle = i * 0.5
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 200.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.3).timeout
	# Lightning burst
	for i in range(24):
		var angle = (TAU / 24) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 250.0
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.3).timeout
	# Gravity pull
	for i in range(32):
		var angle = (TAU / 32) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 180.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)

func _boss6_genesis_wave() -> void:
	# Creation-level burst
	if not bullet_scene or not get_parent():
		return
	for wave in range(5):
		var count = 24 + wave * 8
		for i in range(count):
			var angle = (TAU / count) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 160.0 + wave * 25.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.4).timeout

func _boss6_void_collapse() -> void:
	# Collapsing void
	if not bullet_scene or not get_parent():
		return
	for collapse in range(4):
		# Outward
		for i in range(40):
			var angle = (TAU / 40) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 220.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout
		# Inward spiral
		for i in range(30):
			var angle = i * 0.4
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss6_cosmic_storm() -> void:
	# Space-themed chaos
	if not bullet_scene or not get_parent():
		return
	for storm in range(5):
		# Random bursts
		for i in range(30):
			var angle = randf() * TAU
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position + Vector2(randf() * 200 - 100, randf() * 200 - 100)
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 150.0 + randf() * 100.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		# Spiral overlay
		for i in range(16):
			var angle = storm * 0.5 + i * 0.4
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.6).timeout

func _boss6_eternal_flame() -> void:
	# Infinite fire spiral
	if not bullet_scene or not get_parent():
		return
	for i in range(120):
		for arm in range(4):
			var angle = i * 0.3 + arm * TAU / 4
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 190.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout

func _boss6_omega_burst() -> void:
	# Ultimate burst
	if not bullet_scene or not get_parent():
		return
	for burst in range(3):
		# Dense ring
		for i in range(60):
			var angle = (TAU / 60) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 240.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.3).timeout
		# Aimed burst
		var player = get_tree().get_first_node_in_group("player")
		if player:
			var aim = global_position.direction_to(player.global_position).angle()
			for i in range(20):
				var spread = aim + (i - 9.5) * 0.12
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 280.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.5).timeout

func _boss6_armageddon_rain() -> void:
	# Dense rain of everything
	if not bullet_scene or not get_parent():
		return
	for rain in range(5):
		# Top rain
		for i in range(20):
			var x_pos = 100 + randf() * 700
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 50)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 250.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		# Side bullets
		for i in range(10):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(50, 100 + i * 50)
			bullet.direction = Vector2(1, 0.2)
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
			var bullet2 = bullet_scene.instantiate() as EnemyBullet
			bullet2.global_position = Vector2(850, 100 + i * 50)
			bullet2.direction = Vector2(-1, 0.2)
			bullet2.speed = 200.0
			bullet2.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet2)
		await get_tree().create_timer(0.5).timeout

func _boss6_final_revelation() -> void:
	# Ultimate combined pattern
	if not bullet_scene or not get_parent():
		return
	# Phase 1: Spiral
	for i in range(40):
		var angle = i * 0.4
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 200.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.3).timeout
	# Phase 2: Rings
	for ring in range(3):
		for i in range(40):
			var angle = (TAU / 40) * i + ring * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0 + ring * 20.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.2).timeout
	# Phase 3: Aimed
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var aim = global_position.direction_to(player.global_position).angle()
		for i in range(24):
			var spread = aim + (i - 11.5) * 0.1
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
