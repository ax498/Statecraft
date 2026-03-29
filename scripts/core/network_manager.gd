## 网络管理器（单例）
## 局域网联机：ENet 创建/加入房间、状态追踪、场景同步 RPC
extends Node

const DEFAULT_PORT: int = 9999
const BATTLE_SCENE: String = "res://scenes/battle/battle_test.tscn"

var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()

## true=主机，false=客户端
var is_host: bool = false
## 对手的 MultiplayerPeer ID（主机为 2，客户端为 1）
var opponent_id: int = -1

signal connection_succeeded
signal connection_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
## 对手点击返回时发出，接收方需弹窗「对手已退出」并显示返回按钮
signal opponent_requested_exit
## 客户端 Mod 校验失败时发出，参数为错误信息
signal mod_verify_failed(message: String)
## 主机 Mod 校验通过后发出，主机可点击开始游戏
signal host_can_start


## 获取 GameLogger 单例（避免 autoload 解析问题）
func _get_game_logger() -> Node:
	return get_node_or_null("/root/GameLogger")


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	## 首次启动时 multiplayer/ENet 可能未初始化，导致论策模式抽牌/结束回合无反应。
	## 预热：创建并立即关闭临时服务器，确保网络栈就绪（用户无感知）
	call_deferred("_network_warmup")


## 预热网络栈，避免首次进入论策时抽牌卡住
func _network_warmup() -> void:
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	var warmup_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = warmup_peer.create_server(19998, 1)
	if err == OK:
		multiplayer.multiplayer_peer = warmup_peer
		await get_tree().create_timer(0.05).timeout
	warmup_peer.close()
	multiplayer.multiplayer_peer = null
	peer = ENetMultiplayerPeer.new()


func _on_peer_connected(peer_id: int) -> void:
	opponent_id = peer_id
	peer_connected.emit(peer_id)
	print("[NetworkManager] 对手已连接 peer_id=%d，发送 Mod 校验请求" % peer_id)
	var mm: Node = get_node_or_null("/root/ModManager")
	var host_mod_list: Array = []
	if mm != null and mm.has_method("get_mod_list_for_verification"):
		host_mod_list = mm.call("get_mod_list_for_verification")
	_rpc_request_mod_verify.rpc_id(peer_id, host_mod_list)


func _on_peer_disconnected(peer_id: int) -> void:
	peer_disconnected.emit(peer_id)
	if opponent_id == peer_id:
		opponent_id = -1
	print("[NetworkManager] 对手已断开 peer_id=%d" % peer_id)


func _on_connected_to_server() -> void:
	opponent_id = 1  # 服务器固定为 1
	connection_succeeded.emit()
	var my_id: int = multiplayer.get_unique_id()
	print("[NetworkManager] 已成功加入房间，本机 peer_id=%d (应为 2，若为 1 则异常)" % my_id)


func _on_connection_failed() -> void:
	connection_failed.emit()
	print("[NetworkManager] 连接失败")


## 创建房间（主机）
func create_game(port: int = DEFAULT_PORT) -> Error:
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		peer.close()
		peer = ENetMultiplayerPeer.new()

	var err: Error = peer.create_server(port, 1)  # max_clients=1，仅支持 2 人对战
	if err != OK:
		push_error("[NetworkManager] 创建服务器失败: %s" % error_string(err))
		return err

	multiplayer.multiplayer_peer = peer
	is_host = true
	opponent_id = -1
	print("[NetworkManager] 房间已创建，端口 %d，等待对手..." % port)
	return OK


## 加入房间（客户端）
func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		peer.close()
		peer = ENetMultiplayerPeer.new()

	var err: Error = peer.create_client(ip, port)
	if err != OK:
		push_error("[NetworkManager] 连接失败: %s" % error_string(err))
		return err

	multiplayer.multiplayer_peer = peer
	is_host = false
	opponent_id = -1
	print("[NetworkManager] 正在连接 %s:%d..." % [ip, port])
	return OK


@rpc("any_peer")
func _rpc_request_mod_verify(host_mod_list: Array) -> void:
	var mm: Node = get_node_or_null("/root/ModManager")
	var result: Dictionary = {"ok": true, "message": ""}
	if mm != null and mm.has_method("verify_mod_list_contains"):
		result = mm.call("verify_mod_list_contains", host_mod_list)
	if result.get("ok", true):
		_rpc_mod_verify_result.rpc_id(1, true)
	else:
		mod_verify_failed.emit(result.get("message", "Mod 校验失败"))
		_rpc_mod_verify_result.rpc_id(1, false)
		call_deferred("disconnect_peer")


@rpc("any_peer")
func _rpc_mod_verify_result(ok: bool) -> void:
	if multiplayer.is_server() and ok:
		host_can_start.emit()
	elif multiplayer.is_server() and not ok:
		disconnect_peer()


