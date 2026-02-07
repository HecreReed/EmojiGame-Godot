import pygame
from Bullut.Bumb import *
from Event import *
import math


class EmemiesBumb(Bumb):
    def __init__(self, x, y):
        Bumb.__init__(self, x, y)
        self.direction = 'left'
        self.image = pygame.image.load('image/enemybullut-1.png')
        self.rect = self.image.get_rect()
        self.speed = random.randint(6, 8)
        self.blow = False
        self.ex = Game.wateremoji.x
        self.ey = Game.wateremoji.y
        self.size = 20
        self.canRemove = True  # 能被任意门消除
