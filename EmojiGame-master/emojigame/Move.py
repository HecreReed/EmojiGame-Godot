from ctypes import windll
import pygame

def moveWin(x, y):
    hwnd = pygame.display.get_wm_info()['window']
    w, h = pygame.display.get_surface().get_size()
    windll.user32.MoveWindow(hwnd, x, y, w, h, False)
