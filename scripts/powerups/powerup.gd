extends Area2D
class_name PowerUp

# 原版道具类型：0-15共16种
enum PowerUpType {
	POWER_POTION,    # 0 - 力量药水（增加伤害）
	HEALTH,          # 1 - 恢复生命值
	WEAPON_UPGRADE,  # 2 - 武器升级
	FIRE_RATE,       # 3 - 射速提升
	COIN_SMALL,      # 4 - 小金币
	COIN_MEDIUM,     # 5 - 中金币
	COIN_LARGE,      # 6 - 大金币
	MAX_HEALTH,      # 7 - 最大生命值提升
	POWER,           # 8 - 能量值
	BOMB,            # 9 - 炸弹
	SHIELD,          # 10 - 护盾
	INVINCIBLE,      # 11 - 临时无敌
	CLEAR_SCREEN,    # 12 - 清屏
	SCORE_BOOST,     # 13 - 分数加倍
	FULL_HEALTH,     # 14 - 满血恢复
	MAX_POWER        # 15 - 武器临时强化
}

@export var power_up_type: int = PowerUpType.HEALTH

# Python Supply/Supply.py parity
const FPS: float = 60.0
const SUPPLY_SIZE: float = 20.0
const HALF_SIZE: float = SUPPLY_SIZE / 2.0

var speed_value: float = 105.0
var tan_value: float = 0.0
var sample: int = 1
var spawn_time_sec: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready():
	add_to_group("powerups")
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

	spawn_time_sec = Time.get_ticks_msec() / 1000.0
	sample = 1
	if randf() < 0.5:
		tan_value = -2.0 * randf()
	else:
		tan_value = 2.0 * randf()

	_apply_texture()

func _physics_process(delta):
	if GameManager.time_stop_active:
		return

	_move_supply(delta)
	_calu()
	_despawn_check()


func _apply_texture() -> void:
	if not sprite:
		return
	sprite.scale = Vector2.ONE
	sprite.modulate = Color(1, 1, 1, 1)

	var path := "res://assets/sprites/supply-%d.png" % int(power_up_type)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		tex = load("res://assets/sprites/supply-1.png")
	if tex:
		sprite.texture = tex


func _move_supply(delta: float) -> void:
	# Supply.move() uses the tan/sample line movement. speed_value is squared distance per tick.
	var speed_per_sec := sqrt(speed_value) * FPS if sample != 0 else speed_value * FPS
	var dir := Vector2.ZERO
	if sample == 0:
		var player_pos := _get_player_python_pos()
		var dx := player_pos.x - _python_pos().x
		if dx > 0.0:
			dir = Vector2.RIGHT
		elif dx < 0.0:
			dir = Vector2.LEFT
	else:
		# sample == 1 => move left, sample == -1 => move right
		dir = Vector2(-float(sample), -float(sample) * tan_value)

	if dir.length() > 0.0:
		global_position += dir.normalized() * speed_per_sec * delta


func _calu() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not player:
		return

	var player_pos := _get_player_python_pos()
	var pos := _python_pos()
	var dx := player_pos.x - pos.x
	var dy := player_pos.y - pos.y

	if dx != 0.0:
		tan_value = dy / dx
	else:
		tan_value = 0.0
		sample = 0

	if dx < 0.0:
		sample = 1
	elif dx > 0.0:
		sample = -1


func _despawn_check() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var elapsed := now - spawn_time_sec
	if elapsed < 18.0:
		return

	# Python: remove when elapsed >= 18 + 3 * random.random().
	var p := clampf((elapsed - 18.0) / 3.0, 0.0, 1.0)
	if randf() <= p:
		queue_free()


func _python_pos() -> Vector2:
	return global_position - Vector2(HALF_SIZE, HALF_SIZE)


func _get_player_python_pos() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not player:
		return Vector2.ZERO
	return player.global_position - Vector2(20.0, 20.0)

func _on_area_entered(area):
	if area.is_in_group("player"):
		apply_effect(area)
		queue_free()

func _on_body_entered(body):
	if body.is_in_group("player"):
		apply_effect(body)
		queue_free()

func apply_effect(player):
	if GameManager.has_method("register_supply_collected"):
		GameManager.register_supply_collected()

	match power_up_type:
		PowerUpType.POWER_POTION:
			# 增加伤害
			if "damage" in player:
				player.damage += 2

		PowerUpType.HEALTH:
			# 恢复生命值
			if player.has_method("heal"):
				player.heal(int(8 + 4 * randf()))

		PowerUpType.WEAPON_UPGRADE:
			# 武器升级
			if player.has_method("upgrade_weapon"):
				player.upgrade_weapon()

		PowerUpType.FIRE_RATE:
			# 射速提升
			if "shoot_cooldown" in player:
				player.shoot_cooldown = max(0.125, player.shoot_cooldown - 0.1)
				if "shoot_timer" in player and player.shoot_timer:
					player.shoot_timer.wait_time = player.shoot_cooldown

		PowerUpType.COIN_SMALL:
			GameManager.add_money(10)

		PowerUpType.COIN_MEDIUM:
			GameManager.add_money(50)

		PowerUpType.COIN_LARGE:
			GameManager.add_money(400)

		PowerUpType.MAX_HEALTH:
			# 最大生命值提升
			if "max_health" in player:
				player.max_health = min(player.max_health + 4, 40)

		PowerUpType.POWER:
			# 能量值提升（1-3）
			GameManager.add_power(randi_range(1, 3))

		PowerUpType.BOMB:
			# 炸弹补给
			if player.has_method("add_bomb"):
				player.add_bomb()

		PowerUpType.SHIELD:
			# 护盾补给
			if player.has_method("add_shield"):
				player.add_shield()

		PowerUpType.INVINCIBLE:
			# 临时无敌3秒
			if "is_invincible" in player:
				player.is_invincible = true
			if player.has_method("set_collision_mask_value"):
				player.set_collision_mask_value(4, false)
			await get_tree().create_timer(3.0).timeout
			if is_instance_valid(player):
				if "is_invincible" in player:
					player.is_invincible = false
				if player.has_method("set_collision_mask_value"):
					player.set_collision_mask_value(4, true)

		PowerUpType.CLEAR_SCREEN:
			# 全屏清除敌弹
			var bullets = get_tree().get_nodes_in_group("enemy_bullets")
			for bullet in bullets:
				bullet.queue_free()

		PowerUpType.SCORE_BOOST:
			# 分数加倍10秒
			GameManager.activate_score_multiplier(2.0, 10.0)

		PowerUpType.FULL_HEALTH:
			# 满血恢复
			if player.has_method("heal"):
				player.heal(player.max_health)

		PowerUpType.MAX_POWER:
			# 武器临时强化5秒
			if "weapon_grade" in player:
				var original_grade = player.weapon_grade
				player.weapon_grade = 4  # 临时最高火力
				await get_tree().create_timer(5.0).timeout
				if is_instance_valid(player):
					player.weapon_grade = original_grade
