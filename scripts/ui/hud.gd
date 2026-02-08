extends CanvasLayer

@onready var bottom_bar: Control = $BottomBar

@onready var score_label: Label = $BottomBar/MarginContainer/HBoxContainer/Stats/ScoreLabel
@onready var money_label: Label = $BottomBar/MarginContainer/HBoxContainer/Stats/MoneyLabel
@onready var game_time_label: Label = $BottomBar/MarginContainer/HBoxContainer/Stage/GameTimeLabel
@onready var bomb_label: Label = $BottomBar/MarginContainer/HBoxContainer/Loadout/BombLabel
@onready var shield_label: Label = $BottomBar/MarginContainer/HBoxContainer/Loadout/ShieldLabel
@onready var weapon_label: Label = $BottomBar/MarginContainer/HBoxContainer/Loadout/WeaponLabel
@onready var wave_label: Label = $BottomBar/MarginContainer/HBoxContainer/Stage/WaveLabel
@onready var boss_in_label: Label = $BottomBar/MarginContainer/HBoxContainer/Stage/BossInLabel
@onready var combo_label: Label = $BottomBar/MarginContainer/HBoxContainer/Stats/ComboLabel
@onready var achievement_label: Label = $AchievementLabel
@onready var health_bar: ProgressBar = $BottomBar/MarginContainer/HBoxContainer/Player/HealthBar
@onready var health_label: Label = $BottomBar/MarginContainer/HBoxContainer/Player/HealthBar/HealthLabel
@onready var power_bar: ProgressBar = $BottomBar/MarginContainer/HBoxContainer/Player/PowerBar
@onready var pause_menu: Control = $PauseMenu
@onready var game_over_screen: Control = $GameOverScreen
@onready var final_score_label: Label = $GameOverScreen/VBoxContainer/FinalScoreLabel

# Boss UI
@onready var boss_bar: MarginContainer = $BossBar
@onready var boss_name_label: Label = $BossBar/VBoxContainer/BossNameLabel
@onready var boss_phase_label: Label = $BossBar/VBoxContainer/BossPhaseRow/BossPhaseLabel
@onready var boss_timer_label: Label = $BossBar/VBoxContainer/BossPhaseRow/BossTimerLabel
@onready var spell_bonus_row: HBoxContainer = $BossBar/VBoxContainer/SpellBonusRow
@onready var spell_bonus_value_label: Label = $BossBar/VBoxContainer/SpellBonusRow/SpellBonusValueLabel
@onready var boss_health_bar: ProgressBar = $BossBar/VBoxContainer/BossHealthBar
@onready var boss_health_label: Label = $BossBar/VBoxContainer/BossHealthBar/BossHealthLabel
@onready var boss_orbs: HBoxContainer = $BossBar/VBoxContainer/BossOrbs

# Spellcard overlay (declaration + result)
@onready var spell_overlay: Control = $SpellCardOverlay
@onready var spell_overlay_title: Label = $SpellCardOverlay/VBoxContainer/SpellCardTitleLabel
@onready var spell_overlay_name: Label = $SpellCardOverlay/VBoxContainer/SpellCardNameLabel
@onready var spell_overlay_result: Label = $SpellCardOverlay/VBoxContainer/SpellCardResultLabel

# Buttons
@onready var resume_button: Button = $PauseMenu/VBoxContainer/ResumeButton
@onready var pause_quit_button: Button = $PauseMenu/VBoxContainer/QuitButton
@onready var restart_button: Button = $GameOverScreen/VBoxContainer/RestartButton
@onready var gameover_quit_button: Button = $GameOverScreen/VBoxContainer/QuitButton

var start_ticks_msec: int = 0
var enemy_spawner: Node = null
var achievement_hide_time: float = 0.0

var _orb_texture: Texture2D = null
var _orbs_boss_instance_id: int = 0
var _orbs_total: int = -1
var _spell_overlay_tween: Tween = null

