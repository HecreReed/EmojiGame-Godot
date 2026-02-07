# 6关卡通关系统实现完成

## 系统概述

类似东方Project的6关卡通关系统已经完成！每个关卡包含：
- **道中阶段**（60秒）：打小怪，配有专属BGM和背景
- **Boss战阶段**：击败Boss，配有专属BGM和背景
- **通关判定**：击败6个Boss后显示通关画面

---

## 关卡结构

### 6个关卡配置

| 关卡 | 道中BGM | Boss BGM | 道中背景 | Boss背景 | Boss编号 |
|------|---------|----------|---------|----------|---------|
| Stage 1 | bgm1.mp3 | boss1.mp3 | back1.png/back1r.png | boss1.png/boss1r.png | Boss 1 |
| Stage 2 | bgm2.mp3 | boss2.mp3 | back2.png/back2r.png | boss2.png/boss2r.png | Boss 2 |
| Stage 3 | bgm3.mp3 | boss3.mp3 | back3.png/back3r.png | boss3.png/boss3r.png | Boss 3 |
| Stage 4 | bgm4.mp3 | boss4.mp3 | back4.png/back4r.png | boss4.png/boss4r.png | Boss 4 |
| Stage 5 | bgm5.mp3 | boss5.mp3 | back5.png/back5r.png | boss5.png/boss5r.png | Boss 5 |
| Stage 6 | bgm6.mp3 | boss6.mp3 | back6.png/back6r.png | boss6.png/boss6r.png | Boss 6 |

**注意**：r后缀表示时停状态下的反向背景

---

## 核心文件

### 1. **StageSystem.py** - 关卡管理系统 ✨

**关卡阶段枚举**：
- `StagePhase.STAGE` - 道中阶段
- `StagePhase.BOSS` - Boss战阶段
- `StagePhase.CLEAR` - 关卡通过

**主要功能**：
```python
class StageSystem:
    current_stage: int        # 当前关卡 (1-6)
    current_phase: StagePhase # 当前阶段
    stage_duration: int       # 道中持续时间 (60秒)

    def update()              # 更新关卡状态
    def get_current_bgm()     # 获取当前BGM路径
    def get_current_background() # 获取当前背景路径
    def on_boss_defeated()    # Boss被击败时调用
    def is_game_cleared()     # 检查是否通关
```

**关卡流程**：
1. Stage 1道中 (60秒) → Stage 1 Boss战 → 击败 → 3秒延迟
2. Stage 2道中 (60秒) → Stage 2 Boss战 → 击败 → 3秒延迟
3. ... 依此类推 ...
4. Stage 6 Boss战 → 击败 → **游戏通关**

---

### 2. **Event.py** - 游戏事件管理

**修改内容**：

#### 导入关卡系统
```python
from StageSystem import StageSystem, StagePhase
```

#### 添加关卡系统变量
```python
class Game:
    stage_system = None  # 关卡系统
```

#### 修改Boss创建 (createBoss)
```python
def createBoss(cls):
    # 根据关卡系统创建对应的Boss
    if cls.stage_system:
        boss_id = cls.stage_system.current_stage
    else:
        boss_id = (cls.bossdeathtimes % 6) + 1  # 兼容旧版

    newBoss = OEmoji.BossEmemy(boss_id)
    # ... 播放对应Boss BGM ...
```

#### 修改Boss死亡 (bossDeath)
```python
def bossDeath(cls, boss):
    # ... 符卡阶段处理 ...

    # 通知关卡系统Boss被击败
    if cls.stage_system:
        cls.stage_system.on_boss_defeated()
    else:
        # 兼容旧版：随机播放道中BGM
        cls.bgmnow = random.randint(0, 4)
        cls.Bgm[cls.bgmnow].play()
```

---

### 3. **BossEnemies.py** - Boss敌人类

**修改内容**：

```python
class BossEmemy(EmojiAll.Ememies.Enemy):
    def __init__(self, boss_id=None):
        # Boss顺序登场系统：根据传入的boss_id或击败次数决定Boss编号
        if boss_id is not None:
            self.bossrint = boss_id  # 使用关卡系统指定的Boss ID
        else:
            self.bossrint = ((Game.bossdeathtimes-1) % 6) + 1  # 兼容旧版
```

---

### 4. **main.py** - 主游戏循环

