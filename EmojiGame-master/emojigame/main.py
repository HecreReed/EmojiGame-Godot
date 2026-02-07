# 黄豆流汗飞机大战
# made by Hecre_Reed
# coding = utf-8

# 导入pygame库和sys库
import pygame, time, sys, OEmoji, Bullt, random, sqlite3, Move, win32api, win32gui, wx, Frame, threading
from Event import *

Friend = 'friend'
Enemies = 'enemies' 
# 扩大窗口到2倍大小
WINDOWWIDTH = 1280  # 原来640
WINDOWHEIGHT = 960  # 原来480
if __name__ == '__main__':
    try:
        data = sqlite3.connect('data.db')
        curor = data.cursor()
        Game.rwidth = win32api.GetSystemMetrics(0)
        Game.rheight = win32api.GetSystemMetrics(1)

        # 创建用户表（如果不存在）
        try:
            curor.execute('CREATE TABLE IF NOT EXISTS user (id INTEGER PRIMARY KEY, name INTEGER)')
        except sqlite3.OperationalError as e:
            print(f"创建表失败: {e}")

        # 插入初始数据（使用参数化查询防止SQL注入）
        try:
            curor.execute("INSERT OR IGNORE INTO user (id, name) VALUES (?, ?)", (1, 0))
            curor.execute("INSERT OR IGNORE INTO user (id, name) VALUES (?, ?)", (2, 0))
        except sqlite3.Error as e:
            print(f"插入数据失败: {e}")

        # 读取最高分和金币数据
        curor.execute("SELECT * FROM user")
        best = curor.fetchall()
        bestscore = int(best[0][1]) if best and len(best) > 0 else 0
        money = int(best[1][1]) if best and len(best) > 1 else 0
        Game.money = money
    except sqlite3.Error as e:
        print(f"数据库错误: {e}")
        bestscore = 0
        money = 0
        Game.money = 0
    except Exception as e:
        print(f"初始化错误: {e}")
        bestscore = 0
        money = 0
        Game.money = 0

    pygame.init()
    pygame.mixer.init()
    Game.app = wx.App()
    loading = pygame.image.load('image/loading.png')
    loading = pygame.transform.scale(loading, (WINDOWWIDTH, WINDOWHEIGHT))  # 缩放加载图片
    screen = pygame.display.set_mode((WINDOWWIDTH, WINDOWHEIGHT), 0, 32)
    Game.screen = screen
    pygame.display.set_caption('流汗黄豆emoji抽象战争')
    screen.blit(loading, (0, 0))
    pygame.display.update()

    # 加载所有BGM（Boss BGM已移到这里统一加载）
    Game.Aleph = pygame.mixer.Sound('music/boss1.mp3')  # Boss1 BGM
    Game.Boardline = pygame.mixer.Sound('music/boss2.mp3')  # Boss2 BGM
    Game.temp = pygame.mixer.Sound('music/boss3.mp3')  # Boss3 BGM
    Game.boss4bgm = pygame.mixer.Sound('music/boss4.mp3')  # Boss4 BGM
    Game.boss5bgm = pygame.mixer.Sound('music/boss5.mp3')  # Boss5 BGM
    Game.boss6bgm = pygame.mixer.Sound('music/boss6.mp3')  # Boss6 BGM

    Game.Death = pygame.mixer.Sound('music/death.mp3')

    # 道中BGM（6个关卡）
    Game.Bgm.append(pygame.mixer.Sound('music/bgm1.mp3'))
    Game.Bgm.append(pygame.mixer.Sound('music/bgm2.mp3'))
    Game.Bgm.append(pygame.mixer.Sound('music/bgm3.mp3'))
    Game.Bgm.append(pygame.mixer.Sound('music/bgm4.mp3'))
    Game.Bgm.append(pygame.mixer.Sound('music/bgm5.mp3'))
    Game.Bgm.append(pygame.mixer.Sound('music/bgm6.mp3'))

    # 特殊BGM
    Game.heaven = pygame.mixer.Sound('music/madeinheaven.wav')
    Game.golden = pygame.mixer.Sound('music/gold.wav')
    Game.theworld = pygame.mixer.Sound('music/theworld.wav')
    Game.watertime = pygame.mixer.Sound('music/watertimestop.wav')

    # 加载并缩放所有背景图片到新窗口大小
    Game.backgroundImage = pygame.image.load('image/sky.png')
    Game.backgroundImage = pygame.transform.scale(Game.backgroundImage, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.backgroundImage2 = pygame.image.load('image/fucksky.png')
    Game.backgroundImage2 = pygame.transform.scale(Game.backgroundImage2, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.backgroundImage3 = pygame.image.load('image/boss2.png')
    Game.backgroundImage3 = pygame.transform.scale(Game.backgroundImage3, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.boss2r = pygame.image.load('image/boss2r.png')
    Game.boss2r = pygame.transform.scale(Game.boss2r, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.boss1 = pygame.image.load('image/boss1.png')
    Game.boss1 = pygame.transform.scale(Game.boss1, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.boss3 = pygame.image.load('image/boss3.png')
    Game.boss3 = pygame.transform.scale(Game.boss3, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.boss3r = pygame.image.load('image/boss3r.png')
    Game.boss3r = pygame.transform.scale(Game.boss3r, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.boss1r = pygame.image.load('image/boss1r.png')
    Game.boss1r = pygame.transform.scale(Game.boss1r, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.boss4 = pygame.image.load('image/boss4.png')
    Game.boss4 = pygame.transform.scale(Game.boss4, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.boss4r = pygame.image.load('image/boss4r.png')
    Game.boss4r = pygame.transform.scale(Game.boss4r, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.boss5 = pygame.image.load('image/boss5.png')
    Game.boss5 = pygame.transform.scale(Game.boss5, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.boss5r = pygame.image.load('image/boss5r.png')
    Game.boss5r = pygame.transform.scale(Game.boss5r, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.boss6 = pygame.image.load('image/boss6.png')
    Game.boss6 = pygame.transform.scale(Game.boss6, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.boss6r = pygame.image.load('image/boss6r.png')
    Game.boss6r = pygame.transform.scale(Game.boss6r, (WINDOWWIDTH, WINDOWHEIGHT))

    # 加载所有6个关卡的道中背景（正常和时停）
    Game.back1 = pygame.image.load('image/back1.png')
    Game.back1 = pygame.transform.scale(Game.back1, (WINDOWWIDTH, WINDOWHEIGHT))
    Game.back1r = pygame.image.load('image/back1r.png')
    Game.back1r = pygame.transform.scale(Game.back1r, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.back2 = pygame.image.load('image/back2.png')
    Game.back2 = pygame.transform.scale(Game.back2, (WINDOWWIDTH, WINDOWHEIGHT))
    Game.back2r = pygame.image.load('image/back2r.png')
    Game.back2r = pygame.transform.scale(Game.back2r, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.back3 = pygame.image.load('image/back3.png')
    Game.back3 = pygame.transform.scale(Game.back3, (WINDOWWIDTH, WINDOWHEIGHT))
    Game.back3r = pygame.image.load('image/back3r.png')
    Game.back3r = pygame.transform.scale(Game.back3r, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.back4 = pygame.image.load('image/back4.png')
    Game.back4 = pygame.transform.scale(Game.back4, (WINDOWWIDTH, WINDOWHEIGHT))
    Game.back4r = pygame.image.load('image/back4r.png')
    Game.back4r = pygame.transform.scale(Game.back4r, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.back5 = pygame.image.load('image/back5.png')
    Game.back5 = pygame.transform.scale(Game.back5, (WINDOWWIDTH, WINDOWHEIGHT))
    Game.back5r = pygame.image.load('image/back5r.png')
    Game.back5r = pygame.transform.scale(Game.back5r, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.back6 = pygame.image.load('image/back6.png')
    Game.back6 = pygame.transform.scale(Game.back6, (WINDOWWIDTH, WINDOWHEIGHT))
    Game.back6r = pygame.image.load('image/back6r.png')
    Game.back6r = pygame.transform.scale(Game.back6r, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.bulluten.append(pygame.image.load('image/bossbullut-1.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-2.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-3.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-4.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-5.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-6.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-7.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-8.png'))
    Game.bulluten.append(pygame.image.load('image/enemybullut-1.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-9.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-10.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-11.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-12.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-13.png'))
    Game.bulluten.append(pygame.image.load('image/bossbullut-14.png'))
    Game.special = pygame.image.load('image/waterbullut2.png')

    # 缩放UI图片
    gameoverImage = pygame.image.load('image/gameover.png')
    gameoverImage = pygame.transform.scale(gameoverImage, (WINDOWWIDTH, WINDOWHEIGHT))

    Game.gamepauseImage = pygame.image.load('image/gamepause.png')
    Game.gamepauseImage = pygame.transform.scale(Game.gamepauseImage, (WINDOWWIDTH, WINDOWHEIGHT))

    startImage = pygame.image.load('image/start.png')
    # start.png是10x10的小图标，不需要缩放，保持原始大小
    # startImage = pygame.transform.scale(startImage, (WINDOWWIDTH, WINDOWHEIGHT))  # 移除错误的缩放

    gamestartImage = pygame.image.load('image/gamestart.png')
    gamestartImage = pygame.transform.scale(gamestartImage, (WINDOWWIDTH, WINDOWHEIGHT))

    # 增大字体以适应更大窗口（2倍）
    font = pygame.font.SysFont(None, 96)  # 调整到1.5倍（原来64）
    font1 = pygame.font.SysFont('arial', 12)  # 减小字体避免遮挡视野（从18减到12）
    font2 = pygame.font.SysFont(None, 30)  # 调整到1.5倍（原来20）
    screen.blit(gamestartImage, (0, 0))
    pygame.display.update()
    imagetime = time.time()  # 换背景图片的背景
    tl = pygame.time.Clock()
    tl.tick(Game.FPS)
    Game.waitForKeyPress()
    Game.gameinit()

    # 初始化关卡系统
    from StageSystem import StageSystem
    Game.stage_system = StageSystem()

    lastestTime = time.time()
    starttime = time.time()
    hwnd = pygame.display.get_wm_info()['window']
    rect = win32gui.GetWindowRect(hwnd)
    Game.rx = rect[0]
    Game.ry = rect[1]
    # 保存原始窗口位置
    Game.original_window_x = rect[0]
    Game.original_window_y = rect[1]
    maxEmemies = 2
    maxBoss = 1
    choose = 1  # 选择背景图片，正为原图，反为反相
    Game.lastBoss = time.time()
    randomkis = 55 + 10 * random.random()
    # 播放Stage 1的道中BGM
    Game.bgmnow = 0  # Stage 1对应bgm1.mp3 (索引0)
    Game.Bgm[Game.bgmnow].play(loops=-1)

    # 用于BGM切换的标志
    current_bgm_name = None

    while True:  # 主循环
        # 更新关卡系统
        if Game.stage_system:
            Game.stage_system.update()

            # 检查是否通关
            if Game.stage_system.is_game_cleared():
                # 显示通关画面
                screen.fill((0, 0, 0))
                victory_font = pygame.font.SysFont('arial', 72, bold=True)
                victory_text = victory_font.render('GAME CLEAR!', True, (255, 215, 0))
                text_rect = victory_text.get_rect(center=(WINDOWWIDTH // 2, WINDOWHEIGHT // 2 - 100))
                screen.blit(victory_text, text_rect)

                score_font = pygame.font.SysFont('arial', 48)
                score_text = score_font.render(f'Final Score: {Game.score}', True, (255, 255, 255))
                score_rect = score_text.get_rect(center=(WINDOWWIDTH // 2, WINDOWHEIGHT // 2))
                screen.blit(score_text, score_rect)

                time_text = score_font.render(f'Time: {int(time.time() - starttime)}s', True, (255, 255, 255))
                time_rect = time_text.get_rect(center=(WINDOWWIDTH // 2, WINDOWHEIGHT // 2 + 60))
                screen.blit(time_text, time_rect)

                pygame.display.update()
                time.sleep(5)
                # 重置游戏或退出
                pygame.quit()
                sys.exit()

            # BGM切换逻辑（只在道中阶段处理，Boss BGM由Event.createBoss()处理）
            from StageSystem import StagePhase
            if Game.stage_system.current_phase == StagePhase.STAGE:
                desired_bgm = Game.stage_system.get_current_bgm()
                if desired_bgm != current_bgm_name:
                    # 停止当前所有BGM
                    for bgm in Game.Bgm:
                        bgm.stop()
                    Game.Aleph.stop()
                    Game.Boardline.stop()
                    Game.temp.stop()
                    Game.boss4bgm.stop()
                    Game.boss5bgm.stop()
                    Game.boss6bgm.stop()

                    # 播放道中BGM
                    bgm_index = Game.stage_system.current_stage - 1
                    if 0 <= bgm_index < len(Game.Bgm):
                        Game.Bgm[bgm_index].play(loops=-1)
                        current_bgm_name = desired_bgm
            elif Game.stage_system.current_phase == StagePhase.BOSS:
                # Boss阶段：标记BGM已切换（由Event.createBoss()播放Boss BGM）
                desired_bgm = Game.stage_system.get_current_bgm()
                if desired_bgm != current_bgm_name:
                    current_bgm_name = desired_bgm
            elif Game.stage_system.current_phase == StagePhase.CLEAR:
                # 通关阶段：BGM已在Event.bossDeath()中播放，这里只更新标记
                desired_bgm = Game.stage_system.get_current_bgm()
                if desired_bgm != current_bgm_name:
                    current_bgm_name = desired_bgm

        # 背景显示逻辑：根据关卡系统或Boss状态选择背景
        if Game.haveBoss:
            # Boss战背景
            if Game.boss.bossrint == 1:  # Boss1闪烁效果
                if time.time() - imagetime >= 0.677:
                    imagetime = time.time()
                    choose = -choose
                if choose > 0:
                    screen.blit(Game.boss1, (0, 0))
                elif choose < 0:
                    screen.blit(Game.boss1r, (0, 0))
            elif Game.boss.bossrint == 2:  # Boss2心形传送门效果
                if Game.istimestoptime:
                    screen.blit(Game.boss2r, (0, 0))
                else:
                    screen.blit(Game.backgroundImage3, (0, 0))
                try:
                    Game.showPrevent(screen)
                except IndexError:
                    pass
            elif Game.boss.bossrint == 3:
                if Game.istimestoptime:
                    screen.blit(Game.boss3r, (0, 0))
                else:
                    screen.blit(Game.boss3, (0, 0))
            elif Game.boss.bossrint == 4:
                if Game.istimestoptime:
                    screen.blit(Game.boss4r, (0, 0))
                else:
                    screen.blit(Game.boss4, (0, 0))
            elif Game.boss.bossrint == 5:
                if Game.istimestoptime:
                    screen.blit(Game.boss5r, (0, 0))
                else:
                    screen.blit(Game.boss5, (0, 0))
            elif Game.boss.bossrint == 6:
                if Game.istimestoptime:
                    screen.blit(Game.boss6r, (0, 0))
                else:
                    screen.blit(Game.boss6, (0, 0))
        else:
            # 道中背景：根据关卡系统选择
            if Game.stage_system:
                stage = Game.stage_system.current_stage
                background_map = {
                    1: (Game.back1, Game.back1r),
                    2: (Game.back2, Game.back2r),
                    3: (Game.back3, Game.back3r),
                    4: (Game.back4, Game.back4r),
                    5: (Game.back5, Game.back5r),
                    6: (Game.back6, Game.back6r),
                }
                if stage in background_map:
                    bg_normal, bg_timestop = background_map[stage]
                    if Game.istimestoptime:
                        screen.blit(bg_timestop, (0, 0))
                    else:
                        screen.blit(bg_normal, (0, 0))
                else:
                    # 默认背景
                    screen.blit(Game.backgroundImage, (0, 0))
            else:
                # 兼容旧版：使用默认背景
                screen.blit(Game.backgroundImage, (0, 0))

        screen.blit(startImage, (0, 0))
        if Game.haveBoss:
            Game.drawBoss()
        # 调整UI文字位置（2倍大小）
        Game.drawText('score:%s' % (Game.score), font1, screen, 80, 20)
        Game.drawText('money:%s' % (Game.money), font1, screen, 80, 60)
        Game.drawText('gametime:%s' % (int(time.time() - starttime)), font1, screen, 1080, 20)

        # 显示关卡信息
        if Game.stage_system:
            stage_info = Game.stage_system.get_stage_info()
            Game.drawText(stage_info, font1, screen, 1080, 60)

            # 显示道中进度（只在道中阶段显示）
            from StageSystem import StagePhase
            if Game.stage_system.current_phase == StagePhase.STAGE:
                remaining = Game.stage_system.get_stage_remaining_time()
                Game.drawText(f'Boss in: {remaining}s', font1, screen, 1080, 100)
        else:
            # 兼容旧版：显示波次
            if Game.current_wave > 1:
                Game.drawText('Wave:%s' % Game.current_wave, font1, screen, 1080, 60)

        # 显示新功能：炸弹、护盾、连击（如果有的话）
        if hasattr(Game.wateremoji, 'bombs'):
            Game.drawText('Bombs:%s' % Game.wateremoji.bombs, font1, screen, 80, 100)
        if hasattr(Game.wateremoji, 'shield'):
            Game.drawText('Shield:%s' % Game.wateremoji.shield, font1, screen, 80, 140)

        # 显示当前武器
        if Game.weapon_system:
            weapon_name = Game.weapon_system.current_weapon.upper()
            Game.drawText('Weapon:%s' % weapon_name, font1, screen, 80, 180)

        # 显示连击和倍率
        if Game.score_system:
            combo = Game.score_system.combo_system.combo
            if combo > 0:
                multiplier = Game.score_system.combo_system.get_multiplier()
                Game.drawText('COMBO:%sx (x%.1f)' % (combo, multiplier), font1, screen, 1000, 100)
                # 显示连击等级名称
                level_name = Game.score_system.combo_system.get_combo_level_name()
                if level_name:
                    Game.drawText(level_name, font, screen, 950, 140)

        # 显示成就解锁通知（屏幕中上方）
        if Game.achievement_notifications:
            current_time = time.time()
            # 移除超过3秒的通知
            Game.achievement_notifications = [(name, unlock_time) for name, unlock_time in Game.achievement_notifications if current_time - unlock_time < 3]

            # 显示当前通知（最多显示3个）
            for i, (achievement_name, unlock_time) in enumerate(Game.achievement_notifications[:3]):
                # 闪烁效果
                alpha = int(255 * (1 - (current_time - unlock_time) / 3))
                if int(current_time * 4) % 2 == 0:  # 快速闪烁
                    achievement_font = pygame.font.SysFont('arial', 24, bold=True)
                    achievement_text = achievement_font.render('★ ' + achievement_name + ' ★', True, (255, 215, 0))
                    text_rect = achievement_text.get_rect(center=(WINDOWWIDTH // 2, 150 + i * 40))
                    screen.blit(achievement_text, text_rect)

        keylist = pygame.key.get_pressed()
        Game.keyEvent(screen, keylist, Game.gamepauseImage)
        interval = time.time() - lastestTime
        Game.showLife(font2, screen)
        Game.showPower()

        # 更新新系统状态
        if hasattr(Game.wateremoji, 'update_bomb'):
            Game.wateremoji.update_bomb()
        if hasattr(Game.wateremoji, 'update_dash'):
            Game.wateremoji.update_dash()
        # 更新武器系统子弹
        if Game.weapon_system:
            Game.weapon_system.update_bullets(Game.wateremoji.allbumb)
        # 更新分数和连击系统
        if Game.score_system:
            Game.score_system.update()
        # 更新Boss增强管理器
        if Game.boss_enhancement_manager:
            Game.boss_enhancement_manager.update()

        if time.time() - starttime <= randomkis:
            maxEmemies = int(2 + 1 / 15 * (time.time() - starttime))
            Game.maxEn = maxEmemies
        if interval >= 10 * random.random() and len(Game.g_enemies) < maxEmemies and Game.haveBoss is False:
            Game.createEnemy(0)
            lastestTime = time.time()
            # 增加波次计数
            Game.current_wave += 1

            # 波次系统：每10波生成MiniBoss，每5波生成EliteEnemy
            try:
                from EmojiAll.NewEnemyTypes import MiniBoss, EliteEnemy
                import main as main_module

                if Game.current_wave % 10 == 0:
                    # 每10波生成1个MiniBoss
                    mini_boss = MiniBoss()
                    mini_boss.x = main_module.WINDOWWIDTH + random.randint(50, 150)
                    mini_boss.y = random.randint(100, main_module.WINDOWHEIGHT - 100)
                    mini_boss.direction = 'left'
                    Game.g_enemies.append(mini_boss)
                elif Game.current_wave % 5 == 0:
                    # 每5波生成2个EliteEnemy
                    for i in range(2):
                        elite = EliteEnemy()
                        elite.x = main_module.WINDOWWIDTH + i * 150
                        elite.y = random.randint(100, main_module.WINDOWHEIGHT - 100)
                        elite.direction = 'left'
                        Game.g_enemies.append(elite)
            except ImportError:
                pass  # 如果NewEnemyTypes不存在，跳过
        # 关卡系统：检查是否应该生成Boss
        if Game.stage_system:
            from StageSystem import StagePhase
            # 进入Boss阶段且还没有Boss时，生成Boss
            if Game.stage_system.current_phase == StagePhase.BOSS and not Game.haveBoss:
                Game.createBoss()
                Game.bosscreatetime = time.time()
                if Game.boss.bossrint == 2:
                    Skill.BossSkillSecond.createFrame()
                if Game.boss.bossrint == 3:
                    t1 = threading.Thread(target=Skill.BossSkillThird.teleport)
                    t1.daemon = True
                    t1.start()
                    t2 = threading.Thread(target=Skill.BossSkillThird.moveFrameThird)
                    t2.daemon = True
                    t2.start()
        else:
            # 兼容旧版：随机时间生成Boss
            if time.time() - Game.lastBoss >= random.randint(50, 60) and Game.haveBoss is False:
                Game.createBoss()
                Game.bosscreatetime = time.time()
                if Game.boss.bossrint == 2:
                    Skill.BossSkillSecond.createFrame()
                if Game.boss.bossrint == 3:
                    t1 = threading.Thread(target=Skill.BossSkillThird.teleport)
                    t1.daemon = True
                    t1.start()
                    t2 = threading.Thread(target=Skill.BossSkillThird.moveFrameThird)
                    t2.daemon = True
                    t2.start()

        if Game.haveBoss is True:
            Game.bossUseSkill()
        # 优化：移除不必要的线程，直接调用射击函数
        Game.shoot(screen)
        if Skill.BossSkillSecond.hasAttr:  # 如果有心形传送门就把它画出来
            Game.showAttr(screen)
        Game.updateLocation()
        try:
            Game.draw(screen)
        except pygame.error:
            pass
        Game.supplyMove(screen)
        Game.getEffect()
        # 优化：移除不必要的线程，直接调用敌人射击函数
        Game.enshoot(screen)

        # Boss6第二阶段：颜色覆盖层
        if Game.haveBoss and Game.boss.bossrint == 6:
            color_overlay = Skill.BossSkillSixth.get_color_overlay()
            if color_overlay:
                screen.blit(color_overlay, (0, 0))

        # Boss6第三阶段：半透明效果
        if Game.haveBoss and Game.boss.bossrint == 6 and Skill.BossSkillSixth.transparency_active:
            # 创建半透明覆盖层
            transparent_overlay = pygame.Surface((WINDOWWIDTH, WINDOWHEIGHT))
            transparent_overlay.fill((255, 255, 255))
            transparent_overlay.set_alpha(128)
            screen.blit(transparent_overlay, (0, 0))

        pygame.display.update()
        tl.tick(Game.FPS)
        if Game.gameover() or Game.isok:
            time.sleep(1)
            screen.blit(gameoverImage, (0, 0))
            # 调整游戏结束文字位置（2倍大小）
            Game.drawText('score: %s' % (Game.score), font, screen, 340, 440)
            Game.drawText('best: %s' % (bestscore), font, screen, 340, 640)

            # 安全地更新数据库（使用参数化查询防止SQL注入）
            try:
                if (Game.score > bestscore):
                    curor.execute('UPDATE user SET name = ? WHERE id = ?', (int(Game.score), 1))
                curor.execute('UPDATE user SET name = ? WHERE id = ?', (int(Game.money), 2))
                data.commit()
            except sqlite3.Error as e:
                print(f"保存数据失败: {e}")
            finally:
                curor.close()
                data.close()

            pygame.display.update()
            Game.waitForKeyPress()
            break
