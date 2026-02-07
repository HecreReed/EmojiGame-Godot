extends Node2D

func _ready():
	# Setup game
	setup_game()

func setup_game():
	# Create player
	var player_scene = preload("res://scenes/player.tscn")
	var player = player_scene.instantiate()
	$Entities.add_child(player)
	
	# Create game manager
	var game_manager = GameManager.new()
	add_child(game_manager)
	
	# Create UI
	var ui = GameUI.new()
	add_child(ui)
	
	# Create music manager
	var music_manager = MusicManager.new()
	add_child(music_manager)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		# Pause or quit
		get_tree().quit()
	
	# Player abilities
	var player = get_tree().get_first_node_in_group("player")
	if player:
		if event.is_action_pressed("bomb"):
			player.use_bomb()
		if event.is_action_pressed("time_stop"):
			player.use_time_stop()
