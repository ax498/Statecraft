# BattleManager 代码说明

**路径**：`scripts/core/battle_manager.gd`  
**类型**：Autoload 单例

---

## 主要逻辑

战斗状态机，管理回合切换、抽牌/结束回合请求、矛盾过渡、联机 RPC。主机权威：抽牌、结算、回合切换仅在主机计算，客户端通过 RPC 接收结果。支持 Mod 劫持（如他山之石选择流程）。

---

## 状态枚举

| State | 说明 |
|-------|------|
| START_BATTLE | 初始化 |
| PLAYER_TURN | 玩家回合，可抽牌/结束 |
| PROCESSING | 处理中（抽牌动画、结算等） |
| CONTRADICTION | 矛盾动画中 |

---

## 核心方法

| 方法 | 功能 | 实现 |
|------|------|------|
| `request_draw()` | 请求抽牌 | 联机客户端 RPC 到主机；主机/单机调用 `_execute_draw` 或 `cm.draw_card` |
| `_execute_draw()` | 主机执行抽牌 | 调用 `cm.draw_card`，根据是否在 `turn_container` 发送 `_rpc_apply_draw` 或 `_rpc_apply_consumed_draw` |
| `request_end_turn()` | 请求结束回合 | 联机客户端 RPC；主机执行 `_execute_end_turn`，结算后 RPC 下发 |
| `draw_animation_finished()` | 抽牌动画结束 | 联机客户端：若有 `mod_tashanzhishi_pending` 触发 sync+post_draw_animation；主机触发 `post_draw_animation` 钩子 |
| `mod_resume_without_settle()` | Mod 恢复流程 | 解除 `mod_pause_settlement`，过渡到 PLAYER_TURN，RPC 更新客户端 UI |
| `request_mod_tashanzhishi_to_client(pi)` | 通知客户端他山之石 | 主机在 `post_draw_card` 中调用，RPC 设置 `mod_tashanzhishi_pending` |
| `request_tashanzhishi_selection(sel)` | 他山之石选择 | 客户端 RPC 到主机；主机 `_apply_tashanzhishi_selection` 执行删牌并 RPC 特效 |
| `request_mod_soft_remove_effect(cards)` | 请求删牌特效 | 发出 `mod_soft_remove_effect_requested`，联机时 RPC `_rpc_mod_soft_remove_effect` 到客户端 |
| `request_mod_resume_without_settle()` | Mod 恢复（含 RPC） | 客户端调用时 RPC 到主机，主机执行 `mod_resume_without_settle` |
