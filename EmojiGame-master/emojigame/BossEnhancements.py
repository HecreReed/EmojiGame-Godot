"""
Boss机制增强系统
为Boss添加护盾、阶段切换、召唤等复杂机制
"""
import time
import random
import pygame
import Event
from EmojiAll.NewEnemyTypes import FastEnemy, TankEnemy, SuicideEnemy


class BossEnhancement:
    """Boss增强系统基类"""

    def __init__(self, boss):
        self.boss = boss
        self.active = True

    def update(self):
        """每帧更新"""
        pass

    def on_damage(self, damage):
        """受伤时触发"""
        return damage

    def on_phase_change(self):
        """阶段切换时触发"""
        pass


class ShieldPhase(BossEnhancement):
    """护盾阶段：Boss有一个必须先打破的护盾"""

    def __init__(self, boss, shield_hp_multiplier=0.5):
        super().__init__(boss)
        self.shield_hp = int(boss.maxlive * shield_hp_multiplier)
        self.max_shield_hp = self.shield_hp
        self.shield_active = True

        # 护盾再生
        self.shield_regen_rate = boss.maxlive * 0.01  # 每秒恢复1%最大护盾值
        self.last_damage_time = time.time()
        self.regen_delay = 5  # 5秒不受伤后开始再生

    def update(self):
        """更新护盾"""
        if not self.shield_active and time.time() - self.last_damage_time > self.regen_delay:
            # 护盾再生
            self.shield_hp += self.shield_regen_rate
            if self.shield_hp >= self.max_shield_hp:
                self.shield_hp = self.max_shield_hp
                self.shield_active = True

    def on_damage(self, damage):
        """先扣除护盾值"""
        self.last_damage_time = time.time()

        if self.shield_active:
            self.shield_hp -= damage
            if self.shield_hp <= 0:
                self.shield_active = False
                # 护盾破碎，剩余伤害作用于Boss
                return abs(self.shield_hp)
            return 0  # 护盾吸收所有伤害
        else:
            return damage  # 护盾已破，正常受伤


class InvincibilityPhase(BossEnhancement):
    """无敌阶段：Boss周期性进入无敌状态"""

    def __init__(self, boss, invincible_duration=3, cycle_duration=15):
        super().__init__(boss)
        self.invincible_duration = invincible_duration  # 无敌持续时间
        self.cycle_duration = cycle_duration  # 循环周期
        self.last_cycle_time = time.time()
        self.is_invincible = False
        self.invincible_start_time = 0

    def update(self):
        """更新无敌状态"""
        current_time = time.time()

        if not self.is_invincible:
            # 检查是否应该进入无敌
            if current_time - self.last_cycle_time >= self.cycle_duration:
                self.is_invincible = True
                self.invincible_start_time = current_time
                self.last_cycle_time = current_time
        else:
            # 检查无敌是否结束
            if current_time - self.invincible_start_time >= self.invincible_duration:
                self.is_invincible = False

    def on_damage(self, damage):
        """无敌时免疫伤害"""
        if self.is_invincible:
            return 0
        return damage


class SummonPhase(BossEnhancement):
    """召唤阶段：Boss会召唤小怪"""

    def __init__(self, boss, summon_interval=10, summon_count=3):
        super().__init__(boss)
        self.summon_interval = summon_interval  # 召唤间隔
        self.summon_count = summon_count  # 每次召唤数量
        self.last_summon_time = time.time()

        # 小怪类型池
        self.minion_types = [FastEnemy, TankEnemy, SuicideEnemy]

    def update(self):
        """周期性召唤小怪"""
        current_time = time.time()

        if current_time - self.last_summon_time >= self.summon_interval:
            self.summon_minions()
            self.last_summon_time = current_time

    def summon_minions(self):
        """召唤小怪"""
        for i in range(self.summon_count):
            minion_class = random.choice(self.minion_types)
            minion = minion_class()

            # 在Boss周围生成
            minion.x = self.boss.x + random.randint(-100, 100)
            minion.y = self.boss.y + random.randint(-100, 100)

            Event.Game.g_enemies.append(minion)


class EnragePhase(BossEnhancement):
    """狂暴阶段：Boss血量低于阈值时狂暴，攻击力和速度提升"""

    def __init__(self, boss, enrage_threshold=0.3, damage_multiplier=2, speed_multiplier=1.5):
        super().__init__(boss)
        self.enrage_threshold = enrage_threshold  # 狂暴血量阈值（百分比）
        self.damage_multiplier = damage_multiplier
        self.speed_multiplier = speed_multiplier
        self.is_enraged = False
        self.original_speed = boss.speed
        self.original_shoot_interval = boss.sleepbumbtime

    def update(self):
        """检查是否应该狂暴"""
        hp_percentage = self.boss.live / self.boss.maxlive

        if not self.is_enraged and hp_percentage <= self.enrage_threshold:
            # 进入狂暴
            self.is_enraged = True
            self.boss.speed = int(self.original_speed * self.speed_multiplier)
            self.boss.sleepbumbtime = self.original_shoot_interval / self.damage_multiplier


