import pygame, random
from EmojiAll.Emoji import *
from Statement.Type import *
import Event
from Bullut.EnemiesBumb import *
import Bullt
import main


class Enemy(Emoji):
    def __init__(self, boostspeed=0):
        Emoji.__init__(self)
        self.isboss = False
        self.rint = 1
        if Event.Game.bossdeathtimes - 1 <= 3:
            self.rint = random.randint(1, 4 + Event.Game.bossdeathtimes - 1)
        else:
            self.rint = random.randint(1, 7)
        self.x = 1280  # 调整到新窗口宽度
        self.y = random.randint(0, 880)  # 调整到新窗口高度（960-80留边距）
        self.imagesourance = 'image/enemy-' + str(self.rint) + '.png'
        self.image = pygame.image.load(self.imagesourance)
        self.rect = self.image.get_rect()
        self.canbeshoot = True
        self.basicspeed = 0.8
        self.canChangeMove = True
        if self.rint == 3:
            self.basicspeed = 0.5
        elif self.rint == 2:
            self.basicspeed = 0.8
        elif self.rint == 1:
            self.basicspeed = 1
        self.type = Type.NORMAL_EMOJI
        self.direction = 'left'
        self.boostspeed = 2 * random.random()
        self.speed = self.basicspeed + self.boostspeed
        self.live = 50
        if self.rint == 1:
            self.live = 30 * Event.Game.bossdeathtimes
            self.maxlive = 30 * Event.Game.bossdeathtimes
        elif self.rint == 2:
            self.live = 50 * Event.Game.bossdeathtimes
            self.maxlive = 50 * Event.Game.bossdeathtimes
        elif self.rint == 3:
            self.live = 70 * Event.Game.bossdeathtimes
            self.maxlive = 70 * Event.Game.bossdeathtimes
        elif self.rint == 4:
            self.live = 100 * Event.Game.bossdeathtimes
            self.maxlive = 100 * Event.Game.bossdeathtimes
        elif self.rint == 5:
            self.live = 120 * Event.Game.bossdeathtimes
            self.maxlive = 120 * Event.Game.bossdeathtimes
        elif self.rint == 6:
            self.live = 150 * Event.Game.bossdeathtimes
            self.maxlive = 150 * Event.Game.bossdeathtimes
        elif self.rint == 7:
            self.live = 200 * Event.Game.bossdeathtimes
            self.maxlive = 200 * Event.Game.bossdeathtimes
        self.allbumb = []
        self.sleepbumbtime = 1.8
        self.createtime = time.time()
        self.intervaltime = 0
        self.imagesize = 40
        self.cotime = 0

    def shoot(self):
        if (time.time() - self.lasttime > self.sleepbumbtime):
            self.lasttime = time.time()
            temp = random.random()
            if 6 <= self.rint <= 7:
                if temp < 0.25:
                    self.trackshoot()
                elif 0.25 <= temp < 0.5:
                    self.randomshoot()
                elif 0.5 <= temp < 0.75:
                    self.sandshoot()
                else:
                    self.circleshoot()
            elif 4 <= self.rint < 6:
                if temp < 0.25:
                    self.normalshoot()
                elif 0.25 <= temp < 0.5:
                    self.trackshoot()
                elif 0.5 <= temp < 0.75:
                    self.randomshoot()
                else:
                    self.sandshoot()
            else:
                if temp < 0.33:
                    self.normalshoot()
                elif 0.33 <= temp < 0.67:
                    self.trackshoot()
                else:
                    self.randomshoot()

    def circleshoot(self):
        rive = math.pi / 3
        artan = 0
        lenth = 40
        ex = Event.Game.wateremoji.x
        ey = Event.Game.wateremoji.y
        if ex - self.x != 0:
            tan = (ey - self.y) / (ex - self.x)
        else:
            tan = 0
            sample = 0
        if ex - self.x < 0:
            sample = -1
        elif ex - self.x > 0:
            sample = 1
        for i in range(12):
            sin = math.sin(artan)
            cos = math.cos(artan)
            newbumb = Bullt.BossBumb(self.x + lenth * sin, self.y + lenth * cos)
            newbumb.speed = 7
            newbumb.image = Event.Game.bulluten[7]
            newbumb.sample = sample
            newbumb.tan = tan
            Event.Game.allenbumbs.append(newbumb)
            artan += rive

    def sandshoot(self):
        rive = math.pi / 10
        artan = 0
        index = 0
        timek = 0
        for i in range(8):
            newbumb = Bullt.BossBumb(self.x, self.y)
            newbumb.speed = 8
            newbumb.image = Event.Game.bulluten[8]
            if i != 0:
                if index % 2 != 0:
                    newbumb.tan = math.tan(artan + timek * rive)
                else:
                    newbumb.tan = math.tan(artan - timek * rive)
                    timek += 1
            else:
                artan = math.atan(newbumb.tan)
            Event.Game.allenbumbs.append(newbumb)
            index += 1

    def randomshoot(self):
        bumb = Bullt.BossBumb(self.x, self.y)
        bumb.image = Event.Game.bulluten[8]
        bumb.speed = 30
        bumb.tan = random.random() * 2.4 - 1.2
        Event.Game.allenbumbs.append(bumb)

    def normalshoot(self):
        # 延迟导入以避免循环依赖
        from Bullut.EnemiesBumb import EmemiesBumb
        Event.Game.allenbumbs.append(EmemiesBumb(self.x, self.y))

    def trackshoot(self):
        newbumb = Bullt.BossBumb(self.x, self.y)
        newbumb.image = Event.Game.bulluten[8]
        newbumb.speed = 23
        Event.Game.allenbumbs.append(newbumb)

    def move(self):
        if self.direction == 'left':
            if self.x >= 1 / 4 * main.WINDOWWIDTH:  # 限制在3/4宽度的右边移动
                self.x -= self.speed
        elif self.direction == 'right':
            if self.intervaltime < 18:
                if self.x <= main.WINDOWWIDTH - self.imagesize:
                    self.x += self.speed
            else:
                self.x += self.speed
        elif self.direction == 'up':
            if self.y >= 0:
                self.y -= self.speed
        elif self.direction == 'down':
            if self.canChangeMove:
                if self.y <= main.WINDOWHEIGHT - self.imagesize:  # 同上，防止敌军emoji飞出屏幕
                    self.y += self.speed
            else:
                self.y += self.speed
