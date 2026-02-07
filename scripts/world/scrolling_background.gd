extends Node2D

@export var scroll_speed: float = 50.0
@export var seam_feather_enabled: bool = true
@export var seam_feather_px: float = 80.0

@onready var background_1: ColorRect = $ColorRect1
@onready var background_2: ColorRect = $ColorRect2

var bg_sprite_a: Sprite2D
var bg_sprite_b: Sprite2D
var start_overlay_sprite: Sprite2D

var viewport_size: Vector2 = Vector2.ZERO
var current_bg_path: String = ""

# Seam feathering (to hide scroll edge seams)
var _seam_overlap_px: float = 0.0
var _seam_gap_px: float = 0.0
var _seam_shader: Shader = null

# Boss1 flicker (Python: switch every ~0.677s)
var boss1_flicker_timer: float = 0.0
var boss1_flicker_use_inverse: bool = false
var _boss1_intro_remaining: float = 0.0
var _boss1_was_active: bool = false

func _ready() -> void:
	viewport_size = get_viewport_rect().size
	_update_seam_params()

	# Hide legacy ColorRect backgrounds
	if background_1:
		background_1.visible = false
	if background_2:
		background_2.visible = false

	bg_sprite_a = Sprite2D.new()
	bg_sprite_a.name = "BackgroundSpriteA"
	bg_sprite_a.centered = false
	bg_sprite_a.position = Vector2.ZERO
	add_child(bg_sprite_a)

	bg_sprite_b = Sprite2D.new()
	bg_sprite_b.name = "BackgroundSpriteB"
	bg_sprite_b.centered = false
	bg_sprite_b.position = Vector2(_seam_gap_px, 0)
	add_child(bg_sprite_b)

	start_overlay_sprite = Sprite2D.new()
	start_overlay_sprite.name = "StartOverlay"
	start_overlay_sprite.centered = true
	start_overlay_sprite.position = viewport_size * 0.5
	start_overlay_sprite.texture = load("res://assets/sprites/start.png")
	start_overlay_sprite.visible = false
	add_child(start_overlay_sprite)

	_apply_scale(bg_sprite_a)
	_apply_scale(bg_sprite_b)
	_setup_seam_feather_materials()

	_update_background(true)


func _process(delta: float) -> void:
	# Background should still update during time stop (r variants),
	# but movement/scrolling is not part of the Python version.
	if StageManager.is_game_cleared():
		return

	# Boss1 flicker logic (disabled during time stop).
	var boss1_active := StageManager.current_phase == StageManager.StagePhase.BOSS and StageManager.current_stage == 1
	if boss1_active and not _boss1_was_active:
		# Boss1 entrance: brief red flash/flicker only (avoid a permanent red overlay).
		_boss1_intro_remaining = 2.4
		boss1_flicker_timer = 0.0
		boss1_flicker_use_inverse = false
	_boss1_was_active = boss1_active

	if boss1_active and _boss1_intro_remaining > 0.0 and not GameManager.time_stop_active:
		_boss1_intro_remaining = maxf(0.0, _boss1_intro_remaining - delta)
		boss1_flicker_timer += delta
		if boss1_flicker_timer >= 0.677:
			boss1_flicker_timer = 0.0
			boss1_flicker_use_inverse = not boss1_flicker_use_inverse
	else:
		boss1_flicker_timer = 0.0
		if not boss1_active or _boss1_intro_remaining <= 0.0:
			boss1_flicker_use_inverse = false

	_update_background()

	_scroll_background(delta)


func _update_background(force: bool = false) -> void:
	var desired_path := _get_desired_background_path()
	if not force and desired_path == current_bg_path:
		return
	current_bg_path = desired_path

	var tex: Texture2D = load(desired_path)
	if not tex:
		tex = load("res://assets/sprites/sky.png")
	bg_sprite_a.texture = tex
	bg_sprite_b.texture = tex
	_apply_scale(bg_sprite_a)
	_apply_scale(bg_sprite_b)
	_reset_scroll_positions()


