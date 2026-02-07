import Skill, random, time, threading


class Skills:
    lastskilltime = 0
    boss6_phase_skills = {
        1: [],  # 第一阶段技能列表
        2: [],  # 第二阶段技能列表
        3: [],  # 第三阶段技能列表
        4: [],  # 第四阶段技能列表
        5: []   # 第五阶段技能列表
    }

    @classmethod
    def FirstBossSkill(cls):
        Skill.BossSkillFirst.melySkill()
        if time.time() - cls.lastskilltime >= random.randint(4, 8):
            randoms = random.random()
            if randoms < 0.125:
                newthread = threading.Thread(target=Skill.BossSkillFirst.sandShoot)
            elif 0.125 <= randoms < 0.25:
                newthread = threading.Thread(target=Skill.BossSkillFirst.summonTeleport)
            elif 0.25 <= randoms < 0.375:
                newthread = threading.Thread(target=Skill.BossSkillFirst.shootaside)
            elif 0.375 <= randoms < 0.5:
                newthread = threading.Thread(target=Skill.BossSkillFirst.starShoot)
            elif 0.5 <= randoms < 0.625:
                newthread = threading.Thread(target=Skill.BossSkillFirst.mirrorShoot)
            elif 0.625 <= randoms < 0.75:
                newthread = threading.Thread(target=Skill.BossSkillFirst.blackHole)
            elif 0.75 <= randoms < 0.875:
                newthread = threading.Thread(target=Skill.BossSkillFirst.lightningChain)
            else:
                newthread = threading.Thread(target=Skill.BossSkillFirst.spiralTrap)
            cls.lastskilltime = time.time()
            newthread.daemon = True
            newthread.start()

    @classmethod
    def SecondBossSkill(cls):
        if time.time() - cls.lastskilltime >= random.randint(4, 8):
            Skill.BossSkillSecond.createPrevent()
            randoms = random.random()
            if randoms > 0.75:
                newthread = threading.Thread(target=Skill.BossSkillSecond.generateLove)
            elif 0.625 < randoms <= 0.75:
                newthread = threading.Thread(target=Skill.BossSkillSecond.useAttract)
            elif 0.5 < randoms <= 0.625:
                newthread = threading.Thread(target=Skill.BossSkillSecond.madeinheaven)
            elif 0.375 < randoms <= 0.5:
                newthread = threading.Thread(target=Skill.BossSkillSecond.heartRain)
            elif 0.25 < randoms <= 0.375:
                newthread = threading.Thread(target=Skill.BossSkillSecond.reverseTime)
            elif 0.125 < randoms <= 0.25:
                newthread = threading.Thread(target=Skill.BossSkillSecond.heartTrap)
            else:
                newthread = threading.Thread(target=Skill.BossSkillSecond.splitBomb)
            newthread.daemon = True
            newthread.start()
            cls.lastskilltime = time.time()

    @classmethod
    def ThirdBossSkill(cls):
        if time.time() - cls.lastskilltime >= random.randint(4, 8):
            # 防御屏障是Boss2专属技能，Boss3不需要
            randoms = random.random()
            if randoms < 0.143:
                newthread = threading.Thread(target=Skill.BossSkillThird.setgold)
                newthread.daemon = True
                newthread.start()
            elif 0.143 <= randoms < 0.286:
                newthread = threading.Thread(target=Skill.BossSkillThird.cutBody)
                newthread.daemon = True
                newthread.start()
            elif 0.286 <= randoms < 0.429:
                Skill.BossSkillThird.timestop()
            elif 0.429 <= randoms < 0.572:
                newthread = threading.Thread(target=Skill.BossSkillThird.superShoot)
                newthread.daemon = True
                newthread.start()
            elif 0.572 <= randoms < 0.715:
                newthread = threading.Thread(target=Skill.BossSkillThird.goldenStorm)
                newthread.daemon = True
                newthread.start()
            elif 0.715 <= randoms < 0.858:
                newthread = threading.Thread(target=Skill.BossSkillThird.timeBubble)
                newthread.daemon = True
                newthread.start()
            else:
                newthread = threading.Thread(target=Skill.BossSkillThird.coinBarrage)
                newthread.daemon = True
                newthread.start()
            cls.lastskilltime = time.time()

    @classmethod
    def ForthBossSkill(cls):
        if time.time() - cls.lastskilltime >= random.randint(4, 8):
            # 防御屏障是Boss2专属技能，Boss4不需要
            randoms = random.random()
            if randoms < 0.143:
                th = threading.Thread(target=Skill.BossSkillForth.lightshoot)
                th.daemon = True
                th.start()
            elif 0.143 <= randoms < 0.286:
                th = threading.Thread(target=Skill.BossSkillForth.dragShoot)
                th.daemon = True
                th.start()
            elif 0.286 <= randoms < 0.429:
                th = threading.Thread(target=Skill.BossSkillForth.summonUFO)
                th.daemon = True
                th.start()
            elif 0.429 <= randoms < 0.572:
                th = threading.Thread(target=Skill.BossSkillForth.sideShoot)
                th.daemon = True
                th.start()
            elif 0.572 <= randoms < 0.715:
                th = threading.Thread(target=Skill.BossSkillForth.screenStatic)
                th.daemon = True
                th.start()
            elif 0.715 <= randoms < 0.858:
                th = threading.Thread(target=Skill.BossSkillForth.orbitalStrike)
                th.daemon = True
                th.start()
            else:
                th = threading.Thread(target=Skill.BossSkillForth.pixelStorm)
                th.daemon = True
                th.start()
            cls.lastskilltime = time.time()

    @classmethod
    def FifthBossSkill(cls):
        if time.time() - cls.lastskilltime >= random.randint(4, 8):
            # 防御屏障是Boss2专属技能，Boss5不需要
            randoms = random.random()
            if randoms < 0.167:
                th = threading.Thread(target=Skill.BossSkillFifth.throwTNT)
                th.daemon = True
                th.start()
            elif 0.167 <= randoms < 0.334:
                th = threading.Thread(target=Skill.BossSkillFifth.jumpShoot)
                th.daemon = True
                th.start()
            elif 0.334 <= randoms < 0.501:
                th = threading.Thread(target=Skill.BossSkillFifth.healMode)
                th.daemon = True
                th.start()
            elif 0.501 <= randoms < 0.668:
                th = threading.Thread(target=Skill.BossSkillFifth.chainExplosion)
                th.daemon = True
                th.start()
            elif 0.668 <= randoms < 0.835:
                th = threading.Thread(target=Skill.BossSkillFifth.gravitySink)
                th.daemon = True
                th.start()
            else:
                th = threading.Thread(target=Skill.BossSkillFifth.mirrorTNT)
                th.daemon = True
                th.start()
            cls.lastskilltime = time.time()

    @classmethod
    def SixthBossSkill(cls):
        """Boss6五阶段技能系统"""
        import Event

        # 获取当前阶段
        current_phase = Skill.BossSkillSixth.get_current_phase()

        # 第一阶段专属：启动窗口震动、激光和火焰雨
        if current_phase == 1:
            # 启动第一阶段的持续技能（只启动一次）
            if not hasattr(Skill.BossSkillSixth, '_phase1_started'):
                Skill.BossSkillSixth._phase1_started = True
                threading.Thread(target=Skill.BossSkillSixth.phase1_window_shake, daemon=True).start()
                threading.Thread(target=Skill.BossSkillSixth.phase1_left_laser, daemon=True).start()
                threading.Thread(target=Skill.BossSkillSixth.phase1_fire_rain, daemon=True).start()

            # 释放随机技能
            if time.time() - cls.lastskilltime >= random.randint(4, 7):
                randoms = random.random()
                if randoms < 0.25:
                    threading.Thread(target=Skill.BossSkillSixth.phase1_spiral_attack, daemon=True).start()
                elif randoms < 0.5:
                    threading.Thread(target=Skill.BossSkillSixth.phase1_cross_laser, daemon=True).start()
                elif randoms < 0.75:
                    threading.Thread(target=Skill.BossSkillSixth.phase1_fire_pillar, daemon=True).start()
                else:
                    threading.Thread(target=Skill.BossSkillSixth.phase1_laser_web, daemon=True).start()
                cls.lastskilltime = time.time()

        # 第二阶段：颜色变化、锥形弹幕、瞬移
        elif current_phase == 2:
            # 从第一阶段切换过来时的清理
            if hasattr(Skill.BossSkillSixth, '_phase1_started'):
                del Skill.BossSkillSixth._phase1_started
            if Skill.BossSkillSixth.window_shake_active:
                Skill.BossSkillSixth.window_shake_active = False
                # 回到原点
                import Move
                Move.moveWin(Event.Game.rx, Event.Game.ry)

            # 启动持续技能
            if not hasattr(Skill.BossSkillSixth, '_phase2_started'):
                Skill.BossSkillSixth._phase2_started = True
                threading.Thread(target=Skill.BossSkillSixth.phase2_color_shift, daemon=True).start()
                threading.Thread(target=Skill.BossSkillSixth.phase2_cone_shot, daemon=True).start()
                threading.Thread(target=Skill.BossSkillSixth.phase2_boss_teleport, daemon=True).start()

            # 释放随机技能
            if time.time() - cls.lastskilltime >= random.randint(3, 6):
                randoms = random.random()
                if randoms < 0.2:
                    threading.Thread(target=Skill.BossSkillSixth.phase2_wave_attack, daemon=True).start()
                elif randoms < 0.4:
                    threading.Thread(target=Skill.BossSkillSixth.phase2_tracking_bullets, daemon=True).start()
                elif randoms < 0.6:
                    threading.Thread(target=Skill.BossSkillSixth.phase2_meteor_shower, daemon=True).start()
                elif randoms < 0.8:
                    threading.Thread(target=Skill.BossSkillSixth.phase2_mirror_boss, daemon=True).start()
                else:
                    threading.Thread(target=Skill.BossSkillSixth.phase2_homing_wave, daemon=True).start()
                cls.lastskilltime = time.time()

        # 第三阶段：外星人、反弹子弹、半透明
        elif current_phase == 3:
            # 从第二阶段切换过来时的清理
            if hasattr(Skill.BossSkillSixth, '_phase2_started'):
                del Skill.BossSkillSixth._phase2_started
                # 确保窗口在原点
                import Move
                Move.moveWin(Event.Game.rx, Event.Game.ry)

            # 启动持续技能
            if not hasattr(Skill.BossSkillSixth, '_phase3_started'):
                Skill.BossSkillSixth._phase3_started = True
                Skill.BossSkillSixth.phase3_transparency()
                threading.Thread(target=Skill.BossSkillSixth.phase3_alien_summon, daemon=True).start()
                threading.Thread(target=Skill.BossSkillSixth.phase3_bounce_bullets, daemon=True).start()

            # 释放随机技能
            if time.time() - cls.lastskilltime >= random.randint(4, 8):
                randoms = random.random()
                if randoms < 0.25:
                    threading.Thread(target=Skill.BossSkillSixth.phase3_circle_trap, daemon=True).start()
                elif randoms < 0.5:
                    threading.Thread(target=Skill.BossSkillSixth.phase3_laser_grid, daemon=True).start()
                elif randoms < 0.75:
                    threading.Thread(target=Skill.BossSkillSixth.phase3_dimension_rift, daemon=True).start()
                else:
                    threading.Thread(target=Skill.BossSkillSixth.phase3_prismatic_beam, daemon=True).start()
                cls.lastskilltime = time.time()

        # 第四阶段：窗口闪现、混沌弹幕、双激光（最难）
        elif current_phase == 4:
            # 从第三阶段切换过来时的清理
            if hasattr(Skill.BossSkillSixth, '_phase3_started'):
                del Skill.BossSkillSixth._phase3_started
                Skill.BossSkillSixth.transparency_active = False
                # 确保窗口在原点再开始闪现
                import Move
                Move.moveWin(Event.Game.rx, Event.Game.ry)

            # 启动持续技能
            if not hasattr(Skill.BossSkillSixth, '_phase4_started'):
                Skill.BossSkillSixth._phase4_started = True
                threading.Thread(target=Skill.BossSkillSixth.phase4_window_teleport, daemon=True).start()
                threading.Thread(target=Skill.BossSkillSixth.phase4_chaos_bullets, daemon=True).start()
                threading.Thread(target=Skill.BossSkillSixth.phase4_right_dual_laser, daemon=True).start()

            # 第四阶段持续释放技能
            if time.time() - cls.lastskilltime >= random.randint(2, 4):
                randoms = random.random()
                if randoms < 0.33:
                    threading.Thread(target=Skill.BossSkillSixth.phase4_spiral_hell, daemon=True).start()
                elif randoms < 0.66:
                    threading.Thread(target=Skill.BossSkillSixth.phase4_vortex_trap, daemon=True).start()
                else:
                    threading.Thread(target=Skill.BossSkillSixth.phase4_temporal_split, daemon=True).start()
                cls.lastskilltime = time.time()

        # 第五阶段：五角星、四方弹幕（终极阶段）
        elif current_phase == 5:
            if hasattr(Skill.BossSkillSixth, '_phase4_started'):
                del Skill.BossSkillSixth._phase4_started
                # 回到游戏启动时的原始位置
                import Move
                Move.moveWin(Event.Game.original_window_x, Event.Game.original_window_y)
                Event.Game.rx = Event.Game.original_window_x
                Event.Game.ry = Event.Game.original_window_y

            # 启动持续技能
            if not hasattr(Skill.BossSkillSixth, '_phase5_started'):
                Skill.BossSkillSixth._phase5_started = True
                Skill.BossSkillSixth.phase5_pentagram()
                Skill.BossSkillSixth.phase5_boss_speedup()
                threading.Thread(target=Skill.BossSkillSixth.phase5_four_direction_shot, daemon=True).start()

            # 释放随机技能
            if time.time() - cls.lastskilltime >= random.randint(3, 5):
                randoms = random.random()
                if randoms < 0.25:
                    threading.Thread(target=Skill.BossSkillSixth.phase5_star_burst, daemon=True).start()
                elif randoms < 0.5:
                    threading.Thread(target=Skill.BossSkillSixth.phase5_final_laser_cross, daemon=True).start()
                elif randoms < 0.75:
                    threading.Thread(target=Skill.BossSkillSixth.phase5_judgment_ray, daemon=True).start()
                else:
                    threading.Thread(target=Skill.BossSkillSixth.phase5_armageddon, daemon=True).start()
                cls.lastskilltime = time.time()
