extends Node2D

@export var scroll_speed: float = 50.0

@onready var background_1: ColorRect = $ColorRect1
@onready var background_2: ColorRect = $ColorRect2

var bg_width: float = 1152.0  # Match window width
var background_sprites: Array[Sprite2D] = []
var sky_texture: Texture2D

func _ready():
	# Load background texture
	sky_texture = load("res://assets/sprites/sky.png")

	# Create sprite-based backgrounds with texture
	if sky_texture:
		# Hide old ColorRects
		if background_1:
			background_1.visible = false
		if background_2:
			background_2.visible = false

		# Create 3 background sprites for seamless scrolling
		for i in range(3):
			var sprite = Sprite2D.new()
			sprite.texture = sky_texture
			sprite.position = Vector2(i * bg_width + bg_width/2, 324)
			sprite.centered = true

			# Scale to fill screen
			var texture_size = sky_texture.get_size()
			sprite.scale = Vector2(bg_width / texture_size.x, 648.0 / texture_size.y)

			add_child(sprite)
			background_sprites.append(sprite)

		print("Background sprites created: ", background_sprites.size())
	else:
		# Fallback to ColorRect backgrounds
		if background_1:
			background_1.position.x = 0
		if background_2:
			background_2.position.x = bg_width
		print("Using ColorRect backgrounds")

func _process(delta):
	# Scroll sprite backgrounds
	if not background_sprites.is_empty():
		for sprite in background_sprites:
			sprite.position.x -= scroll_speed * delta

			# Wrap around when off screen
			if sprite.position.x < -bg_width/2:
				sprite.position.x += bg_width * background_sprites.size()
	else:
		# Scroll ColorRect backgrounds (fallback)
		if background_1:
			background_1.position.x -= scroll_speed * delta
		if background_2:
			background_2.position.x -= scroll_speed * delta

		# Reset position when off screen
		if background_1 and background_1.position.x <= -bg_width:
			background_1.position.x = background_2.position.x + bg_width
		if background_2 and background_2.position.x <= -bg_width:
			background_2.position.x = background_1.position.x + bg_width
