"""
连击和分数倍增系统
让游戏更有节奏感和成就感
"""
import time


class ComboSystem:
    """连击系统"""

    def __init__(self):
        self.combo = 0  # 当前连击数
        self.max_combo = 0  # 最高连击数
        self.last_kill_time = 0  # 上次击杀时间
        self.combo_timeout = 3  # 连击超时时间（秒）

        # 连击等级奖励
        self.combo_levels = {
            10: 1.5,  # 10连击：1.5倍分数
            25: 2.0,  # 25连击：2倍分数
            50: 3.0,  # 50连击：3倍分数
            100: 5.0,  # 100连击：5倍分数
            200: 10.0  # 200连击：10倍分数
        }

    def add_kill(self):
        """增加击杀，维持连击"""
        current_time = time.time()

        # 检查连击是否超时
        if current_time - self.last_kill_time > self.combo_timeout:
            self.combo = 0

        self.combo += 1
        self.last_kill_time = current_time

        # 更新最高连击
        if self.combo > self.max_combo:
            self.max_combo = self.combo

        return self.combo

    def get_multiplier(self):
        """获取当前连击倍率"""
        multiplier = 1.0

        # 从高到低检查连击等级
        for threshold in sorted(self.combo_levels.keys(), reverse=True):
            if self.combo >= threshold:
                multiplier = self.combo_levels[threshold]
                break

        return multiplier

    def reset(self):
        """重置连击"""
        self.combo = 0

    def update(self):
        """更新连击状态（每帧调用）"""
        current_time = time.time()
        if self.combo > 0 and current_time - self.last_kill_time > self.combo_timeout:
            self.combo = 0

    def get_combo_level_name(self):
        """获取连击等级名称"""
        if self.combo >= 200:
            return "GODLIKE!"
        elif self.combo >= 100:
            return "LEGENDARY!"
        elif self.combo >= 50:
            return "AMAZING!"
        elif self.combo >= 25:
            return "AWESOME!"
        elif self.combo >= 10:
            return "GREAT!"
        else:
            return ""


class ScoreSystem:
    """分数系统"""

    def __init__(self):
        self.score = 0
        self.high_score = 0
        self.combo_system = ComboSystem()

        # 分数倍增器（临时buff）
        self.temp_multiplier = 1.0
        self.multiplier_end_time = 0

        # 击杀分数基础值
        self.kill_scores = {
            'normal_enemy': 100,
            'fast_enemy': 150,
            'tank_enemy': 200,
            'suicide_enemy': 120,
            'sniper_enemy': 180,
            'shield_enemy': 220,
            'split_enemy': 150,
            'elite_enemy': 500,
            'mini_boss': 2000,
            'boss': 10000
        }

    def add_enemy_kill(self, enemy_type='normal_enemy'):
        """击杀敌人，获得分数"""
        # 基础分数
        base_score = self.kill_scores.get(enemy_type, 100)

        # 连击倍率
        self.combo_system.add_kill()
        combo_multiplier = self.combo_system.get_multiplier()

        # 临时倍率
        current_time = time.time()
        if current_time < self.multiplier_end_time:
            total_multiplier = combo_multiplier * self.temp_multiplier
        else:
            total_multiplier = combo_multiplier
            self.temp_multiplier = 1.0

        # 计算最终分数
        final_score = int(base_score * total_multiplier)
        self.score += final_score

        # 更新最高分
        if self.score > self.high_score:
            self.high_score = self.score

        return final_score

    def activate_score_multiplier(self, multiplier, duration):
        """激活临时分数倍增"""
        self.temp_multiplier = multiplier
        self.multiplier_end_time = time.time() + duration

    def get_total_multiplier(self):
        """获取总倍率"""
        combo_mult = self.combo_system.get_multiplier()

        current_time = time.time()
        if current_time < self.multiplier_end_time:
            return combo_mult * self.temp_multiplier
        else:
            return combo_mult

    def update(self):
        """更新分数系统"""
        self.combo_system.update()

    def reset_for_new_game(self):
        """新游戏重置"""
        self.score = 0
        self.combo_system.reset()
        self.temp_multiplier = 1.0
        self.multiplier_end_time = 0


class AchievementSystem:
    """成就系统"""

    def __init__(self):
        self.achievements = {
            'first_blood': {'unlocked': False, 'name': '首杀', 'desc': '击杀第一个敌人'},
            'combo_10': {'unlocked': False, 'name': '连击新手', 'desc': '达成10连击'},
            'combo_50': {'unlocked': False, 'name': '连击大师', 'desc': '达成50连击'},
            'combo_100': {'unlocked': False, 'name': '连击之神', 'desc': '达成100连击'},
            'score_10k': {'unlocked': False, 'name': '初出茅庐', 'desc': '分数达到10000'},
            'score_100k': {'unlocked': False, 'name': '游戏高手', 'desc': '分数达到100000'},
            'score_1m': {'unlocked': False, 'name': '传奇玩家', 'desc': '分数达到1000000'},
            'boss_1': {'unlocked': False, 'name': 'Boss杀手', 'desc': '击败第一个Boss'},
            'boss_all': {'unlocked': False, 'name': 'Boss终结者', 'desc': '击败所有6个Boss'},
            'no_damage': {'unlocked': False, 'name': '完美闪避', 'desc': '无伤击败一个Boss'},
            'bomb_master': {'unlocked': False, 'name': '炸弹大师', 'desc': '使用10次炸弹'},
            'collector': {'unlocked': False, 'name': '收集狂魔', 'desc': '收集100个补给'},
        }

        self.stats = {
            'total_kills': 0,
            'total_bosses_killed': 0,
            'total_bombs_used': 0,
            'total_supplies_collected': 0,
            'bosses_killed_no_damage': 0
        }

    def check_achievement(self, achievement_id):
        """检查并解锁成就"""
        if achievement_id in self.achievements and not self.achievements[achievement_id]['unlocked']:
            self.achievements[achievement_id]['unlocked'] = True
            return True  # 返回True表示新解锁
        return False

    def update_stats(self, stat_name, value=1):
        """更新统计数据"""
        if stat_name in self.stats:
            self.stats[stat_name] += value

            # 检查相关成就
            self._check_stat_achievements()

    def _check_stat_achievements(self):
        """根据统计数据检查成就"""
        if self.stats['total_kills'] >= 1:
            self.check_achievement('first_blood')

        if self.stats['total_bosses_killed'] >= 1:
            self.check_achievement('boss_1')

        if self.stats['total_bosses_killed'] >= 6:
            self.check_achievement('boss_all')

        if self.stats['total_bombs_used'] >= 10:
            self.check_achievement('bomb_master')

        if self.stats['total_supplies_collected'] >= 100:
            self.check_achievement('collector')

    def get_unlocked_count(self):
        """获取已解锁成就数量"""
        return sum(1 for ach in self.achievements.values() if ach['unlocked'])

    def get_total_count(self):
        """获取总成就数量"""
        return len(self.achievements)
