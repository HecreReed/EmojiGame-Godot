from Bullut.Bumb import *
from Statement.State import *


class WaterBumb(Bumb):
    def __init__(self, x, y,hurt):
        Bumb.__init__(self, x, y)
        self.rect = self.image.get_rect()
        self.hurt = hurt
        self.Remove = True
