import time, pygame, win32gui, random, main, Event, Move, threading, Bullt, math, OEmoji, Frame, main, wx


class BossSkillThird:
    stopok = False

    @classmethod
    def teleport(cls):
        while Event.Game.haveBoss:
            while Event.Game.istimestoptime:
                time.sleep(1)
            Event.Game.boss.x = random.randint(400, 560)
            Event.Game.boss.y = random.randint(0, 400)
            time.sleep(1)

    @classmethod
    def superShoot(cls):
        index = 10
        dir = 1
        for i in range(16):
            if Event.Game.haveBoss:
                while Event.Game.istimestoptime:
                    time.sleep(1)
                newbumb = Bullt.BossBumb(Event.Game.boss.x, index)
                newbumb.speed = 5
                newbumb.sample = 0
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                if dir == 1:
                    index += 60
                else:
                    index -= 60
                if index >= 450:
                    dir = -1
                newbumb.image = Event.Game.bulluten[4]
                Event.Game.allenbumbs.append(newbumb)
                time.sleep(0.3)

    @classmethod
    def moveFrameThird(cls):
        try:
            while Event.Game.haveBoss:
                Move.moveWin(Event.Game.rx, Event.Game.ry - 10)
                time.sleep(0.2597)
                Move.moveWin(Event.Game.rx - 10, Event.Game.ry - 10)
                time.sleep(0.2597)
                Move.moveWin(Event.Game.rx - 10, Event.Game.ry)
                time.sleep(0.2597)
                Move.moveWin(Event.Game.rx, Event.Game.ry)
                time.sleep(0.2597)
        except RuntimeError:
            pass

    @classmethod
    def setgold(cls):
        Event.Game.gold = True
        Event.Game.golden.play()
        time.sleep(5)
        Event.Game.gold = False

    @classmethod
    def cutBody(cls):
        newfen = OEmoji.BossEmemy()
        newfen.x = random.randint(400, 560)
        newfen.y = random.randint(0, 400)
        newfen.bossrint = 3
        newfen.image = pygame.image.load('image/bossenemy-3.png')
        newfen.maxlive = 65 * Event.Game.bossdeathtimes
        newfen.live = 65 * Event.Game.bossdeathtimes
        newfen.isboss = False
        newfen.rint = 1
        newfen.sleepbumbtime = 3
        Event.Game.g_enemies.append(newfen)
        newfen = OEmoji.BossEmemy()
        newfen.x = random.randint(400, 560)
        newfen.y = random.randint(0, 400)
        newfen.bossrint = 3
        newfen.image = pygame.image.load('image/bossenemy-3.png')
        newfen.maxlive = 65 * Event.Game.bossdeathtimes
        newfen.live = 65 * Event.Game.bossdeathtimes
        newfen.isboss = False
        newfen.rint = 1
        newfen.sleepbumbtime = 3
        Event.Game.g_enemies.append(newfen)

    @classmethod
    def updatewhenstop(cls):
        boss3 = pygame.image.load('image/boss3.png')
        while cls.stopok:
            if Event.Game.boss.bossrint == 6:
                Event.Game.screen.blit(Event.Game.boss6r, (0, 0))
            else:
                Event.Game.screen.blit(Event.Game.boss3r, (0, 0))
            Event.Game.screen.blit(Event.Game.wateremoji.image, (Event.Game.wateremoji.x, Event.Game.wateremoji.y))
            for i in Event.Game.g_enemies:
                i.shoot()
                try:
                    Event.Game.screen.blit(i.image, (i.x, i.y))
                except pygame.error:
                    pass
            for i in Event.Game.allenbumbs:
                Event.Game.screen.blit(i.image, (i.x, i.y))
            for i in Event.Game.wateremoji.allbumb:
                Event.Game.screen.blit(i.image, (i.x, i.y))
            try:
                for i in Event.Game.allsupply:
                    Event.Game.screen.blit(i.image, (i.x, i.y))
            except pygame.error:
                pass
            Event.Game.setDirection()
            Event.Game.boss.move()
            Event.Game.showPower()
            font2 = pygame.font.SysFont(None, 20)
            Event.Game.showLife(font2, Event.Game.screen)
            pygame.display.update()
            pygame.time.Clock().tick(Event.Game.FPS)

    @classmethod
    def timestop(cls):
        t1 = threading.Thread(target=cls.updatewhenstop)
        t1.daemon = True
        t1.start()
        Event.Game.theworld.play()
        cls.stopok = True
        timek = time.time()
        Event.Game.isBossTimestop = True
        while time.time() - timek <= 5:
            a = 1
            pass
        Event.Game.isBossTimestop = False
        cls.stopok = False

    @classmethod
    def goldenStorm(cls):
        """黄金风暴：发射大量金色旋转子弹"""
        for rotation in range(0, 720, 15):
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime or Event.Game.isBossTimestop:
                time.sleep(0.1)

            # 四方向旋转弹幕
            for offset in [0, 90, 180, 270]:
                angle = rotation + offset
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = Event.Game.bulluten[4]  # 金色子弹
                newbumb.speed = 12
                newbumb.tan = math.tan(math.radians(angle))
                newbumb.willRotate = True
                if 90 < angle % 360 < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.08)

    @classmethod
    def timeBubble(cls):
        """时间气泡：创建减速玩家的时间气泡"""
        for i in range(4):
            if not Event.Game.haveBoss:
                break

            bubble_x = random.randint(200, main.WINDOWWIDTH - 200)
            bubble_y = random.randint(150, main.WINDOWHEIGHT - 150)

            # 创建气泡
            bubble = Bullt.BossBumb(bubble_x, bubble_y)
            bubble.canMove = False
            bubble.hurt = 0
            bubble.canDelete = False
            bubble.size = 150
            bubble.image = pygame.Surface((150, 150), pygame.SRCALPHA)
            pygame.draw.circle(bubble.image, (255, 215, 0, 100), (75, 75), 75)
            pygame.draw.circle(bubble.image, (255, 215, 0, 200), (75, 75), 75, 3)
            bubble.rect = bubble.image.get_rect()
            bubble.rect.left = bubble.x
            bubble.rect.top = bubble.y
            Event.Game.allenbumbs.append(bubble)

            # 在气泡内减速玩家
            threading.Thread(target=cls._bubbleEffect, args=(bubble, bubble_x, bubble_y), daemon=True).start()
            time.sleep(1.5)

    @classmethod
    def _bubbleEffect(cls, bubble, bx, by):
        """气泡减速效果"""
        duration = 4
        start = time.time()
        was_slowed = False  # 跟踪当前气泡是否正在减速玩家

        while time.time() - start < duration and bubble in Event.Game.allenbumbs:
            # 检查玩家是否在气泡内
            distance = math.sqrt((Event.Game.wateremoji.x - bx)**2 + (Event.Game.wateremoji.y - by)**2)
            player_in_bubble = distance < 75

            if player_in_bubble and not was_slowed:
                # 玩家刚进入，施加减速
                Event.Game.wateremoji.slowdown_effects += 1
                Event.Game.wateremoji.normal_speed = 2
                was_slowed = True
            elif not player_in_bubble and was_slowed:
                # 玩家刚离开，移除减速
                Event.Game.wateremoji.slowdown_effects -= 1
                if Event.Game.wateremoji.slowdown_effects <= 0:
                    Event.Game.wateremoji.slowdown_effects = 0
                    Event.Game.wateremoji.normal_speed = Event.Game.wateremoji.ORIGINAL_NORMAL_SPEED
                was_slowed = False

            time.sleep(0.1)

        # 确保移除减速效果
        if was_slowed:
            Event.Game.wateremoji.slowdown_effects -= 1
            if Event.Game.wateremoji.slowdown_effects <= 0:
                Event.Game.wateremoji.slowdown_effects = 0
                Event.Game.wateremoji.normal_speed = Event.Game.wateremoji.ORIGINAL_NORMAL_SPEED

        # 移除气泡
        if bubble in Event.Game.allenbumbs:
            try:
                Event.Game.allenbumbs.remove(bubble)
            except ValueError:
                pass  # 已经被移除

    @classmethod
    def coinBarrage(cls):
        """金币弹幕：发射金币形状的弹幕"""
        # 从Boss位置发射金币墙
        for i in range(10):
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime or Event.Game.isBossTimestop:
                time.sleep(0.1)

            # 垂直一列金币
            for y_offset in range(-200, 700, 80):
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y + y_offset)
                newbumb.image = Event.Game.bulluten[4]
                newbumb.speed = 6
                newbumb.sample = 0
                newbumb.direction = 'left'
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.5)
