# 他山之石 Mod 代码说明

**路径**：`mods/tashanzhishi_mod/main.gd`  
**类型**：RefCounted（Mod 脚本实例）

---

## 主要逻辑

抽到他山之石时，若任意一方手牌有一石二鸟，进入选择流程：第一次选一石二鸟，第二次选对手牌（排除第一次）。被选卡牌在手牌原位播放变亮→震动→淡出后移入弃牌堆；他山之石正常加入回合区。联机时客户端抽到需主机 RPC 通知，客户端选择后 RPC 到主机执行。

---

## 钩子与流程

| 钩子 | 处理 | 说明 |
|------|------|------|
| post_draw_card | `_handle_post_draw_card` | 检测他山之石、是否有双，设置 `mod_pause_settlement`；联机客户端抽到时调用 `request_mod_tashanzhishi_to_client` |
| sync_tashanzhishi_mode | `_handle_sync_tashanzhishi_mode` | 联机客户端专用，设置 `_pending`、`_player_index` |
| post_draw_animation | `_handle_post_draw_animation` | 论策 AI 或单机对手→自动选择；联机对手→跳过（对方处理）；本地玩家→高亮一石二鸟供选择 |

---

## 核心方法

| 方法 | 功能 | 实现 |
|------|------|------|
| `_handle_post_draw_card(args)` | 抽牌后 | 检测 ability_id、has_double，设置 _pending，联机时通知客户端 |
| `_handle_sync_tashanzhishi_mode(args)` | 客户端同步 | 设置 _pending、_player_index |
| `_handle_post_draw_animation()` | 动画后 | 分支：自动选择 / 跳过 / 高亮一石二鸟 |
| `_auto_select(mod_loader)` | 自动选择 | 取第一张一石二鸟与对手第一张非双牌，调用 `request_mod_soft_remove_effect` |
| `_highlight_double_cards` | 高亮一石二鸟 | 使用 `get_target_container(pi)` 获取正确容器，绑定点击 |
| `_execute_remove(opponent_card)` | 执行移除 | 联机客户端：发送 `request_tashanzhishi_selection`（含 hand_index）；主机/单机：直接 `request_mod_soft_remove_effect` |
| `_finish_and_continue()` | 结束流程 | 调用 `request_mod_resume_without_settle`（含 RPC） |
