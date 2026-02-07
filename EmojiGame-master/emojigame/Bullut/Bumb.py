import pygame, math, random


class Bumb(pygame.sprite.Sprite, object):
    def __init__(self, x, y):
        pygame.sprite.Sprite.__init__(self)
        self.direction = 'right'
        self.image = pygame.image.load('image/waterbullut.png')
        self.x = x
        self.y = y
        self.speed = 18
        self.tan = 0
        self.canReturn = False
        self.sample = 0
        self.hurt = random.randint(8, 9)
        self.canDelete = True  # 碰到对象后消失
        self.canMove = True
        self.banRemove = False

    def draw(self, screen):
        if self.canMove:
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
        screen.blit(self.image, (self.x, self.y))
