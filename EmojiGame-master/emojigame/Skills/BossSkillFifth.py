import time, pygame, win32gui, random, main, Event, Move, threading, Bullt, math, OEmoji

import wx

import Frame


class BossSkillFifth:
    @classmethod
    def moveFrame(cls):
        try:
            while (Event.Game.haveBoss and Event.Game.boss.bossrint == 5):
                Move.moveWin(Event.Game.rx, Event.Game.ry)
                time.sleep(0.06857)
                Move.moveWin(Event.Game.rx, Event.Game.ry - 10)
                time.sleep(0.06857)
                Move.moveWin(Event.Game.rx, Event.Game.ry - 20)
                time.sleep(0.06857)
                Move.moveWin(Event.Game.rx, Event.Game.ry - 10)
                time.sleep(0.06857)
                Move.moveWin(Event.Game.rx, Event.Game.ry)
                time.sleep(0.06857)
        except RuntimeError:
            pass

    @classmethod
    def modifyTNT(cls, tnt):
        time.sleep(1.5)
        tnt.image = Event.Game.bulluten[14]
        time.sleep(1)
        while Event.Game.istimestoptime:
            time.sleep(1)
        newbumb = Bullt.BossBumb(tnt.x, tnt.y)
        newbumb.canDelete = False
        newbumb.canMove = False
        newbumb.image = Event.Game.bulluten[13]
        newbumb.rect = newbumb.image.get_rect()
        newbumb.rect.left = newbumb.x
        newbumb.rect.top = newbumb.y
        Event.Game.allenbumbs.append(newbumb)
        try:
            Event.Game.allenbumbs.remove(tnt)
        except ValueError:
            pass
        index = 240
        newbumb.image.set_alpha(index)
        for i in range(10):
            while Event.Game.istimestoptime:
                time.sleep(1)
            newbumb.size += 8
            newbumb.x -= 4
            newbumb.y -= 4
            newbumb.image = pygame.transform.smoothscale(newbumb.image,
                                                         (newbumb.size, newbumb.size))
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y  # 更新碰撞体积
            newbumb.image.set_alpha(index)
            index -= 20
            time.sleep(0.1)
        try:
            Event.Game.allenbumbs.remove(newbumb)
        except ValueError:
            pass

    @classmethod
    def dragAttack(cls, newbumb):
        art = math.atan(newbumb.tan)
        artt = math.atan(newbumb.tan)
        sample = newbumb.sample
        randoms = random.random()
        while -20 <= newbumb.x < main.WINDOWWIDTH and -20 <= newbumb.y <= main.WINDOWHEIGHT and not newbumb.blow:
            while Event.Game.istimestoptime:
                time.sleep(1)
            if randoms < 0.5:
                art -= math.pi / 5
            else:
                art += math.pi / 5
            newbumb.tan = math.tan(art)
            if sample == 0:
                if newbumb.direction == 'left':
                    newbumb.x -= newbumb.speed
            elif newbumb.direction == 'right':
                newbumb.x += math.sqrt(newbumb.speed * 10 / (1 + math.tan(artt) ** 2))
                newbumb.y += math.sqrt(newbumb.speed * 10 / (1 + math.tan(artt) ** 2)) * math.tan(artt)
            elif newbumb.direction == 'left' or (newbumb.direction == 'right' and newbumb.sample == -1):
                newbumb.x -= math.sqrt(newbumb.speed * 10 / (1 + math.tan(artt) ** 2))
                newbumb.y -= math.sqrt(newbumb.speed * 10 / (1 + math.tan(artt) ** 2)) * math.tan(artt)
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            time.sleep(0.1)
        if not (-20 <= newbumb.x < main.WINDOWWIDTH and -20 <= newbumb.y <= main.WINDOWHEIGHT):
            try:
                Event.Game.allenbumbs.remove(newbumb)
            except ValueError:
                pass

    @classmethod
    def jumpShoot(cls):
        for i in range(10):
            if Event.Game.haveBoss:
                while Event.Game.istimestoptime:
                    time.sleep(1)
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = Event.Game.bulluten[5]
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                newbumb.size = 23
                newbumb.banRemove = True
                newbumb.canReturn = True
                Event.Game.allenbumbs.append(newbumb)
                th = threading.Thread(target=cls.dragAttack, args=(newbumb,))
                th.daemon = True
                th.start()
                time.sleep(0.2)
    @classmethod
    def healMode(cls):
        Event.Game.healtime = True
        Event.Game.boss.image = pygame.image.load('image/lightboss1.png')
        time.sleep(3)
        Event.Game.healtime = False
        Event.Game.boss.image = pygame.image.load('image/bossenemy-5.png')
    @classmethod
    def throwTNT(cls):
        for i in range(5):
            if Event.Game.haveBoss:
                while Event.Game.istimestoptime:
                    time.sleep(1)
                tnt = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                tnt.image = Event.Game.bulluten[12]
                tnt.rect = tnt.image.get_rect()
                tnt.rect.left = tnt.x
                tnt.rect.top = tnt.y
                tnt.speed = 7
                Event.Game.allenbumbs.append(tnt)
                th = threading.Thread(target=cls.modifyTNT, args=(tnt,))
                th.daemon = True
                th.start()
                time.sleep(0.8)

    @classmethod
    def chainExplosion(cls):
        """连锁爆炸：在屏幕上创建连锁反应的爆炸"""
        explosions = []
        # 第一个爆炸点在boss处
        start_x, start_y = Event.Game.boss.x, Event.Game.boss.y

        for i in range(8):
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 每次爆炸向玩家方向偏移
            if i == 0:
                ex, ey = start_x, start_y
            else:
                # 朝向玩家方向延伸
                px, py = Event.Game.wateremoji.x, Event.Game.wateremoji.y
                prev_x, prev_y = explosions[-1]
                dx = px - prev_x
                dy = py - prev_y
                distance = math.sqrt(dx**2 + dy**2)
                if distance > 0:
                    ex = prev_x + (dx / distance) * 120
                    ey = prev_y + (dy / distance) * 120
                else:
                    ex = prev_x + random.randint(-100, 100)
                    ey = prev_y + random.randint(-100, 100)

            explosions.append((ex, ey))

            # 警告标记
            warning = Bullt.BossBumb(ex - 40, ey - 40)
            warning.canMove = False
            warning.hurt = 0
            warning.canDelete = False
            warning.image = pygame.Surface((80, 80), pygame.SRCALPHA)
            pygame.draw.circle(warning.image, (255, 255, 0, 150), (40, 40), 40, 3)
            warning.rect = warning.image.get_rect()
            warning.rect.left = warning.x
            warning.rect.top = warning.y
            Event.Game.allenbumbs.append(warning)

            time.sleep(0.4)

            # 移除警告，创建爆炸
            if warning in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(warning)

            explosion = Bullt.BossBumb(ex - 50, ey - 50)
            explosion.canMove = False
            explosion.canDelete = False
            explosion.hurt = 12
            explosion.image = Event.Game.bulluten[13]
            explosion.size = 100
            explosion.image = pygame.transform.smoothscale(explosion.image, (100, 100))
            explosion.rect = explosion.image.get_rect()
            explosion.rect.left = explosion.x
            explosion.rect.top = explosion.y
            Event.Game.allenbumbs.append(explosion)

            # 爆炸扩散并淡出
            threading.Thread(target=cls._explosionFade, args=(explosion,), daemon=True).start()

            # 四散弹幕
            for angle in range(0, 360, 45):
                newbumb = Bullt.BossBumb(ex, ey)
                newbumb.image = Event.Game.bulluten[5]
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

    @classmethod
    def _explosionFade(cls, explosion):
        """爆炸淡出"""
        for alpha in range(255, 0, -25):
            explosion.image.set_alpha(alpha)
            time.sleep(0.05)
        if explosion in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(explosion)

    @classmethod
    def gravitySink(cls):
        """重力陷阱：创建一个吸引所有子弹的重力井"""
        # 在随机位置创建重力井
        sink_x = random.randint(300, main.WINDOWWIDTH - 300)
        sink_y = random.randint(250, main.WINDOWHEIGHT - 250)

        # 创建重力井视觉效果
        sink = Bullt.BossBumb(sink_x - 60, sink_y - 60)
        sink.canMove = False
        sink.hurt = 0
        sink.canDelete = False
        sink.size = 120
        sink.image = pygame.Surface((120, 120), pygame.SRCALPHA)
        # 绘制多层圆环
        for radius in range(60, 10, -10):
            alpha = int(255 * (1 - radius / 60))
            pygame.draw.circle(sink.image, (100, 50, 200, alpha), (60, 60), radius, 5)
        sink.rect = sink.image.get_rect()
        sink.rect.left = sink.x
        sink.rect.top = sink.y
        Event.Game.allenbumbs.append(sink)

        # 启动重力效果
        duration = 5
        start = time.time()

        while time.time() - start < duration and sink in Event.Game.allenbumbs:
            # 吸引玩家
            dx = sink_x - Event.Game.wateremoji.x
            dy = sink_y - Event.Game.wateremoji.y
            distance = math.sqrt(dx**2 + dy**2)
            if distance > 10:
                pull_strength = min(250 / distance, 2.5)
                Event.Game.wateremoji.x += dx / distance * pull_strength
                Event.Game.wateremoji.y += dy / distance * pull_strength

            # 每隔一段时间从重力井发射子弹
            if random.random() < 0.4:
                angle = random.randint(0, 359)
                newbumb = Bullt.BossBumb(sink_x, sink_y)
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

            time.sleep(0.15)

        # 移除重力井
        if sink in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(sink)

    @classmethod
    def mirrorTNT(cls):
        """镜像TNT：投掷会创建镜像副本的TNT"""
        for i in range(4):
            if not Event.Game.haveBoss:
                break
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 主TNT
            main_tnt = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            main_tnt.image = Event.Game.bulluten[12]
            main_tnt.speed = 8
            main_tnt.get = True  # 追踪玩家
            main_tnt.rect = main_tnt.image.get_rect()
            main_tnt.rect.left = main_tnt.x
            main_tnt.rect.top = main_tnt.y
            Event.Game.allenbumbs.append(main_tnt)

            # 1秒后创建镜像
            threading.Thread(target=cls._createMirrors, args=(main_tnt,), daemon=True).start()
            time.sleep(1.2)

    @classmethod
    def _createMirrors(cls, main_tnt):
        """创建镜像TNT"""
        time.sleep(1)

        if main_tnt not in Event.Game.allenbumbs:
            return

        # 记录主TNT位置
        center_x, center_y = main_tnt.x, main_tnt.y

        # 创建4个镜像TNT（上下左右）
        mirror_offsets = [
            (0, -80), (0, 80), (-80, 0), (80, 0)
        ]

        mirrors = []
        for dx, dy in mirror_offsets:
            mirror = Bullt.BossBumb(center_x + dx, center_y + dy)
            mirror.image = Event.Game.bulluten[14]  # 红色TNT
            mirror.canMove = False
            mirror.canDelete = False
            mirror.rect = mirror.image.get_rect()
            mirror.rect.left = mirror.x
            mirror.rect.top = mirror.y
            Event.Game.allenbumbs.append(mirror)
            mirrors.append(mirror)

        # 主TNT也变成红色
        main_tnt.image = Event.Game.bulluten[14]

        time.sleep(0.8)

        # 所有TNT同时爆炸
        all_tnts = mirrors + [main_tnt]
        for tnt in all_tnts:
            if tnt not in Event.Game.allenbumbs:
                continue

            # 创建爆炸
            explosion = Bullt.BossBumb(tnt.x - 35, tnt.y - 35)
            explosion.canMove = False
            explosion.canDelete = False
            explosion.hurt = 10
            explosion.image = Event.Game.bulluten[13]
            explosion.size = 70
            explosion.image = pygame.transform.smoothscale(explosion.image, (70, 70))
            explosion.rect = explosion.image.get_rect()
            explosion.rect.left = explosion.x
            explosion.rect.top = explosion.y
            Event.Game.allenbumbs.append(explosion)

            # 移除TNT
            try:
                Event.Game.allenbumbs.remove(tnt)
            except ValueError:
                pass

            # 爆炸淡出
            threading.Thread(target=cls._explosionFade, args=(explosion,), daemon=True).start()

            # 爆炸弹幕
            for angle in range(0, 360, 30):
                newbumb = Bullt.BossBumb(tnt.x, tnt.y)
                newbumb.image = Event.Game.bulluten[5]
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
