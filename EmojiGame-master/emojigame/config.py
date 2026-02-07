# coding = utf-8
"""
游戏配置文件 - 存储所有游戏常量
将魔术数字集中管理，便于调整游戏平衡性
"""

# 窗口设置
WINDOW_WIDTH = 1280  # 原来640
WINDOW_HEIGHT = 960  # 原来480
FPS = 60

# 游戏时间设置
INVINCIBILITY_TIME = 1.0  # 受击后无敌时间（秒）
BOSS_SPAWN_MIN_TIME = 50  # Boss最小生成间隔（秒）
BOSS_SPAWN_MAX_TIME = 60  # Boss最大生成间隔（秒）
SUPPLY_LIFETIME_MIN = 18  # 补给最小存在时间（秒）
SUPPLY_LIFETIME_MAX = 21  # 补给最大存在时间（秒）

# 玩家设置
PLAYER_MAX_LIFE = 100  # 玩家初始最大生命值
PLAYER_INITIAL_HURT = 10  # 玩家初始伤害
PLAYER_SIZE = 40  # 玩家图像大小
PLAYER_INITIAL_SHOOT_INTERVAL = 0.6  # 初始射击间隔
PLAYER_MIN_SHOOT_INTERVAL = 0.125  # 最小射击间隔

# 东方风格判定点系统
PLAYER_HITBOX_SIZE = 4  # 判定点半径（像素）
PLAYER_NORMAL_SPEED = 5  # 正常移动速度
PLAYER_FOCUSED_SPEED = 2  # 精确移动速度（按住Shift）
HITBOX_COLOR_INNER = (255, 0, 0)  # 判定点内部颜色（红色）
HITBOX_COLOR_OUTER = (255, 255, 255)  # 判定点外圈颜色（白色）

# Boss设置
BOSS_BASE_HP = 1200  # Boss基础生命值（乘以玩家等级）
BOSS_HP_INCREMENT = 1500  # 每次击败Boss后增加的生命值
BOSS_SIZE = 80  # Boss图像大小
BOSS_DEFAULT_SPEED = 2  # Boss默认移动速度
BOSS_DEFAULT_SHOOT_INTERVAL = 0.6  # Boss默认射击间隔

# Boss1（唐氏）设置
BOSS1_BACKGROUND_SWITCH_TIME = 0.677  # 背景切换时间间隔

# Boss2设置
BOSS2_SHOOT_INTERVAL = 5.0
BOSS2_SPEED = 4

# Boss3设置
BOSS3_SHOOT_INTERVAL = 1.5

# Boss4和Boss5设置
BOSS45_SHOOT_INTERVAL = 1.8

# 敌人设置
ENEMY_BASE_COUNT = 2  # 初始敌人数量
ENEMY_INCREASE_RATE = 1.0 / 15.0  # 每秒增加敌人数量的速率
ENEMY_HP_TYPE1 = 20  # 1型敌人血量
ENEMY_HP_TYPE2 = 50  # 2型敌人血量
ENEMY_HP_TYPE3 = 100  # 3型以上敌人血量

# 移动方向改变概率
ENEMY_DIRECTION_CHANGE_CHANCE = 0.2  # 普通敌人方向改变概率
BOSS_DIRECTION_CHANGE_CHANCE = 0.125  # Boss方向改变概率
DIRECTION_CHANGE_INTERVAL = 0.5  # 方向改变检查间隔

# 敌人移动区域限制
ENEMY_MOVE_AREA_WIDTH_RATIO = 6.0 / 8.0  # Boss在屏幕宽度右侧6/8区域移动

# 补给掉落概率
SUPPLY_DROP_CHANCE_TYPE1 = 0.2  # 1型敌人补给掉落概率
SUPPLY_DROP_CHANCE_TYPE2 = 0.3  # 2型敌人补给掉落概率
SUPPLY_DROP_CHANCE_TYPE3 = 0.5  # 3型及以上敌人补给掉落概率
SUPPLY_DROP_CHANCE_TELEPORT = 0.6  # 传送门敌人补给掉落概率
SUPPLY_MONEY_DROP_MULTIPLIER = 1.7  # 金钱补给掉落概率倍数

# 补给效果
SUPPLY_HEAL_BASE = 8  # 治疗补给基础回复量
SUPPLY_HEAL_RANDOM = 4  # 治疗补给随机回复量
SUPPLY_SHOOT_INTERVAL_DECREASE = 0.1  # 射速提升补给效果
SUPPLY_MONEY_SMALL = 10  # 小金钱补给
SUPPLY_MONEY_MEDIUM = 50  # 中等金钱补给
SUPPLY_MONEY_LARGE = 400  # 大金钱补给
SUPPLY_POWER_INCREASE = 2  # 力量补给增加伤害
SUPPLY_MAX_HP_INCREASE = 4  # 最大生命值提升
SUPPLY_MAX_HP_LIMIT = 40  # 最大生命值上限
SUPPLY_POWER_BAR_INCREASE_MIN = 1  # 能量条增加最小值
SUPPLY_POWER_BAR_INCREASE_MAX = 3  # 能量条增加最大值
SUPPLY_POWER_BAR_MAX = 100  # 能量条最大值

# 技能设置
SKILL_COST_CRAZY_SHOOT = 0  # 疯狂射击技能消耗
SKILL_COST_BLOW = 0  # 吹走子弹技能消耗
SKILL_COST_TIMESTOP = 0  # 时间停止技能消耗
TIMESTOP_DURATION = 2.0  # 时间停止持续时间（秒）

# Boss血条设置
BOSS_HP_BAR_X = 70
BOSS_HP_BAR_Y = 10
BOSS_HP_BAR_WIDTH = 500
BOSS_HP_BAR_HEIGHT = 20

# 能量条设置
POWER_BAR_X = 40
POWER_BAR_Y = 440
POWER_BAR_WIDTH = 120
POWER_BAR_HEIGHT = 20

# 颜色定义
COLOR_BLACK = (0, 0, 0)
COLOR_GRAY = (123, 123, 123)
COLOR_RED = (255, 0, 0)
COLOR_BLUE = (0, 0, 255)
COLOR_PINK = (199, 21, 133)

# 玩家血条设置
PLAYER_HP_BAR_WIDTH = 40
PLAYER_HP_BAR_HEIGHT = 5
PLAYER_HP_BAR_OFFSET_Y = -10
PLAYER_HP_BAR_TEXT_OFFSET_Y = -15

# 敌人血条设置
ENEMY_HP_BAR_WIDTH = 40
ENEMY_HP_BAR_HEIGHT = 5
ENEMY_HP_BAR_OFFSET_Y = -10

# 子弹设置
BULLET_SIZE = 20  # 子弹默认大小
BULLET_SPEED_DEFAULT = 10  # 默认子弹速度
BOSS2_BULLET_SPEED = 8  # Boss2特殊子弹速度

# 补给移动设置
SUPPLY_SPEED = 105  # 补给移动速度
SUPPLY_TAN_MAX = 2.0  # 补给移动角度最大值
SUPPLY_SIZE = 20  # 补给图像大小
