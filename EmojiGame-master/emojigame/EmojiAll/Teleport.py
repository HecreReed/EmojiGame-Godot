import EmojiAll.Ememies, pygame

from Event import *


class Teleport(EmojiAll.Ememies.Enemy):
    def __init__(self):
        EmojiAll.Ememies.Enemy.__init__(self)
        self.rint = 0.5
        Game.haveTeleport = True
        self.maxlive = 100 * Game.bossdeathtimes
        self.live = 100 * Game.bossdeathtimes
        self.image = pygame.image.load('image/teleport.png')

    def shoot(self):
        pass

    def move(self):
        pass
