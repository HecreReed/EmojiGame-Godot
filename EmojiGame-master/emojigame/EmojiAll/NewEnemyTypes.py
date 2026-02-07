"""
新增敌人类型系统
包含多种特殊行为的敌人，让小怪阶段更有趣
"""
import random
import time
import pygame
import math
import Event
import main
from EmojiAll.Ememies import Enemy
from Bullut.EnemiesBumb import EmemiesBumb


class FastEnemy(Enemy):
    """快速敌人：移动速度是普通敌人的2倍，血量较低"""
    def __init__(self):
        super().__init__()
        self.speed = 6  # 2倍速度
        self.maxlive = 20 * Event.Game.bossdeathtimes
        self.live = self.maxlive
        self.rint = 11  # 新敌人类型ID
        self.sleepbumbtime = 0.4  # 射击较快
        # 快速移动模式
        self.move_pattern = random.choice(['zigzag', 'dash'])
        self.move_timer = 0

    def move(self):
        """特殊移动模式"""
        if self.move_pattern == 'zigzag':
            # 之字形移动
            self.x -= self.speed
            self.y += math.sin(self.x * 0.1) * 5
        elif self.move_pattern == 'dash':
            # 突进移动
            if time.time() - self.move_timer > 1:
                self.speed = 15  # 突然加速
                self.move_timer = time.time()
            elif time.time() - self.move_timer > 0.3:
                self.speed = 3  # 减速
            self.x -= self.speed


class TankEnemy(Enemy):
    """坦克敌人：移动缓慢，血量是普通敌人的3倍"""
    def __init__(self):
        super().__init__()
        self.speed = 1  # 慢速
        self.maxlive = 150 * Event.Game.bossdeathtimes
        self.live = self.maxlive
        self.rint = 12
        self.sleepbumbtime = 1.5
        self.size_multiplier = 1.5  # 体型更大


class SuicideEnemy(Enemy):
    """自爆敌人：会追踪玩家并自爆，造成大量弹幕"""
    def __init__(self):
        super().__init__()
        self.speed = 4
        self.maxlive = 30 * Event.Game.bossdeathtimes
        self.live = self.maxlive
        self.rint = 13
        self.canShoot = False  # 不射击，靠自爆
        self.tracking = True  # 追踪玩家
        self.exploded = False

    def move(self):
        """追踪玩家移动"""
        if hasattr(Event.Game, 'wateremoji'):
            player = Event.Game.wateremoji
            dx = player.x - self.x
            dy = player.y - self.y
            distance = math.sqrt(dx**2 + dy**2)

            if distance > 5:
                # 向玩家方向移动
                self.x += (dx / distance) * self.speed
                self.y += (dy / distance) * self.speed
            elif not self.exploded:
                # 接近玩家，自爆
                self.explode()

    def explode(self):
        """自爆，发射环形弹幕"""
        self.exploded = True
        for angle in range(0, 360, 15):
            newbumb = EmemiesBumb(self.x, self.y)
            newbumb.speed = 10
            newbumb.tan = math.tan(math.radians(angle))
            if 90 < angle < 270:
                newbumb.sample = 1
            else:
                newbumb.sample = -1
            Event.Game.allenbumbs.append(newbumb)
        # 自毁
        self.live = 0


class SniperEnemy(Enemy):
    """狙击敌人：停留在远处，精确射击玩家"""
    def __init__(self):
        super().__init__()
        self.speed = 2
        self.maxlive = 60 * Event.Game.bossdeathtimes
        self.live = self.maxlive
        self.rint = 14
        self.sleepbumbtime = 2.5  # 射速慢但精准
        self.stop_distance = 600  # 保持距离

    def shoot(self):
        """精准射击玩家当前位置"""
        if time.time() - self.lasttime > self.sleepbumbtime:
            self.lasttime = time.time()
            player = Event.Game.wateremoji
            dx = player.x - self.x
            dy = player.y - self.y

            # 3连发
            for i in range(3):
                newbumb = EmemiesBumb(self.x, self.y)
                if dx != 0:
                    newbumb.tan = dy / dx
                else:
                    newbumb.tan = 0
                newbumb.speed = 15  # 快速子弹
                if dx < 0:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                Event.Game.allenbumbs.append(newbumb)


class ShieldEnemy(Enemy):
    """护盾敌人：有护盾，必须先打破护盾"""
    def __init__(self):
        super().__init__()
        self.speed = 2
        self.maxlive = 80 * Event.Game.bossdeathtimes
        self.live = self.maxlive
        self.rint = 15
        self.shield_hp = 100 * Event.Game.bossdeathtimes
        self.has_shield = True

    def take_damage(self, damage):
        """先扣除护盾值"""
        if self.has_shield:
            self.shield_hp -= damage
            if self.shield_hp <= 0:
                self.has_shield = False
                self.live -= abs(self.shield_hp)
        else:
            self.live -= damage


class SplitEnemy(Enemy):
    """分裂敌人：死亡时分裂成2个小敌人"""
    def __init__(self, is_child=False):
        super().__init__()
        self.is_child = is_child
        if is_child:
            self.maxlive = 20 * Event.Game.bossdeathtimes
            self.speed = 5
            self.size_multiplier = 0.5
        else:
            self.maxlive = 100 * Event.Game.bossdeathtimes
            self.speed = 2
        self.live = self.maxlive
        self.rint = 16

    def on_death(self):
        """死亡时分裂"""
        if not self.is_child:
            # 创建2个小敌人
            for i in range(2):
                child = SplitEnemy(is_child=True)
                child.x = self.x + random.randint(-30, 30)
                child.y = self.y + random.randint(-30, 30)
                Event.Game.g_enemies.append(child)


