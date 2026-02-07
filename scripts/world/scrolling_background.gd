extends Node2D

@export var scroll_speed: float = 50.0

@onready var background_1: ColorRect = $ColorRect1
@onready var background_2: ColorRect = $ColorRect2

var bg_sprite: Sprite2D
var start_overlay_sprite: Sprite2D

var viewport_size: Vector2 = Vector2.ZERO
var current_bg_path: String = ""

# Boss1 flicker (Python: switch every ~0.677s)
var boss1_flicker_timer: float = 0.0
var boss1_flicker_use_inverse: bool = false

func _ready() -> void:
	viewport_size = get_viewport_rect().size

	# Hide legacy ColorRect backgrounds
	if background_1:
		background_1.visible = false
	if background_2:
		background_2.visible = false

	bg_sprite = Sprite2D.new()
	bg_sprite.name = "BackgroundSprite"
	bg_sprite.centered = false
	bg_sprite.position = Vector2.ZERO
	add_child(bg_sprite)

	start_overlay_sprite = Sprite2D.new()
	start_overlay_sprite.name = "StartOverlay"
	start_overlay_sprite.centered = false
	start_overlay_sprite.position = Vector2.ZERO
	start_overlay_sprite.texture = load("res://assets/sprites/start.png")
	add_child(start_overlay_sprite)

	_apply_scale(bg_sprite)
	_apply_scale(start_overlay_sprite)

	_update_background(true)


func _process(delta: float) -> void:
	# Background should still update during time stop (r variants),
	# but movement/scrolling is not part of the Python version.
	if StageManager.is_game_cleared():
		return

	# Boss1 flicker logic (disabled during time stop).
	if StageManager.current_phase == StageManager.StagePhase.BOSS and StageManager.current_stage == 1 and not GameManager.time_stop_active:
		boss1_flicker_timer += delta
		if boss1_flicker_timer >= 0.677:
			boss1_flicker_timer = 0.0
			boss1_flicker_use_inverse = not boss1_flicker_use_inverse
	else:
		boss1_flicker_timer = 0.0
		boss1_flicker_use_inverse = false

	_update_background()

	if start_overlay_sprite:
		# Python time stop renderer doesn't blit start.png.
		start_overlay_sprite.visible = not GameManager.time_stop_active


func _update_background(force: bool = false) -> void:
	var desired_path := _get_desired_background_path()
	if not force and desired_path == current_bg_path:
		return
	current_bg_path = desired_path

	var tex: Texture2D = load(desired_path)
	if not tex:
		tex = load("res://assets/sprites/sky.png")
	bg_sprite.texture = tex
	_apply_scale(bg_sprite)


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
	if is_timestop:
		return "res://assets/sprites/fucksky.png"
	return "res://assets/sprites/back%d.png" % stage


func _apply_scale(sprite: Sprite2D) -> void:
	if not sprite or not sprite.texture:
		return
	var tex_size := sprite.texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	sprite.scale = Vector2(viewport_size.x / tex_size.x, viewport_size.y / tex_size.y)
