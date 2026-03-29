# NetworkManager 代码说明

**路径**：`scripts/core/network_manager.gd`  
**类型**：Autoload 单例

---

## 主要逻辑

局域网联机：ENet 创建/加入房间、Mod 校验、场景同步、退出/重新开始。主机 peer_id=1，客户端 peer_id=2。

---

## 核心方法

| 方法 | 功能 | 实现 |
|------|------|------|
| `create_game(port)` | 创建房间 | `peer.create_server(port, 1)`，设置 `multiplayer.multiplayer_peer` |
| `join_game(ip, port)` | 加入房间 | `peer.create_client(ip, port)` |
| `is_multiplayer()` | 是否联机 | 检查 `multiplayer_peer` 存在且已连接 |
| `get_local_player_index()` | 本地玩家索引 | 主机=0，客户端=1 |
| `is_my_turn(current_index)` | 是否我的回合 | `current_index == get_local_player_index()` |
| `_sync_to_battle()` | 同步到对决 | 生成种子，`_reset_managers`，RPC `_rpc_sync_to_battle`，跳转场景 |
| `request_exit_game()` | 退出游戏 | RPC 通知对手，`force_exit_to_main` |
| `request_restart_game()` | 重新开始 | 仅主机可调用，RPC 后双方同步重置并重载场景 |
