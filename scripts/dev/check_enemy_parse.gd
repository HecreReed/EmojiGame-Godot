extends SceneTree


func _init() -> void:
	print("Checking Enemy parse...")
	var enemy_script := load("res://scripts/enemies/enemy.gd")
	print("Enemy script loaded: %s" % [enemy_script])
	quit()

