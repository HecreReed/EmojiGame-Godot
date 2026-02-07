"""
符卡系统 - 每个Boss死亡后进入符卡阶段
符卡阶段Boss血量回满，使用原技能的加强版，持续到Boss真正死亡
"""
import time, pygame, random, main, Event, threading, Bullt, math
import Skills.BossSkillFirst as BossSkillFirst
import Skills.BossSkillSecond as BossSkillSecond
import Skills.BossSkillThird as BossSkillThird
import Skills.BossSkillForth as BossSkillForth
import Skills.BossSkillFifth as BossSkillFifth
import Skills.BossSkillSixth as BossSkillSixth


class SpellCardSystem:
    """符卡系统管理类"""
    is_spell_card_active = False
    current_spell_card = None
    spell_card_start_time = 0

    @classmethod
    def activate_spell_card(cls, boss_number):
        """激活符卡阶段"""
        if cls.is_spell_card_active:
            return

        cls.is_spell_card_active = True
        cls.spell_card_start_time = time.time()

        # 根据Boss编号启动对应的符卡技能循环
        if boss_number == 1:
            threading.Thread(target=cls._boss1_spell_loop, daemon=True).start()
        elif boss_number == 2:
            threading.Thread(target=cls._boss2_spell_loop, daemon=True).start()
        elif boss_number == 3:
            threading.Thread(target=cls._boss3_spell_loop, daemon=True).start()
        elif boss_number == 4:
            threading.Thread(target=cls._boss4_spell_loop, daemon=True).start()
        elif boss_number == 5:
            threading.Thread(target=cls._boss5_spell_loop, daemon=True).start()
        elif boss_number == 6:
            threading.Thread(target=cls._boss6_spell_loop, daemon=True).start()

    @classmethod
    def deactivate_spell_card(cls):
        """结束符卡阶段"""
        cls.is_spell_card_active = False
        cls.current_spell_card = None

    # ==================== Boss1 符卡循环 ====================

    @classmethod
    def _boss1_spell_loop(cls):
        """Boss1符卡：持续使用加强版技能直到死亡"""
        Event.Game.boss.canShoot = False

        last_skill_time = 0
        skill_index = 0

        # 加强版技能列表
        skills = [
            cls._enhanced_sandShoot,      # 加强版沙尘射击
            cls._enhanced_starShoot,      # 加强版星星射击
            cls._enhanced_mirrorShoot,    # 加强版镜像弹幕
            cls._enhanced_blackHole,      # 加强版黑洞
            cls._enhanced_lightningChain, # 加强版雷电链
            cls._enhanced_spiralTrap,     # 加强版螺旋陷阱
        ]

        while Event.Game.haveBoss and Event.Game.boss_spell_card_activated:
            # 每5-8秒释放一个技能（原版2-4秒，延长间隔）
            if time.time() - last_skill_time >= random.uniform(5, 8):
                threading.Thread(target=skills[skill_index], daemon=True).start()
                skill_index = (skill_index + 1) % len(skills)
                last_skill_time = time.time()

            time.sleep(0.1)

        Event.Game.boss.canShoot = True

    @classmethod
    def _enhanced_sandShoot(cls):
        """加强版沙尘射击：双倍数量 + 子弹会分裂"""
        for i in range(70):  # 原版35，现在70
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            # 同时发射4个子弹（原版2个）
            for offset in [-math.pi/8, -math.pi/12, math.pi/12, math.pi/8]:
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.tan = math.tan(math.atan(newbumb.tan) + offset)
                newbumb.image = Event.Game.bulluten[10]
                newbumb.speed = 15  # 原版10，提速
                if newbumb.tan > 0:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

                # 子弹会分裂
                threading.Thread(target=cls._split_bullet, args=(newbumb,), daemon=True).start()

            time.sleep(0.05)  # 原版0.1，更快

    @classmethod
    def _split_bullet(cls, bullet):
        """子弹分裂"""
        time.sleep(0.8)
        if bullet not in Event.Game.allenbumbs:
            return

        bx, by = bullet.x, bullet.y

        # 分裂成3个
        for angle_offset in [-30, 0, 30]:
            newbumb = Bullt.BossBumb(bx, by)
            newbumb.image = Event.Game.bulluten[10]
            newbumb.speed = 8
            base_angle = math.degrees(math.atan(bullet.tan))
            new_angle = base_angle + angle_offset
            newbumb.tan = math.tan(math.radians(new_angle))
            if 90 < new_angle < 270:
                newbumb.sample = 1
            else:
                newbumb.sample = -1
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)

    @classmethod
    def _enhanced_starShoot(cls):
        """加强版星星射击：三重螺旋 + 更快速度"""
        for wave in range(6):  # 原版3，现在6
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            # 三重螺旋（原版单螺旋）
            for spiral in range(3):
                for angle in range(0, 360, 10):  # 原版15度，现在10度更密集
                    angle_with_spiral = angle + spiral * 120 + wave * 30
                    newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                    newbumb.image = Event.Game.bulluten[0]
                    newbumb.speed = 18  # 原版12，提速
                    newbumb.tan = math.tan(math.radians(angle_with_spiral))
                    if 90 < angle_with_spiral < 270:
                        newbumb.sample = 1
                    else:
                        newbumb.sample = -1
                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.4)  # 原版0.6，更快

    @classmethod
    def _enhanced_mirrorShoot(cls):
        """加强版镜像射击：四重对称 + 追踪弹"""
        for wave in range(6):  # 原版3，现在6
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            # 四重对称（原版两重）
            for angle in range(0, 360, 10):  # 原版15度，更密集
                for mirror in [0, 90, 180, 270]:  # 四方向对称
                    final_angle = angle + mirror
                    newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                    newbumb.image = Event.Game.bulluten[1]
                    newbumb.speed = 14  # 原版10，提速
                    newbumb.tan = math.tan(math.radians(final_angle))
                    if 90 < final_angle < 270:
                        newbumb.sample = 1
                    else:
                        newbumb.sample = -1
                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)

            # 加入追踪弹
            for i in range(3):
                tracking = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                tracking.image = Event.Game.bulluten[2]
                tracking.speed = 8
                tracking.get = True  # 追踪
                tracking.rect = tracking.image.get_rect()
                tracking.rect.left = tracking.x
                tracking.rect.top = tracking.y
                Event.Game.allenbumbs.append(tracking)

            time.sleep(0.5)  # 原版0.8，更快

    @classmethod
    def _enhanced_blackHole(cls):
        """加强版黑洞：吸力翻倍 + 更多弹幕"""
        duration = 8  # 原版6秒，延长
        start = time.time()

        while time.time() - start < duration and Event.Game.haveBoss and Event.Game.boss_spell_card_activated:
            # 吸引玩家（吸力翻倍）
            dx = Event.Game.boss.x - Event.Game.wateremoji.x
            dy = Event.Game.boss.y - Event.Game.wateremoji.y
            distance = math.sqrt(dx**2 + dy**2)
            if distance > 10:
                pull_strength = min(600 / distance, 6)  # 原版300/distance, 3，翻倍
                Event.Game.wateremoji.x += dx / distance * pull_strength
                Event.Game.wateremoji.y += dy / distance * pull_strength

            # 发射更多环形弹幕
            for angle in range(0, 360, 12):  # 原版18度，更密集
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = Event.Game.bulluten[5]
                newbumb.speed = 12  # 原版10，提速
                newbumb.tan = math.tan(math.radians(angle))
                if 90 < angle < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.15)  # 原版0.2，更快

    @classmethod
    def _enhanced_lightningChain(cls):
        """加强版雷电链：闪电数量翻倍 + 闪电会连锁"""
        for i in range(16):  # 原版8，翻倍
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            # 随机位置闪电
            x = random.randint(100, main.WINDOWWIDTH - 100)

            # 创建闪电警告
            warning = Bullt.BossBumb(x - 25, 0)
            warning.canMove = False
            warning.hurt = 0
            warning.canDelete = False
            warning.image = pygame.Surface((50, main.WINDOWHEIGHT))
            warning.image.fill((255, 255, 0))
            warning.rect = warning.image.get_rect()
            warning.rect.left = warning.x
            warning.rect.top = warning.y
            Event.Game.allenbumbs.append(warning)

            # 0.3秒后闪电
            def create_lightning(warn_x):
                time.sleep(0.3)

                lightning = Bullt.BossBumb(warn_x - 25, 0)
                lightning.canMove = False
                lightning.canDelete = False
                lightning.image = pygame.Surface((50, main.WINDOWHEIGHT))
                lightning.image.fill((255, 255, 255))
                lightning.rect = lightning.image.get_rect()
                lightning.rect.left = lightning.x
                lightning.rect.top = lightning.y
                Event.Game.allenbumbs.append(lightning)

                # 连锁闪电（左右各一道）
                time.sleep(0.2)
                for offset in [-150, 150]:
                    chain_x = warn_x + offset
                    if 100 < chain_x < main.WINDOWWIDTH - 100:
                        chain = Bullt.BossBumb(chain_x - 25, 0)
                        chain.canMove = False
                        chain.canDelete = False
                        chain.image = pygame.Surface((50, main.WINDOWHEIGHT))
                        chain.image.fill((200, 200, 255))
                        chain.rect = chain.image.get_rect()
                        chain.rect.left = chain.x
                        chain.rect.top = chain.y
                        Event.Game.allenbumbs.append(chain)

                        threading.Thread(target=cls._fade_lightning, args=(chain,), daemon=True).start()

                threading.Thread(target=cls._fade_lightning, args=(lightning,), daemon=True).start()

                if warning in Event.Game.allenbumbs:
                    Event.Game.allenbumbs.remove(warning)

            threading.Thread(target=create_lightning, args=(x,), daemon=True).start()
            time.sleep(0.25)  # 原版0.4，更快

    @classmethod
    def _fade_lightning(cls, lightning):
        """闪电淡出"""
        time.sleep(0.4)
        if lightning in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(lightning)

    @classmethod
    def _enhanced_spiralTrap(cls):
        """加强版螺旋陷阱：双层螺旋 + 向内收缩"""
        center_x = Event.Game.wateremoji.x
        center_y = Event.Game.wateremoji.y

        # 双层螺旋（原版单层）
        for layer in range(2):
            for radius in range(400, 50, -25):  # 原版300到50
                if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                    break

                # 5个螺旋臂（原版3个）
                for arm in range(5):
                    base_angle = arm * 72 + (400 - radius) * 3 + layer * 36

                    # 每个臂多个子弹
                    for offset in range(0, 360, 20):  # 原版30度，更密集
                        angle = base_angle + offset
                        x = center_x + radius * math.cos(math.radians(angle))
                        y = center_y + radius * math.sin(math.radians(angle))

                        newbumb = Bullt.BossBumb(x, y)
                        # 向中心射击
                        newbumb.tan = math.tan(math.radians(angle + 180))
                        newbumb.speed = 6  # 原版5，提速
                        newbumb.image = Event.Game.bulluten[1]
                        if 90 < (angle + 180) % 360 < 270:
                            newbumb.sample = 1
                        else:
                            newbumb.sample = -1
                        newbumb.rect = newbumb.image.get_rect()
                        newbumb.rect.left = newbumb.x
                        newbumb.rect.top = newbumb.y
                        Event.Game.allenbumbs.append(newbumb)

                time.sleep(0.15)  # 原版0.3，更快

    # ==================== Boss2-6 符卡循环 ====================

    @classmethod
    def _boss2_spell_loop(cls):
        """Boss2符卡：爱心弹幕加强版"""
        Event.Game.boss.canShoot = False
        last_skill_time = 0

        while Event.Game.haveBoss and Event.Game.boss_spell_card_activated:
            if time.time() - last_skill_time >= random.uniform(4, 7):  # 原版2-3秒，延长间隔
                skill = random.choice([
                    cls._enhanced_heartRain,
                    cls._enhanced_reverseTime,
                    cls._enhanced_heartTrap,
                    cls._enhanced_splitBomb
                ])
                threading.Thread(target=skill, daemon=True).start()
                last_skill_time = time.time()
            time.sleep(0.1)

        Event.Game.boss.canShoot = True

    @classmethod
    def _enhanced_heartRain(cls):
        """加强版心形雨：数量翻倍 + 反弹"""
        for i in range(40):  # 原版20，翻倍
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            x = random.randint(0, main.WINDOWWIDTH)
            newbumb = Bullt.BossBumb(x, -30)
            newbumb.image = Event.Game.bulluten[3]
            newbumb.speed = random.randint(15, 25)  # 提速
            newbumb.direction = 'down'
            newbumb.tan = 0
            newbumb.sample = 0
            newbumb.banRemove = True  # 会反弹，不会移除
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)
            time.sleep(0.05)

    @classmethod
    def _enhanced_reverseTime(cls):
        """加强版时间倒流：持续时间翻倍"""
        duration = 6  # 原版3秒，翻倍
        start = time.time()

        while time.time() - start < duration and Event.Game.haveBoss and Event.Game.boss_spell_card_activated:
            # 反转所有子弹
            for bullet in Event.Game.allenbumbs[::]:
                if hasattr(bullet, 'tan') and bullet.canMove:
                    bullet.tan = -bullet.tan
                    bullet.sample = -bullet.sample
            time.sleep(1)  # 每秒反转一次

    @classmethod
    def _enhanced_heartTrap(cls):
        """加强版爱心陷阱：更多层 + 会旋转"""
        # 5层陷阱（原版3层）
        for radius in [80, 120, 160, 200, 240]:
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            for angle in range(0, 360, 15):  # 原版20度，更密集
                x = Event.Game.wateremoji.x + radius * math.cos(math.radians(angle))
                y = Event.Game.wateremoji.y + radius * math.sin(math.radians(angle))

                if 0 < x < main.WINDOWWIDTH and 0 < y < main.WINDOWHEIGHT:
                    newbumb = Bullt.BossBumb(x, y)
                    newbumb.image = Event.Game.bulluten[3]
                    newbumb.canMove = False
                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)

                    # 0.8秒后开始旋转移动
                    threading.Thread(target=cls._rotate_heart, args=(newbumb, x, y, radius), daemon=True).start()

            time.sleep(0.3)

    @classmethod
    def _rotate_heart(cls, heart, cx, cy, radius):
        """爱心旋转移动"""
        time.sleep(0.8)
        if heart not in Event.Game.allenbumbs:
            return

        heart.canMove = True
        # 切线方向旋转
        angle = math.degrees(math.atan2(heart.y - cy, heart.x - cx))
        heart.tan = math.tan(math.radians(angle + 90))
        heart.speed = 8
        if 0 < (angle + 90) % 360 < 180:
            heart.sample = 1
        else:
            heart.sample = -1

    @classmethod
    def _enhanced_splitBomb(cls):
        """加强版分裂炸弹：分裂成16个 + 二次分裂"""
        for i in range(6):  # 原版4，增加
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            main_bomb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            main_bomb.image = Event.Game.bulluten[3]
            main_bomb.speed = 10
            main_bomb.get = True
            main_bomb.rect = main_bomb.image.get_rect()
            main_bomb.rect.left = main_bomb.x
            main_bomb.rect.top = main_bomb.y
            Event.Game.allenbumbs.append(main_bomb)

            threading.Thread(target=cls._split_heart_bomb, args=(main_bomb,), daemon=True).start()
            time.sleep(0.8)

    @classmethod
    def _split_heart_bomb(cls, bomb):
        """分裂爱心炸弹"""
        time.sleep(1)
        if bomb not in Event.Game.allenbumbs:
            return

        bx, by = bomb.x, bomb.y
        Event.Game.allenbumbs.remove(bomb)

        # 分裂成16个（原版8个）
        for i in range(16):
            angle = i * 22.5  # 360/16 = 22.5度间隔
            newbumb = Bullt.BossBumb(bx, by)
            newbumb.image = Event.Game.bulluten[3]
            newbumb.speed = 16
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
    def _boss3_spell_loop(cls):
        """Boss3符卡：时间与黄金加强版"""
        Event.Game.boss.canShoot = False
        last_skill_time = 0
        time_stop_interval = 0

        while Event.Game.haveBoss and Event.Game.boss_spell_card_activated:
            # 周期性时间停止（原版技能的增强）
            if time.time() - time_stop_interval >= 8:  # 每8秒停一次
                Event.Game.istimestoptime = True
                time.sleep(4)  # 停4秒（原版3秒，延长）
                Event.Game.istimestoptime = False
                time_stop_interval = time.time()

            if time.time() - last_skill_time >= random.uniform(4, 6):  # 原版1.5-2.5秒，大幅延长间隔
                skill = random.choice([
                    cls._enhanced_goldenStorm,
                    cls._enhanced_timeBubble,
                    cls._enhanced_coinBarrage
                ])
                threading.Thread(target=skill, daemon=True).start()
                last_skill_time = time.time()
            time.sleep(0.1)

        Event.Game.istimestoptime = False
        Event.Game.boss.canShoot = True

    @classmethod
    def _enhanced_goldenStorm(cls):
        """加强版黄金风暴：8方向 + 旋转"""
        for rotation in range(36):  # 旋转更多圈
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            # 8方向（原版4方向）
            for direction in range(8):
                angle = direction * 45 + rotation * 10
                newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
                newbumb.image = Event.Game.bulluten[8]
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

            time.sleep(0.08)

    @classmethod
    def _enhanced_timeBubble(cls):
        """加强版时间气泡：减速加倍"""
        for i in range(5):
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            bubble_x = random.randint(200, main.WINDOWWIDTH - 200)
            bubble_y = random.randint(200, main.WINDOWHEIGHT - 200)

            bubble = Bullt.BossBumb(bubble_x - 60, bubble_y - 60)
            bubble.canMove = False
            bubble.hurt = 0
            bubble.canDelete = False
            bubble.size = 120
            bubble.image = pygame.Surface((120, 120), pygame.SRCALPHA)
            for r in range(60, 0, -5):
                alpha = int(200 * (1 - r / 60))
                pygame.draw.circle(bubble.image, (255, 215, 0, alpha), (60, 60), r, 3)
            bubble.rect = bubble.image.get_rect()
            bubble.rect.left = bubble.x
            bubble.rect.top = bubble.y
            Event.Game.allenbumbs.append(bubble)

            threading.Thread(target=cls._bubble_effect, args=(bubble, bubble_x, bubble_y), daemon=True).start()
            time.sleep(0.5)

    @classmethod
    def _bubble_effect(cls, bubble, bx, by):
        """气泡减速效果"""
        duration = 5
        start = time.time()
        was_slowed = False  # 跟踪当前气泡是否正在减速玩家

        while time.time() - start < duration and bubble in Event.Game.allenbumbs:
            dx = bx - Event.Game.wateremoji.x
            dy = by - Event.Game.wateremoji.y
            distance = math.sqrt(dx**2 + dy**2)
            player_in_bubble = distance < 60

            if player_in_bubble and not was_slowed:
                # 玩家刚进入，施加减速
                Event.Game.wateremoji.slowdown_effects += 1
                Event.Game.wateremoji.normal_speed = 1
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
    def _enhanced_coinBarrage(cls):
        """加强版金币弹幕：更密集的墙"""
        for wave in range(5):
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            # 垂直金币墙
            for y in range(0, main.WINDOWHEIGHT, 30):  # 原版40，更密集
                coin = Bullt.BossBumb(-30, y)
                coin.image = Event.Game.bulluten[8]
                coin.direction = 'right'
                coin.speed = 18
                coin.tan = 0
                coin.sample = 0
                coin.rect = coin.image.get_rect()
                coin.rect.left = coin.x
                coin.rect.top = coin.y
                Event.Game.allenbumbs.append(coin)

            time.sleep(1)

    @classmethod
    def _boss4_spell_loop(cls):
        """Boss4符卡：UFO舰队加强版"""
        Event.Game.boss.canShoot = False
        last_skill_time = 0

        while Event.Game.haveBoss and Event.Game.boss_spell_card_activated:
            if time.time() - last_skill_time >= random.uniform(4, 7):  # 原版2-3秒，延长间隔
                skill = random.choice([
                    cls._enhanced_screenStatic,
                    cls._enhanced_orbitalStrike,
                    cls._enhanced_pixelStorm
                ])
                threading.Thread(target=skill, daemon=True).start()
                last_skill_time = time.time()
            time.sleep(0.1)

        Event.Game.boss.canShoot = True

    @classmethod
    def _enhanced_screenStatic(cls):
        """加强版屏幕干扰：更多干扰 + 持续时间加倍"""
        for i in range(6):  # 原版3，翻倍
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            screen_x = random.randint(150, main.WINDOWWIDTH - 300)
            screen_y = random.randint(100, main.WINDOWHEIGHT - 250)

            static = Bullt.BossBumb(screen_x, screen_y)
            static.canMove = False
            static.hurt = 8  # 原版5，增加伤害
            static.canDelete = False
            static.size = 180  # 原版150，更大

            # 预生成4个不同的静态图像用于轮换（性能优化）
            static.images = []
            for _ in range(4):
                img = pygame.Surface((180, 180))
                for x in range(0, 180, 3):
                    for y in range(0, 180, 3):
                        color = random.choice([
                            (255, 255, 255), (200, 200, 200), (150, 150, 150),
                            (100, 100, 255), (255, 100, 100), (100, 255, 100)
                        ])
                        pygame.draw.rect(img, color, (x, y, 3, 3))
                static.images.append(img)

            static.image = static.images[0]
            static.image_index = 0
            static.rect = static.image.get_rect()
            static.rect.left = static.x
            static.rect.top = static.y
            Event.Game.allenbumbs.append(static)

            threading.Thread(target=cls._static_effect, args=(static, screen_x, screen_y, 8), daemon=True).start()
            time.sleep(1)

    @classmethod
    def _static_effect(cls, screen, sx, sy, duration):
        """干扰效果"""
        start = time.time()
        was_slowed = False  # 跟踪当前色块是否正在减速玩家

        while time.time() - start < duration and screen in Event.Game.allenbumbs:
            # 轮换预生成的图像而不是每帧重绘（性能优化）
            if hasattr(screen, 'images'):
                screen.image_index = (screen.image_index + 1) % len(screen.images)
                screen.image = screen.images[screen.image_index]

            player_in_area = (sx <= Event.Game.wateremoji.x <= sx + 180 and
                             sy <= Event.Game.wateremoji.y <= sy + 180)

            if player_in_area and not was_slowed:
                # 玩家刚进入，施加减速
                Event.Game.wateremoji.slowdown_effects += 1
                Event.Game.wateremoji.normal_speed = 2
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
    def _enhanced_orbitalStrike(cls):
        """加强版轨道打击：UFO数量翻倍 + 发射更快"""
        ufos = []
        # 8个UFO（原版4个）
        for i in range(8):
            angle = i * 45
            radius = 400
            x = main.WINDOWWIDTH // 2 + radius * math.cos(math.radians(angle))
            y = main.WINDOWHEIGHT // 2 + radius * math.sin(math.radians(angle))

            ufo = Bullt.BossBumb(x, y)
            ufo.canMove = False
            ufo.hurt = 12  # 原版10，增加
            ufo.canDelete = False
            ufo.image = pygame.image.load('image/alien.png')
            ufo.rect = ufo.image.get_rect()
            ufo.rect.left = ufo.x
            ufo.rect.top = ufo.y
            Event.Game.allenbumbs.append(ufo)
            ufos.append(ufo)

        threading.Thread(target=cls._orbital_shoot, args=(ufos,), daemon=True).start()

    @classmethod
    def _orbital_shoot(cls, ufos):
        """轨道射击"""
        for i in range(40):  # 原版30，增加
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            for ufo in ufos[:]:
                if ufo not in Event.Game.allenbumbs:
                    continue

                angle = math.degrees(math.atan2(
                    Event.Game.wateremoji.y - ufo.y,
                    Event.Game.wateremoji.x - ufo.x
                ))

                newbumb = Bullt.BossBumb(ufo.x, ufo.y)
                newbumb.image = Event.Game.bulluten[10]
                newbumb.speed = 14  # 原版10，提速
                newbumb.tan = math.tan(math.radians(angle))
                if 90 < angle < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.15)  # 原版0.25，更快

        for ufo in ufos:
            if ufo in Event.Game.allenbumbs:
                Event.Game.allenbumbs.remove(ufo)

    @classmethod
    def _enhanced_pixelStorm(cls):
        """加强版像素风暴：所有模式同时出现"""
        if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
            return

        center_x = Event.Game.wateremoji.x
        center_y = Event.Game.wateremoji.y

        # 同时创建三种模式的像素
        patterns = [
            # 十字形
            [(center_x + dx * 40, center_y) for dx in range(-5, 6)] +
            [(center_x, center_y + dy * 40) for dy in range(-5, 6)],
            # 方形网格
            [(center_x + dx * 50, center_y + dy * 50)
             for dx in range(-4, 5) for dy in range(-4, 5)],
            # 对角线
            [(center_x + d * 40, center_y + d * 40) for d in range(-6, 7)] +
            [(center_x + d * 40, center_y - d * 40) for d in range(-6, 7)]
        ]

        pixels = []
        for pattern in patterns:
            for x, y in pattern:
                if 0 <= x < main.WINDOWWIDTH and 0 <= y < main.WINDOWHEIGHT:
                    pixel = Bullt.BossBumb(x, y)
                    pixel.canMove = False
                    pixel.canDelete = False
                    pixel.size = 20  # 原版15，更大
                    pixel.image = pygame.Surface((20, 20))
                    pixel.image.fill(random.choice([
                        (255, 100, 100), (100, 255, 100), (100, 100, 255),
                        (255, 255, 100), (255, 100, 255), (100, 255, 255)
                    ]))
                    pixel.rect = pixel.image.get_rect()
                    pixel.rect.left = pixel.x
                    pixel.rect.top = pixel.y
                    Event.Game.allenbumbs.append(pixel)
                    pixels.append(pixel)

        time.sleep(1)

        # 所有像素向外射出
        for pixel in pixels:
            if pixel not in Event.Game.allenbumbs:
                continue

            dx = pixel.x - center_x
            dy = pixel.y - center_y
            distance = math.sqrt(dx**2 + dy**2)

            if distance > 5:
                angle = math.degrees(math.atan2(dy, dx))
                pixel.canMove = True
                pixel.speed = 15  # 原版12，提速
                pixel.tan = math.tan(math.radians(angle))
                if -90 < angle % 360 < 90:
                    pixel.sample = 1
                else:
                    pixel.sample = -1

    @classmethod
    def _boss5_spell_loop(cls):
        """Boss5符卡：TNT加强版"""
        Event.Game.boss.canShoot = False
        last_skill_time = 0

        while Event.Game.haveBoss and Event.Game.boss_spell_card_activated:
            if time.time() - last_skill_time >= random.uniform(4, 6):  # 原版1.5-2.5秒，大幅延长间隔
                skill = random.choice([
                    cls._enhanced_chainExplosion,
                    cls._enhanced_gravitySink,
                    cls._enhanced_mirrorTNT
                ])
                threading.Thread(target=skill, daemon=True).start()
                last_skill_time = time.time()
            time.sleep(0.1)

        Event.Game.boss.canShoot = True

    @classmethod
    def _enhanced_chainExplosion(cls):
        """加强版连锁爆炸：爆炸次数翻倍 + 更大范围"""
        explosions = []
        start_x, start_y = Event.Game.boss.x, Event.Game.boss.y

        for i in range(16):  # 原版8，翻倍
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            if i == 0:
                ex, ey = start_x, start_y
            else:
                px, py = Event.Game.wateremoji.x, Event.Game.wateremoji.y
                prev_x, prev_y = explosions[-1]
                dx = px - prev_x
                dy = py - prev_y
                distance = math.sqrt(dx**2 + dy**2)
                if distance > 0:
                    ex = prev_x + (dx / distance) * 100  # 原版120，更快追踪
                    ey = prev_y + (dy / distance) * 100
                else:
                    ex = prev_x + random.randint(-100, 100)
                    ey = prev_y + random.randint(-100, 100)

            explosions.append((ex, ey))

            # 爆炸
            explosion = Bullt.BossBumb(ex - 60, ey - 60)
            explosion.canMove = False
            explosion.canDelete = False
            explosion.hurt = 15  # 原版12，增加
            explosion.image = Event.Game.bulluten[13]
            explosion.size = 120  # 原版100，更大
            explosion.image = pygame.transform.smoothscale(explosion.image, (120, 120))
            explosion.rect = explosion.image.get_rect()
            explosion.rect.left = explosion.x
            explosion.rect.top = explosion.y
            Event.Game.allenbumbs.append(explosion)

            threading.Thread(target=cls._explosion_fade, args=(explosion,), daemon=True).start()

            # 更多方向的弹幕
            for angle in range(0, 360, 30):  # 原版45度，更密集
                newbumb = Bullt.BossBumb(ex, ey)
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

            time.sleep(0.2)

    @classmethod
    def _explosion_fade(cls, explosion):
        """爆炸淡出"""
        time.sleep(0.5)
        if explosion in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(explosion)

    @classmethod
    def _enhanced_gravitySink(cls):
        """加强版重力陷阱：吸力翻倍 + 更多弹幕"""
        sink_x = random.randint(300, main.WINDOWWIDTH - 300)
        sink_y = random.randint(250, main.WINDOWHEIGHT - 250)

        sink = Bullt.BossBumb(sink_x - 80, sink_y - 80)
        sink.canMove = False
        sink.hurt = 0
        sink.canDelete = False
        sink.size = 160  # 原版120，更大
        sink.image = pygame.Surface((160, 160), pygame.SRCALPHA)
        for r in range(80, 0, -5):
            alpha = int(255 * (1 - r / 80))
            color = (100, 50, 200, alpha)
            pygame.draw.circle(sink.image, color, (80, 80), r)
        sink.rect = sink.image.get_rect()
        sink.rect.left = sink.x
        sink.rect.top = sink.y
        Event.Game.allenbumbs.append(sink)

        duration = 7  # 原版5秒，延长
        start = time.time()

        while time.time() - start < duration and sink in Event.Game.allenbumbs:
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            dx = sink_x - Event.Game.wateremoji.x
            dy = sink_y - Event.Game.wateremoji.y
            distance = math.sqrt(dx**2 + dy**2)
            if distance > 10:
                pull_strength = min(500 / distance, 5)  # 原版250/distance, 2.5，翻倍
                Event.Game.wateremoji.x += dx / distance * pull_strength
                Event.Game.wateremoji.y += dy / distance * pull_strength

            # 更多弹幕
            if random.random() < 0.7:  # 原版0.4，更频繁
                angle = random.randint(0, 359)
                newbumb = Bullt.BossBumb(sink_x, sink_y)
                newbumb.image = Event.Game.bulluten[5]
                newbumb.speed = 12  # 原版10，提速
                newbumb.tan = math.tan(math.radians(angle))
                if 90 < angle < 270:
                    newbumb.sample = 1
                else:
                    newbumb.sample = -1
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left = newbumb.x
                newbumb.rect.top = newbumb.y
                Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.1)

        if sink in Event.Game.allenbumbs:
            Event.Game.allenbumbs.remove(sink)

    @classmethod
    def _enhanced_mirrorTNT(cls):
        """加强版镜像TNT：镜像数量翻倍"""
        for i in range(6):  # 原版4，增加
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            main_tnt = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            main_tnt.image = Event.Game.bulluten[12]
            main_tnt.speed = 10
            main_tnt.get = True
            main_tnt.rect = main_tnt.image.get_rect()
            main_tnt.rect.left = main_tnt.x
            main_tnt.rect.top = main_tnt.y
            Event.Game.allenbumbs.append(main_tnt)

            threading.Thread(target=cls._mirror_tnt_explode, args=(main_tnt,), daemon=True).start()
            time.sleep(1)

    @classmethod
    def _mirror_tnt_explode(cls, main_tnt):
        """镜像TNT爆炸"""
        time.sleep(1)
        if main_tnt not in Event.Game.allenbumbs:
            return

        center_x, center_y = main_tnt.x, main_tnt.y

        # 8个镜像TNT（原版4个）
        mirror_offsets = [
            (0, -100), (0, 100), (-100, 0), (100, 0),
            (-70, -70), (70, -70), (-70, 70), (70, 70)
        ]

        mirrors = []
        for dx, dy in mirror_offsets:
            mirror = Bullt.BossBumb(center_x + dx, center_y + dy)
            mirror.image = Event.Game.bulluten[14]
            mirror.canMove = False
            mirror.canDelete = False
            mirror.rect = mirror.image.get_rect()
            mirror.rect.left = mirror.x
            mirror.rect.top = mirror.y
            Event.Game.allenbumbs.append(mirror)
            mirrors.append(mirror)

        main_tnt.image = Event.Game.bulluten[14]
        time.sleep(0.6)

        all_tnts = mirrors + [main_tnt]
        for tnt in all_tnts:
            if tnt not in Event.Game.allenbumbs:
                continue

            explosion = Bullt.BossBumb(tnt.x - 40, tnt.y - 40)
            explosion.canMove = False
            explosion.canDelete = False
            explosion.hurt = 12  # 原版10，增加
            explosion.image = Event.Game.bulluten[13]
            explosion.size = 80
            explosion.image = pygame.transform.smoothscale(explosion.image, (80, 80))
            explosion.rect = explosion.image.get_rect()
            explosion.rect.left = explosion.x
            explosion.rect.top = explosion.y
            Event.Game.allenbumbs.append(explosion)

            try:
                Event.Game.allenbumbs.remove(tnt)
            except ValueError:
                pass

            threading.Thread(target=cls._explosion_fade, args=(explosion,), daemon=True).start()

            # 更多弹幕
            for angle in range(0, 360, 20):  # 原版30度，更密集
                newbumb = Bullt.BossBumb(tnt.x, tnt.y)
                newbumb.image = Event.Game.bulluten[5]
                newbumb.speed = 14  # 原版12，提速
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
    def _boss6_spell_loop(cls):
        """Boss6符卡：五重终焉 - 所有阶段技能的加强版循环"""
        Event.Game.boss.canShoot = False
        skill_index = 0
        last_skill_time = 0

        # Boss6特殊：同时循环使用所有5个阶段的加强版技能
        skills = [
            cls._enhanced_phase1_skills,
            cls._enhanced_phase2_skills,
            cls._enhanced_phase3_skills,
            cls._enhanced_phase4_skills,
            cls._enhanced_phase5_skills
        ]

        while Event.Game.haveBoss and Event.Game.boss_spell_card_activated:
            if time.time() - last_skill_time >= random.uniform(6, 9):  # 原版3-5秒，延长间隔
                threading.Thread(target=skills[skill_index], daemon=True).start()
                skill_index = (skill_index + 1) % len(skills)
                last_skill_time = time.time()
            time.sleep(0.1)

        Event.Game.boss.canShoot = True

    @classmethod
    def _enhanced_phase1_skills(cls):
        """加强版第一阶段技能"""
        # 火焰雨翻倍
        for i in range(20):  # 原版10
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            x = random.randint(0, main.WINDOWWIDTH)
            fire = Bullt.BossBumb(x, -30)
            fire.image = BossSkillSixth.BossSkillSixth.load_fire_image('fire1')
            fire.speed = random.randint(20, 30)  # 提速
            fire.direction = 'down'
            fire.tan = 0
            fire.sample = 0
            fire.rect = fire.image.get_rect()
            fire.rect.left = fire.x
            fire.rect.top = fire.y
            Event.Game.allenbumbs.append(fire)
            time.sleep(0.1)

    @classmethod
    def _enhanced_phase2_skills(cls):
        """加强版第二阶段技能"""
        # 锥形弹幕更密集
        for angle in range(-60, 61, 3):  # 原版-45到45，范围更大，更密集
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            newbumb = Bullt.BossBumb(Event.Game.boss.x, Event.Game.boss.y)
            newbumb.image = BossSkillSixth.BossSkillSixth.load_fire_image('fire1')
            newbumb.speed = 18  # 原版15，提速
            target_angle = math.degrees(math.atan2(
                Event.Game.wateremoji.y - Event.Game.boss.y,
                Event.Game.wateremoji.x - Event.Game.boss.x
            )) + angle
            newbumb.tan = math.tan(math.radians(target_angle))
            if 90 < target_angle < 270:
                newbumb.sample = 1
            else:
                newbumb.sample = -1
            newbumb.rect = newbumb.image.get_rect()
            newbumb.rect.left = newbumb.x
            newbumb.rect.top = newbumb.y
            Event.Game.allenbumbs.append(newbumb)

    @classmethod
    def _enhanced_phase3_skills(cls):
        """加强版第三阶段技能"""
        # 多层圆圈陷阱
        for radius in [80, 120, 160, 200, 240]:  # 原版3层，现在5层
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            for angle in range(0, 360, 10):  # 原版15度，更密集
                x = Event.Game.wateremoji.x + radius * math.cos(math.radians(angle))
                y = Event.Game.wateremoji.y + radius * math.sin(math.radians(angle))

                if 0 < x < main.WINDOWWIDTH and 0 < y < main.WINDOWHEIGHT:
                    newbumb = Bullt.BossBumb(x, y)
                    newbumb.image = Event.Game.bulluten[1]
                    newbumb.speed = 10
                    newbumb.tan = math.tan(math.radians(angle + 180))
                    if 90 < (angle + 180) % 360 < 270:
                        newbumb.sample = 1
                    else:
                        newbumb.sample = -1
                    newbumb.rect = newbumb.image.get_rect()
                    newbumb.rect.left = newbumb.x
                    newbumb.rect.top = newbumb.y
                    Event.Game.allenbumbs.append(newbumb)

            time.sleep(0.2)

    @classmethod
    def _enhanced_phase4_skills(cls):
        """加强版第四阶段技能"""
        # 全屏混沌弹幕加倍
        for i in range(100):  # 原版50，翻倍
            if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                break

            x = random.randint(0, main.WINDOWWIDTH)
            y = random.randint(0, main.WINDOWHEIGHT)
            angle = random.uniform(0, 360)

            newbumb = Bullt.BossBumb(x, y)
            newbumb.image = BossSkillSixth.BossSkillSixth.load_fire_image('fire2', scale=1.3)
            newbumb.speed = random.randint(8, 20)  # 原版5-15，提速
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
    def _enhanced_phase5_skills(cls):
        """加强版第五阶段技能"""
        # 四方fire2.png更密集更快
        for direction in ['left', 'right', 'top', 'bottom']:
            for i in range(10):  # 原版5，翻倍
                if not (Event.Game.haveBoss and Event.Game.boss_spell_card_activated):
                    break

                if direction == 'left':
                    x = random.randint(-30, 50)
                    y = random.randint(0, main.WINDOWHEIGHT)
                    angle = 0
                elif direction == 'right':
                    x = random.randint(main.WINDOWWIDTH - 50, main.WINDOWWIDTH + 30)
                    y = random.randint(0, main.WINDOWHEIGHT)
                    angle = 180
                elif direction == 'top':
                    x = random.randint(0, main.WINDOWWIDTH)
                    y = random.randint(-30, 50)
                    angle = 90
                else:
                    x = random.randint(0, main.WINDOWWIDTH)
                    y = random.randint(main.WINDOWHEIGHT - 50, main.WINDOWHEIGHT + 30)
                    angle = 270

                newbumb = Bullt.BossBumb(x, y)
                newbumb.image = BossSkillSixth.BossSkillSixth.load_fire_image('fire2', scale=1.3)
                newbumb.speed = 22  # 原版18，提速
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
