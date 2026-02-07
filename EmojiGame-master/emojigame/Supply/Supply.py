import pygame, time, random, math, Event, main


class Supply(pygame.sprite.Sprite, object):
    def __init__(self, type, x, y):
        pygame.sprite.Sprite.__init__(self)
        self.type = type
        # 尝试加载对应类型的图片，如果不存在则使用默认图片
        try:
            self.image = pygame.image.load('image/supply-' + str(self.type) + '.png')
        except (pygame.error, FileNotFoundError):
            # 如果图片不存在，使用type-1的图片作为备用（或创建一个简单的彩色方块）
            try:
                self.image = pygame.image.load('image/supply-1.png')  # 备用图片
            except:
                # 如果连备用图片都没有，创建一个彩色方块
                self.image = pygame.Surface((20, 20))
                # 根据类型显示不同颜色
                colors = {
                    9: (255, 200, 0),    # 炸弹 - 橙色
                    10: (100, 200, 255),  # 护盾 - 蓝色
                    11: (255, 255, 100),  # 无敌 - 黄色
                    12: (255, 100, 100),  # 清屏 - 红色
                    13: (200, 100, 255),  # 分数加倍 - 紫色
                    14: (100, 255, 100),  # 满血 - 绿色
                    15: (255, 150, 200),  # 武器强化 - 粉色
                }
                color = colors.get(self.type, (150, 150, 150))
                self.image.fill(color)

        self.rect = self.image.get_rect()
        self.x = x
        self.y = y
        self.speed = 105
        self.createtime = time.time()
        self.size = 20
        self.sample = 1
        if random.random() < 0.5:
            self.tan = -2 * random.random()
        else:
            self.tan = 2 * random.random()

    def move(self, screen):  # 补给的移动
        if self.sample == 1:
            self.x -= math.sqrt(self.speed / (1 + self.tan ** 2))
            self.y -= math.sqrt(self.speed / (1 + self.tan ** 2)) * self.tan
        elif self.sample == -1:
            self.x += math.sqrt(self.speed / (1 + self.tan ** 2))
            self.y += math.sqrt(self.speed / (1 + self.tan ** 2)) * self.tan
        elif self.sample == 0:
            if self.ex - self.x > 0:
                self.x += self.speed
            elif self.ex - self.x < 0:
                self.x -= self.speed
        self.rect.left = self.x
        self.rect.top = self.y
        screen.blit(self.image, (self.x, self.y))
        # 优化：移除不必要的线程，直接调用计算函数
        self.calu()

    def calu(self):
        self.ex = Event.Game.wateremoji.x
        self.ey = Event.Game.wateremoji.y
        if self.ex - self.x != 0:
            self.tan = (self.ey - self.y) / (self.ex - self.x)
        else:
            self.tan = 0
            self.sample = 0
        if self.ex - self.x < 0:
            self.sample = 1
        elif self.ex - self.x > 0:
            self.sample = -1

    def attract(self):  # 补给被吸收
        if self.type == 1:
            if Event.Game.wateremoji.live < Event.Game.wateremoji.maxlive:
                Event.Game.wateremoji.live += int(8 + 4 * random.random())
                if Event.Game.wateremoji.live > Event.Game.wateremoji.maxlive:
                    Event.Game.wateremoji.live = Event.Game.wateremoji.maxlive
        elif self.type == 2:
            Event.Game.wateremoji.grade += 1
            Event.Game.wateremoji.upgrading()
        elif self.type == 3:
            Event.Game.wateremoji.sleepbumbtime -= 0.1
            if Event.Game.wateremoji.sleepbumbtime <= 0.125:
                Event.Game.wateremoji.sleepbumbtime = 0.125
        elif self.type == 4:
            Event.Game.money += 10
        elif self.type == 5:
            Event.Game.money += 50
        elif self.type == 6:
            Event.Game.money += 400
        elif self.type == 0:
            Event.Game.wateremoji.hurt += 2  # 力量药水
        elif self.type == 7:
            if Event.Game.wateremoji.maxlive <= 40:
                Event.Game.wateremoji.maxlive += 4
            else:
                Event.Game.wateremoji.maxlive = 40
        elif self.type == 8:
            Event.Game.power += random.randint(1, 3)
            if Event.Game.power > 100:
                Event.Game.power = 100
        # 新增补给类型
        elif self.type == 9:
            # 炸弹补给
            if Event.Game.wateremoji.bombs < Event.Game.wateremoji.max_bombs:
                Event.Game.wateremoji.bombs += 1
        elif self.type == 10:
            # 护盾补给
            if Event.Game.wateremoji.shield < Event.Game.wateremoji.max_shield:
                Event.Game.wateremoji.shield += 1
        elif self.type == 11:
            # 临时无敌（3秒）
            Event.Game.invincible_until = time.time() + 3
        elif self.type == 12:
            # 全屏清除敌弹（不消耗bomb）
            Event.Game.allenbumbs.clear()
        elif self.type == 13:
            # 分数加倍（10秒）
            if Event.Game.score_system:
                Event.Game.score_system.temp_multiplier = 2.0
                Event.Game.score_system.multiplier_end_time = time.time() + 10
            Event.Game.score_multiplier = 2
            Event.Game.multiplier_end_time = time.time() + 10
        elif self.type == 14:
            # 满血恢复
            Event.Game.wateremoji.live = Event.Game.wateremoji.maxlive
        elif self.type == 15:
            # 武器临时强化（5秒满级火力）
            Event.Game.temp_max_power_until = time.time() + 5
