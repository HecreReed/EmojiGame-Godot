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
				Callable(self, "_special_wave_wall")
			]
			spell1_pool = [
				Callable(self, "_boss1_star_shoot"),
				Callable(self, "_boss1_mirror_shoot"),
				Callable(self, "_boss1_spiral_trap"),
				Callable(self, "_special_spiral_madness")
			]
			spell2_pool = [
				Callable(self, "_boss1_summon_teleport"),
				Callable(self, "_boss1_portal_pattern"),
				Callable(self, "_special_accelerate_burst"),
				Callable(self, "_special_homing_hell")
			]
		2:
			nonspell_pool = [
				Callable(self, "_boss2_nonspell_step"),
				Callable(self, "_boss2_generate_love"),
				Callable(self, "_boss2_heart_trap"),
				Callable(self, "_special_butterfly_swarm")
			]
			spell1_pool = [
				Callable(self, "_boss2_use_attract"),
				Callable(self, "_boss2_heart_rain"),
				Callable(self, "_boss2_heart_orbit_dive"),
				Callable(self, "_special_homing_hell")
			]
			spell2_pool = [
				Callable(self, "_boss2_split_bomb"),
				Callable(self, "_boss2_reverse_time"),
				Callable(self, "_boss2_made_in_heaven"),
				Callable(self, "_special_split_bomb")
			]
		3:
			nonspell_pool = [
				Callable(self, "_boss3_nonspell_step"),
				Callable(self, "_boss3_super_shoot"),
				Callable(self, "_boss3_thshoot"),
				Callable(self, "_special_decelerate_trap")
			]
			spell1_pool = [
				Callable(self, "_boss3_time_stop"),
				Callable(self, "_boss3_time_bubble"),
				Callable(self, "_boss3_golden_storm"),
				Callable(self, "_special_spiral_madness")
			]
			spell2_pool = [
				Callable(self, "_boss3_coin_barrage"),
				Callable(self, "_boss3_time_lock_ring"),
				Callable(self, "_boss3_time_lock_mines"),
				Callable(self, "_special_accelerate_burst")
			]
		4:
			nonspell_pool = [
				Callable(self, "_boss4_light_single"),
				Callable(self, "_boss4_drag_shoot"),
				Callable(self, "_boss4_side_shoot"),
				Callable(self, "_special_wave_wall")
			]
			spell1_pool = [
				Callable(self, "_boss4_screen_static"),
				Callable(self, "_boss4_light_shoot"),
				Callable(self, "_boss4_orbital_strike"),
				Callable(self, "_special_laser_cross")
			]
			spell2_pool = [
				Callable(self, "_boss4_pixel_storm"),
				Callable(self, "_boss4_glitch_packets"),
				Callable(self, "_boss4_summon_ufo"),
				Callable(self, "_special_bounce_chaos")
			]
		5:
			nonspell_pool = [
				Callable(self, "_boss5_throw_tnt"),
				Callable(self, "_boss5_jump_shoot"),
				Callable(self, "_boss5_double_shoot"),
				Callable(self, "_special_accelerate_burst")
			]
			spell1_pool = [
				Callable(self, "_boss5_heal_mode"),
				Callable(self, "_boss5_chain_explosion"),
				Callable(self, "_boss5_gravity_sink"),
				Callable(self, "_special_split_bomb")
			]
			spell2_pool = [
				Callable(self, "_boss5_mirror_tnt"),
				Callable(self, "_special_bounce_chaos"),
				Callable(self, "_special_ultimate_chaos"),
				Callable(self, "_special_homing_hell")
			]
		6:
			nonspell_pool = [
				Callable(self, "_boss6_phase1_fire_rain"),
				Callable(self, "_boss6_ember_scatter"),
				Callable(self, "_boss6_blaze_wave"),
				Callable(self, "_special_butterfly_swarm"),
				Callable(self, "_special_wave_wall")
			]
			spell1_pool = [
				Callable(self, "_boss6_spell1_spiral_fire"),
				Callable(self, "_boss6_inferno_spiral"),
				Callable(self, "_boss6_flame_wheel"),
				Callable(self, "_special_spiral_madness"),
				Callable(self, "_special_homing_hell")
			]
			spell2_pool = [
				Callable(self, "_boss6_fire_serpent"),
				Callable(self, "_boss6_horizontal_laser_pattern"),
				Callable(self, "_boss6_galaxy_burst"),
				Callable(self, "_special_laser_cross"),
				Callable(self, "_special_accelerate_burst"),
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
	phases.append(_make_phase_mix(PhaseKind.NONSPELL, "Mid Nonspell", hps[0], 35.0, 0.65, 0.30, 0.9, nonspell_pool[0], nonspell_pool))
	phases.append(_make_phase_mix(PhaseKind.SPELL, "Mid Spell 1", hps[1], 45.0, 0.0, 0.25, 1.1, spell1_pool[0], spell1_pool))
	if spell_count >= 2 and hps.size() >= 3:
		phases.append(_make_phase_mix(PhaseKind.SPELL, "Mid Spell 2", hps[2], 48.0, 0.0, 0.22, 1.2, spell2_pool[0], spell2_pool, PatternPoolMode.CYCLE))
	return phases

func _build_boss1_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])

	# Nonspell 1: Desert Awakening - 5 unique skills
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss1_sandstorm_prelude"),
		Callable(self, "_boss1_desert_wind"),
		Callable(self, "_boss1_sand_ripples"),
		Callable(self, "_boss1_dune_cascade"),
		Callable(self, "_boss1_mirage_shimmer")
	]

	# Spell 1: Lightning Tempest - 5 unique skills
	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss1_lightning_barrage"),
		Callable(self, "_boss1_thunder_spiral"),
		Callable(self, "_boss1_storm_vortex"),
		Callable(self, "_boss1_electric_web"),
		Callable(self, "_boss1_plasma_burst")
	]

	# Nonspell 2: Desert Summoning - 5 summoning skills
	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss1_sand_guardian_summon"),
		Callable(self, "_boss1_scarab_swarm"),
		Callable(self, "_boss1_pharaoh_guard"),
		Callable(self, "_boss1_obelisk_ritual"),
		Callable(self, "_boss1_desert_legion")
	]

	# Spell 2: Gravity Manipulation - 5 unique skills
	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss1_gravity_lens"),
		Callable(self, "_boss1_event_horizon_ring"),
		Callable(self, "_boss1_spacetime_tear"),
		Callable(self, "_boss1_singularity_burst"),
		Callable(self, "_boss1_gravity_storm")
	]

	# Final: Cataclysm - 5 unique skills
	var final_pool: Array[Callable] = [
		Callable(self, "_boss1_desert_apocalypse"),
		Callable(self, "_boss1_cosmic_mirage"),
		Callable(self, "_boss1_eternal_storm"),
		Callable(self, "_boss1_void_serpent"),
		Callable(self, "_boss1_cataclysm")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Sandstorm Prelude", hps[0], 38.0, 0.6, 0.25, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Chain Lightning", hps[1], 55.0, 0.0, 0.18, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Desert Summoning", hps[2], 38.0, 0.55, 0.25, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Singularity Pull", hps[3], 60.0, 0.0, 0.18, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Event Horizon", hps[4], 70.0, 0.45, 0.14, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
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

		await get_tree().create_timer(0.20).timeout

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

	# Spell 1: Dark Heart - 5 unique skills
	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss2_black_heart_expand"),
		Callable(self, "_boss2_jealousy_thorns"),
		Callable(self, "_boss2_heartstring_web"),
		Callable(self, "_boss2_passion_rain"),
		Callable(self, "_boss2_dark_cupid")
	]

	# Nonspell 2: Heart Rain - 5 unique skills
	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss2_valentine_storm"),
		Callable(self, "_boss2_love_letter_cascade"),
		Callable(self, "_boss2_rose_petal_fall"),
		Callable(self, "_boss2_confession_barrage"),
		Callable(self, "_boss2_broken_mirror")
	]

	# Spell 2: Forbidden Love - 5 unique skills
	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss2_love_cage"),
		Callable(self, "_boss2_heartbreak_rain"),
		Callable(self, "_boss2_dark_devotion"),
		Callable(self, "_boss2_forbidden_kiss"),
		Callable(self, "_boss2_love_labyrinth")
	]

	# Final: Made in Heaven - 5 unique super skills
	var final_pool: Array[Callable] = [
		Callable(self, "_boss2_eternal_love"),
		Callable(self, "_boss2_heaven_ascension"),
		Callable(self, "_boss2_heartbreak_apocalypse"),
		Callable(self, "_boss2_love_transcendence"),
		Callable(self, "_boss2_ultimate_heartbreak")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Heartbeat Barrage", hps[0], 45.0, 0.65, 0.25, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Dark Heart", hps[1], 60.0, 0.0, 0.18, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Heart Rain", hps[2], 45.0, 0.6, 0.25, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Forbidden Love", hps[3], 62.0, 0.0, 0.18, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Made in Heaven", hps[4], 78.0, 0.5, 0.14, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
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

		await get_tree().create_timer(0.20).timeout

func _build_boss3_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])

	# Nonspell 1: Clockwork Assault - 5 unique skills
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss3_clock_hand_sweep"),
		Callable(self, "_boss3_gear_grind"),
		Callable(self, "_boss3_pendulum_barrage"),
		Callable(self, "_boss3_minute_hand_rain"),
		Callable(self, "_boss3_tick_tock_burst")
	]

	# Spell 1: Temporal Rift - 5 unique skills
	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss3_time_warp_volley"),
		Callable(self, "_boss3_afterimage_assault"),
		Callable(self, "_boss3_temporal_shatter"),
		Callable(self, "_boss3_chrono_cage"),
		Callable(self, "_boss3_rewind_spiral")
	]

	# Nonspell 2: Phantom Clock - 5 unique skills
	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss3_phantom_strike"),
		Callable(self, "_boss3_clone_barrage"),
		Callable(self, "_boss3_ghost_spiral"),
		Callable(self, "_boss3_time_echo"),
		Callable(self, "_boss3_phantom_cage")
	]

	# Spell 2: ZA WARUDO - 5 unique skills
	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss3_world_freeze"),
		Callable(self, "_boss3_stopped_time_knives"),
		Callable(self, "_boss3_time_skip_assault"),
		Callable(self, "_boss3_road_roller"),
		Callable(self, "_boss3_time_resume")
	]

	# Final: Chronos Apocalypse - 5 super skills
	var final_pool: Array[Callable] = [
		Callable(self, "_boss3_time_collapse"),
		Callable(self, "_boss3_chronos_wrath"),
		Callable(self, "_boss3_eternity_end"),
		Callable(self, "_boss3_temporal_singularity"),
		Callable(self, "_boss3_omega_timeline")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Clockwork Assault", hps[0], 45.0, 0.6, 0.25, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Temporal Rift", hps[1], 62.0, 0.0, 0.18, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Phantom Clock", hps[2], 45.0, 0.55, 0.25, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "ZA WARUDO", hps[3], 65.0, 0.0, 0.18, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Chronos Apocalypse", hps[4], 82.0, 0.5, 0.14, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
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

	# Nonspell 1: Digital Chaos - 5 unique skills
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss4_static_spray"),
		Callable(self, "_boss4_glitch_scatter"),
		Callable(self, "_boss4_pixel_rain"),
		Callable(self, "_boss4_data_corruption"),
		Callable(self, "_boss4_noise_burst")
	]

	# Spell 1: Narrow Escape - 5 unique skills
	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss4_closing_walls"),
		Callable(self, "_boss4_corridor_sweep"),
		Callable(self, "_boss4_shrinking_ring"),
		Callable(self, "_boss4_cage_squeeze"),
		Callable(self, "_boss4_pixel_maze")
	]

	# Nonspell 2: Size Shift - 5 unique skills
	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss4_pulse_expand"),
		Callable(self, "_boss4_breathing_cage"),
		Callable(self, "_boss4_zoom_barrage"),
		Callable(self, "_boss4_inflate_burst"),
		Callable(self, "_boss4_scale_spiral")
	]

	# Spell 2: System Override - 5 unique skills
	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss4_firewall_breach"),
		Callable(self, "_boss4_overflow_cascade"),
		Callable(self, "_boss4_virus_swarm"),
		Callable(self, "_boss4_kernel_panic"),
		Callable(self, "_boss4_blue_screen")
	]

	# Final: Total Meltdown - 5 super skills
	var final_pool: Array[Callable] = [
		Callable(self, "_boss4_system_meltdown"),
		Callable(self, "_boss4_digital_apocalypse"),
		Callable(self, "_boss4_matrix_shatter"),
		Callable(self, "_boss4_total_corruption"),
		Callable(self, "_boss4_final_shutdown")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Digital Chaos", hps[0], 45.0, 0.6, 0.25, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Narrow Escape", hps[1], 62.0, 0.0, 0.18, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Size Shift", hps[2], 45.0, 0.55, 0.25, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "System Override", hps[3], 65.0, 0.0, 0.18, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Total Meltdown", hps[4], 85.0, 0.5, 0.14, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
	]

func _build_boss5_phases(total_hp: int) -> Array[BossPhaseDef]:
	var hps := _alloc_phase_hp(total_hp, [0.18, 0.20, 0.18, 0.20, 0.24])

	# Nonspell 1: Shrapnel Barrage - 5 explosive skills
	var nonspell_1_pool: Array[Callable] = [
		Callable(self, "_boss5_shrapnel_burst"),
		Callable(self, "_boss5_cluster_bomb"),
		Callable(self, "_boss5_mortar_rain"),
		Callable(self, "_boss5_grenade_scatter"),
		Callable(self, "_boss5_dynamite_chain")
	]

	# Spell 1: Vampiric Drain - 5 blood/life-steal skills
	var spell_1_pool: Array[Callable] = [
		Callable(self, "_boss5_blood_drain"),
		Callable(self, "_boss5_life_siphon"),
		Callable(self, "_boss5_soul_harvest"),
		Callable(self, "_boss5_crimson_vortex"),
		Callable(self, "_boss5_essence_steal")
	]

	# Nonspell 2: Summoning Assault - 5 summoning skills
	var nonspell_2_pool: Array[Callable] = [
		Callable(self, "_boss5_minion_swarm"),
		Callable(self, "_boss5_artillery_summon"),
		Callable(self, "_boss5_phantom_army"),
		Callable(self, "_boss5_trap_field"),
		Callable(self, "_boss5_cross_fire")
	]

	# Spell 2: Dark Barrage - 5 cursed/dark skills
	var spell_2_pool: Array[Callable] = [
		Callable(self, "_boss5_cursed_barrage"),
		Callable(self, "_boss5_death_sentence"),
		Callable(self, "_boss5_hellfire_rain"),
		Callable(self, "_boss5_soul_cage"),
		Callable(self, "_boss5_doom_spiral")
	]

	# Final: Apocalypse - 5 ultimate destruction skills
	var final_pool: Array[Callable] = [
		Callable(self, "_boss5_nuclear_meltdown"),
		Callable(self, "_boss5_armageddon_rain"),
		Callable(self, "_boss5_vampiric_apocalypse"),
		Callable(self, "_boss5_grand_explosion"),
		Callable(self, "_boss5_final_detonation")
	]
	return [
		_make_phase_mix(PhaseKind.NONSPELL, "Shrapnel Barrage", hps[0], 45.0, 0.6, 0.25, 1.0, nonspell_1_pool[0], nonspell_1_pool),
		_make_phase_mix(PhaseKind.SPELL, "Vampiric Drain", hps[1], 62.0, 0.0, 0.18, 1.2, spell_1_pool[0], spell_1_pool),
		_make_phase_mix(PhaseKind.NONSPELL, "Summoning Assault", hps[2], 45.0, 0.55, 0.25, 1.0, nonspell_2_pool[0], nonspell_2_pool),
		_make_phase_mix(PhaseKind.SPELL, "Dark Barrage", hps[3], 68.0, 0.0, 0.18, 1.2, spell_2_pool[0], spell_2_pool),
		_make_phase_mix(PhaseKind.FINAL, "Apocalypse", hps[4], 92.0, 0.5, 0.14, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
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
		_make_phase_mix(PhaseKind.NONSPELL, "Inferno Overture", hps[0], 55.0, 0.5, 0.20, 1.0, nonspell_1_pool[0], nonspell_1_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.SPELL, "Pentagram Blaze", hps[1], 72.0, 0.0, 0.14, 1.2, spell_1_pool[0], spell_1_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.NONSPELL, "Teleport Convergence", hps[2], 58.0, 0.45, 0.18, 1.0, nonspell_2_pool[0], nonspell_2_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.SPELL, "Cross Laser Cathedral", hps[3], 78.0, 0.0, 0.12, 1.2, spell_2_pool[0], spell_2_pool, PatternPoolMode.RANDOM),
		_make_phase_mix(PhaseKind.FINAL, "Apocalypse Symphony", hps[4], 110.0, 0.4, 0.08, 1.0, final_pool[0], final_pool, PatternPoolMode.RANDOM)
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

func _boss6_horizontal_laser_pattern() -> void:
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)
	@warning_ignore("redundant_await")
	await _boss6_horizontal_laser(playfield_bottom)

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

	await get_tree().create_timer(0.30).timeout
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

		await get_tree().create_timer(0.18).timeout
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

		await get_tree().create_timer(0.30).timeout

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

func _boss1_portal_pattern() -> void:
	# Midboss-safe wrapper: the raw spawn loop expects a portal argument and runs indefinitely.
	# This pattern ensures a portal exists, then uses it as a bullet emitter for a short burst.
	var token := _phase_token

	if not is_instance_valid(_boss1_portal_ref):
		await _boss1_summon_teleport()

	if _pattern_should_abort(token):
		return

	var portal := _boss1_portal_ref as Node2D
	if not portal or not is_instance_valid(portal) or portal.is_queued_for_deletion():
		return

	var texture_path := "res://assets/sprites/bossbullut-2.png"
	var ring_texture := "res://assets/sprites/bossbullut-3.png"
	var base_speed := 8.5 * 60.0
	for wave in range(3):
		if _pattern_should_abort(token):
			return
		portal = _boss1_portal_ref as Node2D
		if not portal or not is_instance_valid(portal) or portal.is_queued_for_deletion():
			return
		var portal_pos := portal.global_position

		var player := _get_player_safe()
		if player:
			var to_player := player.global_position - portal_pos
			if to_player.length() == 0.0:
				to_player = Vector2.LEFT
				var base_angle := to_player.angle()
				var spread := 30.0
				var count := 5
				for i in range(count):
					var t := 0.0
					if count > 1:
						t = float(i) / float(count - 1)
					var a := base_angle + deg_to_rad(lerpf(-spread * 0.5, spread * 0.5, t))
					var dir := Vector2(cos(a), sin(a))
					_spawn_bullet_at(portal_pos, dir, base_speed + float(wave) * 40.0, EnemyBullet.BulletType.NORMAL, texture_path)

		# Small ring for "portal ambience".
		var ring_count := 10 + wave * 2
		for j in range(ring_count):
			var ang := (TAU / float(ring_count)) * float(j)
			var dir2 := Vector2(cos(ang), sin(ang))
			_spawn_bullet_at(portal_pos, dir2, (6.0 + float(wave) * 0.6) * 60.0, EnemyBullet.BulletType.NORMAL, ring_texture)

		await get_tree().create_timer(0.22).timeout

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
		await get_tree().create_timer(0.30).timeout
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
		await get_tree().create_timer(0.30).timeout
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
		await get_tree().create_timer(0.16).timeout

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
		await get_tree().create_timer(0.18).timeout

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

		await get_tree().create_timer(0.15).timeout

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
	await get_tree().create_timer(0.18).timeout

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

	await get_tree().create_timer(0.30).timeout

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

		await get_tree().create_timer(0.30).timeout
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
		await get_tree().create_timer(0.15).timeout
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

	await get_tree().create_timer(0.30).timeout
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
# Boss 1 New Skills - Desert/Egyptian Theme (25 skills)
# ============================================================================

# ============================================================================
# Boss 1 - Desert Awakening (Nonspell 1) -- 5 skills
# ============================================================================

func _boss1_sandstorm_prelude() -> void:
	# Sand bullets rain from ALL 4 screen edges converging on player position.
	# Boss also fires aimed decelerate trap bullets. 8 waves, fast.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for wave in range(8):
		var target_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- Top edge: 10 bullets raining down ---
		for i in range(10):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(target_pos.x + randf_range(-320, 320), 20)
			bullet.direction = (target_pos - bullet.global_position).normalized().rotated(randf_range(-0.12, 0.12))
			bullet.speed = randf_range(260.0, 380.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		# --- Bottom edge: 8 bullets rising up ---
		for i in range(8):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(target_pos.x + randf_range(-280, 280), vp.y - 30)
			bullet.direction = (target_pos - bullet.global_position).normalized().rotated(randf_range(-0.1, 0.1))
			bullet.speed = randf_range(240.0, 340.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		# --- Left edge: 6 bullets ---
		for i in range(6):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(20, target_pos.y + randf_range(-200, 200))
			bullet.direction = (target_pos - bullet.global_position).normalized().rotated(randf_range(-0.08, 0.08))
			bullet.speed = randf_range(280.0, 360.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		# --- Right edge: 6 bullets ---
		for i in range(6):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(vp.x - 20, target_pos.y + randf_range(-200, 200))
			bullet.direction = (target_pos - bullet.global_position).normalized().rotated(randf_range(-0.08, 0.08))
			bullet.speed = randf_range(280.0, 360.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		# --- Boss fires decelerate trap bullets aimed at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(7):
				var spread = aim + (j - 3) * 0.22
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 320.0
				bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
				bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


func _boss1_desert_wind() -> void:
	# Dual rotating laser beams sweep from boss position (2 arms, rotating).
	# Between sweeps, aimed sand bullet fans at player. Very flashy.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var arm_angle_base = 0.0
	for step in range(48):
		# --- Two rotating laser arms (180 degrees apart) ---
		for arm in range(2):
			var arm_angle = arm_angle_base + arm * PI
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(arm_angle), sin(arm_angle))
			bullet.speed = 600.0
			bullet.bullet_type = EnemyBullet.BulletType.LASER
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
			# Trail bullets along each laser arm for visual density
			var trail = bullet_scene.instantiate() as EnemyBullet
			trail.global_position = global_position + Vector2(cos(arm_angle), sin(arm_angle)) * 40.0
			trail.direction = Vector2(cos(arm_angle), sin(arm_angle))
			trail.speed = 480.0
			trail.bullet_type = EnemyBullet.BulletType.LASER
			trail.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(trail)
		arm_angle_base += 0.18  # Rotate the arms each step
		# --- Every 6 steps, fire aimed sand bullet fan at player ---
		if step % 6 == 0 and player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(11):
				var spread = aim + (j - 5) * 0.16
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 300.0
				bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout


func _boss1_sand_ripples() -> void:
	# Concentric rings fired from boss, each ring has a gap that tracks the player.
	# Rings get denser over time. Accelerating bullets fill the gaps after a delay.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for ring in range(10):
		var gap_angle = 0.0
		if player and is_instance_valid(player):
			gap_angle = global_position.direction_to(player.global_position).angle()
		var ring_count = 20 + ring * 2  # Gets denser: 20, 22, 24 ... 38
		var gap_half_width = 0.35 - ring * 0.015  # Gap shrinks slightly over time
		for i in range(ring_count):
			var angle = (TAU / ring_count) * i + ring * 0.12
			# Skip bullets in the gap zone (centered on player direction)
			var angle_diff = fmod(abs(angle - gap_angle) + PI, TAU) - PI
			if abs(angle_diff) < gap_half_width:
				continue
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0 + ring * 12.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		# --- Accelerating bullets that fill the gap after a delay ---
		if ring % 2 == 0:
			for g in range(4):
				var fill_angle = gap_angle + (g - 1.5) * 0.18
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(fill_angle), sin(fill_angle))
				bullet.speed = 80.0
				bullet.start_delay = 0.4
				bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


func _boss1_dune_cascade() -> void:
	# Cascading bullet walls from top of screen with a gap that follows player.
	# Simultaneously, homing scorpion bullets spawn from left and right screen edges.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for wave in range(10):
		var gap_x = 450.0
		if player and is_instance_valid(player):
			gap_x = player.global_position.x
		# --- Bullet wall from top with gap ---
		var wall_count = 22
		for i in range(wall_count):
			var x_pos = 30 + i * ((vp.x - 60) / wall_count)
			if abs(x_pos - gap_x) < 55:
				continue  # Leave gap near player
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 20 + wave * 3)
			bullet.direction = Vector2(randf_range(-0.05, 0.05), 1).normalized()
			bullet.speed = 280.0 + wave * 10.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		# --- Homing scorpion bullets from left edge ---
		if player and is_instance_valid(player):
			for j in range(3):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = Vector2(25, 120 + j * 120 + wave * 15)
				bullet.direction = (player.global_position - bullet.global_position).normalized()
				bullet.speed = 220.0
				bullet.bullet_type = EnemyBullet.BulletType.HOMING
				bullet._homing_strength = 2.5
				bullet._homing_duration = 0.6
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
		# --- Homing scorpion bullets from right edge ---
		if player and is_instance_valid(player):
			for j in range(3):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = Vector2(vp.x - 25, 120 + j * 120 + wave * 15)
				bullet.direction = (player.global_position - bullet.global_position).normalized()
				bullet.speed = 220.0
				bullet.bullet_type = EnemyBullet.BulletType.HOMING
				bullet._homing_strength = 2.5
				bullet._homing_duration = 0.6
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout


func _boss1_mirage_shimmer() -> void:
	# Bullets spawn in a ring around the player, orbit briefly, then dash inward.
	# Boss also fires a laser through center. Uses orbit mechanics.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for shimmer in range(8):
		var center = player.global_position
		var orbit_count = 16
		# --- Orbiting ring around player ---
		for i in range(orbit_count):
			var angle = (TAU / orbit_count) * i + shimmer * 0.4
			var radius = 200.0 + shimmer * 10.0
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * radius
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = Vector2(cos(angle + PI / 2), sin(angle + PI / 2))
			bullet.speed = 0.0
			bullet.orbit_center = center
			bullet.orbit_radius = radius
			bullet.orbit_angle = angle
			bullet.orbit_angular_speed = 3.5 * (1 if shimmer % 2 == 0 else -1)
			bullet.orbit_time_left = 0.7
			bullet.dash_after_orbit = true
			bullet.dash_target = center
			bullet.dash_speed = 300.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		# --- Boss fires laser through center of the ring ---
		var aim = global_position.direction_to(center).angle()
		for k in range(3):
			var laser = bullet_scene.instantiate() as EnemyBullet
			laser.global_position = global_position
			laser.direction = Vector2(cos(aim + (k - 1) * 0.06), sin(aim + (k - 1) * 0.06))
			laser.speed = 550.0
			laser.bullet_type = EnemyBullet.BulletType.LASER
			laser.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(laser)
		await get_tree().create_timer(0.12).timeout


# ============================================================================
# Boss 1 - Lightning Tempest (Spell 1) -- 5 skills
# ============================================================================

func _boss1_lightning_barrage() -> void:
	# Rapid laser beams fired in a sweeping zigzag pattern across the screen.
	# Between zigzag sweeps, aimed lightning bolt fans at player. Very fast.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	var sweep_dir = 1  # 1 = left-to-right, -1 = right-to-left
	for sweep in range(6):
		# --- Zigzag laser sweep across screen ---
		var steps = 12
		for s in range(steps):
			var progress = float(s) / float(steps)
			var x_pos: float
			if sweep_dir > 0:
				x_pos = 60 + progress * (vp.x - 120)
			else:
				x_pos = (vp.x - 60) - progress * (vp.x - 120)
			# Fire laser downward from top
			var laser = bullet_scene.instantiate() as EnemyBullet
			laser.global_position = Vector2(x_pos, 25)
			laser.direction = Vector2(randf_range(-0.08, 0.08), 1).normalized()
			laser.speed = 520.0
			laser.bullet_type = EnemyBullet.BulletType.LASER
			laser.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser)
			# Fire laser upward from bottom for visual cross
			var laser2 = bullet_scene.instantiate() as EnemyBullet
			laser2.global_position = Vector2(x_pos + 40 * sweep_dir, vp.y - 25)
			laser2.direction = Vector2(randf_range(-0.08, 0.08), -1).normalized()
			laser2.speed = 480.0
			laser2.bullet_type = EnemyBullet.BulletType.LASER
			laser2.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser2)
			await get_tree().create_timer(0.03).timeout
		sweep_dir *= -1
		# --- Aimed lightning bolt fan at player between sweeps ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(13):
				var spread = aim + (j - 6) * 0.14
				var bolt = bullet_scene.instantiate() as EnemyBullet
				bolt.global_position = global_position
				bolt.direction = Vector2(cos(spread), sin(spread))
				bolt.speed = 340.0
				bolt.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bolt)
		await get_tree().create_timer(0.06).timeout


func _boss1_thunder_spiral() -> void:
	# Triple spiral arms (3 arms, rotating) firing continuously.
	# Every 10 steps, fire 3 laser beams aimed directly at player. Dense and fast.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var spiral_angle = 0.0
	for step in range(60):
		# --- 3 spiral arms, each 120 degrees apart ---
		for arm in range(3):
			var angle = spiral_angle + arm * (TAU / 3.0)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
			# Inner spiral layer (slightly offset, slower)
			var inner = bullet_scene.instantiate() as EnemyBullet
			inner.global_position = global_position
			inner.direction = Vector2(cos(angle + 0.15), sin(angle + 0.15))
			inner.speed = 200.0
			inner.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(inner)
		spiral_angle += 0.16
		# --- Every 10 steps, fire 3 laser beams aimed at player ---
		if step % 10 == 0 and player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for k in range(3):
				var laser = bullet_scene.instantiate() as EnemyBullet
				laser.global_position = global_position
				laser.direction = Vector2(cos(aim + (k - 1) * 0.25), sin(aim + (k - 1) * 0.25))
				laser.speed = 580.0
				laser.bullet_type = EnemyBullet.BulletType.LASER
				laser.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(laser)
		await get_tree().create_timer(0.03).timeout


func _boss1_storm_vortex() -> void:
	# Rotating CURVE bullet vortex ring from boss. Simultaneously, lightning bolts
	# summoned from top, left, right screen edges aimed at player. 10 waves.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	var vortex_angle = 0.0
	for wave in range(10):
		# --- Rotating curve bullet vortex from boss ---
		var vortex_count = 14
		for i in range(vortex_count):
			var angle = vortex_angle + (TAU / vortex_count) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 240.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.turn_rate = 1.8 * (1 if wave % 2 == 0 else -1)
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		vortex_angle += 0.35
		# --- Lightning bolts from top edge ---
		if player and is_instance_valid(player):
			for j in range(5):
				var bolt = bullet_scene.instantiate() as EnemyBullet
				bolt.global_position = Vector2(player.global_position.x + (j - 2) * 80, 20)
				bolt.direction = (player.global_position - bolt.global_position).normalized()
				bolt.speed = 380.0
				bolt.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bolt)
		# --- Lightning bolts from left edge ---
		if player and is_instance_valid(player):
			for j in range(3):
				var bolt = bullet_scene.instantiate() as EnemyBullet
				bolt.global_position = Vector2(20, player.global_position.y + (j - 1) * 100)
				bolt.direction = (player.global_position - bolt.global_position).normalized()
				bolt.speed = 360.0
				bolt.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bolt)
		# --- Lightning bolts from right edge ---
		if player and is_instance_valid(player):
			for j in range(3):
				var bolt = bullet_scene.instantiate() as EnemyBullet
				bolt.global_position = Vector2(vp.x - 20, player.global_position.y + (j - 1) * 100)
				bolt.direction = (player.global_position - bolt.global_position).normalized()
				bolt.speed = 360.0
				bolt.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bolt)
		await get_tree().create_timer(0.10).timeout


func _boss1_electric_web() -> void:
	# Phase 1: Vertical laser lines sweep left-to-right.
	# Phase 2: Horizontal laser lines sweep top-to-bottom.
	# Phase 3: Bouncing spark bullets aimed at player.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	# --- Phase 1: Vertical laser lines sweeping left to right ---
	for col in range(14):
		var x_pos = 40 + col * ((vp.x - 80) / 14.0)
		for row in range(3):
			var laser = bullet_scene.instantiate() as EnemyBullet
			laser.global_position = Vector2(x_pos, 30 + row * (vp.y / 3.0))
			laser.direction = Vector2(0, 1).rotated(randf_range(-0.04, 0.04))
			laser.speed = 500.0
			laser.bullet_type = EnemyBullet.BulletType.LASER
			laser.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser)
		await get_tree().create_timer(0.04).timeout
	# --- Phase 2: Horizontal laser lines sweeping top to bottom ---
	for row in range(10):
		var y_pos = 40 + row * ((vp.y - 80) / 10.0)
		for col in range(3):
			var laser = bullet_scene.instantiate() as EnemyBullet
			laser.global_position = Vector2(30 + col * (vp.x / 3.0), y_pos)
			laser.direction = Vector2(1, 0).rotated(randf_range(-0.04, 0.04))
			laser.speed = 480.0
			laser.bullet_type = EnemyBullet.BulletType.LASER
			laser.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser)
		await get_tree().create_timer(0.04).timeout
	# --- Phase 3: Bouncing spark bullets aimed at player ---
	if player and is_instance_valid(player):
		for burst in range(5):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(9):
				var spread = aim + (j - 4) * 0.2
				var spark = bullet_scene.instantiate() as EnemyBullet
				spark.global_position = global_position
				spark.direction = Vector2(cos(spread), sin(spread))
				spark.speed = 300.0
				spark.bullet_type = EnemyBullet.BulletType.BOUNCE
				spark.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(spark)
			await get_tree().create_timer(0.08).timeout


func _boss1_plasma_burst() -> void:
	# Dense aimed SPLIT bullet fans at player (14 bullets per fan).
	# Homing plasma orbs spawn from both sides of boss. 8 bursts, very fast.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for burst in range(8):
		# --- Dense SPLIT bullet fan aimed at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for i in range(14):
				var spread = aim + (i - 6.5) * 0.12
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 280.0 + i * 8.0
				bullet.bullet_type = EnemyBullet.BulletType.SPLIT
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
		# --- Homing plasma orbs from left side of boss ---
		for j in range(3):
			var orb = bullet_scene.instantiate() as EnemyBullet
			orb.global_position = global_position + Vector2(-60, -30 + j * 30)
			if player and is_instance_valid(player):
				orb.direction = (player.global_position - orb.global_position).normalized()
			else:
				orb.direction = Vector2(0, 1)
			orb.speed = 200.0
			orb.bullet_type = EnemyBullet.BulletType.HOMING
			orb._homing_strength = 2.0
			orb._homing_duration = 0.6
			orb.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(orb)
		# --- Homing plasma orbs from right side of boss ---
		for j in range(3):
			var orb = bullet_scene.instantiate() as EnemyBullet
			orb.global_position = global_position + Vector2(60, -30 + j * 30)
			if player and is_instance_valid(player):
				orb.direction = (player.global_position - orb.global_position).normalized()
			else:
				orb.direction = Vector2(0, 1)
			orb.speed = 200.0
			orb.bullet_type = EnemyBullet.BulletType.HOMING
			orb._homing_strength = 2.0
			orb._homing_duration = 0.6
			orb.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(orb)
		await get_tree().create_timer(0.07).timeout

# =============================================================================
# NONSPELL 2 - Serpent's Dance (5 skills)
# =============================================================================

# =============================================================================
# NONSPELL 2 - Desert Summoning (5 skills)
# =============================================================================

func _boss1_sand_guardian_summon() -> void:
	# Summon 3 TANK minions in a triangle around the boss. While minions exist,
	# fire aimed fans at player. Also fire DECELERATE ring that stops and re-aims.
	if not bullet_scene or not get_parent():
		return
	var token := _phase_token
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var enemy_scene_ref: PackedScene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref:
		return

	# --- Summon 3 TANK minions in triangle formation around boss ---
	for i in range(3):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var angle := (TAU / 3.0) * float(i) - PI / 2.0
		var minion: Enemy = enemy_scene_ref.instantiate() as Enemy
		if not minion:
			continue
		minion.enemy_kind = EnemyKind.TANK
		var pos := global_position + Vector2(cos(angle), sin(angle)) * 140.0
		pos.x = clampf(pos.x, 60.0, viewport_size.x - 60.0)
		pos.y = clampf(pos.y, 60.0, playfield_bottom - 60.0)
		minion.global_position = pos
		get_parent().add_child(minion)
	await get_tree().create_timer(0.15).timeout
	if _pattern_should_abort(token):
		return

	# --- Main attack loop: aimed fans + decelerate rings ---
	for wave in range(10):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return

		var aim := global_position.direction_to(player.global_position).angle()
		# Aimed bullet fan at player (9 bullets)
		for j in range(9):
			var spread := aim + (float(j) - 4.0) * 0.18
			var bullet := bullet_scene.instantiate() as EnemyBullet
			if not bullet:
				continue
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 300.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
		if _pattern_should_abort(token):
			return

		# DECELERATE ring that stops and re-aims at player
		if wave % 2 == 0:
			for k in range(16):
				var ring_angle := (TAU / 16.0) * float(k) + float(wave) * 0.3
				var ring_bullet := bullet_scene.instantiate() as EnemyBullet
				if not ring_bullet:
					continue
				ring_bullet.global_position = global_position
				ring_bullet.direction = Vector2(cos(ring_angle), sin(ring_angle))
				ring_bullet.speed = 280.0
				ring_bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
				ring_bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(ring_bullet)
		await get_tree().create_timer(0.10).timeout
		if _pattern_should_abort(token):
			return

		# Secondary aimed burst between waves for pressure
		player = _get_player_safe()
		if player:
			var aim2 := global_position.direction_to(player.global_position).angle()
			for m in range(5):
				var spread2 := aim2 + (float(m) - 2.0) * 0.25
				var bullet2 := bullet_scene.instantiate() as EnemyBullet
				if not bullet2:
					continue
				bullet2.global_position = global_position
				bullet2.direction = Vector2(cos(spread2), sin(spread2))
				bullet2.speed = 340.0
				bullet2.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(bullet2)
		await get_tree().create_timer(0.02).timeout
		if _pattern_should_abort(token):
			return


func _boss1_scarab_swarm() -> void:
	# Summon 4 FAST minions from screen edges (top, bottom, left, right).
	# Boss fires HOMING bullets at player. Between waves, fire SPLIT bullets.
	if not bullet_scene or not get_parent():
		return
	var token := _phase_token
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var enemy_scene_ref: PackedScene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref:
		return

	# --- Summon 4 FAST minions from each screen edge ---
	var edge_positions: Array[Vector2] = [
		Vector2(viewport_size.x * 0.5, 30.0),                    # top center
		Vector2(viewport_size.x * 0.5, playfield_bottom - 30.0), # bottom center (exclude BottomBar)
		Vector2(30.0, playfield_bottom * 0.4),                   # left
		Vector2(viewport_size.x - 30.0, playfield_bottom * 0.4)  # right
	]
	for idx in range(edge_positions.size()):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var minion: Enemy = enemy_scene_ref.instantiate() as Enemy
		if not minion:
			continue
		minion.enemy_kind = EnemyKind.FAST
		var spawn_pos := edge_positions[idx]
		spawn_pos.x = clampf(spawn_pos.x, 60.0, viewport_size.x - 60.0)
		spawn_pos.y = clampf(spawn_pos.y, 60.0, playfield_bottom - 60.0)
		minion.global_position = spawn_pos
		get_parent().add_child(minion)
	await get_tree().create_timer(0.12).timeout
	if _pattern_should_abort(token):
		return

	# --- Main attack loop: HOMING bullets + SPLIT bursts ---
	for wave in range(8):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return

		# HOMING bullets aimed at player from boss (6 per wave)
		var aim = global_position.direction_to(player.global_position).angle()
		for j in range(6):
			var spread = aim + (j - 2.5) * 0.22
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 240.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 2.8
			bullet._homing_duration = 0.7
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout
		if _pattern_should_abort(token):
			return

		# SPLIT bullets aimed at player between waves
		player = _get_player_safe()
		if wave % 2 == 0 and player:
			var aim2 = global_position.direction_to(player.global_position).angle()
			for k in range(8):
				var spread2 = aim2 + (k - 3.5) * 0.15
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread2), sin(spread2))
				bullet.speed = 310.0
				bullet.bullet_type = EnemyBullet.BulletType.SPLIT
				bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
		if _pattern_should_abort(token):
			return

		# Extra aimed burst for sustained pressure
		player = _get_player_safe()
		if player:
			var aim3 = global_position.direction_to(player.global_position).angle()
			for n in range(4):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position + Vector2(cos(aim3 + PI / 2), sin(aim3 + PI / 2)) * (n - 1.5) * 25.0
				bullet.direction = Vector2(cos(aim3), sin(aim3))
				bullet.speed = 350.0
				bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		if _pattern_should_abort(token):
			return


func _boss1_pharaoh_guard() -> void:
	# Summon 2 SNIPER minions flanking the boss. Boss fires alternating SINE_WAVE
	# streams aimed at player. Minions provide crossfire pressure.
	if not bullet_scene or not get_parent():
		return
	var token := _phase_token
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var enemy_scene_ref: PackedScene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref:
		return

	# --- Summon 2 SNIPER minions flanking the boss ---
	var flank_offset = 180.0
	for side in range(2):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var x_off = -flank_offset if side == 0 else flank_offset
		var minion: Enemy = enemy_scene_ref.instantiate() as Enemy
		if not minion:
			continue
		minion.enemy_kind = EnemyKind.SNIPER
		var pos := Vector2(global_position.x + x_off, global_position.y + 40.0)
		pos.x = clampf(pos.x, 60.0, viewport_size.x - 60.0)
		pos.y = clampf(pos.y, 60.0, playfield_bottom - 60.0)
		minion.global_position = pos
		get_parent().add_child(minion)
	await get_tree().create_timer(0.12).timeout
	if _pattern_should_abort(token):
		return

	# --- Main attack loop: alternating SINE_WAVE streams at player ---
	var stream_offset = 0.0
	for wave in range(12):
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
		var aim = global_position.direction_to(player_pos).angle()
		# Alternating sine wave streams (left-leaning and right-leaning)
		var sine_sign = 1.0 if wave % 2 == 0 else -1.0
		for j in range(5):
			var spread = aim + (j - 2) * 0.14 + stream_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 270.0 + j * 15.0
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			bullet.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(bullet)
		stream_offset += 0.08 * sine_sign
		await get_tree().create_timer(0.07).timeout
		if _pattern_should_abort(token):
			return

		# Every 3rd wave, fire a tight aimed burst for extra pressure
		player = _get_player_safe()
		if wave % 3 == 0 and player:
			var aim2 = global_position.direction_to(player.global_position).angle()
			for k in range(7):
				var spread2 = aim2 + (k - 3) * 0.12
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread2), sin(spread2))
				bullet.speed = 320.0
				bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(bullet)
		# Every 4th wave, fire sine wave streams from flank positions
		player = _get_player_safe()
		if wave % 4 == 0 and player:
			var ppos := player.global_position
			for side in range(2):
				var flank_pos = Vector2(global_position.x + (-flank_offset if side == 0 else flank_offset), global_position.y + 40.0)
				flank_pos.x = clampf(flank_pos.x, 60.0, viewport_size.x - 60.0)
				flank_pos.y = clampf(flank_pos.y, 60.0, playfield_bottom - 60.0)
				var flank_aim = flank_pos.direction_to(ppos).angle()
				for f in range(4):
					var bullet = bullet_scene.instantiate() as EnemyBullet
					bullet.global_position = flank_pos
					bullet.direction = Vector2(cos(flank_aim + (f - 1.5) * 0.2), sin(flank_aim + (f - 1.5) * 0.2))
					bullet.speed = 290.0
					bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
					bullet.set_sprite("res://assets/sprites/bossbullut-8.png")
					get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		if _pattern_should_abort(token):
			return


func _boss1_obelisk_ritual() -> void:
	# Summon 4 SUICIDE minions at screen corners. Boss fires ACCELERATE aimed fans.
	# Between summon waves, fire orbit bullets that dash at player after orbiting.
	if not bullet_scene or not get_parent():
		return
	var token := _phase_token
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var enemy_scene_ref: PackedScene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref:
		return

	# --- Summon 4 SUICIDE minions at screen corners ---
	var corner_positions = [
		Vector2(60, 60),
		Vector2(viewport_size.x - 60, 60),
		Vector2(60, playfield_bottom - 60),
		Vector2(viewport_size.x - 60, playfield_bottom - 60)
	]
	for idx in range(4):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var minion: Enemy = enemy_scene_ref.instantiate() as Enemy
		if not minion:
			continue
		minion.enemy_kind = EnemyKind.SUICIDE
		var pos: Vector2 = corner_positions[idx]
		pos.x = clampf(pos.x, 60.0, viewport_size.x - 60.0)
		pos.y = clampf(pos.y, 60.0, playfield_bottom - 60.0)
		minion.global_position = pos
		get_parent().add_child(minion)
	await get_tree().create_timer(0.12).timeout
	if _pattern_should_abort(token):
		return

	# --- Main attack loop: ACCELERATE fans + orbit-dash bullets ---
	for wave in range(8):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return

		# ACCELERATE bullet fan aimed at player (10 bullets)
		var aim = global_position.direction_to(player.global_position).angle()
		for j in range(10):
			var spread = aim + (j - 4.5) * 0.16
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout
		if _pattern_should_abort(token):
			return

		# Orbit bullets that circle boss then dash at player
		player = _get_player_safe()
		if wave % 2 == 0 and player:
			var dash_target := player.global_position
			var orbit_count = 10
			for k in range(orbit_count):
				var orb_angle = (TAU / orbit_count) * k
				var radius = 120.0
				var spawn_pos = global_position + Vector2(cos(orb_angle), sin(orb_angle)) * radius
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = spawn_pos
				bullet.direction = Vector2(cos(orb_angle + PI / 2), sin(orb_angle + PI / 2))
				bullet.speed = 0.0
				bullet.orbit_center = global_position
				bullet.orbit_radius = radius
				bullet.orbit_angle = orb_angle
				bullet.orbit_angular_speed = 4.0 * (1 if wave % 4 == 0 else -1)
				bullet.orbit_time_left = 0.6
				bullet.dash_after_orbit = true
				bullet.dash_target = dash_target
				bullet.dash_speed = 340.0
				bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
		if _pattern_should_abort(token):
			return

		# Extra aimed narrow burst for sustained threat
		player = _get_player_safe()
		if player:
			var aim2 = global_position.direction_to(player.global_position).angle()
			for n in range(3):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(aim2 + (n - 1) * 0.08), sin(aim2 + (n - 1) * 0.08))
				bullet.speed = 380.0
				bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		if _pattern_should_abort(token):
			return


func _boss1_desert_legion() -> void:
	# Multi-wave summoning: Wave 1: 2 FAST + aimed fan. Wave 2: 2 TANK + LASER sweep.
	# Wave 3: 2 SNIPER + HOMING burst. Each wave summons at random edge positions.
	if not bullet_scene or not get_parent():
		return
	var token := _phase_token
	var viewport_size := get_viewport_rect().size
	var playfield_bottom := viewport_size.y
	if GameManager and GameManager.has_method("get_playfield_bottom_y"):
		playfield_bottom = GameManager.get_playfield_bottom_y(viewport_size)

	var enemy_scene_ref: PackedScene = load("res://scenes/enemies/enemy.tscn") as PackedScene
	if not enemy_scene_ref:
		return

	# ===== WAVE 1: 2 FAST minions + aimed bullet fan =====
	for i in range(2):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var minion: Enemy = enemy_scene_ref.instantiate() as Enemy
		if not minion:
			continue
		minion.enemy_kind = EnemyKind.FAST
		var edge_x = randf_range(80.0, viewport_size.x - 80.0)
		var edge_y = 30.0 if i == 0 else playfield_bottom - 30.0
		minion.global_position = Vector2(edge_x, edge_y)
		get_parent().add_child(minion)
	await get_tree().create_timer(0.10).timeout
	if _pattern_should_abort(token):
		return

	# Wave 1 bullets: aimed fan at player (4 rounds)
	for round_idx in range(4):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return

		var aim = global_position.direction_to(player.global_position).angle()
		for j in range(11):
			var spread = aim + (j - 5) * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 290.0 + round_idx * 15.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
		if _pattern_should_abort(token):
			return

	# ===== WAVE 2: 2 TANK minions + LASER sweep at player =====
	for i in range(2):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var minion: Enemy = enemy_scene_ref.instantiate() as Enemy
		if not minion:
			continue
		minion.enemy_kind = EnemyKind.TANK
		var edge_y2 = randf_range(100.0, maxf(100.0, playfield_bottom - 100.0))
		var edge_x2 = 30.0 if i == 0 else viewport_size.x - 30.0
		minion.global_position = Vector2(edge_x2, edge_y2)
		get_parent().add_child(minion)
	await get_tree().create_timer(0.10).timeout
	if _pattern_should_abort(token):
		return

	# Wave 2 bullets: LASER sweep aimed at player (sweeping arc)
	var player := _get_player_safe()
	if player:
		var base_aim = global_position.direction_to(player.global_position).angle()
		var sweep_start = base_aim - 0.6
		for s in range(16):
			if _pattern_should_abort(token):
				return
			while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
				if _pattern_should_abort(token):
					return
				await get_tree().create_timer(0.1).timeout

			var sweep_angle = sweep_start + s * 0.075
			var laser = bullet_scene.instantiate() as EnemyBullet
			laser.global_position = global_position
			laser.direction = Vector2(cos(sweep_angle), sin(sweep_angle))
			laser.speed = 520.0
			laser.bullet_type = EnemyBullet.BulletType.LASER
			laser.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser)
			# Parallel normal bullets alongside laser
			var side_bullet = bullet_scene.instantiate() as EnemyBullet
			side_bullet.global_position = global_position
			side_bullet.direction = Vector2(cos(sweep_angle + 0.15), sin(sweep_angle + 0.15))
			side_bullet.speed = 310.0
			side_bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(side_bullet)
			await get_tree().create_timer(0.04).timeout
			if _pattern_should_abort(token):
				return

	# ===== WAVE 3: 2 SNIPER minions + HOMING burst =====
	for i in range(2):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var minion: Enemy = enemy_scene_ref.instantiate() as Enemy
		if not minion:
			continue
		minion.enemy_kind = EnemyKind.SNIPER
		var edge_x3 = randf_range(100.0, viewport_size.x - 100.0)
		var edge_y3 = 30.0 if i == 0 else playfield_bottom - 30.0
		minion.global_position = Vector2(edge_x3, edge_y3)
		get_parent().add_child(minion)
	await get_tree().create_timer(0.10).timeout
	if _pattern_should_abort(token):
		return

	# Wave 3 bullets: HOMING burst aimed at player (5 rounds)
	for round_idx in range(5):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		player = _get_player_safe()
		if not player:
			return

		var aim = global_position.direction_to(player.global_position).angle()
		for j in range(8):
			var spread = aim + (j - 3.5) * 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 230.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 3.0
			bullet._homing_duration = 0.8
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		# Supplementary aimed normal bullets
		player = _get_player_safe()
		if player:
			var aim2 = global_position.direction_to(player.global_position).angle()
			for k in range(5):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(aim2 + (k - 2) * 0.1), sin(aim2 + (k - 2) * 0.1))
				bullet.speed = 350.0
				bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.07).timeout
		if _pattern_should_abort(token):
			return
# =============================================================================
# SPELL 2 - Gravity Manipulation (5 skills)
# =============================================================================

func _boss1_gravity_lens() -> void:
	# Curve bullets in expanding rings aimed at player with decelerate traps
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for wave in range(6):
		var aim_angle = global_position.direction_to(player.global_position).angle()
		var ring_count = 18 + wave * 3
		# Expanding curve ring offset toward player
		for i in range(ring_count):
			var angle = (TAU / ring_count) * i + wave * 0.3
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 170.0 + wave * 15.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.turn_rate = 1.2 * (1.0 if i % 2 == 0 else -1.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout
		# Decelerate trap bullets near player position
		for d in range(8):
			var trap_angle = aim_angle + (d - 3.5) * 0.25
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(trap_angle), sin(trap_angle))
			bullet.speed = 300.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss1_event_horizon_ring() -> void:
	# Decelerate rings spawn centered on player - bullets fly out, stop, re-aim back
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for ring in range(6):
		var center = player.global_position
		var bullet_count = 16 + ring * 4
		# Bullets spawn at player pos, fly outward, decelerate, then re-aim at player
		for i in range(bullet_count):
			var angle = (TAU / bullet_count) * i + ring * 0.4
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = center
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 250.0 + ring * 20.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout
		# Additional inner ring for density
		for j in range(8):
			var inner_angle = (TAU / 8.0) * j + ring * 0.7
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = center
			bullet.direction = Vector2(cos(inner_angle), sin(inner_angle))
			bullet.speed = 150.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss1_spacetime_tear() -> void:
	# Bullets from 8 random rift positions around screen, all converging on player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for rift_idx in range(8):
		# Random rift positions along screen edges
		var rift_pos: Vector2
		var edge = randi() % 4
		match edge:
			0: rift_pos = Vector2(randf_range(50, 850), 10)
			1: rift_pos = Vector2(randf_range(50, 850), 590)
			2: rift_pos = Vector2(10, randf_range(50, 550))
			3: rift_pos = Vector2(890, randf_range(50, 550))
		var aim_dir = (player.global_position - rift_pos).normalized()
		# 10 bullets per rift with slight spread
		for i in range(10):
			var spread = aim_dir.rotated((i - 4.5) * 0.08)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = rift_pos
			bullet.direction = spread
			# Mix in homing bullets every 3rd bullet
			if i % 3 == 0:
				bullet.speed = 200.0
				bullet.bullet_type = EnemyBullet.BulletType.HOMING
				bullet._homing_strength = 2.0
				bullet._homing_duration = 0.6
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			else:
				bullet.speed = 260.0 + randf() * 40.0
				bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.06).timeout

func _boss1_singularity_burst() -> void:
	# Phase 1: massive aimed burst, Phase 2: spiral follow-up, Phase 3: decelerate trap
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	# Phase 1: 40-bullet burst aimed at player direction
	var aim_angle = global_position.direction_to(player.global_position).angle()
	for i in range(40):
		var spread_angle = aim_angle + (i - 19.5) * 0.06
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
		bullet.speed = 220.0 + abs(i - 19.5) * 5.0
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.08).timeout
	# Phase 2: 50 spiral bullets
	for i in range(50):
		var spiral_angle = (TAU / 50.0) * i * 3.0
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(spiral_angle), sin(spiral_angle))
		bullet.speed = 180.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.02).timeout
	await get_tree().create_timer(0.05).timeout
	# Phase 3: Decelerate ring trap around player
	var trap_center = player.global_position
	for i in range(24):
		var ring_angle = (TAU / 24.0) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = (trap_center + Vector2(cos(ring_angle), sin(ring_angle)) * 120.0 - global_position).normalized()
		bullet.speed = 350.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.05).timeout

func _boss1_gravity_storm() -> void:
	# Curve laser sweeps toward player + decelerate minefield around player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for wave in range(5):
		var aim_angle = global_position.direction_to(player.global_position).angle()
		var sweep_dir = 1.0 if wave % 2 == 0 else -1.0
		# Curve laser sweep: 8 laser bullets that bend toward player
		for l in range(8):
			var laser_angle = aim_angle + sweep_dir * (l - 3.5) * 0.12
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(laser_angle), sin(laser_angle))
			bullet.speed = 380.0
			bullet.bullet_type = EnemyBullet.BulletType.LASER
			bullet.turn_rate = sweep_dir * -0.8
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout
		# Decelerate minefield scattered around player position
		var player_pos = player.global_position
		for d in range(12):
			var scatter_angle = (TAU / 12.0) * d + wave * 0.5
			var scatter_dist = 80.0 + randf() * 100.0
			var target_pos = player_pos + Vector2(cos(scatter_angle), sin(scatter_angle)) * scatter_dist
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = (target_pos - global_position).normalized()
			bullet.speed = (target_pos - global_position).length() * 2.5
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout
		# Extra curve bullets for visual flair
		for c in range(6):
			var curve_angle = aim_angle + (c - 2.5) * 0.3
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(curve_angle), sin(curve_angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.turn_rate = sweep_dir * 1.5
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout

# =============================================================================
# FINAL PHASE - Cataclysm (5 super skills) - Boss 1 Desert/Egyptian Theme
# =============================================================================

func _boss1_desert_apocalypse() -> void:
	# Super multi-phase: sand rain -> laser strikes -> aimed fan -> decelerate trap
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	# Phase 1: Dense sand rain from top of screen, angled toward player
	for i in range(30):
		var bullet = bullet_scene.instantiate() as EnemyBullet
		var x_pos = randf_range(80.0, 820.0)
		bullet.global_position = Vector2(x_pos, 40.0)
		var to_player = Vector2(x_pos, 40.0).direction_to(player.global_position)
		var drift = Vector2(randf_range(-0.15, 0.15), 0)
		bullet.direction = (to_player + drift).normalized()
		bullet.speed = randf_range(180.0, 260.0)
		bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
		bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
		get_parent().add_child(bullet)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.08).timeout

	# Phase 2: 5 rapid LASER strikes aimed at player
	for i in range(5):
		var aim = global_position.direction_to(player.global_position).angle()
		var spread = (i - 2) * 0.08
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(aim + spread), sin(aim + spread))
		bullet.speed = 320.0
		bullet.bullet_type = EnemyBullet.BulletType.LASER
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout

	await get_tree().create_timer(0.08).timeout

	# Phase 3: 20-bullet aimed fan burst
	var aim_angle = global_position.direction_to(player.global_position).angle()
	for i in range(20):
		var fan_spread = aim_angle + (i - 9.5) * 0.09
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(fan_spread), sin(fan_spread))
		bullet.speed = 240.0
		bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(bullet)

	await get_tree().create_timer(0.08).timeout

	# Phase 4: DECELERATE ring trap spawned around player position
	var trap_center = player.global_position
	for i in range(24):
		var angle = (TAU / 24.0) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = trap_center
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 200.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)

func _boss1_cosmic_mirage() -> void:
	# Super summoning + trapping: decelerate traps, homing orbs, sine snakes
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var corners = [
		Vector2(60.0, 60.0),
		Vector2(840.0, 60.0),
		Vector2(60.0, 540.0),
		Vector2(840.0, 540.0)
	]

	for cycle in range(4):
		# Attack A: DECELERATE ring trap centered on player
		var trap_pos = player.global_position
		for i in range(16):
			var angle = (TAU / 16.0) * i + cycle * 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = trap_pos
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)

		await get_tree().create_timer(0.06).timeout

		# Attack B: HOMING orbs from all 4 corners
		for corner in corners:
			var aim = corner.direction_to(player.global_position)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = corner
			bullet.direction = aim
			bullet.speed = 160.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 2.0
			bullet._homing_duration = 0.6
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)

		await get_tree().create_timer(0.06).timeout

		# Attack C: SINE_WAVE snake stream from boss aimed at player
		var snake_aim = global_position.direction_to(player.global_position).angle()
		for seg in range(14):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			var wobble = sin(seg * 0.6) * 0.15
			bullet.direction = Vector2(cos(snake_aim + wobble), sin(snake_aim + wobble))
			bullet.speed = 200.0 + seg * 4.0
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			bullet.wave_amplitude = 40.0
			bullet.wave_frequency = 3.5
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.02).timeout

		await get_tree().create_timer(0.08).timeout

func _boss1_eternal_storm() -> void:
	# Super spiral + laser + gravity: triple spiral arms with laser and gravity overlays
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	for step in range(80):
		# Triple SPIRAL arms rotating outward
		for arm in range(3):
			var base_angle = step * 0.12 + arm * (TAU / 3.0)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(base_angle), sin(base_angle))
			bullet.speed = 150.0 + step * 0.5
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)

		# Every 8 steps: fire a LASER aimed at player
		if step % 8 == 0:
			var laser_aim = global_position.direction_to(player.global_position).angle()
			var laser = bullet_scene.instantiate() as EnemyBullet
			laser.global_position = global_position
			laser.direction = Vector2(cos(laser_aim), sin(laser_aim))
			laser.speed = 340.0
			laser.bullet_type = EnemyBullet.BulletType.LASER
			laser.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser)

		# Every 12 steps: fire DECELERATE gravity ring (12 bullets)
		if step % 12 == 0:
			for g in range(12):
				var g_angle = (TAU / 12.0) * g + step * 0.05
				var grav = bullet_scene.instantiate() as EnemyBullet
				grav.global_position = global_position
				grav.direction = Vector2(cos(g_angle), sin(g_angle))
				grav.speed = 170.0
				grav.bullet_type = EnemyBullet.BulletType.DECELERATE
				grav.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(grav)

		await get_tree().create_timer(0.03).timeout

func _boss1_void_serpent() -> void:
	# Super summoning + multi-source: 3 giant sine snakes + aimed bursts + edge homing
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var snake_dirs = [-0.5, 0.0, 0.5]
	var edge_spawns = [
		Vector2(60.0, 300.0),
		Vector2(840.0, 300.0),
		Vector2(450.0, 60.0),
		Vector2(450.0, 540.0)
	]

	# Fire 3 giant curving snakes interleaved with aimed bursts and homing
	for seg in range(80):
		# Snake bullets: 3 streams with decreasing speed for coiling effect
		for s in range(3):
			var base_aim = global_position.direction_to(player.global_position).angle()
			var offset_angle = base_aim + snake_dirs[s]
			var wobble = sin(seg * 0.5 + s * 2.0) * 0.25
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(offset_angle + wobble), sin(offset_angle + wobble))
			bullet.speed = 220.0 - seg * 1.5
			if bullet.speed < 60.0:
				bullet.speed = 60.0
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			bullet.wave_amplitude = 35.0 + s * 10.0
			bullet.wave_frequency = 3.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)

		# Every 10 segments: aimed burst at player (10 bullets)
		if seg % 10 == 5:
			var aim = global_position.direction_to(player.global_position).angle()
			for b in range(10):
				var fan = aim + (b - 4.5) * 0.1
				var burst = bullet_scene.instantiate() as EnemyBullet
				burst.global_position = global_position
				burst.direction = Vector2(cos(fan), sin(fan))
				burst.speed = 250.0
				burst.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(burst)

		# Every 16 segments: homing bullets from screen edges
		if seg % 16 == 0:
			for edge in edge_spawns:
				var hb = bullet_scene.instantiate() as EnemyBullet
				hb.global_position = edge
				hb.direction = edge.direction_to(player.global_position)
				hb.speed = 140.0
				hb.bullet_type = EnemyBullet.BulletType.HOMING
				hb._homing_strength = 2.0
				hb._homing_duration = 0.6
				hb.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(hb)

		await get_tree().create_timer(0.03).timeout

func _boss1_cataclysm() -> void:
	# THE ULTIMATE ATTACK - all elements combined in 5 rapid phases
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	# Phase 1: Sand rain from top + aimed fan at player
	for i in range(30):
		var bullet = bullet_scene.instantiate() as EnemyBullet
		var x_pos = randf_range(80.0, 820.0)
		bullet.global_position = Vector2(x_pos, 40.0)
		var to_player = Vector2(x_pos, 40.0).direction_to(player.global_position)
		bullet.direction = (to_player + Vector2(randf_range(-0.1, 0.1), 0)).normalized()
		bullet.speed = randf_range(200.0, 280.0)
		bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
		bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
		get_parent().add_child(bullet)
		if i % 6 == 5:
			await get_tree().create_timer(0.02).timeout
	# Simultaneous aimed fan
	var aim1 = global_position.direction_to(player.global_position).angle()
	for i in range(16):
		var fan = aim1 + (i - 7.5) * 0.1
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(fan), sin(fan))
		bullet.speed = 230.0
		bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(bullet)

	await get_tree().create_timer(0.08).timeout

	# Phase 2: Lightning LASER spiral (24 lasers in spiral pattern)
	for i in range(24):
		var spiral_angle = i * (TAU / 24.0) + i * 0.15
		var laser = bullet_scene.instantiate() as EnemyBullet
		laser.global_position = global_position
		laser.direction = Vector2(cos(spiral_angle), sin(spiral_angle))
		laser.speed = 300.0
		laser.bullet_type = EnemyBullet.BulletType.LASER
		laser.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(laser)
		await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.08).timeout

	# Phase 3: Snake SINE_WAVE stream aimed at player (40 bullets)
	var snake_aim = global_position.direction_to(player.global_position).angle()
	for i in range(40):
		var wobble = sin(i * 0.4) * 0.2
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(snake_aim + wobble), sin(snake_aim + wobble))
		bullet.speed = 210.0 + i * 1.5
		bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
		bullet.wave_amplitude = 45.0
		bullet.wave_frequency = 4.0
		bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
		get_parent().add_child(bullet)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.08).timeout

	# Phase 4: Gravity DECELERATE ring (32 bullets expanding from boss)
	for i in range(32):
		var angle = (TAU / 32.0) * i
		var grav = bullet_scene.instantiate() as EnemyBullet
		grav.global_position = global_position
		grav.direction = Vector2(cos(angle), sin(angle))
		grav.speed = 190.0
		grav.bullet_type = EnemyBullet.BulletType.DECELERATE
		grav.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(grav)

	await get_tree().create_timer(0.08).timeout

	# Phase 5: Final HOMING burst - 16 from boss + 4 from screen edges
	var aim5 = global_position.direction_to(player.global_position).angle()
	for i in range(16):
		var spread = aim5 + (i - 7.5) * 0.12
		var homing = bullet_scene.instantiate() as EnemyBullet
		homing.global_position = global_position
		homing.direction = Vector2(cos(spread), sin(spread))
		homing.speed = 170.0
		homing.bullet_type = EnemyBullet.BulletType.HOMING
		homing._homing_strength = 2.0
		homing._homing_duration = 0.6
		homing.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(homing)
	# Edge homing reinforcements
	var edges = [
		Vector2(60.0, 300.0), Vector2(840.0, 300.0),
		Vector2(450.0, 60.0), Vector2(450.0, 540.0)
	]
	for edge in edges:
		var hb = bullet_scene.instantiate() as EnemyBullet
		hb.global_position = edge
		hb.direction = edge.direction_to(player.global_position)
		hb.speed = 180.0
		hb.bullet_type = EnemyBullet.BulletType.HOMING
		hb._homing_strength = 2.0
		hb._homing_duration = 0.6
		hb.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(hb)


# ============================================================================
# Boss 2 New Skills - Love/Heart Theme (25 skills)
# ============================================================================

# ============================================================================
# Boss 2 - Love's Embrace (Nonspell 1) -- 5 skills
# ============================================================================

func _boss2_heartbeat_pulse() -> void:
	# Rhythmic heartbeat: alternating tight aimed bursts and wide rings.
	# Pink rain falls between beats. 8 beats total, musical rhythm.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for beat in range(8):
		var target_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- BEAT 1: Tight aimed burst at player (12 bullets, narrow spread) ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for i in range(12):
				var spread = aim + (i - 5.5) * 0.07
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 360.0 + i * 10.0
				bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
		# --- BEAT 2: Wide expanding ring (20 bullets) ---
		var ring_count = 20
		for i in range(ring_count):
			var angle = (TAU / ring_count) * i + beat * 0.25
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 180.0 + beat * 15.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		# --- Pink rain from top of screen between beats ---
		for r in range(8):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(randf_range(40, vp.x - 40), randf_range(-10, 15))
			bullet.direction = Vector2(randf_range(-0.08, 0.08), 1).normalized()
			bullet.speed = randf_range(200.0, 320.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout


func _boss2_cupid_arrows_aimed() -> void:
	# Cupid's arrows: 10 volleys of 5 HOMING arrows with wide spread.
	# Between volleys, fire a quick 3-bullet LASER love beam at player.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for volley in range(10):
		# --- 5 HOMING arrows aimed at player with wide spread ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for i in range(5):
				var spread = aim + (i - 2) * 0.4
				var arrow = bullet_scene.instantiate() as EnemyBullet
				arrow.global_position = global_position + Vector2(cos(spread), sin(spread)) * 20.0
				arrow.direction = Vector2(cos(spread), sin(spread))
				arrow.speed = 240.0
				arrow.bullet_type = EnemyBullet.BulletType.HOMING
				arrow._homing_strength = 2.5
				arrow._homing_duration = 0.5
				arrow.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(arrow)
		await get_tree().create_timer(0.10).timeout
		# --- 3-bullet LASER love beam aimed at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for k in range(3):
				var laser = bullet_scene.instantiate() as EnemyBullet
				laser.global_position = global_position
				laser.direction = Vector2(cos(aim + (k - 1) * 0.05), sin(aim + (k - 1) * 0.05))
				laser.speed = 580.0
				laser.bullet_type = EnemyBullet.BulletType.LASER
				laser.set_sprite("res://assets/sprites/bossbullut-14.png")
				get_parent().add_child(laser)
		await get_tree().create_timer(0.05).timeout


func _boss2_love_shower() -> void:
	# Dense heart rain from top with SINE_WAVE wobble. BOUNCE bullets from edges.
	# Creates a curtain the player must weave through. 6 waves.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for wave in range(6):
		# --- 20 columns of sine-wave rain from top ---
		for col in range(20):
			var x_pos = 30 + col * ((vp.x - 60) / 20.0)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, randf_range(-15, 10))
			bullet.direction = Vector2(0, 1)
			bullet.speed = randf_range(160.0, 260.0)
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			bullet.wave_amplitude = 30.0
			bullet.wave_frequency = 3.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
		# --- BOUNCE bullets from left edge aimed at player ---
		if player and is_instance_valid(player):
			for j in range(4):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = Vector2(15, 80 + j * 120 + wave * 20)
				bullet.direction = (player.global_position - bullet.global_position).normalized().rotated(randf_range(-0.15, 0.15))
				bullet.speed = randf_range(250.0, 340.0)
				bullet.bullet_type = EnemyBullet.BulletType.BOUNCE
				bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(bullet)
		# --- BOUNCE bullets from right edge aimed at player ---
		if player and is_instance_valid(player):
			for j in range(4):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = Vector2(vp.x - 15, 80 + j * 120 + wave * 20)
				bullet.direction = (player.global_position - bullet.global_position).normalized().rotated(randf_range(-0.15, 0.15))
				bullet.speed = randf_range(250.0, 340.0)
				bullet.bullet_type = EnemyBullet.BulletType.BOUNCE
				bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


func _boss2_affection_wave() -> void:
	# Alternating CURVE bullet waves from boss - left curve then right curve.
	# Between waves, fire 6 SPLIT bullets at player. 8 waves, very fast.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for wave in range(8):
		var curve_dir = 1.5 if wave % 2 == 0 else -1.5
		# --- 20 CURVE bullets aimed roughly at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for i in range(20):
				var spread = aim + (i - 9.5) * 0.09
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 240.0 + i * 6.0
				bullet.bullet_type = EnemyBullet.BulletType.CURVE
				bullet.turn_rate = curve_dir
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		# --- 6 SPLIT bullets aimed at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(6):
				var spread = aim + (j - 2.5) * 0.2
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 280.0
				bullet.bullet_type = EnemyBullet.BulletType.SPLIT
				bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout


func _boss2_romance_spiral() -> void:
	# Dual spiral arms (180 degrees apart) firing continuously.
	# Every 12 steps, spawn 12 orbit bullets around player that dash inward.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var spiral_angle = 0.0
	for step in range(60):
		# --- 2 spiral arms, 180 degrees apart ---
		for arm in range(2):
			var angle = spiral_angle + arm * PI
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 220.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
			# Second layer slightly offset for density
			var inner = bullet_scene.instantiate() as EnemyBullet
			inner.global_position = global_position
			inner.direction = Vector2(cos(angle + 0.12), sin(angle + 0.12))
			inner.speed = 180.0
			inner.set_sprite("res://assets/sprites/bossbullut-4.png")
			get_parent().add_child(inner)
		spiral_angle += 0.14
		# --- Every 12 steps, orbit ring around player ---
		if step % 12 == 0 and player and is_instance_valid(player):
			var center = player.global_position
			for i in range(12):
				var ring_angle = (TAU / 12.0) * i
				var radius = 180.0
				var spawn_pos = center + Vector2(cos(ring_angle), sin(ring_angle)) * radius
				var orb = bullet_scene.instantiate() as EnemyBullet
				orb.global_position = spawn_pos
				orb.direction = Vector2(cos(ring_angle + PI / 2), sin(ring_angle + PI / 2))
				orb.speed = 0.0
				orb.orbit_center = center
				orb.orbit_radius = radius
				orb.orbit_angle = ring_angle
				orb.orbit_angular_speed = 4.0
				orb.orbit_time_left = 1.0
				orb.dash_after_orbit = true
				orb.dash_target = center
				orb.dash_speed = 300.0
				orb.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(orb)
		await get_tree().create_timer(0.04).timeout


# ============================================================================
# Boss 2 - Dark Heart (Spell 1) -- 5 skills
# ============================================================================

func _boss2_black_heart_expand() -> void:
	# Signature black heart attack! 3 waves of heart-shaped DECELERATE patterns.
	# Parametric heart: x=16*sin^3(t), y=-(13*cos(t)-5*cos(2t)-2*cos(3t)-cos(4t))
	# Hearts expand outward, stop, then re-aim at player. Aimed fans between hearts.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for heart_wave in range(3):
		# --- Heart shape using parametric equation (30 bullets) ---
		var heart_count = 30
		for i in range(heart_count):
			var t = (TAU / heart_count) * i
			var hx = 16.0 * pow(sin(t), 3)
			var hy = -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
			var heart_dir = Vector2(hx, hy).normalized()
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = heart_dir
			bullet.speed = 200.0 + heart_wave * 30.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout
		# --- Aimed fan between hearts ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(9):
				var spread = aim + (j - 4) * 0.18
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 320.0
				bullet.set_sprite("res://assets/sprites/bossbullut-7.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout


func _boss2_jealousy_thorns() -> void:
	# Jealousy thorns: 8 waves of 10 BOUNCE bullets in a spread.
	# Between bouncing waves, fire aimed ACCELERATE bullets at player.
	# Screen fills with ricocheting dark purple thorns.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for wave in range(8):
		# --- 10 BOUNCE bullets in a spread from boss ---
		var base_angle = (TAU / 8.0) * wave
		for i in range(10):
			var angle = base_angle + (i - 4.5) * 0.22
			var thorn = bullet_scene.instantiate() as EnemyBullet
			thorn.global_position = global_position
			thorn.direction = Vector2(cos(angle), sin(angle))
			thorn.speed = randf_range(200.0, 340.0)
			thorn.bullet_type = EnemyBullet.BulletType.BOUNCE
			thorn.set_sprite("res://assets/sprites/bossbullut-7.png")
			get_parent().add_child(thorn)
		await get_tree().create_timer(0.05).timeout
		# --- 6 ACCELERATE bullets aimed at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(6):
				var spread = aim + (j - 2.5) * 0.12
				var accel = bullet_scene.instantiate() as EnemyBullet
				accel.global_position = global_position
				accel.direction = Vector2(cos(spread), sin(spread))
				accel.speed = 140.0
				accel.bullet_type = EnemyBullet.BulletType.ACCELERATE
				accel.acceleration = 350.0
				accel.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(accel)
		await get_tree().create_timer(0.08).timeout


func _boss2_heartstring_web() -> void:
	# Heartstring web: CURVE bullets fired from 8 compass points around the player,
	# curving inward to weave a tangled web of strings. Between waves, boss fires
	# aimed SPIRAL bullets at player. 6 waves of tightening strings.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for wave in range(6):
		# --- 8 anchor points around player, CURVE bullets curving inward ---
		if player and is_instance_valid(player):
			var center = player.global_position
			for anchor in range(8):
				var ring_angle = (TAU / 8.0) * anchor + wave * 0.3
				var radius = 220.0 - wave * 15.0
				var spawn_pos = center + Vector2(cos(ring_angle), sin(ring_angle)) * radius
				spawn_pos.x = clampf(spawn_pos.x, 20, vp.x - 20)
				spawn_pos.y = clampf(spawn_pos.y, 20, vp.y - 20)
				# Fire 3 CURVE bullets per anchor, alternating curve direction
				for strand in range(3):
					var aim_angle = spawn_pos.direction_to(center).angle()
					var offset_angle = aim_angle + (strand - 1) * 0.25
					var curve_b = bullet_scene.instantiate() as EnemyBullet
					curve_b.global_position = spawn_pos
					curve_b.direction = Vector2(cos(offset_angle), sin(offset_angle))
					curve_b.speed = 240.0 + strand * 30.0
					curve_b.bullet_type = EnemyBullet.BulletType.CURVE
					curve_b.turn_rate = 2.0 if anchor % 2 == 0 else -2.0
					curve_b.set_sprite("res://assets/sprites/bossbullut-6.png")
					get_parent().add_child(curve_b)
		await get_tree().create_timer(0.08).timeout
		# --- Boss fires 8 SPIRAL bullets aimed at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for s in range(8):
				var spread = aim + (s - 3.5) * 0.15
				var spiral_b = bullet_scene.instantiate() as EnemyBullet
				spiral_b.global_position = global_position
				spiral_b.direction = Vector2(cos(spread), sin(spread))
				spiral_b.speed = 280.0
				spiral_b.bullet_type = EnemyBullet.BulletType.SPIRAL
				spiral_b.set_sprite("res://assets/sprites/bossbullut-7.png")
				get_parent().add_child(spiral_b)
		await get_tree().create_timer(0.06).timeout


func _boss2_passion_rain() -> void:
	# Passion rain: Dense columns of SPLIT bullets rain from the top of the screen,
	# fragmenting near the player's vertical position. Boss simultaneously fires
	# aimed SINE_WAVE volleys at the player. 7 waves of overwhelming passion.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for wave in range(7):
		# --- 16 SPLIT rain bullets from top, spread across screen width ---
		for col in range(16):
			var x_pos = 25 + col * ((vp.x - 50) / 16.0) + randf_range(-10, 10)
			var rain = bullet_scene.instantiate() as EnemyBullet
			rain.global_position = Vector2(x_pos, randf_range(-20, 5))
			# Aim slightly toward player's X position
			var x_drift = 0.0
			if player and is_instance_valid(player):
				x_drift = clampf((player.global_position.x - x_pos) * 0.002, -0.15, 0.15)
			rain.direction = Vector2(x_drift, 1).normalized()
			rain.speed = randf_range(220.0, 340.0)
			rain.bullet_type = EnemyBullet.BulletType.SPLIT
			rain.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(rain)
		await get_tree().create_timer(0.05).timeout
		# --- Boss fires 10 SINE_WAVE bullets aimed at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for i in range(10):
				var spread = aim + (i - 4.5) * 0.12
				var sine_b = bullet_scene.instantiate() as EnemyBullet
				sine_b.global_position = global_position
				sine_b.direction = Vector2(cos(spread), sin(spread))
				sine_b.speed = 260.0 + i * 8.0
				sine_b.bullet_type = EnemyBullet.BulletType.SINE_WAVE
				sine_b.wave_amplitude = 25.0
				sine_b.wave_frequency = 4.0
				sine_b.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(sine_b)
		await get_tree().create_timer(0.04).timeout
		# --- 4 fast dark bullets aimed directly at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for k in range(4):
				var snipe = bullet_scene.instantiate() as EnemyBullet
				snipe.global_position = global_position
				snipe.direction = Vector2(cos(aim + (k - 1.5) * 0.06), sin(aim + (k - 1.5) * 0.06))
				snipe.speed = 380.0
				snipe.set_sprite("res://assets/sprites/bossbullut-7.png")
				get_parent().add_child(snipe)
		await get_tree().create_timer(0.10).timeout


func _boss2_dark_cupid() -> void:
	# Dark cupid: HOMING arrows spawn from all 4 screen edges and home toward
	# the player. Between edge volleys, boss fires aimed LASER beams in a tight
	# fan. Alternating pressure from edges and center. 6 cycles.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for cycle in range(6):
		# --- 12 HOMING arrows from screen edges ---
		if player and is_instance_valid(player):
			for h in range(12):
				var edge_pos: Vector2
				match h % 4:
					0: edge_pos = Vector2(randf_range(40, vp.x - 40), 5)
					1: edge_pos = Vector2(randf_range(40, vp.x - 40), vp.y - 5)
					2: edge_pos = Vector2(5, randf_range(40, vp.y - 40))
					3: edge_pos = Vector2(vp.x - 5, randf_range(40, vp.y - 40))
				var arrow = bullet_scene.instantiate() as EnemyBullet
				arrow.global_position = edge_pos
				arrow.direction = edge_pos.direction_to(player.global_position)
				arrow.speed = 230.0 + h * 10.0
				arrow.bullet_type = EnemyBullet.BulletType.HOMING
				arrow._homing_strength = 2.5
				arrow._homing_duration = 0.8
				arrow.set_sprite("res://assets/sprites/bossbullut-4.png")
				get_parent().add_child(arrow)
				await get_tree().create_timer(0.03).timeout
		# --- Boss fires 6 LASER beams in aimed fan ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for l in range(6):
				var fan_angle = aim + (l - 2.5) * 0.18
				var laser = bullet_scene.instantiate() as EnemyBullet
				laser.global_position = global_position
				laser.direction = Vector2(cos(fan_angle), sin(fan_angle))
				laser.speed = 350.0
				laser.bullet_type = EnemyBullet.BulletType.LASER
				laser.set_sprite("res://assets/sprites/bossbullut-14.png")
				get_parent().add_child(laser)
		await get_tree().create_timer(0.07).timeout
		# --- 6 ACCELERATE bullets aimed at player for pressure ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for a in range(6):
				var acc_angle = aim + (a - 2.5) * 0.10
				var acc_b = bullet_scene.instantiate() as EnemyBullet
				acc_b.global_position = global_position
				acc_b.direction = Vector2(cos(acc_angle), sin(acc_angle))
				acc_b.speed = 200.0
				acc_b.bullet_type = EnemyBullet.BulletType.ACCELERATE
				acc_b.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(acc_b)
		await get_tree().create_timer(0.12).timeout

# ============================================================================
# Boss 2 - Heart Rain (Nonspell 2) -- 5 skills
# ============================================================================

func _boss2_valentine_storm() -> void:
	# Dense heart rain from top with random x-drift. Every other wave adds 8
	# BOUNCE bullets from left/right edges that ricochet across the screen.
	# Pink rain + red bouncing hearts = beautiful valentine chaos.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for wave in range(8):
		# --- 25 heart rain bullets falling from top with slight x-drift ---
		for i in range(25):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			var x_pos = randf_range(30, vp.x - 30)
			bullet.global_position = Vector2(x_pos, randf_range(-20, 10))
			var x_drift = randf_range(-0.18, 0.18)
			bullet.direction = Vector2(x_drift, 1.0).normalized()
			bullet.speed = randf_range(180.0, 300.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout
		# --- Every other wave: 8 BOUNCE bullets from left/right edges ---
		if wave % 2 == 0:
			for side in range(2):
				var edge_x = 15.0 if side == 0 else vp.x - 15.0
				for j in range(4):
					var bullet = bullet_scene.instantiate() as EnemyBullet
					var y_pos = 80.0 + j * 130.0 + randf_range(-20, 20)
					bullet.global_position = Vector2(edge_x, y_pos)
					var aim_dir: Vector2
					if player and is_instance_valid(player):
						aim_dir = (player.global_position - bullet.global_position).normalized()
					else:
						aim_dir = Vector2(1.0 - side * 2.0, 0.3).normalized()
					bullet.direction = aim_dir.rotated(randf_range(-0.2, 0.2))
					bullet.speed = randf_range(280.0, 380.0)
					bullet.bullet_type = EnemyBullet.BulletType.BOUNCE
					bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
					get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout


func _boss2_love_letter_cascade() -> void:
	# Cascading "love letters": bullets fall from top in 5 columns. Each column
	# fires 6 SPLIT bullets that split into 3 after falling partway, creating a
	# "letter opening" visual. Between cascades, fire aimed fans at player.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for cascade in range(6):
		# --- 5 columns of 6 SPLIT bullets each ---
		var col_spacing = (vp.x - 120.0) / 4.0
		for col in range(5):
			var col_x = 60.0 + col * col_spacing + randf_range(-15, 15)
			for row in range(6):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = Vector2(col_x + randf_range(-8, 8), -10.0 - row * 18.0)
				var drift = (col - 2.0) * 0.04
				bullet.direction = Vector2(drift, 1.0).normalized()
				bullet.speed = 200.0 + row * 15.0
				bullet.bullet_type = EnemyBullet.BulletType.SPLIT
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		# --- Aimed fan at player from boss between cascades ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for f in range(9):
				var spread = aim + (f - 4.0) * 0.15
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 300.0
				bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


func _boss2_rose_petal_fall() -> void:
	# Rose petals: 80 SINE_WAVE bullets fall from top with beautiful wobble.
	# Simultaneously, HOMING "thorns" spawn from screen edges (4 per wave, 6 waves).
	# The sine wave creates a gentle falling petal visual while thorns pressure player.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for wave in range(6):
		# --- ~13 rose petal SINE_WAVE bullets per wave (80 total across 6 waves) ---
		var petals_this_wave = 13 if wave < 5 else 15
		for i in range(petals_this_wave):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			var x_pos = randf_range(25, vp.x - 25)
			bullet.global_position = Vector2(x_pos, randf_range(-25, 5))
			bullet.direction = Vector2(randf_range(-0.06, 0.06), 1.0).normalized()
			bullet.speed = randf_range(120.0, 200.0)
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			bullet.wave_amplitude = 35.0
			bullet.wave_frequency = 2.5
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout
		# --- 4 HOMING thorn bullets from screen edges ---
		if player and is_instance_valid(player):
			var edge_positions: Array[Vector2] = [
				Vector2(15, randf_range(80, vp.y - 80)),
				Vector2(vp.x - 15, randf_range(80, vp.y - 80)),
				Vector2(randf_range(80, vp.x - 80), 15),
				Vector2(randf_range(80, vp.x - 80), vp.y - 15)
			]
			for e in range(4):
				var thorn = bullet_scene.instantiate() as EnemyBullet
				thorn.global_position = edge_positions[e]
				thorn.direction = (player.global_position - thorn.global_position).normalized()
				thorn.speed = 200.0
				thorn.bullet_type = EnemyBullet.BulletType.HOMING
				thorn._homing_strength = 2.0
				thorn._homing_duration = 0.6
				thorn.set_sprite("res://assets/sprites/bossbullut-7.png")
				get_parent().add_child(thorn)
		await get_tree().create_timer(0.12).timeout


func _boss2_confession_barrage() -> void:
	# Confession: Rapid aimed bursts at player (15 bullets per burst, 10 bursts).
	# Every 3rd burst is DECELERATE type -- bullets stop near player then re-aim.
	# Between bursts, fire a quick ring of 12 bullets. Very aggressive and fast.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for burst in range(10):
		var target_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		var aim = global_position.direction_to(target_pos).angle()
		var is_decel = (burst % 3 == 2)
		# --- 15-bullet aimed burst at player ---
		for i in range(15):
			var spread = aim + (i - 7.0) * 0.06
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 340.0 + i * 8.0
			if is_decel:
				bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
				bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			else:
				bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout
		# --- Quick ring of 12 bullets between bursts ---
		for r in range(12):
			var ring_angle = (TAU / 12.0) * r + burst * 0.3
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(ring_angle), sin(ring_angle))
			bullet.speed = 220.0
			bullet.set_sprite("res://assets/sprites/bossbullut-4.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout


func _boss2_broken_mirror() -> void:
	# Broken mirror: BOUNCE bullets in aimed fans ricochet off walls like shattered
	# glass. Between volleys, black big hearts spawn at boss and GROW
	# before launching at the player. 7 volleys of reflected shards + growing hearts.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for volley in range(7):
		var aim = global_position.direction_to(player.global_position).angle()
		# --- 12-bullet BOUNCE fan aimed at player ---
		for i in range(12):
			var spread = aim + (i - 5.5) * 0.13
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = randf_range(280.0, 370.0)
			bullet.bullet_type = EnemyBullet.BulletType.BOUNCE
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout
		# --- 3 black big hearts that grow then launch at player ---
		var hearts_this_volley: Array[EnemyBullet] = []
		for h in range(3):
			var heart = bullet_scene.instantiate() as EnemyBullet
			heart.global_position = global_position + Vector2(randf_range(-30, 30), randf_range(-20, 20))
			heart.direction = Vector2.ZERO
			heart.speed = 0.0
			heart.scale = Vector2(0.4, 0.4)
			heart.set_sprite("res://assets/sprites/bossbullut-7.png")
			get_parent().add_child(heart)
			hearts_this_volley.append(heart)
			var tw = get_tree().create_tween()
			tw.tween_property(heart, "scale", Vector2(2.2, 2.2), 0.35)
		await get_tree().create_timer(0.38).timeout
		# Launch grown hearts at player
		for heart in hearts_this_volley:
			if is_instance_valid(heart) and player and is_instance_valid(player):
				heart.direction = (player.global_position - heart.global_position).normalized()
				heart.speed = 240.0
		await get_tree().create_timer(0.08).timeout


# ============================================================================
# Boss 2 - Forbidden Love (Spell 2) -- 5 skills
# ============================================================================

func _boss2_love_cage() -> void:
	# Love cage: Orbit bullets circle the player then dash inward. Between orbit
	# waves, boss fires aimed SINE_WAVE fans. The orbiting hearts close in like a
	# cage of love. 6 waves of orbit-dash + sine fans.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for wave in range(6):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 10 orbit bullets circling the player ---
		for i in range(10):
			var orbit_angle = (TAU / 10.0) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = p_pos + Vector2(cos(orbit_angle), sin(orbit_angle)) * 160.0
			bullet.direction = Vector2.ZERO
			bullet.speed = 0.0
			bullet.orbit_center = p_pos
			bullet.orbit_radius = 160.0
			bullet.orbit_angle = orbit_angle
			bullet.orbit_angular_speed = 3.5
			bullet.orbit_time_left = 1.2
			bullet.dash_after_orbit = true
			bullet.dash_target = p_pos
			bullet.dash_speed = 320.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		# --- 8 SINE_WAVE bullets aimed at player from boss ---
		var aim = global_position.direction_to(p_pos).angle()
		for j in range(8):
			var spread = aim + (j - 3.5) * 0.18
			var sine_b = bullet_scene.instantiate() as EnemyBullet
			sine_b.global_position = global_position
			sine_b.direction = Vector2(cos(spread), sin(spread))
			sine_b.speed = 260.0
			sine_b.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			sine_b.amplitude = 35.0
			sine_b.frequency = 5.0
			sine_b.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(sine_b)
		await get_tree().create_timer(0.12).timeout


func _boss2_heartbreak_rain() -> void:
	# Heartbreak rain: Dense SPLIT rain from top of screen aimed
	# toward the player. Each raindrop splits into 3 smaller bullets on a timer,
	# creating a cascading downpour. Boss also fires aimed ACCELERATE bursts. 8 waves.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for wave in range(8):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 18 SPLIT rain bullets from top, angled toward player ---
		for i in range(18):
			var x_pos = randf_range(30, vp.x - 30)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, randf_range(-15, 5))
			var dir_to_player = (p_pos - bullet.global_position).normalized()
			var drift = Vector2(randf_range(-0.15, 0.15), 0)
			bullet.direction = (dir_to_player + drift).normalized()
			bullet.speed = randf_range(200.0, 310.0)
			bullet.bullet_type = EnemyBullet.BulletType.SPLIT
			bullet.split_count = 3
			bullet.split_angle_spread = 0.5
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout
		# --- 6 ACCELERATE bullets from boss aimed at player ---
		var aim = global_position.direction_to(p_pos).angle()
		for j in range(6):
			var spread = aim + (j - 2.5) * 0.22
			var acc_b = bullet_scene.instantiate() as EnemyBullet
			acc_b.global_position = global_position
			acc_b.direction = Vector2(cos(spread), sin(spread))
			acc_b.speed = 200.0
			acc_b.bullet_type = EnemyBullet.BulletType.ACCELERATE
			acc_b.set_sprite("res://assets/sprites/bossbullut-4.png")
			get_parent().add_child(acc_b)
		await get_tree().create_timer(0.10).timeout


func _boss2_dark_devotion() -> void:
	# Dark devotion: DECELERATE heart rings expand from boss, slow to a stop, then
	# re-aim and ACCELERATE toward the player. Black hearts (bossbullut-7) that
	# decelerate create a freeze-frame effect before homing in. 6 rings of 14 bullets.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for ring in range(6):
		var ring_bullets: Array[EnemyBullet] = []
		# --- 14-bullet DECELERATE ring expanding from boss ---
		for i in range(14):
			var angle = (TAU / 14.0) * i + ring * 0.25
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 300.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
			ring_bullets.append(bullet)
		await get_tree().create_timer(0.03).timeout
		# --- 5 aimed SPIRAL bullets from boss at player ---
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		var aim = global_position.direction_to(p_pos).angle()
		for j in range(5):
			var spread = aim + (j - 2.0) * 0.28
			var sp_b = bullet_scene.instantiate() as EnemyBullet
			sp_b.global_position = global_position
			sp_b.direction = Vector2(cos(spread), sin(spread))
			sp_b.speed = 250.0
			sp_b.bullet_type = EnemyBullet.BulletType.SPIRAL
			sp_b.set_sprite("res://assets/sprites/bossbullut-7.png")
			get_parent().add_child(sp_b)
		# Wait for decelerate bullets to slow down, then re-aim them
		await get_tree().create_timer(0.55).timeout
		for b in ring_bullets:
			if is_instance_valid(b) and player and is_instance_valid(player):
				b.direction = (player.global_position - b.global_position).normalized()
				b.speed = 280.0
				b.bullet_type = EnemyBullet.BulletType.ACCELERATE
		await get_tree().create_timer(0.08).timeout


func _boss2_forbidden_kiss() -> void:
	# Forbidden kiss: HOMING bullets spawn from screen edges and chase the player
	# while the boss fires LASER beams aimed at the player. The combination of
	# persistent homing and sweeping lasers creates deadly crossfire. 7 waves.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for wave in range(7):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 8 HOMING bullets from random screen edges aimed at player ---
		for i in range(8):
			var edge_pos: Vector2
			var side = randi() % 4
			match side:
				0: edge_pos = Vector2(randf_range(0, vp.x), -10)
				1: edge_pos = Vector2(randf_range(0, vp.x), vp.y + 10)
				2: edge_pos = Vector2(-10, randf_range(0, vp.y))
				3: edge_pos = Vector2(vp.x + 10, randf_range(0, vp.y))
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = edge_pos
			bullet.direction = (p_pos - edge_pos).normalized()
			bullet.speed = 220.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 2.5
			bullet._homing_duration = 1.5
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout
		# --- 4 LASER beams from boss aimed at player with slight spread ---
		var aim = global_position.direction_to(p_pos).angle()
		for j in range(4):
			var spread = aim + (j - 1.5) * 0.15
			var laser = bullet_scene.instantiate() as EnemyBullet
			laser.global_position = global_position
			laser.direction = Vector2(cos(spread), sin(spread))
			laser.speed = 380.0
			laser.bullet_type = EnemyBullet.BulletType.LASER
			laser.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser)
		await get_tree().create_timer(0.02).timeout
		# --- 6 pink scatter bullets from boss toward player ---
		for k in range(6):
			var scatter = aim + randf_range(-0.5, 0.5)
			var pink = bullet_scene.instantiate() as EnemyBullet
			pink.global_position = global_position
			pink.direction = Vector2(cos(scatter), sin(scatter))
			pink.speed = randf_range(250.0, 340.0)
			pink.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(pink)
		await get_tree().create_timer(0.10).timeout


func _boss2_love_labyrinth() -> void:
	# Love labyrinth: CURVE bullet walls spawn from all 4 sides and curve inward
	# toward the player, forming closing maze walls. Boss also fires aimed BOUNCE
	# fans through the gaps. The curving walls force the player to navigate a
	# shrinking labyrinth of love. 6 waves.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for wave in range(6):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- CURVE walls from 4 sides, 6 bullets per side, aimed toward player ---
		# Top wall
		for i in range(6):
			var x = (vp.x / 7.0) * (i + 1)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x, -10)
			bullet.direction = (p_pos - bullet.global_position).normalized()
			bullet.speed = randf_range(210.0, 290.0)
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.curve_strength = randf_range(1.5, 3.0) * (1 if randf() > 0.5 else -1)
			bullet.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout
		# Bottom wall
		for i in range(6):
			var x = (vp.x / 7.0) * (i + 1)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x, vp.y + 10)
			bullet.direction = (p_pos - bullet.global_position).normalized()
			bullet.speed = randf_range(210.0, 290.0)
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.curve_strength = randf_range(1.5, 3.0) * (1 if randf() > 0.5 else -1)
			bullet.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout
		# Left wall
		for i in range(6):
			var y = (vp.y / 7.0) * (i + 1)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(-10, y)
			bullet.direction = (p_pos - bullet.global_position).normalized()
			bullet.speed = randf_range(210.0, 290.0)
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.curve_strength = randf_range(1.5, 3.0) * (1 if randf() > 0.5 else -1)
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout
		# Right wall
		for i in range(6):
			var y = (vp.y / 7.0) * (i + 1)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(vp.x + 10, y)
			bullet.direction = (p_pos - bullet.global_position).normalized()
			bullet.speed = randf_range(210.0, 290.0)
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.curve_strength = randf_range(1.5, 3.0) * (1 if randf() > 0.5 else -1)
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout
		# --- 8 BOUNCE bullets from boss aimed at player through gaps ---
		var aim = global_position.direction_to(p_pos).angle()
		for j in range(8):
			var spread = aim + (j - 3.5) * 0.16
			var bounce_b = bullet_scene.instantiate() as EnemyBullet
			bounce_b.global_position = global_position
			bounce_b.direction = Vector2(cos(spread), sin(spread))
			bounce_b.speed = randf_range(300.0, 370.0)
			bounce_b.bullet_type = EnemyBullet.BulletType.BOUNCE
			bounce_b.set_sprite("res://assets/sprites/bossbullut-7.png")
			get_parent().add_child(bounce_b)
		await get_tree().create_timer(0.12).timeout

# =============================================================================
# FINAL PHASE - Made in Heaven (5 super skills) - Boss 2 Love/Heart Theme
# =============================================================================

func _boss2_eternal_love() -> void:
	# Super: Heart shape (SPLIT) -> dense rain at player -> HOMING barrage
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	# Phase 1: HUGE heart-shaped pattern using parametric heart equation, all SPLIT
	for i in range(40):
		var t = (float(i) / 40.0) * TAU
		var hx = 8.0 * (16.0 * pow(sin(t), 3))
		var hy = -8.0 * (13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		var heart_offset = Vector2(hx, hy)
		var spawn_pos = global_position + heart_offset / 16.0
		var outward = heart_offset.normalized()
		if outward.length() < 0.01:
			outward = Vector2.UP
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = spawn_pos
		bullet.direction = outward
		bullet.speed = 120.0
		bullet.bullet_type = EnemyBullet.BulletType.SPLIT
		bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
		get_parent().add_child(bullet)
		if i % 5 == 4:
			await get_tree().create_timer(0.04).timeout

	await get_tree().create_timer(0.08).timeout

	# Phase 2: Dense rain from top aimed at player (30 bullets)
	var vp = get_viewport_rect().size
	for i in range(30):
		var x_pos = randf_range(60.0, vp.x - 60.0)
		var rain_origin = Vector2(x_pos, 20.0)
		var to_player = rain_origin.direction_to(player.global_position)
		var drift = Vector2(randf_range(-0.12, 0.12), 0)
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = rain_origin
		bullet.direction = (to_player + drift).normalized()
		bullet.speed = randf_range(220.0, 320.0)
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)
		if i % 6 == 5:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.08).timeout

	# Phase 3: 16 HOMING bullets from boss converging on player
	var aim_angle = global_position.direction_to(player.global_position).angle()
	for i in range(16):
		var spread = aim_angle + (i - 7.5) * 0.25
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(spread), sin(spread))
		bullet.speed = 200.0
		bullet.bullet_type = EnemyBullet.BulletType.HOMING
		bullet._homing_strength = 2.0
		bullet._homing_duration = 0.6
		bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
		get_parent().add_child(bullet)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout


func _boss2_heaven_ascension() -> void:
	# Super: Dense quad spiral + BOUNCE ricochets + LASER beams = maximum chaos
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	# Dense quad spiral: 4 arms, 80 steps, with BOUNCE and LASER overlays
	for step in range(80):
		# 4 spiral arms rotating outward
		for arm in range(4):
			var base_angle = step * 0.10 + arm * (TAU / 4.0)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(base_angle), sin(base_angle))
			bullet.speed = 140.0 + step * 0.6
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)

		# Every 8 steps: 6 BOUNCE bullets aimed at player that ricochet everywhere
		if step % 8 == 0:
			var bounce_aim = global_position.direction_to(player.global_position).angle()
			for b in range(6):
				var spread = bounce_aim + (b - 2.5) * 0.18
				var bounce = bullet_scene.instantiate() as EnemyBullet
				bounce.global_position = global_position
				bounce.direction = Vector2(cos(spread), sin(spread))
				bounce.speed = 280.0
				bounce.bullet_type = EnemyBullet.BulletType.BOUNCE
				bounce.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(bounce)

		# Every 12 steps: 2 LASER beams aimed at player
		if step % 12 == 0:
			var laser_aim = global_position.direction_to(player.global_position).angle()
			for l in range(2):
				var offset = (l - 0.5) * 0.12
				var laser = bullet_scene.instantiate() as EnemyBullet
				laser.global_position = global_position
				laser.direction = Vector2(cos(laser_aim + offset), sin(laser_aim + offset))
				laser.speed = 360.0
				laser.bullet_type = EnemyBullet.BulletType.LASER
				laser.set_sprite("res://assets/sprites/bossbullut-7.png")
				get_parent().add_child(laser)

		await get_tree().create_timer(0.03).timeout


func _boss2_heartbreak_apocalypse() -> void:
	# Super: Dense rain -> DECELERATE ring trap -> HOMING edges -> LASER spiral -> orbit cage
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var vp = get_viewport_rect().size

	# Phase 1: Dense rain from top - 36 bullets falling toward player
	for i in range(36):
		var x_pos = randf_range(40.0, vp.x - 40.0)
		var rain_origin = Vector2(x_pos, 10.0)
		var to_player = rain_origin.direction_to(player.global_position)
		var drift = Vector2(randf_range(-0.08, 0.08), 0)
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = rain_origin
		bullet.direction = (to_player + drift).normalized()
		bullet.speed = randf_range(260.0, 360.0)
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)
		if i % 6 == 5:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.08).timeout

	# Phase 2: DECELERATE ring trap - 28 bullets closing ring around player
	var trap_center = player.global_position
	for i in range(28):
		var angle = (TAU / 28.0) * i
		var spawn_pos = trap_center + Vector2(cos(angle), sin(angle)) * 240.0
		var inward = spawn_pos.direction_to(trap_center)
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = spawn_pos
		bullet.direction = inward
		bullet.speed = 220.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-4.png")
		get_parent().add_child(bullet)
		if i % 7 == 6:
			await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.10).timeout

	# Phase 3: HOMING bullets from all 4 screen edges converging on player
	for edge in range(4):
		for j in range(6):
			var spawn = Vector2.ZERO
			match edge:
				0: spawn = Vector2(randf_range(60.0, vp.x - 60.0), 12.0)
				1: spawn = Vector2(randf_range(60.0, vp.x - 60.0), vp.y - 12.0)
				2: spawn = Vector2(12.0, randf_range(60.0, vp.y - 60.0))
				3: spawn = Vector2(vp.x - 12.0, randf_range(60.0, vp.y - 60.0))
			var to_player = spawn.direction_to(player.global_position)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn
			bullet.direction = to_player
			bullet.speed = 210.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 2.5
			bullet._homing_duration = 0.8
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.08).timeout

	# Phase 4: LASER spiral from boss - 6 arms, 50 steps
	for step in range(50):
		for arm in range(6):
			var angle = step * 0.14 + arm * (TAU / 6.0)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0 + step * 0.8
			bullet.bullet_type = EnemyBullet.BulletType.LASER
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 5: Orbit cage around player that dashes inward
	var cage_center = player.global_position
	for i in range(20):
		var angle = (TAU / 20.0) * i
		var spawn_pos = cage_center + Vector2(cos(angle), sin(angle)) * 140.0
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = spawn_pos
		bullet.direction = Vector2.ZERO
		bullet.speed = 0.0
		bullet.set_sprite("res://assets/sprites/bossbullut-7.png")
		bullet.orbit_center = cage_center
		bullet.orbit_radius = 140.0
		bullet.orbit_angle = angle
		bullet.orbit_angular_speed = 4.0
		bullet.orbit_time_left = 1.2
		bullet.dash_after_orbit = true
		bullet.dash_target = cage_center
		bullet.dash_speed = 400.0
		get_parent().add_child(bullet)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout


func _boss2_love_transcendence() -> void:
	# Super: 3 SPLIT streams -> BOUNCE from corners -> CURVE walls -> ACCELERATE barrage
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var vp = get_viewport_rect().size

	# Phase 1: 3 SPLIT streams aimed at player from boss, offset angles
	for stream in range(3):
		var base_aim = global_position.direction_to(player.global_position).angle()
		var stream_offset = (stream - 1) * 0.35
		for i in range(10):
			var wobble = sin(i * 0.8) * 0.12
			var angle = base_aim + stream_offset + wobble
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 240.0 + i * 8.0
			bullet.bullet_type = EnemyBullet.BulletType.SPLIT
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.08).timeout

	# Phase 2: BOUNCE bullets from all 4 corners aimed at player
	var corner_positions = [
		Vector2(25.0, 25.0), Vector2(vp.x - 25.0, 25.0),
		Vector2(25.0, vp.y - 25.0), Vector2(vp.x - 25.0, vp.y - 25.0),
	]
	for rep in range(3):
		for corner in corner_positions:
			var to_player = (corner as Vector2).direction_to(player.global_position)
			for k in range(4):
				var spread = to_player.rotated((k - 1.5) * 0.15)
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = corner as Vector2
				bullet.direction = spread
				bullet.speed = 280.0
				bullet.bullet_type = EnemyBullet.BulletType.BOUNCE
				bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout

	await get_tree().create_timer(0.08).timeout

	# Phase 3: CURVE walls closing in from left and right toward player
	var player_y = player.global_position.y
	for side in range(2):
		for i in range(16):
			var x_start = 15.0 if side == 0 else vp.x - 15.0
			var y_pos = clampf(player_y + (i - 7.5) * 28.0, 30.0, vp.y - 30.0)
			var spawn = Vector2(x_start, y_pos)
			var to_player = spawn.direction_to(player.global_position)
			var curve_dir = to_player.rotated(0.4 if side == 0 else -0.4)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn
			bullet.direction = curve_dir
			bullet.speed = 250.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 4: Aimed ACCELERATE barrage - 24 bullets from boss at player
	var accel_aim = global_position.direction_to(player.global_position).angle()
	for i in range(24):
		var spread = accel_aim + (i - 11.5) * 0.07
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(spread), sin(spread))
		bullet.speed = 200.0
		bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-7.png")
		get_parent().add_child(bullet)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout


func _boss2_ultimate_heartbreak() -> void:
	# THE FINAL ATTACK: rain + spiral + HOMING + DECELERATE traps + LASER in rapid succession
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var vp = get_viewport_rect().size

	# Phase 1: Rapid heart rain - 40 bullets from top aimed at player
	for i in range(40):
		var x_pos = randf_range(30.0, vp.x - 30.0)
		var rain_pos = Vector2(x_pos, 8.0)
		var to_player = rain_pos.direction_to(player.global_position)
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = rain_pos
		bullet.direction = to_player.rotated(randf_range(-0.1, 0.1))
		bullet.speed = randf_range(300.0, 400.0)
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 2: Double spiral from boss - 8 arms, 40 steps
	for step in range(40):
		for arm in range(8):
			var angle = step * 0.18 + arm * (TAU / 8.0)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 220.0 + step * 1.2
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 3: HOMING swarm from boss - 30 bullets fanning out then homing
	var fan_aim = global_position.direction_to(player.global_position).angle()
	for i in range(30):
		var angle = fan_aim + (i - 14.5) * 0.12
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 200.0
		bullet.bullet_type = EnemyBullet.BulletType.HOMING
		bullet._homing_strength = 3.0
		bullet._homing_duration = 1.0
		bullet.set_sprite("res://assets/sprites/bossbullut-4.png")
		get_parent().add_child(bullet)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 4: DECELERATE trap rings - 3 concentric rings around player
	for ring in range(3):
		var ring_center = player.global_position
		var ring_radius = 100.0 + ring * 70.0
		var ring_count = 16 + ring * 4
		for i in range(ring_count):
			var angle = (TAU / float(ring_count)) * i
			var spawn = ring_center + Vector2(cos(angle), sin(angle)) * ring_radius
			var inward = spawn.direction_to(ring_center)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn
			bullet.direction = inward
			bullet.speed = 180.0 + ring * 30.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 5: LASER cross beams from boss aimed at player + orbit finisher
	var laser_aim = global_position.direction_to(player.global_position).angle()
	for beam in range(4):
		var beam_angle = laser_aim + beam * (PI / 2.0)
		for i in range(12):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(beam_angle), sin(beam_angle))
			bullet.speed = 250.0 + i * 12.0
			bullet.bullet_type = EnemyBullet.BulletType.LASER
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.04).timeout

	# Final orbit cage collapse
	var final_center = player.global_position
	for i in range(24):
		var angle = (TAU / 24.0) * i
		var spawn_pos = final_center + Vector2(cos(angle), sin(angle)) * 160.0
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = spawn_pos
		bullet.direction = Vector2.ZERO
		bullet.speed = 0.0
		bullet.set_sprite("res://assets/sprites/bossbullut-14.png")
		bullet.orbit_center = final_center
		bullet.orbit_radius = 160.0
		bullet.orbit_angle = angle
		bullet.orbit_angular_speed = 5.0
		bullet.orbit_time_left = 0.9
		bullet.dash_after_orbit = true
		bullet.dash_target = final_center
		bullet.dash_speed = 400.0
		get_parent().add_child(bullet)
		if i % 6 == 5:
			await get_tree().create_timer(0.02).timeout

# ============================================================================

# ============================================================================
# Boss 3 New Skills - Time/Clock Theme (25 skills)
# ============================================================================

# ============================================================================
# Boss 3 - Clockwork Assault (Nonspell 1) -- 5 skills
# Theme: Time/Clock - aggressive clock-themed attacks targeting the player
# ============================================================================

func _boss3_clock_hand_sweep() -> void:
	# Giant clock hand sweeps across the screen: a dense LASER line rotates from
	# boss aimed toward player, with ACCELERATE bullets trailing behind each step.
	# 30 laser steps rotating around the player's direction + 5 trail bullets each.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var base_aim = global_position.direction_to(player.global_position).angle()
	var sweep_start = base_aim - 1.2  # Start sweep ~70 degrees before player
	for step in range(30):
		if not is_instance_valid(player):
			break
		var sweep_angle = sweep_start + step * 0.08  # Sweep across ~2.4 radians
		# --- LASER bullet forming the clock hand ---
		var laser = bullet_scene.instantiate() as EnemyBullet
		laser.global_position = global_position
		laser.direction = Vector2(cos(sweep_angle), sin(sweep_angle))
		laser.speed = 560.0
		laser.bullet_type = EnemyBullet.BulletType.LASER
		laser.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(laser)
		# --- 5 ACCELERATE trail bullets behind the laser ---
		for t in range(5):
			var trail_offset = 20.0 + t * 18.0
			var trail = bullet_scene.instantiate() as EnemyBullet
			trail.global_position = global_position + Vector2(cos(sweep_angle), sin(sweep_angle)) * trail_offset
			trail.direction = Vector2(cos(sweep_angle + 0.03 * (t - 2)), sin(sweep_angle + 0.03 * (t - 2)))
			trail.speed = 140.0 + t * 20.0
			trail.bullet_type = EnemyBullet.BulletType.ACCELERATE
			trail.acceleration = 280.0
			trail.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(trail)
		await get_tree().create_timer(0.04).timeout


func _boss3_gear_grind() -> void:
	# Interlocking gear patterns: two rings of orbit bullets spinning in opposite
	# directions around the boss, then all dash at the player. Mechanical gears.
	# 2 rings x 20 bullets each = 40 orbit bullets total.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var center = global_position
	var target = player.global_position
	# --- Ring 1: 20 bullets orbiting clockwise at radius 120 ---
	for i in range(20):
		var angle = (TAU / 20.0) * i
		var radius = 120.0
		var spawn_pos = center + Vector2(cos(angle), sin(angle)) * radius
		var gear1 = bullet_scene.instantiate() as EnemyBullet
		gear1.global_position = spawn_pos
		gear1.direction = Vector2(cos(angle + PI / 2), sin(angle + PI / 2))
		gear1.speed = 0.0
		gear1.orbit_center = center
		gear1.orbit_radius = radius
		gear1.orbit_angle = angle
		gear1.orbit_angular_speed = 5.0  # Clockwise
		gear1.orbit_time_left = 1.2
		gear1.dash_after_orbit = true
		gear1.dash_target = target
		gear1.dash_speed = 320.0
		gear1.set_sprite("res://assets/sprites/bossbullut-9.png")
		get_parent().add_child(gear1)
	await get_tree().create_timer(0.06).timeout
	# --- Ring 2: 20 bullets orbiting counter-clockwise at radius 180 ---
	if player and is_instance_valid(player):
		target = player.global_position
	for i in range(20):
		var angle = (TAU / 20.0) * i + 0.16  # Offset for interlocking
		var radius = 180.0
		var spawn_pos = center + Vector2(cos(angle), sin(angle)) * radius
		var gear2 = bullet_scene.instantiate() as EnemyBullet
		gear2.global_position = spawn_pos
		gear2.direction = Vector2(cos(angle - PI / 2), sin(angle - PI / 2))
		gear2.speed = 0.0
		gear2.orbit_center = center
		gear2.orbit_radius = radius
		gear2.orbit_angle = angle
		gear2.orbit_angular_speed = -4.5  # Counter-clockwise
		gear2.orbit_time_left = 1.2
		gear2.dash_after_orbit = true
		gear2.dash_target = target
		gear2.dash_speed = 300.0
		gear2.set_sprite("res://assets/sprites/bossbullut-3.png")
		get_parent().add_child(gear2)
	await get_tree().create_timer(0.08).timeout


func _boss3_pendulum_barrage() -> void:
	# Alternating aimed fan bursts that swing left-right like a pendulum.
	# 8 swings, 12 bullets per swing aimed at player with increasing spread.
	# Mix in HOMING bullets every 3rd swing for extra pressure.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for swing in range(8):
		if not player or not is_instance_valid(player):
			break
		var aim = global_position.direction_to(player.global_position).angle()
		# Pendulum offset: swings left on even, right on odd, amplitude grows
		var pendulum_offset = (0.5 + swing * 0.08) * (1.0 if swing % 2 == 0 else -1.0)
		var fan_center = aim + pendulum_offset
		var spread_step = 0.10 + swing * 0.012  # Spread increases each swing
		# --- 12 bullets in aimed fan ---
		for i in range(12):
			var angle = fan_center + (i - 5.5) * spread_step
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 280.0 + i * 8.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout
		# --- Every 3rd swing: 4 HOMING bullets aimed at player ---
		if swing % 3 == 0 and player and is_instance_valid(player):
			var homing_aim = global_position.direction_to(player.global_position).angle()
			for h in range(4):
				var h_angle = homing_aim + (h - 1.5) * 0.3
				var homing_b = bullet_scene.instantiate() as EnemyBullet
				homing_b.global_position = global_position
				homing_b.direction = Vector2(cos(h_angle), sin(h_angle))
				homing_b.speed = 220.0
				homing_b.bullet_type = EnemyBullet.BulletType.HOMING
				homing_b._homing_strength = 2.5
				homing_b._homing_duration = 0.7
				homing_b.set_sprite("res://assets/sprites/bossbullut-9.png")
				get_parent().add_child(homing_b)
		await get_tree().create_timer(0.08).timeout


func _boss3_minute_hand_rain() -> void:
	# Rain of bullets from top of screen (y=40) all aimed at player position,
	# with DECELERATE bullets that stop and re-aim as time-freeze traps.
	# 6 waves of 15 rain bullets + 8 decelerate traps per wave.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for wave in range(6):
		var target_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 15 rain bullets from top aimed at player ---
		for i in range(15):
			var x_pos = target_pos.x + randf_range(-280, 280)
			x_pos = clampf(x_pos, 30, vp.x - 30)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 40)
			bullet.direction = (target_pos - bullet.global_position).normalized().rotated(randf_range(-0.1, 0.1))
			bullet.speed = randf_range(260.0, 380.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout
		# --- 8 DECELERATE trap bullets that stop and re-aim at player ---
		for j in range(8):
			var trap_x = target_pos.x + randf_range(-200, 200)
			trap_x = clampf(trap_x, 40, vp.x - 40)
			var trap = bullet_scene.instantiate() as EnemyBullet
			trap.global_position = Vector2(trap_x, randf_range(40, 80))
			if player and is_instance_valid(player):
				trap.direction = (player.global_position - trap.global_position).normalized()
			else:
				trap.direction = Vector2(0, 1)
			trap.speed = 300.0
			trap.bullet_type = EnemyBullet.BulletType.DECELERATE
			trap.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(trap)
		await get_tree().create_timer(0.10).timeout


func _boss3_tick_tock_burst() -> void:
	# Alternating fast/slow rhythm like a clock ticking.
	# "Tick" fires 20-bullet aimed fan at player (fast, speed 320).
	# "Tock" fires 16-bullet DECELERATE ring from player position.
	# 6 tick-tock cycles creating rhythmic pressure.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for cycle in range(6):
		# --- TICK: 20-bullet aimed fan at player (fast) ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for i in range(20):
				var spread = aim + (i - 9.5) * 0.08
				var tick_b = bullet_scene.instantiate() as EnemyBullet
				tick_b.global_position = global_position
				tick_b.direction = Vector2(cos(spread), sin(spread))
				tick_b.speed = 320.0 + i * 5.0
				tick_b.set_sprite("res://assets/sprites/bossbullut-9.png")
				get_parent().add_child(tick_b)
		await get_tree().create_timer(0.06).timeout
		# --- TOCK: 16-bullet DECELERATE ring from player position ---
		if player and is_instance_valid(player):
			var center = player.global_position
			for j in range(16):
				var angle = (TAU / 16.0) * j + cycle * 0.2
				var tock_b = bullet_scene.instantiate() as EnemyBullet
				tock_b.global_position = center
				tock_b.direction = Vector2(cos(angle), sin(angle))
				tock_b.speed = 240.0
				tock_b.bullet_type = EnemyBullet.BulletType.DECELERATE
				tock_b.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(tock_b)
		await get_tree().create_timer(0.10).timeout


# ============================================================================
# Boss 3 - Temporal Rift (Spell 1) -- 5 skills
# Theme: Time distortion - teleportation illusions, afterimages, time warps
# ============================================================================

func _boss3_time_warp_volley() -> void:
	# Boss fires aimed bursts, then "teleport" bullets appear at random screen-edge
	# positions and fire inward at player. Simulates temporal displacement.
	# 5 volleys: each has 10 aimed bullets from boss + 6 edge-spawn HOMING bullets.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for volley in range(5):
		# --- 10 aimed bullets from boss at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for i in range(10):
				var spread = aim + (i - 4.5) * 0.11
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 300.0 + i * 10.0
				bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		# --- 6 HOMING bullets from random screen edges ("teleported" in) ---
		if player and is_instance_valid(player):
			for e in range(6):
				var edge_pos: Vector2
				match e % 4:
					0: edge_pos = Vector2(randf_range(60, vp.x - 60), 10)
					1: edge_pos = Vector2(randf_range(60, vp.x - 60), vp.y - 10)
					2: edge_pos = Vector2(10, randf_range(60, vp.y - 60))
					3: edge_pos = Vector2(vp.x - 10, randf_range(60, vp.y - 60))
				var warp_b = bullet_scene.instantiate() as EnemyBullet
				warp_b.global_position = edge_pos
				warp_b.direction = edge_pos.direction_to(player.global_position)
				warp_b.speed = 250.0 + e * 15.0
				warp_b.bullet_type = EnemyBullet.BulletType.HOMING
				warp_b._homing_strength = 2.8
				warp_b._homing_duration = 0.6
				warp_b.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(warp_b)
				await get_tree().create_timer(0.03).timeout
		await get_tree().create_timer(0.10).timeout


func _boss3_afterimage_assault() -> void:
	# Simulates afterimages: bullets spawn from 3 positions (boss pos, and 2 offset
	# "clone" positions +/-150px). All 3 fire aimed fans at player simultaneously.
	# 6 waves, 8 bullets per position per wave = 144 total bullets.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for wave in range(6):
		if not player or not is_instance_valid(player):
			break
		var boss_pos = global_position
		# 3 spawn positions: boss center, left clone, right clone
		var positions = [
			boss_pos,
			boss_pos + Vector2(-150, randf_range(-40, 40)),
			boss_pos + Vector2(150, randf_range(-40, 40))
		]
		var sprites = [
			"res://assets/sprites/bossbullut-3.png",
			"res://assets/sprites/bossbullut-6.png",
			"res://assets/sprites/bossbullut-6.png"
		]
		for p_idx in range(3):
			var origin = positions[p_idx]
			var aim = origin.direction_to(player.global_position).angle()
			for i in range(8):
				var angle = aim + (i - 3.5) * 0.14
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = origin
				bullet.direction = Vector2(cos(angle), sin(angle))
				bullet.speed = 260.0 + wave * 15.0
				bullet.set_sprite(sprites[p_idx])
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout


func _boss3_temporal_shatter() -> void:
	# SPLIT bullets fired in aimed streams at player - they split into 3 after
	# 1 second, creating a cascade of shattered time fragments.
	# 4 rounds of 12 split bullets each, with CURVE bullet interludes.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for round_idx in range(4):
		# --- 12 SPLIT bullets aimed at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for i in range(12):
				var angle = aim + (i - 5.5) * 0.09
				var split_b = bullet_scene.instantiate() as EnemyBullet
				split_b.global_position = global_position
				split_b.direction = Vector2(cos(angle), sin(angle))
				split_b.speed = 220.0 + i * 8.0
				split_b.bullet_type = EnemyBullet.BulletType.SPLIT
				split_b.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(split_b)
				await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.06).timeout
		# --- CURVE bullet interlude: 6 curving bullets aimed at player ---
		if player and is_instance_valid(player):
			var aim2 = global_position.direction_to(player.global_position).angle()
			for c in range(6):
				var c_angle = aim2 + (c - 2.5) * 0.2
				var curve_b = bullet_scene.instantiate() as EnemyBullet
				curve_b.global_position = global_position
				curve_b.direction = Vector2(cos(c_angle), sin(c_angle))
				curve_b.speed = 280.0
				curve_b.bullet_type = EnemyBullet.BulletType.CURVE
				curve_b.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(curve_b)
		await get_tree().create_timer(0.10).timeout


func _boss3_chrono_cage() -> void:
	# DECELERATE bullets fired outward from player position in rings, creating a
	# cage that closes in when they re-aim. Boss fires LASER shots between rings.
	# 5 rings of 20 bullets each + LASER shots from boss between rings.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for ring in range(5):
		# --- 20 DECELERATE bullets expanding outward from player position ---
		if player and is_instance_valid(player):
			var center = player.global_position
			for i in range(20):
				var angle = (TAU / 20.0) * i + ring * 0.16
				var cage_b = bullet_scene.instantiate() as EnemyBullet
				cage_b.global_position = center
				cage_b.direction = Vector2(cos(angle), sin(angle))
				cage_b.speed = 260.0 + ring * 20.0
				cage_b.bullet_type = EnemyBullet.BulletType.DECELERATE
				cage_b.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(cage_b)
		await get_tree().create_timer(0.05).timeout
		# --- 4 LASER shots from boss aimed at player between rings ---
		if player and is_instance_valid(player):
			var laser_aim = global_position.direction_to(player.global_position).angle()
			for l in range(4):
				var l_angle = laser_aim + (l - 1.5) * 0.15
				var laser = bullet_scene.instantiate() as EnemyBullet
				laser.global_position = global_position
				laser.direction = Vector2(cos(l_angle), sin(l_angle))
				laser.speed = 400.0
				laser.bullet_type = EnemyBullet.BulletType.LASER
				laser.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(laser)
		await get_tree().create_timer(0.08).timeout


func _boss3_rewind_spiral() -> void:
	# Triple SPIRAL arms that rotate, with every 10th step firing a burst of
	# HOMING bullets from screen edges aimed at player. Time rewinding effect.
	# 60 spiral steps + edge homing every 10 steps.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	var base_angle = global_position.direction_to(player.global_position).angle()
	for step in range(60):
		if not player or not is_instance_valid(player):
			break
		# --- 3 SPIRAL arms rotating outward ---
		for arm in range(3):
			var arm_offset = (TAU / 3.0) * arm
			var angle = base_angle + arm_offset + step * 0.12
			var spiral_b = bullet_scene.instantiate() as EnemyBullet
			spiral_b.global_position = global_position
			spiral_b.direction = Vector2(cos(angle), sin(angle))
			spiral_b.speed = 200.0 + step * 2.5
			spiral_b.bullet_type = EnemyBullet.BulletType.SPIRAL
			spiral_b.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(spiral_b)
		await get_tree().create_timer(0.04).timeout
		# --- Every 10th step: 4 HOMING bullets from screen edges ---
		if step % 10 == 0 and step > 0 and player and is_instance_valid(player):
			var edge_positions = [
				Vector2(randf_range(80, vp.x - 80), 15),
				Vector2(randf_range(80, vp.x - 80), vp.y - 15),
				Vector2(15, randf_range(80, vp.y - 80)),
				Vector2(vp.x - 15, randf_range(80, vp.y - 80))
			]
			for e_pos in edge_positions:
				var homing_b = bullet_scene.instantiate() as EnemyBullet
				homing_b.global_position = e_pos
				homing_b.direction = e_pos.direction_to(player.global_position)
				homing_b.speed = 280.0
				homing_b.bullet_type = EnemyBullet.BulletType.HOMING
				homing_b._homing_strength = 3.0
				homing_b._homing_duration = 0.8
				homing_b.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(homing_b)
			await get_tree().create_timer(0.02).timeout

# =============================================================================
# NONSPELL 2 - Phantom Clock (5 skills)
# =============================================================================

func _boss3_phantom_strike() -> void:
	# 4 phantom positions around the screen fire aimed bursts at the player
	# simultaneously. Each phantom fires 10 bullets in a tight aimed spread.
	# 5 rounds total; phantoms shift position each round for unpredictability.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for round_idx in range(5):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# 4 phantom positions shift each round via rotation offset
		var offset = round_idx * 0.35
		var phantom_positions: Array[Vector2] = [
			Vector2(120.0 + round_idx * 40.0, 80.0),
			Vector2(vp.x - 120.0 - round_idx * 40.0, 80.0),
			Vector2(80.0, vp.y * 0.5 + sin(offset) * 100.0),
			Vector2(vp.x - 80.0, vp.y * 0.5 - sin(offset) * 100.0)
		]
		for phantom_idx in range(4):
			var origin = phantom_positions[phantom_idx]
			var aim = origin.direction_to(p_pos).angle()
			for i in range(10):
				var spread = aim + (i - 4.5) * 0.07
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = origin
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 310.0 + i * 6.0
				bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
				get_parent().add_child(bullet)
			await get_tree().create_timer(0.03).timeout
		await get_tree().create_timer(0.12).timeout


func _boss3_clone_barrage() -> void:
	# 3 clone positions (boss + 2 mirror positions) each fire alternating
	# SINE_WAVE streams aimed at the player. 8 waves, 12 bullets per clone
	# per wave. Clones mirror the boss position for a disorienting effect.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for wave in range(8):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		var clone_positions: Array[Vector2] = [
			global_position,
			Vector2(900.0 - global_position.x, global_position.y),
			Vector2(global_position.x, 600.0 - global_position.y)
		]
		var side = 1.0 if wave % 2 == 0 else -1.0
		for clone_idx in range(3):
			var origin = clone_positions[clone_idx]
			var aim = origin.direction_to(p_pos).angle()
			for i in range(12):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = origin
				var offset_angle = aim + side * 0.25 + (i - 5.5) * 0.04
				bullet.direction = Vector2(cos(offset_angle), sin(offset_angle))
				bullet.speed = 220.0 + i * 8.0
				bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
				bullet.wave_amplitude = 30.0
				bullet.wave_frequency = 3.0
				bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(bullet)
			await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.10).timeout


func _boss3_ghost_spiral() -> void:
	# Spiral bullets from boss + HOMING ghost bullets from 4 screen corners
	# aimed at the player. 50 spiral steps with corner homing every 8 steps.
	# 3 homing bullets per corner. Creates a spiral web with homing pressure.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	var corners: Array[Vector2] = [
		Vector2(30, 30),
		Vector2(vp.x - 30, 30),
		Vector2(30, vp.y - 30),
		Vector2(vp.x - 30, vp.y - 30)
	]
	for step in range(50):
		var spiral_angle = (TAU / 50.0) * step * 3.0
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(spiral_angle), sin(spiral_angle))
		bullet.speed = 240.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
		get_parent().add_child(bullet)
		# Every 8 steps, fire 3 homing ghost bullets from each corner
		if step % 8 == 0 and player and is_instance_valid(player):
			var p_pos = player.global_position
			for corner in corners:
				for h in range(3):
					var homing_b = bullet_scene.instantiate() as EnemyBullet
					homing_b.global_position = corner
					homing_b.direction = (p_pos - corner).normalized().rotated((h - 1.0) * 0.12)
					homing_b.speed = 210.0
					homing_b.bullet_type = EnemyBullet.BulletType.HOMING
					homing_b._homing_strength = 2.5
					homing_b._homing_duration = 0.7
					homing_b.set_sprite("res://assets/sprites/bossbullut-5.png")
					get_parent().add_child(homing_b)
		await get_tree().create_timer(0.04).timeout


func _boss3_time_echo() -> void:
	# Fires an aimed fan at the player, then 0.3s later fires the same pattern
	# from a position 200px offset (the "echo"). 6 echo pairs, 15 bullets per
	# fan. The echo uses ACCELERATE bullets for a delayed-rush feel.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for pair in range(6):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- Primary fan from boss ---
		var aim = global_position.direction_to(p_pos).angle()
		for i in range(15):
			var spread = aim + (i - 7.0) * 0.09
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 300.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		# --- Echo fan from offset position (200px perpendicular to aim) ---
		var perp = Vector2(cos(aim + PI * 0.5), sin(aim + PI * 0.5))
		var echo_side = 1.0 if pair % 2 == 0 else -1.0
		var echo_origin = global_position + perp * echo_side * 200.0
		# Clamp echo origin to screen bounds
		echo_origin.x = clampf(echo_origin.x, 40.0, 860.0)
		echo_origin.y = clampf(echo_origin.y, 40.0, 560.0)
		var echo_aim = echo_origin.direction_to(p_pos).angle()
		for i in range(15):
			var spread = echo_aim + (i - 7.0) * 0.09
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = echo_origin
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.acceleration = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


func _boss3_phantom_cage() -> void:
	# Orbit bullets from 4 phantom positions around the player, all dash inward
	# after orbiting. 4 phantoms x 12 orbit bullets each. The orbiting bullets
	# form a closing cage that collapses on the player's position.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	var phantom_origins: Array[Vector2] = [
		Vector2(vp.x * 0.25, vp.y * 0.2),
		Vector2(vp.x * 0.75, vp.y * 0.2),
		Vector2(vp.x * 0.25, vp.y * 0.75),
		Vector2(vp.x * 0.75, vp.y * 0.75)
	]
	for phantom_idx in range(4):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		for i in range(12):
			var orbit_angle = (TAU / 12.0) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = p_pos + Vector2(cos(orbit_angle), sin(orbit_angle)) * 180.0
			bullet.direction = Vector2.ZERO
			bullet.speed = 0.0
			bullet.orbit_center = p_pos
			bullet.orbit_radius = 180.0
			bullet.orbit_angle = orbit_angle
			bullet.orbit_angular_speed = 3.0 + phantom_idx * 0.5
			bullet.orbit_time_left = 1.2
			bullet.dash_after_orbit = true
			bullet.dash_target = p_pos
			bullet.dash_speed = 350.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
	# --- Boss fires aimed burst while cage closes ---
	if player and is_instance_valid(player):
		var aim = global_position.direction_to(player.global_position).angle()
		for j in range(10):
			var spread = aim + (j - 4.5) * 0.12
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 280.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
	await get_tree().create_timer(0.06).timeout


# =============================================================================
# SPELL 2 - ZA WARUDO (5 skills)
# =============================================================================

func _boss3_world_freeze() -> void:
	# Massive ring of 32 DECELERATE bullets from boss -- they stop mid-screen,
	# then ALL re-aim at the player and fire. 3 waves. Between waves, fire a
	# LASER volley aimed at the player. The "time freeze" signature attack.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for wave in range(3):
		# --- 32-bullet DECELERATE ring expanding from boss ---
		for i in range(32):
			var angle = (TAU / 32.0) * i + wave * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 280.0 + wave * 30.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout
		# --- LASER volley aimed at player between waves ---
		if player and is_instance_valid(player):
			var p_pos = player.global_position
			var aim = global_position.direction_to(p_pos).angle()
			for j in range(5):
				var spread = aim + (j - 2.0) * 0.10
				var laser = bullet_scene.instantiate() as EnemyBullet
				laser.global_position = global_position
				laser.direction = Vector2(cos(spread), sin(spread))
				laser.speed = 400.0
				laser.bullet_type = EnemyBullet.BulletType.LASER
				laser.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(laser)
		await get_tree().create_timer(0.12).timeout


func _boss3_stopped_time_knives() -> void:
	# "Knife throw in stopped time" - DECELERATE bullets spawn in a circle
	# AROUND the player (radius 200), aimed outward. They stop, then the engine
	# re-aims them inward at the player. 4 rounds of 16 knives + aimed fan from
	# boss between rounds. Iconic time-stop knife circle.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for round_idx in range(4):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 16 DECELERATE knives in a circle around the player ---
		for i in range(16):
			var angle = (TAU / 16.0) * i + round_idx * 0.2
			var spawn_pos = p_pos + Vector2(cos(angle), sin(angle)) * 200.0
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			# Aimed outward initially; DECELERATE engine will stop then re-aim at player
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 220.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		# --- Aimed fan from boss between rounds ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(11):
				var spread = aim + (j - 5.0) * 0.10
				var fan_b = bullet_scene.instantiate() as EnemyBullet
				fan_b.global_position = global_position
				fan_b.direction = Vector2(cos(spread), sin(spread))
				fan_b.speed = 320.0
				fan_b.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(fan_b)
		await get_tree().create_timer(0.10).timeout


func _boss3_time_skip_assault() -> void:
	# Rapid teleport-style attack - bullets appear at random positions near the
	# player (within 300px) with DECELERATE, stop briefly, then dash at player.
	# 40 bullets total in rapid succession + HOMING from edges. Chaotic and
	# aggressive, simulating time-skip movement.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	# --- 40 DECELERATE bullets spawning near the player rapidly ---
	for i in range(40):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		var rand_angle = randf() * TAU
		var rand_dist = randf_range(120.0, 300.0)
		var spawn_pos = p_pos + Vector2(cos(rand_angle), sin(rand_angle)) * rand_dist
		spawn_pos.x = clampf(spawn_pos.x, 20.0, vp.x - 20.0)
		spawn_pos.y = clampf(spawn_pos.y, 20.0, vp.y - 20.0)
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = spawn_pos
		# Aim away from player initially; DECELERATE will stop then re-aim at player
		var away_dir = (spawn_pos - p_pos).normalized()
		bullet.direction = away_dir
		bullet.speed = 200.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout
	# --- 12 HOMING bullets from screen edges ---
	if player and is_instance_valid(player):
		var p_pos = player.global_position
		var edge_positions: Array[Vector2] = [
			Vector2(15, vp.y * 0.25), Vector2(15, vp.y * 0.75),
			Vector2(vp.x - 15, vp.y * 0.25), Vector2(vp.x - 15, vp.y * 0.75),
			Vector2(vp.x * 0.25, 15), Vector2(vp.x * 0.75, 15),
			Vector2(vp.x * 0.25, vp.y - 15), Vector2(vp.x * 0.75, vp.y - 15),
			Vector2(vp.x * 0.5, 15), Vector2(vp.x * 0.5, vp.y - 15),
			Vector2(15, vp.y * 0.5), Vector2(vp.x - 15, vp.y * 0.5)
		]
		for e in range(12):
			var homing_b = bullet_scene.instantiate() as EnemyBullet
			homing_b.global_position = edge_positions[e]
			homing_b.direction = (p_pos - edge_positions[e]).normalized()
			homing_b.speed = 230.0
			homing_b.bullet_type = EnemyBullet.BulletType.HOMING
			homing_b._homing_strength = 2.5
			homing_b._homing_duration = 0.6
			homing_b.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(homing_b)
		await get_tree().create_timer(0.04).timeout


func _boss3_road_roller() -> void:
	# Dense ACCELERATE barrage from above aimed at the player (like dropping
	# something heavy). 5 waves of 20 accelerate bullets from top, speed starts
	# slow (100) with high acceleration (250). Between waves, BOUNCE bullets
	# from sides add lateral pressure. Crushing overhead assault.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for wave in range(5):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 20 ACCELERATE bullets from top of screen aimed at player ---
		for i in range(20):
			var x_pos = p_pos.x + (i - 9.5) * 22.0 + randf_range(-10, 10)
			x_pos = clampf(x_pos, 20.0, vp.x - 20.0)
			var spawn_pos = Vector2(x_pos, randf_range(-20, 10))
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			var aim_dir = (p_pos - spawn_pos).normalized()
			bullet.direction = aim_dir.rotated(randf_range(-0.08, 0.08))
			bullet.speed = 100.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.acceleration = 250.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.05).timeout
		# --- 8 BOUNCE bullets from left/right sides between waves ---
		for side in range(2):
			var edge_x = 15.0 if side == 0 else vp.x - 15.0
			for j in range(4):
				var y_pos = 80.0 + j * 120.0 + randf_range(-20, 20)
				var bounce_b = bullet_scene.instantiate() as EnemyBullet
				bounce_b.global_position = Vector2(edge_x, y_pos)
				var aim_dir: Vector2
				if player and is_instance_valid(player):
					aim_dir = (player.global_position - bounce_b.global_position).normalized()
				else:
					aim_dir = Vector2(1.0 - side * 2.0, 0.3).normalized()
				bounce_b.direction = aim_dir.rotated(randf_range(-0.15, 0.15))
				bounce_b.speed = randf_range(280.0, 360.0)
				bounce_b.bullet_type = EnemyBullet.BulletType.BOUNCE
				bounce_b.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bounce_b)
		await get_tree().create_timer(0.10).timeout


func _boss3_time_resume() -> void:
	# Multi-source DECELERATE attack: bullets from boss + 4 edges + 4 corners,
	# ALL decelerate to stop, then ALL re-aim at the player simultaneously.
	# 80+ bullets total, then LASER sweep from boss. The ultimate time-resume
	# attack -- everything freezes, then everything moves at once.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
	# --- 20 DECELERATE bullets from boss in a wide ring ---
	for i in range(20):
		var angle = (TAU / 20.0) * i
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 260.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.04).timeout
	# --- 32 DECELERATE bullets from 4 screen edges (8 per edge) ---
	# Top edge
	for i in range(8):
		var x = (vp.x / 9.0) * (i + 1)
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = Vector2(x, -10)
		bullet.direction = (p_pos - bullet.global_position).normalized()
		bullet.speed = 280.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
	# Bottom edge
	for i in range(8):
		var x = (vp.x / 9.0) * (i + 1)
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = Vector2(x, vp.y + 10)
		bullet.direction = (p_pos - bullet.global_position).normalized()
		bullet.speed = 280.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
	# Left edge
	for i in range(8):
		var y = (vp.y / 9.0) * (i + 1)
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = Vector2(-10, y)
		bullet.direction = (p_pos - bullet.global_position).normalized()
		bullet.speed = 280.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
	# Right edge
	for i in range(8):
		var y = (vp.y / 9.0) * (i + 1)
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = Vector2(vp.x + 10, y)
		bullet.direction = (p_pos - bullet.global_position).normalized()
		bullet.speed = 280.0
		bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
		bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(bullet)
	await get_tree().create_timer(0.04).timeout
	# --- 16 DECELERATE bullets from 4 corners (4 per corner) ---
	var corners: Array[Vector2] = [
		Vector2(30, 30), Vector2(vp.x - 30, 30),
		Vector2(30, vp.y - 30), Vector2(vp.x - 30, vp.y - 30)
	]
	for corner in corners:
		for j in range(4):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = corner
			var aim_dir = (p_pos - corner).normalized().rotated((j - 1.5) * 0.12)
			bullet.direction = aim_dir
			bullet.speed = 300.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
	await get_tree().create_timer(0.06).timeout
	# --- LASER sweep from boss aimed at player ---
	if player and is_instance_valid(player):
		var aim = global_position.direction_to(player.global_position).angle()
		var sweep_start = aim - 0.6
		for step in range(20):
			var sweep_angle = sweep_start + (step / 20.0) * 1.2
			for l in range(3):
				var laser_offset = sweep_angle + (l - 1.0) * 0.04
				var laser = bullet_scene.instantiate() as EnemyBullet
				laser.global_position = global_position
				laser.direction = Vector2(cos(laser_offset), sin(laser_offset))
				laser.speed = 400.0
				laser.bullet_type = EnemyBullet.BulletType.LASER
				laser.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(laser)
			await get_tree().create_timer(0.03).timeout

# =============================================================================
# FINAL PHASE - Chronos Apocalypse (5 super skills) - Boss 3 Time/Clock Theme
# The ultimate time manipulation attacks combining ALL previous mechanics.
# =============================================================================

func _boss3_time_collapse() -> void:
	# Super multi-phase time collapse:
	# Phase 1: Dense DECELERATE ring (32 bullets) from boss that stops mid-screen.
	# Phase 2: While frozen bullets wait, fire aimed LASER sweep at player (20 steps).
	# Phase 3: All decelerate bullets re-aim and fire (engine auto-handles).
	# Phase 4: HOMING from all 4 screen edges (4 per edge).
	# Phase 5: Final aimed SPLIT burst (15 split bullets).
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: Dense DECELERATE ring - 32 bullets expanding from boss
	var aim_base = global_position.direction_to(player.global_position).angle()
	for i in range(32):
		var angle = (TAU / 32.0) * i
		var decel = bullet_scene.instantiate() as EnemyBullet
		decel.global_position = global_position
		decel.direction = Vector2(cos(angle), sin(angle))
		decel.speed = 280.0
		decel.bullet_type = EnemyBullet.BulletType.DECELERATE
		decel.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(decel)
		if i % 8 == 7:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 2: LASER sweep aimed at player - 20 laser steps rotating through player
	if not player or not is_instance_valid(player):
		return
	var sweep_center = global_position.direction_to(player.global_position).angle()
	var sweep_start = sweep_center - 0.8
	for step in range(20):
		if not is_instance_valid(player):
			break
		var sweep_angle = sweep_start + step * 0.08
		var laser = bullet_scene.instantiate() as EnemyBullet
		laser.global_position = global_position
		laser.direction = Vector2(cos(sweep_angle), sin(sweep_angle))
		laser.speed = 380.0
		laser.bullet_type = EnemyBullet.BulletType.LASER
		laser.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(laser)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 3: Decelerate bullets have auto re-aimed by engine. No code needed.
	# Phase 4: HOMING from all 4 screen edges - 4 per edge = 16 total
	if not player or not is_instance_valid(player):
		return
	var edge_positions = []
	for k in range(4):
		edge_positions.append(Vector2(vp.x * (0.2 + k * 0.2), 15.0))        # Top
		edge_positions.append(Vector2(vp.x * (0.2 + k * 0.2), vp.y - 15.0)) # Bottom
		edge_positions.append(Vector2(15.0, vp.y * (0.2 + k * 0.2)))         # Left
		edge_positions.append(Vector2(vp.x - 15.0, vp.y * (0.2 + k * 0.2))) # Right
	for idx in range(edge_positions.size()):
		var spawn = edge_positions[idx] as Vector2
		var hb = bullet_scene.instantiate() as EnemyBullet
		hb.global_position = spawn
		hb.direction = spawn.direction_to(player.global_position)
		hb.speed = 260.0
		hb.bullet_type = EnemyBullet.BulletType.HOMING
		hb._homing_strength = 2.8
		hb._homing_duration = 0.7
		hb.set_sprite("res://assets/sprites/bossbullut-9.png")
		get_parent().add_child(hb)
		if idx % 4 == 3:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 5: Final aimed SPLIT burst - 15 split bullets at player
	if not player or not is_instance_valid(player):
		return
	var final_aim = global_position.direction_to(player.global_position).angle()
	for i in range(15):
		var spread = final_aim + (i - 7.0) * 0.10
		var split_b = bullet_scene.instantiate() as EnemyBullet
		split_b.global_position = global_position
		split_b.direction = Vector2(cos(spread), sin(spread))
		split_b.speed = 300.0 + i * 6.0
		split_b.bullet_type = EnemyBullet.BulletType.SPLIT
		split_b.set_sprite("res://assets/sprites/bossbullut-3.png")
		get_parent().add_child(split_b)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout


func _boss3_chronos_wrath() -> void:
	# Super multi-phase chronos wrath:
	# Phase 1: 4 phantom positions fire aimed fans at player (10 bullets each).
	# Phase 2: ACCELERATE rain from top aimed at player (25 bullets).
	# Phase 3: Orbit cage around player (20 orbit bullets, dash inward).
	# Phase 4: Triple SPIRAL arms with CURVE interludes.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: 4 phantom clock positions fire aimed fans at player
	var phantoms = [
		Vector2(vp.x * 0.2, vp.y * 0.2),
		Vector2(vp.x * 0.8, vp.y * 0.2),
		Vector2(vp.x * 0.2, vp.y * 0.8),
		Vector2(vp.x * 0.8, vp.y * 0.8),
	]
	for p_idx in range(phantoms.size()):
		if not player or not is_instance_valid(player):
			break
		var phantom_pos = phantoms[p_idx] as Vector2
		var aim = phantom_pos.direction_to(player.global_position).angle()
		for i in range(10):
			var spread = aim + (i - 4.5) * 0.12
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = phantom_pos
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 300.0 + i * 5.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 2: ACCELERATE rain from top aimed at player - 25 bullets
	if not player or not is_instance_valid(player):
		return
	var target_pos = player.global_position
	for i in range(25):
		var x_pos = target_pos.x + randf_range(-300, 300)
		x_pos = clampf(x_pos, 25, vp.x - 25)
		var rain_b = bullet_scene.instantiate() as EnemyBullet
		rain_b.global_position = Vector2(x_pos, 20.0)
		rain_b.direction = (target_pos - rain_b.global_position).normalized().rotated(randf_range(-0.08, 0.08))
		rain_b.speed = 240.0
		rain_b.bullet_type = EnemyBullet.BulletType.ACCELERATE
		rain_b.acceleration = 320.0
		rain_b.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(rain_b)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 3: Orbit cage around player - 20 bullets orbit then dash inward
	if not player or not is_instance_valid(player):
		return
	var cage_center = player.global_position
	for i in range(20):
		var angle = (TAU / 20.0) * i
		var spawn_pos = cage_center + Vector2(cos(angle), sin(angle)) * 130.0
		var orb = bullet_scene.instantiate() as EnemyBullet
		orb.global_position = spawn_pos
		orb.direction = Vector2.ZERO
		orb.speed = 0.0
		orb.orbit_center = cage_center
		orb.orbit_radius = 130.0
		orb.orbit_angle = angle
		orb.orbit_angular_speed = 5.5
		orb.orbit_time_left = 1.0
		orb.dash_after_orbit = true
		orb.dash_target = cage_center
		orb.dash_speed = 380.0
		orb.set_sprite("res://assets/sprites/bossbullut-9.png")
		get_parent().add_child(orb)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 4: Triple SPIRAL arms with CURVE interludes
	if not player or not is_instance_valid(player):
		return
	for step in range(60):
		if not is_instance_valid(player):
			break
		# 3 spiral arms
		for arm in range(3):
			var base_angle = step * 0.14 + arm * (TAU / 3.0)
			var spiral_b = bullet_scene.instantiate() as EnemyBullet
			spiral_b.global_position = global_position
			spiral_b.direction = Vector2(cos(base_angle), sin(base_angle))
			spiral_b.speed = 220.0 + step * 0.8
			spiral_b.bullet_type = EnemyBullet.BulletType.SPIRAL
			spiral_b.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(spiral_b)
		# Every 10 steps: CURVE interlude aimed at player
		if step % 10 == 0 and player and is_instance_valid(player):
			var curve_aim = global_position.direction_to(player.global_position).angle()
			for c in range(4):
				var c_angle = curve_aim + (c - 1.5) * 0.20
				var curve_b = bullet_scene.instantiate() as EnemyBullet
				curve_b.global_position = global_position
				curve_b.direction = Vector2(cos(c_angle), sin(c_angle))
				curve_b.speed = 280.0
				curve_b.bullet_type = EnemyBullet.BulletType.CURVE
				curve_b.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(curve_b)
		await get_tree().create_timer(0.03).timeout


func _boss3_eternity_end() -> void:
	# Super multi-phase eternity end:
	# Phase 1: 3 clone positions fire SINE_WAVE streams at player (15 per clone).
	# Phase 2: BOUNCE bullets from all 4 corners (8 per corner).
	# Phase 3: DECELERATE minefield scattered around player.
	# Phase 4: LASER cross from boss aimed at player.
	# Phase 5: Massive aimed fan burst (30 bullets).
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: 3 clone positions fire SINE_WAVE streams at player
	var clones = [
		Vector2(vp.x * 0.25, vp.y * 0.15),
		Vector2(vp.x * 0.50, vp.y * 0.10),
		Vector2(vp.x * 0.75, vp.y * 0.15),
	]
	for clone_idx in range(clones.size()):
		if not player or not is_instance_valid(player):
			break
		var clone_pos = clones[clone_idx] as Vector2
		var aim = clone_pos.direction_to(player.global_position).angle()
		for i in range(15):
			var wobble = sin(i * 0.7) * 0.10
			var angle = aim + wobble
			var sine_b = bullet_scene.instantiate() as EnemyBullet
			sine_b.global_position = clone_pos
			sine_b.direction = Vector2(cos(angle), sin(angle))
			sine_b.speed = 260.0 + i * 5.0
			sine_b.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			sine_b.wave_amplitude = 35.0
			sine_b.wave_frequency = 4.0
			sine_b.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(sine_b)
			if i % 5 == 4:
				await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 2: BOUNCE bullets from all 4 corners - 8 per corner
	if not player or not is_instance_valid(player):
		return
	var corners = [
		Vector2(20.0, 20.0), Vector2(vp.x - 20.0, 20.0),
		Vector2(20.0, vp.y - 20.0), Vector2(vp.x - 20.0, vp.y - 20.0),
	]
	for corner in corners:
		var to_player = (corner as Vector2).direction_to(player.global_position)
		for j in range(8):
			var spread = to_player.rotated((j - 3.5) * 0.12)
			var bounce_b = bullet_scene.instantiate() as EnemyBullet
			bounce_b.global_position = corner as Vector2
			bounce_b.direction = spread
			bounce_b.speed = 320.0
			bounce_b.bullet_type = EnemyBullet.BulletType.BOUNCE
			bounce_b.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bounce_b)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 3: DECELERATE minefield scattered around player position
	if not player or not is_instance_valid(player):
		return
	var mine_center = player.global_position
	for i in range(24):
		var rand_offset = Vector2(randf_range(-200, 200), randf_range(-180, 180))
		var mine_pos = mine_center + rand_offset
		mine_pos.x = clampf(mine_pos.x, 30, vp.x - 30)
		mine_pos.y = clampf(mine_pos.y, 30, vp.y - 30)
		var mine_dir = mine_pos.direction_to(player.global_position)
		var mine_b = bullet_scene.instantiate() as EnemyBullet
		mine_b.global_position = global_position
		mine_b.direction = (mine_pos - global_position).normalized()
		mine_b.speed = 350.0
		mine_b.bullet_type = EnemyBullet.BulletType.DECELERATE
		mine_b.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(mine_b)
		if i % 6 == 5:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 4: LASER cross from boss aimed at player - 4 beams, 10 bullets each
	if not player or not is_instance_valid(player):
		return
	var cross_aim = global_position.direction_to(player.global_position).angle()
	for beam in range(4):
		var beam_angle = cross_aim + beam * (PI / 2.0)
		for i in range(10):
			var laser_b = bullet_scene.instantiate() as EnemyBullet
			laser_b.global_position = global_position
			laser_b.direction = Vector2(cos(beam_angle), sin(beam_angle))
			laser_b.speed = 280.0 + i * 15.0
			laser_b.bullet_type = EnemyBullet.BulletType.LASER
			laser_b.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser_b)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 5: Massive aimed fan burst - 30 bullets at player
	if not player or not is_instance_valid(player):
		return
	var fan_aim = global_position.direction_to(player.global_position).angle()
	for i in range(30):
		var spread = fan_aim + (i - 14.5) * 0.07
		var fan_b = bullet_scene.instantiate() as EnemyBullet
		fan_b.global_position = global_position
		fan_b.direction = Vector2(cos(spread), sin(spread))
		fan_b.speed = 340.0 + i * 3.0
		fan_b.set_sprite("res://assets/sprites/bossbullut-9.png")
		get_parent().add_child(fan_b)
		if i % 6 == 5:
			await get_tree().create_timer(0.02).timeout


func _boss3_temporal_singularity() -> void:
	# Super multi-phase temporal singularity:
	# Phase 1: Converging DECELERATE bullets from 8 screen-edge positions toward player.
	# Phase 2: HOMING bullets from boss (20 bullets).
	# Phase 3: SPLIT streams from 4 phantom positions aimed at player.
	# Phase 4: Dense ACCELERATE barrage from above.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: Converging DECELERATE from 8 screen-edge positions toward player
	var edge_spawns = [
		Vector2(vp.x * 0.15, 15.0), Vector2(vp.x * 0.50, 15.0),
		Vector2(vp.x * 0.85, 15.0), Vector2(vp.x - 15.0, vp.y * 0.50),
		Vector2(vp.x * 0.85, vp.y - 15.0), Vector2(vp.x * 0.50, vp.y - 15.0),
		Vector2(vp.x * 0.15, vp.y - 15.0), Vector2(15.0, vp.y * 0.50),
	]
	for e_idx in range(edge_spawns.size()):
		if not player or not is_instance_valid(player):
			break
		var spawn = edge_spawns[e_idx] as Vector2
		var to_player = spawn.direction_to(player.global_position)
		for i in range(5):
			var spread = to_player.rotated((i - 2.0) * 0.10)
			var decel_b = bullet_scene.instantiate() as EnemyBullet
			decel_b.global_position = spawn
			decel_b.direction = spread
			decel_b.speed = 300.0
			decel_b.bullet_type = EnemyBullet.BulletType.DECELERATE
			decel_b.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(decel_b)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 2: HOMING bullets from boss - 20 bullets fanning out then homing
	if not player or not is_instance_valid(player):
		return
	var homing_aim = global_position.direction_to(player.global_position).angle()
	for i in range(20):
		var spread = homing_aim + (i - 9.5) * 0.16
		var homing_b = bullet_scene.instantiate() as EnemyBullet
		homing_b.global_position = global_position
		homing_b.direction = Vector2(cos(spread), sin(spread))
		homing_b.speed = 240.0
		homing_b.bullet_type = EnemyBullet.BulletType.HOMING
		homing_b._homing_strength = 3.0
		homing_b._homing_duration = 0.8
		homing_b.set_sprite("res://assets/sprites/bossbullut-9.png")
		get_parent().add_child(homing_b)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 3: SPLIT streams from 4 phantom positions aimed at player
	if not player or not is_instance_valid(player):
		return
	var phantom_positions = [
		Vector2(vp.x * 0.20, vp.y * 0.25),
		Vector2(vp.x * 0.80, vp.y * 0.25),
		Vector2(vp.x * 0.35, vp.y * 0.10),
		Vector2(vp.x * 0.65, vp.y * 0.10),
	]
	for ph_idx in range(phantom_positions.size()):
		if not player or not is_instance_valid(player):
			break
		var ph_pos = phantom_positions[ph_idx] as Vector2
		var aim = ph_pos.direction_to(player.global_position).angle()
		for i in range(8):
			var wobble = sin(i * 0.9) * 0.08
			var angle = aim + wobble + (i - 3.5) * 0.06
			var split_b = bullet_scene.instantiate() as EnemyBullet
			split_b.global_position = ph_pos
			split_b.direction = Vector2(cos(angle), sin(angle))
			split_b.speed = 280.0 + i * 8.0
			split_b.bullet_type = EnemyBullet.BulletType.SPLIT
			split_b.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(split_b)
			if i % 4 == 3:
				await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 4: Dense ACCELERATE barrage from above aimed at player
	if not player or not is_instance_valid(player):
		return
	var barrage_target = player.global_position
	for i in range(30):
		var x_pos = barrage_target.x + randf_range(-320, 320)
		x_pos = clampf(x_pos, 20, vp.x - 20)
		var accel_b = bullet_scene.instantiate() as EnemyBullet
		accel_b.global_position = Vector2(x_pos, 15.0)
		accel_b.direction = (barrage_target - accel_b.global_position).normalized().rotated(randf_range(-0.06, 0.06))
		accel_b.speed = 220.0
		accel_b.bullet_type = EnemyBullet.BulletType.ACCELERATE
		accel_b.acceleration = 350.0
		accel_b.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(accel_b)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout


func _boss3_omega_timeline() -> void:
	# THE ULTIMATE ATTACK - Omega Timeline:
	# Phase 1: Rain + aimed fan simultaneously.
	# Phase 2: DECELERATE ring trap around player + LASER spiral from boss.
	# Phase 3: Phantom clone barrage from 4 positions.
	# Phase 4: Orbit cage that dashes at player.
	# Phase 5: Everything at once - aimed burst + edge homing + spiral + decelerate traps.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: Rain from top + aimed fan simultaneously
	var target_p1 = player.global_position
	# Rain: 20 bullets from top
	for i in range(20):
		var x_pos = target_p1.x + randf_range(-280, 280)
		x_pos = clampf(x_pos, 25, vp.x - 25)
		var rain_b = bullet_scene.instantiate() as EnemyBullet
		rain_b.global_position = Vector2(x_pos, 15.0)
		rain_b.direction = (target_p1 - rain_b.global_position).normalized().rotated(randf_range(-0.08, 0.08))
		rain_b.speed = randf_range(280.0, 380.0)
		rain_b.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(rain_b)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout
	# Simultaneous aimed fan: 18 bullets from boss
	if player and is_instance_valid(player):
		var fan_aim = global_position.direction_to(player.global_position).angle()
		for i in range(18):
			var spread = fan_aim + (i - 8.5) * 0.09
			var fan_b = bullet_scene.instantiate() as EnemyBullet
			fan_b.global_position = global_position
			fan_b.direction = Vector2(cos(spread), sin(spread))
			fan_b.speed = 320.0 + i * 4.0
			fan_b.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(fan_b)

	await get_tree().create_timer(0.05).timeout

	# Phase 2: DECELERATE ring trap around player + LASER spiral from boss
	if not player or not is_instance_valid(player):
		return
	var trap_center = player.global_position
	# DECELERATE ring: 24 bullets converging on player
	for i in range(24):
		var angle = (TAU / 24.0) * i
		var spawn_pos = trap_center + Vector2(cos(angle), sin(angle)) * 220.0
		var inward = spawn_pos.direction_to(trap_center)
		var decel_b = bullet_scene.instantiate() as EnemyBullet
		decel_b.global_position = spawn_pos
		decel_b.direction = inward
		decel_b.speed = 260.0
		decel_b.bullet_type = EnemyBullet.BulletType.DECELERATE
		decel_b.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(decel_b)
		if i % 6 == 5:
			await get_tree().create_timer(0.02).timeout
	# LASER spiral from boss: 5 arms, 20 steps
	for step in range(20):
		for arm in range(5):
			var angle = step * 0.16 + arm * (TAU / 5.0)
			var laser_b = bullet_scene.instantiate() as EnemyBullet
			laser_b.global_position = global_position
			laser_b.direction = Vector2(cos(angle), sin(angle))
			laser_b.speed = 250.0 + step * 1.5
			laser_b.bullet_type = EnemyBullet.BulletType.LASER
			laser_b.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser_b)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 3: Phantom clone barrage from 4 positions aimed at player
	if not player or not is_instance_valid(player):
		return
	var clone_positions = [
		Vector2(vp.x * 0.15, vp.y * 0.20),
		Vector2(vp.x * 0.85, vp.y * 0.20),
		Vector2(vp.x * 0.30, vp.y * 0.10),
		Vector2(vp.x * 0.70, vp.y * 0.10),
	]
	for cl_idx in range(clone_positions.size()):
		if not player or not is_instance_valid(player):
			break
		var cl_pos = clone_positions[cl_idx] as Vector2
		var aim = cl_pos.direction_to(player.global_position).angle()
		for i in range(12):
			var spread = aim + (i - 5.5) * 0.11
			var cl_b = bullet_scene.instantiate() as EnemyBullet
			cl_b.global_position = cl_pos
			cl_b.direction = Vector2(cos(spread), sin(spread))
			cl_b.speed = 310.0 + i * 5.0
			cl_b.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(cl_b)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 4: Orbit cage that dashes at player
	if not player or not is_instance_valid(player):
		return
	var cage_center = player.global_position
	for i in range(24):
		var angle = (TAU / 24.0) * i
		var spawn_pos = cage_center + Vector2(cos(angle), sin(angle)) * 150.0
		var orb = bullet_scene.instantiate() as EnemyBullet
		orb.global_position = spawn_pos
		orb.direction = Vector2.ZERO
		orb.speed = 0.0
		orb.orbit_center = cage_center
		orb.orbit_radius = 150.0
		orb.orbit_angle = angle
		orb.orbit_angular_speed = 6.0
		orb.orbit_time_left = 0.8
		orb.dash_after_orbit = true
		orb.dash_target = cage_center
		orb.dash_speed = 400.0
		orb.set_sprite("res://assets/sprites/bossbullut-9.png")
		get_parent().add_child(orb)
		if i % 6 == 5:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 5: EVERYTHING AT ONCE - aimed burst + edge homing + spiral + decelerate traps
	if not player or not is_instance_valid(player):
		return

	# Sub-A: Aimed burst from boss - 20 bullets
	var burst_aim = global_position.direction_to(player.global_position).angle()
	for i in range(20):
		var spread = burst_aim + (i - 9.5) * 0.08
		var burst_b = bullet_scene.instantiate() as EnemyBullet
		burst_b.global_position = global_position
		burst_b.direction = Vector2(cos(spread), sin(spread))
		burst_b.speed = 360.0 + i * 3.0
		burst_b.set_sprite("res://assets/sprites/bossbullut-3.png")
		get_parent().add_child(burst_b)

	await get_tree().create_timer(0.02).timeout

	# Sub-B: Edge HOMING - 3 per edge = 12 total
	if not player or not is_instance_valid(player):
		return
	var homing_spawns = []
	for k in range(3):
		homing_spawns.append(Vector2(vp.x * (0.25 + k * 0.25), 15.0))
		homing_spawns.append(Vector2(vp.x * (0.25 + k * 0.25), vp.y - 15.0))
		homing_spawns.append(Vector2(15.0, vp.y * (0.25 + k * 0.25)))
		homing_spawns.append(Vector2(vp.x - 15.0, vp.y * (0.25 + k * 0.25)))
	for h_spawn in homing_spawns:
		var hb = bullet_scene.instantiate() as EnemyBullet
		hb.global_position = h_spawn as Vector2
		hb.direction = (h_spawn as Vector2).direction_to(player.global_position)
		hb.speed = 280.0
		hb.bullet_type = EnemyBullet.BulletType.HOMING
		hb._homing_strength = 2.5
		hb._homing_duration = 0.6
		hb.set_sprite("res://assets/sprites/bossbullut-9.png")
		get_parent().add_child(hb)

	await get_tree().create_timer(0.02).timeout

	# Sub-C: Triple spiral arms from boss
	for step in range(30):
		if not is_instance_valid(player):
			break
		for arm in range(3):
			var angle = step * 0.18 + arm * (TAU / 3.0)
			var sp_b = bullet_scene.instantiate() as EnemyBullet
			sp_b.global_position = global_position
			sp_b.direction = Vector2(cos(angle), sin(angle))
			sp_b.speed = 240.0 + step * 1.0
			sp_b.bullet_type = EnemyBullet.BulletType.SPIRAL
			sp_b.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(sp_b)
		await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.02).timeout

	# Sub-D: DECELERATE traps scattered around player
	if not player or not is_instance_valid(player):
		return
	var trap_pos = player.global_position
	for i in range(16):
		var rand_off = Vector2(randf_range(-250, 250), randf_range(-200, 200))
		var dest = trap_pos + rand_off
		dest.x = clampf(dest.x, 25, vp.x - 25)
		dest.y = clampf(dest.y, 25, vp.y - 25)
		var trap_b = bullet_scene.instantiate() as EnemyBullet
		trap_b.global_position = global_position
		trap_b.direction = (dest - global_position).normalized()
		trap_b.speed = 380.0
		trap_b.bullet_type = EnemyBullet.BulletType.DECELERATE
		trap_b.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(trap_b)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout

# ============================================================================

# ============================================================================
# Boss 4 New Skills - Chaos/Glitch/Digital Theme (25 skills)
# ============================================================================

# ============================================================================
# Boss 4 - Digital Chaos (Nonspell 1) -- 5 skills
# Theme: Chaos/Glitch/Digital - chaotic random bullets, unpredictable attacks
# ============================================================================

func _boss4_static_spray() -> void:
	# Pure digital chaos: rapid random-angle bullets from boss. Every 5th bullet
	# is HOMING aimed at player. 80 total bullets fired rapidly (0.02s each).
	# Random speeds 200-380. Mix of normal + homing for unpredictable pressure.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for i in range(80):
		if not is_inside_tree():
			break
		var is_homing = (i % 5 == 4)
		if is_homing and player and is_instance_valid(player):
			# --- Every 5th bullet: HOMING aimed at player ---
			var aim = global_position.direction_to(player.global_position).angle()
			var homing_b = bullet_scene.instantiate() as EnemyBullet
			homing_b.global_position = global_position
			homing_b.direction = Vector2(cos(aim), sin(aim))
			homing_b.speed = randf_range(240.0, 340.0)
			homing_b.bullet_type = EnemyBullet.BulletType.HOMING
			homing_b._homing_strength = 2.5
			homing_b._homing_duration = 0.6
			homing_b.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(homing_b)
		else:
			# --- Normal bullet at random angle with random speed ---
			var rand_angle = randf_range(0, TAU)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(rand_angle), sin(rand_angle))
			bullet.speed = randf_range(200.0, 380.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.02).timeout


func _boss4_glitch_scatter() -> void:
	# 6 waves of "glitched" bursts: each wave fires 15 bullets at random angles
	# from boss, PLUS 8 aimed bullets at player. Bullets alternate between
	# ACCELERATE and normal types. Fast 0.03s between bullets, 0.08s between waves.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for wave in range(6):
		if not is_inside_tree():
			break
		# --- 15 random-angle "glitch" bullets from boss ---
		for i in range(15):
			var rand_angle = randf_range(0, TAU)
			var glitch = bullet_scene.instantiate() as EnemyBullet
			glitch.global_position = global_position + Vector2(randf_range(-15, 15), randf_range(-15, 15))
			glitch.direction = Vector2(cos(rand_angle), sin(rand_angle))
			glitch.speed = randf_range(220.0, 370.0)
			if i % 2 == 0:
				glitch.bullet_type = EnemyBullet.BulletType.ACCELERATE
				glitch.acceleration = 200.0
				glitch.set_sprite("res://assets/sprites/bossbullut-14.png")
			else:
				glitch.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(glitch)
			await get_tree().create_timer(0.03).timeout
		# --- 8 aimed bullets at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(8):
				var spread = aim + (j - 3.5) * 0.12
				var aimed = bullet_scene.instantiate() as EnemyBullet
				aimed.global_position = global_position
				aimed.direction = Vector2(cos(spread), sin(spread))
				aimed.speed = 320.0 + j * 10.0
				if j % 2 == 0:
					aimed.bullet_type = EnemyBullet.BulletType.ACCELERATE
					aimed.acceleration = 250.0
					aimed.set_sprite("res://assets/sprites/bossbullut-14.png")
				else:
					aimed.set_sprite("res://assets/sprites/bossbullut-4.png")
				get_parent().add_child(aimed)
		await get_tree().create_timer(0.08).timeout


func _boss4_pixel_rain() -> void:
	# Dense rain from ALL 4 screen edges converging on player position.
	# 4 edges x 10 bullets per edge x 5 waves = 200 bullets total.
	# Each bullet aimed at player with slight random spread (+-0.15 rad).
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for wave in range(5):
		if not is_inside_tree():
			break
		var target_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- Top edge: 10 bullets raining down toward player ---
		for i in range(10):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(randf_range(30, vp.x - 30), randf_range(-15, 10))
			bullet.direction = (target_pos - bullet.global_position).normalized().rotated(randf_range(-0.15, 0.15))
			bullet.speed = randf_range(240.0, 360.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(bullet)
		# --- Bottom edge: 10 bullets rising toward player ---
		for i in range(10):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(randf_range(30, vp.x - 30), vp.y + randf_range(-10, 15))
			bullet.direction = (target_pos - bullet.global_position).normalized().rotated(randf_range(-0.15, 0.15))
			bullet.speed = randf_range(240.0, 360.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(bullet)
		# --- Left edge: 10 bullets moving right toward player ---
		for i in range(10):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(randf_range(-15, 10), randf_range(30, vp.y - 30))
			bullet.direction = (target_pos - bullet.global_position).normalized().rotated(randf_range(-0.15, 0.15))
			bullet.speed = randf_range(240.0, 360.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-4.png")
			get_parent().add_child(bullet)
		# --- Right edge: 10 bullets moving left toward player ---
		for i in range(10):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(vp.x + randf_range(-10, 15), randf_range(30, vp.y - 30))
			bullet.direction = (target_pos - bullet.global_position).normalized().rotated(randf_range(-0.15, 0.15))
			bullet.speed = randf_range(240.0, 360.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-4.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


func _boss4_data_corruption() -> void:
	# Bullets spawn at random positions across the entire screen, then fire
	# TOWARD player. 50 bullets total, spawning rapidly. Every 3rd bullet uses
	# DECELERATE type for lingering threat. Creates chaotic screen-wide danger.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for i in range(50):
		if not is_inside_tree():
			break
		var spawn_pos = Vector2(randf_range(30, vp.x - 30), randf_range(30, vp.y - 30))
		var target_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = spawn_pos
		bullet.direction = (target_pos - spawn_pos).normalized().rotated(randf_range(-0.08, 0.08))
		bullet.speed = randf_range(220.0, 360.0)
		if i % 3 == 2:
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
		else:
			bullet.set_sprite("res://assets/sprites/bossbullut-8.png")
		get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout


func _boss4_noise_burst() -> void:
	# Alternating pattern: "noise" phase fires 20 random-direction SINE_WAVE
	# bullets for wobbly chaotic paths, then "signal" phase fires 12-bullet
	# aimed fan at player. 6 cycles of noise/signal alternation.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for cycle in range(6):
		if not is_inside_tree():
			break
		# --- NOISE phase: 20 random-direction SINE_WAVE bullets ---
		for i in range(20):
			var rand_angle = randf_range(0, TAU)
			var noise_b = bullet_scene.instantiate() as EnemyBullet
			noise_b.global_position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
			noise_b.direction = Vector2(cos(rand_angle), sin(rand_angle))
			noise_b.speed = randf_range(200.0, 340.0)
			noise_b.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			noise_b.wave_amplitude = randf_range(20.0, 45.0)
			noise_b.wave_frequency = randf_range(2.5, 5.0)
			noise_b.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(noise_b)
		await get_tree().create_timer(0.06).timeout
		# --- SIGNAL phase: 12-bullet aimed fan at player ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(12):
				var spread = aim + (j - 5.5) * 0.10
				var signal_b = bullet_scene.instantiate() as EnemyBullet
				signal_b.global_position = global_position
				signal_b.direction = Vector2(cos(spread), sin(spread))
				signal_b.speed = 340.0 + j * 8.0
				signal_b.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(signal_b)
		await get_tree().create_timer(0.10).timeout


# ============================================================================
# Boss 4 - Narrow Escape (Spell 1) -- 5 skills
# Theme: Walls/corridors forcing player through narrow gaps, expand/contract
# ============================================================================

func _boss4_closing_walls() -> void:
	# Two walls of ACCELERATE bullets close in from left and right sides, leaving
	# a narrow gap aligned with player's Y position. 6 waves. Each wall = 15
	# bullets in a vertical line, gap = 3 bullet-widths. Between walls, boss fires
	# aimed burst at player.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for wave in range(6):
		if not is_inside_tree():
			break
		var gap_y = 350.0
		if player and is_instance_valid(player):
			gap_y = player.global_position.y
		var gap_half = 40.0  # 3 bullet-widths gap
		# --- Left wall: 15 bullets in vertical line moving right ---
		for i in range(15):
			var y_pos = 30 + i * ((vp.y - 60) / 15.0)
			if abs(y_pos - gap_y) < gap_half:
				continue  # Leave gap for player
			var wall_b = bullet_scene.instantiate() as EnemyBullet
			wall_b.global_position = Vector2(20, y_pos)
			wall_b.direction = Vector2(1, 0)
			wall_b.speed = 180.0 + wave * 20.0
			wall_b.bullet_type = EnemyBullet.BulletType.ACCELERATE
			wall_b.acceleration = 300.0
			wall_b.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(wall_b)
		# --- Right wall: 15 bullets in vertical line moving left ---
		for i in range(15):
			var y_pos = 30 + i * ((vp.y - 60) / 15.0)
			if abs(y_pos - gap_y) < gap_half:
				continue  # Leave gap for player
			var wall_b = bullet_scene.instantiate() as EnemyBullet
			wall_b.global_position = Vector2(vp.x - 20, y_pos)
			wall_b.direction = Vector2(-1, 0)
			wall_b.speed = 180.0 + wave * 20.0
			wall_b.bullet_type = EnemyBullet.BulletType.ACCELERATE
			wall_b.acceleration = 300.0
			wall_b.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(wall_b)
		await get_tree().create_timer(0.06).timeout
		# --- Boss fires aimed burst between walls ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(8):
				var spread = aim + (j - 3.5) * 0.14
				var burst = bullet_scene.instantiate() as EnemyBullet
				burst.global_position = global_position
				burst.direction = Vector2(cos(spread), sin(spread))
				burst.speed = 300.0 + j * 12.0
				burst.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(burst)
		await get_tree().create_timer(0.12).timeout


func _boss4_corridor_sweep() -> void:
	# Horizontal lines of bullets sweep from top to bottom with a gap that tracks
	# player X position. 8 sweep lines, 20 bullets per line with a 3-bullet gap
	# near player. Lines move downward. Between sweeps, HOMING from boss.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for sweep in range(8):
		if not is_inside_tree():
			break
		var gap_x = 450.0
		if player and is_instance_valid(player):
			gap_x = player.global_position.x
		var gap_half = 45.0  # 3-bullet gap width
		var y_start = 30 + sweep * ((vp.y - 60) / 8.0)
		# --- Horizontal line of 20 bullets with gap near player X ---
		for i in range(20):
			var x_pos = 20 + i * ((vp.x - 40) / 20.0)
			if abs(x_pos - gap_x) < gap_half:
				continue  # Leave gap for player
			var line_b = bullet_scene.instantiate() as EnemyBullet
			line_b.global_position = Vector2(x_pos, y_start)
			line_b.direction = Vector2(0, 1)
			line_b.speed = 200.0 + sweep * 15.0
			line_b.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(line_b)
		await get_tree().create_timer(0.04).timeout
		# --- HOMING bullets from boss between sweeps ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for h in range(3):
				var homing_b = bullet_scene.instantiate() as EnemyBullet
				homing_b.global_position = global_position
				homing_b.direction = Vector2(cos(aim + (h - 1) * 0.2), sin(aim + (h - 1) * 0.2))
				homing_b.speed = 280.0
				homing_b.bullet_type = EnemyBullet.BulletType.HOMING
				homing_b._homing_strength = 2.2
				homing_b._homing_duration = 0.7
				homing_b.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(homing_b)
		await get_tree().create_timer(0.10).timeout


func _boss4_shrinking_ring() -> void:
	# Rings of bullets expand outward from boss, then a SECOND set of DECELERATE
	# rings contracts inward toward player. Creates expanding/contracting pressure.
	# 5 cycles: 20-bullet expand ring + 16-bullet contract ring.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for cycle in range(5):
		if not is_inside_tree():
			break
		# --- Expanding ring: 20 bullets outward from boss ---
		for i in range(20):
			var angle = (TAU / 20.0) * i + cycle * 0.16
			var expand_b = bullet_scene.instantiate() as EnemyBullet
			expand_b.global_position = global_position
			expand_b.direction = Vector2(cos(angle), sin(angle))
			expand_b.speed = 260.0 + cycle * 20.0
			expand_b.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(expand_b)
		await get_tree().create_timer(0.08).timeout
		# --- Contracting ring: 16 DECELERATE bullets inward toward player ---
		if player and is_instance_valid(player):
			var target = player.global_position
			var ring_radius = 280.0
			for j in range(16):
				var angle = (TAU / 16.0) * j + cycle * 0.2
				var spawn_pos = target + Vector2(cos(angle), sin(angle)) * ring_radius
				var contract_b = bullet_scene.instantiate() as EnemyBullet
				contract_b.global_position = spawn_pos
				contract_b.direction = (target - spawn_pos).normalized()
				contract_b.speed = 320.0
				contract_b.bullet_type = EnemyBullet.BulletType.DECELERATE
				contract_b.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(contract_b)
		await get_tree().create_timer(0.12).timeout


func _boss4_cage_squeeze() -> void:
	# Orbit bullets form a large ring around player (radius 250), then the ring
	# SHRINKS via multiple spawns at decreasing radii. After shrinking, all dash
	# at player. 3 rounds of 16 orbit bullets each.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for round_i in range(3):
		if not is_inside_tree():
			break
		if not player or not is_instance_valid(player):
			break
		var target = player.global_position
		# --- Spawn 16 orbit bullets at decreasing radii (cage shrinks) ---
		var radii = [250.0, 210.0, 170.0, 130.0, 90.0]
		for r_idx in range(radii.size()):
			if not is_inside_tree():
				break
			var radius = radii[r_idx]
			for i in range(16):
				var angle = (TAU / 16.0) * i + round_i * 0.3
				var cage_b = bullet_scene.instantiate() as EnemyBullet
				cage_b.global_position = target + Vector2(cos(angle), sin(angle)) * radius
				cage_b.direction = Vector2.ZERO
				cage_b.speed = 0.0
				cage_b.orbit_center = target
				cage_b.orbit_radius = radius
				cage_b.orbit_angle = angle
				cage_b.orbit_angular_speed = 1.8 + r_idx * 0.3
				cage_b.orbit_time_left = 1.2 - r_idx * 0.15
				cage_b.dash_after_orbit = true
				cage_b.dash_target = target
				cage_b.dash_speed = 380.0
				cage_b.set_sprite("res://assets/sprites/bossbullut-4.png")
				get_parent().add_child(cage_b)
			await get_tree().create_timer(0.08).timeout
		await get_tree().create_timer(0.15).timeout


func _boss4_pixel_maze() -> void:
	# Grid pattern of bullets with narrow corridors - fire bullets in a grid
	# pattern (rows and columns) but leave gaps that shift each wave. 5 waves,
	# each wave = grid of ~40 bullets with 2-3 gap positions near player.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	var cols = 10
	var rows = 6
	for wave in range(5):
		if not is_inside_tree():
			break
		var gap_x = 5
		var gap_y = 3
		if player and is_instance_valid(player):
			gap_x = int(clamp(player.global_position.x / (vp.x / cols), 1, cols - 2))
			gap_y = int(clamp(player.global_position.y / (vp.y / rows), 1, rows - 2))
		# --- Grid of bullets with gaps near player position ---
		for r in range(rows):
			for c in range(cols):
				# Leave 2-3 gap positions near player
				if abs(c - gap_x) <= 1 and abs(r - gap_y) <= 1:
					continue  # Gap near player
				var x_pos = (c + 0.5) * (vp.x / cols)
				var y_pos = (r + 0.5) * (vp.y / rows)
				var grid_b = bullet_scene.instantiate() as EnemyBullet
				grid_b.global_position = Vector2(x_pos, y_pos) + Vector2(randf_range(-5, 5), randf_range(-5, 5))
				# Bullets drift slowly toward player
				var target_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
				grid_b.direction = (target_pos - grid_b.global_position).normalized()
				grid_b.speed = 120.0 + wave * 25.0
				if (r + c) % 3 == 0:
					grid_b.bullet_type = EnemyBullet.BulletType.ACCELERATE
					grid_b.acceleration = 180.0
					grid_b.set_sprite("res://assets/sprites/bossbullut-14.png")
				else:
					grid_b.set_sprite("res://assets/sprites/bossbullut-8.png")
				get_parent().add_child(grid_b)
		await get_tree().create_timer(0.04).timeout
		# --- Boss fires aimed burst through the gaps ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(5):
				var spread = aim + (j - 2) * 0.08
				var aimed = bullet_scene.instantiate() as EnemyBullet
				aimed.global_position = global_position
				aimed.direction = Vector2(cos(spread), sin(spread))
				aimed.speed = 350.0
				aimed.bullet_type = EnemyBullet.BulletType.HOMING
				aimed._homing_strength = 3.0
				aimed._homing_duration = 0.5
				aimed.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(aimed)
		await get_tree().create_timer(0.12).timeout

# =============================================================================
# NONSPELL 2 - Size Shift (5 skills)
# =============================================================================

func _boss4_pulse_expand() -> void:
	# Rings that expand outward from boss in pulses. 8 pulses of 24-bullet rings
	# alternating fast (300) and slow (150). Between pulses, 6 aimed bullets at
	# the player. Creates a breathing expand/contract rhythm.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for pulse in range(8):
		var ring_speed = 300.0 if pulse % 2 == 0 else 150.0
		var angle_offset = pulse * 0.13
		# --- 24-bullet expanding ring ---
		for i in range(24):
			var angle = (TAU / 24.0) * i + angle_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = ring_speed
			bullet.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout
		# --- 6 aimed bullets at player between pulses ---
		if player and is_instance_valid(player):
			var p_pos = player.global_position
			var aim = global_position.direction_to(p_pos).angle()
			for j in range(6):
				var spread = aim + (j - 2.5) * 0.10
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 280.0
				bullet.set_sprite("res://assets/sprites/bossbullut-4.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


func _boss4_breathing_cage() -> void:
	# Orbit bullets around the player that "breathe" -- inner ring at radius 120,
	# outer ring at radius 200. Inner ring dashes at player first, then outer.
	# 2 layers x 16 bullets each x 3 rounds. Layered cage that contracts inward.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for round_idx in range(3):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- Inner ring: radius 120, 16 bullets, orbits then dashes first ---
		for i in range(16):
			var orbit_angle = (TAU / 16.0) * i + round_idx * 0.3
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = p_pos + Vector2(cos(orbit_angle), sin(orbit_angle)) * 120.0
			bullet.direction = Vector2.ZERO
			bullet.speed = 0.0
			bullet.orbit_center = p_pos
			bullet.orbit_radius = 120.0
			bullet.orbit_angle = orbit_angle
			bullet.orbit_angular_speed = 3.5
			bullet.orbit_time_left = 0.9
			bullet.dash_after_orbit = true
			bullet.dash_target = p_pos
			bullet.dash_speed = 340.0
			bullet.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		# --- Outer ring: radius 200, 16 bullets, orbits longer then dashes ---
		for i in range(16):
			var orbit_angle = (TAU / 16.0) * i + round_idx * 0.3 + 0.1
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = p_pos + Vector2(cos(orbit_angle), sin(orbit_angle)) * 200.0
			bullet.direction = Vector2.ZERO
			bullet.speed = 0.0
			bullet.orbit_center = p_pos
			bullet.orbit_radius = 200.0
			bullet.orbit_angle = orbit_angle
			bullet.orbit_angular_speed = 2.5
			bullet.orbit_time_left = 1.4
			bullet.dash_after_orbit = true
			bullet.dash_target = p_pos
			bullet.dash_speed = 320.0
			bullet.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout


func _boss4_zoom_barrage() -> void:
	# Bullets fired at varying speeds creating a "zoom" cascade -- slow wave (150),
	# medium (250), fast (380), all aimed at the player. Cascading arrival pattern
	# forces constant movement. 5 zoom cycles x 10 bullets per speed tier.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for cycle in range(5):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		var aim = global_position.direction_to(p_pos).angle()
		# --- Slow tier: 10 bullets at speed 150 ---
		for i in range(10):
			var spread = aim + (i - 4.5) * 0.08
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 150.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout
		# --- Medium tier: 10 bullets at speed 250 ---
		for i in range(10):
			var spread = aim + (i - 4.5) * 0.06
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 250.0
			bullet.set_sprite("res://assets/sprites/bossbullut-4.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout
		# --- Fast tier: 10 bullets at speed 380 ---
		for i in range(10):
			var spread = aim + (i - 4.5) * 0.04
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 380.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


func _boss4_inflate_burst() -> void:
	# DECELERATE bullets expand outward in a ring, stop, then a SECOND ring of
	# faster bullets passes through the frozen ring aimed at the player. Creates
	# "inflating then popping" effect. 4 rounds: 20 decelerate ring + 12 aimed
	# fast burst through the frozen field.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for round_idx in range(4):
		var angle_offset = round_idx * 0.18
		# --- 20-bullet DECELERATE ring expanding from boss ---
		for i in range(20):
			var angle = (TAU / 20.0) * i + angle_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 260.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
		# --- 12 fast aimed bullets that burst through the frozen ring ---
		if player and is_instance_valid(player):
			var p_pos = player.global_position
			var aim = global_position.direction_to(p_pos).angle()
			for j in range(12):
				var spread = aim + (j - 5.5) * 0.09
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 360.0
				bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


func _boss4_scale_spiral() -> void:
	# Spiral arms that start tight then expand wider. 3 spiral arms, 60 steps.
	# Speed increases from 120 to 300 over the steps. Every 15 steps, fire HOMING
	# bullets from screen edges at the player. Growing spiral with homing pressure.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	var edge_positions: Array[Vector2] = [
		Vector2(15, vp.y * 0.3), Vector2(15, vp.y * 0.7),
		Vector2(vp.x - 15, vp.y * 0.3), Vector2(vp.x - 15, vp.y * 0.7)
	]
	for step in range(60):
		var t = float(step) / 59.0
		var spiral_speed = lerpf(120.0, 300.0, t)
		# --- 3 spiral arms ---
		for arm in range(3):
			var base_angle = (TAU / 3.0) * arm
			var spiral_angle = base_angle + step * 0.18
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spiral_angle), sin(spiral_angle))
			bullet.speed = spiral_speed
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			bullet.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(bullet)
		# --- Every 15 steps: HOMING from screen edges ---
		if step % 15 == 0 and player and is_instance_valid(player):
			var p_pos = player.global_position
			for edge_pos in edge_positions:
				var homing_b = bullet_scene.instantiate() as EnemyBullet
				homing_b.global_position = edge_pos
				homing_b.direction = (p_pos - edge_pos).normalized()
				homing_b.speed = 220.0
				homing_b.bullet_type = EnemyBullet.BulletType.HOMING
				homing_b._homing_strength = 2.5
				homing_b._homing_duration = 0.7
				homing_b.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(homing_b)
		await get_tree().create_timer(0.04).timeout


# =============================================================================
# SPELL 2 - System Override (5 skills)
# =============================================================================

func _boss4_firewall_breach() -> void:
	# Dense walls of bullets from left and right with narrow gaps, plus HOMING
	# "virus" bullets from boss aimed at the player. 5 wall pairs. Each wall =
	# 18 bullets vertical line, gap near player Y. 4 homing per wall pair.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for wall_idx in range(5):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		var gap_y = p_pos.y
		var gap_half = 38.0
		# --- Left wall: 18 bullets moving right ---
		for i in range(18):
			var y_pos = (vp.y / 19.0) * (i + 1)
			if abs(y_pos - gap_y) < gap_half:
				continue
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(10, y_pos)
			bullet.direction = Vector2(1, 0)
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.02).timeout
		# --- Right wall: 18 bullets moving left ---
		for i in range(18):
			var y_pos = (vp.y / 19.0) * (i + 1)
			if abs(y_pos - gap_y) < gap_half:
				continue
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(vp.x - 10, y_pos)
			bullet.direction = Vector2(-1, 0)
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout
		# --- 4 HOMING "virus" bullets from boss ---
		if player and is_instance_valid(player):
			for h in range(4):
				var homing_b = bullet_scene.instantiate() as EnemyBullet
				homing_b.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
				homing_b.direction = global_position.direction_to(p_pos)
				homing_b.speed = 200.0
				homing_b.bullet_type = EnemyBullet.BulletType.HOMING
				homing_b._homing_strength = 2.8
				homing_b._homing_duration = 0.7
				homing_b.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(homing_b)
		await get_tree().create_timer(0.12).timeout


func _boss4_overflow_cascade() -> void:
	# SPLIT bullets fired in aimed streams at the player from 4 positions (boss +
	# 3 screen edges). Splits create cascading chaos. 4 sources x 8 split bullets
	# x 3 rounds. Between rounds, LASER from boss.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	var sources: Array[Vector2] = [
		global_position,
		Vector2(15, vp.y * 0.5),
		Vector2(vp.x - 15, vp.y * 0.5),
		Vector2(vp.x * 0.5, 15)
	]
	for round_idx in range(3):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 4 sources x 8 SPLIT bullets each ---
		for src in sources:
			var aim = (p_pos - src).normalized()
			for i in range(8):
				var spread_angle = aim.angle() + (i - 3.5) * 0.12
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = src
				bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
				bullet.speed = 240.0
				bullet.bullet_type = EnemyBullet.BulletType.SPLIT
				bullet.set_sprite("res://assets/sprites/bossbullut-4.png")
				get_parent().add_child(bullet)
			await get_tree().create_timer(0.03).timeout
		await get_tree().create_timer(0.06).timeout
		# --- LASER from boss between rounds ---
		if player and is_instance_valid(player):
			var laser_aim = global_position.direction_to(player.global_position)
			var laser = bullet_scene.instantiate() as EnemyBullet
			laser.global_position = global_position
			laser.direction = laser_aim
			laser.speed = 350.0
			laser.bullet_type = EnemyBullet.BulletType.LASER
			laser.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser)
		await get_tree().create_timer(0.10).timeout


func _boss4_virus_swarm() -> void:
	# 40 HOMING bullets spawn from random screen-edge positions, all tracking the
	# player. Strength 2.0, duration 0.8s. Between swarms, fire DECELERATE ring
	# traps around the player. 3 swarm+trap cycles.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for cycle in range(3):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 40 HOMING bullets from random screen edges ---
		for i in range(40):
			var edge = randi() % 4
			var spawn_pos: Vector2
			match edge:
				0: spawn_pos = Vector2(randf_range(0, vp.x), 5)
				1: spawn_pos = Vector2(randf_range(0, vp.x), vp.y - 5)
				2: spawn_pos = Vector2(5, randf_range(0, vp.y))
				3: spawn_pos = Vector2(vp.x - 5, randf_range(0, vp.y))
			var homing_b = bullet_scene.instantiate() as EnemyBullet
			homing_b.global_position = spawn_pos
			homing_b.direction = (p_pos - spawn_pos).normalized()
			homing_b.speed = 210.0
			homing_b.bullet_type = EnemyBullet.BulletType.HOMING
			homing_b._homing_strength = 2.0
			homing_b._homing_duration = 0.8
			homing_b.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(homing_b)
			if i % 5 == 4:
				await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.06).timeout
		# --- DECELERATE ring trap around the player ---
		if player and is_instance_valid(player):
			p_pos = player.global_position
			for j in range(16):
				var angle = (TAU / 16.0) * j
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = p_pos + Vector2(cos(angle), sin(angle)) * 180.0
				bullet.direction = Vector2(cos(angle + PI), sin(angle + PI))
				bullet.speed = 200.0
				bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
				bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout


func _boss4_kernel_panic() -> void:
	# Multi-source chaos -- random bullets from boss + aimed fans from 4 corners +
	# BOUNCE bullets from edges. All happening simultaneously in 5 waves.
	# 15 random + 8 aimed per corner + 6 bounce per wave.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	var corners: Array[Vector2] = [
		Vector2(20, 20), Vector2(vp.x - 20, 20),
		Vector2(20, vp.y - 20), Vector2(vp.x - 20, vp.y - 20)
	]
	for wave in range(5):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 15 random bullets from boss ---
		for i in range(15):
			var rand_angle = randf_range(0, TAU)
			var rand_speed = randf_range(200.0, 380.0)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position + Vector2(randf_range(-15, 15), randf_range(-15, 15))
			bullet.direction = Vector2(cos(rand_angle), sin(rand_angle))
			bullet.speed = rand_speed
			bullet.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout
		# --- 8 aimed bullets per corner (4 corners) ---
		for corner in corners:
			var aim = (p_pos - corner).normalized().angle()
			for j in range(8):
				var spread = aim + (j - 3.5) * 0.10
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = corner
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 280.0
				bullet.set_sprite("res://assets/sprites/bossbullut-4.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout
		# --- 6 BOUNCE bullets from random edges ---
		for k in range(6):
			var edge = k % 4
			var spawn_pos: Vector2
			match edge:
				0: spawn_pos = Vector2(randf_range(50, vp.x - 50), 10)
				1: spawn_pos = Vector2(randf_range(50, vp.x - 50), vp.y - 10)
				2: spawn_pos = Vector2(10, randf_range(50, vp.y - 50))
				3: spawn_pos = Vector2(vp.x - 10, randf_range(50, vp.y - 50))
			var bounce_aim = (p_pos - spawn_pos).normalized()
			var bounce_b = bullet_scene.instantiate() as EnemyBullet
			bounce_b.global_position = spawn_pos
			bounce_b.direction = bounce_aim
			bounce_b.speed = 250.0
			bounce_b.bullet_type = EnemyBullet.BulletType.BOUNCE
			bounce_b.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(bounce_b)
		await get_tree().create_timer(0.10).timeout


func _boss4_blue_screen() -> void:
	# Screen-filling attack -- horizontal lines sweep down like a blue screen.
	# Each line = 25 bullets with narrow gap at player X. 10 lines sweeping down.
	# After sweep, DECELERATE ring from player position + HOMING from boss.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	# --- 10 horizontal lines sweeping downward ---
	for line_idx in range(10):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		var gap_x = p_pos.x
		var gap_half = 35.0
		var y_pos = 20.0 + line_idx * ((vp.y - 40.0) / 9.0)
		for i in range(25):
			var x_pos = (vp.x / 26.0) * (i + 1)
			if abs(x_pos - gap_x) < gap_half:
				continue
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, y_pos)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 240.0
			bullet.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
	await get_tree().create_timer(0.06).timeout
	# --- DECELERATE ring from player position ---
	if player and is_instance_valid(player):
		var p_pos = player.global_position
		for j in range(20):
			var angle = (TAU / 20.0) * j
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = p_pos
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 280.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
	await get_tree().create_timer(0.04).timeout
	# --- HOMING barrage from boss ---
	if player and is_instance_valid(player):
		var p_pos = player.global_position
		for k in range(8):
			var homing_b = bullet_scene.instantiate() as EnemyBullet
			homing_b.global_position = global_position + Vector2(randf_range(-25, 25), randf_range(-25, 25))
			homing_b.direction = global_position.direction_to(p_pos)
			homing_b.speed = 230.0
			homing_b.bullet_type = EnemyBullet.BulletType.HOMING
			homing_b._homing_strength = 2.5
			homing_b._homing_duration = 0.6
			homing_b.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(homing_b)
			await get_tree().create_timer(0.03).timeout

# =============================================================================
# FINAL PHASE - Total Meltdown (5 super skills) - Boss 4 Chaos/Glitch/Digital
# The ultimate digital catastrophe combining ALL mechanics: chaos spray,
# corridor walls, size shifts, glitch patterns, and digital mayhem.
# =============================================================================

func _boss4_system_meltdown() -> void:
	# Super multi-phase system meltdown:
	# Phase 1: Random chaos spray (40 bullets, random angles, mixed speeds 200-380).
	# Phase 2: Closing walls from left+right with narrow gap at player Y (15 per wall).
	# Phase 3: DECELERATE ring expanding from boss (24 bullets).
	# Phase 4: HOMING swarm from all 4 edges (4 per edge).
	# Phase 5: Aimed SPLIT burst at player (12 split bullets).
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: Random chaos spray - 40 bullets at random angles and mixed speeds
	for i in range(40):
		var chaos_angle = randf_range(0.0, TAU)
		var chaos_b = bullet_scene.instantiate() as EnemyBullet
		chaos_b.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		chaos_b.direction = Vector2(cos(chaos_angle), sin(chaos_angle))
		chaos_b.speed = randf_range(200.0, 380.0)
		var sprite_pool = ["bossbullut-4.png", "bossbullut-8.png", "bossbullut-14.png"]
		chaos_b.set_sprite("res://assets/sprites/" + sprite_pool[i % 3])
		get_parent().add_child(chaos_b)
		if i % 8 == 7:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 2: Closing walls from left+right with narrow gap at player Y
	if not player or not is_instance_valid(player):
		return
	var gap_y = player.global_position.y
	var gap_half = 40.0
	# Left wall - 15 bullets
	for i in range(15):
		var y_pos = (vp.y / 15.0) * (i + 0.5)
		if absf(y_pos - gap_y) < gap_half:
			continue
		var wall_b = bullet_scene.instantiate() as EnemyBullet
		wall_b.global_position = Vector2(15.0, y_pos)
		wall_b.direction = Vector2.RIGHT
		wall_b.speed = 320.0
		wall_b.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(wall_b)
	# Right wall - 15 bullets
	for i in range(15):
		var y_pos = (vp.y / 15.0) * (i + 0.5)
		if absf(y_pos - gap_y) < gap_half:
			continue
		var wall_b = bullet_scene.instantiate() as EnemyBullet
		wall_b.global_position = Vector2(vp.x - 15.0, y_pos)
		wall_b.direction = Vector2.LEFT
		wall_b.speed = 320.0
		wall_b.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(wall_b)

	await get_tree().create_timer(0.05).timeout

	# Phase 3: DECELERATE ring expanding from boss - 24 bullets
	for i in range(24):
		var angle = (TAU / 24.0) * i
		var decel_b = bullet_scene.instantiate() as EnemyBullet
		decel_b.global_position = global_position
		decel_b.direction = Vector2(cos(angle), sin(angle))
		decel_b.speed = 300.0
		decel_b.bullet_type = EnemyBullet.BulletType.DECELERATE
		decel_b.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(decel_b)
		if i % 8 == 7:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 4: HOMING swarm from all 4 edges - 4 per edge = 16 total
	if not player or not is_instance_valid(player):
		return
	var edge_spawns = []
	for k in range(4):
		edge_spawns.append(Vector2(vp.x * (0.15 + k * 0.23), 15.0))
		edge_spawns.append(Vector2(vp.x * (0.15 + k * 0.23), vp.y - 15.0))
		edge_spawns.append(Vector2(15.0, vp.y * (0.15 + k * 0.23)))
		edge_spawns.append(Vector2(vp.x - 15.0, vp.y * (0.15 + k * 0.23)))
	for idx in range(edge_spawns.size()):
		var spawn = edge_spawns[idx] as Vector2
		var hb = bullet_scene.instantiate() as EnemyBullet
		hb.global_position = spawn
		hb.direction = spawn.direction_to(player.global_position)
		hb.speed = 270.0
		hb.bullet_type = EnemyBullet.BulletType.HOMING
		hb._homing_strength = 2.8
		hb._homing_duration = 0.7
		hb.set_sprite("res://assets/sprites/bossbullut-14.png")
		get_parent().add_child(hb)
		if idx % 4 == 3:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 5: Aimed SPLIT burst at player - 12 split bullets
	if not player or not is_instance_valid(player):
		return
	var split_aim = global_position.direction_to(player.global_position).angle()
	for i in range(12):
		var spread = split_aim + (i - 5.5) * 0.12
		var split_b = bullet_scene.instantiate() as EnemyBullet
		split_b.global_position = global_position
		split_b.direction = Vector2(cos(spread), sin(spread))
		split_b.speed = 310.0 + i * 7.0
		split_b.bullet_type = EnemyBullet.BulletType.SPLIT
		split_b.set_sprite("res://assets/sprites/bossbullut-8.png")
		get_parent().add_child(split_b)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout


func _boss4_digital_apocalypse() -> void:
	# Super multi-phase digital apocalypse:
	# Phase 1: Horizontal sweep lines top-to-bottom with gaps at player X (8 lines x 20 bullets).
	# Phase 2: Expanding/contracting orbit cage around player (20 orbit bullets, dash inward).
	# Phase 3: LASER cross from boss aimed at player (4 beams x 8 bullets).
	# Phase 4: Dense aimed fan burst (25 bullets).
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: Horizontal sweep lines top-to-bottom with gaps at player X
	for line_idx in range(8):
		if not player or not is_instance_valid(player):
			break
		var line_y = 40.0 + line_idx * (vp.y - 80.0) / 7.0
		var gap_x = player.global_position.x
		var gap_width = 50.0
		for b_idx in range(20):
			var x_pos = (vp.x / 20.0) * (b_idx + 0.5)
			if absf(x_pos - gap_x) < gap_width:
				continue
			var sweep_b = bullet_scene.instantiate() as EnemyBullet
			sweep_b.global_position = Vector2(x_pos, line_y)
			sweep_b.direction = Vector2(0, 1).rotated(randf_range(-0.05, 0.05))
			sweep_b.speed = 280.0 + randf_range(-30.0, 30.0)
			sweep_b.set_sprite("res://assets/sprites/bossbullut-4.png")
			get_parent().add_child(sweep_b)
		await get_tree().create_timer(0.04).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 2: Expanding/contracting orbit cage around player - 20 orbit bullets
	if not player or not is_instance_valid(player):
		return
	var cage_center = player.global_position
	for i in range(20):
		var angle = (TAU / 20.0) * i
		var spawn_pos = cage_center + Vector2(cos(angle), sin(angle)) * 140.0
		var orb = bullet_scene.instantiate() as EnemyBullet
		orb.global_position = spawn_pos
		orb.direction = Vector2.ZERO
		orb.speed = 0.0
		orb.orbit_center = cage_center
		orb.orbit_radius = 140.0
		orb.orbit_angle = angle
		orb.orbit_angular_speed = 6.0
		orb.orbit_time_left = 0.9
		orb.dash_after_orbit = true
		orb.dash_target = cage_center
		orb.dash_speed = 390.0
		orb.set_sprite("res://assets/sprites/bossbullut-14.png")
		get_parent().add_child(orb)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 3: LASER cross from boss aimed at player - 4 beams x 8 bullets
	if not player or not is_instance_valid(player):
		return
	var cross_aim = global_position.direction_to(player.global_position).angle()
	for beam in range(4):
		var beam_angle = cross_aim + beam * (PI / 2.0)
		for i in range(8):
			var laser_b = bullet_scene.instantiate() as EnemyBullet
			laser_b.global_position = global_position
			laser_b.direction = Vector2(cos(beam_angle), sin(beam_angle))
			laser_b.speed = 300.0 + i * 18.0
			laser_b.bullet_type = EnemyBullet.BulletType.LASER
			laser_b.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser_b)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 4: Dense aimed fan burst - 25 bullets at player
	if not player or not is_instance_valid(player):
		return
	var fan_aim = global_position.direction_to(player.global_position).angle()
	for i in range(25):
		var spread = fan_aim + (i - 12.0) * 0.08
		var fan_b = bullet_scene.instantiate() as EnemyBullet
		fan_b.global_position = global_position
		fan_b.direction = Vector2(cos(spread), sin(spread))
		fan_b.speed = 340.0 + i * 4.0
		fan_b.set_sprite("res://assets/sprites/bossbullut-8.png")
		get_parent().add_child(fan_b)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout


func _boss4_matrix_shatter() -> void:
	# Super multi-phase matrix shatter:
	# Phase 1: Grid pattern with shifting gaps (30 grid bullets).
	# Phase 2: ACCELERATE rain from top aimed at player (20 bullets).
	# Phase 3: BOUNCE bullets from all 4 corners (6 per corner).
	# Phase 4: SINE_WAVE streams from 3 positions aimed at player (10 per position).
	# Phase 5: Final DECELERATE minefield around player (20 bullets).
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: Grid pattern with shifting gaps - 30 bullets
	var gap_col = randi_range(1, 4)
	var gap_row = randi_range(1, 4)
	var grid_idx = 0
	for row in range(5):
		for col in range(6):
			if col == gap_col or row == gap_row:
				continue
			if grid_idx >= 30:
				break
			var gx = 80.0 + col * (vp.x - 160.0) / 5.0
			var gy = 50.0 + row * (vp.y - 100.0) / 4.0
			var grid_b = bullet_scene.instantiate() as EnemyBullet
			grid_b.global_position = Vector2(gx, gy)
			grid_b.direction = Vector2(gx, gy).direction_to(player.global_position)
			grid_b.speed = 260.0
			grid_b.set_sprite("res://assets/sprites/bossbullut-4.png")
			get_parent().add_child(grid_b)
			grid_idx += 1
		if row % 2 == 1:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 2: ACCELERATE rain from top aimed at player - 20 bullets
	if not player or not is_instance_valid(player):
		return
	for i in range(20):
		var x_pos = randf_range(50.0, vp.x - 50.0)
		var rain_origin = Vector2(x_pos, 15.0)
		var rain_b = bullet_scene.instantiate() as EnemyBullet
		rain_b.global_position = rain_origin
		rain_b.direction = rain_origin.direction_to(player.global_position)
		rain_b.speed = 220.0
		rain_b.bullet_type = EnemyBullet.BulletType.ACCELERATE
		rain_b.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(rain_b)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 3: BOUNCE bullets from all 4 corners - 6 per corner = 24 total
	var corners = [
		Vector2(20.0, 20.0), Vector2(vp.x - 20.0, 20.0),
		Vector2(20.0, vp.y - 20.0), Vector2(vp.x - 20.0, vp.y - 20.0)
	]
	for c_idx in range(corners.size()):
		if not player or not is_instance_valid(player):
			break
		var corner = corners[c_idx]
		var aim_dir = corner.direction_to(player.global_position).angle()
		for i in range(6):
			var b_angle = aim_dir + (i - 2.5) * 0.15
			var bounce_b = bullet_scene.instantiate() as EnemyBullet
			bounce_b.global_position = corner
			bounce_b.direction = Vector2(cos(b_angle), sin(b_angle))
			bounce_b.speed = 290.0 + i * 12.0
			bounce_b.bullet_type = EnemyBullet.BulletType.BOUNCE
			bounce_b.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bounce_b)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 4: SINE_WAVE streams from 3 positions aimed at player - 10 per position
	if not player or not is_instance_valid(player):
		return
	var sine_origins = [
		Vector2(vp.x * 0.2, 20.0),
		Vector2(vp.x * 0.5, 20.0),
		Vector2(vp.x * 0.8, 20.0)
	]
	for s_idx in range(sine_origins.size()):
		var origin = sine_origins[s_idx]
		var aim = origin.direction_to(player.global_position).angle()
		for i in range(10):
			var sine_b = bullet_scene.instantiate() as EnemyBullet
			sine_b.global_position = origin
			sine_b.direction = Vector2(cos(aim), sin(aim))
			sine_b.speed = 260.0 + i * 10.0
			sine_b.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			sine_b.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(sine_b)
			if i % 5 == 4:
				await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 5: Final DECELERATE minefield around player - 20 bullets
	if not player or not is_instance_valid(player):
		return
	var mine_center = player.global_position
	for i in range(20):
		var mine_angle = (TAU / 20.0) * i
		var mine_radius = randf_range(60.0, 160.0)
		var mine_pos = mine_center + Vector2(cos(mine_angle), sin(mine_angle)) * mine_radius
		var mine_b = bullet_scene.instantiate() as EnemyBullet
		mine_b.global_position = mine_pos
		mine_b.direction = mine_pos.direction_to(mine_center)
		mine_b.speed = 240.0
		mine_b.bullet_type = EnemyBullet.BulletType.DECELERATE
		mine_b.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(mine_b)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout


func _boss4_total_corruption() -> void:
	# Super multi-phase total corruption:
	# Phase 1: 50 random-position spawns across screen, all fire at player.
	# Phase 2: Closing walls from all 4 sides with tiny gaps.
	# Phase 3: Triple SPIRAL arms from boss.
	# Phase 4: HOMING from boss (16) + edge homing (12).
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: 50 random-position spawns across screen, all fire at player
	for i in range(50):
		if not player or not is_instance_valid(player):
			break
		var rx = randf_range(40.0, vp.x - 40.0)
		var ry = randf_range(40.0, vp.y - 40.0)
		var spawn_pos = Vector2(rx, ry)
		var rnd_b = bullet_scene.instantiate() as EnemyBullet
		rnd_b.global_position = spawn_pos
		rnd_b.direction = spawn_pos.direction_to(player.global_position)
		if i % 3 == 0:
			rnd_b.speed = 240.0
			rnd_b.bullet_type = EnemyBullet.BulletType.DECELERATE
			rnd_b.set_sprite("res://assets/sprites/bossbullut-10.png")
		else:
			rnd_b.speed = randf_range(260.0, 360.0)
			rnd_b.set_sprite("res://assets/sprites/bossbullut-4.png")
		get_parent().add_child(rnd_b)
		if i % 10 == 9:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 2: Closing walls from all 4 sides with tiny gaps
	if not player or not is_instance_valid(player):
		return
	var gap_pos = player.global_position
	var tiny_gap = 35.0
	# Top wall
	for i in range(14):
		var x_pos = (vp.x / 14.0) * (i + 0.5)
		if absf(x_pos - gap_pos.x) < tiny_gap:
			continue
		var tw = bullet_scene.instantiate() as EnemyBullet
		tw.global_position = Vector2(x_pos, 15.0)
		tw.direction = Vector2.DOWN
		tw.speed = 310.0
		tw.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(tw)
	# Bottom wall
	for i in range(14):
		var x_pos = (vp.x / 14.0) * (i + 0.5)
		if absf(x_pos - gap_pos.x) < tiny_gap:
			continue
		var bw = bullet_scene.instantiate() as EnemyBullet
		bw.global_position = Vector2(x_pos, vp.y - 15.0)
		bw.direction = Vector2.UP
		bw.speed = 310.0
		bw.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(bw)
	await get_tree().create_timer(0.02).timeout
	# Left wall
	for i in range(12):
		var y_pos = (vp.y / 12.0) * (i + 0.5)
		if absf(y_pos - gap_pos.y) < tiny_gap:
			continue
		var lw = bullet_scene.instantiate() as EnemyBullet
		lw.global_position = Vector2(15.0, y_pos)
		lw.direction = Vector2.RIGHT
		lw.speed = 310.0
		lw.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(lw)
	# Right wall
	for i in range(12):
		var y_pos = (vp.y / 12.0) * (i + 0.5)
		if absf(y_pos - gap_pos.y) < tiny_gap:
			continue
		var rw = bullet_scene.instantiate() as EnemyBullet
		rw.global_position = Vector2(vp.x - 15.0, y_pos)
		rw.direction = Vector2.LEFT
		rw.speed = 310.0
		rw.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(rw)

	await get_tree().create_timer(0.06).timeout

	# Phase 3: Triple SPIRAL arms from boss
	for arm in range(3):
		var arm_offset = (TAU / 3.0) * arm
		for i in range(10):
			var spiral_angle = arm_offset + i * 0.35
			var sp_b = bullet_scene.instantiate() as EnemyBullet
			sp_b.global_position = global_position
			sp_b.direction = Vector2(cos(spiral_angle), sin(spiral_angle))
			sp_b.speed = 280.0 + i * 12.0
			sp_b.bullet_type = EnemyBullet.BulletType.SPIRAL
			sp_b.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(sp_b)
			if i % 5 == 4:
				await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 4: HOMING from boss (16) + edge homing (12)
	if not player or not is_instance_valid(player):
		return
	# Boss homing - 16 bullets
	for i in range(16):
		var h_angle = (TAU / 16.0) * i
		var hb = bullet_scene.instantiate() as EnemyBullet
		hb.global_position = global_position
		hb.direction = Vector2(cos(h_angle), sin(h_angle))
		hb.speed = 250.0
		hb.bullet_type = EnemyBullet.BulletType.HOMING
		hb._homing_strength = 3.0
		hb._homing_duration = 0.8
		hb.set_sprite("res://assets/sprites/bossbullut-14.png")
		get_parent().add_child(hb)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout
	await get_tree().create_timer(0.03).timeout
	# Edge homing - 12 bullets from random edges
	for i in range(12):
		var edge_pos: Vector2
		var edge_pick = randi_range(0, 3)
		match edge_pick:
			0: edge_pos = Vector2(randf_range(40.0, vp.x - 40.0), 15.0)
			1: edge_pos = Vector2(randf_range(40.0, vp.x - 40.0), vp.y - 15.0)
			2: edge_pos = Vector2(15.0, randf_range(40.0, vp.y - 40.0))
			3: edge_pos = Vector2(vp.x - 15.0, randf_range(40.0, vp.y - 40.0))
		var eh = bullet_scene.instantiate() as EnemyBullet
		eh.global_position = edge_pos
		eh.direction = edge_pos.direction_to(player.global_position)
		eh.speed = 260.0
		eh.bullet_type = EnemyBullet.BulletType.HOMING
		eh._homing_strength = 2.5
		eh._homing_duration = 0.6
		eh.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(eh)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout


func _boss4_final_shutdown() -> void:
	# THE ULTIMATE super attack - Final Shutdown:
	# Phase 1: Chaos spray + aimed fan simultaneously.
	# Phase 2: Walls closing from left+right + rain from top.
	# Phase 3: Expanding ring + contracting DECELERATE ring.
	# Phase 4: SPLIT streams from 4 positions + BOUNCE from corners.
	# Phase 5: Everything at once - random spray + aimed burst + HOMING + LASER + orbit cage.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: Chaos spray + aimed fan simultaneously
	var aim_angle = global_position.direction_to(player.global_position).angle()
	for i in range(30):
		# Chaos spray bullet
		var chaos_a = randf_range(0.0, TAU)
		var cb = bullet_scene.instantiate() as EnemyBullet
		cb.global_position = global_position + Vector2(randf_range(-15, 15), randf_range(-15, 15))
		cb.direction = Vector2(cos(chaos_a), sin(chaos_a))
		cb.speed = randf_range(220.0, 370.0)
		cb.set_sprite("res://assets/sprites/bossbullut-4.png")
		get_parent().add_child(cb)
		# Aimed fan bullet (interleaved)
		if i < 20:
			var fan_a = aim_angle + (i - 10.0) * 0.09
			var fb = bullet_scene.instantiate() as EnemyBullet
			fb.global_position = global_position
			fb.direction = Vector2(cos(fan_a), sin(fan_a))
			fb.speed = 330.0 + i * 5.0
			fb.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(fb)
		if i % 6 == 5:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 2: Walls closing from left+right + rain from top
	if not player or not is_instance_valid(player):
		return
	var wall_gap_y = player.global_position.y
	var rain_gap_x = player.global_position.x
	# Left wall
	for i in range(12):
		var y_pos = (vp.y / 12.0) * (i + 0.5)
		if absf(y_pos - wall_gap_y) < 38.0:
			continue
		var lw = bullet_scene.instantiate() as EnemyBullet
		lw.global_position = Vector2(15.0, y_pos)
		lw.direction = Vector2.RIGHT
		lw.speed = 330.0
		lw.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(lw)
	# Right wall
	for i in range(12):
		var y_pos = (vp.y / 12.0) * (i + 0.5)
		if absf(y_pos - wall_gap_y) < 38.0:
			continue
		var rw = bullet_scene.instantiate() as EnemyBullet
		rw.global_position = Vector2(vp.x - 15.0, y_pos)
		rw.direction = Vector2.LEFT
		rw.speed = 330.0
		rw.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(rw)
	await get_tree().create_timer(0.02).timeout
	# Rain from top
	for i in range(16):
		var rx = (vp.x / 16.0) * (i + 0.5)
		if absf(rx - rain_gap_x) < 42.0:
			continue
		var rain_b = bullet_scene.instantiate() as EnemyBullet
		rain_b.global_position = Vector2(rx, 15.0)
		rain_b.direction = Vector2.DOWN
		rain_b.speed = 300.0
		rain_b.set_sprite("res://assets/sprites/bossbullut-5.png")
		get_parent().add_child(rain_b)

	await get_tree().create_timer(0.05).timeout

	# Phase 3: Expanding ring + contracting DECELERATE ring
	# Expanding ring - 20 bullets outward
	for i in range(20):
		var ring_a = (TAU / 20.0) * i
		var rb = bullet_scene.instantiate() as EnemyBullet
		rb.global_position = global_position
		rb.direction = Vector2(cos(ring_a), sin(ring_a))
		rb.speed = 320.0
		rb.set_sprite("res://assets/sprites/bossbullut-4.png")
		get_parent().add_child(rb)
	await get_tree().create_timer(0.03).timeout
	# Contracting DECELERATE ring - 20 bullets inward toward player
	if not player or not is_instance_valid(player):
		return
	var contract_center = player.global_position
	for i in range(20):
		var ca = (TAU / 20.0) * i
		var outer_pos = contract_center + Vector2(cos(ca), sin(ca)) * 200.0
		var db = bullet_scene.instantiate() as EnemyBullet
		db.global_position = outer_pos
		db.direction = outer_pos.direction_to(contract_center)
		db.speed = 280.0
		db.bullet_type = EnemyBullet.BulletType.DECELERATE
		db.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(db)

	await get_tree().create_timer(0.05).timeout

	# Phase 4: SPLIT streams from 4 positions + BOUNCE from corners
	if not player or not is_instance_valid(player):
		return
	var split_positions = [
		Vector2(vp.x * 0.25, 20.0), Vector2(vp.x * 0.75, 20.0),
		Vector2(vp.x * 0.25, vp.y - 20.0), Vector2(vp.x * 0.75, vp.y - 20.0)
	]
	for sp_idx in range(split_positions.size()):
		var sp_pos = split_positions[sp_idx]
		var sp_aim = sp_pos.direction_to(player.global_position).angle()
		for i in range(5):
			var sa = sp_aim + (i - 2.0) * 0.14
			var sb = bullet_scene.instantiate() as EnemyBullet
			sb.global_position = sp_pos
			sb.direction = Vector2(cos(sa), sin(sa))
			sb.speed = 300.0 + i * 10.0
			sb.bullet_type = EnemyBullet.BulletType.SPLIT
			sb.set_sprite("res://assets/sprites/bossbullut-8.png")
			get_parent().add_child(sb)
		await get_tree().create_timer(0.02).timeout
	# BOUNCE from corners
	var final_corners = [
		Vector2(20.0, 20.0), Vector2(vp.x - 20.0, 20.0),
		Vector2(20.0, vp.y - 20.0), Vector2(vp.x - 20.0, vp.y - 20.0)
	]
	for fc in final_corners:
		var fc_aim = fc.direction_to(player.global_position).angle()
		for i in range(4):
			var ba = fc_aim + (i - 1.5) * 0.18
			var bb = bullet_scene.instantiate() as EnemyBullet
			bb.global_position = fc
			bb.direction = Vector2(cos(ba), sin(ba))
			bb.speed = 310.0
			bb.bullet_type = EnemyBullet.BulletType.BOUNCE
			bb.set_sprite("res://assets/sprites/bossbullut-1.png")
			get_parent().add_child(bb)
		await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 5: EVERYTHING AT ONCE - the ultimate digital meltdown
	if not player or not is_instance_valid(player):
		return
	# Random chaos spray - 15 bullets
	for i in range(15):
		var ca = randf_range(0.0, TAU)
		var c5 = bullet_scene.instantiate() as EnemyBullet
		c5.global_position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		c5.direction = Vector2(cos(ca), sin(ca))
		c5.speed = randf_range(250.0, 400.0)
		c5.set_sprite("res://assets/sprites/bossbullut-4.png")
		get_parent().add_child(c5)
	await get_tree().create_timer(0.02).timeout
	# Aimed burst at player - 10 bullets
	if not player or not is_instance_valid(player):
		return
	var final_aim = global_position.direction_to(player.global_position).angle()
	for i in range(10):
		var fa = final_aim + (i - 4.5) * 0.1
		var f5 = bullet_scene.instantiate() as EnemyBullet
		f5.global_position = global_position
		f5.direction = Vector2(cos(fa), sin(fa))
		f5.speed = 350.0 + i * 6.0
		f5.set_sprite("res://assets/sprites/bossbullut-8.png")
		get_parent().add_child(f5)
	await get_tree().create_timer(0.02).timeout
	# HOMING swarm - 8 bullets from boss
	for i in range(8):
		var ha = (TAU / 8.0) * i
		var h5 = bullet_scene.instantiate() as EnemyBullet
		h5.global_position = global_position
		h5.direction = Vector2(cos(ha), sin(ha))
		h5.speed = 240.0
		h5.bullet_type = EnemyBullet.BulletType.HOMING
		h5._homing_strength = 3.0
		h5._homing_duration = 0.7
		h5.set_sprite("res://assets/sprites/bossbullut-14.png")
		get_parent().add_child(h5)
	await get_tree().create_timer(0.02).timeout
	# LASER cross from boss - 4 beams x 5 bullets
	if not player or not is_instance_valid(player):
		return
	var laser_aim = global_position.direction_to(player.global_position).angle()
	for beam in range(4):
		var la = laser_aim + beam * (PI / 2.0)
		for i in range(5):
			var l5 = bullet_scene.instantiate() as EnemyBullet
			l5.global_position = global_position
			l5.direction = Vector2(cos(la), sin(la))
			l5.speed = 310.0 + i * 20.0
			l5.bullet_type = EnemyBullet.BulletType.LASER
			l5.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(l5)
	await get_tree().create_timer(0.02).timeout
	# Orbit cage around player - 12 bullets
	if not player or not is_instance_valid(player):
		return
	var cage_pos = player.global_position
	for i in range(12):
		var oa = (TAU / 12.0) * i
		var o5 = bullet_scene.instantiate() as EnemyBullet
		o5.global_position = cage_pos + Vector2(cos(oa), sin(oa)) * 120.0
		o5.direction = Vector2.ZERO
		o5.speed = 0.0
		o5.orbit_center = cage_pos
		o5.orbit_radius = 120.0
		o5.orbit_angle = oa
		o5.orbit_angular_speed = 7.0
		o5.orbit_time_left = 0.7
		o5.dash_after_orbit = true
		o5.dash_target = cage_pos
		o5.dash_speed = 400.0
		o5.set_sprite("res://assets/sprites/bossbullut-14.png")
		get_parent().add_child(o5)


# ============================================================================
# Boss 5 New Skills - Explosion/Demolition Theme (25 skills)
# ============================================================================

# ============================================================================
# Boss 5 - Demolition Barrage (Nonspell 1) -- 5 skills
# Theme: Explosion/Demolition - aggressive shrapnel, cluster bombs, mortar fire
# ============================================================================

func _boss5_shrapnel_burst() -> void:
	# Rapid aimed bursts at player: 6 rounds of 15-bullet aimed fans with SPLIT
	# bullets mixed in (every 3rd is SPLIT). Between rounds, fire 8 ACCELERATE
	# bullets at player. Fast 0.03s between bullets for relentless pressure.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for round_i in range(6):
		if not is_inside_tree():
			break
		# --- 15-bullet aimed fan with SPLIT every 3rd bullet ---
		var aim = global_position.direction_to(player.global_position).angle()
		for i in range(15):
			if not is_inside_tree():
				break
			var spread = aim + (i - 7.0) * 0.09
			var is_split = (i % 3 == 0)
			var b = bullet_scene.instantiate() as EnemyBullet
			b.global_position = global_position
			b.direction = Vector2(cos(spread), sin(spread))
			b.speed = 310.0 + i * 5.0
			if is_split:
				b.bullet_type = EnemyBullet.BulletType.SPLIT
				b.set_sprite("res://assets/sprites/bossbullut-6.png")
			else:
				b.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(b)
			await get_tree().create_timer(0.03).timeout
		# --- 8 ACCELERATE bullets aimed at player between rounds ---
		if player and is_instance_valid(player):
			var aim2 = global_position.direction_to(player.global_position).angle()
			for j in range(8):
				var spread2 = aim2 + (j - 3.5) * 0.06
				var acc_b = bullet_scene.instantiate() as EnemyBullet
				acc_b.global_position = global_position
				acc_b.direction = Vector2(cos(spread2), sin(spread2))
				acc_b.speed = 240.0
				acc_b.bullet_type = EnemyBullet.BulletType.ACCELERATE
				acc_b.acceleration = 280.0
				acc_b.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(acc_b)
		await get_tree().create_timer(0.10).timeout


func _boss5_cluster_bomb() -> void:
	# Fire 8 large SPLIT bullets aimed at player in a wide fan. Each splits into
	# 3 after ~1 second. Between clusters, fire HOMING from boss. 4 cluster rounds
	# total for dense explosive coverage.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for round_i in range(4):
		if not is_inside_tree():
			break
		# --- 8 SPLIT bullets in wide fan aimed at player ---
		var aim = global_position.direction_to(player.global_position).angle()
		for i in range(8):
			var spread = aim + (i - 3.5) * 0.18
			var cluster = bullet_scene.instantiate() as EnemyBullet
			cluster.global_position = global_position
			cluster.direction = Vector2(cos(spread), sin(spread))
			cluster.speed = 220.0 + round_i * 15.0
			cluster.bullet_type = EnemyBullet.BulletType.SPLIT
			cluster.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(cluster)
			await get_tree().create_timer(0.04).timeout
		# --- 6 HOMING bullets from boss between clusters ---
		if player and is_instance_valid(player):
			var aim2 = global_position.direction_to(player.global_position).angle()
			for h in range(6):
				var h_angle = aim2 + (h - 2.5) * 0.25
				var homing_b = bullet_scene.instantiate() as EnemyBullet
				homing_b.global_position = global_position
				homing_b.direction = Vector2(cos(h_angle), sin(h_angle))
				homing_b.speed = 280.0
				homing_b.bullet_type = EnemyBullet.BulletType.HOMING
				homing_b._homing_strength = 2.5
				homing_b._homing_duration = 0.7
				homing_b.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(homing_b)
		await get_tree().create_timer(0.12).timeout


func _boss5_mortar_rain() -> void:
	# Dense rain from top of screen aimed at player position. 8 waves of 15
	# ACCELERATE bullets (start slow 120, acceleration 200). Between waves,
	# aimed fan from boss (10 bullets). 0.02s between rain bullets for density.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var vp = get_viewport_rect().size
	for wave in range(8):
		if not is_inside_tree():
			break
		var target_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 15 ACCELERATE bullets raining from top toward player ---
		for i in range(15):
			if not is_inside_tree():
				break
			var spawn_x = target_pos.x + randf_range(-200, 200)
			spawn_x = clamp(spawn_x, 30, vp.x - 30)
			var spawn_pos = Vector2(spawn_x, randf_range(-15, 10))
			var rain = bullet_scene.instantiate() as EnemyBullet
			rain.global_position = spawn_pos
			rain.direction = (target_pos - spawn_pos).normalized().rotated(randf_range(-0.10, 0.10))
			rain.speed = 120.0
			rain.bullet_type = EnemyBullet.BulletType.ACCELERATE
			rain.acceleration = 200.0
			rain.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(rain)
			await get_tree().create_timer(0.02).timeout
		# --- 10-bullet aimed fan from boss between waves ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(10):
				var spread = aim + (j - 4.5) * 0.11
				var fan_b = bullet_scene.instantiate() as EnemyBullet
				fan_b.global_position = global_position
				fan_b.direction = Vector2(cos(spread), sin(spread))
				fan_b.speed = 340.0 + j * 8.0
				fan_b.set_sprite("res://assets/sprites/bossbullut-14.png")
				get_parent().add_child(fan_b)
		await get_tree().create_timer(0.08).timeout


func _boss5_grenade_scatter() -> void:
	# Bullets spawn at random positions near player (within 250px radius), then
	# explode outward in mini-rings of 8 bullets each. 20 "grenades" total in
	# rapid succession. Each grenade = 1 DECELERATE bullet that stops, then 8
	# normal bullets burst outward from that position.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for g in range(20):
		if not is_inside_tree():
			break
		var target_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- Grenade spawns near player at random offset ---
		var offset = Vector2(randf_range(-250, 250), randf_range(-250, 250))
		var grenade_pos = target_pos + offset
		grenade_pos.x = clamp(grenade_pos.x, 30, vp.x - 30)
		grenade_pos.y = clamp(grenade_pos.y, 30, vp.y - 30)
		# --- DECELERATE grenade bullet that stops at position ---
		var grenade = bullet_scene.instantiate() as EnemyBullet
		grenade.global_position = global_position
		grenade.direction = (grenade_pos - global_position).normalized()
		grenade.speed = 350.0
		grenade.bullet_type = EnemyBullet.BulletType.DECELERATE
		grenade.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(grenade)
		# --- 8 normal bullets burst outward from grenade position ---
		for k in range(8):
			var burst_angle = (TAU / 8.0) * k + randf_range(-0.1, 0.1)
			var burst = bullet_scene.instantiate() as EnemyBullet
			burst.global_position = grenade_pos
			burst.direction = Vector2(cos(burst_angle), sin(burst_angle))
			burst.speed = 260.0 + randf_range(-30, 30)
			burst.start_delay = 0.5 + randf_range(0.0, 0.2)
			burst.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(burst)
		await get_tree().create_timer(0.06).timeout


func _boss5_dynamite_chain() -> void:
	# Chain of aimed bursts from boss: simulated via 5 positions along the line
	# from boss to player, each firing a 10-bullet aimed fan at player. 3 chain
	# rounds total. Creates a cascading explosion effect along the trajectory.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for chain in range(3):
		if not is_inside_tree():
			break
		var target_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		var line_dir = (target_pos - global_position)
		var line_len = line_dir.length()
		var line_norm = line_dir.normalized()
		# --- 5 detonation points along boss-to-player line ---
		for p in range(5):
			if not is_inside_tree():
				break
			var frac = (p + 1.0) / 6.0
			var det_pos = global_position + line_norm * line_len * frac
			# --- 10-bullet aimed fan from each detonation point ---
			var aim = (target_pos - det_pos).normalized().angle()
			for i in range(10):
				var spread = aim + (i - 4.5) * 0.13
				var det_b = bullet_scene.instantiate() as EnemyBullet
				det_b.global_position = det_pos
				det_b.direction = Vector2(cos(spread), sin(spread))
				det_b.speed = 280.0 + p * 20.0
				if i % 3 == 0:
					det_b.bullet_type = EnemyBullet.BulletType.SPLIT
					det_b.set_sprite("res://assets/sprites/bossbullut-6.png")
				else:
					det_b.set_sprite("res://assets/sprites/bossbullut-14.png")
				get_parent().add_child(det_b)
			await get_tree().create_timer(0.07).timeout
		await get_tree().create_timer(0.12).timeout


# ============================================================================
# Boss 5 - Vampiric Drain (Spell 1) -- 5 skills
# Theme: 吸血 drain/pull - bullets converge, orbit inward, suction effects
# ============================================================================

func _boss5_blood_drain() -> void:
	# DECELERATE bullets fired outward from boss in rings, they stop mid-screen,
	# then ALL re-aim and converge on player position (the "drain" effect).
	# 4 rings of 24 bullets. Between rings, HOMING "blood" bullets from screen
	# edges (6 per ring) for additional pressure.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for ring in range(4):
		if not is_inside_tree():
			break
		# --- 24 DECELERATE bullets in ring from boss (stop, then re-aim) ---
		for i in range(24):
			var angle = (TAU / 24.0) * i + ring * 0.13
			var drain_b = bullet_scene.instantiate() as EnemyBullet
			drain_b.global_position = global_position
			drain_b.direction = Vector2(cos(angle), sin(angle))
			drain_b.speed = 300.0
			drain_b.bullet_type = EnemyBullet.BulletType.DECELERATE
			drain_b.set_sprite("res://assets/sprites/bossbullut-2.png")
			get_parent().add_child(drain_b)
		await get_tree().create_timer(0.10).timeout
		# --- 6 HOMING "blood" bullets from screen edges ---
		if player and is_instance_valid(player):
			var edge_positions: Array[Vector2] = [
				Vector2(randf_range(50, vp.x - 50), 10),
				Vector2(randf_range(50, vp.x - 50), vp.y - 10),
				Vector2(10, randf_range(50, vp.y - 50)),
				Vector2(vp.x - 10, randf_range(50, vp.y - 50)),
				Vector2(randf_range(50, vp.x - 50), 10),
				Vector2(10, randf_range(50, vp.y - 50)),
			]
			for e in range(6):
				var edge_b = bullet_scene.instantiate() as EnemyBullet
				edge_b.global_position = edge_positions[e]
				var aim = edge_positions[e].direction_to(player.global_position).angle()
				edge_b.direction = Vector2(cos(aim), sin(aim))
				edge_b.speed = 260.0
				edge_b.bullet_type = EnemyBullet.BulletType.HOMING
				edge_b._homing_strength = 2.8
				edge_b._homing_duration = 0.8
				edge_b.set_sprite("res://assets/sprites/bossbullut-7.png")
				get_parent().add_child(edge_b)
		await get_tree().create_timer(0.12).timeout


func _boss5_life_siphon() -> void:
	# Orbit bullets spawn around player at radius 200, orbit inward (decreasing
	# radius via multiple spawn waves at 200, 160, 120, 80), then dash at player.
	# Creates a "siphoning" vortex. 4 layers x 12 bullets. Between layers, aimed
	# LASER from boss for additional threat.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var radii = [200.0, 160.0, 120.0, 80.0]
	for layer in range(4):
		if not is_inside_tree():
			break
		if not player or not is_instance_valid(player):
			break
		var target = player.global_position
		var radius = radii[layer]
		# --- 12 orbit bullets at current radius, spiraling inward ---
		for i in range(12):
			var angle = (TAU / 12.0) * i + layer * 0.26
			var siphon = bullet_scene.instantiate() as EnemyBullet
			siphon.global_position = target + Vector2(cos(angle), sin(angle)) * radius
			siphon.direction = Vector2.ZERO
			siphon.speed = 0.0
			siphon.orbit_center = target
			siphon.orbit_radius = radius
			siphon.orbit_angle = angle
			siphon.orbit_angular_speed = 2.2 + layer * 0.4
			siphon.orbit_time_left = 1.5 - layer * 0.25
			siphon.dash_after_orbit = true
			siphon.dash_target = target
			siphon.dash_speed = 360.0
			siphon.set_sprite("res://assets/sprites/bossbullut-2.png")
			get_parent().add_child(siphon)
		await get_tree().create_timer(0.08).timeout
		# --- Aimed LASER from boss between layers ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for l in range(3):
				var l_spread = aim + (l - 1.0) * 0.08
				var laser = bullet_scene.instantiate() as EnemyBullet
				laser.global_position = global_position
				laser.direction = Vector2(cos(l_spread), sin(l_spread))
				laser.speed = 520.0
				laser.bullet_type = EnemyBullet.BulletType.LASER
				laser.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(laser)
		await get_tree().create_timer(0.12).timeout


func _boss5_soul_harvest() -> void:
	# Bullets from ALL 4 screen edges + 4 corners (8 sources) all converge on
	# player simultaneously. 8 sources x 8 bullets each x 3 waves. Mix of normal
	# and HOMING. Creates overwhelming convergence from every direction.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for wave in range(3):
		if not is_inside_tree():
			break
		var target = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 8 source positions: 4 edges + 4 corners ---
		var sources: Array[Vector2] = [
			Vector2(target.x, 5),                    # top
			Vector2(target.x, vp.y - 5),             # bottom
			Vector2(5, target.y),                     # left
			Vector2(vp.x - 5, target.y),             # right
			Vector2(15, 15),                          # top-left
			Vector2(vp.x - 15, 15),                  # top-right
			Vector2(15, vp.y - 15),                   # bottom-left
			Vector2(vp.x - 15, vp.y - 15),           # bottom-right
		]
		for s in range(8):
			if not is_inside_tree():
				break
			var src = sources[s]
			for i in range(8):
				var aim = src.direction_to(target).angle() + (i - 3.5) * 0.08
				var soul = bullet_scene.instantiate() as EnemyBullet
				soul.global_position = src + Vector2(randf_range(-20, 20), randf_range(-20, 20))
				soul.direction = Vector2(cos(aim), sin(aim))
				soul.speed = 280.0 + wave * 25.0
				if i % 3 == 0:
					soul.bullet_type = EnemyBullet.BulletType.HOMING
					soul._homing_strength = 2.2
					soul._homing_duration = 0.6
					soul.set_sprite("res://assets/sprites/bossbullut-7.png")
				else:
					soul.set_sprite("res://assets/sprites/bossbullut-2.png")
				get_parent().add_child(soul)
			await get_tree().create_timer(0.03).timeout
		await get_tree().create_timer(0.15).timeout


func _boss5_crimson_vortex() -> void:
	# CURVE bullets fired in rings from boss that curve TOWARD player (turn_rate
	# aimed inward). 6 rings of 20 curve bullets. Between rings, DECELERATE traps
	# around player position (8 per ring) to restrict movement.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for ring in range(6):
		if not is_inside_tree():
			break
		var target = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 20 CURVE bullets in ring, curving toward player ---
		for i in range(20):
			var angle = (TAU / 20.0) * i + ring * 0.16
			var curve_b = bullet_scene.instantiate() as EnemyBullet
			curve_b.global_position = global_position
			curve_b.direction = Vector2(cos(angle), sin(angle))
			curve_b.speed = 250.0 + ring * 15.0
			curve_b.bullet_type = EnemyBullet.BulletType.CURVE
			# Turn rate aimed inward toward player
			var to_player = (target - global_position).angle()
			var diff = angle - to_player
			curve_b.turn_rate = -sign(sin(diff)) * (1.8 + ring * 0.2)
			curve_b.set_sprite("res://assets/sprites/bossbullut-2.png")
			get_parent().add_child(curve_b)
		await get_tree().create_timer(0.06).timeout
		# --- 8 DECELERATE traps around player position ---
		if player and is_instance_valid(player):
			var trap_target = player.global_position
			for t in range(8):
				var trap_angle = (TAU / 8.0) * t + ring * 0.4
				var trap_pos = trap_target + Vector2(cos(trap_angle), sin(trap_angle)) * 130.0
				var trap = bullet_scene.instantiate() as EnemyBullet
				trap.global_position = trap_pos
				trap.direction = Vector2(cos(trap_angle + PI), sin(trap_angle + PI))
				trap.speed = 180.0
				trap.bullet_type = EnemyBullet.BulletType.DECELERATE
				trap.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(trap)
		await get_tree().create_timer(0.10).timeout


func _boss5_essence_steal() -> void:
	# Multi-phase drain: Phase 1 - orbit cage around player (16 bullets, dash
	# inward). Phase 2 - DECELERATE ring from player position outward then stops.
	# Phase 3 - HOMING from all edges. Phase 4 - aimed ACCELERATE barrage from
	# boss. Everything converges on player for maximum drain pressure.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	var target = player.global_position

	# === PHASE 1: Orbit cage around player (16 bullets, dash inward) ===
	for i in range(16):
		if not is_inside_tree():
			break
		var angle = (TAU / 16.0) * i
		var cage = bullet_scene.instantiate() as EnemyBullet
		cage.global_position = target + Vector2(cos(angle), sin(angle)) * 220.0
		cage.direction = Vector2.ZERO
		cage.speed = 0.0
		cage.orbit_center = target
		cage.orbit_radius = 220.0
		cage.orbit_angle = angle
		cage.orbit_angular_speed = 1.8
		cage.orbit_time_left = 2.0
		cage.dash_after_orbit = true
		cage.dash_target = target
		cage.dash_speed = 400.0
		cage.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(cage)
	await get_tree().create_timer(0.15).timeout

	# === PHASE 2: DECELERATE ring from player position ===
	if player and is_instance_valid(player):
		target = player.global_position
	for i in range(16):
		if not is_inside_tree():
			break
		var angle = (TAU / 16.0) * i + 0.2
		var decel = bullet_scene.instantiate() as EnemyBullet
		decel.global_position = target
		decel.direction = Vector2(cos(angle), sin(angle))
		decel.speed = 280.0
		decel.bullet_type = EnemyBullet.BulletType.DECELERATE
		decel.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(decel)
	await get_tree().create_timer(0.12).timeout

	# === PHASE 3: HOMING from all edges (12 bullets) ===
	if player and is_instance_valid(player):
		target = player.global_position
		var edge_spawns: Array[Vector2] = [
			Vector2(randf_range(50, vp.x - 50), 5),
			Vector2(randf_range(50, vp.x - 50), 5),
			Vector2(randf_range(50, vp.x - 50), 5),
			Vector2(randf_range(50, vp.x - 50), vp.y - 5),
			Vector2(randf_range(50, vp.x - 50), vp.y - 5),
			Vector2(randf_range(50, vp.x - 50), vp.y - 5),
			Vector2(5, randf_range(50, vp.y - 50)),
			Vector2(5, randf_range(50, vp.y - 50)),
			Vector2(5, randf_range(50, vp.y - 50)),
			Vector2(vp.x - 5, randf_range(50, vp.y - 50)),
			Vector2(vp.x - 5, randf_range(50, vp.y - 50)),
			Vector2(vp.x - 5, randf_range(50, vp.y - 50)),
		]
		for e in range(12):
			if not is_inside_tree():
				break
			var hb = bullet_scene.instantiate() as EnemyBullet
			hb.global_position = edge_spawns[e]
			var aim = edge_spawns[e].direction_to(target).angle()
			hb.direction = Vector2(cos(aim), sin(aim))
			hb.speed = 300.0
			hb.bullet_type = EnemyBullet.BulletType.HOMING
			hb._homing_strength = 3.0
			hb._homing_duration = 0.7
			hb.set_sprite("res://assets/sprites/bossbullut-7.png")
			get_parent().add_child(hb)
			await get_tree().create_timer(0.03).timeout
	await get_tree().create_timer(0.10).timeout

	# === PHASE 4: Aimed ACCELERATE barrage from boss (20 bullets) ===
	if player and is_instance_valid(player):
		var aim = global_position.direction_to(player.global_position).angle()
		for i in range(20):
			if not is_inside_tree():
				break
			var spread = aim + (i - 9.5) * 0.06
			var acc = bullet_scene.instantiate() as EnemyBullet
			acc.global_position = global_position
			acc.direction = Vector2(cos(spread), sin(spread))
			acc.speed = 200.0
			acc.bullet_type = EnemyBullet.BulletType.ACCELERATE
			acc.acceleration = 250.0
			acc.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(acc)
			await get_tree().create_timer(0.02).timeout

# =============================================================================
# NONSPELL 2 - Summoning Barrage (5 skills)
# =============================================================================

func _boss5_minion_swarm() -> void:
	# 6 "minion" positions spawn around screen edges. Each minion fires 8-bullet
	# aimed fan at player. Minions shift position each round. 5 rounds.
	# Between rounds, boss fires LASER at player.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for round_idx in range(5):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 6 minion positions along screen edges, shifting each round ---
		var shift = round_idx * 55.0
		var minion_positions: Array[Vector2] = [
			Vector2(clampf(80.0 + shift, 30, vp.x - 30), 15.0),
			Vector2(clampf(vp.x - 80.0 - shift, 30, vp.x - 30), 15.0),
			Vector2(15.0, clampf(150.0 + shift, 30, vp.y - 30)),
			Vector2(vp.x - 15.0, clampf(150.0 + shift, 30, vp.y - 30)),
			Vector2(clampf(200.0 + shift * 0.7, 30, vp.x - 30), vp.y - 15.0),
			Vector2(clampf(vp.x - 200.0 - shift * 0.7, 30, vp.x - 30), vp.y - 15.0)
		]
		# --- Each minion fires 8-bullet aimed fan at player ---
		for minion_idx in range(6):
			var origin = minion_positions[minion_idx]
			var aim = origin.direction_to(p_pos).angle()
			for i in range(8):
				var spread = aim + (i - 3.5) * 0.11
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = origin
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 290.0 + i * 5.0
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
			await get_tree().create_timer(0.03).timeout
		await get_tree().create_timer(0.06).timeout
		# --- Boss fires LASER at player between rounds ---
		if player and is_instance_valid(player):
			var laser_aim = global_position.direction_to(player.global_position)
			var laser = bullet_scene.instantiate() as EnemyBullet
			laser.global_position = global_position
			laser.direction = laser_aim
			laser.speed = 380.0
			laser.bullet_type = EnemyBullet.BulletType.LASER
			laser.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(laser)
		await get_tree().create_timer(0.10).timeout


func _boss5_artillery_summon() -> void:
	# 4 "artillery" positions at screen corners. Each fires 10 ACCELERATE bullets
	# aimed at player in rapid succession. 4 rounds, artillery positions rotate
	# each round. Boss fires HOMING between rounds.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	var base_corners: Array[Vector2] = [
		Vector2(30, 30), Vector2(vp.x - 30, 30),
		Vector2(30, vp.y - 30), Vector2(vp.x - 30, vp.y - 30)
	]
	for round_idx in range(4):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- Rotate which corners are active by shifting index ---
		for c_idx in range(4):
			var corner = base_corners[(c_idx + round_idx) % 4]
			var aim = corner.direction_to(p_pos).angle()
			# --- 10 ACCELERATE bullets per artillery in rapid succession ---
			for i in range(10):
				var spread = aim + (i - 4.5) * 0.06
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = corner
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 220.0
				bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
				await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.06).timeout
		# --- Boss fires HOMING between rounds ---
		if player and is_instance_valid(player):
			var h_aim = global_position.direction_to(player.global_position)
			for h in range(3):
				var homing_b = bullet_scene.instantiate() as EnemyBullet
				homing_b.global_position = global_position + Vector2(randf_range(-15, 15), randf_range(-15, 15))
				homing_b.direction = h_aim
				homing_b.speed = 230.0
				homing_b.bullet_type = EnemyBullet.BulletType.HOMING
				homing_b._homing_strength = 2.5
				homing_b._homing_duration = 0.7
				homing_b.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(homing_b)
		await get_tree().create_timer(0.10).timeout


func _boss5_phantom_army() -> void:
	# 6 phantom positions (3 on each side of screen) fire SINE_WAVE streams
	# aimed at player simultaneously. 4 waves of 8 bullets per phantom.
	# Between waves, DECELERATE ring from boss.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for wave in range(4):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 6 phantom positions: 3 left side, 3 right side ---
		var phantoms: Array[Vector2] = [
			Vector2(15.0, vp.y * 0.2 + wave * 20.0),
			Vector2(15.0, vp.y * 0.5),
			Vector2(15.0, vp.y * 0.8 - wave * 20.0),
			Vector2(vp.x - 15.0, vp.y * 0.2 + wave * 20.0),
			Vector2(vp.x - 15.0, vp.y * 0.5),
			Vector2(vp.x - 15.0, vp.y * 0.8 - wave * 20.0)
		]
		# --- Each phantom fires 8 SINE_WAVE bullets aimed at player ---
		for ph_idx in range(6):
			var origin = phantoms[ph_idx]
			var aim = origin.direction_to(p_pos).angle()
			for i in range(8):
				var spread = aim + (i - 3.5) * 0.09
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = origin
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 270.0 + i * 8.0
				bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
				bullet.set_sprite("res://assets/sprites/bossbullut-7.png")
				get_parent().add_child(bullet)
			await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.06).timeout
		# --- DECELERATE ring from boss between waves ---
		for j in range(16):
			var angle = (TAU / 16.0) * j + wave * 0.2
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 250.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


func _boss5_trap_field() -> void:
	# DECELERATE bullets spawn at 20 random positions across the screen. They all
	# stop, wait, then re-aim at player and fire. 3 rounds. Between rounds,
	# aimed fan from boss (12 bullets).
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for round_idx in range(3):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 20 DECELERATE bullets at random positions, aimed outward initially ---
		for i in range(20):
			var spawn_pos = Vector2(
				randf_range(60.0, vp.x - 60.0),
				randf_range(60.0, vp.y - 60.0)
			)
			var rand_angle = randf_range(0, TAU)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = Vector2(cos(rand_angle), sin(rand_angle))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
			if i % 5 == 4:
				await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.08).timeout
		# --- Re-aim phase: fire new aimed bullets from scattered positions ---
		if player and is_instance_valid(player):
			p_pos = player.global_position
			for j in range(20):
				var trap_pos = Vector2(
					randf_range(60.0, vp.x - 60.0),
					randf_range(60.0, vp.y - 60.0)
				)
				var aim = trap_pos.direction_to(p_pos).angle()
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = trap_pos
				bullet.direction = Vector2(cos(aim), sin(aim))
				bullet.speed = 320.0
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
				if j % 5 == 4:
					await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.06).timeout
		# --- Boss fires 12-bullet aimed fan between rounds ---
		if player and is_instance_valid(player):
			p_pos = player.global_position
			var aim = global_position.direction_to(p_pos).angle()
			for k in range(12):
				var spread = aim + (k - 5.5) * 0.09
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 300.0
				bullet.set_sprite("res://assets/sprites/bossbullut-2.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout


func _boss5_cross_fire() -> void:
	# 4 positions form a cross around player (above, below, left, right at 300px
	# distance). All 4 fire aimed streams at player simultaneously. 6 waves of
	# 10 bullets per position. Boss fires SPLIT bullets between waves.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for wave in range(6):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 4 cross positions around player at 300px distance ---
		var cross_offsets: Array[Vector2] = [
			Vector2(0, -300), Vector2(0, 300),
			Vector2(-300, 0), Vector2(300, 0)
		]
		for c_idx in range(4):
			var origin = p_pos + cross_offsets[c_idx]
			origin.x = clampf(origin.x, 15.0, vp.x - 15.0)
			origin.y = clampf(origin.y, 15.0, vp.y - 15.0)
			var aim = origin.direction_to(p_pos).angle()
			# --- 10 bullets per position in tight aimed stream ---
			for i in range(10):
				var spread = aim + (i - 4.5) * 0.04
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = origin
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 310.0 + i * 4.0
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
			await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.06).timeout
		# --- Boss fires SPLIT bullets between waves ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for s in range(3):
				var s_angle = aim + (s - 1) * 0.15
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(s_angle), sin(s_angle))
				bullet.speed = 280.0
				bullet.bullet_type = EnemyBullet.BulletType.SPLIT
				bullet.set_sprite("res://assets/sprites/bossbullut-14.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


# =============================================================================
# SPELL 2 - Cursed Arsenal (5 skills)
# =============================================================================

func _boss5_cursed_barrage() -> void:
	# Phase 1: Dense aimed fan from boss (20 bullets). Phase 2: HOMING from all
	# 4 edges (5 per edge). Phase 3: DECELERATE ring trap around player (20
	# bullets). Repeat 3 times with increasing density.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for cycle in range(3):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		var density_mult = 1.0 + cycle * 0.3
		# --- Phase 1: Dense aimed fan from boss ---
		var fan_count = int(20 * density_mult)
		var aim = global_position.direction_to(p_pos).angle()
		for i in range(fan_count):
			var spread = aim + (i - fan_count / 2.0) * 0.07
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 310.0
			bullet.set_sprite("res://assets/sprites/bossbullut-2.png")
			get_parent().add_child(bullet)
			if i % 4 == 3:
				await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.06).timeout
		# --- Phase 2: HOMING from all 4 edges ---
		if player and is_instance_valid(player):
			p_pos = player.global_position
		var edge_origins: Array[Array] = [
			[Vector2(vp.x * 0.5, 15.0)],
			[Vector2(vp.x * 0.5, vp.y - 15.0)],
			[Vector2(15.0, vp.y * 0.5)],
			[Vector2(vp.x - 15.0, vp.y * 0.5)]
		]
		var homing_per_edge = int(5 * density_mult)
		for edge in edge_origins:
			var origin: Vector2 = edge[0]
			var h_aim = origin.direction_to(p_pos)
			for h in range(homing_per_edge):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = origin + Vector2(randf_range(-30, 30), randf_range(-30, 30))
				bullet.direction = h_aim
				bullet.speed = 240.0
				bullet.bullet_type = EnemyBullet.BulletType.HOMING
				bullet._homing_strength = 2.5
				bullet._homing_duration = 0.6
				bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(bullet)
			await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.06).timeout
		# --- Phase 3: DECELERATE ring trap around player ---
		if player and is_instance_valid(player):
			p_pos = player.global_position
		var ring_count = int(20 * density_mult)
		for j in range(ring_count):
			var angle = (TAU / float(ring_count)) * j
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = p_pos + Vector2(cos(angle), sin(angle)) * 220.0
			bullet.direction = Vector2(cos(angle + PI), sin(angle + PI))
			bullet.speed = 200.0
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout


func _boss5_death_sentence() -> void:
	# Orbit cage around player (20 bullets at radius 180, orbit 1.5s, then dash
	# inward at 380 speed). While orbiting, boss fires LASER aimed at player
	# every 0.1s. 3 cage rounds.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for cage_round in range(3):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- Spawn 20 orbit bullets forming cage around player ---
		for i in range(20):
			var angle = (TAU / 20.0) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = p_pos + Vector2(cos(angle), sin(angle)) * 180.0
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 0.0
			bullet.orbit_center = p_pos
			bullet.orbit_radius = 180.0
			bullet.orbit_angle = angle
			bullet.orbit_angular_speed = TAU / 1.5
			bullet.orbit_time_left = 1.5
			bullet.dash_after_orbit = true
			bullet.dash_target = p_pos
			bullet.dash_speed = 380.0
			bullet.set_sprite("res://assets/sprites/bossbullut-7.png")
			get_parent().add_child(bullet)
		# --- While orbiting, boss fires LASER at player every 0.1s ---
		var laser_count = int(1.5 / 0.1)
		for l in range(laser_count):
			if player and is_instance_valid(player):
				var l_aim = global_position.direction_to(player.global_position)
				var laser = bullet_scene.instantiate() as EnemyBullet
				laser.global_position = global_position
				laser.direction = l_aim
				laser.speed = 370.0
				laser.bullet_type = EnemyBullet.BulletType.LASER
				laser.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(laser)
			await get_tree().create_timer(0.1).timeout
		await get_tree().create_timer(0.12).timeout


func _boss5_hellfire_rain() -> void:
	# Rain from top + sides simultaneously. Top: 20 ACCELERATE bullets aimed at
	# player. Left: 10 aimed bullets. Right: 10 aimed bullets. 5 waves. Between
	# waves, CURVE bullets from boss that curve toward player.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for wave in range(5):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- Top: 20 ACCELERATE bullets aimed at player ---
		for i in range(20):
			var x_pos = (vp.x / 21.0) * (i + 1)
			var origin = Vector2(x_pos, 15.0)
			var aim = origin.direction_to(p_pos)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = origin
			bullet.direction = aim
			bullet.speed = 230.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
			if i % 5 == 4:
				await get_tree().create_timer(0.02).timeout
		# --- Left side: 10 aimed bullets ---
		for i in range(10):
			var y_pos = (vp.y / 11.0) * (i + 1)
			var origin = Vector2(15.0, y_pos)
			var aim = origin.direction_to(p_pos)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = origin
			bullet.direction = aim
			bullet.speed = 290.0
			bullet.set_sprite("res://assets/sprites/bossbullut-2.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.02).timeout
		# --- Right side: 10 aimed bullets ---
		for i in range(10):
			var y_pos = (vp.y / 11.0) * (i + 1)
			var origin = Vector2(vp.x - 15.0, y_pos)
			var aim = origin.direction_to(p_pos)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = origin
			bullet.direction = aim
			bullet.speed = 290.0
			bullet.set_sprite("res://assets/sprites/bossbullut-2.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		# --- CURVE bullets from boss between waves ---
		if player and is_instance_valid(player):
			var c_aim = global_position.direction_to(player.global_position).angle()
			for c in range(4):
				var c_angle = c_aim + (c - 1.5) * 0.2
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(c_angle), sin(c_angle))
				bullet.speed = 260.0
				bullet.bullet_type = EnemyBullet.BulletType.CURVE
				bullet.set_sprite("res://assets/sprites/bossbullut-14.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout


func _boss5_soul_cage() -> void:
	# Multi-source orbit: 4 orbit rings at different positions around player
	# (offset by 90 degrees), each with 8 bullets. All dash at player after
	# orbiting. Between cages, SPLIT burst from boss aimed at player. 3 rounds.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	for cage_round in range(3):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- 4 orbit rings offset by 90 degrees around player ---
		var ring_offsets: Array[Vector2] = [
			Vector2(0, -140), Vector2(140, 0),
			Vector2(0, 140), Vector2(-140, 0)
		]
		for ring_idx in range(4):
			var ring_center = p_pos + ring_offsets[ring_idx]
			# --- 8 orbit bullets per ring ---
			for i in range(8):
				var angle = (TAU / 8.0) * i + cage_round * 0.4
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = ring_center + Vector2(cos(angle), sin(angle)) * 90.0
				bullet.direction = Vector2(cos(angle), sin(angle))
				bullet.speed = 0.0
				bullet.orbit_center = ring_center
				bullet.orbit_radius = 90.0
				bullet.orbit_angle = angle
				bullet.orbit_angular_speed = TAU / 1.2
				bullet.orbit_time_left = 1.2
				bullet.dash_after_orbit = true
				bullet.dash_target = p_pos
				bullet.dash_speed = 350.0
				bullet.set_sprite("res://assets/sprites/bossbullut-7.png")
				get_parent().add_child(bullet)
			await get_tree().create_timer(0.03).timeout
		# --- Wait for orbit to complete ---
		await get_tree().create_timer(0.08).timeout
		# --- SPLIT burst from boss aimed at player between cages ---
		if player and is_instance_valid(player):
			var aim = global_position.direction_to(player.global_position).angle()
			for s in range(6):
				var s_angle = aim + (s - 2.5) * 0.13
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(s_angle), sin(s_angle))
				bullet.speed = 300.0
				bullet.bullet_type = EnemyBullet.BulletType.SPLIT
				bullet.set_sprite("res://assets/sprites/bossbullut-14.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout


func _boss5_doom_spiral() -> void:
	# Triple SPIRAL arms from boss + HOMING from 4 edges + DECELERATE minefield
	# around player. All happening in overlapping waves. 60 spiral steps with
	# edge homing every 10 steps and decelerate every 15 steps.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size
	for step in range(60):
		var p_pos = player.global_position if player and is_instance_valid(player) else Vector2(450, 350)
		# --- Triple SPIRAL arms from boss ---
		for arm in range(3):
			var angle = (TAU / 3.0) * arm + step * 0.15
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 280.0
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		# --- HOMING from 4 edges every 10 steps ---
		if step % 10 == 0:
			var edge_positions: Array[Vector2] = [
				Vector2(randf_range(50, vp.x - 50), 15.0),
				Vector2(randf_range(50, vp.x - 50), vp.y - 15.0),
				Vector2(15.0, randf_range(50, vp.y - 50)),
				Vector2(vp.x - 15.0, randf_range(50, vp.y - 50))
			]
			for e_idx in range(4):
				var origin = edge_positions[e_idx]
				var h_aim = origin.direction_to(p_pos)
				for h in range(3):
					var hb = bullet_scene.instantiate() as EnemyBullet
					hb.global_position = origin + Vector2(randf_range(-20, 20), randf_range(-20, 20))
					hb.direction = h_aim
					hb.speed = 250.0
					hb.bullet_type = EnemyBullet.BulletType.HOMING
					hb._homing_strength = 3.0
					hb._homing_duration = 0.8
					hb.set_sprite("res://assets/sprites/bossbullut-5.png")
					get_parent().add_child(hb)
		# --- DECELERATE minefield around player every 15 steps ---
		if step % 15 == 0:
			for m in range(12):
				var m_angle = (TAU / 12.0) * m + step * 0.3
				var spawn_dist = randf_range(100.0, 250.0)
				var spawn_pos = p_pos + Vector2(cos(m_angle), sin(m_angle)) * spawn_dist
				spawn_pos.x = clampf(spawn_pos.x, 15.0, vp.x - 15.0)
				spawn_pos.y = clampf(spawn_pos.y, 15.0, vp.y - 15.0)
				var aim = spawn_pos.direction_to(p_pos)
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = spawn_pos
				bullet.direction = aim
				bullet.speed = 210.0
				bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
				bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout

# =============================================================================
# FINAL PHASE - Bakuretsu Finale / 爆裂終章 (5 super skills)
# Boss 5 Theme: Explosion/Demolition - vampiric drain, summoning, shooting
# The ultimate explosion combining ALL mechanics: split bursts, accelerate rain,
# homing swarms, decelerate traps, orbit cages, laser crosses, curve bullets,
# bounce ricochets, sine waves, spirals - maximum demolition intensity.
# =============================================================================

func _boss5_nuclear_meltdown() -> void:
	# Super multi-phase nuclear meltdown:
	# Phase 1: Dense SPLIT burst aimed at player (15 split bullets in fan).
	# Phase 2: ACCELERATE rain from top aimed at player (25 bullets).
	# Phase 3: HOMING swarm from all 4 edges (5 per edge = 20 total).
	# Phase 4: DECELERATE ring trap around player (24 bullets converging).
	# Phase 5: Orbit cage (16 bullets) that dashes inward.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: Dense SPLIT burst aimed at player - 15 split bullets in fan
	var split_aim = global_position.direction_to(player.global_position).angle()
	for i in range(15):
		var spread = split_aim + (i - 7.0) * 0.11
		var sb = bullet_scene.instantiate() as EnemyBullet
		sb.global_position = global_position
		sb.direction = Vector2(cos(spread), sin(spread))
		sb.speed = 290.0 + i * 6.0
		sb.bullet_type = EnemyBullet.BulletType.SPLIT
		sb.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(sb)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 2: ACCELERATE rain from top aimed at player - 25 bullets
	if not player or not is_instance_valid(player):
		return
	var rain_target = player.global_position
	for i in range(25):
		var x_pos = rain_target.x + randf_range(-340, 340)
		x_pos = clampf(x_pos, 25, vp.x - 25)
		var rain_origin = Vector2(x_pos, 15.0)
		var rain_b = bullet_scene.instantiate() as EnemyBullet
		rain_b.global_position = rain_origin
		rain_b.direction = (rain_target - rain_origin).normalized().rotated(randf_range(-0.06, 0.06))
		rain_b.speed = 240.0
		rain_b.bullet_type = EnemyBullet.BulletType.ACCELERATE
		rain_b.acceleration = 380.0
		rain_b.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(rain_b)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 3: HOMING swarm from all 4 edges - 5 per edge = 20 total
	if not player or not is_instance_valid(player):
		return
	var edge_sets = []
	for k in range(5):
		edge_sets.append(Vector2(vp.x * (0.1 + k * 0.2), 15.0))
		edge_sets.append(Vector2(vp.x * (0.1 + k * 0.2), vp.y - 15.0))
		edge_sets.append(Vector2(15.0, vp.y * (0.1 + k * 0.2)))
		edge_sets.append(Vector2(vp.x - 15.0, vp.y * (0.1 + k * 0.2)))
	for idx in range(edge_sets.size()):
		var spawn = edge_sets[idx] as Vector2
		var hb = bullet_scene.instantiate() as EnemyBullet
		hb.global_position = spawn
		hb.direction = spawn.direction_to(player.global_position)
		hb.speed = 280.0
		hb.bullet_type = EnemyBullet.BulletType.HOMING
		hb._homing_strength = 2.8
		hb._homing_duration = 0.7
		hb.set_sprite("res://assets/sprites/bossbullut-7.png")
		get_parent().add_child(hb)
		if idx % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 4: DECELERATE ring trap around player - 24 bullets converging
	if not player or not is_instance_valid(player):
		return
	var trap_center = player.global_position
	for i in range(24):
		var angle = (TAU / 24.0) * i
		var outer_pos = trap_center + Vector2(cos(angle), sin(angle)) * 210.0
		var decel_b = bullet_scene.instantiate() as EnemyBullet
		decel_b.global_position = outer_pos
		decel_b.direction = outer_pos.direction_to(trap_center)
		decel_b.speed = 270.0
		decel_b.bullet_type = EnemyBullet.BulletType.DECELERATE
		decel_b.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(decel_b)
		if i % 6 == 5:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 5: Orbit cage (16 bullets) that dashes inward at player
	if not player or not is_instance_valid(player):
		return
	var cage_center = player.global_position
	for i in range(16):
		var angle = (TAU / 16.0) * i
		var spawn_pos = cage_center + Vector2(cos(angle), sin(angle)) * 135.0
		var orb = bullet_scene.instantiate() as EnemyBullet
		orb.global_position = spawn_pos
		orb.direction = Vector2.ZERO
		orb.speed = 0.0
		orb.orbit_center = cage_center
		orb.orbit_radius = 135.0
		orb.orbit_angle = angle
		orb.orbit_angular_speed = 7.5
		orb.orbit_time_left = 0.8
		orb.dash_after_orbit = true
		orb.dash_target = cage_center
		orb.dash_speed = 400.0
		orb.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(orb)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout


func _boss5_armageddon_rain() -> void:
	# Super multi-phase armageddon rain:
	# Phase 1: Rain from ALL 4 screen edges converging on player (10 per edge = 40).
	# Phase 2: 4 "artillery" positions fire aimed ACCELERATE streams (8 per position = 32).
	# Phase 3: LASER cross from boss aimed at player (4 beams x 6 bullets = 24).
	# Phase 4: CURVE bullets from boss curving toward player (20 bullets).
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: Rain from ALL 4 screen edges converging on player - 10 per edge
	var target_p1 = player.global_position
	# Top edge
	for i in range(10):
		var x_pos = target_p1.x + randf_range(-360, 360)
		x_pos = clampf(x_pos, 20, vp.x - 20)
		var rb = bullet_scene.instantiate() as EnemyBullet
		rb.global_position = Vector2(x_pos, 15.0)
		rb.direction = (target_p1 - rb.global_position).normalized().rotated(randf_range(-0.05, 0.05))
		rb.speed = randf_range(280.0, 370.0)
		rb.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(rb)
	await get_tree().create_timer(0.02).timeout
	# Bottom edge
	for i in range(10):
		var x_pos = target_p1.x + randf_range(-360, 360)
		x_pos = clampf(x_pos, 20, vp.x - 20)
		var rb = bullet_scene.instantiate() as EnemyBullet
		rb.global_position = Vector2(x_pos, vp.y - 15.0)
		rb.direction = (target_p1 - rb.global_position).normalized().rotated(randf_range(-0.05, 0.05))
		rb.speed = randf_range(280.0, 370.0)
		rb.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(rb)
	await get_tree().create_timer(0.02).timeout
	# Left edge
	for i in range(10):
		var y_pos = target_p1.y + randf_range(-280, 280)
		y_pos = clampf(y_pos, 20, vp.y - 20)
		var rb = bullet_scene.instantiate() as EnemyBullet
		rb.global_position = Vector2(15.0, y_pos)
		rb.direction = (target_p1 - rb.global_position).normalized().rotated(randf_range(-0.05, 0.05))
		rb.speed = randf_range(280.0, 370.0)
		rb.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(rb)
	await get_tree().create_timer(0.02).timeout
	# Right edge
	for i in range(10):
		var y_pos = target_p1.y + randf_range(-280, 280)
		y_pos = clampf(y_pos, 20, vp.y - 20)
		var rb = bullet_scene.instantiate() as EnemyBullet
		rb.global_position = Vector2(vp.x - 15.0, y_pos)
		rb.direction = (target_p1 - rb.global_position).normalized().rotated(randf_range(-0.05, 0.05))
		rb.speed = randf_range(280.0, 370.0)
		rb.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(rb)

	await get_tree().create_timer(0.05).timeout

	# Phase 2: 4 "artillery" positions fire aimed ACCELERATE streams - 8 per position
	if not player or not is_instance_valid(player):
		return
	var artillery_positions = [
		Vector2(vp.x * 0.15, vp.y * 0.15),
		Vector2(vp.x * 0.85, vp.y * 0.15),
		Vector2(vp.x * 0.15, vp.y * 0.85),
		Vector2(vp.x * 0.85, vp.y * 0.85),
	]
	for art_idx in range(artillery_positions.size()):
		if not player or not is_instance_valid(player):
			break
		var art_pos = artillery_positions[art_idx] as Vector2
		var aim = art_pos.direction_to(player.global_position).angle()
		for i in range(8):
			var spread = aim + (i - 3.5) * 0.09
			var ab = bullet_scene.instantiate() as EnemyBullet
			ab.global_position = art_pos
			ab.direction = Vector2(cos(spread), sin(spread))
			ab.speed = 230.0
			ab.bullet_type = EnemyBullet.BulletType.ACCELERATE
			ab.acceleration = 360.0
			ab.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(ab)
			if i % 4 == 3:
				await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 3: LASER cross from boss aimed at player - 4 beams x 6 bullets
	if not player or not is_instance_valid(player):
		return
	var cross_aim = global_position.direction_to(player.global_position).angle()
	for beam in range(4):
		var beam_angle = cross_aim + beam * (PI / 2.0)
		for i in range(6):
			var lb = bullet_scene.instantiate() as EnemyBullet
			lb.global_position = global_position
			lb.direction = Vector2(cos(beam_angle), sin(beam_angle))
			lb.speed = 320.0 + i * 22.0
			lb.bullet_type = EnemyBullet.BulletType.LASER
			lb.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(lb)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 4: CURVE bullets from boss curving toward player - 20 bullets
	if not player or not is_instance_valid(player):
		return
	var curve_base = global_position.direction_to(player.global_position).angle()
	for i in range(20):
		var offset_angle = curve_base + (i - 9.5) * 0.16
		var curve_dir = Vector2(cos(offset_angle), sin(offset_angle))
		var cb = bullet_scene.instantiate() as EnemyBullet
		cb.global_position = global_position
		cb.direction = curve_dir
		cb.speed = 260.0 + i * 5.0
		cb.bullet_type = EnemyBullet.BulletType.CURVE
		cb.set_sprite("res://assets/sprites/bossbullut-14.png")
		get_parent().add_child(cb)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout


func _boss5_vampiric_apocalypse() -> void:
	# Super multi-phase vampiric apocalypse:
	# Phase 1: Orbit cage around player (20 bullets, dash inward).
	# Phase 2: DECELERATE bullets from 8 screen positions, all converge on player.
	# Phase 3: HOMING from boss (16 bullets).
	# Phase 4: SINE_WAVE streams from 3 phantom positions aimed at player.
	# Phase 5: Final aimed SPLIT burst (12 bullets).
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: Orbit cage around player - 20 bullets orbit then dash inward
	var cage_center = player.global_position
	for i in range(20):
		var angle = (TAU / 20.0) * i
		var spawn_pos = cage_center + Vector2(cos(angle), sin(angle)) * 145.0
		var orb = bullet_scene.instantiate() as EnemyBullet
		orb.global_position = spawn_pos
		orb.direction = Vector2.ZERO
		orb.speed = 0.0
		orb.orbit_center = cage_center
		orb.orbit_radius = 145.0
		orb.orbit_angle = angle
		orb.orbit_angular_speed = 7.0
		orb.orbit_time_left = 0.85
		orb.dash_after_orbit = true
		orb.dash_target = cage_center
		orb.dash_speed = 390.0
		orb.set_sprite("res://assets/sprites/bossbullut-7.png")
		get_parent().add_child(orb)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.06).timeout

	# Phase 2: DECELERATE bullets from 8 screen positions converging on player
	if not player or not is_instance_valid(player):
		return
	var decel_spawns = [
		Vector2(vp.x * 0.12, 15.0), Vector2(vp.x * 0.50, 15.0),
		Vector2(vp.x * 0.88, 15.0), Vector2(vp.x - 15.0, vp.y * 0.50),
		Vector2(vp.x * 0.88, vp.y - 15.0), Vector2(vp.x * 0.50, vp.y - 15.0),
		Vector2(vp.x * 0.12, vp.y - 15.0), Vector2(15.0, vp.y * 0.50),
	]
	for d_idx in range(decel_spawns.size()):
		if not player or not is_instance_valid(player):
			break
		var d_pos = decel_spawns[d_idx] as Vector2
		var to_player = d_pos.direction_to(player.global_position)
		for i in range(4):
			var spread = to_player.rotated((i - 1.5) * 0.12)
			var db = bullet_scene.instantiate() as EnemyBullet
			db.global_position = d_pos
			db.direction = spread
			db.speed = 310.0
			db.bullet_type = EnemyBullet.BulletType.DECELERATE
			db.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(db)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 3: HOMING from boss - 16 bullets fanning out then homing
	if not player or not is_instance_valid(player):
		return
	var homing_aim = global_position.direction_to(player.global_position).angle()
	for i in range(16):
		var spread = homing_aim + (i - 7.5) * 0.18
		var hb = bullet_scene.instantiate() as EnemyBullet
		hb.global_position = global_position
		hb.direction = Vector2(cos(spread), sin(spread))
		hb.speed = 250.0
		hb.bullet_type = EnemyBullet.BulletType.HOMING
		hb._homing_strength = 2.5
		hb._homing_duration = 0.7
		hb.set_sprite("res://assets/sprites/bossbullut-7.png")
		get_parent().add_child(hb)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 4: SINE_WAVE streams from 3 phantom positions aimed at player
	if not player or not is_instance_valid(player):
		return
	var phantom_origins = [
		Vector2(vp.x * 0.20, vp.y * 0.12),
		Vector2(vp.x * 0.50, vp.y * 0.08),
		Vector2(vp.x * 0.80, vp.y * 0.12),
	]
	for ph_idx in range(phantom_origins.size()):
		if not player or not is_instance_valid(player):
			break
		var ph_pos = phantom_origins[ph_idx] as Vector2
		var aim = ph_pos.direction_to(player.global_position).angle()
		for i in range(10):
			var wobble = sin(i * 0.65) * 0.12
			var sine_b = bullet_scene.instantiate() as EnemyBullet
			sine_b.global_position = ph_pos
			sine_b.direction = Vector2(cos(aim + wobble), sin(aim + wobble))
			sine_b.speed = 270.0 + i * 8.0
			sine_b.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			sine_b.wave_amplitude = 38.0
			sine_b.wave_frequency = 4.5
			sine_b.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(sine_b)
			if i % 5 == 4:
				await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 5: Final aimed SPLIT burst - 12 split bullets at player
	if not player or not is_instance_valid(player):
		return
	var final_aim = global_position.direction_to(player.global_position).angle()
	for i in range(12):
		var spread = final_aim + (i - 5.5) * 0.13
		var split_b = bullet_scene.instantiate() as EnemyBullet
		split_b.global_position = global_position
		split_b.direction = Vector2(cos(spread), sin(spread))
		split_b.speed = 310.0 + i * 7.0
		split_b.bullet_type = EnemyBullet.BulletType.SPLIT
		split_b.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(split_b)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout


func _boss5_grand_explosion() -> void:
	# Super multi-phase grand explosion:
	# Phase 1: 6 phantom positions fire aimed fans at player (10 per position = 60).
	# Phase 2: BOUNCE bullets from all 4 corners (8 per corner = 32).
	# Phase 3: Triple SPIRAL arms from boss.
	# Phase 4: Dense aimed fan burst (30 bullets) + DECELERATE minefield.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: 6 phantom positions fire aimed fans at player - 10 per position
	var phantom_spots = [
		Vector2(vp.x * 0.10, vp.y * 0.15),
		Vector2(vp.x * 0.35, vp.y * 0.08),
		Vector2(vp.x * 0.65, vp.y * 0.08),
		Vector2(vp.x * 0.90, vp.y * 0.15),
		Vector2(vp.x * 0.20, vp.y * 0.90),
		Vector2(vp.x * 0.80, vp.y * 0.90),
	]
	for ph_idx in range(phantom_spots.size()):
		if not player or not is_instance_valid(player):
			break
		var ph_pos = phantom_spots[ph_idx] as Vector2
		var aim = ph_pos.direction_to(player.global_position).angle()
		for i in range(10):
			var spread = aim + (i - 4.5) * 0.10
			var fb = bullet_scene.instantiate() as EnemyBullet
			fb.global_position = ph_pos
			fb.direction = Vector2(cos(spread), sin(spread))
			fb.speed = 300.0 + i * 5.0
			fb.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(fb)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 2: BOUNCE bullets from all 4 corners - 8 per corner
	if not player or not is_instance_valid(player):
		return
	var corners = [
		Vector2(25.0, 25.0),
		Vector2(vp.x - 25.0, 25.0),
		Vector2(25.0, vp.y - 25.0),
		Vector2(vp.x - 25.0, vp.y - 25.0),
	]
	for c_idx in range(corners.size()):
		if not player or not is_instance_valid(player):
			break
		var c_pos = corners[c_idx] as Vector2
		var aim_c = c_pos.direction_to(player.global_position).angle()
		for i in range(8):
			var spread = aim_c + (i - 3.5) * 0.14
			var bb = bullet_scene.instantiate() as EnemyBullet
			bb.global_position = c_pos
			bb.direction = Vector2(cos(spread), sin(spread))
			bb.speed = 280.0 + i * 10.0
			bb.bullet_type = EnemyBullet.BulletType.BOUNCE
			bb.set_sprite("res://assets/sprites/bossbullut-14.png")
			get_parent().add_child(bb)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 3: Triple SPIRAL arms from boss
	if not player or not is_instance_valid(player):
		return
	var spiral_base = global_position.direction_to(player.global_position).angle()
	for step in range(18):
		for arm in range(3):
			var angle = spiral_base + arm * (TAU / 3.0) + step * 0.22
			var sp_b = bullet_scene.instantiate() as EnemyBullet
			sp_b.global_position = global_position
			sp_b.direction = Vector2(cos(angle), sin(angle))
			sp_b.speed = 260.0 + step * 8.0
			sp_b.bullet_type = EnemyBullet.BulletType.SPIRAL
			sp_b.set_sprite("res://assets/sprites/bossbullut-2.png")
			get_parent().add_child(sp_b)
		await get_tree().create_timer(0.03).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 4: Dense aimed fan burst (30 bullets) + DECELERATE minefield
	if not player or not is_instance_valid(player):
		return
	var fan_aim = global_position.direction_to(player.global_position).angle()
	for i in range(30):
		var spread = fan_aim + (i - 14.5) * 0.065
		var fan_b = bullet_scene.instantiate() as EnemyBullet
		fan_b.global_position = global_position
		fan_b.direction = Vector2(cos(spread), sin(spread))
		fan_b.speed = 340.0 + i * 3.0
		fan_b.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(fan_b)
		if i % 6 == 5:
			await get_tree().create_timer(0.02).timeout
	# DECELERATE minefield around player
	if not player or not is_instance_valid(player):
		return
	var mine_center = player.global_position
	for i in range(16):
		var angle = (TAU / 16.0) * i
		var mine_pos = mine_center + Vector2(cos(angle), sin(angle)) * randf_range(80.0, 200.0)
		var mine_dir = mine_center.direction_to(mine_pos).normalized()
		var mine_b = bullet_scene.instantiate() as EnemyBullet
		mine_b.global_position = mine_center
		mine_b.direction = mine_dir
		mine_b.speed = 220.0
		mine_b.bullet_type = EnemyBullet.BulletType.DECELERATE
		mine_b.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(mine_b)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout


func _boss5_final_detonation() -> void:
	# THE ULTIMATE - Super multi-phase final detonation:
	# Phase 1: Chaos spray + aimed fan simultaneously.
	# Phase 2: Rain from top + HOMING from edges.
	# Phase 3: Orbit cage + LASER from boss.
	# Phase 4: SPLIT streams from 4 positions + DECELERATE traps.
	# Phase 5: Everything at once - aimed burst + edge summoning + spiral + orbit cage + HOMING.
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return
	var vp = get_viewport_rect().size

	# Phase 1: Chaos spray + aimed fan simultaneously
	# Chaos spray - 20 random direction bullets from boss
	for i in range(20):
		var chaos_angle = randf_range(0.0, TAU)
		var chaos_b = bullet_scene.instantiate() as EnemyBullet
		chaos_b.global_position = global_position
		chaos_b.direction = Vector2(cos(chaos_angle), sin(chaos_angle))
		chaos_b.speed = randf_range(240.0, 380.0)
		chaos_b.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(chaos_b)
	# Aimed fan - 16 bullets at player
	if not player or not is_instance_valid(player):
		return
	var fan_aim = global_position.direction_to(player.global_position).angle()
	for i in range(16):
		var spread = fan_aim + (i - 7.5) * 0.08
		var fan_b = bullet_scene.instantiate() as EnemyBullet
		fan_b.global_position = global_position
		fan_b.direction = Vector2(cos(spread), sin(spread))
		fan_b.speed = 320.0 + i * 5.0
		fan_b.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(fan_b)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.05).timeout

	# Phase 2: Rain from top + HOMING from edges
	if not player or not is_instance_valid(player):
		return
	var rain_target = player.global_position
	for i in range(20):
		var x_pos = rain_target.x + randf_range(-380, 380)
		x_pos = clampf(x_pos, 20, vp.x - 20)
		var rain_b = bullet_scene.instantiate() as EnemyBullet
		rain_b.global_position = Vector2(x_pos, 15.0)
		rain_b.direction = (rain_target - rain_b.global_position).normalized()
		rain_b.speed = randf_range(290.0, 380.0)
		rain_b.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(rain_b)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout
	# HOMING from left and right edges
	if not player or not is_instance_valid(player):
		return
	for i in range(8):
		var y_pos = vp.y * (0.1 + i * 0.1)
		for side in [15.0, vp.x - 15.0]:
			var hb = bullet_scene.instantiate() as EnemyBullet
			hb.global_position = Vector2(side, y_pos)
			hb.direction = hb.global_position.direction_to(player.global_position)
			hb.speed = 260.0
			hb.bullet_type = EnemyBullet.BulletType.HOMING
			hb._homing_strength = 2.6
			hb._homing_duration = 0.65
			hb.set_sprite("res://assets/sprites/bossbullut-7.png")
			get_parent().add_child(hb)
		await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 3: Orbit cage + LASER from boss
	if not player or not is_instance_valid(player):
		return
	var cage_center_p3 = player.global_position
	for i in range(14):
		var angle = (TAU / 14.0) * i
		var spawn_pos = cage_center_p3 + Vector2(cos(angle), sin(angle)) * 125.0
		var orb = bullet_scene.instantiate() as EnemyBullet
		orb.global_position = spawn_pos
		orb.direction = Vector2.ZERO
		orb.speed = 0.0
		orb.orbit_center = cage_center_p3
		orb.orbit_radius = 125.0
		orb.orbit_angle = angle
		orb.orbit_angular_speed = 8.0
		orb.orbit_time_left = 0.75
		orb.dash_after_orbit = true
		orb.dash_target = cage_center_p3
		orb.dash_speed = 400.0
		orb.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(orb)
		if i % 7 == 6:
			await get_tree().create_timer(0.02).timeout
	# LASER from boss - 6 beams x 5 bullets
	if not player or not is_instance_valid(player):
		return
	var laser_aim = global_position.direction_to(player.global_position).angle()
	for beam in range(6):
		var beam_angle = laser_aim + beam * (TAU / 6.0)
		for i in range(5):
			var lb = bullet_scene.instantiate() as EnemyBullet
			lb.global_position = global_position
			lb.direction = Vector2(cos(beam_angle), sin(beam_angle))
			lb.speed = 330.0 + i * 25.0
			lb.bullet_type = EnemyBullet.BulletType.LASER
			lb.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(lb)
		await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 4: SPLIT streams from 4 positions + DECELERATE traps
	if not player or not is_instance_valid(player):
		return
	var split_positions = [
		Vector2(vp.x * 0.20, 15.0),
		Vector2(vp.x * 0.80, 15.0),
		Vector2(15.0, vp.y * 0.50),
		Vector2(vp.x - 15.0, vp.y * 0.50),
	]
	for sp_idx in range(split_positions.size()):
		if not player or not is_instance_valid(player):
			break
		var sp_pos = split_positions[sp_idx] as Vector2
		var aim = sp_pos.direction_to(player.global_position).angle()
		for i in range(6):
			var spread = aim + (i - 2.5) * 0.12
			var sb = bullet_scene.instantiate() as EnemyBullet
			sb.global_position = sp_pos
			sb.direction = Vector2(cos(spread), sin(spread))
			sb.speed = 300.0 + i * 8.0
			sb.bullet_type = EnemyBullet.BulletType.SPLIT
			sb.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(sb)
		await get_tree().create_timer(0.02).timeout
	# DECELERATE traps around player
	if not player or not is_instance_valid(player):
		return
	var trap_center = player.global_position
	for i in range(12):
		var angle = (TAU / 12.0) * i
		var trap_b = bullet_scene.instantiate() as EnemyBullet
		trap_b.global_position = trap_center + Vector2(cos(angle), sin(angle)) * 50.0
		trap_b.direction = Vector2(cos(angle), sin(angle))
		trap_b.speed = 240.0
		trap_b.bullet_type = EnemyBullet.BulletType.DECELERATE
		trap_b.set_sprite("res://assets/sprites/bossbullut-10.png")
		get_parent().add_child(trap_b)
		if i % 4 == 3:
			await get_tree().create_timer(0.02).timeout

	await get_tree().create_timer(0.04).timeout

	# Phase 5: EVERYTHING AT ONCE - the ultimate detonation
	# Aimed burst from boss
	if not player or not is_instance_valid(player):
		return
	var ult_aim = global_position.direction_to(player.global_position).angle()
	for i in range(12):
		var spread = ult_aim + (i - 5.5) * 0.10
		var ub = bullet_scene.instantiate() as EnemyBullet
		ub.global_position = global_position
		ub.direction = Vector2(cos(spread), sin(spread))
		ub.speed = 350.0 + i * 4.0
		ub.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(ub)
	await get_tree().create_timer(0.02).timeout
	# Edge summoning - bullets from all 4 edges aimed at player
	if not player or not is_instance_valid(player):
		return
	for i in range(6):
		var x_top = vp.x * (0.1 + i * 0.15)
		var eb_t = bullet_scene.instantiate() as EnemyBullet
		eb_t.global_position = Vector2(x_top, 15.0)
		eb_t.direction = eb_t.global_position.direction_to(player.global_position)
		eb_t.speed = 330.0
		eb_t.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(eb_t)
		var eb_b = bullet_scene.instantiate() as EnemyBullet
		eb_b.global_position = Vector2(x_top, vp.y - 15.0)
		eb_b.direction = eb_b.global_position.direction_to(player.global_position)
		eb_b.speed = 330.0
		eb_b.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(eb_b)
	for i in range(5):
		var y_side = vp.y * (0.15 + i * 0.17)
		var eb_l = bullet_scene.instantiate() as EnemyBullet
		eb_l.global_position = Vector2(15.0, y_side)
		eb_l.direction = eb_l.global_position.direction_to(player.global_position)
		eb_l.speed = 330.0
		eb_l.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(eb_l)
		var eb_r = bullet_scene.instantiate() as EnemyBullet
		eb_r.global_position = Vector2(vp.x - 15.0, y_side)
		eb_r.direction = eb_r.global_position.direction_to(player.global_position)
		eb_r.speed = 330.0
		eb_r.set_sprite("res://assets/sprites/bossbullut-2.png")
		get_parent().add_child(eb_r)
	await get_tree().create_timer(0.02).timeout
	# Spiral arms from boss - 2 arms, 12 steps
	if not player or not is_instance_valid(player):
		return
	var spiral_aim = global_position.direction_to(player.global_position).angle()
	for step in range(12):
		for arm in range(2):
			var angle = spiral_aim + arm * PI + step * 0.28
			var sp = bullet_scene.instantiate() as EnemyBullet
			sp.global_position = global_position
			sp.direction = Vector2(cos(angle), sin(angle))
			sp.speed = 280.0 + step * 10.0
			sp.bullet_type = EnemyBullet.BulletType.SPIRAL
			sp.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(sp)
		await get_tree().create_timer(0.02).timeout
	# Orbit cage around player - 12 bullets
	if not player or not is_instance_valid(player):
		return
	var final_cage = player.global_position
	for i in range(12):
		var angle = (TAU / 12.0) * i
		var spawn_pos = final_cage + Vector2(cos(angle), sin(angle)) * 110.0
		var orb = bullet_scene.instantiate() as EnemyBullet
		orb.global_position = spawn_pos
		orb.direction = Vector2.ZERO
		orb.speed = 0.0
		orb.orbit_center = final_cage
		orb.orbit_radius = 110.0
		orb.orbit_angle = angle
		orb.orbit_angular_speed = 9.0
		orb.orbit_time_left = 0.65
		orb.dash_after_orbit = true
		orb.dash_target = final_cage
		orb.dash_speed = 400.0
		orb.set_sprite("res://assets/sprites/bossbullut-7.png")
		get_parent().add_child(orb)
	await get_tree().create_timer(0.02).timeout
	# Final HOMING barrage - 10 bullets from boss
	if not player or not is_instance_valid(player):
		return
	var homing_base = global_position.direction_to(player.global_position).angle()
	for i in range(10):
		var spread = homing_base + (i - 4.5) * 0.22
		var hb = bullet_scene.instantiate() as EnemyBullet
		hb.global_position = global_position
		hb.direction = Vector2(cos(spread), sin(spread))
		hb.speed = 270.0
		hb.bullet_type = EnemyBullet.BulletType.HOMING
		hb._homing_strength = 3.0
		hb._homing_duration = 0.8
		hb.set_sprite("res://assets/sprites/bossbullut-7.png")
		get_parent().add_child(hb)
		if i % 5 == 4:
			await get_tree().create_timer(0.02).timeout

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
	await get_tree().create_timer(0.15).timeout
	await _danmaku_pentagram(130.0, 12, 11.0, "res://assets/sprites/bossbullut-10.png")

func _boss6_final_judgment() -> void:
	# 最终审判 - 激光扫射+追踪雨
	await _danmaku_laser_sweep(0.0, TAU, 3.0, 5, 17.0, "res://assets/sprites/bossbullut-5.png")
	await get_tree().create_timer(0.3).timeout
	await _danmaku_tracking_rain(25, 0.08, 13.0, "res://assets/sprites/bossbullut-11.png")

func _boss6_chaos_dimension() -> void:
	# 混沌次元 - 随机散射+网格+爆炸环
	await _danmaku_random_spray(35, 6.0, 15.0, "res://assets/sprites/bossbullut-1.png")
	await get_tree().create_timer(0.15).timeout
	await _danmaku_grid(6, 10, 40.0, 9.0, "res://assets/sprites/bossbullut-6.png")
	await get_tree().create_timer(0.15).timeout
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
	await get_tree().create_timer(0.40).timeout

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
	await get_tree().create_timer(0.18).timeout

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
	await get_tree().create_timer(0.18).timeout

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
	# Dense fire rain aimed at player area
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for wave in range(8):
		var target_x = player.global_position.x if player else 450.0
		for i in range(16):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(
				target_x + randf_range(-250.0, 250.0),
				40.0
			)
			var angle = PI / 2.0 + randf_range(-0.2, 0.2)
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = randf_range(220.0, 340.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss6_inferno_spiral() -> void:
	# Triple interleaving fire spirals + aimed bursts
	if not bullet_scene or not get_parent():
		return
	var token := _phase_token
	for step in range(48):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		for arm in range(3):
			var base_angle = step * 0.175 + arm * (TAU / 3.0)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(base_angle), sin(base_angle))
			bullet.speed = 220.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			get_parent().add_child(bullet)
		if step % 8 == 0:
			var player := _get_player_safe()
			if player:
				var aim = global_position.direction_to(player.global_position).angle()
				for i in range(5):
					var bullet = bullet_scene.instantiate() as EnemyBullet
					bullet.global_position = global_position
					bullet.direction = Vector2(cos(aim + (i - 2) * 0.15), sin(aim + (i - 2) * 0.15))
					bullet.speed = 300.0
					bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
					get_parent().add_child(bullet)
		await get_tree().create_timer(0.04).timeout
		if _pattern_should_abort(token):
			return

func _boss6_flame_wheel() -> void:
	# Rotating fire wheel that tracks player
	if not bullet_scene or not get_parent():
		return
	var token := _phase_token
	for rotation in range(12):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var aim_offset = 0.0
		var player := _get_player_safe()
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		for spoke in range(20):
			var angle = spoke * (TAU / 20.0) + rotation * 0.3 + aim_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0 + rotation * 8.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout
		if _pattern_should_abort(token):
			return

func _boss6_ember_scatter() -> void:
	# Rapid aimed ember spray with homing
	if not bullet_scene or not get_parent():
		return
	var token := _phase_token
	for burst in range(10):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return
		var aim_angle = global_position.direction_to(player.global_position).angle()
		for i in range(14):
			var spread = randf_range(-0.5, 0.5)
			var angle = aim_angle + spread
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = randf_range(200.0, 350.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			if i < 3:
				bullet.bullet_type = EnemyBullet.BulletType.HOMING
				bullet._homing_strength = 1.5
				bullet._homing_duration = 0.5
			else:
				bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout
		if _pattern_should_abort(token):
			return

func _boss6_blaze_wave() -> void:
	# Fast sweeping fire walls from screen edges
	if not bullet_scene or not get_parent():
		return
	for wave in range(10):
		var direction_sign = 1.0 if wave % 2 == 0 else -1.0
		var start_x = 50.0 if direction_sign > 0 else 850.0
		for i in range(18):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(start_x, 80 + i * 30.0)
			bullet.direction = Vector2(direction_sign, randf_range(-0.1, 0.1)).normalized()
			bullet.speed = 280.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss6_fire_serpent() -> void:
	# Fast curving fire snakes aimed at player
	if not bullet_scene or not get_parent():
		return
	var token := _phase_token
	for serpent in range(6):
		if _pattern_should_abort(token):
			return
		while GameManager.time_stop_active and GameManager.time_stop_freeze_boss:
			if _pattern_should_abort(token):
				return
			await get_tree().create_timer(0.1).timeout

		var player := _get_player_safe()
		if not player:
			return
		var base_angle = global_position.direction_to(player.global_position).angle()
		base_angle += serpent * 0.35 - 0.875
		for segment in range(16):
			if _pattern_should_abort(token):
				return
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			var wobble = sin(segment * 0.8) * 0.25
			bullet.direction = Vector2(cos(base_angle + wobble), sin(base_angle + wobble))
			bullet.speed = 220.0 + segment * 8.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.02).timeout
			if _pattern_should_abort(token):
				return
		await get_tree().create_timer(0.08).timeout
		if _pattern_should_abort(token):
			return

func _boss6_magma_burst() -> void:
	# Explosive rings + aimed homing center
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for ring in range(7):
		var bullet_count = 20 + ring * 4
		var ring_offset = ring * 0.12
		for i in range(bullet_count):
			var angle = i * (TAU / bullet_count) + ring_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 160.0 + ring * 25.0
			bullet.set_sprite("res://assets/sprites/bossbullut-1.png")
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			get_parent().add_child(bullet)
		if player and ring % 2 == 0:
			var aim = global_position.direction_to(player.global_position).angle()
			for i in range(8):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(aim + (i - 3.5) * 0.1), sin(aim + (i - 3.5) * 0.1))
				bullet.speed = 320.0
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				bullet.bullet_type = EnemyBullet.BulletType.HOMING
				bullet._homing_strength = 1.0
				bullet._homing_duration = 0.3
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss6_volcanic_eruption() -> void:
	# Bullets erupt upward then rain down on player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for burst in range(6):
		var target_x = player.global_position.x if player else 450.0
		for i in range(18):
			var spread_angle = -PI / 2.0 + randf_range(-0.6, 0.6)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(target_x + randf_range(-100, 100), 50)
			bullet.direction = Vector2(cos(spread_angle), sin(spread_angle))
			bullet.speed = randf_range(250.0, 380.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			bullet.bullet_type = EnemyBullet.BulletType.DECELERATE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss6_heat_haze() -> void:
	# Sine wave bullets aimed at player from multiple angles
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for wave in range(12):
		var aim = global_position.direction_to(player.global_position).angle()
		for i in range(10):
			var angle = aim + (i - 4.5) * 0.18
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 220.0 + wave * 5.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			bullet.bullet_type = EnemyBullet.BulletType.SINE_WAVE
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout

func _boss6_pyroclastic_flow() -> void:
	# Dense flowing fire from all screen edges toward player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for wave in range(8):
		# Top edge
		for i in range(12):
			var x_pos = 80 + i * 65.0
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 40)
			var aim_dir = Vector2(0, 1)
			if player:
				aim_dir = (player.global_position - bullet.global_position).normalized()
			bullet.direction = aim_dir.rotated(randf_range(-0.15, 0.15))
			bullet.speed = randf_range(200.0, 300.0)
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			get_parent().add_child(bullet)
		# Side edges
		for i in range(6):
			var y_pos = 100 + i * 80.0
			for side in [-1, 1]:
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = Vector2(50 if side < 0 else 850, y_pos)
				var aim_dir = Vector2(side * -1, 0)
				if player:
					aim_dir = (player.global_position - bullet.global_position).normalized()
				bullet.direction = aim_dir
				bullet.speed = 260.0
				bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

# =============================================================================
# SPELL 1 - Pentagram Patterns (10 skills)
# =============================================================================

func _boss6_pentagram_seal() -> void:
	# Five-pointed star burst aimed at player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for rotation in range(8):
		var aim_offset = 0.0
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		for point in range(5):
			var base_angle = (TAU / 5) * point + rotation * 0.25 + aim_offset
			for i in range(12):
				var angle = base_angle + (i - 5.5) * 0.06
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(angle), sin(angle))
				bullet.speed = 240.0 + i * 8.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.18).timeout

func _boss6_hexagram_bind() -> void:
	# Six-pointed star that traps player area
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for rotation in range(6):
		var center = player.global_position
		# Triangle 1
		for point in range(3):
			var angle = (TAU / 3) * point + rotation * 0.2
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * 280
			for i in range(10):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = spawn_pos
				bullet.direction = (center - spawn_pos).normalized().rotated((i - 4.5) * 0.08)
				bullet.speed = 220.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
		# Triangle 2 (inverted)
		for point in range(3):
			var angle = (TAU / 3) * point + PI / 3 + rotation * 0.2
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * 280
			for i in range(10):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = spawn_pos
				bullet.direction = (center - spawn_pos).normalized().rotated((i - 4.5) * 0.08)
				bullet.speed = 220.0
				bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.25).timeout

func _boss6_sacred_geometry() -> void:
	# Geometric patterns aimed at player with increasing complexity
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for polygon in range(6):
		var sides = 3 + polygon % 4
		var bullets_per_side = 10
		var aim_offset = 0.0
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		for side in range(sides):
			var start_angle = (TAU / sides) * side + aim_offset
			var end_angle = (TAU / sides) * (side + 1) + aim_offset
			for i in range(bullets_per_side):
				var t = float(i) / bullets_per_side
				var angle = lerp(start_angle, end_angle, t)
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(angle), sin(angle))
				bullet.speed = 220.0 + polygon * 15.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss6_runic_circle() -> void:
	# Circular runes that spawn around player and close in
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for circle in range(5):
		var center = player.global_position
		var radius = 320.0 - circle * 40.0
		var count = 28 + circle * 6
		for i in range(count):
			var angle = (TAU / count) * i + circle * 0.1
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * radius
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = (center - spawn_pos).normalized()
			bullet.speed = 180.0 + circle * 20.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.20).timeout

func _boss6_sigil_storm() -> void:
	# Sigils spawn at screen edges and fire at player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for sigil in range(10):
		var sigil_pos = Vector2(
			100 + randf() * 700,
			50 + randf() * 100
		)
		if sigil % 3 == 1:
			sigil_pos = Vector2(50, 100 + randf() * 400)
		elif sigil % 3 == 2:
			sigil_pos = Vector2(850, 100 + randf() * 400)
		var aim_dir = (player.global_position - sigil_pos).normalized()
		for i in range(16):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = sigil_pos
			bullet.direction = aim_dir.rotated((i - 7.5) * 0.08)
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss6_arcane_web() -> void:
	# Web of magic bullets with homing center
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for layer in range(8):
		# Radial aimed lines
		var aim_offset = 0.0
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		for i in range(16):
			var angle = (TAU / 16) * i + layer * 0.12 + aim_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 220.0 + layer * 8.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		# Homing center bullets
		if player and layer % 2 == 0:
			for i in range(4):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				var aim = global_position.direction_to(player.global_position).angle()
				bullet.direction = Vector2(cos(aim + (i - 1.5) * 0.3), sin(aim + (i - 1.5) * 0.3))
				bullet.speed = 280.0
				bullet.bullet_type = EnemyBullet.BulletType.HOMING
				bullet._homing_strength = 2.0
				bullet._homing_duration = 0.6
				bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss6_mystic_spiral() -> void:
	# Fast dual spiral with aimed interleave
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for i in range(100):
		for arm in range(3):
			var angle = i * 0.3 + arm * TAU / 3
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 240.0
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		if i % 12 == 0 and player:
			var aim = global_position.direction_to(player.global_position).angle()
			for j in range(8):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(aim + (j - 3.5) * 0.12), sin(aim + (j - 3.5) * 0.12))
				bullet.speed = 320.0
				bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.03).timeout

func _boss6_enchant_ring() -> void:
	# Enchanted rings that converge on player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for ring in range(10):
		var center = player.global_position
		var count = 24 + ring * 2
		var radius = 300.0
		var offset = ring * 0.25
		for i in range(count):
			var angle = (TAU / count) * i + offset
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * radius
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = (center - spawn_pos).normalized()
			bullet.speed = 200.0 + ring * 10.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss6_spell_weave() -> void:
	# Interlocking aimed patterns
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for weave in range(10):
		var aim_offset = 0.0
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		# Pattern A: clockwise aimed
		for i in range(20):
			var angle = (TAU / 20) * i + weave * 0.25 + aim_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 240.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
		# Pattern B: counter-clockwise
		for i in range(20):
			var angle = (TAU / 20) * i - weave * 0.25
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout

func _boss6_grimoire_page() -> void:
	# Bullet walls from screen edges aimed at player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for page in range(6):
		var side = 1 if page % 2 == 0 else -1
		var start_x = 50.0 if side > 0 else 850.0
		for row in range(10):
			for col in range(4):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = Vector2(
					start_x,
					80 + row * 50 + col * 12
				)
				var aim_dir = Vector2(float(side) * -1, 0)
				if player:
					aim_dir = (player.global_position - bullet.global_position).normalized()
				bullet.direction = aim_dir.rotated(col * 0.05 * side)
				bullet.speed = 250.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.18).timeout

# =============================================================================
# NONSPELL 2 - Convergence Patterns (10 skills)
# =============================================================================

func _boss6_convergence_beam() -> void:
	# Converging beams from screen corners aimed at player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	var corners = [Vector2(50, 50), Vector2(850, 50), Vector2(50, 600), Vector2(850, 600)]
	for beam in range(10):
		for corner in corners:
			var aim_dir = (player.global_position - corner).normalized()
			for i in range(10):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = corner
				bullet.direction = aim_dir.rotated((i - 4.5) * 0.08)
				bullet.speed = 280.0 + i * 5.0
				bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss6_cross_fire() -> void:
	# Cross-shaped fire that rotates toward player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for cross in range(8):
		var aim_offset = 0.0
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		for arm in range(4):
			var base_angle = arm * PI / 2 + cross * 0.2 + aim_offset
			for i in range(15):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(base_angle), sin(base_angle))
				bullet.speed = 180.0 + i * 12.0
				bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss6_pincer_attack() -> void:
	# Bullets from both screen sides closing on player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for pincer in range(8):
		var target = player.global_position
		# Left wall
		for i in range(16):
			var y_pos = target.y + (i - 7.5) * 25
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(50, y_pos)
			bullet.direction = (target - bullet.global_position).normalized()
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		# Right wall
		for i in range(16):
			var y_pos = target.y + (i - 7.5) * 25
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(850, y_pos)
			bullet.direction = (target - bullet.global_position).normalized()
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.18).timeout

func _boss6_encirclement() -> void:
	# Tightening rings around player with gaps
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for ring in range(6):
		var center = player.global_position
		var radius = 350.0 - ring * 40.0
		var count = 32 + ring * 4
		var gap_angle = randf() * TAU
		for i in range(count):
			var angle = (TAU / count) * i
			if abs(angle - gap_angle) < 0.4 or abs(angle - gap_angle + TAU) < 0.4 or abs(angle - gap_angle - TAU) < 0.4:
				continue
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * radius
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = (center - spawn_pos).normalized()
			bullet.speed = 160.0 + ring * 15.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.20).timeout

func _boss6_vortex_pull() -> void:
	# Pulling vortex centered on player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for vortex in range(5):
		var center = player.global_position if player else Vector2(450, 350)
		for i in range(48):
			var angle = i * 0.45 + vortex * 1.2
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * 350
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = (center - spawn_pos).normalized().rotated(0.3)
			bullet.speed = 240.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
			await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.10).timeout

func _boss6_dimension_rift() -> void:
	# Bullets from random screen positions aimed at player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for rift in range(12):
		var rift_pos = Vector2(80 + randf() * 740, 50 + randf() * 500)
		var aim_dir = (player.global_position - rift_pos).normalized()
		for i in range(14):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = rift_pos
			bullet.direction = aim_dir.rotated((i - 6.5) * 0.1)
			bullet.speed = 280.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss6_gravity_well() -> void:
	# Gravity bullets that curve toward player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for well in range(8):
		var aim_offset = 0.0
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		for i in range(32):
			var angle = (TAU / 32) * i + aim_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 240.0
			bullet.bullet_type = EnemyBullet.BulletType.CURVE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss6_time_warp_bullets() -> void:
	# Speed-varying aimed bullets
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for warp in range(10):
		var aim_offset = 0.0
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		for i in range(28):
			var angle = (TAU / 28) * i + aim_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 160.0 + (i % 7) * 35.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss6_mirror_dimension() -> void:
	# Mirrored patterns aimed at player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for mirror in range(8):
		var aim = 0.0
		if player:
			aim = global_position.direction_to(player.global_position).angle()
		for i in range(24):
			var angle = i * 0.25
			# Original aimed
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle + aim), sin(angle + aim))
			bullet.speed = 240.0
			bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
			get_parent().add_child(bullet)
			# Mirror
			var mirror_bullet = bullet_scene.instantiate() as EnemyBullet
			mirror_bullet.global_position = global_position
			mirror_bullet.direction = Vector2(cos(-angle + aim), sin(-angle + aim))
			mirror_bullet.speed = 240.0
			mirror_bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(mirror_bullet)
			await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.10).timeout

func _boss6_phase_shift() -> void:
	# Rapid alternating aimed patterns
	if not bullet_scene or not get_parent():
		return
	for shift in range(10):
		var player = get_tree().get_first_node_in_group("player")
		if shift % 2 == 0:
			# Phase A: aimed rings
			var aim_offset = 0.0
			if player:
				aim_offset = global_position.direction_to(player.global_position).angle()
			for i in range(28):
				var angle = (TAU / 28) * i + aim_offset
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(angle), sin(angle))
				bullet.speed = 260.0
				bullet.set_sprite("res://assets/sprites/bossbullut-3.png")
				get_parent().add_child(bullet)
		else:
			# Phase B: dense aimed fan
			if player:
				var aim = global_position.direction_to(player.global_position).angle()
				for i in range(18):
					var spread = aim + (i - 8.5) * 0.12
					var bullet = bullet_scene.instantiate() as EnemyBullet
					bullet.global_position = global_position
					bullet.direction = Vector2(cos(spread), sin(spread))
					bullet.speed = 300.0
					bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
					get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

# =============================================================================
# SPELL 2 - Cathedral Patterns (10 skills)
# =============================================================================

func _boss6_cathedral_pillars() -> void:
	# Vertical laser pillars that track player X
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for pillar in range(10):
		var x_pos = 450.0
		if player:
			x_pos = player.global_position.x + randf_range(-200, 200)
		x_pos = clamp(x_pos, 80, 820)
		for i in range(20):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 30 + i * 3)
			bullet.direction = Vector2(0, 1)
			bullet.speed = 320.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout

func _boss6_stained_glass() -> void:
	# Colorful aimed geometric patterns
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	var sprites = [
		"res://assets/sprites/bossbullut-1.png",
		"res://assets/sprites/bossbullut-3.png",
		"res://assets/sprites/bossbullut-5.png",
		"res://assets/sprites/bossbullut-6.png",
		"res://assets/sprites/bossbullut-9.png",
		"res://assets/sprites/bossbullut-11.png"
	]
	for pattern in range(8):
		var aim_offset = 0.0
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		for i in range(42):
			var angle = (TAU / 42) * i + pattern * 0.12 + aim_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 240.0
			bullet.set_sprite(sprites[i % sprites.size()])
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss6_holy_cross() -> void:
	# Cross-shaped laser aimed at player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for cross in range(6):
		var aim = 0.0
		if player:
			aim = global_position.direction_to(player.global_position).angle()
		var rotation = cross * PI / 6 + aim
		for arm in range(4):
			var arm_angle = rotation + arm * PI / 2
			for i in range(20):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(arm_angle), sin(arm_angle))
				bullet.speed = 150.0 + i * 12.0
				bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss6_divine_judgment_aimed() -> void:
	# Rapid aimed divine beams
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for judgment in range(12):
		var aim = global_position.direction_to(player.global_position).angle()
		for i in range(20):
			var spread = aim + (i - 9.5) * 0.08
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 320.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		# Side harassment
		for side in [-1, 1]:
			for i in range(6):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = Vector2(450 + side * 400, 50 + i * 80)
				bullet.direction = (player.global_position - bullet.global_position).normalized()
				bullet.speed = 250.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss6_angel_wings() -> void:
	# Wing-shaped fans aimed at player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for wing in range(8):
		var aim = 0.0
		if player:
			aim = global_position.direction_to(player.global_position).angle()
		# Left wing
		for i in range(18):
			var angle = aim + PI/2 + i * 0.06
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 240.0 + i * 4.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		# Right wing
		for i in range(18):
			var angle = aim - PI/2 - i * 0.06
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 240.0 + i * 4.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

func _boss6_heaven_gate() -> void:
	# Gate walls closing on player from sides
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for gate in range(6):
		var target = player.global_position
		# Left pillar
		for i in range(16):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(target.x - 250, target.y - 150 + i * 20)
			bullet.direction = Vector2(1, 0)
			bullet.speed = 220.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		# Right pillar
		for i in range(16):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(target.x + 250, target.y - 150 + i * 20)
			bullet.direction = Vector2(-1, 0)
			bullet.speed = 220.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		# Arch from above
		for i in range(20):
			var angle = PI + (TAU / 40) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(target.x, target.y - 200)
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.18).timeout

func _boss6_sacred_arrow() -> void:
	# Fast homing arrows at player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for arrow in range(14):
		var aim = global_position.direction_to(player.global_position).angle()
		# Arrow head - homing
		for i in range(7):
			var spread = aim + (i - 3) * 0.12
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 300.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 2.5
			bullet._homing_duration = 0.5
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		# Arrow trail
		for i in range(10):
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(aim), sin(aim))
			bullet.speed = 280.0 - i * 8.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout

func _boss6_blessing_rain() -> void:
	# Dense divine rain tracking player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for rain in range(10):
		var target_x = player.global_position.x if player else 450.0
		for i in range(30):
			var x_pos = target_x + randf_range(-300, 300)
			x_pos = clamp(x_pos, 60, 840)
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 30)
			bullet.direction = Vector2(sin(i * 0.3) * 0.15, 1).normalized()
			bullet.speed = 280.0 + randf() * 60.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout

func _boss6_choir_of_light() -> void:
	# Rhythmic aimed light bursts
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for choir in range(12):
		var aim_offset = 0.0
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		var count = 20 + (choir % 3) * 6
		for i in range(count):
			var angle = (TAU / count) * i + choir * 0.18 + aim_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout

func _boss6_sanctuary_seal() -> void:
	# Sealing rings around player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	for seal in range(5):
		var center = player.global_position
		# Inner ring
		for i in range(24):
			var angle = (TAU / 24) * i
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * 150
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = (center - spawn_pos).normalized()
			bullet.speed = 200.0
			bullet.set_sprite("res://assets/sprites/bossbullut-9.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
		# Middle ring
		for i in range(32):
			var angle = (TAU / 32) * i + 0.1
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * 250
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = (center - spawn_pos).normalized()
			bullet.speed = 230.0
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
		# Outer ring
		for i in range(40):
			var angle = (TAU / 40) * i + 0.2
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * 350
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = (center - spawn_pos).normalized()
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.15).timeout

# =============================================================================
# FINAL - Apocalypse (8 skills)
# =============================================================================

func _boss6_ragnarok() -> void:
	# All elements combined - multi-phase super attack
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	# Phase 1: Fire spiral aimed at player
	for i in range(40):
		var aim = 0.0
		if player:
			aim = global_position.direction_to(player.global_position).angle()
		var angle = i * 0.4 + aim
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 280.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
		get_parent().add_child(bullet)
		if i % 5 == 0:
			await get_tree().create_timer(0.02).timeout
	await get_tree().create_timer(0.08).timeout
	# Phase 2: Lightning burst from edges
	if player:
		for corner_idx in range(4):
			var corner = [Vector2(50, 50), Vector2(850, 50), Vector2(50, 600), Vector2(850, 600)][corner_idx]
			var aim_dir = (player.global_position - corner).normalized()
			for i in range(12):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = corner
				bullet.direction = aim_dir.rotated((i - 5.5) * 0.06)
				bullet.speed = 320.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				get_parent().add_child(bullet)
	await get_tree().create_timer(0.08).timeout
	# Phase 3: Gravity pull around player
	if player:
		for i in range(40):
			var angle = (TAU / 40) * i
			var spawn_pos = player.global_position + Vector2(cos(angle), sin(angle)) * 300
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = (player.global_position - spawn_pos).normalized()
			bullet.speed = 220.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)

func _boss6_genesis_wave() -> void:
	# Creation-level burst aimed at player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for wave in range(8):
		var aim_offset = 0.0
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		var count = 28 + wave * 6
		for i in range(count):
			var angle = (TAU / count) * i + aim_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 220.0 + wave * 20.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout

func _boss6_void_collapse() -> void:
	# Collapsing void centered on player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for collapse in range(6):
		var center = player.global_position if player else Vector2(450, 350)
		# Outward ring from boss
		for i in range(48):
			var angle = (TAU / 48) * i
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 300.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.08).timeout
		# Inward spiral toward player
		for i in range(36):
			var angle = i * 0.35 + collapse * 0.5
			var spawn_pos = center + Vector2(cos(angle), sin(angle)) * 350
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			bullet.direction = (center - spawn_pos).normalized()
			bullet.speed = 250.0
			bullet.bullet_type = EnemyBullet.BulletType.ACCELERATE
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss6_cosmic_storm() -> void:
	# Space-themed chaos from all directions
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for storm in range(8):
		# Random bursts aimed at player
		for i in range(36):
			var spawn_pos = Vector2(randf_range(50, 850), randf_range(50, 600))
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = spawn_pos
			var aim_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			if player:
				aim_dir = (player.global_position - spawn_pos).normalized().rotated(randf_range(-0.3, 0.3))
			bullet.direction = aim_dir
			bullet.speed = 220.0 + randf() * 100.0
			bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
			get_parent().add_child(bullet)
		# Spiral overlay from boss
		for i in range(20):
			var angle = storm * 0.6 + i * 0.35
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 280.0
			bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
			bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.12).timeout

func _boss6_eternal_flame() -> void:
	# Infinite fire spiral tracking player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for i in range(160):
		var aim_offset = 0.0
		if player and i % 20 == 0:
			aim_offset = global_position.direction_to(player.global_position).angle()
		for arm in range(5):
			var angle = i * 0.25 + arm * TAU / 5 + aim_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 260.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.02).timeout

func _boss6_omega_burst() -> void:
	# Ultimate burst - dense rings + aimed fans
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for burst in range(5):
		# Dense ring
		for i in range(72):
			var angle = (TAU / 72) * i + burst * 0.05
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 300.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
		# Aimed burst
		if player:
			var aim = global_position.direction_to(player.global_position).angle()
			for i in range(24):
				var spread = aim + (i - 11.5) * 0.08
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = global_position
				bullet.direction = Vector2(cos(spread), sin(spread))
				bullet.speed = 350.0
				bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
				bullet.bullet_type = EnemyBullet.BulletType.HOMING
				bullet._homing_strength = 1.5
				bullet._homing_duration = 0.3
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout

func _boss6_armageddon_rain() -> void:
	# Dense rain from all edges targeting player
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	for rain in range(8):
		# Top rain aimed at player
		for i in range(24):
			var x_pos = 60 + i * 34.0
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = Vector2(x_pos, 30)
			var aim_dir = Vector2(0, 1)
			if player:
				aim_dir = (player.global_position - bullet.global_position).normalized()
			bullet.direction = aim_dir.rotated(randf_range(-0.1, 0.1))
			bullet.speed = 300.0
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
		# Side bullets aimed at player
		for i in range(12):
			for side in [-1, 1]:
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = Vector2(50 if side < 0 else 850, 80 + i * 45)
				var aim_dir = Vector2(float(-side), 0)
				if player:
					aim_dir = (player.global_position - bullet.global_position).normalized()
				bullet.direction = aim_dir
				bullet.speed = 280.0
				bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
				get_parent().add_child(bullet)
		await get_tree().create_timer(0.10).timeout

func _boss6_final_revelation() -> void:
	# Ultimate combined pattern - all attack types
	if not bullet_scene or not get_parent():
		return
	var player = get_tree().get_first_node_in_group("player")
	# Phase 1: Aimed spiral
	for i in range(50):
		var aim = 0.0
		if player:
			aim = global_position.direction_to(player.global_position).angle()
		var angle = i * 0.35 + aim
		var bullet = bullet_scene.instantiate() as EnemyBullet
		bullet.global_position = global_position
		bullet.direction = Vector2(cos(angle), sin(angle))
		bullet.speed = 280.0
		bullet.bullet_type = EnemyBullet.BulletType.SPIRAL
		bullet.set_sprite("res://assets/sprites/bossbullut-11.png")
		get_parent().add_child(bullet)
		if i % 6 == 0:
			await get_tree().create_timer(0.02).timeout
	await get_tree().create_timer(0.06).timeout
	# Phase 2: Dense aimed rings
	for ring in range(4):
		var aim_offset = 0.0
		if player:
			aim_offset = global_position.direction_to(player.global_position).angle()
		for i in range(48):
			var angle = (TAU / 48) * i + ring * 0.1 + aim_offset
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(angle), sin(angle))
			bullet.speed = 250.0 + ring * 25.0
			bullet.set_sprite("res://assets/sprites/bossbullut-5.png")
			get_parent().add_child(bullet)
		await get_tree().create_timer(0.06).timeout
	# Phase 3: Homing barrage
	if player:
		var aim = global_position.direction_to(player.global_position).angle()
		for i in range(30):
			var spread = aim + (i - 14.5) * 0.08
			var bullet = bullet_scene.instantiate() as EnemyBullet
			bullet.global_position = global_position
			bullet.direction = Vector2(cos(spread), sin(spread))
			bullet.speed = 320.0
			bullet.bullet_type = EnemyBullet.BulletType.HOMING
			bullet._homing_strength = 2.0
			bullet._homing_duration = 0.5
			bullet.set_sprite("res://assets/sprites/bossbullut-6.png")
			get_parent().add_child(bullet)
	# Phase 4: Screen edge assault
	if player:
		for edge in range(4):
			var positions = [
				Vector2(randf_range(100, 800), 30),
				Vector2(randf_range(100, 800), 620),
				Vector2(30, randf_range(100, 550)),
				Vector2(870, randf_range(100, 550))
			]
			for i in range(8):
				var bullet = bullet_scene.instantiate() as EnemyBullet
				bullet.global_position = positions[edge]
				bullet.direction = (player.global_position - bullet.global_position).normalized()
				bullet.speed = 340.0
				bullet.set_sprite("res://assets/sprites/bossbullut-10.png")
				get_parent().add_child(bullet)