func _ready():
	# HUD and pause UI must keep receiving input while the game is paused.
	# Otherwise Resume button / Space / ESC will not work after pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	if pause_menu:
		pause_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if game_over_screen:
		game_over_screen.process_mode = Node.PROCESS_MODE_ALWAYS

	start_ticks_msec = Time.get_ticks_msec()

	# Connect to GameManager signals
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.health_changed.connect(_on_health_changed)
	GameManager.money_changed.connect(_on_money_changed)
	GameManager.power_changed.connect(_on_power_changed)
	GameManager.combo_changed.connect(_on_combo_changed)
	GameManager.achievement_unlocked.connect(_on_achievement_unlocked)
	GameManager.game_over.connect(_on_game_over)
	GameManager.game_paused.connect(_on_game_paused)
	GameManager.game_resumed.connect(_on_game_resumed)
	if GameManager.has_signal("spellcard_declared"):
		GameManager.spellcard_declared.connect(_on_spellcard_declared)
	if GameManager.has_signal("spellcard_result"):
		GameManager.spellcard_result.connect(_on_spellcard_result)

	# Connect button signals
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if pause_quit_button:
		pause_quit_button.pressed.connect(_on_quit_pressed)
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if gameover_quit_button:
		gameover_quit_button.pressed.connect(_on_quit_pressed)

	# Hide menus initially
	pause_menu.hide()
	game_over_screen.hide()
	if achievement_label:
		achievement_label.hide()
	if spell_overlay:
		spell_overlay.hide()

	# Connect to enemy spawner for wave updates
	enemy_spawner = get_node_or_null("/root/Main/EnemySpawner")

	# Report playfield bounds (exclude BottomBar from gameplay space).
	call_deferred("_report_playfield_bounds")

func _report_playfield_bounds() -> void:
	if not bottom_bar:
		return
	if GameManager and GameManager.has_method("set_playfield_bottom_override_y"):
		var r := bottom_bar.get_global_rect()
		GameManager.set_playfield_bottom_override_y(r.position.y)

func _process(_delta):
	_update_boss_ui()

	# Gametime (Python: show TIMESTOP during time stop)
	if game_time_label:
		if GameManager.time_stop_active:
			game_time_label.text = "Gametime: TIMESTOP"
		else:
			var elapsed := int((Time.get_ticks_msec() - start_ticks_msec) / 1000.0)
			game_time_label.text = "Gametime: %d" % elapsed

	# Stage info (Python StageSystem parity)
	if wave_label:
		var stage_text := StageManager.get_stage_info()
		if enemy_spawner and enemy_spawner.has_method("get_wave_number"):
			stage_text += " | Wave %d" % enemy_spawner.get_wave_number()
		wave_label.text = stage_text
		if boss_in_label:
			if StageManager.current_phase == StageManager.StagePhase.STAGE:
				boss_in_label.visible = true
				boss_in_label.text = "Boss in: %ds" % StageManager.get_stage_remaining_time()
			else:
				boss_in_label.visible = false

	if achievement_label and achievement_label.visible and Time.get_ticks_msec() / 1000.0 >= achievement_hide_time:
		achievement_label.hide()

	# Update bomb/shield values from player
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player) and not player.is_queued_for_deletion():
		if bomb_label:
			bomb_label.text = "Bombs: %d" % player.bombs
		if shield_label:
			shield_label.text = "Shield: %d" % player.shield
		if weapon_label:
			if player.has_method("get_weapon_name"):
				weapon_label.text = "Weapon: %s" % player.get_weapon_name()
			elif "weapon_type" in player:
				weapon_label.text = "Weapon: %s" % str(player.weapon_type)