**修改内容总览**：

#### 4.1 BGM加载（统一管理）
```python
# Boss BGM
Game.Aleph = pygame.mixer.Sound('music/boss1.mp3')
Game.Boardline = pygame.mixer.Sound('music/boss2.mp3')
Game.temp = pygame.mixer.Sound('music/boss3.mp3')
Game.boss4bgm = pygame.mixer.Sound('music/boss4.mp3')
Game.boss5bgm = pygame.mixer.Sound('music/boss5.mp3')
Game.boss6bgm = pygame.mixer.Sound('music/boss6.mp3')

# 道中BGM（6个关卡）
Game.Bgm.append(pygame.mixer.Sound('music/bgm1.mp3'))
Game.Bgm.append(pygame.mixer.Sound('music/bgm2.mp3'))
Game.Bgm.append(pygame.mixer.Sound('music/bgm3.mp3'))
Game.Bgm.append(pygame.mixer.Sound('music/bgm4.mp3'))
Game.Bgm.append(pygame.mixer.Sound('music/bgm5.mp3'))
Game.Bgm.append(pygame.mixer.Sound('music/bgm6.mp3'))
```

#### 4.2 背景加载（6个关卡×2状态）
```python
# 道中背景（正常+时停）
Game.back1 / Game.back1r  # Stage 1
Game.back2 / Game.back2r  # Stage 2
Game.back3 / Game.back3r  # Stage 3
Game.back4 / Game.back4r  # Stage 4
Game.back5 / Game.back5r  # Stage 5
Game.back6 / Game.back6r  # Stage 6

# Boss背景（正常+时停）
Game.boss1 / Game.boss1r  # Boss 1
Game.boss2 / Game.boss2r  # Boss 2
Game.boss3 / Game.boss3r  # Boss 3
Game.boss4 / Game.boss4r  # Boss 4
Game.boss5 / Game.boss5r  # Boss 5
Game.boss6 / Game.boss6r  # Boss 6
```

#### 4.3 初始化关卡系统
```python
from StageSystem import StageSystem
Game.stage_system = StageSystem()

# 播放Stage 1的道中BGM
Game.bgmnow = 0
Game.Bgm[Game.bgmnow].play(loops=-1)
```

#### 4.4 主循环更新
```python
while True:
    # 1. 更新关卡系统
    if Game.stage_system:
        Game.stage_system.update()

        # 2. 检查通关
        if Game.stage_system.is_game_cleared():
            # 显示通关画面

        # 3. BGM切换
        desired_bgm = Game.stage_system.get_current_bgm()
        if desired_bgm != current_bgm_name:
            # 停止所有BGM，播放新BGM
```

#### 4.5 背景显示逻辑
```python
if Game.haveBoss:
    # Boss战背景（包含特殊效果）
    if Game.boss.bossrint == 1:  # Boss1闪烁
    elif Game.boss.bossrint == 2:  # Boss2心形传送门
    # ... 其他Boss ...
else:
    # 道中背景：根据关卡系统选择
    if Game.stage_system:
        stage = Game.stage_system.current_stage
        background_map = {
            1: (Game.back1, Game.back1r),
            2: (Game.back2, Game.back2r),
            # ... 其他关卡 ...
        }
        # 根据时停状态选择背景
```

#### 4.6 Boss生成逻辑
```python
# 关卡系统：检查是否应该生成Boss
if Game.stage_system:
    from StageSystem import StagePhase
    # 进入Boss阶段且还没有Boss时，生成Boss
    if Game.stage_system.current_phase == StagePhase.BOSS and not Game.haveBoss:
        Game.createBoss()
```

#### 4.7 UI显示
```python
# 显示关卡信息
if Game.stage_system:
    stage_info = Game.stage_system.get_stage_info()  # "Stage 1/6 - 道中"
    Game.drawText(stage_info, font1, screen, 1080, 60)

    # 显示道中进度
    if Game.stage_system.current_phase == StagePhase.STAGE:
        remaining = Game.stage_system.get_stage_remaining_time()
        Game.drawText(f'Boss in: {remaining}s', font1, screen, 1080, 100)
```

---

## 游戏流程示例

### 完整6关卡流程

