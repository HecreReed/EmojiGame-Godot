"""
新武器类型系统
提供多种特殊武器模式，让战斗更有策略性
"""
import time
import math
import random
import pygame
import Event
from Bullut.WaterBumb import WaterBumb


class SpreadShot:
    """扇形射击：发射扇形弹幕"""
    @staticmethod
    def shoot(player):
        if time.time() - player.lasttime > player.sleepbumbtime:
            player.lasttime = time.time()

            # 根据火力等级调整子弹数量和扇形角度
            from Statement.State import State
            if player.statement == State.NORMAL:
                bullet_count = 3
                angle_step = 15
            elif player.statement == State.DOUBLE:
                bullet_count = 5
                angle_step = 12
            elif player.statement == State.TWINBLE:
                bullet_count = 7
                angle_step = 10
            else:  # FINAL
                bullet_count = 9
                angle_step = 8

            # 计算起始角度，确保扇形居中
            start_angle = -(bullet_count - 1) * angle_step // 2

            for i in range(bullet_count):
                angle = start_angle + i * angle_step
                bullet = WaterBumb(player.x, player.y + 20, player.hurt)
                bullet.has_spread = True
                bullet.spread_angle = angle
                # 设置子弹的tan和sample以实现扇形
                angle_rad = math.radians(angle)
                bullet.tan = math.tan(angle_rad)
                bullet.sample = 1  # 向右射击
                player.allbumb.append(bullet)


class HomingMissile:
    """追踪导弹：会自动追踪最近的敌人"""
    @staticmethod
    def shoot(player):
        if time.time() - player.lasttime > player.sleepbumbtime * 1.5:  # 发射慢一些
            player.lasttime = time.time()

            # 根据火力等级调整导弹数量
            from Statement.State import State
            if player.statement == State.NORMAL:
                missile_count = 1
            elif player.statement == State.DOUBLE:
                missile_count = 2
            elif player.statement == State.TWINBLE:
                missile_count = 3
            else:  # FINAL
                missile_count = 4

            for i in range(missile_count):
                offset = (i - missile_count / 2 + 0.5) * 15  # 垂直分散
                bullet = WaterBumb(player.x, player.y + 20 + offset, player.hurt * 2)  # 伤害更高
                bullet.is_homing = True
                bullet.homing_target = None
                player.allbumb.append(bullet)

    @staticmethod
    def update_bullet(bullet):
        """更新追踪逻辑"""
        if not hasattr(bullet, 'is_homing') or not bullet.is_homing:
            return

        # 寻找最近的敌人
        min_distance = float('inf')
        closest_enemy = None

        for enemy in Event.Game.g_enemies:
            if enemy.live > 0:
                dx = enemy.x - bullet.x
                dy = enemy.y - bullet.y
                distance = math.sqrt(dx**2 + dy**2)
                if distance < min_distance:
                    min_distance = distance
                    closest_enemy = enemy

        # 追踪敌人
        if closest_enemy:
            dx = closest_enemy.x - bullet.x
            dy = closest_enemy.y - bullet.y
            if dx != 0:
                bullet.tan = dy / dx
            bullet.sample = 1 if dx > 0 else -1