func _update_boss_ui() -> void:
	if not boss_bar or not boss_health_bar or not boss_health_label or not boss_name_label:
		return

	var boss := get_tree().get_first_node_in_group("boss")
	if not boss or not is_instance_valid(boss) or boss.is_queued_for_deletion():
		boss_bar.visible = false
		if spell_bonus_row:
			spell_bonus_row.visible = false
		if boss_orbs:
			boss_orbs.visible = false
		return

	var boss_health: int = int(boss.get("health")) if "health" in boss else 0
	var boss_max_health: int = int(boss.get("max_health")) if "max_health" in boss else 0
	var boss_id: int = int(boss.get("boss_id")) if "boss_id" in boss else StageManager.current_stage
	var phase_name: String = str(boss.get("phase_name")) if "phase_name" in boss else ""
	var phase_kind: int = int(boss.get("phase_kind")) if "phase_kind" in boss else 0
	var has_phase_timer: bool = "phase_time_left_sec" in boss
	var phase_time_left: float = float(boss.get("phase_time_left_sec")) if has_phase_timer else 0.0
	var phase_index: int = int(boss.get("phase_index")) if "phase_index" in boss else 0
	var is_midboss: bool = bool(boss.get("is_midboss")) if "is_midboss" in boss else false
	var defs: Array = []
	var total_phases: int = 0
	if "phase_defs" in boss:
		defs = boss.get("phase_defs")
		if defs is Array:
			total_phases = defs.size()

	boss_bar.visible = true
	boss_name_label.text = "MIDBOSS" if is_midboss else ("BOSS %d" % boss_id)

	if boss_phase_label:
		var phase_text := phase_name
		if phase_text == "":
			phase_text = "Midboss" if is_midboss else ("Phase %d" % (phase_index + 1))
		if total_phases > 0:
			phase_text += " (%d/%d)" % [phase_index + 1, total_phases]
		boss_phase_label.text = phase_text

		var c := Color(1, 1, 1, 1)
		# BossEnemy.PhaseKind: 0 NONSPELL, 1 SPELL, 2 FINAL
		if phase_kind == 1:
			c = Color(1.0, 0.6, 1.0, 1.0)
		elif phase_kind == 2:
			c = Color(1.0, 0.35, 0.35, 1.0)
		boss_phase_label.add_theme_color_override("font_color", c)

	if boss_timer_label:
		boss_timer_label.text = ("TIME: %d" % int(ceil(maxf(0.0, phase_time_left)))) if has_phase_timer else ""

	# Spell Bonus row (Touhou-like)
	if spell_bonus_row:
		var is_spell := phase_kind == 1 or phase_kind == 2
		spell_bonus_row.visible = is_spell
		if is_spell and spell_bonus_value_label:
			var bonus_current: int = int(boss.get("spell_bonus_current")) if "spell_bonus_current" in boss else 0
			var bonus_valid: bool = bool(boss.get("spell_bonus_valid")) if "spell_bonus_valid" in boss else true
			if bonus_valid:
				spell_bonus_value_label.text = _format_int(bonus_current)
				spell_bonus_value_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4, 1))
			else:
				spell_bonus_value_label.text = "FAILED"
				spell_bonus_value_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4, 1))

	_update_boss_orbs(boss, defs, phase_index)

	boss_health_bar.max_value = max(1, boss_max_health)
	boss_health_bar.value = clampi(boss_health, 0, boss_max_health)
	boss_health_label.text = "%d/%d" % [boss_health, boss_max_health]

func _format_int(value: int) -> String:
	var n: int = abs(value)
	var s: String = str(n)
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3, 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	if value < 0:
		out = "-" + out
	return out

func _phase_kind_color(kind: int) -> Color:
	# BossEnemy.PhaseKind: 0 NONSPELL, 1 SPELL, 2 FINAL
	if kind == 1:
		return Color(1.0, 0.6, 1.0, 1.0)
	if kind == 2:
		return Color(1.0, 0.35, 0.35, 1.0)
	return Color(0.7, 0.9, 1.0, 1.0)

func _get_orb_texture() -> Texture2D:
	if _orb_texture:
		return _orb_texture
	var radius := 5
	var size := radius * 2 + 1
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(float(radius), float(radius))
	for y in range(size):
		for x in range(size):
			var dist := Vector2(float(x), float(y)).distance_to(center)
			if dist <= float(radius):
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	_orb_texture = ImageTexture.create_from_image(img)
	return _orb_texture

func _update_boss_orbs(boss: Node, defs: Array, phase_index: int) -> void:
	if not boss_orbs:
		return
	if not (defs is Array) or defs.is_empty():
		boss_orbs.visible = false
		return
	boss_orbs.visible = true

	var boss_instance_id := boss.get_instance_id()
	if boss_instance_id != _orbs_boss_instance_id or defs.size() != _orbs_total:
		_orbs_boss_instance_id = boss_instance_id
		_orbs_total = defs.size()
		for c in boss_orbs.get_children():
			(c as Node).queue_free()
		for _i in range(defs.size()):
			var orb := TextureRect.new()
			orb.texture = _get_orb_texture()
			orb.custom_minimum_size = Vector2(12, 12)
			orb.stretch_mode = TextureRect.STRETCH_SCALE
			orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			boss_orbs.add_child(orb)

	for i in range(min(defs.size(), boss_orbs.get_child_count())):
		var def = defs[i]
		var kind := int(def.kind) if def and ("kind" in def) else 0
		var color := _phase_kind_color(kind)
		var alpha := 1.0
		if i < phase_index:
			alpha = 0.25
		var orb_node := boss_orbs.get_child(i) as Control
		if orb_node:
			orb_node.modulate = Color(color.r, color.g, color.b, alpha)
			orb_node.scale = Vector2.ONE * (1.35 if i == phase_index else 1.0)

