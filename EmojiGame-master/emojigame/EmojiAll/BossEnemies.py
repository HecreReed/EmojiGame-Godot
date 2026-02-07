import random

import EmojiAll.Ememies, time, pygame, Skills.Skills
from Event import *
from Bullut.BossBumb import *
from Bullut.EnemiesBumb import *


class BossEmemy(EmojiAll.Ememies.Enemy):
    def __init__(self, boss_id=None):
        EmojiAll.Ememies.Enemy.__init__(self)

        self.isboss = True
        self.rint = 0
        # Boss顺序登场系统：根据传入的boss_id或击败次数决定Boss编号
        if boss_id is not None:
            self.bossrint = boss_id  # 使用关卡系统指定的Boss ID
        else:
            self.bossrint = ((Game.bossdeathtimes-1) % 6) + 1  # 1-6循环（兼容旧版）

        # 根据Boss编号设置血量（大幅提升5倍）
        base_hp = (1200 * Game.wateremoji.grade + (Game.bossdeathtimes - 1) * 1500) * 5
        # Boss6的血量是普通Boss的5倍（5个阶段，每个阶段相当于一个普通Boss）
        if self.bossrint == 6:
            self.live = base_hp * 5
            self.maxlive = base_hp * 5
        else:
            self.live = base_hp
            self.maxlive = base_hp
        self.image = pygame.image.load('image/bossenemy-' + str(self.bossrint) + '.png')
        self.rect = self.image.get_rect()
        self.imagesize = 80
        self.speed = 2
        self.sleepbumbtime = 0.6
        if self.bossrint == 2:
            self.x = random.randint(800, 1100)  # 调整到新窗口宽度（2倍）
            self.y = -80
            self.direction = 'down'
            self.sleepbumbtime = 5
            self.speed = 4
        if self.bossrint == 3:  # Boss6素材未完成，暂时注释
            self.sleepbumbtime = 1.5
        if self.bossrint == 4 or self.bossrint == 5:
            self.sleepbumbtime = 1.8
            self.x = random.randint(600, 800)  # 调整到新窗口宽度（2倍）
        self.canshoot = True
        self.canmove = True
        self.lastnormaltime = 0

    def thshoot(self):
        e1 = EmemiesBumb(self.x, self.y)
        e1.image = Event.Game.bulluten[4]
        e1.rect = e1.image.get_rect()
        e1.rect.left = e1.x
        e1.rect.top = e1.y
        Game.allenbumbs.append(e1)
        Game.allenbumbs.append(BossBumb(self.x, self.y))
        time.sleep(0.3)
        e2 = EmemiesBumb(self.x, self.y)
        e2.image = Event.Game.bulluten[4]
        e2.rect = e1.image.get_rect()
        e2.rect.left = e1.x
        e2.rect.top = e1.y
        Game.allenbumbs.append(e2)
        Game.allenbumbs.append(BossBumb(self.x, self.y))
        time.sleep(0.3)

    def doubleshoot(self):
        e1 = BossBumb(self.x, self.y)
        e1.image = Event.Game.bulluten[11]
        e1.canReturn = True
        e1.rect = e1.image.get_rect()
        e1.rect.left = e1.x
        e1.rect.top = e1.y
        Game.allenbumbs.append(e1)
        time.sleep(0.2)
        e1 = BossBumb(self.x, self.y)
        e1.image = Event.Game.bulluten[11]
        e1.canReturn = True
        e1.rect = e1.image.get_rect()
        e1.rect.left = e1.x
        e1.rect.top = e1.y
        Game.allenbumbs.append(e1)

    def shoot(self):
        if time.time() - self.lastnormaltime > 1 and self.canshoot:
            if self.bossrint == 2:
                self.lastnormaltime = time.time()
                newbumb = BossBumb(self.x, self.y)
                newbumb.image = Event.Game.bulluten[6]
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                newbumb.canReturn = True
                Game.allenbumbs.append(newbumb)
        if (time.time() - self.lasttime > self.sleepbumbtime) and self.canshoot:
            self.lasttime = time.time()
            if self.bossrint == 5:  # Boss6素材未完成，暂时注释
                th = threading.Thread(target=self.doubleshoot)
                th.daemon = True
                th.start()
            elif self.bossrint != 3:
                newbumb = BossBumb(self.x, self.y)
                if self.bossrint == 4:
                    newbumb.image = Event.Game.bulluten[10]
                if self.bossrint == 2:
                    newbumb.image = Event.Game.bulluten[2]
                    newbumb.speed = 8
                    newbumb.get = True
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Game.allenbumbs.append(newbumb)
            else:
                t1 = threading.Thread(target=self.thshoot)
                t1.daemon = True
                t1.start()

    def move(self):
        if self.canmove is True:
            if self.direction == 'left':
                if self.x >= 6 / 8 * main.WINDOWWIDTH:  # 限制在3/4宽度的右边移动
                    self.x -= self.speed
            elif self.direction == 'right':
                if self.x <= main.WINDOWWIDTH - self.imagesize:
                    self.x += self.speed
            elif self.direction == 'up':
                if self.y >= 0:
                    self.y -= self.speed
            elif self.direction == 'down':
                if self.y <= main.WINDOWHEIGHT - self.imagesize:  # 同上，防止敌军emoji飞出屏幕
                    self.y += self.speed

    def useSkills(self):
        if self.bossrint == 1:
            Skills.Skills.Skills.FirstBossSkill()
        elif self.bossrint == 2:
            Skills.Skills.Skills.SecondBossSkill()
        elif self.bossrint == 3:
            Skills.Skills.Skills.ThirdBossSkill()
        elif self.bossrint == 4:
            Skills.Skills.Skills.ForthBossSkill()
        elif self.bossrint == 5:
            Skills.Skills.Skills.FifthBossSkill()
        elif self.bossrint == 6:
            Skills.Skills.Skills.SixthBossSkill()
