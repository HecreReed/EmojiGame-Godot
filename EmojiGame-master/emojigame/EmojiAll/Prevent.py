import pygame, Event


class Prevent(pygame.sprite.Sprite):
    def __init__(self, x, y):
        pygame.sprite.Sprite.__init__(self)
        self.image = pygame.image.load('image/prevent.png')
        Event.Game.allprevent.append(self)
        self.x = x
        self.y = y
        self.rect = self.image.get_rect()
        self.rect.left = x
        self.rect.top = y
