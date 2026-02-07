import EmojiAll.Ememies, random, pygame, time, threading
from Event import *
from Bullut.EnemiesBumb import *


class SummonEnemies(EmojiAll.Ememies.Enemy):
    def __init__(self):
        EmojiAll.Ememies.Enemy.__init__(self)
        self.speed = 3
        self.rint = -random.randint(1, 2)
        self.image = pygame.image.load('image/enemy-' + str(self.rint) + '.png')

    def doubleshoot(self):
        Game.allenbumbs.append(EmemiesBumb(self.x, self.y))
        time.sleep(0.2)
        Game.allenbumbs.append(EmemiesBumb(self.x, self.y))

    def shoot(self):
        if (time.time() - self.lasttime > self.sleepbumbtime):
            self.lasttime = time.time()
            t1 = threading.Thread(target=self.doubleshoot)
            t1.daemon = True
            t1.start()
    def move(self):
        if self.direction == 'left':
            if self.x >= 2 / 4 * main.WINDOWWIDTH:  # 限制在2/4宽度的右边移动
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
            if self.y <= main.WINDOWHEIGHT - self.imagesize:  # 同上，防止敌军emoji飞出屏幕
                self.y += self.speed