"""
关卡系统 - 类似东方Project
6个关卡，每个关卡包含道中（打小怪）和Boss战
"""
import time
import pygame


class StagePhase:
    """关卡阶段枚举"""
    STAGE = 0  # 道中阶段（打小怪）
    BOSS = 1   # Boss战阶段
    CLEAR = 2  # 关卡通过


class StageSystem:
    """关卡系统管理器"""

    def __init__(self):
        self.current_stage = 1  # 当前关卡（1-6）
        self.current_phase = StagePhase.STAGE  # 当前阶段
        self.total_stages = 6  # 总关卡数

        # 道中计时器
        self.stage_start_time = time.time()
        self.stage_duration = 60  # 道中持续60秒

        # Boss相关
        self.boss_defeated = False
        self.stage_clear_time = 0
        self.stage_clear_delay = 3  # 通关后延迟3秒

        # BGM管理
        self.current_bgm = None
        self.bgm_loaded = False

    def get_stage_bgm(self):
        """获取当前关卡道中BGM路径"""
        return f'music/bgm{self.current_stage}.mp3'

    def get_boss_bgm(self):
        """获取当前关卡Boss BGM路径"""
        return f'music/boss{self.current_stage}.mp3'

    def get_stage_background(self, is_timestop=False):
        """获取当前关卡道中背景路径"""
        suffix = 'r' if is_timestop else ''
        return f'image/back{self.current_stage}{suffix}.png'

    def get_boss_background(self, is_timestop=False):
        """获取当前关卡Boss背景路径"""
        suffix = 'r' if is_timestop else ''
        return f'image/boss{self.current_stage}{suffix}.png'

    def get_current_background(self, is_timestop=False):
        """获取当前背景路径"""
        if self.current_phase == StagePhase.STAGE:
            return self.get_stage_background(is_timestop)
        else:
            return self.get_boss_background(is_timestop)

    def get_current_bgm(self):
        """获取当前应该播放的BGM路径"""
        if self.current_phase == StagePhase.STAGE:
            return self.get_stage_bgm()
        else:
            return self.get_boss_bgm()

    def update(self):
        """更新关卡状态"""
        if self.current_phase == StagePhase.STAGE:
            # 道中阶段：检查是否应该进入Boss战
            elapsed_time = time.time() - self.stage_start_time
            if elapsed_time >= self.stage_duration:
                self.enter_boss_phase()

        elif self.current_phase == StagePhase.BOSS:
            # Boss阶段：等待Boss被击败
            if self.boss_defeated:
                self.current_phase = StagePhase.CLEAR
                self.stage_clear_time = time.time()

        elif self.current_phase == StagePhase.CLEAR:
            # 通关阶段：延迟后进入下一关
            if time.time() - self.stage_clear_time >= self.stage_clear_delay:
                self.next_stage()

    def enter_boss_phase(self):
        """进入Boss战阶段"""
        self.current_phase = StagePhase.BOSS
        self.boss_defeated = False
        print(f"Stage {self.current_stage}: Boss战开始！")

    def on_boss_defeated(self):
        """Boss被击败时调用"""
        self.boss_defeated = True
        print(f"Stage {self.current_stage}: Boss击败！")

    def next_stage(self):
        """进入下一关"""
        if self.current_stage < self.total_stages:
            self.current_stage += 1
            self.current_phase = StagePhase.STAGE
            self.stage_start_time = time.time()
            self.boss_defeated = False
            self.bgm_loaded = False
            print(f"进入Stage {self.current_stage}")
        else:
            # 已经通关所有关卡
            print("恭喜通关！")

    def is_game_cleared(self):
        """检查是否已经通关（打败最后一个Boss）"""
        return self.current_stage > self.total_stages or (
            self.current_stage == self.total_stages and
            self.current_phase == StagePhase.CLEAR
        )

    def get_stage_progress(self):
        """获取道中进度（0-100）"""
        if self.current_phase != StagePhase.STAGE:
            return 100
        elapsed_time = time.time() - self.stage_start_time
        return min(100, int((elapsed_time / self.stage_duration) * 100))

    def get_stage_remaining_time(self):
        """获取道中剩余时间（秒）"""
        if self.current_phase != StagePhase.STAGE:
            return 0
        elapsed_time = time.time() - self.stage_start_time
        remaining = self.stage_duration - elapsed_time
        return max(0, int(remaining))

    def reset(self):
        """重置关卡系统（重新开始游戏）"""
        self.current_stage = 1
        self.current_phase = StagePhase.STAGE
        self.stage_start_time = time.time()
        self.boss_defeated = False
        self.bgm_loaded = False
        print("关卡系统重置")

    def get_stage_info(self):
        """获取关卡信息文本"""
        phase_text = {
            StagePhase.STAGE: "道中",
            StagePhase.BOSS: "Boss战",
            StagePhase.CLEAR: "通过"
        }
        return f"Stage {self.current_stage}/{self.total_stages} - {phase_text[self.current_phase]}"