## 主机点击开始游戏后调用，player_count 2~8，空位用 AI 填充
func start_yanbing_game(player_count: int = 2) -> void:
	if not multiplayer.is_server() or opponent_id < 0:
		return
	var pc: int = clampi(player_count, 2, 8)
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm != null:
		bm.set("player_count", pc)
	var seed_value: int = randi()
	seed(seed_value)
	_reset_managers(true)  ## force_yanbing：演兵流程，不依赖 is_multiplayer（安卓可能时序不准）
	_rpc_sync_to_battle.rpc(seed_value, pc)
	get_tree().change_scene_to_file(BATTLE_SCENE)


@rpc("authority")
func _rpc_sync_to_battle(seed_value: int, player_count: int = 2) -> void:
	seed(seed_value)
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm != null:
		bm.set("player_count", clampi(player_count, 2, 8))
	_reset_managers(true)  ## force_yanbing：客户端收到同步，必定是演兵
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _reset_managers(force_yanbing: bool = false) -> void:
	var cm: Node = get_node_or_null("/root/CardManager")
	var bm: Node = get_node_or_null("/root/BattleManager")
	var mp: bool = is_multiplayer()
	var lunce_before: bool = bm.get("is_lunce_mode") if bm != null else false
	var gl: Node = _get_game_logger()
	if gl and gl.has_method("record"):
		gl.record("NetworkManager", "_reset_managers", {"mp": mp, "lunce": lunce_before, "force_yanbing": force_yanbing})
	## 演兵模式：force_yanbing 或 mp=true 时强制 is_lunce_mode=false，避免论策残留导致对手显示为 AI（安卓 is_multiplayer 可能时序不准）
	if bm != null:
		if force_yanbing or mp:
			bm.set("is_lunce_mode", false)
			print("[NetworkManager] _reset_managers: 演兵模式，已设 is_lunce_mode=false")
		elif lunce_before:
			bm.set("current_player_index", 0)
			print("[NetworkManager] _reset_managers: 论策模式，保留 is_lunce_mode，已设 current_player_index=0")
		else:
			bm.set("current_player_index", 0)
			print("[NetworkManager] _reset_managers: 单机/演兵未连接，已设 current_player_index=0")
	if cm and cm.has_method("reset_for_new_game"):
		cm.reset_for_new_game()
	if bm and bm.has_method("reset_to_start"):
		bm.reset_to_start()
		print("[NetworkManager] _reset_managers: reset_to_start 后 current_player_index=%s" % bm.get("current_player_index"))


## 获取本机局域网 IP（用于创建房间时显示给对手）
## 排除 127.0.0.1，优先返回 192.168.x.x 等内网地址
func get_local_lan_ip() -> String:
	var addrs: PackedStringArray = IP.get_local_addresses()
	for a: String in addrs:
		if a.begins_with("127.") or a == "::1":
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	if addrs.size() > 0:
		return addrs[0]
	return ""


## 是否处于联机模式（场景加载后依然有效）
func is_multiplayer() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## 本地玩家索引：主机=0，客户端=1；单机时恒为 0
func get_local_player_index() -> int:
	if not is_multiplayer():
		return 0
	return 0 if is_host else 1


## 全局判定：current_index 是否为本地玩家回合
func is_my_turn(current_index: int) -> bool:
	return current_index == get_local_player_index()


## 断开连接
func disconnect_peer() -> void:
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		peer.close()
		multiplayer.multiplayer_peer = null
	is_host = false
	opponent_id = -1


## 一方点击返回：通知对手弹窗并显示返回按钮，发起方立即退出
func request_exit_game() -> void:
	if is_multiplayer() and opponent_id >= 0:
		_rpc_opponent_exited.rpc_id(opponent_id)
	force_exit_to_main()


@rpc("any_peer")
func _rpc_opponent_exited() -> void:
	opponent_requested_exit.emit()


## 断开连接并跳转主菜单（无 RPC，供对手点击返回按钮后调用）
func force_exit_to_main() -> void:
	disconnect_peer()
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm != null:
		bm.set("return_to_mode_select", true)
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


## 重新开始：仅主机可调用，RPC 广播后双方同步重置并重载对决场景
func request_restart_game() -> void:
	var gl: Node = _get_game_logger()
	if gl:
		if gl.has_method("record"):
			gl.record("NetworkManager", "request_restart_game", {"mp": is_multiplayer()})
		if gl.has_method("flush"):
			gl.flush()
	if not is_multiplayer():
		_set_restart_flag()
		_reset_managers(false)
		get_tree().reload_current_scene()
		return
	if multiplayer.is_server():
		_set_restart_flag()
		_rpc_restart_game.rpc()
		_reset_managers(true)  ## 联机重开，保持演兵模式
		get_tree().reload_current_scene()


func _set_restart_flag() -> void:
	set_meta("_just_restarted", true)


## 重载后由 battle_test 检查，用于 log 提示
func consume_restart_flag() -> bool:
	if get_meta("_just_restarted", false):
		remove_meta("_just_restarted")
		return true
	return false


@rpc("authority")
func _rpc_restart_game() -> void:
	_set_restart_flag()
	_reset_managers(true)  ## 客户端收到重开，保持演兵模式
	get_tree().reload_current_scene()
