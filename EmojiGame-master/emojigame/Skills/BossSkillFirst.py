import time, pygame, win32gui, random, main, Event, Move, threading, Bullt, math, OEmoji


class BossSkillFirst:
    lastmovetime = 0
    movedirection = 'right'
    thistime = 0
    teleporttime = 0
    thisteleport = object

    @classmethod
    def haveTeleport(cls):  # 有传送门时执行
        while (Event.Game.haveTeleport):
            newe = OEmoji.SummonEnemies()
            newe.x = cls.thisteleport.x
            newe.y = cls.thisteleport.y
            if newe.rint == -1:
                newe.live = 100 * Event.Game.bossdeathtimes
                newe.maxlive = 100 * Event.Game.bossdeathtimes
            elif newe.rint == -2:
                newe.live = 130 * Event.Game.bossdeathtimes
                newe.maxlive = 130 * Event.Game.bossdeathtimes
            Event.Game.g_enemies.append(newe)
            time.sleep(random.randint(3, 9))

    @classmethod  # 传送门技能
    def summonTeleport(cls):
        if time.time() - cls.teleporttime >= 15 and time.time() - Event.Game.teleportDeathtime >= 8 + 8 * random.random() and Event.Game.haveTeleport is False:
            cls.thisteleport = OEmoji.Teleport()
            cls.thisteleport.x = Event.Game.boss.x - 120
            cls.thisteleport.y = Event.Game.boss.y
            Event.Game.g_enemies.append(cls.thisteleport)
            t1 = threading.Thread(target=cls.haveTeleport)
            t1.daemon = True
            t1.start()
        else:
            newthread = threading.Thread(target=cls.starShoot)
            newthread.daemon = True
            newthread.start()

    @classmethod
    def shootaside(cls):
        for i in range(35):
            if Event.Game.haveBoss is False:
                break
            while Event.Game.istimestoptime:
                time.sleep(1)
            newbumb1 = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            newbumb2 = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            newbumb1.tan = math.tan(math.atan(newbumb1.tan) + math.pi / 10)
            newbumb2.tan = math.tan(math.atan(newbumb1.tan) - math.pi / 10)
            newbumb1.image = Event.Game.bulluten[1]
            newbumb2.image = Event.Game.bulluten[1]
            newbumb1.rect = newbumb1.image.get_rect()
            newbumb1.rect.left = newbumb1.x
            newbumb1.rect.top = newbumb1.y
            newbumb2.rect = newbumb2.image.get_rect()
            newbumb2.rect.left = newbumb2.x
            newbumb2.rect.top = newbumb2.y
            Event.Game.allenbumbs.append(newbumb1)
            Event.Game.allenbumbs.append(newbumb2)
            time.sleep(0.2)

    @classmethod
    def sandShoot(cls):  # 散射技能
        settime = 1
        for i in range(random.randint(3, 5)):
            while Event.Game.istimestoptime:
                time.sleep(1)
            cls.setSand(settime)
            if Event.Game.haveBoss is False:
                break
            time.sleep(0.5)
            settime += 1

    @classmethod
    def setSand(cls, times):  # time为第几波
        rive = math.pi / 10
        artan = 0
        index = 0
        timek = 0
        for i in range(9 + times * 2):
            newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            newbumb.speed = 12
            if i != 0:
                if index % 2 != 0:
                    newbumb.tan = math.tan(artan + timek * rive)
                else:
                    newbumb.tan = math.tan(artan - timek * rive)
                if index % 2 == 0:
                    timek += 1
            else:
                artan = math.atan(newbumb.tan)
            newbumb.image = Event.Game.bulluten[1]
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)
            index += 1

    @classmethod  # 窗口移动的技能
    def melySkill(cls):
        if time.time() - cls.thistime >= 0.001:
            cls.thistime = time.time()
            cls.moveWindows()

    @classmethod
    def moveWindows(cls):
        hwnd = pygame.display.get_wm_info()['window']
        rect = win32gui.GetWindowRect(hwnd)
        x = rect[0]
        y = rect[1]
        if time.time() - cls.lastmovetime >= 2:
            randoms = random.random()
            if randoms > 0 and randoms <= 0.25:
                cls.movedirection = 'right'
            elif randoms > 0.25 and randoms <= 0.5:
                cls.movedirection = 'left'
            elif randoms > 0.5 and randoms <= 0.75:
                cls.movedirection = 'up'
            elif randoms > 0.75 and randoms < 1:
                cls.movedirection = 'down'
        if cls.movedirection == 'right':
            if x < Event.Game.rwidth - main.WINDOWWIDTH:
                Move.moveWin(x + random.randint(1, 3), y)
        elif cls.movedirection == 'left':
            if x > 0:
                Move.moveWin(x - random.randint(1, 3), y)
        elif cls.movedirection == 'down':
            if y < Event.Game.rheight - main.WINDOWHEIGHT:
                Move.moveWin(x, y + random.randint(1, 3))
        elif cls.movedirection == 'up':
            if y > 0:
                Move.moveWin(x, y - random.randint(1, 3))

    @classmethod
    def starChange(cls, newbumb):
        index = 0
        while -80 <= newbumb.x <= 1280 and -80 <= newbumb.y <= 960:  # 调整到新窗口大小
            while Event.Game.istimestoptime:
                time.sleep(1)
            newbumb.image1 = pygame.transform.rotate(newbumb.image, 20 + index)
            time.sleep(0.1)
            newbumb.rect = newbumb.image1.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y  # 更新碰撞体积
            index += 20

    @classmethod
    def starShoot(cls):
        for i in range(5):
            if Event.Game.haveBoss:
                while Event.Game.istimestoptime:
                    time.sleep(1)
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.size = 80
                newbumb.speed = 20
                newbumb.image = Event.Game.bulluten[9]
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                newbumb.willRotate = True
                newbumb.canReturn = True
                newbumb.canDelete = False
                Event.Game.allenbumbs.append(newbumb)
                th = threading.Thread(target=cls.starChange, args=(newbumb,))
                th.daemon = True
                th.start()
                time.sleep(1.2)

    @classmethod
    def mirrorShoot(cls):
        """镜像弹幕：以Boss为中心对称射击"""
        for wave in range(3):
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(1)

            # 12个方向，镜像对称
            for angle in range(0, 180, 15):
                # 正向
                newbumb1 = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb1.tan = math.tan(math.radians(angle))
                newbumb1.speed = 10
                newbumb1.image = Event.Game.bulluten[1]
                if 90 < angle < 270:
                    newbumb1.sample = 1
                else:
                    newbumb1.sample = -1
                newbumb1.rect = newbumb1.image.get_rect()
                newbumb1.rect.left = newbumb1.x
                newbumb1.rect.top = newbumb1.y
                Event.Game.allenbumbs.append(newbumb1)

                # 镜像（180度对称）
                mirror_angle = angle + 180
                newbumb2 = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb2.tan = math.tan(math.radians(mirror_angle))
                newbumb2.speed = 10
                newbumb2.image = Event.Game.bulluten[1]
                if 90 < mirror_angle < 270:
                    newbumb2.sample = 1
                else:
                    newbumb2.sample = -1
                newbumb2.rect = newbumb2.image.get_rect()
                newbumb2.rect.left = newbumb2.x
                newbumb2.rect.top = newbumb2.y
                Event.Game.allenbumbs.append(newbumb2)

            time.sleep(0.8)

    @classmethod
    def blackHole(cls):
        """黑洞：吸引玩家并发射环形弹幕"""
        # 创建黑洞
        hole_x = random.randint(300, main.WINDOWWIDTH - 300)
        hole_y = random.randint(200, main.WINDOWHEIGHT - 200)

        hole = Bullt.BossBumb(hole_x, hole_y)
        hole.canMove = False
        hole.hurt = 0
        hole.canDelete = False
        hole.image = Event.Game.bulluten[9]  # 使用星星图标
        hole.size = 80
        hole.rect = hole.image.get_rect()
        hole.rect.left = hole.x
        hole.rect.top = hole.y
        Event.Game.allenbumbs.append(hole)

        # 吸引效果持续3秒
        start_time = time.time()
        while time.time() - start_time < 3:
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 吸引玩家
            dx = hole_x - Event.Game.wateremoji.x
            dy = hole_y - Event.Game.wateremoji.y
            distance = math.sqrt(dx**2 + dy**2)
            if distance > 10:
                pull_strength = min(300 / distance, 3)  # 距离越近吸引力越强
                Event.Game.wateremoji.x += dx / distance * pull_strength
                Event.Game.wateremoji.y += dy / distance * pull_strength

            # 发射环形弹幕
            if random.random() < 0.3:
                angle = random.randint(0, 359)
                newbumb = Bullt.BossBumb(hole_x, hole_y)
                newbumb.tan = math.tan(math.radians(angle))
                newbumb.speed = 8
                newbumb.image = Event.Game.bulluten[2]
                if 90 < angle < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.1)

        # 移除黑洞
        if hole in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(hole)

    @classmethod
    def lightningChain(cls):
        """雷电链：连续闪电攻击"""
        for i in range(8):
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(1)

            # 随机位置闪电
            x_pos = random.randint(0, main.WINDOWWIDTH - 50)

            # 警告
            warning = Bullt.BossBumb(x_pos, 0)
            warning.canMove = False
            warning.hurt = 0
            warning.canDelete = False
            warning.image = pygame.Surface((50, main.WINDOWHEIGHT))
            warning.image.fill((255, 255, 0))
            warning.image.set_alpha(100)
            warning.rect = warning.image.get_rect()
            warning.rect.left = warning.x
            warning.rect.top = warning.y
            Event.Game.allenbumbs.append(warning)

            time.sleep(0.5)

            # 闪电
            if warning in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(warning)

            lightning = Bullt.BossBumb(x_pos, 0)
            lightning.canMove = False
            lightning.canDelete = False
            lightning.image = pygame.Surface((50, main.WINDOWHEIGHT))
            lightning.image.fill((255, 255, 100))
            lightning.rect = lightning.image.get_rect()
            lightning.rect.left = lightning.x
            lightning.rect.top = lightning.y
            Event.Game.allenbumbs.append(lightning)

            # 闪电效果
            for alpha in range(255, 0, -30):
                lightning.image.set_alpha(alpha)
                time.sleep(0.05)

            if lightning in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(lightning)

    @classmethod
    def spiralTrap(cls):
        """螺旋陷阱：创建螺旋形缩小的弹幕陷阱"""
        center_x = Event.Game.wateremoji.x
        center_y = Event.Game.wateremoji.y

        for radius in range(300, 50, -25):
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(1)

            # 螺旋臂数量
            for arm in range(3):
                base_angle = arm * 120 + (300 - radius) * 2  # 旋转效果

                # 每个臂发射多个子弹形成圆
                for offset in range(0, 360, 30):
                    angle = base_angle + offset
                    x = center_x + radius * math.cos(math.radians(angle))
                    y = center_y + radius * math.sin(math.radians(angle))

                    newbumb = Bullt.BossBumb(x, y)
                    # 向中心射击
                    newbumb.tan = math.tan(math.radians(angle + 180))
                    newbumb.speed = 5
                    newbumb.image = Event.Game.bulluten[1]
                    if 90 < (angle + 180) % 360 < 270:
                        newbumb.sample = 1
                    else:
                        newbumb.sample = -1
                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.3)

    # ==================== 符卡技能 ====================

    @classmethod
    def spellcard_sandstorm_apocalypse(cls):
        """符卡：沙尘暴末日 - 大规模沙尘弹幕"""
        Event.Game.boss.canShoot = False  # 禁止普通射击

        # 持续30秒的弹幕
        start_time = time.time()
        while time.time() - start_time < 30 and Event.Game.haveBoss:
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 1. 从四周向中心发射沙尘弹
            for edge in ['top', 'bottom', 'left', 'right']:
                for i in range(5):
                    if edge == 'top':
                        x = random.randint(0, main.WINDOWWIDTH)
                        y = 0
                        angle = random.uniform(60, 120)
                    elif edge == 'bottom':
                        x = random.randint(0, main.WINDOWWIDTH)
                        y = main.WINDOWHEIGHT
                        angle = random.uniform(240, 300)
                    elif edge == 'left':
                        x = 0
                        y = random.randint(0, main.WINDOWHEIGHT)
                        angle = random.uniform(-30, 30)
                    else:  # right
                        x = main.WINDOWWIDTH
                        y = random.randint(0, main.WINDOWHEIGHT)
                        angle = random.uniform(150, 210)

                    newbumb = Bullt.BossBumb(x, y)
                    newbumb.image = Event.Game.bulluten[10]
                    newbumb.speed = random.randint(8, 15)
                    newbumb.tan = math.tan(math.radians(angle))
                    if 90 < angle % 360 < 270:
                        newbumb.sample = 1
                    else:
                        newbumb.sample = -1
                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)

            # 2. Boss位置发射旋转星星
            for angle in range(0, 360, 15):
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = Event.Game.bulluten[0]
                newbumb.speed = 12
                newbumb.tan = math.tan(math.radians(angle))
                if 90 < angle < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.4)

        Event.Game.boss.canShoot = True

    @classmethod
    def spellcard_star_explosion_rain(cls):
        """符卡：星爆雨 - 从天而降的爆炸星星"""
        Event.Game.boss.canShoot = False

        # 持续25秒
        start_time = time.time()
        explosion_count = 0

        while time.time() - start_time < 25 and Event.Game.haveBoss:
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 随机位置落下星星
            for i in range(8):
                x = random.randint(100, main.WINDOWWIDTH - 100)

                # 警告标记
                warning = Bullt.BossBumb(x - 20, 0)
                warning.canMove = False
                warning.hurt = 0
                warning.canDelete = False
                warning.image = pygame.Surface((40, main.WINDOWHEIGHT), pygame.SRCALPHA)
                warning.image.fill((255, 255, 100, 80))
                warning.rect = warning.image.get_rect()
                warning.rect.left = warning.x
                warning.rect.top = warning.y
                Event.Game.allenbumbs.append(warning)

                # 0.3秒后移除警告并创建下落星星
                threading.Thread(target=cls._delayed_star_drop, args=(warning, x), daemon=True).start()

            explosion_count += 1
            time.sleep(0.8)

        Event.Game.boss.canShoot = True

    @classmethod
    def _delayed_star_drop(cls, warning, x):
        """延迟星星下落"""
        time.sleep(0.3)

        if warning in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(warning)

        # 创建下落的星星
        star = Bullt.BossBumb(x, 0)
        star.image = Event.Game.bulluten[0]
        star.speed = 20
        star.direction = 'down'
        star.tan = 0
        star.sample = 0
        star.rect = star.image.get_rect()
        star.rect.left = star.x
        star.rect.top = star.y
        Event.Game.allenbumbs.append(star)

        # 当星星到达屏幕中央时爆炸
        while star in Event.Game.allenbumbs and star.y < main.WINDOWHEIGHT // 2:
            time.sleep(0.05)

        if star in Event.Game.allenbumbs:
            # 爆炸，向八方发射子弹
            explosion_x, explosion_y = star.x, star.y
            Event.Game.allenbumbs.remove(star)

            for angle in range(0, 360, 30):
                newbumb = Bullt.BossBumb(explosion_x, explosion_y)
                newbumb.image = Event.Game.bulluten[1]
                newbumb.speed = 15
                newbumb.tan = math.tan(math.radians(angle))
                if 90 < angle < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

    @classmethod
    def spellcard_dimensional_rift_maze(cls):
        """符卡：次元裂缝迷宫 - 大量传送门和黑洞"""
        Event.Game.boss.canShoot = False

        # 创建多个黑洞
        black_holes = []
        for i in range(6):
            bh_x = random.randint(200, main.WINDOWWIDTH - 200)
            bh_y = random.randint(200, main.WINDOWHEIGHT - 200)

            black_hole = Bullt.BossBumb(bh_x - 50, bh_y - 50)
            black_hole.canMove = False
            black_hole.hurt = 0
            black_hole.canDelete = False
            black_hole.size = 100
            black_hole.image = pygame.Surface((100, 100), pygame.SRCALPHA)
            # 绘制黑洞
            for r in range(50, 0, -5):
                alpha = int(255 * (1 - r / 50))
                color = (50, 0, 100, alpha)
                pygame.draw.circle(black_hole.image, color, (50, 50), r)
            black_hole.rect = black_hole.image.get_rect()
            black_hole.rect.left = black_hole.x
            black_hole.rect.top = black_hole.y
            black_hole.bh_center = (bh_x, bh_y)
            Event.Game.allenbumbs.append(black_hole)
            black_holes.append(black_hole)

        # 持续20秒
        start_time = time.time()

        while time.time() - start_time < 20 and Event.Game.haveBoss:
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 每个黑洞发射子弹和吸引玩家
            for bh in black_holes[:]:
                if bh not in Event.Game.allenbumbs:
                    continue

                bh_x, bh_y = bh.bh_center

                # 吸引玩家
                dx = bh_x - Event.Game.wateremoji.x
                dy = bh_y - Event.Game.wateremoji.y
                distance = math.sqrt(dx**2 + dy**2)
                if distance > 10:
                    pull_strength = min(200 / distance, 2)
                    Event.Game.wateremoji.x += dx / distance * pull_strength
                    Event.Game.wateremoji.y += dy / distance * pull_strength

                # 发射螺旋子弹
                if random.random() < 0.5:
                    angle = random.randint(0, 359)
                    newbumb = Bullt.BossBumb(bh_x, bh_y)
                    newbumb.image = Event.Game.bulluten[5]
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

            # Boss也发射子弹
            for angle in range(0, 360, 45):
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = Event.Game.bulluten[10]
                newbumb.speed = 8
                newbumb.tan = math.tan(math.radians(angle))
                if 90 < angle < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.3)

        # 移除所有黑洞
        for bh in black_holes:
            if bh in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(bh)

        Event.Game.boss.canShoot = True

    @classmethod
    def spellcard_combined_ultimate(cls):
        """符卡：终极组合技 - 结合所有技能的超强弹幕"""
        Event.Game.boss.canShoot = False

        # 持续35秒的终极弹幕
        start_time = time.time()
        phase = 0

        while time.time() - start_time < 35 and Event.Game.haveBoss:
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            current_time = time.time() - start_time

            # 第一阶段（0-10秒）：螺旋陷阱 + 镜像弹幕
            if current_time < 10:
                # 螺旋
                for arm in range(5):
                    angle = (current_time * 100 + arm * 72) % 360
                    for radius in [100, 150, 200, 250]:
                        x = Event.Game.boss.x + radius * math.cos(math.radians(angle))
                        y = Event.Game.boss.y + radius * math.sin(math.radians(angle))

                        newbumb = Bullt.BossBumb(x, y)
                        newbumb.image = Event.Game.bulluten[1]
                        newbumb.speed = 6
                        newbumb.tan = math.tan(math.radians(angle))
                        if 90 < angle < 270:
                            newbumb.sample = 1
                        else:
                            newbumb.sample = -1
                        newbumb.rect = newbumb.image.get_rect()
                        newbumb.rect.left = newbumb.x
                        newbumb.rect.top = newbumb.y
                        Event.Game.allenbumbs.append(newbumb)

                # 镜像
                base_angle = math.degrees(math.atan2(
                    Event.Game.wateremoji.y - Event.Game.boss.y,
                    Event.Game.wateremoji.x - Event.Game.boss.x
                ))
                for offset in [-30, 0, 30]:
                    angle = base_angle + offset
                    newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                    newbumb.image = Event.Game.bulluten[0]
                    newbumb.speed = 12
                    newbumb.tan = math.tan(math.radians(angle))
                    if 90 < angle < 270:
                        newbumb.sample = 1
                    else:
                        newbumb.sample = -1
                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)

                    # 对称
                    mirror_angle = base_angle + 180 + offset
                    newbumb2 = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                    newbumb2.image = Event.Game.bulluten[0]
                    newbumb2.speed = 12
                    newbumb2.tan = math.tan(math.radians(mirror_angle))
                    if 90 < mirror_angle < 270:
                        newbumb2.sample = 1
                    else:
                        newbumb2.sample = -1
                    newbumb2.rect = newbumb2.image.get_rect()
                    newbumb2.rect.left = newbumb2.x
                    newbumb2.rect.top = newbumb2.y
                    Event.Game.allenbumbs.append(newbumb2)

            # 第二阶段（10-20秒）：雷电链 + 黑洞
            elif current_time < 20:
                # 随机闪电
                if random.random() < 0.3:
                    x = random.randint(100, main.WINDOWWIDTH - 100)
                    y = random.randint(100, main.WINDOWHEIGHT - 100)

                    lightning = Bullt.BossBumb(x - 15, 0)
                    lightning.canMove = False
                    lightning.canDelete = False
                    lightning.image = pygame.Surface((30, main.WINDOWHEIGHT))
                    lightning.image.fill((255, 255, 0))
                    lightning.rect = lightning.image.get_rect()
                    lightning.rect.left = lightning.x
                    lightning.rect.top = lightning.y
                    Event.Game.allenbumbs.append(lightning)

                    threading.Thread(target=cls._fade_lightning, args=(lightning,), daemon=True).start()

                # 吸引玩家
                dx = Event.Game.boss.x - Event.Game.wateremoji.x
                dy = Event.Game.boss.y - Event.Game.wateremoji.y
                distance = math.sqrt(dx**2 + dy**2)
                if distance > 10:
                    pull_strength = min(180 / distance, 1.5)
                    Event.Game.wateremoji.x += dx / distance * pull_strength
                    Event.Game.wateremoji.y += dy / distance * pull_strength

                # 环形弹幕
                for angle in range(0, 360, 20):
                    newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                    newbumb.image = Event.Game.bulluten[5]
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

            # 第三阶段（20-35秒）：全屏混沌
            else:
                # 从四方发射
                for direction in range(4):
                    angle = direction * 90 + random.uniform(-30, 30)
                    for speed in [8, 10, 12, 14]:
                        newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                        newbumb.image = Event.Game.bulluten[random.randint(0, 10)]
                        newbumb.speed = speed
                        newbumb.tan = math.tan(math.radians(angle))
                        if 90 < angle < 270:
                            newbumb.sample = 1
                        else:
                            newbumb.sample = -1
                        newbumb.rect = newbumb.image.get_rect()
                        newbumb.rect.left = newbumb.x
                        newbumb.rect.top = newbumb.y
                        Event.Game.allenbumbs.append(newbumb)

                # 追踪弹
                if random.random() < 0.4:
                    newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                    newbumb.image = Event.Game.bulluten[2]
                    newbumb.speed = 9
                    newbumb.get = True
                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.15)

        Event.Game.boss.canShoot = True

    @classmethod
    def _fade_lightning(cls, lightning):
        """闪电淡出"""
        time.sleep(0.5)
        if lightning in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(lightning)
