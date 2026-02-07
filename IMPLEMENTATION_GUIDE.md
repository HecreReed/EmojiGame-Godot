# Godot 4.x Emoji Game - 完整实现文档

## 项目概述

这是使用 Godot 4.x 引擎完整复现的 Emoji 射击游戏，基于原版 Python + Pygame 实现。

## 已实现功能

### ✅ 核心游戏系统

#### 1. 玩家系统 (scripts/player/player.gd)
- **移动控制**: WASD 或方向键
- **射击系统**: 空格键或J键连续射击
- **生命值系统**: 100点基础生命，受伤时UI实时更新
- **碰撞检测**: 与敌人和敌人子弹的碰撞
- **边界限制**: 玩家无法移出屏幕

#### 2. 子弹系统
**玩家子弹** (scripts/bullets/player_bullet.gd)
- 直线飞行，速度600
- 碰撞敌人后造成伤害并消失
- 飞出屏幕自动销毁

**敌人子弹** (scripts/bullets/enemy_bullet.gd)
- 5种弹幕类型:
  - NORMAL: 直线射击
  - TRACKING: 追踪玩家位置
  - CIRCLE: 圆形弹幕（12颗子弹环绕）
  - SAND: 扇形散射（8颗子弹）
  - RANDOM: 随机方向

#### 3. 敌人系统 (scripts/enemies/enemy.gd)
- **多种射击模式**: 根据敌人血量自动选择弹幕模式
- **受伤反馈**: 被击中时闪红色
- **智能射击**: 不同强度敌人使用不同攻击模式
- **移动模式**: 从右向左匀速移动

#### 4. Boss 系统 (scripts/enemies/boss_enemy.gd)
- **5种Boss类型**: 每种Boss有独特攻击模式
  - Boss 1: 简单螺旋弹幕
  - Boss 2: 追踪子弹连发
  - Boss 3: 三连发 + 圆形弹幕
  - Boss 4: 密集螺旋
  - Boss 5: 双重螺旋 + 追踪

- **复杂移动模式**:
  - Boss 1: 上下移动
  - Boss 2: 从顶部出现后停止
  - Boss 3-5: 波浪形移动

- **弹幕攻击**:
  - 螺旋弹幕（可调节子弹数量和旋转速度）
  - 双重螺旋
  - 追踪弹幕
  - 三连发

#### 5. 敌人生成系统 (scripts/autoload/enemy_spawner.gd)
- **波次系统**: 每波20个敌人，击败后生成Boss
- **难度递增**:
  - 敌人血量随波次增加
  - 移动速度提升
  - Boss血量增长
- **随机生成**: 6个不同的生成点位随机选择
- **Boss战机制**: 普通敌人全部击败后2秒生成Boss
- **循环波次**: Boss被击败后3秒开始新一波

#### 6. 游戏管理器 (scripts/autoload/game_manager.gd)
- **分数系统**:
  - 击败普通敌人获得分数
  - Boss双倍分数
  - 最高分记录
- **暂停/继续**: ESC键暂停游戏
- **游戏状态**: 管理游戏进行、暂停、结束状态
- **信号系统**: 通过信号与UI通信

#### 7. UI 系统 (scripts/ui/hud.gd)
- **实时HUD**:
  - 分数显示
  - 当前波次
  - 生命值条（带数值显示）

- **暂停菜单**:
  - 继续游戏
  - 退出到菜单

- **游戏结束界面**:
  - 最终分数显示
  - 重新开始
  - 退出游戏

#### 8. 背景系统 (scripts/world/scrolling_background.gd)
- 无限循环滚动背景
- 可调节滚动速度

## 项目结构

```
godot-emojigame/
├── assets/                      # 游戏资源
│   ├── sprites/                # 所有图片资源（已从原版复制）
│   └── audio/                  # 音频资源（已从原版复制）
│       └── music/
│
├── scenes/                      # 场景文件
│   ├── player/
│   │   └── player.tscn        # 玩家场景
│   ├── enemies/
│   │   ├── enemy.tscn         # 普通敌人场景
│   │   └── boss_enemy.tscn    # Boss场景
│   ├── bullets/
│   │   ├── player_bullet.tscn # 玩家子弹场景
│   │   └── enemy_bullet.tscn  # 敌人子弹场景
│   └── world/
│       └── main.tscn          # 主场景（游戏入口）
│
├── scripts/                     # 所有游戏逻辑脚本
│   ├── player/
│   │   └── player.gd          # 玩家控制
│   ├── enemies/
│   │   ├── enemy.gd           # 敌人基类（含5种弹幕）
│   │   └── boss_enemy.gd     # Boss类（5种Boss模式）
│   ├── bullets/
│   │   ├── player_bullet.gd   # 玩家子弹
│   │   └── enemy_bullet.gd    # 敌人子弹（5种类型）
│   ├── ui/
│   │   └── hud.gd             # UI管理
│   ├── autoload/
│   │   ├── game_manager.gd    # 游戏管理器（单例）
│   │   └── enemy_spawner.gd   # 敌人生成器
│   └── world/
│       └── scrolling_background.gd  # 背景滚动
│
└── project.godot                # 项目配置

```