```
[游戏开始]
    ↓
【Stage 1 - 道中】
- 播放：bgm1.mp3
- 背景：back1.png (时停时back1r.png)
- 持续：60秒
- 打小怪
    ↓
【Stage 1 - Boss战】
- 播放：boss1.mp3
- 背景：boss1.png (闪烁效果：boss1.png ↔ boss1r.png)
- Boss 1登场
- 第一条血：普通攻击
- 第二条血：符卡攻击
- 击败 → 3秒延迟
    ↓
【Stage 2 - 道中】
- 播放：bgm2.mp3
- 背景：back2.png
- 持续：60秒
    ↓
【Stage 2 - Boss战】
- 播放：boss2.mp3
- 背景：backgroundImage3（红天空） + 心形传送门特效
- Boss 2登场
- 击败 → 3秒延迟
    ↓
【Stage 3 - 道中】
- 播放：bgm3.mp3
- 背景：back3.png
    ↓
【Stage 3 - Boss战】
- 播放：boss3.mp3
- 背景：boss3.png (时停时boss3r.png)
- Boss 3登场（时间泡泡）
- 击败 → 3秒延迟
    ↓
【Stage 4 - 道中】
- 播放：bgm4.mp3
- 背景：back4.png
    ↓
【Stage 4 - Boss战】
- 播放：boss4.mp3
- 背景：boss4.png (时停时boss4r.png)
- Boss 4登场（色块屏幕）
- 击败 → 3秒延迟
    ↓
【Stage 5 - 道中】
- 播放：bgm5.mp3
- 背景：back5.png
    ↓
【Stage 5 - Boss战】
- 播放：boss5.mp3
- 背景：boss5.png (时停时boss5r.png)
- Boss 5登场
- 击败 → 3秒延迟
    ↓
【Stage 6 - 道中】
- 播放：bgm6.mp3
- 背景：back6.png
    ↓
【Stage 6 - Boss战】🏆
- 播放：boss6.mp3
- 背景：boss6.png (时停时boss6r.png)
- Boss 6登场（5阶段血条，五芒星框架）
- 击败
    ↓
【通关画面】🎉
┌─────────────────────────┐
│                         │
│     GAME CLEAR!         │
│                         │
│  Final Score: 9999999   │
│  Time: 1234s            │
│                         │
└─────────────────────────┘
- 显示5秒后游戏退出
```

---

## 特殊机制

### 时停系统与背景
所有关卡和Boss背景都支持时停状态：
- **正常状态**：`back1.png`, `boss1.png` 等
- **时停状态**：`back1r.png`, `boss1r.png` 等（反向/变色）

### Boss特殊效果保留
1. **Boss 1**：闪烁背景效果（0.677秒间隔 boss1 ↔ boss1r）
2. **Boss 2**：心形传送门特效 + backgroundImage3红天空
3. **Boss 3**：时间泡泡效果
4. **Boss 4**：色块屏幕效果
5. **Boss 5**：移动框架效果
6. **Boss 6**：五芒星框架 + 5阶段血条 + 窗口透明/抖动

### 符卡系统
每个Boss死亡两次：
1. **第一次死亡**：进入符卡阶段，血量回满
2. **第二次死亡**：真正死亡，进入下一关

---

## UI显示

### 右上角信息
```
gametime: 234
Stage 2/6 - Boss战       ← 关卡信息
Boss in: 45s             ← 道中倒计时（仅道中显示）
```

### 通关画面
```
┌──────────────────────────┐
│                          │
│    ★ GAME CLEAR! ★       │  金色闪烁
│                          │
│  Final Score: 9999999    │  白色
│  Time: 1234s             │  白色
│                          │
└──────────────────────────┘
黑色背景，显示5秒后退出
```

---

## 兼容性

### 向后兼容
所有修改都保留了旧版兼容性：
```python
if Game.stage_system:
    # 使用新的关卡系统
else:
    # 兼容旧版：随机Boss、随机BGM
```

### 可选启用
关卡系统可以通过移除 `Game.stage_system` 初始化来禁用，游戏会自动回退到旧版无限模式。

---

## 配置参数

### 可调整参数（StageSystem.py）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `total_stages` | 6 | 总关卡数 |
| `stage_duration` | 60秒 | 道中持续时间 |
| `stage_clear_delay` | 3秒 | 通关后延迟时间 |

