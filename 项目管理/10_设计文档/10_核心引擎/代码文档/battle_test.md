# battle_test 代码说明

**路径**：`scenes/battle/battle_test.gd`  
**类型**：Control 场景脚本（战斗主场景）

---

## 主要逻辑

战斗 UI：手牌/回合区显示、抽牌动画、矛盾淡出、他山之石删牌特效。监听 CardManager/BattleManager 信号，联机时手牌刷新由 `hand_collection_requested` 统一触发，镜像 UI（本地手牌在底部、对手在顶部）。

---

## 核心方法

| 方法 | 功能 | 实现 |
|------|------|------|
| `get_target_container(logic_player_index)` | 获取手牌容器 | 根据本地索引返回 PlayerHandDisplay 或 OpponentHandDisplay |
| `_refresh_hand_displays()` | 刷新手牌 | 清空容器，按 `player_hands` 重建 card_ui |
| `_on_card_drawn(card)` | 抽牌 | 在回合区实例化 card_ui，播放滑入动画，动画结束调用 `draw_animation_finished` |
| `_on_mod_soft_remove_effect_requested(cards)` | 他山之石删牌特效 | 在手牌容器中按 card 定位 card_ui，播放变亮→震动→淡出，回调中 `remove_card_from_hand` 并刷新 |
| `_animate_cards_to_hand(player_index)` | 收牌动画 | 回合区卡牌飞向对应手牌容器 |
| `_play_light_shake()` | 轻微震动 | ShakeLayer 位移动画 |