## 技术特性

### 碰撞层设置
- Layer 1: 玩家
- Layer 2: 玩家子弹
- Layer 4: 敌人和敌人子弹

### 输入映射
- `move_left`: A / 左箭头
- `move_right`: D / 右箭头
- `move_up`: W / 上箭头
- `move_down`: S / 下箭头
- `shoot`: 空格 / J
- `ui_cancel`: ESC（暂停）

### 单例（Autoload）
- **GameManager**: 全局游戏状态管理

## 游戏玩法

1. **开始游戏**: 打开项目后直接运行主场景
2. **移动**: 使用WASD或方向键控制玩家移动
3. **射击**: 按住空格键或J键连续射击
4. **波次**: 击败20个敌人后会出现Boss
5. **Boss战**: 击败Boss后进入下一波，难度提升
6. **暂停**: 按ESC键暂停/继续游戏
7. **游戏结束**: 生命值归零后显示最终分数

## 核心机制复现对比

| 原版 Python 功能 | Godot 实现 | 完成度 |
|---|---|---|
| 玩家移动和射击 | ✅ 完整实现 | 100% |
| 5种敌人子弹类型 | ✅ 完整实现（NORMAL, TRACKING, CIRCLE, SAND, RANDOM） | 100% |
| Boss弹幕模式 | ✅ 5种Boss，每种有独特攻击模式 | 100% |
| 敌人生成系统 | ✅ 波次系统，难度递增 | 100% |
| 分数系统 | ✅ 完整实现 | 100% |
| UI系统 | ✅ HUD、暂停菜单、游戏结束界面 | 100% |
| 背景滚动 | ✅ 无限循环滚动 | 100% |
| 道具系统 | ⏳ 待实现 | 0% |
| 音效/音乐 | ⏳ 资源已复制，待集成 | 0% |

## 待完善功能

### 🔸 道具系统
原版有多种道具（补给、强化等），目前Godot版本尚未实现。

### 🔸 音频系统
- 音频文件已复制到 `assets/audio/`
- 需要添加AudioStreamPlayer节点
- 需要在合适时机播放音效（射击、爆炸、Boss出现等）

### 🔸 视觉效果
- 粒子效果（爆炸、子弹轨迹）
- 屏幕震动
- 更丰富的伤害反馈

### 🔸 更多内容
- 开始菜单界面
- 设置界面（音量、难度调节）
- 更多敌人类型
- 成就系统

## 如何在 Godot 中使用

1. **打开项目**: 使用 Godot 4.x 打开 `godot-emojigame` 文件夹
2. **查看主场景**: `scenes/world/main.tscn`
3. **运行游戏**: 点击运行按钮或按 F5
4. **调试**:
   - 修改敌人生成间隔: 编辑 `enemy_spawner.gd`
   - 调整难度: 修改各个场景的 @export 参数
   - 测试Boss: 在 enemy_spawner.gd 中减少 `enemies_per_wave` 的值

## 性能优化建议

1. **对象池**: 为子弹实现对象池，避免频繁创建/销毁
2. **碰撞优化**: 使用更精确的碰撞形状
3. **渲染优化**: 对于大量子弹，考虑使用GPUParticles2D

## 扩展建议

1. **多人模式**: Godot支持网络同步，可以添加多人对战
2. **关卡系统**: 设计不同主题的关卡
3. **技能系统**: 为玩家添加特殊技能
4. **Boss阶段**: Boss血量降低时切换攻击模式

## 致谢

本项目基于原版 Python + Pygame 实现复刻，保留了核心玩法和弹幕系统，并适配到 Godot 4.x 引擎。

## 版本信息

- **Godot 版本**: 4.5
- **渲染器**: GL Compatibility
- **窗口分辨率**: 1152 x 648
- **开发时间**: 2026-01

---

**游戏已可正常运行！** 打开 Godot 编辑器，运行主场景即可开始游戏。
