import pygame, Bullt, OEmoji, sys, time, random, main, AllSupply, Skill, Move, threading
from Skills.SpellCards import SpellCardSystem
from StageSystem import StageSystem, StagePhase
# 导入新敌人类型系统
try:
    from EmojiAll.NewEnemyTypes import FastEnemy, TankEnemy, SuicideEnemy, SniperEnemy, ShieldEnemy, SplitEnemy, EliteEnemy, MiniBoss
    NEW_ENEMIES_AVAILABLE = True
except ImportError:
    NEW_ENEMIES_AVAILABLE = False
# 导入武器系统
try:
    from WeaponSystem import WeaponSystem
    WEAPON_SYSTEM_AVAILABLE = True
except ImportError:
    WEAPON_SYSTEM_AVAILABLE = False
# 导入游戏系统（连击、分数）
try:
    from GameSystems import ComboSystem, ScoreSystem
    GAME_SYSTEMS_AVAILABLE = True
except ImportError:
    GAME_SYSTEMS_AVAILABLE = False


class Game:
    wateremoji = object
    g_enemies = []
    score = 0
    latesttime = 0
    allenbumbs = []
    allsupply = []
    haveBoss = False
    allprevent = []
    Aleph = object
    Bgm = []
    FPS = 60
    lastBoss = 0
    Death = object
    rx = 0
    ry = 0
    thistime = 0
    boss_spell_card_activated = False  # Boss是否已进入符卡阶段
    original_window_x = 0  # 游戏启动时的原始窗口X位置
    original_window_y = 0  # 游戏启动时的原始窗口Y位置
    boss = object
    bosscreatetime = 0
    rwidth = 0
    rheight = 0
    bossdeathtimes = 1
    haveTeleport = False
    teleportDeathtime = 0
    maxEn = 0
    bgmnow = 1
    Boardline = object
    app = object
    money = 0
    haveLovebumb = False
    loveBumb = object
    heaven = object
    temp = object
    gold = False
    golden = object
    theworld = object
    screen = object
    istimestoptime = False
    gamepauseImage = object
    backgroundImage = object
    backgroundImage2 = object
    backgroundImage3 = object
    boss1, boss3, boss4, boss1r, boss3r, boss2r, boss4r, boss5, boss5r = object, object, object, object, object, object, object, object, object
    boss6, boss6r = object, object
    bulluten = []
    isok = False
    boss4bgm, boss5bgm, boss6bgm = object, object, object
    healtime = False
    power = 0
    isBossTimestop = False
    special = object

    # 新游戏系统
    current_wave = 1  # 当前波次
    wave_spawn_timer = 0  # 波次生成计时器
    score_system = None  # 分数系统
    weapon_system = None  # 武器系统
    achievement_system = None  # 成就系统
    boss_enhancement_manager = None  # Boss增强管理器
    stage_system = None  # 关卡系统

    # 临时Buff系统
    invincible_until = 0  # 临时无敌结束时间
    score_multiplier = 1  # 分数倍增器
    multiplier_end_time = 0  # 分数倍增结束时间
    temp_max_power_until = 0  # 临时满火力结束时间

    # 成就通知系统
    achievement_notifications = []  # 成就通知队列 [(achievement_name, unlock_time), ...]

    @classmethod
    def createWaterEmoji(cls):
        cls.wateremoji = OEmoji.WaterEmoji()

    @classmethod
    def createBoss(cls):
        # 根据关卡系统创建对应的Boss
        if cls.stage_system:
            boss_id = cls.stage_system.current_stage
        else:
            boss_id = (cls.bossdeathtimes % 6) + 1  # 兼容旧版

        newBoss = OEmoji.BossEmemy(boss_id)
        cls.haveBoss = True

        # 停止所有道中BGM（关卡系统下可能有多个）
        for bgm in cls.Bgm:
            bgm.stop()

        for i in cls.g_enemies:
            if not i.isboss:
                th = threading.Thread(target=cls.removeNormal, args=(i,))
                th.daemon = True
                th.start()
        if newBoss.bossrint == 1:
            cls.Aleph.play(loops=-1)
        elif newBoss.bossrint == 2:
            cls.Boardline.play(loops=-1)
        elif newBoss.bossrint == 3:
            cls.temp.play(loops=-1)
        elif newBoss.bossrint == 4:
            cls.boss4bgm.play(loops=-1)
        elif newBoss.bossrint == 5:
            cls.boss5bgm.play(loops=-1)
        elif newBoss.bossrint == 6:
            cls.boss6bgm.play(loops=-1)
        cls.boss = newBoss
        if newBoss.bossrint == 4:
            Skill.BossSkillForth.framemove()
        if newBoss.bossrint == 5:
            th = threading.Thread(target=Skill.BossSkillFifth.moveFrame)
            th.daemon = True
            th.start()
        if newBoss.bossrint == 6:
            # 初始化Boss6的5阶段血量系统
            Skill.BossSkillSixth.init_phases()
        cls.g_enemies.append(newBoss)

        # 应用Boss增强系统
        try:
            from BossEnhancements import apply_boss_enhancements
            # 根据击败次数确定难度（1-5）
            difficulty = min(cls.bossdeathtimes, 5)
            cls.boss_enhancement_manager = apply_boss_enhancements(newBoss, difficulty)
        except ImportError:
            pass

    @classmethod
    def removeNormal(cls, em):
        index = 255
        for i in range(20):
            em.image.set_alpha(index)
            index -= 20
            time.sleep(0.1)
        try:
            cls.g_enemies.remove(em)
        except ValueError:
            pass

    @classmethod
    def bossUseSkill(cls):
        cls.boss.useSkills()
        if cls.haveBoss and cls.boss.bossrint == 2:
            try:
                if len(cls.allprevent) >= 2:
                    # 使用判定点检测与防御屏障的碰撞
                    if cls.wateremoji.hitbox_rect.colliderect(cls.allprevent[0].rect) or \
                       cls.wateremoji.hitbox_rect.colliderect(cls.allprevent[1].rect):
                        cls.wateremoji.x = random.randint(0, 300)
                        cls.wateremoji.y = random.randint(0, 440)
                        cls.wateremoji.update_hitbox()  # 更新判定点位置
            except (ValueError, IndexError) as e:
                # 防御屏障不存在时忽略碰撞检测
                pass

    @classmethod
    def showPrevent(cls, screen):
        if len(cls.allprevent) >= 2:
            screen.blit(cls.allprevent[0].image, (cls.allprevent[0].x, cls.allprevent[0].y))
            screen.blit(cls.allprevent[1].image, (cls.allprevent[1].x, cls.allprevent[1].y))

    @classmethod
    def createEnemy(cls, boostspeed):
        """创建敌人，支持新敌人类型"""
        if NEW_ENEMIES_AVAILABLE and random.random() < 0.6:  # 60%概率生成新类型敌人
            # 选择新类型敌人
            enemy_types = [FastEnemy, TankEnemy, SniperEnemy, SplitEnemy]

            # 根据波次增加难度，有概率生成特殊敌人
            if cls.current_wave % 5 == 0 and random.random() < 0.3:
                # 每5波有30%概率生成精英敌人
                newEnemy = EliteEnemy()
            elif random.random() < 0.2:
                # 20%概率生成自爆敌人
                newEnemy = SuicideEnemy()
            else:
                # 普通新类型敌人
                enemy_class = random.choice(enemy_types)
                newEnemy = enemy_class()

            # 设置位置
            newEnemy.x = main.WINDOWWIDTH + random.randint(0, 100)
            newEnemy.y = random.randint(50, main.WINDOWHEIGHT - 100)
            newEnemy.direction = 'left'
        else:
            # 生成原版敌人
            newEnemy = OEmoji.Enemy(boostspeed)

        cls.g_enemies.append(newEnemy)

    @classmethod
    def randommove(cls, i, chance):
        randoms = random.random()
        if randoms > 0 and randoms < chance and time.time() - i.cotime >= 0.5:
            i.cotime = time.time()
            i.direction = 'left'
        elif randoms >= chance and randoms < 2 * chance and time.time() - i.cotime >= 0.5:
            i.cotime = time.time()
            i.direction = 'right'
        elif randoms >= 2 * chance and randoms < 3 * chance and time.time() - i.cotime >= 0.5:
            i.cotime = time.time()
            i.direction = 'up'
        elif randoms >= 3 * chance and randoms <= 4 * chance and time.time() - i.cotime >= 0.5:
            i.cotime = time.time()
            i.direction = 'down'
        elif time.time() - i.cotime >= 0.5:
            i.cotime = time.time()
            i.direction = 'none'

    @classmethod
    def setDirection(cls):  # 敌人随机移动的方法
        for i in cls.g_enemies:
            i.intervaltime = time.time() - i.createtime
            if i.canChangeMove:
                if i.rint != 0:
                    if i.intervaltime < 1:
                        i.direction = 'left'
                    else:
                        cls.randommove(i, 0.2)
                else:
                    if i.intervaltime < 2.4:
                        if i.bossrint == 2:
                            i.direction = 'down'
                        else:
                            i.direction = 'left'
                    elif i.intervaltime >= i.movetime:
                        cls.randommove(i, 0.125)

    @classmethod
    def getEffect(cls):  # 获得效果
        for i in cls.allsupply:
            # 两阶段碰撞检测：先用快速rect检测，再用精确mask检测（补给使用整个角色碰撞）
            if i.rect.colliderect(cls.wateremoji.rect) and pygame.sprite.collide_mask(i, cls.wateremoji):
                i.attract()
                cls.allsupply.remove(i)

    @classmethod
    def createSupply(cls, type, x, y):  # 生成补给物
        cls.allsupply.append(AllSupply.Supply(type, x, y))

    @classmethod
    def supplyMove(cls, screen):  # 补给物移动的方法
        for i in cls.allsupply:
            i.move(screen)
        for i in cls.allsupply:
            if time.time() - i.createtime >= 18 + 3 * random.random():
                cls.allsupply.remove(i)

    @classmethod
    def gameinit(cls):  # 初始化游戏
        cls.createWaterEmoji()

        # 初始化新游戏系统
        if WEAPON_SYSTEM_AVAILABLE:
            cls.weapon_system = WeaponSystem()
        if GAME_SYSTEMS_AVAILABLE:
            cls.score_system = ScoreSystem()
            # 导入并初始化成就系统
            try:
                from GameSystems import AchievementSystem
                cls.achievement_system = AchievementSystem()
            except ImportError:
                pass

        # 重置波次
        cls.current_wave = 1
        cls.wave_spawn_timer = time.time()

    @classmethod
    def getkey(cls, key):
        cls.wateremoji.move(key)

    @classmethod
    def draw(cls, screen):
        cls.setDirection()
        for i in cls.g_enemies[::]:
            i.draw(screen)
            # 清理从任何方向离开屏幕的敌人（左、右、上、下）
            if (i.x > main.WINDOWWIDTH + 100 or i.x < -100 or
                i.y > main.WINDOWHEIGHT + 100 or i.y < -100):
                cls.g_enemies.remove(i)

        cls.wateremoji.draw(screen)
        cls.wateremoji.rect.left = cls.wateremoji.x
        cls.wateremoji.rect.top = cls.wateremoji.y
        cls.wateremoji.update_hitbox()  # 确保判定点位置与角色同步

        # 绘制判定点（只在按住shift时显示）
        if cls.wateremoji.is_focused:
            hitbox_center = cls.wateremoji.get_hitbox_center()
            # 绘制红色判定点
            pygame.draw.circle(screen, (255, 0, 0), hitbox_center, cls.wateremoji.hitbox_size)
            # 绘制白色外圈，增加可见性
            pygame.draw.circle(screen, (255, 255, 255), hitbox_center, cls.wateremoji.hitbox_size + 1, 1)

        for i in cls.wateremoji.allbumb[::]:
            if i.x > 1280:  # 调整到新窗口宽度
                cls.wateremoji.allbumb.remove(i)

    @classmethod
    def updateLocation(cls):
        for i in cls.g_enemies:
            i.move()  # 敌人移动
            i.rect.left = i.x
            i.rect.top = i.y

    @classmethod
    def testfor(cls, bumb, value):
        try:
            if len(cls.allprevent) >= 2:
                # 两阶段碰撞检测：先用快速rect检测，再用精确mask检测
                if (bumb.rect.colliderect(cls.allprevent[0].rect) and pygame.sprite.collide_mask(bumb, cls.allprevent[0])) or \
                   (bumb.rect.colliderect(cls.allprevent[1].rect) and pygame.sprite.collide_mask(bumb, cls.allprevent[1])):
                    try:
                        if value == 0:
                            cls.allenbumbs.remove(bumb)
                        elif value == 1:
                            cls.wateremoji.allbumb.remove(bumb)
                    except ValueError:
                        # 子弹已被移除
                        pass
        except IndexError:
            # 防御屏障不存在
            pass

    @classmethod
    def showAttr(cls, screen):
        screen.blit(Skill.BossSkillSecond.newattr.image,
                    (Skill.BossSkillSecond.newattr.x, Skill.BossSkillSecond.newattr.y))

    @classmethod
    def enshoot(cls, screen):  # 敌人射击的方法
        for i in cls.g_enemies:
            i.shoot()

        # 优化：批量绘制敌人子弹
        for j in cls.allenbumbs:
            # 性能优化：屏幕剔除 - 跳过屏幕外子弹的绘制
            if -100 <= j.x <= main.WINDOWWIDTH + 100 and -100 <= j.y <= main.WINDOWHEIGHT + 100:
                j.draw(screen)

        # 优化：使用列表副本进行碰撞检测
        bullets_copy = cls.allenbumbs[::]
        for j in bullets_copy:
            if j not in cls.allenbumbs:  # 子弹可能已被移除
                continue

            # 性能优化：屏幕剔除 - 跳过屏幕外子弹的碰撞检测
            if not (-100 <= j.x <= main.WINDOWWIDTH + 100 and -100 <= j.y <= main.WINDOWHEIGHT + 100):
                continue

            # Boss2的防御屏障碰撞检测
            if cls.haveBoss is True and cls.boss.bossrint == 2 and j.canRemove is True:
                t1 = threading.Thread(target=cls.testfor(j, 0))
                t1.daemon = True
                t1.start()

            # 与玩家的碰撞检测（使用判定点）
            # 检查临时无敌buff
            if time.time() < cls.invincible_until:
                # 无敌状态，跳过碰撞处理
                continue

            # 无限血量模式：只移除子弹，不扣血
            if cls.wateremoji.hitbox_rect.colliderect(j.rect) and \
               time.time() - cls.latesttime >= 1 and not j.blow:
                cls.latesttime = time.time()
                # cls.wateremoji.live = int(cls.wateremoji.live - j.hurt)  # 注释掉扣血
                if j.canDelete and j in cls.allenbumbs:
                    cls.allenbumbs.remove(j)
                # 无限血量模式：不会死亡
                # if cls.wateremoji.live <= 0:
                #     cls.wateremoji.live = 0
                #     Game.isok = True
            elif cls.wateremoji.hitbox_rect.colliderect(j.rect) and \
                 not time.time() - cls.latesttime >= 1 and j.canDelete:
                if j in cls.allenbumbs:
                    cls.allenbumbs.remove(j)

            # 子弹反弹逻辑
            if j.canReturn and j.x <= 0:
                j.x += j.speed
                j.tan = -j.tan
                j.sample = -j.sample
                j.direction = 'right'
            if j.canReturn and (j.y <= 0 or j.y >= main.WINDOWHEIGHT - j.size):
                j.tan = -j.tan

            # 移除超出屏幕的子弹
            if (j.x <= 0 - j.size or j.x >= main.WINDOWWIDTH or j.y < 0 - j.size or j.y >= main.WINDOWHEIGHT) \
                    and not j.banRemove:
                if j == cls.loveBumb:
                    cls.loveBumb = object
                    cls.haveLovebumb = False
                if j in cls.allenbumbs:
                    cls.allenbumbs.remove(j)

    @classmethod
    def generateSupply(cls, chance, x, y):  # 随机概率生成随机补给物
        if random.random() < chance:
            cls.createSupply(random.randint(1, 3), x - 20, y)
        if chance == 1:  # 只有boss才会有100%掉落，所以这里是boss掉落物
            cls.createSupply(6, x - 20, y)
            cls.createSupply(6, x - 20, y)
            cls.createSupply(6, x - 20, y)
            cls.createSupply(0, x - 20, y)
            cls.createSupply(7, x - 20, y)
            return
        if random.random() < chance * 1.7:
            cls.createSupply(4, x - 20, y)
        elif random.random() < chance:
            cls.createSupply(5, x - 20, y)
        elif random.random() < chance * 0.3:
            cls.createSupply(6, x - 20, y)

    @classmethod
    def bossDeath(cls, boss):
        # 检查是否已经进入符卡阶段
        if not cls.boss_spell_card_activated:
            # 第一次死亡，进入符卡阶段
            cls.boss_spell_card_activated = True

            # 清空所有子弹（给玩家喘息）
            cls.allenbumbs.clear()

            # Boss血量回满
            cls.boss.live = cls.boss.maxlive

            # Boss移动到屏幕上方中央
            cls.boss.x = main.WINDOWWIDTH // 2
            cls.boss.y = 150
            cls.boss.rect.left = cls.boss.x
            cls.boss.rect.top = cls.boss.y

            # 停止Boss普通移动
            cls.boss.canShoot = False

            # 播放一个提示音（如果有的话）
            # cls.Death.play()

            # 激活符卡系统（延迟1秒让玩家看到提示）
            def delayed_spell_card():
                time.sleep(1)
                if cls.haveBoss:
                    SpellCardSystem.activate_spell_card(cls.boss.bossrint)
                    cls.boss.canShoot = True

            threading.Thread(target=delayed_spell_card, daemon=True).start()

            return  # 不真正死亡，继续战斗

        # 第二次死亡（符卡阶段结束），真正死亡
        cls.score += cls.boss.maxlive
        cls.haveBoss = False
        cls.boss_spell_card_activated = False  # 重置符卡标志
        SpellCardSystem.deactivate_spell_card()  # 结束符卡阶段

        # 清理所有残留的特殊效果（闪电、色块、UFO等canDelete=False的对象）
        cls.allenbumbs.clear()

        if cls.boss.bossrint == 1:
            cls.Aleph.stop()
        elif cls.boss.bossrint == 2:
            cls.Boardline.stop()
            cls.allprevent.clear()
        elif cls.boss.bossrint == 3:
            cls.temp.stop()
        elif cls.boss.bossrint == 4:
            cls.boss4bgm.stop()
            Skill.BossSkillForth.frame.Hide()
        elif cls.boss.bossrint == 5:
            cls.boss5bgm.stop()
        elif cls.boss.bossrint == 6:
            cls.boss6bgm.stop()
            # 清理Boss6的五角星框架
            if Skill.BossSkillSixth.pentagram_frame:
                try:
                    Skill.BossSkillSixth.pentagram_frame.Hide()
                except:
                    pass
            # 重置Boss6状态
            Skill.BossSkillSixth.transparency_active = False
            Skill.BossSkillSixth.window_shake_active = False
            # 清理阶段标记
            for attr in ['_phase1_started', '_phase2_started', '_phase3_started', '_phase4_started', '_phase5_started']:
                if hasattr(Skill.BossSkillSixth, attr):
                    delattr(Skill.BossSkillSixth, attr)

        # 清理Boss增强管理器
        cls.boss_enhancement_manager = None

        cls.Death.play()

        # 通知关卡系统Boss被击败
        if cls.stage_system:
            cls.stage_system.on_boss_defeated()

            # 停止所有道中BGM（确保没有双重播放）
            for bgm in cls.Bgm:
                bgm.stop()

            # 播放下一关的道中BGM（如果不是最后一关）
            if cls.stage_system.current_stage < cls.stage_system.total_stages:
                next_stage_index = cls.stage_system.current_stage  # 下一关的索引（当前关+1）
                if 0 <= next_stage_index < len(cls.Bgm):
                    cls.Bgm[next_stage_index].play(loops=-1)
            # 如果是最后一关，停止所有BGM
        else:
            # 兼容旧版：随机播放道中BGM
            cls.bgmnow = random.randint(0, 4)
            cls.Bgm[cls.bgmnow].play()

        cls.lastBoss = time.time()
        cls.bossdeathtimes += 1
        Move.moveWin(cls.rx, cls.ry)  # 还原坐标
        for k in range(random.randint(1, 5)):
            cls.generateSupply(1, boss.x, boss.y)

        # 成就系统检查 - Boss击杀
        if cls.achievement_system:
            cls.achievement_system.update_stats('total_bosses_killed')

            unlocked_achievements = []
            if cls.achievement_system.stats['total_bosses_killed'] == 1:
                if cls.achievement_system.check_achievement('boss_1'):
                    unlocked_achievements.append('boss_1')
            if cls.achievement_system.stats['total_bosses_killed'] >= 6:
                if cls.achievement_system.check_achievement('boss_all'):
                    unlocked_achievements.append('boss_all')

            for achievement_id in unlocked_achievements:
                achievement = cls.achievement_system.achievements[achievement_id]
                cls.achievement_notifications.append((achievement['name'], time.time()))

    @classmethod
    def emojiDeath(cls, emoji):
        cls.createSupply(8, emoji.x - 20, emoji.y)

        # 确定敌人类型用于分数系统
        enemy_type = 'normal_enemy'
        if hasattr(emoji, 'rint'):
            if emoji.rint == 11:
                enemy_type = 'fast_enemy'
            elif emoji.rint == 12:
                enemy_type = 'tank_enemy'
            elif emoji.rint == 13:
                enemy_type = 'suicide_enemy'
            elif emoji.rint == 14:
                enemy_type = 'sniper_enemy'
            elif emoji.rint == 15:
                enemy_type = 'shield_enemy'
            elif emoji.rint == 16:
                enemy_type = 'split_enemy'
            elif emoji.rint == 17:
                enemy_type = 'elite_enemy'
            elif emoji.rint == 18:
                enemy_type = 'mini_boss'

        # 使用新分数系统（如果可用）
        if cls.score_system:
            score_gained = cls.score_system.add_enemy_kill(enemy_type)
            cls.score = cls.score_system.score
        else:
            # 原版分数系统
            cls.score += emoji.maxlive

        if emoji.rint == 1:
            cls.generateSupply(0.2, emoji.x, emoji.y)
        elif emoji.rint == 2:
            cls.generateSupply(0.3, emoji.x, emoji.y)
        elif emoji.rint >= 3:
            if emoji.rint == 8:
                return
            cls.generateSupply(0.5, emoji.x, emoji.y)
        elif emoji.rint == 0.5:
            cls.generateSupply(0.6, emoji.x, emoji.y)
            cls.teleportDeathtime = time.time()
            cls.haveTeleport = False
        elif emoji.rint == -1:
            cls.generateSupply(0.2, emoji.x, emoji.y)
        elif emoji.rint == -2:
            cls.generateSupply(0.2, emoji.x, emoji.y)
        # 新敌人类型的额外补给掉落
        elif emoji.rint == 17:  # 精英敌人
            # 掉落更多补给
            for i in range(3):
                supply_type = random.choice([1, 2, 3, 9, 10])
                cls.createSupply(supply_type, emoji.x + i * 20, emoji.y)
        elif emoji.rint == 18:  # 小Boss
            # 掉落大量补给
            for i in range(5):
                supply_type = random.choice([1, 2, 3, 9, 10, 13, 14])
                cls.createSupply(supply_type, emoji.x + i * 25, emoji.y)

        # 处理分裂敌人
        if hasattr(emoji, 'on_death'):
            emoji.on_death()

        # 成就系统检查
        if cls.achievement_system:
            # 更新击杀统计
            cls.achievement_system.update_stats('total_kills')

            # 检查击杀相关成就
            unlocked_achievements = []
            if cls.achievement_system.stats['total_kills'] == 1:
                if cls.achievement_system.check_achievement('first_blood'):
                    unlocked_achievements.append('first_blood')

            # 检查连击成就
            if cls.score_system:
                combo = cls.score_system.combo_system.combo
                if combo >= 10 and cls.achievement_system.check_achievement('combo_10'):
                    unlocked_achievements.append('combo_10')
                if combo >= 50 and cls.achievement_system.check_achievement('combo_50'):
                    unlocked_achievements.append('combo_50')
                if combo >= 100 and cls.achievement_system.check_achievement('combo_100'):
                    unlocked_achievements.append('combo_100')

            # 检查分数成就
            if cls.score >= 10000 and cls.achievement_system.check_achievement('score_10k'):
                unlocked_achievements.append('score_10k')
            if cls.score >= 100000 and cls.achievement_system.check_achievement('score_100k'):
                unlocked_achievements.append('score_100k')
            if cls.score >= 1000000 and cls.achievement_system.check_achievement('score_1m'):
                unlocked_achievements.append('score_1m')

            # 将解锁的成就添加到通知队列
            for achievement_id in unlocked_achievements:
                achievement = cls.achievement_system.achievements[achievement_id]
                cls.achievement_notifications.append((achievement['name'], time.time()))

    @classmethod
    def drawBoss(cls):  # boss血条（调整到1.5倍大小）
        # 符卡阶段提示
        if cls.boss_spell_card_activated:
            font = pygame.font.SysFont('arial', 40, bold=True)
            spell_text = font.render('★ SPELL CARD ★', True, (255, 255, 0))
            text_rect = spell_text.get_rect(center=(main.WINDOWWIDTH // 2, 70))
            # 闪烁效果
            if int(time.time() * 2) % 2 == 0:
                cls.screen.blit(spell_text, text_rect)

        if cls.boss.bossrint == 6:
            # Boss6：5个阶段血条
            current_phase = Skill.BossSkillSixth.get_current_phase()
            bar_width = 150  # 每个血条宽度
            bar_height = 30
            bar_gap = 5
            start_x = 105
            start_y = 15

            total_hp = cls.boss.maxlive
            phase_hp_size = total_hp / 5  # 每个阶段的血量

            for i in range(5):
                x = start_x + i * (bar_width + bar_gap)
                phase_num = i + 1

                # 背景框
                pygame.draw.rect(cls.screen, (0, 0, 0), (x - 2, start_y - 2, bar_width + 4, bar_height + 4))
                pygame.draw.rect(cls.screen, (123, 123, 123), (x, start_y, bar_width, bar_height))

                # 计算当前血条的填充
                if phase_num < current_phase:
                    # 已经通过的阶段，空血条
                    fill_ratio = 0
                    color = (64, 64, 64)  # 已通过灰色
                elif phase_num == current_phase:
                    # 当前阶段，计算血量比例
                    # 阶段的血量范围
                    phase_start_hp = Skill.BossSkillSixth.phase_hp[i]  # 阶段开始阈值
                    phase_end_hp = total_hp if i == 0 else Skill.BossSkillSixth.phase_hp[i - 1]  # 阶段结束阈值

                    current_hp_in_phase = cls.boss.live - phase_start_hp
                    phase_total = phase_end_hp - phase_start_hp

                    fill_ratio = max(0, min(1, current_hp_in_phase / phase_total))
                    color = (255, 0, 0)  # 当前阶段红色
                else:
                    # 未到的阶段，满血条
                    fill_ratio = 1
                    color = (255, 150, 150)  # 未到粉色

                pygame.draw.rect(cls.screen, color, (x, start_y, int(bar_width * fill_ratio), bar_height))

                # 阶段编号
                font = pygame.font.SysFont('arial', 16)
                phase_text = font.render(str(phase_num), True, (255, 255, 255))
                text_rect = phase_text.get_rect(center=(x + bar_width // 2, start_y + bar_height // 2))
                cls.screen.blit(phase_text, text_rect)
        else:
            # 其他Boss：单血条
            pygame.draw.rect(cls.screen, (0, 0, 0), (104, 14, 753, 33))
            pygame.draw.rect(cls.screen, (123, 123, 123), (105, 15, 750, 30))
            pygame.draw.rect(cls.screen, (255, 0, 0), (105, 15, int(750 * (cls.boss.live / cls.boss.maxlive)), 30))

    @classmethod
    def shoot(cls, screen):  # 流汗黄豆射击方法
        cls.wateremoji.shoot()
        # 优化：使用列表副本避免迭代时修改列表
        bullets_copy = cls.wateremoji.allbumb[::]
        enemies_copy = cls.g_enemies[::]

        for i in bullets_copy:
            if i not in cls.wateremoji.allbumb:  # 子弹可能已被移除
                continue

            # 性能优化：屏幕剔除 - 跳过屏幕外子弹的绘制
            if -100 <= i.x <= main.WINDOWWIDTH + 100 and -100 <= i.y <= main.WINDOWHEIGHT + 100:
                i.draw(screen)
            else:
                # 屏幕外的子弹跳过碰撞检测
                continue

            # 优化：先检查子弹是否还在列表中再进行碰撞检测
            for j in enemies_copy:
                if j not in cls.g_enemies:  # 敌人可能已被移除
                    continue
                # 两阶段碰撞检测：先用快速rect检测，再用精确mask检测
                if i.rect.colliderect(j.rect) and pygame.sprite.collide_mask(i, j) and j.canbeshoot:
                    if j.rint == 0 and cls.healtime:
                        j.live = int(j.live + i.hurt)
                        if j.live > j.maxlive:
                            j.live = j.maxlive
                    else:
                        # 计算实际伤害
                        damage = i.hurt

                        # Boss增强系统伤害拦截
                        if j.rint == 0 and cls.boss_enhancement_manager:
                            damage = cls.boss_enhancement_manager.process_damage(damage)

                        j.live = int(j.live - damage)
                    if j.live <= 0:
                        if j.rint != 0:
                            cls.emojiDeath(j)
                            if j in cls.g_enemies:
                                cls.g_enemies.remove(j)
                        elif j.rint == 0:
                            # Boss死亡处理
                            was_spell_card_activated = cls.boss_spell_card_activated
                            cls.bossDeath(j)
                            # 如果刚进入符卡阶段（第一次死亡），不移除Boss
                            if not was_spell_card_activated and cls.boss_spell_card_activated:
                                # 进入符卡阶段，Boss血量已回满，不移除
                                pass
                            else:
                                # 真正死亡，移除Boss
                                if j in cls.g_enemies:
                                    cls.g_enemies.remove(j)
                    try:
                        # 处理轰炸弹爆炸效果
                        if hasattr(i, 'is_bomb') and i.is_bomb:
                            from WeaponSystem import BombardmentShot
                            BombardmentShot.explode(i)
                            if i in cls.wateremoji.allbumb:
                                cls.wateremoji.allbumb.remove(i)
                                break
                        # 处理穿透弹
                        elif hasattr(i, 'can_penetrate') and i.can_penetrate:
                            i.penetrate_count -= 1
                            if i.penetrate_count <= 0:
                                # 穿透次数用完，移除子弹
                                if i in cls.wateremoji.allbumb:
                                    cls.wateremoji.allbumb.remove(i)
                                    break
                            # 否则继续穿透，不移除子弹
                        elif i.Remove and i in cls.wateremoji.allbumb:
                            cls.wateremoji.allbumb.remove(i)
                            break  # 子弹已移除，跳出内层循环
                    except (ValueError, AttributeError):
                        # 子弹已被移除或属性不存在
                        break

    @classmethod
    def gameover(cls):
        # 无限血量模式：直接返回False，永不死亡
        # 使用判定点检测与敌人的碰撞（保留碰撞检测但不扣血）
        for i in cls.g_enemies:
            if cls.wateremoji.hitbox_rect.colliderect(i.rect) and time.time() - cls.latesttime >= 1:
                # cls.wateremoji.live -= 10  # 注释掉扣血
                cls.latesttime = time.time()
                # 无限血量模式：不会死亡
                # if cls.wateremoji.live <= 0:
                #     cls.wateremoji.live = 0
                #     return True
        return False

    @classmethod
    def waitForKeyPress(cls):
        while True:
            for e in pygame.event.get():
                if e.type == pygame.QUIT:
                    cls.terminate()
                elif e.type == pygame.KEYDOWN:
                    if e.key == pygame.K_RETURN:
                        return

    @staticmethod
    def terminate():
        pygame.quit()
        sys.exit(0)

    @classmethod
    def pause(cls, screen, image):
        screen.blit(image, (0, 0))
        pygame.display.update()
        while True:
            for e in pygame.event.get():
                if e.type == pygame.QUIT:
                    cls.terminate()
                elif e.type == pygame.KEYDOWN:
                    if e.key == pygame.K_SPACE or pygame.K_ESCAPE:
                        return

    @classmethod
    def showPower(cls):  # 能量条（调整到1.5倍大小）
        pygame.draw.rect(cls.screen, (0, 0, 0), (59, 905, 183, 33))
        pygame.draw.rect(cls.screen, (123, 123, 123), (60, 906, 180, 30))
        if cls.power != 100:
            pygame.draw.rect(cls.screen, (0, 0, 255), (60, 906, int(180 * (cls.power / 100)), 30))
        else:
            pygame.draw.rect(cls.screen, (199, 21, 133), (60, 906, 180, 30))

    @classmethod
    def showLife(cls, font, screen):  # 显示敌人emoji的血量（调整到1.5倍大小）
        for i in cls.g_enemies:
            if not i.isboss:
                pygame.draw.rect(cls.screen, (123, 123, 123), (i.x, i.y - 15, 60, 8))
                pygame.draw.rect(cls.screen, (255, 0, 0),
                                 (i.x, i.y - 15, int(60 * (i.live / i.maxlive)), 8))
        pygame.draw.rect(cls.screen, (123, 123, 123), (cls.wateremoji.x, cls.wateremoji.y - 15, 60, 8))
        pygame.draw.rect(cls.screen, (255, 0, 0),
                         (cls.wateremoji.x, cls.wateremoji.y - 15,
                          int(60 * (cls.wateremoji.live / cls.wateremoji.maxlive)), 8))
        cls.drawText('%s/%s' % (cls.wateremoji.live, cls.wateremoji.maxlive), font, screen, cls.wateremoji.x,
                     cls.wateremoji.y - 23)

    @staticmethod
    def drawText(text, font, screen, x, y):
        content = font.render(text, False, (0, 0, 0))
        contentRect = content.get_rect()
        contentRect.left = x
        contentRect.top = y
        screen.blit(content, contentRect)

    @classmethod
    def crazyShoot(cls):
        for i in range(20):
            for j in range(0, 960, 40):  # 调整到新窗口高度（2倍）
                cls.wateremoji.allbumb.append(Bullt.WaterBumb(cls.wateremoji.x, j, cls.wateremoji.hurt))
            time.sleep(0.1)

    @classmethod
    def blowbullut(cls):
        for i in cls.allenbumbs:
            i.direction = 'right'
            i.tan = 0
            i.sample = 0
            i.blow = True

    @classmethod
    def waterTimeStop(cls, screen):
        font1 = pygame.font.SysFont('arial', 12)  # 减小字体避免遮挡视野（从18减到12）
        font2 = pygame.font.SysFont(None, 30)  # 调整到1.5倍
        Game.watertime.play()
        while cls.istimestoptime:
            if Game.haveBoss is True and Game.boss.bossrint == 1:  # 唐氏出场的换背景图的技能
                screen.blit(Game.boss1r, (0, 0))
            elif Game.haveBoss is True and Game.boss.bossrint == 2:
                screen.blit(Game.boss2r, (0, 0))
                try:
                    Game.showPrevent(screen)
                except IndexError:
                    pass
            elif Game.haveBoss is True and Game.boss.bossrint == 3:
                screen.blit(Game.boss3r, (0, 0))
            elif Game.haveBoss and Game.boss.bossrint == 4:
                screen.blit(Game.boss4r, (0, 0))
            elif Game.haveBoss and Game.boss.bossrint == 5:
                screen.blit(Game.boss5r, (0, 0))
            elif Game.haveBoss and Game.boss.bossrint == 6:
                screen.blit(Game.boss6r, (0, 0))
            else:
                screen.blit(Game.backgroundImage2, (0, 0))
            if Game.haveBoss:
                Game.drawBoss()
            # 调整时间停止模式下的UI文字位置（2倍大小）
            Game.drawText('score:%s' % (Game.score), font1, screen, 80, 20)
            Game.drawText('money:%s' % (Game.money), font1, screen, 80, 60)
            Game.drawText('gametime:%s' % ('TIMESTOP'), font1, screen, 1080, 20)
            Game.showLife(font2, screen)
            Game.showPower()
            for i in Game.g_enemies:
                Game.screen.blit(i.image, (i.x, i.y))

            # 绘制主角子弹
            for i in Game.wateremoji.allbumb:
                Game.screen.blit(i.image, (i.x, i.y))

            # 绘制敌人子弹
            for i in Game.allenbumbs:
                try:
                    Game.screen.blit(i.image, (i.x, i.y))
                except pygame.error:
                    pass

            # 绘制判定点（时间停止时也显示）
            if cls.wateremoji.is_focused:
                hitbox_center = cls.wateremoji.get_hitbox_center()
                pygame.draw.circle(screen, (255, 0, 0), hitbox_center, cls.wateremoji.hitbox_size)
                pygame.draw.circle(screen, (255, 255, 255), hitbox_center, cls.wateremoji.hitbox_size + 1, 1)

            try:
                for i in Game.allsupply:
                    Game.screen.blit(i.image, (i.x, i.y))
            except pygame.error:
                pass
            cls.wateremoji.shoot()
            if Skill.BossSkillSecond.hasAttr:  # 如果有心形传送门就把它画出来
                Game.showAttr(screen)
            try:
                Game.draw(screen)
            except pygame.error:
                pass
            Game.getEffect()
            pygame.display.update()
            tl = pygame.time.Clock()
            tl.tick(Game.FPS)

    @classmethod
    def powerShoot(cls):
        cls.wateremoji.canShoot = False
        for j in range(30):
            index = 50
            for i in range(4):
                while cls.isBossTimestop:
                    time.sleep(1)
                newbumb = Bullt.WaterBumb(cls.wateremoji.x, cls.wateremoji.y + index, cls.wateremoji.hurt / 1.8)
                newbumb.Remove = False
                newbumb.image = cls.special
                newbumb.rect = newbumb.image.get_rect()
                newbumb.rect.left, newbumb.rect.top = newbumb.x, newbumb.y
                cls.wateremoji.allbumb.append(newbumb)
                index -= 25
            time.sleep(0.1)
        cls.wateremoji.canShoot = True

    @classmethod
    def keyEvent(cls, screen, keylist, gamepauseImage):
        # 检测shift按键状态（精确移动模式）
        if hasattr(cls.wateremoji, 'is_focused'):
            cls.wateremoji.is_focused = keylist[pygame.K_LSHIFT] or keylist[pygame.K_RSHIFT]

        for e in pygame.event.get():
            if e.type == pygame.QUIT:
                Game.terminate()
            elif e.type == pygame.KEYDOWN:
                if e.key == pygame.K_SPACE or e.key == pygame.K_ESCAPE:
                    Game.pause(screen, gamepauseImage)
                # X键：使用炸弹（Bomb系统）
                if e.key == pygame.K_x:
                    if cls.wateremoji.use_bomb():
                        # 清除所有敌方子弹
                        cls.allenbumbs.clear()
                        # 可选：对所有敌人造成伤害
                        for enemy in cls.g_enemies:
                            enemy.live -= 50

                # C键：冲刺（Dash系统）
                if e.key == pygame.K_c:
                    # 获取当前移动方向
                    dx, dy = 0, 0
                    if keylist[pygame.K_LEFT] or keylist[pygame.K_a]:
                        dx = -1
                    elif keylist[pygame.K_RIGHT] or keylist[pygame.K_d]:
                        dx = 1
                    if keylist[pygame.K_UP] or keylist[pygame.K_w]:
                        dy = -1
                    elif keylist[pygame.K_DOWN] or keylist[pygame.K_s]:
                        dy = 1
                    # 如果没有按方向键，默认向右冲刺
                    if dx == 0 and dy == 0:
                        dx = 1
                    cls.wateremoji.use_dash(dx, dy)

                # 1-8键：切换武器
                if cls.weapon_system:
                    weapon_keys = {
                        pygame.K_1: 'normal',
                        pygame.K_2: 'spread',
                        pygame.K_3: 'homing',
                        pygame.K_4: 'laser',
                        pygame.K_5: 'penetrating',
                        pygame.K_6: 'bombardment',
                        pygame.K_7: 'wave',
                        pygame.K_8: 'spiral'
                    }
                    if e.key in weapon_keys:
                        cls.weapon_system.switch_weapon(weapon_keys[e.key])

                if e.key == pygame.K_e:
                    if cls.power == 100:
                        cls.power = 0
                        th = threading.Thread(target=cls.powerShoot)
                        th.daemon = True
                        th.start()
                if e.key == pygame.K_j:
                    if Game.money >= 0:
                        Game.money -= 0
                        th = threading.Thread(target=cls.crazyShoot)
                        th.daemon = True
                        th.start()
                if e.key == pygame.K_k:
                    if Game.money >= 0:
                        Game.money -= 0
                        cls.blowbullut()
                if e.key == pygame.K_l and not cls.istimestoptime:
                    if Game.money >= 0:
                        Game.money -= 0
                        th = threading.Thread(target=cls.waterTimeStop, args=(screen,))
                        th.daemon = True
                        th.start()
                        times = time.time()
                        cls.istimestoptime = True
                        while time.time() - times <= 2:
                            keylist = pygame.key.get_pressed()
                            Game.keyEvent(screen, keylist, Game.gamepauseImage)
                            pygame.time.Clock().tick(Game.FPS)
                        cls.istimestoptime = False

        if cls.haveBoss and cls.boss.bossrint == 3 and cls.gold:
            if (keylist[pygame.K_RIGHT] or keylist[pygame.K_d]) and (keylist[pygame.K_UP] or keylist[pygame.K_w]):
                Game.getkey('left-down')
            elif (keylist[pygame.K_RIGHT] or keylist[pygame.K_d]) and (
                    keylist[pygame.K_DOWN] or keylist[pygame.K_s]):
                Game.getkey('left-up')
            elif (keylist[pygame.K_LEFT] or keylist[pygame.K_a]) and (keylist[pygame.K_UP] or keylist[pygame.K_w]):
                Game.getkey('right-down')
            elif (keylist[pygame.K_LEFT] or keylist[pygame.K_a]) and (
                    keylist[pygame.K_DOWN] or keylist[pygame.K_s]):
                Game.getkey('right-up')
            elif keylist[pygame.K_UP] or keylist[pygame.K_w]:
                Game.getkey('down')
            elif keylist[pygame.K_DOWN] or keylist[pygame.K_s]:
                Game.getkey('up')
            elif keylist[pygame.K_LEFT] or keylist[pygame.K_a]:
                Game.getkey('right')
            elif keylist[pygame.K_RIGHT] or keylist[pygame.K_d]:
                Game.getkey('left')
        else:
            if (keylist[pygame.K_RIGHT] or keylist[pygame.K_d]) and (keylist[pygame.K_UP] or keylist[pygame.K_w]):
                Game.getkey('right-up')
            elif (keylist[pygame.K_RIGHT] or keylist[pygame.K_d]) and (
                    keylist[pygame.K_DOWN] or keylist[pygame.K_s]):
                Game.getkey('right-down')
            elif (keylist[pygame.K_LEFT] or keylist[pygame.K_a]) and (keylist[pygame.K_UP] or keylist[pygame.K_w]):
                Game.getkey('left-up')
            elif (keylist[pygame.K_LEFT] or keylist[pygame.K_a]) and (
                    keylist[pygame.K_DOWN] or keylist[pygame.K_s]):
                Game.getkey('left-down')
            elif keylist[pygame.K_UP] or keylist[pygame.K_w]:
                Game.getkey('up')
            elif keylist[pygame.K_DOWN] or keylist[pygame.K_s]:
                Game.getkey('down')
            elif keylist[pygame.K_LEFT] or keylist[pygame.K_a]:
                Game.getkey('left')
            elif keylist[pygame.K_RIGHT] or keylist[pygame.K_d]:
                Game.getkey('right')