class LaserBeam:
    """激光束：持续伤害的激光"""
    @staticmethod
    def shoot(player):
        if time.time() - player.lasttime > player.sleepbumbtime * 0.5:
            player.lasttime = time.time()

            # 根据火力等级调整激光数量和密度
            from Statement.State import State
            if player.statement == State.NORMAL:
                laser_count = 3
            elif player.statement == State.DOUBLE:
                laser_count = 5
            elif player.statement == State.TWINBLE:
                laser_count = 7
            else:  # FINAL
                laser_count = 10

            # 激光是一系列连续的高速子弹
            for i in range(laser_count):
                bullet = WaterBumb(player.x + i * 8, player.y + 20, player.hurt // 2)
                bullet.speed = 30
                bullet.is_laser = True
                player.allbumb.append(bullet)


class PenetratingShot:
    """穿透弹：可以穿透敌人"""
    @staticmethod
    def shoot(player):
        if time.time() - player.lasttime > player.sleepbumbtime * 1.2:
            player.lasttime = time.time()

            # 根据火力等级调整穿透弹数量和穿透次数
            from Statement.State import State
            if player.statement == State.NORMAL:
                bullet_count = 1
                penetrate_count = 2
            elif player.statement == State.DOUBLE:
                bullet_count = 2
                penetrate_count = 3
            elif player.statement == State.TWINBLE:
                bullet_count = 3
                penetrate_count = 4
            else:  # FINAL
                bullet_count = 4
                penetrate_count = 5

            for i in range(bullet_count):
                offset = (i - bullet_count / 2 + 0.5) * 15
                bullet = WaterBumb(player.x, player.y + 20 + offset, player.hurt * 1.5)
                bullet.can_penetrate = True
                bullet.penetrate_count = penetrate_count
                player.allbumb.append(bullet)


class BombardmentShot:
    """轰炸弹：击中后爆炸产生范围伤害"""
    @staticmethod
    def shoot(player):
        if time.time() - player.lasttime > player.sleepbumbtime * 2:
            player.lasttime = time.time()

            # 根据火力等级调整轰炸弹数量和爆炸范围
            from Statement.State import State
            if player.statement == State.NORMAL:
                bullet_count = 1
                explosion_radius = 80
                damage_multiplier = 2.5
            elif player.statement == State.DOUBLE:
                bullet_count = 2
                explosion_radius = 100
                damage_multiplier = 3
            elif player.statement == State.TWINBLE:
                bullet_count = 3
                explosion_radius = 120
                damage_multiplier = 3.5
            else:  # FINAL
                bullet_count = 4
                explosion_radius = 150
                damage_multiplier = 4

            for i in range(bullet_count):
                offset = (i - bullet_count / 2 + 0.5) * 20
                bullet = WaterBumb(player.x, player.y + 20 + offset, int(player.hurt * damage_multiplier))
                bullet.is_bomb = True
                bullet.explosion_radius = explosion_radius
                player.allbumb.append(bullet)

    @staticmethod
    def explode(bullet):
        """爆炸效果"""
        if not hasattr(bullet, 'is_bomb') or not bullet.is_bomb:
            return

        # 对范围内所有敌人造成伤害
        for enemy in Event.Game.g_enemies:
            dx = enemy.x - bullet.x
            dy = enemy.y - bullet.y
            distance = math.sqrt(dx**2 + dy**2)

            if distance <= bullet.explosion_radius:
                # 范围伤害
                damage = int(bullet.hurt * (1 - distance / bullet.explosion_radius))
                enemy.live -= damage


class WaveShot:
    """波动弹：子弹呈波浪形前进"""
    @staticmethod
    def shoot(player):
        if time.time() - player.lasttime > player.sleepbumbtime:
            player.lasttime = time.time()

            # 根据火力等级调整波动弹数量
            from Statement.State import State
            if player.statement == State.NORMAL:
                bullet_count = 2
                wave_amplitude = 25
            elif player.statement == State.DOUBLE:
                bullet_count = 3
                wave_amplitude = 30
            elif player.statement == State.TWINBLE:
                bullet_count = 4
                wave_amplitude = 35
            else:  # FINAL
                bullet_count = 5
                wave_amplitude = 40

            for i in range(bullet_count):
                bullet = WaterBumb(player.x, player.y + 20 + i * 12, player.hurt)
                bullet.is_wave = True
                bullet.wave_amplitude = wave_amplitude
                bullet.wave_frequency = 0.1
                bullet.wave_phase = i * 60  # 每个子弹相位不同
                player.allbumb.append(bullet)

    @staticmethod
    def update_bullet(bullet):
        """更新波动弹轨迹"""
        if not hasattr(bullet, 'is_wave') or not bullet.is_wave:
            return

        # 正弦波轨迹
        bullet.y += math.sin(bullet.x * bullet.wave_frequency + bullet.wave_phase) * 2


class SpiralShot:
    """螺旋弹：环绕玩家旋转后射出"""
    def __init__(self):
        self.spiral_angle = 0
        self.last_shoot_time = 0

    def shoot(self, player):
        if time.time() - self.last_shoot_time > player.sleepbumbtime * 0.8:
            self.last_shoot_time = time.time()

            # 根据火力等级调整螺旋弹方向数和半径
            from Statement.State import State
            if player.statement == State.NORMAL:
                direction_count = 3
                spiral_radius = 40
                angle_offsets = [0, 120, 240]
            elif player.statement == State.DOUBLE:
                direction_count = 4
                spiral_radius = 50
                angle_offsets = [0, 90, 180, 270]
            elif player.statement == State.TWINBLE:
                direction_count = 6
                spiral_radius = 55
                angle_offsets = [0, 60, 120, 180, 240, 300]
            else:  # FINAL
                direction_count = 8
                spiral_radius = 60
                angle_offsets = [0, 45, 90, 135, 180, 225, 270, 315]

            # 多个方向同时发射
            for offset in angle_offsets:
                angle = self.spiral_angle + offset
                bullet = WaterBumb(player.x, player.y + 20, player.hurt)
                bullet.is_spiral = True
                bullet.spiral_angle = math.radians(angle)
                bullet.spiral_radius = spiral_radius
                bullet.spiral_speed = 10
                bullet.canMove = False  # 螺旋弹的移动由update_bullet完全控制
                player.allbumb.append(bullet)

            self.spiral_angle = (self.spiral_angle + 15) % 360

    def update_bullet(self, bullet):
        """更新螺旋弹轨迹"""
        if not hasattr(bullet, 'is_spiral') or not bullet.is_spiral:
            return

        # 螺旋轨迹
        bullet.spiral_radius -= 2  # 半径逐渐减小
        if bullet.spiral_radius > 0:
            center_x = Event.Game.wateremoji.x
            center_y = Event.Game.wateremoji.y
            bullet.x = center_x + math.cos(bullet.spiral_angle) * bullet.spiral_radius
            bullet.y = center_y + math.sin(bullet.spiral_angle) * bullet.spiral_radius
            bullet.spiral_angle += 0.2
        else:
            # 螺旋结束后，让子弹以当前角度方向直线飞行
            if not hasattr(bullet, 'spiral_ended'):
                bullet.spiral_ended = True
                # 设置子弹方向和速度，让它继续向外飞
                bullet.tan = math.tan(bullet.spiral_angle)
                if -1.57 < bullet.spiral_angle % (2 * math.pi) < 1.57:
                    bullet.sample = 1  # 向右
                else:
                    bullet.sample = -1  # 向左
                bullet.canMove = True  # 恢复自动移动
                bullet.speed = 15  # 设置飞行速度


class WeaponSystem:
    """武器系统管理器"""
    WEAPON_TYPES = {
        'normal': None,  # 默认武器
        'spread': SpreadShot,
        'homing': HomingMissile,
        'laser': LaserBeam,
        'penetrating': PenetratingShot,
        'bombardment': BombardmentShot,
        'wave': WaveShot,
        'spiral': SpiralShot
    }

    def __init__(self):
        self.current_weapon = 'normal'
        self.spiral_shooter = SpiralShot()  # 螺旋弹需要状态

    def switch_weapon(self, weapon_type):
        """切换武器类型"""
        if weapon_type in self.WEAPON_TYPES:
            self.current_weapon = weapon_type
            return True
        return False

    def shoot(self, player):
        """使用当前武器射击"""
        if self.current_weapon == 'normal':
            player.original_shoot()  # 使用原有射击方法（避免递归）
        elif self.current_weapon == 'spiral':
            self.spiral_shooter.shoot(player)
        else:
            weapon_class = self.WEAPON_TYPES[self.current_weapon]
            if weapon_class:
                weapon_class.shoot(player)

    def update_bullets(self, bullets):
        """更新特殊子弹"""
        for bullet in bullets:
            if hasattr(bullet, 'is_homing') and bullet.is_homing:
                HomingMissile.update_bullet(bullet)
            elif hasattr(bullet, 'is_wave') and bullet.is_wave:
                WaveShot.update_bullet(bullet)
            elif hasattr(bullet, 'is_spiral') and bullet.is_spiral:
                self.spiral_shooter.update_bullet(bullet)
