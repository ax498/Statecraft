# CardManager 代码说明

**路径**：`scripts/core/card_manager.gd`  
**类型**：Autoload 单例

---

## 主要逻辑

卡牌管理器负责牌堆构建、抽牌、矛盾检测、回合结算。联机时仅主机执行抽牌与结算，客户端通过 `apply_draw_from_data`、`apply_settlement_result` 应用主机下发的数据。

---

## 核心方法

| 方法 | 功能 | 实现 |
|------|------|------|
| `_build_deck()` | 构建牌堆 | 从模板生成空牌/见好就收/一石二鸟，合并 Mod 注册卡牌，洗牌 |
| `register_card(card_data)` | Mod 注册卡牌 | 将 Dictionary 加入 `mod_registered_cards`，`_build_deck` 时并入 |
| `draw_card(player_index)` | 抽牌 | 触发 `pre_draw_card`，随机索引调用 `_draw_card_at_index`，返回 `[idx, card]` |
| `_draw_card_at_index(pi, idx)` | 实际抽牌 | 从 `global_deck` 移除，触发 `post_draw_card`；若被消费则 `card_drawn_consumed`，否则加入 `turn_container` 并检测同名矛盾 |
| `apply_draw_from_data(pi, card_data, deck_count)` | 客户端应用抽牌 | 根据 Dictionary 创建 CardResource，加入 `turn_container`，发出 `card_drawn` |
| `apply_consumed_draw_from_data` | 客户端应用消费抽牌 | 不加入 `turn_container`，发出 `card_drawn_consumed` |
| `consume_drawn_card(card)` | Mod 消费抽牌 | 设置 `_consumed_drawn_card`，需在 `post_draw_card` 内调用 |
| `remove_card_from_hand(pi, card)` | 从手牌移除 | 从 `player_hands[pi]` 移除并加入 `discard_pile`，发出 `hand_updated` |
| `check_name_contradiction()` | 同名矛盾检测 | 遍历 `turn_container`，`count_towards_contradiction=true` 且同名则返回触发牌 |
| `trigger_contradiction(card)` | 触发矛盾 | 清空 `turn_container`，发出 `contradiction_triggered`、`force_end_turn` |
| `settle_turn(player_index)` | 回合结算 | 检测矛盾后，累加 `turn_container` 分值到 `player_hands`，发出 `turn_settled` |
| `apply_settlement_result` | 客户端应用结算 | 根据主机数据创建卡牌加入手牌，清空 `turn_container` |
