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

@export var power_up_type: PowerUpType = PowerUpType.HEALTH
@export var move_speed: float = 100.0

var direction: Vector2 = Vector2.LEFT
var target_player: Node2D = null
var is_attracted: bool = false
var attraction_range: float = 150.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready():
	add_to_group("powerups")
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

	# Set color based on type
	if sprite:
		sprite.modulate = get_color_for_type()

func get_color_for_type() -> Color:
	match power_up_type:
		PowerUpType.POWER_POTION:
			return Color(1, 0.3, 0.3)  # Red
		PowerUpType.HEALTH:
			return Color(0, 1, 0)  # Green
		PowerUpType.WEAPON_UPGRADE:
			return Color(1, 1, 0)  # Yellow
		PowerUpType.FIRE_RATE:
			return Color(1, 0.5, 0)  # Orange
		PowerUpType.COIN_SMALL:
			return Color(1, 1, 0.5)  # Light yellow
		PowerUpType.COIN_MEDIUM:
			return Color(1, 0.84, 0)  # Gold
		PowerUpType.COIN_LARGE:
			return Color(1, 0.65, 0)  # Dark gold
		PowerUpType.MAX_HEALTH:
			return Color(0, 0.8, 0.8)  # Cyan
		PowerUpType.POWER:
			return Color(0.5, 0.5, 1)  # Light blue
		PowerUpType.BOMB:
			return Color(1, 0.5, 0)  # Orange-red
		PowerUpType.SHIELD:
			return Color(0, 0.5, 1)  # Blue
		PowerUpType.INVINCIBLE:
			return Color(1, 1, 1)  # White
		PowerUpType.CLEAR_SCREEN:
			return Color(1, 0, 0)  # Red
		PowerUpType.SCORE_BOOST:
			return Color(1, 0, 1)  # Magenta
		PowerUpType.FULL_HEALTH:
			return Color(0, 1, 1)  # Cyan
		PowerUpType.MAX_POWER:
			return Color(1, 0.5, 1)  # Pink
		_:
			return Color(1, 1, 1)

func _physics_process(delta):
	# Check if player is nearby
	if not is_attracted:
		var player = get_tree().get_first_node_in_group("player")
		if player:
			var distance = global_position.distance_to(player.global_position)
			if distance < attraction_range:
				is_attracted = true
				target_player = player

	# Move towards player if attracted
	if is_attracted and target_player:
		direction = (target_player.global_position - global_position).normalized()
		position += direction * move_speed * 2 * delta
	else:
		# Normal movement (left)
		position += direction * move_speed * delta

	# Remove if out of screen
	if position.x < -100:
		queue_free()

func _on_area_entered(area):
	if area.is_in_group("player"):
		apply_effect(area)
		queue_free()

func _on_body_entered(body):
	if body.is_in_group("player"):
		apply_effect(body)
		queue_free()

func apply_effect(player):
	match power_up_type:
		PowerUpType.POWER_POTION:
			# 增加伤害
			if "damage" in player:
				player.damage += 2

		PowerUpType.HEALTH:
			# 恢复生命值
			if player.has_method("heal"):
				player.heal(20)

		PowerUpType.WEAPON_UPGRADE:
			# 武器升级
			if player.has_method("upgrade_weapon"):
				player.upgrade_weapon()

		PowerUpType.FIRE_RATE:
			# 射速提升
			if "shoot_cooldown" in player:
				player.shoot_cooldown = max(0.05, player.shoot_cooldown * 0.9)
				if "shoot_timer" in player and player.shoot_timer:
					player.shoot_timer.wait_time = player.shoot_cooldown

		PowerUpType.COIN_SMALL:
			GameManager.add_score(10)

		PowerUpType.COIN_MEDIUM:
			GameManager.add_score(50)

		PowerUpType.COIN_LARGE:
			GameManager.add_score(400)

		PowerUpType.MAX_HEALTH:
			# 最大生命值提升
			if "max_health" in player:
				player.max_health = min(player.max_health + 20, 200)

		PowerUpType.POWER:
			# 能量值提升（转换为分数）
			GameManager.add_score(100)

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
			if player.has_method("use_bomb"):
				# 使用炸弹机制实现无敌
				player.bomb_active = true
				player.bomb_start_time = Time.get_ticks_msec() / 1000.0
				player.set_collision_mask_value(4, false)
				await get_tree().create_timer(3.0).timeout
				if is_instance_valid(player):
					player.bomb_active = false
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
				player.heal(9999)

		PowerUpType.MAX_POWER:
			# 武器临时强化5秒
			if "weapon_grade" in player:
				var original_grade = player.weapon_grade
				player.weapon_grade = 4  # 临时最高火力
				await get_tree().create_timer(5.0).timeout
				if is_instance_valid(player):
					player.weapon_grade = original_grade
