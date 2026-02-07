import time,pygame
from Bullut.Bumb import *

# 定义emoji类
class Emoji(pygame.sprite.Sprite,object):
    def __init__(self):
        pygame.sprite.Sprite.__init__(self)
        self.sleepbumbtime = 0.325
        self.lasttime = time.time()
        self.allbumb = []
        self.live = 50
        self.maxlive = 100
        self.movetime = 0.12

    def draw(self, screen):
        screen.blit(self.image, (self.x, self.y))

