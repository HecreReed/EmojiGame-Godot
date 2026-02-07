import main, pygame
from EmojiAll.Emoji import *
from Bullut.WaterBumb import *
from Statement.State import *


# 定义流汗黄豆
class WaterEmoji(Emoji):
    def __init__(self):
        Emoji.__init__(self)
        self.imagesourance = 'image/wateremoji.png'
        self.image = pygame.image.load(self.imagesourance)
        self.size = 40
        self.rect = self.image.get_rect()
        self.x = 80
        self.y = 220  # 记得没错的话，点应该在左上角而不是在中心捏
        self.type = main.Friend
        self.statement = State.NORMAL
        self.maxlive = 20
        self.live = 20
        self.grade = 1
        self.hurt = random.randint(8, 12)
        self.canShoot = True

        # 东方风格判定点系统
        self.hitbox_size = 4  # 判定点半径（小红点）
        self.is_focused = False  # 是否按住shift（精确移动模式）
        self.ORIGINAL_NORMAL_SPEED = 5  # 原始正常速度（常量，用于恢复）
        self.ORIGINAL_FOCUSED_SPEED = 2  # 原始精确速度（常量，用于恢复）
        self.normal_speed = self.ORIGINAL_NORMAL_SPEED  # 正常移动速度
        self.focused_speed = self.ORIGINAL_FOCUSED_SPEED  # 精确移动速度（按住shift）
        self.slowdown_effects = 0  # 减速效果计数器（解决多重减速竞态条件）

        # 创建判定点的rect用于碰撞检测
        self.hitbox_rect = pygame.Rect(0, 0, self.hitbox_size * 2, self.hitbox_size * 2)
        self.update_hitbox()  # 初始化判定点位置

        # 新增：Bomb系统
        self.bombs = 3  # 初始炸弹数
        self.max_bombs = 8  # 最大炸弹数
        self.bomb_active = False  # 炸弹是否激活中
        self.bomb_start_time = 0  # 炸弹开始时间
        self.bomb_duration = 2  # 炸弹持续时间

        # 新增：护盾系统
        self.shield = 0  # 护盾值
        self.max_shield = 3  # 最大护盾
        self.shield_recharge_time = 0  # 上次受伤时间

        # 新增：冲刺系统
        self.dash_available = True
        self.dash_cooldown = 3  # 冲刺冷却3秒
        self.last_dash_time = 0
        self.is_dashing = False
        self.dash_start_time = 0
        self.dash_duration = 0.2  # 冲刺持续0.2秒
        self.dash_direction = (0, 0)

    def move(self, key):
        # 根据是否按住shift选择移动速度
        speed = self.focused_speed if self.is_focused else self.normal_speed

        if key == 'up' and self.y > 0:
            self.y -= speed
        elif key == 'down' and self.y < main.WINDOWHEIGHT - 40:
            self.y += speed
        elif key == 'right' and self.x < main.WINDOWWIDTH - 40:
            self.x += speed
        elif key == 'left' and self.x > 0:
            self.x -= speed
        elif key == 'right-up' and self.x < main.WINDOWWIDTH - 40 and self.y > 0:
            self.y -= speed
            self.x += speed
        elif key == 'left-up' and self.x > 0 and self.y > 0:
            self.y -= speed
            self.x -= speed
        elif key == 'right-down' and self.x < main.WINDOWWIDTH - 40 and self.y < main.WINDOWHEIGHT - 40:
            self.x += speed
            self.y += speed
        elif key == 'left-down' and self.x > 0 and self.y < main.WINDOWHEIGHT - 40:
            self.x -= speed
            self.y += speed

        # 更新判定点位置（中心点）
        self.update_hitbox()

    def normalshoot(self):
        if (time.time() - self.lasttime > self.sleepbumbtime):
            self.allbumb.append(
                WaterBumb(self.x, self.y + 20, self.hurt + random.randint(2, 4)))  # y加20是因为图片均为40*40像素，确保子弹是由中间发射出来
            self.lasttime = time.time()  # 处理时间间隔

    def doubleshoot(self):
        if (time.time() - self.lasttime > self.sleepbumbtime):
            self.allbumb.append(WaterBumb(self.x, self.y + 35, self.hurt + random.randint(2, 4)))
            self.allbumb.append(WaterBumb(self.x, self.y + 5, self.hurt + random.randint(2, 4)))
            self.lasttime = time.time()

    def twinbleshoot(self):
        if (time.time() - self.lasttime > self.sleepbumbtime):
            self.allbumb.append(WaterBumb(self.x, self.y + 45, self.hurt + random.randint(2, 4)))
            self.allbumb.append(WaterBumb(self.x, self.y + 20, self.hurt + random.randint(2, 4)))
            self.allbumb.append(WaterBumb(self.x, self.y - 5, self.hurt + random.randint(2, 4)))
            self.lasttime = time.time()

    def finalshoot(self):
        if (time.time() - self.lasttime > self.sleepbumbtime):
            self.allbumb.append(WaterBumb(self.x, self.y + 50, self.hurt + random.randint(2, 4)))
            self.allbumb.append(WaterBumb(self.x, self.y + 25, self.hurt + random.randint(2, 4)))
            self.allbumb.append(WaterBumb(self.x, self.y, self.hurt + random.randint(2, 4)))
            self.allbumb.append(WaterBumb(self.x, self.y - 25, self.hurt + random.randint(2, 4)))
            self.lasttime = time.time()

    def original_shoot(self):
        """原版射击系统（供武器系统调用）"""
        # 检查临时满火力buff
        import Event
        original_statement = self.statement
        if time.time() < Event.Game.temp_max_power_until:
            # 临时提升到最高火力
            self.statement = State.FINAL

        if self.statement == State.NORMAL:
            self.normalshoot()
        elif self.statement == State.DOUBLE:
            self.doubleshoot()
        elif self.statement == State.TWINBLE:
            self.twinbleshoot()
        elif self.statement == State.FINAL:
            self.finalshoot()

        # 恢复原始状态
        if time.time() < Event.Game.temp_max_power_until:
            self.statement = original_statement

    def shoot(self):
        if self.canShoot:
            # 检查是否使用武器系统
            import Event
            if Event.Game.weapon_system and Event.Game.weapon_system.current_weapon != 'normal':
                # 使用武器系统射击
                Event.Game.weapon_system.shoot(self)
            else:
                # 使用原版射击系统
                self.original_shoot()

    def upgrading(self):
        if self.grade > 4:
            self.grade = 4
        elif self.grade == 2:
            self.statement = State.DOUBLE
        elif self.grade == 3:
            self.statement = State.TWINBLE
        elif self.grade == 4:
            self.statement = State.FINAL

    def update_hitbox(self):
        """更新判定点位置到角色中心"""
        center_x = self.x + self.size // 2
        center_y = self.y + self.size // 2
        self.hitbox_rect.centerx = center_x
        self.hitbox_rect.centery = center_y

    def get_hitbox_center(self):
        """获取判定点中心坐标"""
        return (self.x + self.size // 2, self.y + self.size // 2)

    def use_bomb(self):
        """使用炸弹"""
        import time
        if self.bombs > 0 and not self.bomb_active:
            self.bombs -= 1
            self.bomb_active = True
            self.bomb_start_time = time.time()
            return True
        return False

    def update_bomb(self):
        """更新炸弹状态"""
        import time
        if self.bomb_active:
            if time.time() - self.bomb_start_time >= self.bomb_duration:
                self.bomb_active = False

    def use_dash(self, direction_x, direction_y):
        """使用冲刺"""
        import time
        current_time = time.time()
        if self.dash_available and current_time - self.last_dash_time >= self.dash_cooldown:
            self.is_dashing = True
            self.dash_start_time = current_time
            self.last_dash_time = current_time
            # 归一化方向
            length = (direction_x**2 + direction_y**2) ** 0.5
            if length > 0:
                self.dash_direction = (direction_x / length, direction_y / length)
            else:
                self.dash_direction = (0, 0)
            return True
        return False

    def update_dash(self):
        """更新冲刺状态"""
        import time
        if self.is_dashing:
            if time.time() - self.dash_start_time >= self.dash_duration:
                self.is_dashing = False
            else:
                # 冲刺移动（快速）
                dash_speed = 30
                new_x = self.x + self.dash_direction[0] * dash_speed
                new_y = self.y + self.dash_direction[1] * dash_speed
                # 边界检查
                if 0 <= new_x <= main.WINDOWWIDTH - 40:
                    self.x = new_x
                if 0 <= new_y <= main.WINDOWHEIGHT - 40:
                    self.y = new_y
                self.update_hitbox()
