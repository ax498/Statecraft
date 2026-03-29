---
Status: 有效
Version: v0.1.0
Last_Sync: 2025-03-18
Ref_Scripts:
  - scripts/core/mod_loader.gd
  - scripts/core/card_manager.gd
  - scripts/core/battle_manager.gd
---

# Mod API 文档

**版本**：v0.1.0  
**最后更新**：2025-03-18

---

## 1. Mod 脚本规范

- **继承**：必须 `extends RefCounted`
- **存放**：`res://mods/<mod_id>/main.gd`（或 ModManager 指定的路径）
- **入口**：`_mod_init()` 在加载时调用；`_on_hook_triggered(hook_name, args)` 响应钩子

---

## 2. 获取服务

Mod 脚本无 autoload 作用域，需通过场景树获取：

```gdscript
var mod_loader: Node = Engine.get_main_loop().root.get_node_or_null("ModLoader")
var bm: Node = mod_loader.get_battle_manager()
var cm: Node = mod_loader.get_card_manager()
var nm: Node = Engine.get_main_loop().root.get_node_or_null("NetworkManager")
```

---

## 3. api_call（ModLoader）

```gdscript
mod_loader.api_call(api_name: String, method: String, args: Array = []) -> Variant
```

| api_name | method | args | 说明 |
|----------|--------|------|------|
| CardManager | register_card | [card_data] | 注册新卡牌，需在 _mod_init 中调用 |
| BattleManager | （见下方） | — | 通过 bm 直接调用方法 |

---

## 4. CardManager API

### 4.1 register_card(card_data: Dictionary)

在 `_mod_init` 中调用，注册卡牌到牌堆。

**card_data 字段**：

| 字段 | 类型 | 默认 | 说明 |
|------|------|------|------|
| name | String | 必填 | 卡牌名称 |
| ability_id | String | "" | Mod 技能标识，用于钩子判断 |
| scores | Array | [1,2,3,4] | 每项一张，如 [1,2,3,4] |
| score | int | 0 | 与 count 配合，生成多张同分值 |
| count | int | 4 | 未指定 scores 时的张数 |
| count_towards_contradiction | bool | true | 是否参与同名矛盾判定 |
| force_ends_turn | bool | false | 是否强制结束回合 |

**示例**：
```gdscript
mod_loader.api_call("CardManager", "register_card", [
    {"name": "他山之石", "ability_id": "tashanzhishi", "scores": [1, 2, 3, 4], "count_towards_contradiction": true}
])
```

### 4.2 remove_card_from_hand(player_index: int, card: CardResource)

从指定玩家手牌移除卡牌并移入弃牌堆。返回 bool。

### 4.3 consume_drawn_card(card: CardResource)

消费本回合刚抽到的卡牌（不加入回合区）。**必须在 post_draw_card 钩子内、turn_container.append 之前调用**。

### 4.4 peek_next_card() -> CardResource

查看牌堆顶下一张牌（不抽取），供察言观色等 Mod 使用。牌堆为空时返回 null。

### 4.5 只读属性

- `player_hands: Dictionary` — {0: [], 1: []}，玩家手牌
- `turn_container: Array` — 本回合抽到的牌
- `global_deck: Array` — 牌堆
- `discard_pile: Array` — 弃牌堆

---

## 5. BattleManager API

### 5.1 Mod 劫持与恢复

| 方法 | 说明 |
|------|------|
| `bm.set("mod_pause_settlement", true)` | 劫持流程，draw_animation_finished 不自动切换回合 |
| `bm.mod_resume_without_settle()` | 恢复流程，不结算本回合（卡牌留在回合区） |
| `bm.request_mod_resume_without_settle()` | 同上，联机时客户端会 RPC 到主机 |

### 5.2 特效请求

| 方法 | 参数 | 说明 |
|------|------|------|
| `request_mod_soft_remove_effect(cards)` | Array of {card, player_index} | 他山之石等删牌特效，在手牌原位变亮→震动→淡出 |
| `request_mod_contradiction_effect(cards)` | Array | 矛盾同款特效（仅视觉） |
| `request_peek_display(card, show_to_local)` | CardResource, bool | 察言观色等：请求展示下一张牌给本地玩家 |
| `request_lock_opponent_ui(locked)` | bool | 锁定/解锁对手 UI（抽牌、结束回合按钮） |

### 5.3 他山之石专用（需玩家选择的 Mod 可参考）

| 方法 | 说明 |
|------|------|
| `request_mod_tashanzhishi_to_client(player_index)` | 主机在 post_draw_card 中调用，通知客户端抽到需选择的卡 |
| `request_tashanzhishi_selection(selection)` | 客户端选择完成后调用，发送 {double_from, double_idx, opp_idx, opp_hand_idx} 给主机 |

### 5.4 通用

| 方法/属性 | 说明 |
|----------|------|
| `bm.call("is_my_turn")` | 当前是否为本地玩家回合 |
| `bm.get("is_lunce_mode")` | 是否论策模式 |
| `bm.get("current_player_index")` | 当前回合玩家索引 |
| `bm.get("player_scores")` | 双方分数 |

---

## 6. 生命周期钩子

| 钩子 | 触发时机 | args |
|------|----------|------|
| pre_draw_card | 抽牌前 | [player_index] |
| post_draw_card | 抽牌后、加入 turn_container 前 | [card, player_index] |
| post_draw_animation | 抽牌滑入动画结束后 | [current_player_index] |
| sync_tashanzhishi_mode | 联机客户端专用，他山之石 RPC 后 | [player_index] |
| ai_draw_decision | AI 决定抽牌或结束回合前 | [result_ref, turn_container, next_card]，Mod 可设置 result_ref[0]=true 强制抽牌、false 强制结束、null 使用默认。察言观色由核心处理，Mod 可覆盖 |
| pre_turn_settled | 回合结算前 | [current_player_index, turn_score] |
| post_turn_settled | 回合结算后 | [current_player_index, new_score] |
| **trigger_card_effect** | 抽到未知 ability_id 卡牌时（核心未处理） | [card, player_index, opts]，Mod 设置 opts.handled=true 表示已处理，否则核心将 mod_resume_without_settle |
| **stolen_card_effect** | 九牛一毛夺取未知 ability_id 卡牌时 | [stolen_card, steal_player_index, opts]，Mod 设置 opts.skip_mod_resume=true 表示已劫持流程 |

---

## 7. NetworkManager 辅助

| 方法 | 说明 |
|------|------|
| `nm.call("is_multiplayer")` | 是否联机模式 |
| `nm.call("get_local_player_index")` | 本地玩家索引（主机=0，客户端=1） |
| `nm.call("is_my_turn", current_index)` | 等价于 BattleManager.is_my_turn |

---

## 8. 场景与 UI

- **当前场景**：`mod_loader.get_tree().current_scene`
- **手牌容器**：`scene.get_target_container(logic_player_index)` — 根据本地索引返回正确的手牌 HBoxContainer（联机镜像 UI）
- **卡牌 UI**：`child.get("card_data")` 获取 CardResource，`child.get("card_data") == card` 用于匹配
