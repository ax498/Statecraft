---
Status: 有效
Version: v0.1.0
Last_Sync: 2025-03-18
Ref_Scripts:
  - mods/tashanzhishi_mod/main.gd
---

# Mod 编写教程：以他山之石为例

**版本**：v0.1.0  
**最后更新**：2025-03-18

本教程以他山之石 Mod 为例，说明如何在单机与联机两种模式下编写需要玩家选择的卡牌 Mod。

---

## 1. 目录与入口

```
mods/
└── tashanzhishi_mod/
    ├── mod_info.json    # Mod 元信息
    └── main.gd          # 入口脚本
```

**mod_info.json**：
```json
{
  "name": "他山之石",
  "author": "",
  "description": "抽到此牌时，若任意一方手牌有一石二鸟，可选择一张一石二鸟与一张对手卡牌移除",
  "version": "1.0",
  "entry_script": "main.gd"
}
```

**main.gd 基本结构**：
```gdscript
extends RefCounted

func _mod_init() -> void:
    # 注册卡牌
    pass

func _on_hook_triggered(hook_name: String, args: Array) -> void:
    if hook_name == "post_draw_card":
        pass
    elif hook_name == "post_draw_animation":
        pass
```

---

## 2. 单机模式：核心流程

### 2.1 注册卡牌（_mod_init）

```gdscript
func _mod_init() -> void:
    var mod_loader = Engine.get_main_loop().root.get_node_or_null("ModLoader")
    if mod_loader == null:
        return
    mod_loader.api_call("CardManager", "register_card", [
        {"name": "他山之石", "ability_id": "tashanzhishi", "scores": [1, 2, 3, 4], "count_towards_contradiction": true}
    ])
```

### 2.2 抽牌时检测（post_draw_card）

在 `post_draw_card` 中判断是否为我们的卡，并检查是否满足触发条件：

```gdscript
func _handle_post_draw_card(args: Array) -> void:
    if args.size() < 2:
        return
    var card_data = args[0]
    var player_index: int = int(args[1])
    var aid: String = card_data.ability_id if card_data is CardResource else ""

    if aid != "tashanzhishi":
        return

    var cm = mod_loader.get_card_manager()
    var hands = cm.get("player_hands")
    var has_double = false
    for pi in [0, 1]:
        for c in hands.get(pi, []):
            if c.card_name == "一石二鸟":
                has_double = true
                break
        if has_double:
            break

    if not has_double:
        return  # 不满足条件，不劫持

    var bm = mod_loader.get_battle_manager()
    bm.set("mod_pause_settlement", true)  # 劫持流程
    _pending = true
    _player_index = player_index
```

### 2.3 动画后分支（post_draw_animation）

抽牌动画结束后触发 `post_draw_animation`。需区分：**我的回合**（手动选择）还是**对手回合**（AI 自动选择）：

```gdscript
func _handle_post_draw_animation() -> void:
    if not _pending:
        return

    var bm = mod_loader.get_battle_manager()
    var is_lunce = bm.get("is_lunce_mode")
    var nm = Engine.get_main_loop().root.get_node_or_null("NetworkManager")
    var is_mp = nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer")
    var local_idx = 0
    if not is_lunce and is_mp:
        local_idx = nm.call("get_local_player_index")

    # 论策模式 AI 抽到：自动选择
    if is_lunce and _player_index == 1:
        _auto_select(mod_loader)
        return

    # 单机对手回合（AI）：自动选择
    if not is_mp and _player_index != local_idx:
        _auto_select(mod_loader)
        return

    # 本地玩家：显示选择 UI
    _add_abandon_button(scene)
    _highlight_double_cards(scene, mod_loader)
```

### 2.4 自动选择（AI / 对手）

```gdscript
func _auto_select(mod_loader: Node) -> void:
    var cm = mod_loader.get_card_manager()
    var hands = cm.get("player_hands")
    var opponent_index = 1 - _player_index
    var double_card = ...
    var opp_card = ...

    var bm = mod_loader.get_battle_manager()
    bm.request_mod_soft_remove_effect([
        {"card": double_card, "player_index": double_from},
        {"card": opp_card, "player_index": opponent_index}
    ])
    _finish_and_continue()
```

### 2.5 手动选择与执行

玩家点击卡牌后，调用 `_execute_remove`。单机/主机直接请求特效：

```gdscript
func _execute_remove(opponent_card, mod_loader: Node) -> void:
    var bm = mod_loader.get_battle_manager()
    # 单机或主机：直接请求特效
    bm.request_mod_soft_remove_effect([
        {"card": _double_selected, "player_index": _double_from_player},
        {"card": opponent_card, "player_index": opponent_index}
    ])
    _finish_and_continue()
```

### 2.6 结束流程

```gdscript
func _finish_and_continue() -> void:
    var bm = mod_loader.get_battle_manager()
    bm.request_mod_resume_without_settle()  # 或 mod_resume_without_settle
    _finish_pending()
```