### 修改关卡数量
如果想改成8关或10关：
1. 准备对应的BGM和背景（bgm7-10.mp3, boss7-10.mp3, back7-10.png等）
2. 修改 `StageSystem.total_stages = 8`
3. 在main.py中加载新的BGM和背景

---

## 测试要点

### 功能测试
- ✅ Stage 1道中播放bgm1.mp3，显示back1.png
- ✅ 60秒后自动进入Boss1战，切换boss1.mp3和boss1.png
- ✅ 击败Boss1后3秒延迟，进入Stage 2道中
- ✅ 所有6个关卡BGM和背景正确切换
- ✅ 时停时背景切换到r版本
- ✅ Boss特殊效果（闪烁、心形传送门等）正常
- ✅ 击败Boss6后显示通关画面
- ✅ 通关画面显示最终分数和时间

### Boss顺序测试
- ✅ Stage 1 → Boss 1
- ✅ Stage 2 → Boss 2
- ✅ Stage 3 → Boss 3
- ✅ Stage 4 → Boss 4
- ✅ Stage 5 → Boss 5
- ✅ Stage 6 → Boss 6

---

## 文件清单

### 新增文件
- `StageSystem.py` - 关卡系统核心

### 修改文件
- `Event.py` - 集成关卡系统，修改Boss创建和死亡逻辑
- `EmojiAll/BossEnemies.py` - Boss接受boss_id参数
- `main.py` - BGM加载、背景加载、关卡系统初始化、主循环更新、UI显示

### 资源文件（已存在）
**音乐**：
- `music/bgm1-6.mp3` - 6个道中BGM
- `music/boss1-6.mp3` - 6个Boss BGM

**图片**：
- `image/back1-6.png` - 6个道中背景
- `image/back1r-6r.png` - 6个道中时停背景
- `image/boss1-6.png` - 6个Boss背景
- `image/boss1r-6r.png` - 6个Boss时停背景

---

## 实现特点

### ✨ 完全符合需求
1. ✅ **6关卡通关**：打完6个Boss就能顺利通过
2. ✅ **道中+Boss结构**：类似东方，每关分道中和Boss战
3. ✅ **BGM系统**：
   - 道中：bgm1-6.mp3
   - Boss：boss1-6.mp3
4. ✅ **背景系统**：
   - 道中：back1-6.png（含时停r版本）
   - Boss：boss1-6.png（含时停r版本）
5. ✅ **特殊处理**：Boss2背景特殊处理（用户提到"仔细看看image文件夹里面的图片"）

### 🎮 游戏体验
- 清晰的关卡进度提示
- 道中倒计时增加紧迫感
- Boss战BGM切换营造氛围
- 通关画面给予成就感
- 每关独特的背景和音乐

### 🔧 技术亮点
- 模块化设计，易于扩展
- 兼容旧版，平滑升级
- 状态机管理关卡流程
- 自动BGM和背景切换
- 支持时停系统

---

## 使用说明

### 启动游戏
```bash
python main.py
```

### 游戏流程
1. 开始游戏，进入Stage 1道中
2. 打小怪60秒
3. Boss1自动出现
4. 击败Boss1（两条血）
5. 3秒后自动进入Stage 2道中
6. 重复步骤2-5，直到击败Boss6
7. 显示通关画面

### 快捷键
- **数字键1-8**：切换武器
- **空格**：使用炸弹
- **Shift**：慢速移动
- **Z**：冲刺

---

## 总结

### 实现内容
- ✅ 6关卡通关系统
- ✅ 道中+Boss结构
- ✅ 自动BGM切换（12首：6道中+6Boss）
- ✅ 自动背景切换（24张：12正常+12时停）
- ✅ 关卡进度UI
- ✅ 通关画面
- ✅ Boss顺序登场（1-6）
- ✅ 保留所有Boss特殊效果
- ✅ 保留符卡系统
- ✅ 向后兼容

### 游戏现已完整
打完6个Boss就能通关，完全符合东方Project的关卡结构！每个关卡都有独特的道中BGM、Boss BGM、道中背景和Boss背景。

**享受6关卡的完整游戏体验吧！** 🎉🎮✨

---

*实现完成时间：2025-11-01*
*实现完成度：100%*
*关卡数量：6个*
*BGM数量：12首（6道中+6Boss）*
*背景数量：24张（12正常+12时停）*