func _show_spell_overlay(title: String, name: String, result: String, title_color: Color, result_color: Color, duration_sec: float) -> void:
	if not spell_overlay:
		return
	if _spell_overlay_tween:
		_spell_overlay_tween.kill()
		_spell_overlay_tween = null

	spell_overlay.visible = true
	spell_overlay.modulate = Color(1, 1, 1, 0)
	if spell_overlay_title:
		spell_overlay_title.text = title
		spell_overlay_title.add_theme_color_override("font_color", title_color)
	if spell_overlay_name:
		spell_overlay_name.text = "「%s」" % name
	if spell_overlay_result:
		spell_overlay_result.text = result
		spell_overlay_result.add_theme_color_override("font_color", result_color)

	_spell_overlay_tween = create_tween()
	_spell_overlay_tween.tween_property(spell_overlay, "modulate", Color(1, 1, 1, 1), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_spell_overlay_tween.tween_interval(max(0.0, duration_sec - 0.32))
	_spell_overlay_tween.tween_property(spell_overlay, "modulate", Color(1, 1, 1, 0), 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_spell_overlay_tween.finished.connect(func():
		if spell_overlay:
			spell_overlay.hide()
	)

func _on_spellcard_declared(spell_name: String, bonus: int, is_final: bool) -> void:
	var title := "FINAL SPELL" if is_final else "SPELL CARD"
	var title_color := Color(1.0, 0.35, 0.35, 1.0) if is_final else Color(1.0, 0.6, 1.0, 1.0)
	_show_spell_overlay(title, spell_name, "Spell Bonus: %s" % _format_int(bonus), title_color, Color(1, 0.9, 0.4, 1), 1.6)

func _on_spellcard_result(spell_name: String, captured: bool, timed_out: bool, bonus_awarded: int) -> void:
	if captured:
		_show_spell_overlay("SPELL BONUS", spell_name, _format_int(bonus_awarded), Color(1, 0.9, 0.4, 1), Color(1, 0.9, 0.4, 1), 1.2)
		return
	if timed_out:
		_show_spell_overlay("TIME OUT", spell_name, "", Color(1, 0.4, 0.4, 1), Color(1, 0.4, 0.4, 1), 1.2)
		return
	_show_spell_overlay("BONUS FAILED", spell_name, "", Color(0.85, 0.85, 0.85, 1), Color(0.85, 0.85, 0.85, 1), 1.2)

func _on_score_changed(new_score: int):
	if score_label:
		score_label.text = "Score: %d" % new_score

func _on_money_changed(new_money: int):
	if money_label:
		money_label.text = "Money: %d" % new_money

func _on_health_changed(current_health: int, max_health: int):
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	if health_label:
		health_label.text = "%d/%d" % [current_health, max_health]

func _on_power_changed(new_power: int):
	if power_bar:
		power_bar.max_value = 100
		power_bar.value = new_power

func _on_combo_changed(combo: int, multiplier: float):
	if not combo_label:
		return
	if combo <= 0:
		combo_label.text = "Combo: 0"
	else:
		combo_label.text = "Combo: %d (x%.1f)" % [combo, multiplier]

func _on_achievement_unlocked(achievement_name: String):
	if not achievement_label:
		return
	achievement_label.text = "Achievement Unlocked: %s" % achievement_name
	achievement_label.show()
	achievement_hide_time = Time.get_ticks_msec() / 1000.0 + 2.6

func _on_game_over():
	game_over_screen.show()
	if final_score_label:
		final_score_label.text = "Final Score: %d" % GameManager.score

func _on_game_paused():
	pause_menu.show()
	if resume_button:
		resume_button.grab_focus()

func _on_game_resumed():
	pause_menu.hide()

func _input(event):
	# Ignore key repeat to avoid pause/resume flicker (Space is bound to pause in this project).
	if event is InputEventKey and (event as InputEventKey).echo:
		return

	# Allow click-to-resume while paused (keyboard pause/resume is handled globally in GameManager).
	if GameManager.is_paused and pause_menu and pause_menu.visible:
		# Fallback: allow Space/Enter while paused even if global pause input gets blocked.
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_accept"):
			GameManager.resume_game()
			get_viewport().set_input_as_handled()
			return
		# Fallback: allow a left click anywhere on the pause overlay to resume.
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				GameManager.resume_game()
				get_viewport().set_input_as_handled()
				return

func _on_resume_pressed():
	GameManager.resume_game()

func _on_restart_pressed():
	GameManager.restart_game()

func _on_quit_pressed():
	get_tree().quit()
