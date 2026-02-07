import time, pygame, win32gui, random, main, Event, Move, threading, Bullt, math, OEmoji

import wx

import Frame


class BossSkillForth:
    frame = object

    @classmethod
    def light(cls, newbumb):
        time.sleep(2)
        bumb = Bullt.BossBumb(newbumb.x - 1280, newbumb.y)  # 调整到新窗口宽度
        bumb.canMove = False
        bumb.banRemove = True
        bumb.canDelete = False
        bumb.image = pygame.image.load('image/light.png')
        bumb.rect = bumb.image.get_rect()
        bumb.rect.left = bumb.x
        bumb.rect.top = bumb.y
        Event.Game.allenbumbs.append(bumb)
        index = 1
        for i in range(13):
            bumb.image.set_alpha(index)
            index += 18
            time.sleep(0.08)
        Event.Game.allenbumbs.remove(newbumb)
        index = 255
        for i in range(13):
            bumb.image.set_alpha(index)
            index -= 18
            time.sleep(0.08)
        Event.Game.allenbumbs.remove(bumb)

    @classmethod
    def lightshoot(cls):
        for i in range(5):
            if Event.Game.haveBoss:
                while Event.Game.istimestoptime:
                    time.sleep(1)
                x, y = random.randint(150, main.WINDOWWIDTH - 30), random.randint(0, main.WINDOWHEIGHT - 30)
                newbumb = Bullt.BossBumb(x, y)
                newbumb.canMove = False
                newbumb.hurt = 0
                newbumb.canDelete = False
                newbumb.image = pygame.image.load('image/error.png')
                Event.Game.allenbumbs.append(newbumb)
                th = threading.Thread(target=cls.light, args=(newbumb,))
                th.daemon = True
                th.start()
                time.sleep(0.2)

    @classmethod
    def dragAttack(cls, newbumb):
        art = math.atan(newbumb.tan)
        artt = math.atan(newbumb.tan)
        sample = newbumb.sample
        while -20 <= newbumb.x < main.WINDOWWIDTH and -20 <= newbumb.y <= main.WINDOWHEIGHT and not newbumb.blow:
            while Event.Game.istimestoptime:
                time.sleep(1)
            art -= math.pi / 5
            newbumb.tan = math.tan(art)
            if math.cos(art) < 0:
                newbumb.sample = 1
            else:
                newbumb.sample = -1
            if sample == 0:
                if newbumb.direction == 'left':
                    newbumb.x -= newbumb.speed
            elif sample == 1:
                newbumb.x += math.sqrt(newbumb.speed * 10 / (1 + math.tan(artt) ** 2))
                newbumb.y += math.sqrt(newbumb.speed * 10 / (1 + math.tan(artt) ** 2)) * math.tan(artt)
            elif sample == -1:
                newbumb.x -= math.sqrt(newbumb.speed * 9 / (1 + math.tan(artt) ** 2))
                newbumb.y -= math.sqrt(newbumb.speed * 9 / (1 + math.tan(artt) ** 2)) * math.tan(artt)
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            time.sleep(0.1)
        if not (-20 <= newbumb.x < main.WINDOWWIDTH and -20 <= newbumb.y <= main.WINDOWHEIGHT):
            try:
                Event.Game.allenbumbs.remove(newbumb)
            except ValueError:
                pass

    @classmethod
    def dragShoot(cls):
        for i in range(20):
            if Event.Game.haveBoss:
                while Event.Game.istimestoptime:
                    time.sleep(1)
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = Event.Game.bulluten[10]
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                newbumb.banRemove = True
                Event.Game.allenbumbs.append(newbumb)
                th = threading.Thread(target=cls.dragAttack, args=(newbumb,))
                th.daemon = True
                th.start()
                time.sleep(0.2)

    @classmethod
    def sideMove(cls, tv1, tv2, tv3, tv4):
        for i in range(5):
            tv1.y -= 8
            tv2.y += 8
            tv3.y -= 8
            tv4.y += 8
            time.sleep(0.3)

    @classmethod
    def tvShoot(cls, tv1, tv2, tv3, tv4):
        for i in range(25):
            newbumb1 = Bullt.EmemiesBumb(tv1.x, tv1.y)
            newbumb2 = Bullt.EmemiesBumb(tv2.x, tv2.y)
            newbumb1.image = Event.Game.bulluten[10]
            newbumb2.image = Event.Game.bulluten[10]
            newbumb1.speed = 19
            newbumb2.speed = 19
            newbumb3 = Bullt.EmemiesBumb(tv3.x, tv3.y)
            newbumb4 = Bullt.EmemiesBumb(tv4.x, tv4.y)
            newbumb3.image = Event.Game.bulluten[10]
            newbumb4.image = Event.Game.bulluten[10]
            newbumb3.speed = 19
            newbumb4.speed = 19
            newbumb1.rect = newbumb1.image.get_rect()
            newbumb1.rect.left = newbumb1.x
            newbumb1.rect.top = newbumb1.y
            newbumb2.rect = newbumb2.image.get_rect()
            newbumb2.rect.left = newbumb2.x
            newbumb2.rect.top = newbumb2.y
            newbumb3.rect = newbumb3.image.get_rect()
            newbumb3.rect.left = newbumb3.x
            newbumb3.rect.top = newbumb3.y
            newbumb4.rect = newbumb4.image.get_rect()
            newbumb4.rect.left = newbumb4.x
            newbumb4.rect.top = newbumb4.y
            Event.Game.allenbumbs.append(newbumb1)
            Event.Game.allenbumbs.append(newbumb2)
            Event.Game.allenbumbs.append(newbumb3)
            Event.Game.allenbumbs.append(newbumb4)
            time.sleep(0.1)

    @classmethod
    def sideShoot(cls):
        new1 = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
        new2 = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y + 40)
        new3 = Bullt.BossBumb(Event.Game.boss.x, Event.Game.wateremoji.y + 20)
        new4 = Bullt.BossBumb(Event.Game.boss.x, Event.Game.wateremoji.y)
        new1.image = pygame.image.load('image/tv.png')
        new2.image = pygame.image.load('image/tv.png')
        new3.image = pygame.image.load('image/tv.png')
        new4.image = pygame.image.load('image/tv.png')
        new1.canDelete = False
        new2.canDelete = False
        new3.canDelete = False
        new4.canDelete = False
        new1.hurt, new2.hurt, new3.hurt, new4.hurt = 0, 0, 0, 0
        new1.canMove = False
        new2.canMove = False
        new3.canMove = False
        new4.canMove = False
        new1.banRemove = True
        new2.banRemove = True
        new3.banRemove = True
        new4.banRemove = True
        Event.Game.allenbumbs.append(new1)
        Event.Game.allenbumbs.append(new2)
        Event.Game.allenbumbs.append(new3)
        Event.Game.allenbumbs.append(new4)
        Event.Game.boss.canShoot = False
        th = threading.Thread(target=cls.sideMove, args=(new1, new2, new3, new4))
        th.daemon = True
        th.start()
        time.sleep(2)
        th = threading.Thread(target=cls.tvShoot, args=(new1, new2, new3, new4))
        th.daemon = True
        th.start()
        time.sleep(2.5)
        Event.Game.allenbumbs.remove(new1)
        Event.Game.allenbumbs.remove(new2)
        Event.Game.allenbumbs.remove(new3)
        Event.Game.allenbumbs.remove(new4)
        Event.Game.boss.canShoot = True

    @classmethod
    def removeUFO(cls, newe):
        while newe.y <= main.WINDOWHEIGHT:
            if newe not in Event.Game.g_enemies:
                return
            time.sleep(3)
        try:
            Event.Game.g_enemies.remove(newe)
        except ValueError:
            pass

    @classmethod
    def summonUFO(cls):
        for i in range(12):
            newe = OEmoji.Enemy()
            newe.canChangeMove = False
            newe.direction = 'down'
            newe.y = -40
            newe.x = random.randint(300, 400)
            newe.rint = 8
            newe.image = pygame.image.load('image/alien.png')
            newe.live = 40 * Event.Game.bossdeathtimes
            newe.maxlive = 40 * Event.Game.bossdeathtimes
            Event.Game.g_enemies.append(newe)
            th = threading.Thread(target=cls.removeUFO, args=(newe,))
            th.daemon = True
            th.start()
            time.sleep(0.4)

    @classmethod
    def move(cls):
        try:
            while Event.Game.haveBoss and Event.Game.boss.bossrint == 4:
                cls.frame.Move(Event.Game.rx + 1280, 0)  # 调整到新窗口宽度
                time.sleep(0.331)
                cls.frame.Move(Event.Game.rx - 220, 0)
                time.sleep(0.331)
        except RuntimeError:
            pass

    @classmethod
    def moveFrameForth(cls):
        try:
            while (Event.Game.haveBoss and Event.Game.boss.bossrint == 4):
                Move.moveWin(Event.Game.rx, Event.Game.ry - 10)
                time.sleep(0.1655)
                Move.moveWin(Event.Game.rx - 10, Event.Game.ry - 10)
                time.sleep(0.1655)
                Move.moveWin(Event.Game.rx - 10, Event.Game.ry)
                time.sleep(0.1655)
                Move.moveWin(Event.Game.rx, Event.Game.ry)
                time.sleep(0.1655)
        except RuntimeError:
            pass

    @classmethod
    def framemove(cls):
        cls.frame = Frame.Frame('ATTENTION', (Event.Game.rx - 220, 0), (220, 230))
        panel1 = wx.Panel(cls.frame, -1, size=(200, 200))
        cls.frame.Show()
        image = wx.Image('image/attention.png', wx.BITMAP_TYPE_PNG)
        mypic = image.ConvertToBitmap()
        wx.StaticBitmap(panel1, -1, bitmap=mypic, pos=(0, 0))
        hwnd = pygame.display.get_wm_info()['window']
        win32gui.SetForegroundWindow(hwnd)
        cls.sin = random.random()
        cls.cos = random.random()
        th = threading.Thread(target=cls.move)
        th.daemon = True
        th.start()
        th2 = threading.Thread(target=cls.moveFrameForth)
        th2.daemon = True
        th2.start()

    @classmethod
    def screenStatic(cls):
        """屏幕静态干扰：创建干扰屏幕减速玩家"""
        for i in range(3):
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 随机位置创建静态屏幕
            screen_x = random.randint(200, main.WINDOWWIDTH - 350)
            screen_y = random.randint(100, main.WINDOWHEIGHT - 250)

            # 创建静态屏幕
            static_screen = Bullt.BossBumb(screen_x, screen_y)
            static_screen.canMove = False
            static_screen.hurt = 5
            static_screen.canDelete = False
            static_screen.size = 150

            # 预生成3个不同的静态图像用于轮换（性能优化）
            static_screen.images = []
            for _ in range(3):
                img = pygame.Surface((150, 150))
                for x in range(0, 150, 3):
                    for y in range(0, 150, 3):
                        color = random.choice([
                            (255, 255, 255), (200, 200, 200), (150, 150, 150),
                            (100, 100, 255), (255, 100, 100), (100, 255, 100)
                        ])
                        pygame.draw.rect(img, color, (x, y, 3, 3))
                static_screen.images.append(img)

            static_screen.image = static_screen.images[0]
            static_screen.image_index = 0
            static_screen.rect = static_screen.image.get_rect()
            static_screen.rect.left = static_screen.x
            static_screen.rect.top = static_screen.y
            Event.Game.allenbumbs.append(static_screen)

            # 启动干扰效果
            threading.Thread(target=cls._staticEffect, args=(static_screen, screen_x, screen_y), daemon=True).start()
            time.sleep(1.5)

    @classmethod
    def _staticEffect(cls, screen, sx, sy):
        """静态干扰效果"""
        duration = 4
        start = time.time()
        was_slowed = False  # 跟踪当前色块是否正在减速玩家

        while time.time() - start < duration and screen in Event.Game.allenbumbs:
            # 轮换预生成的图像而不是每帧重绘（性能优化）
            if hasattr(screen, 'images'):
                screen.image_index = (screen.image_index + 1) % len(screen.images)
                screen.image = screen.images[screen.image_index]

            # 检查玩家是否在屏幕内
            player_in_area = (sx <= Event.Game.wateremoji.x <= sx + 150 and
                             sy <= Event.Game.wateremoji.y <= sy + 150)

            if player_in_area and not was_slowed:
                # 玩家刚进入，施加减速
                Event.Game.wateremoji.slowdown_effects += 1
                Event.Game.wateremoji.normal_speed = 3
                was_slowed = True
            elif not player_in_area and was_slowed:
                # 玩家刚离开，移除减速
                Event.Game.wateremoji.slowdown_effects -= 1
                if Event.Game.wateremoji.slowdown_effects <= 0:
                    Event.Game.wateremoji.slowdown_effects = 0
                    Event.Game.wateremoji.normal_speed = Event.Game.wateremoji.ORIGINAL_NORMAL_SPEED
                was_slowed = False

            time.sleep(0.2)  # 从0.1改为0.2，减少更新频率

        # 确保移除减速效果
        if was_slowed:
            Event.Game.wateremoji.slowdown_effects -= 1
            if Event.Game.wateremoji.slowdown_effects <= 0:
                Event.Game.wateremoji.slowdown_effects = 0
                Event.Game.wateremoji.normal_speed = Event.Game.wateremoji.ORIGINAL_NORMAL_SPEED

        # 移除色块
        if screen in Event.Game.allenbumbs:
            try:
                Event.Game.allenbumbs.remove(screen)
            except ValueError:
                pass  # 已经被移除

    @classmethod
    def orbitalStrike(cls):
        """轨道打击：UFO在屏幕边缘轨道运行并射击"""
        # 创建4个UFO在四个边
        ufos = []
        positions = [
            ('top', random.randint(200, main.WINDOWWIDTH - 200), 50),
            ('bottom', random.randint(200, main.WINDOWWIDTH - 200), main.WINDOWHEIGHT - 50),
            ('left', 50, random.randint(200, main.WINDOWHEIGHT - 200)),
            ('right', main.WINDOWWIDTH - 50, random.randint(200, main.WINDOWHEIGHT - 200))
        ]

        for edge, x, y in positions:
            ufo = Bullt.BossBumb(x, y)
            ufo.canMove = False
            ufo.hurt = 10
            ufo.canDelete = False
            ufo.image = pygame.image.load('image/alien.png')
            ufo.rect = ufo.image.get_rect()
            ufo.rect.left = ufo.x
            ufo.rect.top = ufo.y
            ufo.edge = edge
            Event.Game.allenbumbs.append(ufo)
            ufos.append(ufo)

        # 启动轨道运动和射击
        threading.Thread(target=cls._orbitalMove, args=(ufos,), daemon=True).start()
        threading.Thread(target=cls._orbitalShoot, args=(ufos,), daemon=True).start()

    @classmethod
    def _orbitalMove(cls, ufos):
        """UFO轨道运动"""
        for frame in range(80):
            for ufo in ufos[:]:
                if ufo not in Event.Game.allenbumbs:
                    continue

                # 沿边缘移动
                if ufo.edge == 'top':
                    ufo.x += 8
                    if ufo.x >= main.WINDOWWIDTH - 50:
                        ufo.edge = 'right'
                        ufo.y = 50
                elif ufo.edge == 'right':
                    ufo.y += 8
                    if ufo.y >= main.WINDOWHEIGHT - 50:
                        ufo.edge = 'bottom'
                        ufo.x = main.WINDOWWIDTH - 50
                elif ufo.edge == 'bottom':
                    ufo.x -= 8
                    if ufo.x <= 50:
                        ufo.edge = 'left'
                        ufo.y = main.WINDOWHEIGHT - 50
                elif ufo.edge == 'left':
                    ufo.y -= 8
                    if ufo.y <= 50:
                        ufo.edge = 'top'
                        ufo.x = 50

                ufo.rect.left = ufo.x
                ufo.rect.top = ufo.y

            time.sleep(0.1)

        # 移除UFO
        for ufo in ufos:
            if ufo in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(ufo)

    @classmethod
    def _orbitalShoot(cls, ufos):
        """UFO射击"""
        for i in range(30):
            for ufo in ufos[:]:
                if ufo not in Event.Game.allenbumbs:
                    continue

                # 向玩家方向射击
                dx = Event.Game.wateremoji.x - ufo.x
                dy = Event.Game.wateremoji.y - ufo.y
                angle = math.degrees(math.atan2(dy, dx))

                newbumb = Bullt.BossBumb(ufo.x, ufo.y)
                newbumb.image = Event.Game.bulluten[10]
                newbumb.speed = 10
                newbumb.tan = math.tan(math.radians(angle))
                if -90 < angle % 360 < 90:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.25)

    @classmethod
    def pixelStorm(cls):
        """像素风暴：创建像素方块弹幕"""
        patterns = [
            # 十字形
            lambda cx, cy: [(cx + dx * 40, cy) for dx in range(-5, 6)] +
                          [(cx, cy + dy * 40) for dy in range(-5, 6)],
            # 方形网格
            lambda cx, cy: [(cx + dx * 50, cy + dy * 50)
                          for dx in range(-4, 5) for dy in range(-4, 5)],
            # 对角线
            lambda cx, cy: [(cx + d * 40, cy + d * 40) for d in range(-6, 7)] +
                          [(cx + d * 40, cy - d * 40) for d in range(-6, 7)]
        ]

        pattern = random.choice(patterns)
        center_x = Event.Game.wateremoji.x
        center_y = Event.Game.wateremoji.y

        positions = pattern(center_x, center_y)
        pixels = []

        # 创建像素方块
        for x, y in positions:
            if 0 <= x < main.WINDOWWIDTH and 0 <= y < main.WINDOWHEIGHT:
                pixel = Bullt.BossBumb(x, y)
                pixel.canMove = False
                pixel.canDelete = False
                pixel.size = 15
                pixel.image = pygame.Surface((15, 15))
                pixel.image.fill(random.choice([
                    (255, 100, 100), (100, 255, 100), (100, 100, 255),
                    (255, 255, 100), (255, 100, 255), (100, 255, 255)
                ]))
                pixel.rect = pixel.image.get_rect()
                pixel.rect.left = pixel.x
                pixel.rect.top = pixel.y
                Event.Game.allenbumbs.append(pixel)
                pixels.append(pixel)

        time.sleep(0.8)

        # 所有像素同时向外射出
        for pixel in pixels:
            if pixel not in Event.Game.allenbumbs:
                continue

            # 计算从中心向外的角度
            dx = pixel.x - center_x
            dy = pixel.y - center_y
            distance = math.sqrt(dx**2 + dy**2)

            if distance > 5:
                angle = math.degrees(math.atan2(dy, dx))
                pixel.canMove = True
                pixel.speed = 12
                pixel.tan = math.tan(math.radians(angle))
                if -90 < angle % 360 < 90:
                    pixel.sample = 1
                else:
                    pixel.sample = -1