class EliteEnemy(Enemy):
    """精英敌人：各项属性增强，掉落更多补给"""
    def __init__(self, enemy_type='normal'):
        super().__init__()
        self.speed = 3
        self.maxlive = 300 * Event.Game.bossdeathtimes  # 高血量
        self.live = self.maxlive
        self.rint = 17
        self.sleepbumbtime = 0.5
        self.enemy_type = enemy_type
        self.is_elite = True

        # 精英特效
        self.glow_color = (255, 215, 0)  # 金色光晕

    def shoot(self):
        """增强的射击模式"""
        if time.time() - self.lasttime > self.sleepbumbtime:
            self.lasttime = time.time()
            # 扇形弹幕
            for angle in range(-30, 31, 15):
                newbumb = EmemiesBumb(self.x, self.y)
                newbumb.speed = 8
                newbumb.tan = math.tan(math.radians(angle))
                if -90 < angle < 90:
                    newbumb.sample = -1
                else:
                    newbumb.sample = 1
                Event.Game.allenbumbs.append(newbumb)

    def on_death(self):
        """掉落多个补给"""
        # 保证掉落补给
        for i in range(3):
            supply_type = random.choice([1, 2, 3, 4, 5, 9, 10])
            Event.Game.createSupply(supply_type, self.x + i * 20, self.y)


class MiniBoss(Enemy):
    """小Boss：在正式Boss之前出现的小Boss"""
    def __init__(self):
        super().__init__()
        self.speed = 2
        self.maxlive = 800 * Event.Game.bossdeathtimes  # 很高的血量
        self.live = self.maxlive
        self.rint = 18
        self.is_mini_boss = True
        self.sleepbumbtime = 0.8

        # 攻击模式
        self.attack_pattern = 0
        self.pattern_change_time = time.time()

    def update_attack(self):
        """切换攻击模式"""
        if time.time() - self.pattern_change_time > 5:
            self.attack_pattern = (self.attack_pattern + 1) % 3
            self.pattern_change_time = time.time()

    def shoot(self):
        """多种攻击模式"""
        if time.time() - self.lasttime > self.sleepbumbtime:
            self.lasttime = time.time()
            self.update_attack()

            if self.attack_pattern == 0:
                # 模式1：螺旋弹幕
                for angle in range(0, 360, 30):
                    newbumb = EmemiesBumb(self.x, self.y)
                    newbumb.speed = 6
                    offset = time.time() * 100 % 360
                    newbumb.tan = math.tan(math.radians(angle + offset))
                    if 90 < (angle + offset) % 360 < 270:
                        newbumb.sample = 1
                    else:
                        newbumb.sample = -1
                    Event.Game.allenbumbs.append(newbumb)

            elif self.attack_pattern == 1:
                # 模式2：追踪玩家
                player = Event.Game.wateremoji
                dx = player.x - self.x
                dy = player.y - self.y
                for i in range(5):
                    newbumb = EmemiesBumb(self.x, self.y)
                    newbumb.speed = 8
                    if dx != 0:
                        newbumb.tan = dy / dx
                    newbumb.sample = -1 if dx > 0 else 1
                    Event.Game.allenbumbs.append(newbumb)

            else:
                # 模式3：随机散射
                for i in range(8):
                    newbumb = EmemiesBumb(self.x, self.y)
                    newbumb.speed = random.randint(5, 12)
                    newbumb.tan = random.uniform(-2, 2)
                    newbumb.sample = random.choice([-1, 1])
                    Event.Game.allenbumbs.append(newbumb)

    def on_death(self):
        """掉落大量补给"""
        for i in range(5):
            supply_type = random.choice([1, 2, 3, 5, 9, 10, 13, 14])
            Event.Game.createSupply(supply_type, self.x + i * 25, self.y)


def spawn_enemy_wave(wave_number):
    """生成敌人波次

    Args:
        wave_number: 波次编号，越高难度越大
    """
    enemies = []

    if wave_number % 10 == 0:
        # 每10波出现一个小Boss
        enemies.append(MiniBoss())
    elif wave_number % 5 == 0:
        # 每5波出现精英敌人
        for i in range(2):
            enemies.append(EliteEnemy())
    else:
        # 普通波次：混合敌人类型
        enemy_types = [FastEnemy, TankEnemy, SniperEnemy, SplitEnemy]

        # 根据波数增加敌人数量
        enemy_count = min(3 + wave_number // 2, 10)

        for i in range(enemy_count):
            enemy_class = random.choice(enemy_types)
            enemy = enemy_class()
            enemy.x = main.WINDOWWIDTH + i * 100
            enemy.y = random.randint(100, main.WINDOWHEIGHT - 100)
            enemies.append(enemy)

        # 有概率混入自爆敌人
        if random.random() < 0.3:
            suicide = SuicideEnemy()
            suicide.x = main.WINDOWWIDTH
            suicide.y = random.randint(100, main.WINDOWHEIGHT - 100)
            enemies.append(suicide)

    return enemies