class PhaseTransition(BossEnhancement):
    """阶段转换：Boss在不同血量段有不同的攻击模式"""

    def __init__(self, boss, phase_thresholds=[0.75, 0.5, 0.25]):
        super().__init__(boss)
        self.phase_thresholds = sorted(phase_thresholds, reverse=True)  # 从高到低
        self.current_phase = 0
        self.phases_triggered = set()

    def update(self):
        """检查阶段转换"""
        hp_percentage = self.boss.live / self.boss.maxlive

        for i, threshold in enumerate(self.phase_thresholds):
            if hp_percentage <= threshold and i not in self.phases_triggered:
                self.trigger_phase(i)
                self.phases_triggered.add(i)
                self.current_phase = i + 1
                break

    def trigger_phase(self, phase_num):
        """触发阶段转换"""
        # 清空屏幕子弹
        Event.Game.allenbumbs.clear()

        # 根据阶段改变攻击模式
        if phase_num == 0:
            # 第一次转换：提升射速
            self.boss.sleepbumbtime *= 0.8
        elif phase_num == 1:
            # 第二次转换：提升移动速度
            self.boss.speed *= 1.5
        elif phase_num == 2:
            # 第三次转换：狂暴模式
            self.boss.sleepbumbtime *= 0.6
            self.boss.speed *= 1.5


class AbsorbShield(BossEnhancement):
    """吸收护盾：吸收一定数量的伤害"""

    def __init__(self, boss, absorb_count=10):
        super().__init__(boss)
        self.absorb_count = absorb_count  # 可以吸收的攻击次数
        self.absorb_remaining = absorb_count

    def on_damage(self, damage):
        """吸收攻击"""
        if self.absorb_remaining > 0:
            self.absorb_remaining -= 1
            return 0  # 完全吸收
        return damage  # 护盾耗尽，正常受伤


class BerserkCounter(BossEnhancement):
    """狂暴计数器：受到一定次数攻击后反击"""

    def __init__(self, boss, counter_threshold=20):
        super().__init__(boss)
        self.counter_threshold = counter_threshold
        self.hit_count = 0

    def on_damage(self, damage):
        """计数攻击次数"""
        self.hit_count += 1

        if self.hit_count >= self.counter_threshold:
            # 触发反击
            self.counter_attack()
            self.hit_count = 0

        return damage

    def counter_attack(self):
        """反击：发射大量弹幕"""
        import math
        from Bullut.BossBumb import BossBumb

        # 环形弹幕
        for angle in range(0, 360, 10):
            newbumb = BossBumb(self.boss.x, self.boss.y)
            newbumb.speed = 12
            newbumb.tan = math.tan(math.radians(angle))
            if 90 < angle < 270:
                newbumb.sample = 1
            else:
                newbumb.sample = -1
            Event.Game.allenbumbs.append(newbumb)


class BossEnhancementManager:
    """Boss增强管理器"""

    def __init__(self, boss):
        self.boss = boss
        self.enhancements = []

    def add_enhancement(self, enhancement):
        """添加增强"""
        self.enhancements.append(enhancement)

    def update(self):
        """更新所有增强"""
        for enhancement in self.enhancements:
            if enhancement.active:
                enhancement.update()

    def process_damage(self, damage):
        """处理伤害（通过所有增强层）"""
        final_damage = damage

        for enhancement in self.enhancements:
            if enhancement.active:
                final_damage = enhancement.on_damage(final_damage)

        return final_damage

    def add_random_enhancements(self, count=2):
        """随机添加增强（用于增加游戏变化性）"""
        available_enhancements = [
            lambda: ShieldPhase(self.boss, 0.5),
            lambda: InvincibilityPhase(self.boss, 3, 15),
            lambda: SummonPhase(self.boss, 12, 2),
            lambda: EnragePhase(self.boss, 0.3, 2, 1.5),
            lambda: PhaseTransition(self.boss, [0.75, 0.5, 0.25]),
            lambda: AbsorbShield(self.boss, 15),
            lambda: BerserkCounter(self.boss, 25)
        ]

        # 随机选择增强
        selected = random.sample(available_enhancements, min(count, len(available_enhancements)))

        for enhancement_creator in selected:
            self.add_enhancement(enhancement_creator())


def apply_boss_enhancements(boss, difficulty_level=1):
    """为Boss应用增强

    Args:
        boss: Boss对象
        difficulty_level: 难度等级（1-5）

    Returns:
        BossEnhancementManager
    """
    manager = BossEnhancementManager(boss)

    # 根据难度应用不同数量的增强
    if difficulty_level == 1:
        # 简单：只有一个增强
        manager.add_enhancement(ShieldPhase(boss, 0.3))
    elif difficulty_level == 2:
        # 普通：两个增强
        manager.add_enhancement(ShieldPhase(boss, 0.4))
        manager.add_enhancement(EnragePhase(boss, 0.25, 1.5, 1.3))
    elif difficulty_level == 3:
        # 困难：三个增强
        manager.add_enhancement(ShieldPhase(boss, 0.5))
        manager.add_enhancement(PhaseTransition(boss, [0.75, 0.5, 0.25]))
        manager.add_enhancement(SummonPhase(boss, 15, 2))
    elif difficulty_level == 4:
        # 非常困难：四个增强
        manager.add_enhancement(ShieldPhase(boss, 0.6))
        manager.add_enhancement(InvincibilityPhase(boss, 3, 12))
        manager.add_enhancement(EnragePhase(boss, 0.3, 2, 1.5))
        manager.add_enhancement(SummonPhase(boss, 12, 3))
    else:  # difficulty_level >= 5
        # 地狱：全部增强
        manager.add_enhancement(ShieldPhase(boss, 0.7))
        manager.add_enhancement(InvincibilityPhase(boss, 4, 10))
        manager.add_enhancement(PhaseTransition(boss, [0.75, 0.5, 0.25]))
        manager.add_enhancement(EnragePhase(boss, 0.35, 2.5, 2))
        manager.add_enhancement(SummonPhase(boss, 10, 4))
        manager.add_enhancement(BerserkCounter(boss, 20))

    return manager
