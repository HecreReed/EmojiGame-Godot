import time, pygame, win32gui, random, main, Event, Move, threading, Bullt, math, OEmoji, wx, Frame


class BossSkillSixth:
    """Boss6 - 5阶段终极Boss"""
    current_phase = 1  # 当前阶段 1-5
    phase_hp = []  # 每个阶段的血量
    window_shake_active = False
    color_shift_r = 255
    color_shift_direction = -1
    transparency_active = False
    pentagram_frame = None
    laser_warning_frames = []

    @classmethod
    def load_fire_image(cls, fire_type, scale=2.0):
        """加载并缩放火焰图片"""
        img = pygame.image.load(f'image/{fire_type}.png')
        # 缩放到2倍大小
        original_size = img.get_size()
        new_size = (int(original_size[0] * scale), int(original_size[1] * scale))
        return pygame.transform.scale(img, new_size)

    @classmethod
    def init_phases(cls):
        """初始化5个阶段的血量阈值"""
        total_hp = Event.Game.boss.maxlive
        phase_hp = total_hp / 5
        # 阶段阈值：[4/5, 3/5, 2/5, 1/5, 0]
        # 当血量 <= 4/5时进入阶段2，<= 3/5时进入阶段3，以此类推
        cls.phase_hp = [phase_hp * i for i in range(4, -1, -1)]  # [4/5, 3/5, 2/5, 1/5, 0]
        cls.current_phase = 1
        cls.window_shake_active = False
        cls.transparency_active = False

    @classmethod
    def get_current_phase(cls):
        """根据当前血量判断阶段"""
        if not Event.Game.haveBoss or Event.Game.boss.bossrint != 6:
            return 1
        boss_hp = Event.Game.boss.live
        # 阶段1: hp > 4/5
        # 阶段2: 3/5 < hp <= 4/5
        # 阶段3: 2/5 < hp <= 3/5
        # 阶段4: 1/5 < hp <= 2/5
        # 阶段5: hp <= 1/5
        for i, hp_threshold in enumerate(cls.phase_hp):
            if boss_hp > hp_threshold:
                return i + 1
        return 5

    # ==================== 第一阶段：窗口震动 + 左侧激光 ====================

    @classmethod
    def phase1_window_shake(cls):
        """第一阶段：窗口丝滑移动"""
        cls.window_shake_active = True
        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 1:
            try:
                # 丝滑的圆周运动
                for angle in range(0, 360, 5):
                    if not (Event.Game.haveBoss and cls.get_current_phase() == 1):
                        break
                    offset_x = int(15 * math.cos(math.radians(angle)))
                    offset_y = int(15 * math.sin(math.radians(angle)))
                    Move.moveWin(Event.Game.rx + offset_x, Event.Game.ry + offset_y)
                    time.sleep(0.02)
            except RuntimeError:
                break
        # 回到原点
        Move.moveWin(Event.Game.rx, Event.Game.ry)
        cls.window_shake_active = False

    @classmethod
    def phase1_left_laser(cls):
        """第一阶段：左侧激光攻击"""
        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 1:
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 随机选择一个y坐标
            laser_y = random.randint(100, main.WINDOWHEIGHT - 200)

            # 白光警告
            warning = Bullt.BossBumb(-50, laser_y)
            warning.canMove = False
            warning.hurt = 0
            warning.canDelete = False
            warning.image = pygame.image.load('image/attention.png')
            warning.rect = warning.image.get_rect()
            warning.rect.left = warning.x
            warning.rect.top = warning.y
            Event.Game.allenbumbs.append(warning)

            time.sleep(0.8)  # 警告时间

            # 射出激光
            if warning in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(warning)

            laser = Bullt.BossBumb(0, laser_y - 50)
            laser.canMove = False
            laser.banRemove = True
            laser.canDelete = False
            laser.image = pygame.image.load('image/light.png')
            laser.rect = laser.image.get_rect()
            laser.rect.left = laser.x
            laser.rect.top = laser.y
            Event.Game.allenbumbs.append(laser)

            # 激光淡入
            for alpha in range(0, 256, 20):
                laser.image.set_alpha(alpha)
                time.sleep(0.05)

            time.sleep(0.3)

            # 激光淡出
            for alpha in range(255, 0, -20):
                laser.image.set_alpha(alpha)
                time.sleep(0.05)

            if laser in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(laser)

            time.sleep(1)  # 每隔1s触发一次

    @classmethod
    def phase1_fire_rain(cls):
        """第一阶段：火焰雨（以boss为中心向前方随机射击）"""
        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 1:
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 向前方（左侧）随机角度射击
            angle = random.uniform(-60, 60)  # 前方120度范围
            newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            newbumb.image = cls.load_fire_image('fire1')
            newbumb.speed = random.randint(8, 15)
            newbumb.tan = math.tan(math.radians(angle))
            newbumb.sample = -1  # 向左
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.2)

    @classmethod
    def phase1_spiral_attack(cls):
        """第一阶段技能1：螺旋弹幕"""
        for rotation in range(0, 720, 15):  # 旋转两圈
            if not (Event.Game.haveBoss and cls.get_current_phase() == 1):
                break
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            for offset in [0, 120, 240]:  # 三方向
                angle = rotation + offset
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = cls.load_fire_image('fire1')
                newbumb.speed = 10
                newbumb.tan = math.tan(math.radians(angle))
                if 90 < angle % 360 < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.1)

    @classmethod
    def phase1_cross_laser(cls):
        """第一阶段技能2：十字激光"""
        # 创建4个方向的警告
        warnings = []
        positions = [
            (Event.Game.boss.x, 0, 'vertical'),  # 上
            (Event.Game.boss.x, main.WINDOWHEIGHT - 50, 'vertical'),  # 下
            (0, Event.Game.boss.y, 'horizontal'),  # 左
            (main.WINDOWWIDTH - 50, Event.Game.boss.y, 'horizontal')  # 右
        ]

        for x, y, orientation in positions:
            warning = Bullt.BossBumb(x, y)
            warning.canMove = False
            warning.hurt = 0
            warning.canDelete = False
            warning.image = pygame.image.load('image/error.png')
            warning.rect = warning.image.get_rect()
            warning.rect.left = warning.x
            warning.rect.top = warning.y
            Event.Game.allenbumbs.append(warning)
            warnings.append(warning)

        time.sleep(1)

        # 移除警告，射出激光
        for warning in warnings:
            if warning in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(warning)

        # 垂直激光
        for x_pos in [Event.Game.boss.x - 25]:
            laser = Bullt.BossBumb(x_pos, 0)
            laser.canMove = False
            laser.canDelete = False
            laser.image = pygame.Surface((50, main.WINDOWHEIGHT))
            laser.image.fill((255, 100, 100))
            laser.rect = laser.image.get_rect()
            laser.rect.left = laser.x
            laser.rect.top = laser.y
            Event.Game.allenbumbs.append(laser)
            threading.Thread(target=cls._fade_out_laser, args=(laser, 1.5), daemon=True).start()

        # 水平激光
        for y_pos in [Event.Game.boss.y - 25]:
            laser = Bullt.BossBumb(0, y_pos)
            laser.canMove = False
            laser.canDelete = False
            laser.image = pygame.Surface((main.WINDOWWIDTH, 50))
            laser.image.fill((255, 100, 100))
            laser.rect = laser.image.get_rect()
            laser.rect.left = laser.x
            laser.rect.top = laser.y
            Event.Game.allenbumbs.append(laser)
            threading.Thread(target=cls._fade_out_laser, args=(laser, 1.5), daemon=True).start()

    @classmethod
    def _fade_out_laser(cls, laser, duration):
        """激光淡出"""
        time.sleep(duration)
        if laser in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(laser)

    # ==================== 第二阶段：颜色变化 + 锥形弹幕 ====================

    @classmethod
    def phase2_color_shift(cls):
        """第二阶段：背景颜色渐变"""
        cls.color_shift_r = 255
        cls.color_shift_direction = -1
        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 2:
            cls.color_shift_r += cls.color_shift_direction * 3
            if cls.color_shift_r <= 0:
                cls.color_shift_r = 0
                cls.color_shift_direction = 1
            elif cls.color_shift_r >= 255:
                cls.color_shift_r = 255
                cls.color_shift_direction = -1
            time.sleep(0.05)

    @classmethod
    def get_color_overlay(cls):
        """获取当前颜色覆盖层"""
        if cls.get_current_phase() == 2:
            overlay = pygame.Surface((main.WINDOWWIDTH, main.WINDOWHEIGHT))
            overlay.fill((cls.color_shift_r, 0, 0))
            overlay.set_alpha(100)
            return overlay
        return None

    @classmethod
    def phase2_cone_shot(cls):
        """第二阶段：锥形弹幕攻击"""
        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 2:
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 计算指向玩家的角度
            dx = Event.Game.wateremoji.x - Event.Game.boss.x
            dy = Event.Game.wateremoji.y - Event.Game.boss.y
            center_angle = math.degrees(math.atan2(dy, dx))

            # 发射10个子弹形成锥形
            for i in range(10):
                spread_angle = center_angle + (i - 4.5) * 8  # 锥形扩散
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = cls.load_fire_image('fire1')
                newbumb.speed = 12
                newbumb.tan = math.tan(math.radians(spread_angle))
                if -90 < spread_angle % 360 < 90:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(3)  # 每隔3s触发

    @classmethod
    def phase2_boss_teleport(cls):
        """第二阶段：Boss快速移动"""
        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 2:
            # 快速移动到随机位置
            target_x = random.randint(main.WINDOWWIDTH // 2, main.WINDOWWIDTH - 100)
            target_y = random.randint(100, main.WINDOWHEIGHT - 100)

            # 淡出效果
            original_alpha = 255
            for alpha in range(255, 100, -30):
                if hasattr(Event.Game.boss.image, 'set_alpha'):
                    Event.Game.boss.image.set_alpha(alpha)
                time.sleep(0.05)

            # 瞬移
            Event.Game.boss.x = target_x
            Event.Game.boss.y = target_y

            # 淡入效果
            for alpha in range(100, 256, 30):
                if hasattr(Event.Game.boss.image, 'set_alpha'):
                    Event.Game.boss.image.set_alpha(alpha)
                time.sleep(0.05)

            time.sleep(2)

    @classmethod
    def phase2_wave_attack(cls):
        """第二阶段技能1：波纹攻击"""
        for wave in range(5):
            if not (Event.Game.haveBoss and cls.get_current_phase() == 2):
                break

            # 每一波发射一圈子弹
            for angle in range(0, 360, 20):
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = cls.load_fire_image('fire1')
                newbumb.speed = 8 + wave * 2  # 每波速度递增
                newbumb.tan = math.tan(math.radians(angle))
                if 90 < angle < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.5)

    @classmethod
    def phase2_tracking_bullets(cls):
        """第二阶段技能2：追踪弹"""
        for i in range(8):
            if not (Event.Game.haveBoss and cls.get_current_phase() == 2):
                break

            newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            newbumb.image = Event.Game.bulluten[2]
            newbumb.speed = 6
            newbumb.get = True  # 追踪
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.3)

    @classmethod
    def phase2_meteor_shower(cls):
        """第二阶段技能3：流星雨"""
        for i in range(15):
            if not (Event.Game.haveBoss and cls.get_current_phase() == 2):
                break

            x_pos = random.randint(0, main.WINDOWWIDTH)
            newbumb = Bullt.BossBumb(x_pos, -50)
            newbumb.image = cls.load_fire_image('fire1')
            newbumb.direction = 'down'
            newbumb.speed = random.randint(10, 20)
            newbumb.tan = 0
            newbumb.sample = 0
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.2)

    # ==================== 第三阶段：外星人 + 反弹子弹 + 半透明 ====================

    @classmethod
    def phase3_transparency(cls):
        """第三阶段：设置半透明效果"""
        cls.transparency_active = True
        # 透明度会在主渲染循环中应用

    @classmethod
    def phase3_alien_summon(cls):
        """第三阶段：召唤外星人"""
        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 3:
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 从四个方向随机召唤
            direction = random.choice(['top', 'bottom', 'left', 'right'])

            if direction == 'top':
                x, y = random.randint(100, main.WINDOWWIDTH - 100), -40
                dir_name = 'down'
            elif direction == 'bottom':
                x, y = random.randint(100, main.WINDOWWIDTH - 100), main.WINDOWHEIGHT + 40
                dir_name = 'up'
            elif direction == 'left':
                x, y = -40, random.randint(100, main.WINDOWHEIGHT - 100)
                dir_name = 'right'
            else:  # right
                x, y = main.WINDOWWIDTH + 40, random.randint(100, main.WINDOWHEIGHT - 100)
                dir_name = 'left'

            alien = OEmoji.Enemy()
            alien.x = x
            alien.y = y
            alien.direction = dir_name
            alien.canChangeMove = False
            alien.rint = 8
            alien.image = pygame.image.load('image/alien.png')
            alien.live = 50 * Event.Game.bossdeathtimes
            alien.maxlive = 50 * Event.Game.bossdeathtimes
            alien.explode_time = time.time() + 3  # 3秒后爆炸
            Event.Game.g_enemies.append(alien)

            # 启动移动和爆炸线程
            threading.Thread(target=cls._alien_move_to_player, args=(alien,), daemon=True).start()
            threading.Thread(target=cls._alien_explode, args=(alien,), daemon=True).start()

            time.sleep(1.5)

    @classmethod
    def _alien_move_to_player(cls, alien):
        """外星人向玩家移动"""
        while alien in Event.Game.g_enemies and alien.live > 0:
            # 计算朝向玩家的方向
            dx = Event.Game.wateremoji.x - alien.x
            dy = Event.Game.wateremoji.y - alien.y
            distance = math.sqrt(dx**2 + dy**2)

            if distance > 5:
                alien.x += (dx / distance) * 3
                alien.y += (dy / distance) * 3

            time.sleep(0.05)

    @classmethod
    def _alien_explode(cls, alien):
        """外星人爆炸"""
        time.sleep(3)

        if alien not in Event.Game.g_enemies:
            return

        # 创建爆炸效果
        explosion = Bullt.BossBumb(alien.x - 50, alien.y - 50)
        explosion.canMove = False
        explosion.canDelete = False
        explosion.hurt = 15  # 范围伤害
        explosion.size = 100
        explosion.image = pygame.Surface((100, 100), pygame.SRCALPHA)
        pygame.draw.circle(explosion.image, (255, 100, 0, 200), (50, 50), 50)
        explosion.rect = explosion.image.get_rect()
        explosion.rect.left = explosion.x
        explosion.rect.top = explosion.y
        Event.Game.allenbumbs.append(explosion)

        # 移除外星人
        try:
            Event.Game.g_enemies.remove(alien)
        except ValueError:
            pass

        # 爆炸扩散动画
        for i in range(5):
            explosion.size += 20
            explosion.x -= 10
            explosion.y -= 10
            explosion.image = pygame.Surface((explosion.size, explosion.size), pygame.SRCALPHA)
            pygame.draw.circle(explosion.image, (255, 100, 0, 200 - i * 40),
                             (explosion.size // 2, explosion.size // 2), explosion.size // 2)
            explosion.rect = explosion.image.get_rect()
            explosion.rect.left = explosion.x
            explosion.rect.top = explosion.y
            time.sleep(0.1)

        if explosion in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(explosion)

    @classmethod
    def phase3_bounce_bullets(cls):
        """第三阶段：反弹子弹"""
        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 3:
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 向玩家方向发射反弹子弹
            dx = Event.Game.wateremoji.x - Event.Game.boss.x
            dy = Event.Game.wateremoji.y - Event.Game.boss.y
            angle = math.degrees(math.atan2(dy, dx))

            newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            newbumb.image = cls.load_fire_image('fire1')
            newbumb.speed = 10
            newbumb.canReturn = True  # 反弹
            newbumb.tan = math.tan(math.radians(angle))
            if -90 < angle % 360 < 90:
                newbumb.sample = 1
            else:
                newbumb.sample = -1
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.5)

    @classmethod
    def phase3_circle_trap(cls):
        """第三阶段技能1：圆形陷阱"""
        # 在玩家周围创建圆形弹幕
        center_x = Event.Game.wateremoji.x
        center_y = Event.Game.wateremoji.y
        radius = 150

        for angle in range(0, 360, 15):
            x = center_x + radius * math.cos(math.radians(angle))
            y = center_y + radius * math.sin(math.radians(angle))

            newbumb = Bullt.BossBumb(x, y)
            newbumb.image = Event.Game.bulluten[1]
            newbumb.speed = 8
            # 向圆心射击
            newbumb.tan = math.tan(math.radians(angle + 180))
            if 90 < (angle + 180) % 360 < 270:
                newbumb.sample = 1
            else:
                newbumb.sample = -1
            newbumb.canReturn = True
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)

    @classmethod
    def phase3_laser_grid(cls):
        """第三阶段技能2：激光网格"""
        # 创建网格状激光
        for i in range(3):
            # 垂直激光
            x_pos = main.WINDOWWIDTH // 4 * (i + 1)
            laser = Bullt.BossBumb(x_pos - 10, 0)
            laser.canMove = False
            laser.canDelete = False
            laser.image = pygame.Surface((20, main.WINDOWHEIGHT))
            laser.image.fill((100, 255, 100))
            laser.image.set_alpha(150)
            laser.rect = laser.image.get_rect()
            laser.rect.left = laser.x
            laser.rect.top = laser.y
            Event.Game.allenbumbs.append(laser)
            threading.Thread(target=cls._fade_out_laser, args=(laser, 2), daemon=True).start()

        time.sleep(0.5)

        for i in range(3):
            # 水平激光
            y_pos = main.WINDOWHEIGHT // 4 * (i + 1)
            laser = Bullt.BossBumb(0, y_pos - 10)
            laser.canMove = False
            laser.canDelete = False
            laser.image = pygame.Surface((main.WINDOWWIDTH, 20))
            laser.image.fill((100, 255, 100))
            laser.image.set_alpha(150)
            laser.rect = laser.image.get_rect()
            laser.rect.left = laser.x
            laser.rect.top = laser.y
            Event.Game.allenbumbs.append(laser)
            threading.Thread(target=cls._fade_out_laser, args=(laser, 2), daemon=True).start()

    # ==================== 第四阶段：窗口闪现 + 混沌弹幕 + 双激光 ====================

    @classmethod
    def phase4_window_teleport(cls):
        """第四阶段：窗口随机闪现"""
        import ctypes
        user32 = ctypes.windll.user32
        screen_width = user32.GetSystemMetrics(0)
        screen_height = user32.GetSystemMetrics(1)

        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 4:
            # 随机位置（不超出屏幕范围）
            max_x = screen_width - main.WINDOWWIDTH
            max_y = screen_height - main.WINDOWHEIGHT

            new_x = random.randint(0, max(0, max_x))
            new_y = random.randint(0, max(0, max_y))

            Move.moveWin(new_x, new_y)
            Event.Game.rx = new_x
            Event.Game.ry = new_y

            time.sleep(2)

    @classmethod
    def phase4_chaos_bullets(cls):
        """第四阶段：混沌弹幕"""
        bullet_images = [
            'image/fire1.png',
            Event.Game.bulluten[1],
            Event.Game.bulluten[2],
            Event.Game.bulluten[4],
            Event.Game.bulluten[5],
            Event.Game.bulluten[9],
            Event.Game.bulluten[10],
            Event.Game.bulluten[11]
        ]

        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 4:
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 疯狂射击
            for i in range(5):
                angle = random.uniform(0, 360)
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)

                # 随机选择子弹图片
                bullet_img = random.choice(bullet_images)
                if isinstance(bullet_img, str):
                    newbumb.image = pygame.image.load(bullet_img)
                else:
                    newbumb.image = bullet_img

                newbumb.speed = random.randint(5, 18)
                newbumb.tan = math.tan(math.radians(angle))
                if 90 < angle < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1

                # 随机特性
                if random.random() < 0.3:
                    newbumb.canReturn = True  # 反弹
                if random.random() < 0.2:
                    newbumb.get = True  # 追踪

                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.15)  # 快速射击

    @classmethod
    def phase4_right_dual_laser(cls):
        """第四阶段：右侧双激光"""
        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 4:
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            # 两个随机高度
            y1 = random.randint(100, main.WINDOWHEIGHT - 300)
            y2 = y1 + random.randint(150, 250)

            for laser_y in [y1, y2]:
                # 警告
                warning = Bullt.BossBumb(main.WINDOWWIDTH - 100, laser_y)
                warning.canMove = False
                warning.hurt = 0
                warning.canDelete = False
                warning.image = pygame.image.load('image/attention.png')
                warning.rect = warning.image.get_rect()
                warning.rect.left = warning.x
                warning.rect.top = warning.y
                Event.Game.allenbumbs.append(warning)

            time.sleep(0.8)

            # 清除警告，射出激光
            for bumb in Event.Game.allenbumbs[::]:
                if hasattr(bumb, 'hurt') and bumb.hurt == 0 and bumb.x > main.WINDOWWIDTH - 150:
                    Event.Game.allenbumbs.remove(bumb)

            for laser_y in [y1, y2]:
                laser = Bullt.BossBumb(main.WINDOWWIDTH - 1280, laser_y - 50)
                laser.canMove = False
                laser.banRemove = True
                laser.canDelete = False
                laser.image = pygame.image.load('image/light.png')
                laser.rect = laser.image.get_rect()
                laser.rect.left = laser.x
                laser.rect.top = laser.y
                Event.Game.allenbumbs.append(laser)

                # 淡入淡出
                threading.Thread(target=cls._laser_fade_effect, args=(laser,), daemon=True).start()

            time.sleep(2.5)

    @classmethod
    def _laser_fade_effect(cls, laser):
        """激光淡入淡出效果"""
        for alpha in range(0, 256, 25):
            laser.image.set_alpha(alpha)
            time.sleep(0.03)
        time.sleep(0.5)
        for alpha in range(255, 0, -25):
            laser.image.set_alpha(alpha)
            time.sleep(0.03)
        if laser in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(laser)

    @classmethod
    def phase4_spiral_hell(cls):
        """第四阶段技能1：螺旋地狱"""
        for rotation in range(0, 1080, 10):  # 旋转三圈
            if not (Event.Game.haveBoss and cls.get_current_phase() == 4):
                break

            for arms in range(6):  # 6条螺旋臂
                angle = rotation + arms * 60
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = cls.load_fire_image('fire1')
                newbumb.speed = 15
                newbumb.tan = math.tan(math.radians(angle))
                if 90 < angle % 360 < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.08)

    # ==================== 第五阶段：五角星 + 四方弹幕 ====================

    @classmethod
    def phase5_pentagram(cls):
        """第五阶段：创建五角星背景"""
        cls.pentagram_frame = Frame.Frame('终焉之星',
                                         (Event.Game.rx + main.WINDOWWIDTH // 2 - 150,
                                          Event.Game.ry + main.WINDOWHEIGHT // 2 - 150),
                                         (300, 300))
        panel = wx.Panel(cls.pentagram_frame, -1, size=(300, 300))

        # 绘制五角星
        dc = wx.ClientDC(panel)
        dc.SetPen(wx.Pen(wx.Colour(255, 215, 0), 5))
        dc.SetBrush(wx.Brush(wx.Colour(255, 215, 0, 128)))

        # 五角星的5个顶点
        points = []
        for i in range(5):
            angle = math.radians(i * 72 - 90)
            x = 150 + 100 * math.cos(angle)
            y = 150 + 100 * math.sin(angle)
            points.append((int(x), int(y)))

        # 画五角星（连接间隔点）
        for i in range(5):
            next_i = (i + 2) % 5
            dc.DrawLine(points[i][0], points[i][1], points[next_i][0], points[next_i][1])

        cls.pentagram_frame.Show()

        # 确保游戏窗口保持焦点
        hwnd = pygame.display.get_wm_info()['window']
        win32gui.SetForegroundWindow(hwnd)

        # 五角星旋转效果
        threading.Thread(target=cls._rotate_pentagram, daemon=True).start()

    @classmethod
    def _rotate_pentagram(cls):
        """五角星旋转"""
        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 5:
            # 跟随Boss位置
            if cls.pentagram_frame:
                try:
                    cls.pentagram_frame.Move(Event.Game.boss.x - 150, Event.Game.boss.y - 150)
                except:
                    pass
            time.sleep(0.1)

        if cls.pentagram_frame:
            try:
                cls.pentagram_frame.Hide()
            except:
                pass

    @classmethod
    def phase5_four_direction_shot(cls):
        """第五阶段：四方弹幕（随机位置）"""
        shot_count = 0
        base_speed = 8
        base_interval = 0.3

        while Event.Game.haveBoss and Event.Game.boss.bossrint == 6 and cls.get_current_phase() == 5:
            while Event.Game.istimestoptime:
                time.sleep(0.1)

            shot_count += 1
            # 速度和数量随时间增加
            current_speed = min(base_speed + shot_count * 0.1, 20)
            bullets_per_side = min(3 + shot_count // 10, 8)
            current_interval = max(base_interval - shot_count * 0.01, 0.1)

            # 计算玩家位置
            px, py = Event.Game.wateremoji.x, Event.Game.wateremoji.y

            # 四个方向随机位置发射
            directions = [
                ('top', random.randint(100, main.WINDOWWIDTH - 100), 0),  # 从上方随机x
                ('bottom', random.randint(100, main.WINDOWWIDTH - 100), main.WINDOWHEIGHT),  # 从下方随机x
                ('left', 0, random.randint(100, main.WINDOWHEIGHT - 100)),  # 从左侧随机y
                ('right', main.WINDOWWIDTH, random.randint(100, main.WINDOWHEIGHT - 100))  # 从右侧随机y
            ]

            for direction_name, start_x, start_y in directions:
                for i in range(bullets_per_side):
                    # 计算朝向玩家的角度
                    angle_to_player = math.degrees(math.atan2(py - start_y, px - start_x))
                    spread = (i - bullets_per_side / 2) * 10

                    final_angle = angle_to_player + spread

                    newbumb = Bullt.BossBumb(start_x, start_y)

                    # 加载并旋转fire2.png（1.3倍大小）
                    fire2_img = cls.load_fire_image('fire2', scale=1.3)
                    rotated_img = pygame.transform.rotate(fire2_img, -final_angle)
                    newbumb.image = rotated_img

                    newbumb.speed = current_speed
                    newbumb.tan = math.tan(math.radians(final_angle))
                    if -90 < final_angle % 360 < 90:
                        newbumb.sample = 1
                    else:
                        newbumb.sample = -1

                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)

            time.sleep(current_interval)

    @classmethod
    def phase5_boss_speedup(cls):
        """第五阶段：Boss移速加快"""
        if Event.Game.haveBoss and Event.Game.boss.bossrint == 6:
            Event.Game.boss.speed = 8  # 加快速度

    @classmethod
    def phase5_star_burst(cls):
        """第五阶段技能1：星爆攻击"""
        for burst in range(3):
            if not (Event.Game.haveBoss and cls.get_current_phase() == 5):
                break

            # 五角星顶点发射
            for i in range(5):
                angle = i * 72
                for spread in range(-30, 31, 15):
                    final_angle = angle + spread
                    newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)

                    fire2_img = cls.load_fire_image('fire2')
                    rotated_img = pygame.transform.rotate(fire2_img, -final_angle)
                    newbumb.image = rotated_img

                    newbumb.speed = 12
                    newbumb.tan = math.tan(math.radians(final_angle))
                    if 90 < final_angle % 360 < 270:
                        newbumb.sample = 1
                    else:
                        newbumb.sample = -1

                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)

            time.sleep(1.5)

    @classmethod
    def phase5_final_laser_cross(cls):
        """第五阶段技能2：终极十字激光"""
        # X形激光
        angles = [45, 135, 225, 315]

        for angle in angles:
            # 警告线
            length = int(main.WINDOWWIDTH * 1.5)
            warning = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            warning.canMove = False
            warning.hurt = 0
            warning.canDelete = False
            warning.image = pygame.Surface((length, 10), pygame.SRCALPHA)
            warning.image.fill((255, 255, 255, 100))
            rotated = pygame.transform.rotate(warning.image, -angle)
            warning.image = rotated
            warning.rect = warning.image.get_rect()
            warning.rect.center = (Event.Game.boss.x, Event.Game.boss.y)
            Event.Game.allenbumbs.append(warning)

        time.sleep(1.5)

        # 清除警告
        for bumb in Event.Game.allenbumbs[::]:
            if hasattr(bumb, 'hurt') and bumb.hurt == 0:
                try:
                    Event.Game.allenbumbs.remove(bumb)
                except:
                    pass

        # 发射激光
        for angle in angles:
            length = int(main.WINDOWWIDTH * 1.5)
            laser = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            laser.canMove = False
            laser.canDelete = False
            laser.image = pygame.Surface((length, 50), pygame.SRCALPHA)
            laser.image.fill((255, 50, 50, 200))
            rotated = pygame.transform.rotate(laser.image, -angle)
            laser.image = rotated
            laser.rect = laser.image.get_rect()
            laser.rect.center = (Event.Game.boss.x, Event.Game.boss.y)
            Event.Game.allenbumbs.append(laser)
            threading.Thread(target=cls._fade_out_laser, args=(laser, 1.5), daemon=True).start()

    # ==================== 额外技能：为所有阶段增加更多变化 ====================

    @classmethod
    def phase1_fire_pillar(cls):
        """第一阶段新技能：火焰柱"""
        for i in range(6):
            if not (Event.Game.haveBoss and cls.get_current_phase() == 1):
                break

            x_pos = random.randint(100, main.WINDOWWIDTH - 100)

            # 警告
            warning = Bullt.BossBumb(x_pos - 25, 0)
            warning.canMove = False
            warning.hurt = 0
            warning.canDelete = False
            warning.image = pygame.Surface((50, main.WINDOWHEIGHT), pygame.SRCALPHA)
            warning.image.fill((255, 200, 0, 80))
            warning.rect = warning.image.get_rect()
            warning.rect.left = warning.x
            warning.rect.top = warning.y
            Event.Game.allenbumbs.append(warning)

            time.sleep(0.6)

            if warning in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(warning)

            # 火焰柱
            pillar = Bullt.BossBumb(x_pos - 25, 0)
            pillar.canMove = False
            pillar.canDelete = False
            pillar.image = pygame.Surface((50, main.WINDOWHEIGHT))
            pillar.image.fill((255, 100, 0))
            pillar.rect = pillar.image.get_rect()
            pillar.rect.left = pillar.x
            pillar.rect.top = pillar.y
            Event.Game.allenbumbs.append(pillar)

            threading.Thread(target=cls._fade_out_laser, args=(pillar, 1), daemon=True).start()
            time.sleep(0.3)

    @classmethod
    def phase1_laser_web(cls):
        """第一阶段新技能：激光网"""
        # X形激光网
        for offset in [-100, 0, 100]:
            # 对角线激光
            for angle in [45, 135]:
                length = int(main.WINDOWWIDTH * 1.5)
                laser = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y + offset)
                laser.canMove = False
                laser.canDelete = False
                laser.image = pygame.Surface((length, 30), pygame.SRCALPHA)
                laser.image.fill((255, 150, 150, 180))
                rotated = pygame.transform.rotate(laser.image, -angle)
                laser.image = rotated
                laser.rect = laser.image.get_rect()
                laser.rect.center = (Event.Game.boss.x, Event.Game.boss.y + offset)
                Event.Game.allenbumbs.append(laser)
                threading.Thread(target=cls._fade_out_laser, args=(laser, 1.5), daemon=True).start()

            time.sleep(0.5)

    @classmethod
    def phase2_mirror_boss(cls):
        """第二阶段新技能：镜像Boss"""
        # 创建3个假Boss
        fake_positions = [
            (random.randint(main.WINDOWWIDTH // 2, main.WINDOWWIDTH - 100), random.randint(100, main.WINDOWHEIGHT - 100)),
            (random.randint(main.WINDOWWIDTH // 2, main.WINDOWWIDTH - 100), random.randint(100, main.WINDOWHEIGHT - 100)),
            (random.randint(main.WINDOWWIDTH // 2, main.WINDOWWIDTH - 100), random.randint(100, main.WINDOWHEIGHT - 100))
        ]

        fakes = []
        for fx, fy in fake_positions:
            fake = Bullt.BossBumb(fx, fy)
            fake.canMove = False
            fake.hurt = 0
            fake.canDelete = False
            fake.image = Event.Game.boss.image.copy()
            fake.image.set_alpha(150)
            fake.rect = fake.image.get_rect()
            fake.rect.left = fake.x
            fake.rect.top = fake.y
            Event.Game.allenbumbs.append(fake)
            fakes.append(fake)

        # 所有假Boss发射弹幕
        for i in range(10):
            if not (Event.Game.haveBoss and cls.get_current_phase() == 2):
                break

            for fake in fakes[:]:
                if fake not in Event.Game.allenbumbs:
                    continue

                angle = random.uniform(0, 360)
                newbumb = Bullt.BossBumb(fake.x, fake.y)
                newbumb.image = cls.load_fire_image('fire1')
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

            time.sleep(0.3)

        # 移除假Boss
        for fake in fakes:
            if fake in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(fake)

    @classmethod
    def phase2_homing_wave(cls):
        """第二阶段新技能：追踪波"""
        for wave in range(4):
            if not (Event.Game.haveBoss and cls.get_current_phase() == 2):
                break

            # 每波5个追踪弹
            for i in range(5):
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = Event.Game.bulluten[2]
                newbumb.speed = 7 + wave
                newbumb.get = True  # 追踪
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)
                time.sleep(0.15)

            time.sleep(1)

    @classmethod
    def phase3_dimension_rift(cls):
        """第三阶段新技能：次元裂缝"""
        # 创建两个传送门
        portal1_x = random.randint(200, main.WINDOWWIDTH // 2)
        portal1_y = random.randint(200, main.WINDOWHEIGHT - 200)
        portal2_x = random.randint(main.WINDOWWIDTH // 2, main.WINDOWWIDTH - 200)
        portal2_y = random.randint(200, main.WINDOWHEIGHT - 200)

        portals = []
        for px, py in [(portal1_x, portal1_y), (portal2_x, portal2_y)]:
            portal = Bullt.BossBumb(px - 40, py - 40)
            portal.canMove = False
            portal.hurt = 0
            portal.canDelete = False
            portal.size = 80
            portal.image = pygame.Surface((80, 80), pygame.SRCALPHA)
            # 绘制旋涡
            for r in range(40, 0, -5):
                alpha = int(255 * (1 - r / 40))
                color = (150, 50, 255, alpha)
                pygame.draw.circle(portal.image, color, (40, 40), r, 3)
            portal.rect = portal.image.get_rect()
            portal.rect.left = portal.x
            portal.rect.top = portal.y
            portal.portal_target = (portal2_x if px == portal1_x else portal1_x,
                                   portal2_y if px == portal1_x else portal1_y)
            Event.Game.allenbumbs.append(portal)
            portals.append(portal)

        # 从传送门发射子弹
        for i in range(20):
            if not (Event.Game.haveBoss and cls.get_current_phase() == 3):
                break

            for portal in portals:
                angle = random.uniform(0, 360)
                newbumb = Bullt.BossBumb(portal.x + 40, portal.y + 40)
                newbumb.image = Event.Game.bulluten[1]
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

            time.sleep(0.2)

        # 移除传送门
        for portal in portals:
            if portal in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(portal)

    @classmethod
    def phase3_prismatic_beam(cls):
        """第三阶段新技能：棱镜光束"""
        # 从boss发射一道光束，分裂成彩虹色
        for i in range(3):
            if not (Event.Game.haveBoss and cls.get_current_phase() == 3):
                break

            base_angle = math.degrees(math.atan2(
                Event.Game.wateremoji.y - Event.Game.boss.y,
                Event.Game.wateremoji.x - Event.Game.boss.x
            ))

            colors = [
                (255, 0, 0), (255, 127, 0), (255, 255, 0),
                (0, 255, 0), (0, 0, 255), (75, 0, 130), (148, 0, 211)
            ]

            for j, color in enumerate(colors):
                angle = base_angle + (j - 3) * 5
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = pygame.Surface((20, 20))
                newbumb.image.fill(color)
                newbumb.speed = 15
                newbumb.tan = math.tan(math.radians(angle))
                if -90 < angle % 360 < 90:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(1.5)

    @classmethod
    def phase4_vortex_trap(cls):
        """第四阶段新技能：漩涡陷阱"""
        vortex_x = Event.Game.wateremoji.x
        vortex_y = Event.Game.wateremoji.y

        # 创建旋转的子弹墙
        for rotation in range(0, 720, 15):
            if not (Event.Game.haveBoss and cls.get_current_phase() == 4):
                break

            for radius in [100, 150, 200]:
                for arm in range(4):
                    angle = rotation + arm * 90
                    x = vortex_x + radius * math.cos(math.radians(angle))
                    y = vortex_y + radius * math.sin(math.radians(angle))

                    newbumb = Bullt.BossBumb(x, y)
                    newbumb.image = Event.Game.bulluten[5]
                    newbumb.speed = 3
                    # 切线方向（顺时针旋转）
                    newbumb.tan = math.tan(math.radians(angle + 90))
                    if 0 < (angle + 90) % 360 < 180:
                        newbumb.sample = 1
                    else:
                        newbumb.sample = -1
                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.08)

    @classmethod
    def phase4_temporal_split(cls):
        """第四阶段新技能：时间分裂"""
        # 短暂减速时间
        original_fps = Event.Game.FPS
        Event.Game.FPS = 20  # 减速

        time.sleep(0.5)

        # 快速填充屏幕
        for i in range(50):
            x = random.randint(50, main.WINDOWWIDTH - 50)
            y = random.randint(50, main.WINDOWHEIGHT - 50)
            angle = random.uniform(0, 360)

            newbumb = Bullt.BossBumb(x, y)
            newbumb.image = Event.Game.bulluten[random.randint(1, 5)]
            newbumb.speed = random.randint(3, 8)
            newbumb.tan = math.tan(math.radians(angle))
            if 90 < angle < 270:
                newbumb.sample = 1
            else:
                newbumb.sample = -1
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)

        time.sleep(0.5)

        # 恢复时间
        Event.Game.FPS = original_fps

    @classmethod
    def phase5_judgment_ray(cls):
        """第五阶段新技能：审判之光"""
        # 从天而降的巨大光束
        target_x = Event.Game.wateremoji.x

        # 警告
        warning = Bullt.BossBumb(target_x - 100, 0)
        warning.canMove = False
        warning.hurt = 0
        warning.canDelete = False
        warning.image = pygame.Surface((200, main.WINDOWHEIGHT), pygame.SRCALPHA)
        warning.image.fill((255, 255, 255, 100))
        warning.rect = warning.image.get_rect()
        warning.rect.left = warning.x
        warning.rect.top = warning.y
        Event.Game.allenbumbs.append(warning)

        time.sleep(1.5)

        if warning in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(warning)

        # 审判光束
        beam = Bullt.BossBumb(target_x - 100, 0)
        beam.canMove = False
        beam.canDelete = False
        beam.image = pygame.Surface((200, main.WINDOWHEIGHT))
        beam.image.fill((255, 255, 200))
        beam.rect = beam.image.get_rect()
        beam.rect.left = beam.x
        beam.rect.top = beam.y
        Event.Game.allenbumbs.append(beam)

        threading.Thread(target=cls._fade_out_laser, args=(beam, 2), daemon=True).start()

    @classmethod
    def phase5_armageddon(cls):
        """第五阶段新技能：末日天启（终极技能）"""
        # 组合多种攻击
        threads = []

        # 1. 火焰雨
        def fire_rain():
            for i in range(30):
                x = random.randint(0, main.WINDOWWIDTH)
                newbumb = Bullt.BossBumb(x, -50)
                newbumb.image = cls.load_fire_image('fire2', scale=1.5)
                newbumb.direction = 'down'
                newbumb.speed = random.randint(15, 25)
                newbumb.tan = 0
                newbumb.sample = 0
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)
                time.sleep(0.1)

        # 2. 螺旋弹幕
        def spiral():
            for rotation in range(0, 360, 10):
                for arm in range(8):
                    angle = rotation + arm * 45
                    newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                    newbumb.image = cls.load_fire_image('fire1')
                    newbumb.speed = 18
                    newbumb.tan = math.tan(math.radians(angle))
                    if 90 < angle < 270:
                        newbumb.sample = 1
                    else:
                        newbumb.sample = -1
                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)
                time.sleep(0.05)

        # 3. 激光网
        def laser_grid():
            for i in range(5):
                x_pos = i * (main.WINDOWWIDTH // 4)
                laser = Bullt.BossBumb(x_pos, 0)
                laser.canMove = False
                laser.canDelete = False
                laser.image = pygame.Surface((20, main.WINDOWHEIGHT))
                laser.image.fill((255, 50, 50))
                laser.rect = laser.image.get_rect()
                laser.rect.left = laser.x
                laser.rect.top = laser.y
                Event.Game.allenbumbs.append(laser)
                threading.Thread(target=cls._fade_out_laser, args=(laser, 3), daemon=True).start()

        threads.append(threading.Thread(target=fire_rain, daemon=True))
        threads.append(threading.Thread(target=spiral, daemon=True))
        threads.append(threading.Thread(target=laser_grid, daemon=True))

        for t in threads:
            t.start()

        for t in threads:
            t.join()