func _get_desired_background_path() -> String:
	var stage: int = clampi(StageManager.current_stage, 1, StageManager.total_stages)
	var is_timestop := GameManager.time_stop_active

	if StageManager.current_phase == StageManager.StagePhase.BOSS:
		# Boss backgrounds
		if stage == 1:
			if is_timestop:
				return "res://assets/sprites/boss1r.png"
			return "res://assets/sprites/%s.png" % ("boss1r" if boss1_flicker_use_inverse else "boss1")
		return "res://assets/sprites/boss%d%s.png" % [stage, "r" if is_timestop else ""]

	# Stage backgrounds (STAGE/CLEAR)
	var stage_path := "res://assets/sprites/back%d%s.png" % [stage, "r" if is_timestop else ""]
	if ResourceLoader.exists(stage_path):
		return stage_path
	return "res://assets/sprites/fucksky.png" if is_timestop else "res://assets/sprites/back%d.png" % stage


func _scroll_background(delta: float) -> void:
	# Continuous horizontal scrolling (right -> left). Freeze during time stop.
	if GameManager.time_stop_active:
		return
	if not bg_sprite_a or not bg_sprite_b:
		return

	bg_sprite_a.position.x -= scroll_speed * delta
	bg_sprite_b.position.x -= scroll_speed * delta

	if bg_sprite_a.position.x <= -_seam_gap_px:
		bg_sprite_a.position.x = bg_sprite_b.position.x + _seam_gap_px
	if bg_sprite_b.position.x <= -_seam_gap_px:
		bg_sprite_b.position.x = bg_sprite_a.position.x + _seam_gap_px

	_update_seam_fade_sides()


func _reset_scroll_positions() -> void:
	if not bg_sprite_a or not bg_sprite_b:
		return
	bg_sprite_a.position = Vector2.ZERO
	bg_sprite_b.position = Vector2(_seam_gap_px, 0.0)
	_update_seam_fade_sides()

func _update_seam_params() -> void:
	_seam_overlap_px = 0.0
	if seam_feather_enabled and seam_feather_px > 0.0:
		# Clamp overlap so we never lose coverage.
		_seam_overlap_px = clampf(seam_feather_px, 0.0, viewport_size.x * 0.45)
	_seam_gap_px = maxf(1.0, viewport_size.x - _seam_overlap_px)

func _setup_seam_feather_materials() -> void:
	if not bg_sprite_a or not bg_sprite_b:
		return
	if not seam_feather_enabled or _seam_overlap_px <= 0.0:
		bg_sprite_a.material = null
		bg_sprite_b.material = null
		return

	_seam_shader = load("res://assets/shaders/background_feather.gdshader") as Shader
	if not _seam_shader:
		return
	var fade_frac := clampf(_seam_overlap_px / maxf(1.0, viewport_size.x), 0.0, 0.45)

	var mat_a := ShaderMaterial.new()
	mat_a.shader = _seam_shader
	mat_a.set_shader_parameter("fade_frac", fade_frac)
	mat_a.set_shader_parameter("fade_side", 1.0)
	bg_sprite_a.material = mat_a

	var mat_b := ShaderMaterial.new()
	mat_b.shader = _seam_shader
	mat_b.set_shader_parameter("fade_frac", fade_frac)
	mat_b.set_shader_parameter("fade_side", -1.0)
	bg_sprite_b.material = mat_b

	_update_seam_fade_sides()

func _set_fade_side(sprite: Sprite2D, side: float) -> void:
	if not sprite:
		return
	var mat := sprite.material as ShaderMaterial
	if not mat:
		return
	mat.set_shader_parameter("fade_side", side)

func _update_seam_fade_sides() -> void:
	if not seam_feather_enabled or _seam_overlap_px <= 0.0:
		_set_fade_side(bg_sprite_a, 0.0)
		_set_fade_side(bg_sprite_b, 0.0)
		return

	if not bg_sprite_a or not bg_sprite_b:
		return

	var left := bg_sprite_a
	var right := bg_sprite_b
	if bg_sprite_a.position.x > bg_sprite_b.position.x:
		left = bg_sprite_b
		right = bg_sprite_a

	# Left background fades out on its right edge, right background fades in on its left edge.
	_set_fade_side(left, 1.0)
	_set_fade_side(right, -1.0)


func _apply_scale(sprite: Sprite2D) -> void:
	if not sprite or not sprite.texture:
		return
	var tex_size := sprite.texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	sprite.scale = Vector2(viewport_size.x / tex_size.x, viewport_size.y / tex_size.y)
