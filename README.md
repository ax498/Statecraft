# Statecraft

Godot 4.6.1 卡片对决游戏 | GDScript

## 技术栈

- **引擎**：Godot 4.6.1
- **语言**：GDScript
- **平台**：Windows / Mobile

## 项目结构

```
Statecraft/
├── project.godot              # 项目配置
├── icon.svg                   # 应用图标
│
├── scenes/                    # 场景
│   ├── battle/                # 战斗场景
│   │   ├── battle_test.tscn   # 战斗测试场景（主入口）
│   │   └── battle_test.gd     # 战斗测试脚本
│   ├── main/                  # 主场景（待开发）
│   └── ui/                    # UI 界面（待开发）
│
├── scripts/                   # 脚本
│   ├── core/                  # 核心逻辑（Autoload 单例）
│   │   ├── card_manager.gd    # 卡牌管理器：抽牌、矛盾检测、回合结算
│   │   └── mod_manager.gd     # Mod 管理器：外部资源包加载
│   ├── data/                  # 数据定义
│   │   └── card_resource.gd   # 卡牌资源类型
│   ├── autoload/              # 其他单例（预留）
│   ├── components/            # 可复用组件（预留）
│   └── tools/                 # 工具脚本（预留）
│
├── resources/                 # 资源文件
│   ├── cards/                 # 卡牌资源（预留）
│   ├── fonts/                 # 字体
│   │   ├── PingFangChangAnTi-2.ttf
│   │   ├── TaiWanQuanZiKuZhengKaiTi-2.ttf
│   │   └── ZiKuJiangHuGuFengTi-2.ttf
│   ├── pictures/              # 图片素材
│   │   ├── StartScene.png / GameScene.png / PVEScene.png
│   │   ├── card.png / card_copy.png / card_jade.png
│   │   ├── button_0~2.png / label_0~1.png / popup.png
│   │   └── ...
│   └── templates/             # 卡牌模板
│       ├── template_null.tres  # 空牌
│       ├── template_stop.tres  # 见好就收
│       └── template_double.tres # 一石二鸟
│
├── project_management/        # 项目管理（英文）
│   └── mod_override_guide.md  # Mod 覆盖指南
│
└── 项目管理/                  # 项目管理（中文）
    ├── 0_制作人工作台/        # 待办、垃圾箱
    ├── 10_设计文档/           # 设计文档
    │   ├── 03_数据与同步/     # 施加点、经验捕捉等
    │   ├── 10_核心引擎/
    │   ├── 20_开发计划/
    │   ├── 60_UI/
    │   ├── 60_工具/
    │   └── 60_玩法扩展/
    └── 20_开发日志/           # 版本记录、时间记录、项目进度
```

## Autoload 单例

| 名称 | 路径 | 说明 |
|------|------|------|
| NetworkManager | `scripts/core/network_manager.gd` | 局域网联机：ENet 创建/加入房间、状态追踪、场景同步 |
| BattleManager | `scripts/core/battle_manager.gd` | 战斗状态机、回合切换、主机权威 RPC |
| CardManager | `scripts/core/card_manager.gd` | 牌堆管理、抽牌、矛盾检测、回合结算 |
| ModManager | `scripts/core/mod_manager.gd` | 外部 Mod 资源包加载（Android 平台） |
| ModLoader | `scripts/core/mod_loader.gd` | Mod 钩子与 API 调用 |

## 主入口

- **主场景**：`scenes/battle/battle_test.tscn`
- **运行**：直接运行项目即可进入战斗测试场景

## 游戏模式

- **论策**：单机模式，玩家 vs AI
- **演兵**：局域网 2 人对战，主机权威架构

## 相关文档

- [Mod 覆盖指南](project_management/mod_override_guide.md) — 玩家 Mod 资源包使用说明
- [Mod API 文档](项目管理/10_设计文档/60_玩法扩展/Mod_API_文档.md) — Mod 编写 API 参考
- [Mod 编写教程](项目管理/10_设计文档/60_玩法扩展/Mod_编写教程.md) — 以他山之石为例，单机/联机 Mod 编写
- [局域网联机逻辑](项目管理/10_设计文档/03_数据与同步/局域网联机逻辑.md) — 演兵模式 RPC 与数据流详解