---

## 3. 联机模式：额外逻辑

联机时**对手是真人**，不能自动选择。需实现：① 主机通知客户端；② 客户端显示选择 UI；③ 客户端选择后 RPC 到主机；④ 主机执行并 RPC 特效到客户端。

### 3.1 客户端抽到时：主机通知

在 `post_draw_card` 中，若抽牌者是**客户端**（`player_index != local_idx`），主机需通知客户端：

```gdscript
var nm = Engine.get_main_loop().root.get_node_or_null("NetworkManager")
if nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer"):
    var local_idx = nm.call("get_local_player_index")
    if player_index != local_idx and bm.has_method("request_mod_tashanzhishi_to_client"):
        bm.call("request_mod_tashanzhishi_to_client", player_index)
```

BattleManager 会 RPC `_rpc_tashanzhishi_mode_started`，客户端设置 `mod_tashanzhishi_pending`。客户端在 `draw_animation_finished` 中会先触发 `sync_tashanzhishi_mode`，再触发 `post_draw_animation`。

### 3.2 客户端 Mod：sync_tashanzhishi_mode

客户端从未执行 `post_draw_card`，因此 `_pending` 一直为 false。需新增钩子 `sync_tashanzhishi_mode`，在 `post_draw_animation` 前设置状态：

```gdscript
func _on_hook_triggered(hook_name: String, args: Array) -> void:
    if hook_name == "sync_tashanzhishi_mode":
        _handle_sync_tashanzhishi_mode(args)
    # ...

func _handle_sync_tashanzhishi_mode(args: Array) -> void:
    if args.size() < 1:
        return
    _pending = true
    _player_index = int(args[0])
    _double_selected = null
    _double_from_player = -1
```

### 3.3 主机端：跳过对手回合的 post_draw_animation

主机也会收到 `post_draw_animation`（主机动画结束）。若抽牌者是客户端，主机应**不显示选择 UI**，直接返回：

```gdscript
if is_mp and _player_index != local_idx:
    return  # 联机对手回合：由对方客户端处理
```

### 3.4 客户端选择：RPC 到主机

客户端选择后，不能直接调用 `request_mod_soft_remove_effect`（主机才有权威数据）。需发送**选择索引**给主机：

```gdscript
func _execute_remove(opponent_card, mod_loader: Node) -> void:
    var nm = Engine.get_main_loop().root.get_node_or_null("NetworkManager")
    var is_mp = nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer")
    var is_server = not is_mp or (mod_loader is Node and mod_loader.multiplayer.is_server())

    if is_mp and not is_server:
        # 联机客户端：发送 hand_index 给主机
        var hands = cm.get("player_hands")
        var double_idx = hands.get(_double_from_player, []).find(_double_selected)
        var opp_hand_idx = hands.get(opponent_index, []).find(opponent_card)
        bm.call("request_tashanzhishi_selection", {
            "double_from": _double_from_player,
            "double_idx": double_idx,
            "opp_idx": opponent_index,
            "opp_hand_idx": opp_hand_idx
        })
    else:
        # 主机或单机：直接请求特效
        bm.request_mod_soft_remove_effect([...])
```

主机收到后，从 `player_hands` 按索引取卡，执行 `request_mod_soft_remove_effect`，并 RPC `_rpc_mod_soft_remove_effect` 到客户端，客户端按 hand_index 定位卡牌并播放特效。

### 3.5 放弃：RPC 到主机

客户端点击「放弃」时，需通知主机恢复流程：

```gdscript
bm.request_mod_resume_without_settle()  # 内部会判断：客户端则 RPC 到主机
```

---

## 4. 手牌容器与镜像 UI

联机时双方屏幕镜像：本地手牌在底部，对手在顶部。应使用 `get_target_container(logic_player_index)` 而非固定路径：

```gdscript
var hand_container = scene.get_target_container(pi) if scene.has_method("get_target_container") else scene.get_node_or_null(PLAYER_HAND_PATH if pi == 0 else OPPONENT_HAND_PATH)
```

---

## 5. 检查清单

| 场景 | 单机 | 联机 |
|------|------|------|
| 我抽到 | post_draw_animation → 显示选择 | 同左 |
| 对手抽到（AI） | post_draw_animation → _auto_select | — |
| 对手抽到（真人） | — | 主机 request_mod_tashanzhishi_to_client；客户端 sync_tashanzhishi_mode + post_draw_animation → 显示选择 |
| 选择完成 | request_mod_soft_remove_effect | 客户端 request_tashanzhishi_selection（RPC） |
| 放弃 | request_mod_resume_without_settle | request_mod_resume_without_settle（客户端会 RPC） |

---

## 6. 参考

- [Mod API 文档](Mod_API_文档.md)
- [他山之石源码](../../../mods/tashanzhishi_mod/main.gd)
- [局域网联机逻辑](../03_数据与同步/局域网联机逻辑.md)
