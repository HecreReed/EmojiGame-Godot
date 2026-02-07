import Bullut.EnemiesBumb, math, Event, threading
import pygame


class BossBumb(Bullut.EnemiesBumb.EmemiesBumb):
    def __init__(self, x, y):
        Bullut.EnemiesBumb.EmemiesBumb.__init__(self, x, y)
        self.speed = 13
        self.blow = False
        self.image1 = Event.Game.bulluten[9]
        self.willRotate = False

        if self.ex - self.x != 0:
            self.tan = (self.ey - self.y) / (self.ex - self.x)
        else:
            self.tan = 0
            self.sample = 0
        if self.ex - self.x < 0:
            self.sample = -1
        elif self.ex - self.x > 0:
            self.sample = 1
        self.image = pygame.image.load('image/bossbullut-1.png')
        self.get = False
        if Event.Game.haveBoss is True and Event.Game.boss.bossrint == 3:
            self.image = pygame.image.load('image/bossbullut-6.png')
        self.rect = self.image.get_rect()
        self.rect.left = self.x
        self.rect.top = self.y

    def draw(self, screen):
        if self.canMove:
            self.ex = Event.Game.wateremoji.x
            self.ey = Event.Game.wateremoji.y
            if self.sample == 0:
                if self.direction == 'left':
                    self.x -= self.speed
                elif self.direction == 'right':
                    self.x += self.speed
            elif self.sample == 1:
                self.x += math.sqrt(self.speed / (1 + self.tan ** 2))
                self.y += math.sqrt(self.speed / (1 + self.tan ** 2)) * self.tan
            elif self.sample == -1:
                self.x -= math.sqrt(self.speed / (1 + self.tan ** 2))
                self.y -= math.sqrt(self.speed / (1 + self.tan ** 2)) * self.tan
        self.rect.left = self.x
        self.rect.top = self.y
        try:
            if not self.willRotate:
                screen.blit(self.image, (self.x, self.y))
            else:
                screen.blit(self.image1, (self.x, self.y))
        except pygame.error:
            pass
        if Event.Game.haveBoss is True and Event.Game.boss.bossrint == 2 and self.get and not self.blow:
            t1 = threading.Thread(target=self.calu)
            t1.daemon = True
            t1.start()

    def calu(self):
        if self.ex - self.x != 0:
            self.tan = (self.ey - self.y) / (self.ex - self.x)
        else:
            self.tan = 0
            self.sample = 0
        if self.ex - self.x < 0:
            self.sample = -1
        elif self.ex - self.x > 0:
            self.sample = 1
