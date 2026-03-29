# card_ui 代码说明

**路径**：`scenes/ui/card_ui.gd`  
**类型**：Control 场景脚本

---

## 主要逻辑

卡牌 UI 组件，统一使用 card.png 底图，通过 Label 显示卡名与分值。支持矛盾样式、变身动画、手牌缩小模式。

---

## 核心方法

| 方法 | 功能 | 实现 |
|------|------|------|
| `setup(card)` | 初始化 | 设置 `card_data`，加载纹理，Label 显示 `card_name` 与 `effect_value` |
| `update_ui()` | 刷新显示 | 当 card_data 被修改后，更新 Label 文本 |
| `set_contradiction_style(is_contradiction)` | 矛盾样式 | 红色或白色 modulate |
| `play_transform_animation(on_complete)` | 变身动画 | Tween 缩放+发光，完成后回调 |
| `play_extra_action_glow()` | 额外行动发光 | 循环 3 次发光动画 |
| `set_compact(compact)` | 手牌缩小 | scale 0.6 或 1.0 |
