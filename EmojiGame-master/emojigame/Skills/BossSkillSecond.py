import time, pygame, win32gui, random, main, Event, Move, threading, Bullt, math, OEmoji, Frame, main, wx


class BossSkillSecond:
    frame1 = object
    frame2 = object
    newbumb = object
    hasAttr = False
    newattr = object
    canmadeinheaven = True

    @classmethod
    def madeinheaven(cls):
        if cls.canmadeinheaven:
            cls.canmadeinheaven = False
            Event.Game.heaven.play()
            Event.Game.boss.movetime = 0.01
            Event.Game.boss.speed = 30
            Event.Game.boss.sleepbumbtime = 1
            Event.Game.boss.image = pygame.image.load('image/madeinheaven.png')
            Event.Game.boss.canbeshoot = False
            time.sleep(8)
            Event.Game.boss.movetime = 0.12
            Event.Game.boss.speed = 4
            Event.Game.boss.sleepbumbtime = 5
            Event.Game.boss.image = pygame.image.load('image/bossenemy-2.png')
            Event.Game.boss.canbeshoot = True
        cls.canmadeinheaven = True

    @classmethod
    def attractMove(cls):
        while cls.hasAttr:
            cls.newattr.x += 5
            cls.newattr.y += 5
            time.sleep(0.1)
            cls.newattr.x -= 5
            cls.newattr.y -= 5
            time.sleep(0.1)
            cls.newattr.x += 5
            cls.newattr.y -= 5
            time.sleep(0.1)
            cls.newattr.x -= 5
            cls.newattr.y += 5
            time.sleep(0.1)

    @classmethod
    def attract(cls):
        while cls.hasAttr:
            while Event.Game.istimestoptime:
                time.sleep(1)
            ex = Event.Game.wateremoji.x
            ey = Event.Game.wateremoji.y
            if cls.newattr.x != ex:
                tan = (cls.newattr.y - ey) / (cls.newattr.x - ex)
                if cls.newattr.x > ex:
                    Event.Game.wateremoji.x += math.sqrt(125 / (1 + tan ** 2))
                    Event.Game.wateremoji.y += math.sqrt(125 / (1 + tan ** 2)) * tan
                else:
                    Event.Game.wateremoji.x -= math.sqrt(125 / (1 + tan ** 2))
                    Event.Game.wateremoji.y -= math.sqrt(125 / (1 + tan ** 2)) * tan
            else:
                if cls.newattr.y > ey:
                    Event.Game.wateremoji.y -= 125
                else:
                    Event.Game.wateremoji.y += 125
            time.sleep(0.05)

    @classmethod
    def closeAttract(cls):
        time.sleep(4)
        cls.hasAttr = False

    @classmethod
    def useAttract(cls):
        if not cls.hasAttr and cls.canmadeinheaven:
            cls.newattr = Bullt.BossBumb(Event.Game.boss.x - 50, Event.Game.boss.y)
            cls.newattr.image = pygame.image.load('image/attract.png')
            cls.newattr.rect = cls.newattr.image.get_rect()
            cls.newattr.rect.left = cls.newattr.x
            cls.newattr.rect.top = cls.newattr.y
            cls.newattr.canMove = False
            cls.hasAttr = True
            t1 = threading.Thread(target=cls.attractMove)
            t1.daemon = True
            t1.start()
            t2 = threading.Thread(target=cls.attract)
            t2.daemon = True
            t2.start()
            t3 = threading.Thread(target=cls.closeAttract)
            t3.daemon = True
            t3.start()

    @classmethod
    def enlargeLove(cls):
        while Event.Game.haveLovebumb:
            if cls.newbumb.size <= 120:
                cls.newbumb.size += 10
                cls.newbumb.image = pygame.transform.smoothscale(cls.newbumb.image,
                                                                 (cls.newbumb.size, cls.newbumb.size))
                cls.newbumb.rect = cls.newbumb.image.get_rect()
                cls.newbumb.rect.left = cls.newbumb.x
                cls.newbumb.rect.top = cls.newbumb.y  # 更新碰撞体积
            time.sleep(0.1)

    @classmethod
    def generateLove(cls):
        cls.newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
        cls.newbumb.image = Event.Game.bulluten[3]
        cls.newbumb.size = 25
        cls.newbumb.canRemove = False  # 不能被任意门消除
        cls.newbumb.get = False  # 不追踪
        cls.newbumb.sample = 0
        cls.newbumb.canDelete = False
        Event.Game.loveBumb = cls.newbumb
        Event.Game.allenbumbs.append(cls.newbumb)
        Event.Game.haveLovebumb = True
        t1 = threading.Thread(target=cls.enlargeLove())
        t1.daemon = True
        t1.start()

    @classmethod
    def createPrevent(cls):
        pr1 = OEmoji.Prevent(400, 0)  # 调整到新窗口大小（2倍）
        pr2 = OEmoji.Prevent(400, 720)  # 调整到新窗口大小（2倍）

    @classmethod
    def moveFrame(cls):
        try:
            while Event.Game.haveBoss:
                cls.frame1.Move(Event.Game.rx - 300, Event.Game.ry - 10)
                cls.frame2.Move(Event.Game.rx + 1480, Event.Game.ry - 10)  # 调整到新窗口宽度（2倍）
                Move.moveWin(Event.Game.rx, Event.Game.ry - 5)
                time.sleep(0.0745)
                cls.frame1.Move(Event.Game.rx - 300, Event.Game.ry - 25)
                cls.frame2.Move(Event.Game.rx + 1480, Event.Game.ry - 25)  # 调整到新窗口宽度（2倍）
                Move.moveWin(Event.Game.rx, Event.Game.ry - 10)
                time.sleep(0.0745)
                cls.frame1.Move(Event.Game.rx - 300, Event.Game.ry - 38)
                cls.frame2.Move(Event.Game.rx + 1480, Event.Game.ry - 38)  # 调整到新窗口宽度（2倍）
                Move.moveWin(Event.Game.rx, Event.Game.ry - 15)
                time.sleep(0.0745)
                cls.frame1.Move(Event.Game.rx - 300, Event.Game.ry - 25)
                cls.frame2.Move(Event.Game.rx + 1480, Event.Game.ry - 25)  # 调整到新窗口宽度（2倍）
                Move.moveWin(Event.Game.rx, Event.Game.ry - 10)
                time.sleep(0.0745)
                cls.frame1.Move(Event.Game.rx - 300, Event.Game.ry - 10)
                cls.frame2.Move(Event.Game.rx + 1480, Event.Game.ry - 10)  # 调整到新窗口宽度（2倍）
                Move.moveWin(Event.Game.rx, Event.Game.ry - 5)
                time.sleep(0.0745)
                cls.frame1.Move(Event.Game.rx - 300, Event.Game.ry)
                cls.frame2.Move(Event.Game.rx + 1480, Event.Game.ry)  # 调整到新窗口宽度（2倍）
                Move.moveWin(Event.Game.rx, Event.Game.ry)
                time.sleep(0.0745)
            cls.frame1.Hide()
            cls.frame2.Hide()
        except RuntimeError:
            pass

    @classmethod
    def createFrame(cls):
        cls.frame1 = Frame.Frame('禁忌的边界线', (Event.Game.rx - 200, Event.Game.ry), (220, 220))
        cls.frame2 = Frame.Frame('禁忌的边界线', (Event.Game.rx + 1480, Event.Game.ry), (220, 220))  # 调整到新窗口宽度（2倍）
        panel1 = wx.Panel(cls.frame1, -1, size=(200, 200))
        panel2 = wx.Panel(cls.frame2, -1, size=(200, 200))
        cls.frame1.Show()
        cls.frame2.Show()
        image = wx.Image('image/heart.png', wx.BITMAP_TYPE_PNG)
        mypic = image.ConvertToBitmap()
        wx.StaticBitmap(panel1, -1, bitmap=mypic, pos=(0, 0))
        wx.StaticBitmap(panel2, -1, bitmap=mypic, pos=(0, 0))
        hwnd = pygame.display.get_wm_info()['window']
        win32gui.SetForegroundWindow(hwnd)
        t1 = threading.Thread(target=cls.moveFrame)
        t1.daemon = True
        t1.start()

    @classmethod
    def heartRain(cls):
        """心形弹幕雨：从天而降的爱心子弹"""
        for i in range(20):
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(1)

            x_pos = random.randint(100, main.WINDOWWIDTH - 100)
            newbumb = Bullt.BossBumb(x_pos, -50)
            newbumb.image = Event.Game.bulluten[3]  # 爱心图标
            newbumb.direction = 'down'
            newbumb.speed = random.randint(6, 12)
            newbumb.tan = 0
            newbumb.sample = 0
            newbumb.canReturn = True  # 可以反弹
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)
            time.sleep(0.15)

    @classmethod
    def reverseTime(cls):
        """时间倒流：所有子弹倒飞"""
        # 反转所有敌方子弹的方向
        for bullet in Event.Game.allenbumbs[::]:
            bullet.tan = -bullet.tan
            bullet.sample = -bullet.sample
            if bullet.direction == 'left':
                bullet.direction = 'right'
            elif bullet.direction == 'right':
                bullet.direction = 'left'
            elif bullet.direction == 'up':
                bullet.direction = 'down'
            elif bullet.direction == 'down':
                bullet.direction = 'up'

        time.sleep(2)

    @classmethod
    def heartTrap(cls):
        """爱心陷阱：在玩家周围创建爱心包围圈"""
        px, py = Event.Game.wateremoji.x, Event.Game.wateremoji.y

        # 三层爱心圈
        for radius in [100, 150, 200]:
            for angle in range(0, 360, 20):
                x = px + radius * math.cos(math.radians(angle))
                y = py + radius * math.sin(math.radians(angle))

                newbumb = Bullt.BossBumb(x, y)
                newbumb.image = Event.Game.bulluten[3]
                newbumb.canMove = False
                newbumb.canDelete = False
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

                # 2秒后移除
                threading.Thread(target=cls._removeAfter, args=(newbumb, 2), daemon=True).start()

            time.sleep(0.3)

    @classmethod
    def _removeAfter(cls, bullet, delay):
        """延迟移除子弹"""
        time.sleep(delay)
        if bullet in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(bullet)

    @classmethod
    def splitBomb(cls):
        """分裂炸弹：发射会分裂的爱心炸弹"""
        for i in range(5):
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(1)

            # 主弹
            main_bullet = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            main_bullet.image = Event.Game.bulluten[3]
            main_bullet.speed = 8
            main_bullet.get = True  # 追踪
            main_bullet.rect = main_bullet.image.get_rect()
            main_bullet.rect.left = main_bullet.x
            main_bullet.rect.top = main_bullet.y
            Event.Game.allenbumbs.append(main_bullet)

            # 1秒后分裂
            threading.Thread(target=cls._splitBullet, args=(main_bullet,), daemon=True).start()
            time.sleep(0.8)

    @classmethod
    def _splitBullet(cls, bullet):
        """分裂子弹"""
        time.sleep(1)
        if bullet not in Event.Game.allenbumbs:
            return

        # 记录位置
        split_x, split_y = bullet.x, bullet.y

        # 移除主弹
        try:
            Event.Game.allenbumbs.remove(bullet)
        except:
            return

        # 分裂成8个小弹
        for angle in range(0, 360, 45):
            newbumb = Bullt.BossBumb(split_x, split_y)
            newbumb.image = Event.Game.bulluten[2]
            newbumb.speed = 10
            newbumb.tan = math.tan(math.radians(angle))
            if 90 < angle < 270:
                newbumb.sample = 1
            else:
                newbumb.sample = -1
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)
