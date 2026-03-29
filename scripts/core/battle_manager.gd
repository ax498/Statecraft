## 战斗管理器（单例）
## 状态机：多玩家轮替、分数累加、抽牌按钮控制；联机时主机权威、种子同步
extends Node

enum State {
	START_BATTLE,
	PLAYER_TURN,
	PROCESSING,
	CONTRADICTION,
	GAME_OVER
}

## 通过场景树获取 GameLogger（避免 autoload 解析问题）
func _log_record(tag: String, action: String, data: Variant = "") -> void:
	var gl: Node = get_node_or_null("/root/GameLogger")
	if gl and gl.has_method("record"):
		gl.record(tag, action, data)

# ---- 信号 ----
signal can_draw_changed(can_draw: bool)
signal contradiction_started
signal contradiction_finished
signal score_updated(player_index: int, new_score: int)
signal turn_changed(player_index: int)
## winner_index: 0=玩家0胜, 1=玩家1胜, -1=平局；联机时客户端根据本地索引换算显示文本
## all_scores: 各玩家索引 -> 终局有效分（>2 人联机结算 UI 需用本地索引取分）
signal game_ended(result_text: String, player_score: int, opponent_score: int, all_scores: Dictionary)
## 神来之笔等 Mod 选择时锁定对手 UI
signal ui_lock_changed(locked: bool)
## 收牌动画同步：主机广播后双方同时触发，确保视觉对齐
signal hand_collection_requested(logic_player_index: int)
## 联机客户端专用：收到主机抽牌 RPC 后发出，供 battle_test 实时渲染回合牌堆
signal client_draw_received(card: CardResource)
## 联机客户端专用：收到主机消费抽牌 RPC 后发出
signal client_consumed_draw_received(card: CardResource)
## Mod 请求矛盾同款特效（仅视觉，不结束回合）：参数为需展示的卡牌数组
signal mod_contradiction_effect_requested(cards: Array)
## Mod 请求软特效（他山之石删牌等）：柔和发光+淡出，不震动不闪红，避免删牌逻辑问题
signal mod_soft_remove_effect_requested(cards: Array)
## 察言观色等：请求展示「下一张牌」给本地玩家，show_to_local=true 时显示
signal peek_card_display_requested(card: CardResource, show_to_local: bool)
## 九牛一毛：请求选择对手牌类型以夺取，drawer_index 为抽牌者
signal jiuniuyimao_selection_requested(drawer_index: int)
## 九牛一毛：夺取动画开始（在 transfer 前发出，供从手牌原位飞入回合区），drawer_index 为夺取者
signal jiuniuyimao_steal_animation_started(card: CardResource, opponent_index: int, hand_index: int, drawer_index: int)
## 九牛一毛：夺取的牌已加入回合区（联机客户端或无法找到原卡时用）
signal jiuniuyimao_card_added_to_turn(card: CardResource)
## 出奇制胜：请求选择对手牌类型以弃牌，drawer_index 为抽牌者
signal chuqizhisheng_selection_requested(drawer_index: int)
## 出奇制胜：弃牌特效（红发光消失），cards: [{card, player_index}]
signal chuqizhisheng_discard_effect_requested(cards: Array)
## 他山之石：请求弹窗选择（两阶段：一石二鸟 + 对手牌）
signal tashanzhishi_selection_requested(drawer_index: int)
## 偷梁换柱：请求选择回合区卡牌交换，drawer_index 为抽牌者
signal toulianghuanzhu_selection_requested(drawer_index: int)
## 偷梁换柱：交换动画请求，idx_a 与 idx_b 为 turn_container 索引
signal toulianghuanzhu_swap_requested(idx_a: int, idx_b: int)
## 箭在弦上：无抽牌滑入动画时（偷梁换柱交换后、九牛一毛夺取后）请求播放蓄力特效并强制再抽一张
signal jianzaixianshang_play_effect_requested(card: CardResource, player_index: int)

# ---- 状态与数据 ----
## Mod 劫持模式：为 true 时 draw_animation_finished 不自动切换回合
var mod_pause_settlement: bool = false
## 从对决返回时：为 true 则主菜单显示模式选择界面
var return_to_mode_select: bool = false
## 论策模式标志：从主菜单论策进入时设为 true，battle_test 按单机逻辑处理（不受 is_multiplayer 影响）
var is_lunce_mode: bool = false
var current_state: State = State.START_BATTLE
## 玩家数量（2~8），影响 player_scores、next_turn、布局
var player_count: int = 2
var player_scores: Dictionary = {0: 0, 1: 0}
var current_player_index: int = 0
## 神来之笔选择时：对手端 UI 被锁定
var ui_locked: bool = false
## 联机时客户端抽到神来之笔：主机通知后客户端需在 draw_animation_finished 中触发 post_draw_animation
var mod_copy_mode_pending: bool = false
var mod_copy_mode_player_index: int = 0
## 联机时客户端抽到他山之石：主机在 post_draw_card 中通知，客户端在 draw_animation_finished 中触发 post_draw_animation
var mod_tashanzhishi_pending: bool = false
var mod_tashanzhishi_player_index: int = 0
## 九牛一毛：抽到且对手有牌时进入选择模式
var mod_jiuniuyimao_pending: bool = false
var mod_jiuniuyimao_player_index: int = 0
## 出奇制胜：抽到且对手有牌时进入选择模式
var mod_chuqizhisheng_pending: bool = false
var mod_chuqizhisheng_player_index: int = 0
## 偷梁换柱：抽到且回合区至少 2 张时进入选择模式
var mod_toulianghuanzhu_pending: bool = false
var mod_toulianghuanzhu_drawer_index: int = 0
## 偷梁换柱：交换动画完成后触发被选牌效果，格式 {card, player_index}
var _pending_toulianghuanzhu_effect: Dictionary = {}
## 九牛一毛夺取见好就收：等飞牌动画完成再 settle，-1 表示无等待
var _pending_jiuniuyimao_stolen_stop_settle: int = -1
## 九牛一毛夺取出奇制胜/九牛一毛：等飞牌动画完成再触发被夺取牌效果，空字典表示无等待
var _pending_stolen_card_deferred: Dictionary = {}
## 收牌动画：等动画完成再切换回合，-1 表示无等待
var _awaiting_collection_next_index: int = -1
## 特效阻塞：为 true 时游戏逻辑不推进，由 battle_test 在特效开始/结束时设置
var effect_playing: bool = false
## AI 行动调度去重：避免同一回合挂出多个 timer，导致下家 AI 连续行动
var _ai_turn_schedule_id: int = 0
var _ai_turn_scheduled_player_index: int = -1
## 回合切换后首次抽牌前清空 turn_container，避免跨回合残留导致误判矛盾
var _just_switched_turn: bool = false
## 矛盾触发时暂存数据，供延迟过渡与 RPC 使用
var _pending_contradiction: Dictionary = {}
## 论策模式：玩家显示名，0=玩家，1..n-1=AI 名字（春秋战国风格）
var player_display_names: Dictionary = {}

## 供 battle_test 调用：特效开始/结束时设置，游戏逻辑在 effect_playing 期间不推进
func set_effect_playing(playing: bool) -> void:
	effect_playing = playing

func is_effect_playing() -> bool:
	return effect_playing


func _cancel_ai_turn_schedule() -> void:
	_ai_turn_schedule_id += 1
	_ai_turn_scheduled_player_index = -1

const CARD_MANAGER_PATH: String = "/root/CardManager"
const MOD_LOADER_PATH: String = "/root/ModLoader"
const AI_NAMES_SCRIPT: GDScript = preload("res://resources/ai_names.gd")

## 缓存 Autoload 引用，避免重复 get_node
var _card_manager: Node
var _mod_loader: Node
var _network_manager: Node
const CONTRADICTION_DURATION: float = 1.1
const AI_DRAW_DELAY: float = 1.0
## 总分上限，超过则触发矛盾（顺手牵羊等效果修改后的最终分数）
const SCORE_LIMIT: int = 13
## 矛盾提示延迟，确保分数 Label 先更新再弹出
const CONTRADICTION_UI_DELAY: float = 0.25
## 见好就收：由 battle_test 特效结束后回调，不再使用固定延迟

## 联机：player_index 0=主机(peer 1)，1=客户端(peer 2)
## 论策模式强制返回 false，确保单机/联机逻辑完全分离
func _is_multiplayer() -> bool:
	if is_lunce_mode:
		return false
	var peer_ok: bool = multiplayer.multiplayer_peer != null
	var status_ok: bool = peer_ok and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	return status_ok

func _peer_id_for_player(pi: int) -> int:
	return pi + 1  # 0->1(host), 1->2(client)


## 联机时获取对手 peer_id（主机 RPC 用），无连接时返回 2（客户端默认）
func _get_opponent_peer_id() -> int:
	if _network_manager == null:
		return 2
	var oid_val = _network_manager.get("opponent_id")
	var oid: int = int(oid_val) if oid_val != null else -1
	return oid if oid >= 0 else 2


## 指定索引是否为 AI：论策 1..N-1 为 AI；联机 2..N-1 为 AI（主机执行）；供「当前回合」与「抽牌者」共用
func _is_player_index_ai(player_index: int) -> bool:
	if is_lunce_mode:
		return player_index != 0
	## 联机：2 人对战无 AI；is_multiplayer 可能因安卓时序误报，用 peer 状态兜底
	var nm: Node = _network_manager
	if nm != null and nm.get("is_host") == false:
		return false  ## 客户端视角：对手是真人，不自动执行
	if not _is_multiplayer():
		return player_index != 0
	return multiplayer.is_server() and player_index >= 2


## 当前回合是否为 AI 控制
func _is_current_player_ai() -> bool:
	return _is_player_index_ai(current_player_index)


func _ensure_player_scores_size() -> void:
	for i in range(player_count):
		if not player_scores.has(i):
			player_scores[i] = 0


func _serialize_cards(cards: Array) -> Array:
	var result: Array = []
	for c in cards:
		if c is CardResource:
			result.append({
				"card_name": c.card_name,
				"effect_value": c.effect_value,
				"ability_id": c.ability_id,
				"count_towards_contradiction": c.count_towards_contradiction,
				"force_ends_turn": c.force_ends_turn
			})
	return result

## 供 UI/Mod 调用：当前是否为本地玩家回合（委托 NetworkManager 判定）
func is_my_turn() -> bool:
	if is_lunce_mode:
		return current_player_index == 0  # 论策模式：玩家索引恒为 0
	var nm: Node = _network_manager
	if nm != null and nm.has_method("is_my_turn"):
		return nm.call("is_my_turn", current_player_index)
	return current_player_index == 0  # 单机：仅玩家 0 可操作


func _is_my_turn() -> bool:
	return is_my_turn()


## 重置为开始状态，供重新开始使用
func reset_to_start() -> void:
	_transition_to(State.START_BATTLE)


## 新一局开始前清除上一局残留的阻塞标志（否则重启/重载后无法抽牌）
func _reset_transient_battle_state() -> void:
	effect_playing = false
	mod_pause_settlement = false
	mod_copy_mode_pending = false
	mod_tashanzhishi_pending = false
	mod_jiuniuyimao_pending = false
	mod_chuqizhisheng_pending = false
	mod_toulianghuanzhu_pending = false
	_pending_toulianghuanzhu_effect = {}
	_pending_jiuniuyimao_stolen_stop_settle = -1
	_pending_stolen_card_deferred = {}
	_awaiting_collection_next_index = -1
	_pending_contradiction = {}
	if ui_locked:
		ui_locked = false
		ui_lock_changed.emit(false)
	if _mod_loader != null:
		_mod_loader.trigger_hook("tashanzhishi_selection_finished", [])


## 对决初始化（伪代码对应）：创建牌堆、创建玩家列表、状态设为抽牌
## 供 main_menu 论策/演兵确认后、切换战斗场景前调用
func init_duel() -> void:
	var cm: Node = _card_manager
	cm.reset_for_new_game()
	reset_to_start()


func _ready() -> void:
	_card_manager = get_node(CARD_MANAGER_PATH)
	_mod_loader = get_node(MOD_LOADER_PATH)
	_network_manager = get_node_or_null("/root/NetworkManager")
	_card_manager.card_drawn.connect(_on_card_drawn)
	_card_manager.contradiction_triggered.connect(_on_contradiction)
	_card_manager.score_contradiction_triggered.connect(_on_score_contradiction)
	_card_manager.force_end_turn.connect(_on_force_end_turn)
	_card_manager.turn_settled.connect(_on_turn_settled)
	_transition_to(State.START_BATTLE)


func _transition_to(new_state: State) -> void:
	if new_state != State.PLAYER_TURN:
		_cancel_ai_turn_schedule()
	current_state = new_state
	_log_record("BattleManager", "transition_to", {"state": new_state, "current_player": current_player_index})
	match new_state:
		State.START_BATTLE:
			_reset_transient_battle_state()
			_ensure_player_scores_size()
			for i in range(player_count):
				player_scores[i] = 0
				score_updated.emit(i, 0)
			current_player_index = 0
			_just_switched_turn = false
			_init_player_display_names()
			_transition_to(State.PLAYER_TURN)
		State.PLAYER_TURN:
			_update_ui_state()
			if _is_current_player_ai():
				call_deferred("_start_ai_turn")
		State.PROCESSING:
			can_draw_changed.emit(false)
		State.CONTRADICTION:
			can_draw_changed.emit(false)
			mod_tashanzhishi_pending = false
			mod_toulianghuanzhu_pending = false
			## 矛盾清空回合区，九牛一毛/出奇制胜等「待选择」已失效，必须清除，否则下次抽牌会误走旧分支、卡住流程
			mod_jiuniuyimao_pending = false
			mod_chuqizhisheng_pending = false
			_mod_loader.trigger_hook("tashanzhishi_selection_finished", [])
			set_effect_playing(true)
			contradiction_started.emit()
			## 联机时同步矛盾数据到客户端
			if _is_multiplayer() and multiplayer.is_server():
				var cd: Array = _pending_contradiction.get("cards_data", [])
				var pi_arr: Array = _pending_contradiction.get("protected_indices", [])
				var pidx: int = int(_pending_contradiction.get("player_index", 0))
				_rpc_contradiction_triggered.rpc(cd, pi_arr, pidx)
			get_tree().create_timer(CONTRADICTION_DURATION).timeout.connect(_on_contradiction_timeout)
		State.GAME_OVER:
			can_draw_changed.emit(false)


func _init_player_display_names() -> void:
	player_display_names.clear()
	if is_lunce_mode:
		player_display_names[0] = "玩家"
		var names_pool: Array = AI_NAMES_SCRIPT.get_shuffled_names() if AI_NAMES_SCRIPT else []
		for i in range(1, player_count):
			player_display_names[i] = names_pool.pop_back() if not names_pool.is_empty() else ("对手%d" % i)
	else:
		## 联机：按本地视角设置「玩家」「对手」，避免安卓等误识别人机
		var nm: Node = _network_manager
		var local_idx: int = 0
		if nm != null and nm.has_method("get_local_player_index"):
			local_idx = nm.call("get_local_player_index")
		for i in range(player_count):
			player_display_names[i] = "玩家" if i == local_idx else "对手"


## 供 UI 获取玩家显示名（论策：玩家/AI名；联机：玩家/对手）
func get_player_display_name(pi: int) -> String:
	if player_display_names.has(pi):
		return str(player_display_names[pi])
	if pi == 0:
		return "玩家"
	return "对手%d" % pi


func _on_contradiction_timeout() -> void:
	if current_state == State.CONTRADICTION:
		contradiction_finished.emit()
		## next_turn 由 battle_test 在矛盾淡出特效结束后调用 contradiction_effect_complete 执行


func _start_ai_turn() -> void:
	if effect_playing or current_state != State.PLAYER_TURN or not _is_current_player_ai():
		return
	if _ai_turn_scheduled_player_index == current_player_index:
		return
	_ai_turn_schedule_id += 1
	var schedule_id: int = _ai_turn_schedule_id
	var scheduled_player_index: int = current_player_index
	_ai_turn_scheduled_player_index = scheduled_player_index
	get_tree().create_timer(AI_DRAW_DELAY).timeout.connect(func() -> void:
		if schedule_id != _ai_turn_schedule_id:
			return
		_ai_turn_scheduled_player_index = -1
		if current_player_index != scheduled_player_index:
			return
		_ai_draw_or_end()
	)


## 供 battle_test 调用：论策模式下若已是对手回合，确保 AI 会行动（防止加载时 timer 未触发）
func ensure_ai_turn_started() -> void:
	if _is_current_player_ai() and current_state == State.PLAYER_TURN:
		_start_ai_turn()


## 处理九牛一毛/出奇制胜/偷梁换柱待定选择：若有待定则执行并返回 true
func _try_handle_pending_selection_modes() -> bool:
	if mod_jiuniuyimao_pending:
		if _is_player_index_ai(mod_jiuniuyimao_player_index):
			_auto_jiuniuyimao_select()
		else:
			jiuniuyimao_selection_requested.emit(mod_jiuniuyimao_player_index)
		return true
	if mod_chuqizhisheng_pending:
		if _is_player_index_ai(mod_chuqizhisheng_player_index):
			_auto_chuqizhisheng_select()
		else:
			chuqizhisheng_selection_requested.emit(mod_chuqizhisheng_player_index)
		return true
	if mod_toulianghuanzhu_pending:
		if _is_player_index_ai(mod_toulianghuanzhu_drawer_index):
			_auto_toulianghuanzhu_select()
		else:
			toulianghuanzhu_selection_requested.emit(mod_toulianghuanzhu_drawer_index)
		return true
	return false


func _ai_draw_or_end() -> void:
	if effect_playing or current_state != State.PLAYER_TURN or not _is_current_player_ai():
		return
	var cm: Node = _card_manager
	var turn_size: int = cm.turn_container.size()
	var next_card: Variant = cm.peek_next_card() if cm.has_method("peek_next_card") else null
	var args: Array = [null]  # args[0] = true 强制抽牌, false 强制结束, null 使用默认
	# 察言观色（核心）：若 AI 刚抽到，下一张会导致矛盾则结束回合
	var turn_cards: Array = cm.turn_container
	if next_card != null and turn_cards.size() > 0:
		var last: Variant = turn_cards[-1]
		var aid: String = last.ability_id if last is CardResource else str(last.get("ability_id", ""))
		if aid == "chayanguanse":
			var names_seen: Dictionary = {}
			for c in turn_cards:
				if not (c is CardResource):
					continue
				if not c.count_towards_contradiction or c.card_name.is_empty():
					continue
				names_seen[c.card_name] = c
			var next_name: String = next_card.card_name if next_card is CardResource else str(next_card.get("card_name", ""))
			if next_card is CardResource and next_card.count_towards_contradiction and not next_name.is_empty():
				if names_seen.has(next_name):
					args[0] = false
	# Mod 可覆盖
	_mod_loader.trigger_hook("ai_draw_decision", [args, cm.turn_container.duplicate(), next_card])
	var override: Variant = args[0] if args.size() > 0 else null
	if override == true:
		request_draw()
		return
	if override == false:
		request_end_turn()
		return
	# 默认策略：已有 2 张且未炸，50% 结束回合
	if turn_size >= 2 and randf() < 0.5:
		request_end_turn()
	else:
		request_draw()


## 切换回合：主机为唯一权威，计算新索引后广播；非联机时本地直接执行
func next_turn() -> void:
	var new_index: int = (current_player_index + 1) % player_count
	if not _is_multiplayer():
		_apply_turn_switch(new_index)  # 单机/论策：本地直接执行
	elif multiplayer.is_server():
		_rpc_sync_turn.rpc(new_index)
		# 客户端绝不自行修改 current_player_index，等待 RPC 同步


## 内部：执行回合切换（设置索引、清空回合牌堆、过渡、更新 UI、检查结束）
## 联机时仅主机执行 _check_game_end（客户端 global_deck 不同步，禁止计算）
func _apply_turn_switch(new_index: int) -> void:
	current_player_index = new_index
	var cm: Node = _card_manager
	cm.turn_container.clear()
	_just_switched_turn = true
	_transition_to(State.PLAYER_TURN)  # 内部会调用 _update_ui_state()
	if not _is_multiplayer() or multiplayer.is_server():
		_check_game_end()


## 权威同步 RPC：主机广播后，强制双方 current_player_index 对齐并执行回合切换
@rpc("authority", "call_local")
func _rpc_sync_turn(new_index: int) -> void:
	_apply_turn_switch(new_index)


## 实时有效分数：手牌分 + 回合牌堆分（仅抽到最后一张牌的玩家，且未触发矛盾时加回合分）
func get_effective_score(player_index: int) -> int:
	var cm: Node = _card_manager
	var hand_score: int = cm.compute_hand_score(player_index) if cm.has_method("compute_hand_score") else 0
	if player_index == current_player_index and _pending_contradiction.is_empty() and current_state != State.CONTRADICTION:
		var turn_score: int = cm.compute_turn_score() if cm.has_method("compute_turn_score") else 0
		return hand_score + turn_score
	return hand_score


## cheek（伪代码对应）：牌堆空则游戏结束，返回 true
func cheek() -> bool:
	var cm: Node = _card_manager
	if cm.global_deck.is_empty():
		_check_game_end()
		return true
	return false


func _check_game_end() -> void:
	var cm: Node = _card_manager
	if not cm.global_deck.is_empty():
		return
	_transition_to(State.GAME_OVER)
	can_draw_changed.emit(false)
	var winner_index: int = -1
	var max_score: int = -1
	for i in range(player_count):
		var s: int = get_effective_score(i)
		if s > max_score:
			max_score = s
			winner_index = i
	var tied: bool = false
	for i in range(player_count):
		if i != winner_index and get_effective_score(i) == max_score:
			tied = true
			break
	if tied:
		winner_index = -1
	var all_scores: Dictionary = {}
	for i in range(player_count):
		all_scores[i] = get_effective_score(i)
	var p: int = int(all_scores.get(0, 0))
	var o: int = int(all_scores.get(1, 0)) if player_count > 1 else 0
	var result_text: String = _result_text_for_local(winner_index, 0)
	game_ended.emit(result_text, p, o, all_scores)
	if _is_multiplayer() and multiplayer.is_server():
		_rpc_game_ended.rpc(winner_index, p, o, all_scores)


## 根据 winner_index 和本地玩家索引计算显示文本
func _result_text_for_local(winner_index: int, local_player_index: int) -> String:
	if winner_index < 0:
		return "平分秋色"
	if winner_index == local_player_index:
		return "大获全胜"
	return "棋差一招"


@rpc("authority")
func _rpc_game_ended(winner_index: int, player_score: int, opponent_score: int, all_scores: Dictionary) -> void:
	_transition_to(State.GAME_OVER)
	can_draw_changed.emit(false)
	var nm: Node = _network_manager
	var local_idx: int = 0
	if nm != null and nm.has_method("get_local_player_index"):
		local_idx = nm.call("get_local_player_index")
	var result_text: String = _result_text_for_local(winner_index, local_idx)
	game_ended.emit(result_text, player_score, opponent_score, all_scores)


## 由 UI 调用：请求抽牌（联机时仅当前玩家可发起，客户端通过 RPC 请求主机执行）
## 单机时 AI(current_player_index==1) 也可调用
func request_draw() -> void:
	if effect_playing or current_state != State.PLAYER_TURN:
		return
	if current_player_index < 0 or current_player_index >= player_count:
		return
	# 允许：我的回合 或 单机模式下 AI 的回合
	if not _is_my_turn() and not _is_current_player_ai():
		return
	var cm: Node = _card_manager
	if cm.global_deck.is_empty():
		_check_game_end()
		return

	if _is_multiplayer():
		if multiplayer.is_server():
			_execute_draw()
		else:
			_rpc_request_draw.rpc_id(1)
	else:
		_transition_to(State.PROCESSING)
		cm.draw_card(current_player_index)


## 箭在弦上：特效结束后强制抽牌，绕过 effect_playing 与 PLAYER_TURN 检查
func request_force_draw_after_effect() -> void:
	if current_player_index < 0 or current_player_index >= player_count:
		return
	var cm: Node = _card_manager
	if cm.global_deck.is_empty():
		_check_game_end()
		return
	if _is_multiplayer():
		if multiplayer.is_server():
			_execute_draw()
		else:
			_rpc_request_draw.rpc_id(1)
	else:
		_transition_to(State.PROCESSING)
		cm.draw_card(current_player_index)


func _execute_draw() -> void:
	_transition_to(State.PROCESSING)
	var cm: Node = _card_manager
	## 新回合首次抽牌前清空残留，避免跨回合误判矛盾；同一回合多次抽牌（如 Mod 额外行动）不清空
	if _just_switched_turn:
		_just_switched_turn = false
		cm.turn_container.clear()
	var result: Array = cm.draw_card(current_player_index)
	var card: CardResource = result[1] as CardResource if result.size() > 1 else null
	if card != null:
		var card_data: Dictionary = {
			"card_name": card.card_name,
			"effect_value": card.effect_value,
			"ability_id": card.ability_id,
			"count_towards_contradiction": card.count_towards_contradiction,
			"force_ends_turn": card.force_ends_turn
		}
		var deck_count: int = cm.global_deck.size()
		## 矛盾时 turn_container 已清空，不发送 draw RPC，由 _rpc_contradiction_triggered 统一同步
		if not _pending_contradiction.is_empty():
			pass  # 矛盾流程会 RPC 完整 involved
		elif card in cm.turn_container:
			_rpc_apply_draw.rpc(current_player_index, card_data, deck_count)
		else:
			_rpc_apply_consumed_draw.rpc(current_player_index, card_data, deck_count)


@rpc("any_peer")
func _rpc_request_draw() -> void:
	if multiplayer.is_server() and current_state == State.PLAYER_TURN:
		_execute_draw()


## 主机权威：客户端根据卡牌数据生成显示，不调用 draw_card_at_index
@rpc("authority")
func _rpc_apply_draw(player_index: int, card_data: Dictionary, deck_count: int) -> void:
	_transition_to(State.PROCESSING)
	var cm: Node = _card_manager
	cm.apply_draw_from_data(player_index, card_data, deck_count)
	## 联机客户端：显式发出信号确保 battle_test 实时渲染回合牌堆（不依赖 _is_multiplayer，安卓可能误报）
	if not multiplayer.is_server():
		var tc: Array = cm.get("turn_container")
		if not tc.is_empty():
			client_draw_received.emit(tc[-1])


## 主机权威：卡牌被 Mod 消费时，客户端仅显示消费特效，不加入回合区
## 若为他山之石且抽牌者为本地玩家，在此设置 mod_tashanzhishi_pending，避免 RPC 到达顺序导致漏设
@rpc("authority")
func _rpc_apply_consumed_draw(player_index: int, card_data: Dictionary, deck_count: int) -> void:
	_transition_to(State.PROCESSING)
	if not multiplayer.is_server():
		var aid: String = str(card_data.get("ability_id", ""))
		if aid == "tashanzhishi":
			var nm: Node = _network_manager
			var local_idx: int = nm.call("get_local_player_index") if nm != null and nm.has_method("get_local_player_index") else 0
			if player_index == local_idx:
				mod_tashanzhishi_pending = true
				mod_tashanzhishi_player_index = player_index
	var cm: Node = _card_manager
	cm.apply_consumed_draw_from_data(player_index, card_data, deck_count)
	if not multiplayer.is_server():
		client_consumed_draw_received.emit(cm.create_card_from_data(card_data))


## 由 UI 调用：请求结束回合（手动结算）
## 单机时 AI(current_player_index==1) 也可调用
func request_end_turn() -> void:
	if effect_playing or current_state != State.PLAYER_TURN:
		return
	# 允许：我的回合 或 AI 的回合（论策/联机主机）
	if not _is_my_turn() and not _is_current_player_ai():
		return
	var cm: Node = _card_manager
	if cm.turn_container.is_empty():
		if _is_multiplayer() and not multiplayer.is_server():
			_rpc_request_empty_turn.rpc_id(1)
		else:
			next_turn()
		return

	if _is_multiplayer():
		if multiplayer.is_server():
			_execute_end_turn()
		else:
			_rpc_request_end_turn.rpc_id(1)
	else:
		_transition_to(State.PROCESSING)
		cm.settle_turn(current_player_index)
		_on_turn_settled_manual()


func _execute_end_turn() -> void:
	_transition_to(State.PROCESSING)
	var player_who_ended: int = current_player_index
	var cm: Node = _card_manager
	# 1. 主机结算并捕获卡牌数据
	var cards_data: Array = []
	for card in cm.turn_container:
		cards_data.append({
			"card_name": card.card_name,
			"effect_value": card.effect_value,
			"ability_id": card.ability_id,
			"count_towards_contradiction": card.count_towards_contradiction,
			"force_ends_turn": card.force_ends_turn
		})
	cm.settle_turn(player_who_ended)  # 主机执行完整结算（含 Mod 钩子）
	var next_index: int = (current_player_index + 1) % player_count
	# 2. 先发结算结果（客户端需先应用数据），再发收牌动画，确保在 current_player_index 切换前完成
	_rpc_apply_settlement_result.rpc(player_who_ended, cards_data, player_scores[0], player_scores[1], next_index)
	_rpc_sync_hand_collection.rpc(player_who_ended)
	_awaiting_collection_next_index = next_index  # 阻塞：等收牌动画完成再切换


@rpc("any_peer")
func _rpc_request_end_turn() -> void:
	if multiplayer.is_server() and current_state == State.PLAYER_TURN:
		_execute_end_turn()


@rpc("any_peer")
func _rpc_request_empty_turn() -> void:
	if multiplayer.is_server() and current_state == State.PLAYER_TURN:
		next_turn()


## 收牌动画同步：在 current_player_index 切换前触发，双方同时执行收牌动画
@rpc("authority", "call_local")
func _rpc_sync_hand_collection(logic_player_index: int) -> void:
	hand_collection_requested.emit(logic_player_index)


## 客户端专用：仅应用主机发来的结算结果，禁止任何计算
@rpc("authority")
func _rpc_apply_settlement_result(player_who_ended: int, cards_data: Array, score_0: int, score_1: int, next_index: int) -> void:
	_transition_to(State.PROCESSING)
	var cm: Node = _card_manager
	cm.apply_settlement_result(player_who_ended, cards_data, score_0, score_1)
	player_scores[0] = score_0
	player_scores[1] = score_1
	score_updated.emit(0, score_0)
	score_updated.emit(1, score_1)
	_apply_turn_switch(next_index)


## 客户端专用：Mod 结算（不切换回合），仅应用数据
@rpc("authority")
func _rpc_apply_mod_settlement(player_who_ended: int, cards_data: Array, score_0: int, score_1: int) -> void:
	var cm: Node = _card_manager
	cm.apply_settlement_result(player_who_ended, cards_data, score_0, score_1)
	player_scores[0] = score_0
	player_scores[1] = score_1
	score_updated.emit(0, score_0)
	score_updated.emit(1, score_1)
	hand_collection_requested.emit(player_who_ended)  # 同步收牌动画
	_transition_to(State.PLAYER_TURN)
	_update_ui_state()


@rpc("authority")
func _rpc_update_ui_state(new_current_player_index: int) -> void:
	current_player_index = new_current_player_index
	_update_ui_state()


func _update_ui_state() -> void:
	## 显式委托 NetworkManager 判定：联机时根据 is_host 识别「我的回合」vs「对手回合」
	var is_me: bool
	if is_lunce_mode:
		is_me = (current_player_index == 0)  # 论策模式：玩家索引恒为 0
	else:
		var nm: Node = _network_manager
		if nm != null and nm.has_method("is_my_turn"):
			is_me = nm.call("is_my_turn", current_player_index)
		else:
			is_me = (current_player_index == 0)  # 单机默认玩家 0
	can_draw_changed.emit(is_me)
	turn_changed.emit(current_player_index)


@rpc("authority")
func _rpc_sync_scores(score_0: int, score_1: int) -> void:
	player_scores[0] = score_0
	player_scores[1] = score_1
	score_updated.emit(0, score_0)
	score_updated.emit(1, score_1)


func _on_turn_settled_manual() -> void:
	# 手动结束回合：阻塞等收牌动画完成再切换
	if current_state == State.PROCESSING:
		_awaiting_collection_next_index = (current_player_index + 1) % player_count


func _on_card_drawn(_card: Resource) -> void:
	pass


## 九牛一毛：抽到且对手有牌时进入选择模式，联机时通知客户端
func _on_jiuniuyimao_mode_requested(drawer_index: int) -> void:
	mod_pause_settlement = true
	mod_jiuniuyimao_pending = true
	mod_jiuniuyimao_player_index = drawer_index
	if _is_multiplayer() and multiplayer.is_server() and drawer_index != 0:
		_rpc_jiuniuyimao_mode_started.rpc_id(_get_opponent_peer_id(), drawer_index)


@rpc("authority")
func _rpc_jiuniuyimao_mode_started(drawer_index: int) -> void:
	mod_pause_settlement = true
	mod_jiuniuyimao_pending = true
	mod_jiuniuyimao_player_index = drawer_index
	## 客户端收到即需选择，立即 emit 显示 UI（九牛一毛夺取后无 draw_animation_finished）
	if _is_player_index_ai(drawer_index):
		_auto_jiuniuyimao_select()
	else:
		jiuniuyimao_selection_requested.emit(drawer_index)


## 出奇制胜：抽到且对手有牌时进入选择模式，联机时通知客户端
func _on_chuqizhisheng_mode_requested(drawer_index: int) -> void:
	mod_pause_settlement = true
	mod_chuqizhisheng_pending = true
	mod_chuqizhisheng_player_index = drawer_index
	if _is_multiplayer() and multiplayer.is_server() and drawer_index != 0:
		_rpc_chuqizhisheng_mode_started.rpc_id(_get_opponent_peer_id(), drawer_index)


@rpc("authority")
func _rpc_chuqizhisheng_mode_started(drawer_index: int) -> void:
	mod_pause_settlement = true
	mod_chuqizhisheng_pending = true
	mod_chuqizhisheng_player_index = drawer_index
	## 客户端收到即需选择，立即 emit 显示 UI（九牛一毛夺取后无 draw_animation_finished）
	if _is_player_index_ai(drawer_index):
		_auto_chuqizhisheng_select()
	else:
		chuqizhisheng_selection_requested.emit(drawer_index)


## 偷梁换柱：抽到且回合区至少 2 张时进入选择模式，联机时通知客户端
func _on_toulianghuanzhu_selection_requested(drawer_index: int) -> void:
	mod_pause_settlement = true
	mod_toulianghuanzhu_pending = true
	mod_toulianghuanzhu_drawer_index = drawer_index
	if _is_multiplayer() and multiplayer.is_server() and drawer_index != 0:
		_rpc_toulianghuanzhu_mode_started.rpc_id(_get_opponent_peer_id(), drawer_index)


@rpc("authority")
func _rpc_toulianghuanzhu_mode_started(drawer_index: int) -> void:
	mod_pause_settlement = true
	mod_toulianghuanzhu_pending = true
	mod_toulianghuanzhu_drawer_index = drawer_index
	## 客户端收到即需选择，立即 emit 显示 UI（九牛一毛夺取偷梁换柱后无 draw_animation_finished）
	if _is_player_index_ai(drawer_index):
		_auto_toulianghuanzhu_select()
	else:
		toulianghuanzhu_selection_requested.emit(drawer_index)


## 察言观色：仅当抽牌者为本地玩家时展示下一张牌（AI/联机对手抽到则不展示）
## 联机时客户端抽到需 RPC 窥牌结果，因客户端牌堆未同步
func _on_chayanguanse_peek_requested(next_card: CardResource, drawer_index: int) -> void:
	var local_idx: int = 0
	if is_lunce_mode:
		pass
	else:
		var nm: Node = _network_manager
		if nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer"):
			local_idx = nm.call("get_local_player_index")
	var show_to_local: bool = (drawer_index == local_idx)
	if _is_multiplayer() and multiplayer.is_server() and drawer_index != local_idx:
		# 联机：客户端抽到时，主机 RPC 窥牌结果给客户端（客户端牌堆未同步，不能本地 peek）
		var card_data: Dictionary = {
			"card_name": next_card.card_name,
			"effect_value": next_card.effect_value,
			"ability_id": next_card.ability_id,
			"count_towards_contradiction": next_card.count_towards_contradiction,
			"force_ends_turn": next_card.force_ends_turn
		}
		_rpc_peek_card_to_client.rpc_id(_get_opponent_peer_id(), card_data)
	request_peek_display(next_card, show_to_local)


@rpc("authority")
func _rpc_peek_card_to_client(card_data: Dictionary) -> void:
	var card: CardResource = _card_manager.create_card_from_data(card_data)
	request_peek_display(card, true)


func _on_contradiction(involved_cards: Array, protected_indices: Array, player_index: int) -> void:
	_pending_contradiction = {
		"cards_data": _serialize_cards(involved_cards),
		"protected_indices": protected_indices,
		"player_index": player_index
	}
	_do_contradiction_transition()


func _on_score_contradiction(player_index: int, _card: Resource, scores_before: Dictionary) -> void:
	_pending_contradiction = {"cards_data": [], "protected_indices": [], "player_index": player_index}
	get_tree().create_timer(CONTRADICTION_UI_DELAY).timeout.connect(func() -> void:
		if current_state == State.PROCESSING or current_state == State.PLAYER_TURN:
			player_scores[0] = scores_before.get(0, 0)
			player_scores[1] = scores_before.get(1, 0)
			score_updated.emit(0, player_scores[0])
			score_updated.emit(1, player_scores[1])
			if _is_multiplayer() and multiplayer.is_server():
				_rpc_sync_scores.rpc(player_scores[0], player_scores[1])
			_transition_to(State.CONTRADICTION)
	)


func _do_contradiction_transition() -> void:
	# 延迟过渡，确保分数 Label 动画先于矛盾提示
	get_tree().create_timer(CONTRADICTION_UI_DELAY).timeout.connect(func() -> void:
		if current_state == State.PROCESSING or current_state == State.PLAYER_TURN:
			_transition_to(State.CONTRADICTION)
	)


## 主机权威：矛盾触发时同步客户端（应用保护卡牌到手牌、清空 turn_container、触发 UI、过渡到 CONTRADICTION）
## cards_data: involved 卡牌数据数组；protected_indices: 被保护索引；player_index: 回合玩家
@rpc("authority")
func _rpc_contradiction_triggered(cards_data: Array, protected_indices: Array, player_index: int) -> void:
	var cm: Node = _card_manager
	var hands: Array = cm.player_hands.get(player_index, [])
	for i in protected_indices:
		if i >= 0 and i < cards_data.size():
			hands.append(cm.create_card_from_data(cards_data[i]))
	cm.hand_updated.emit(player_index)
	cm.turn_container.clear()
	var involved: Array = []
	for d in cards_data:
		involved.append(cm.create_card_from_data(d))
	cm.emit_signal("contradiction_triggered", involved, protected_indices, player_index)
	_transition_to(State.CONTRADICTION)


func _on_force_end_turn() -> void:
	if current_state != State.PROCESSING:
		return
	mod_pause_settlement = false  # 矛盾触发时解除 Mod 劫持
	var cm: Node = _card_manager
	## 同名矛盾时 trigger_contradiction 已清空 turn_container，不执行强制结算，由矛盾流程负责 next_turn
	if cm.turn_container.is_empty():
		return
	## 见好就收：锁定 UI，等 battle_test 特效结束后回调 complete_stop_card_effect
	var last_card: CardResource = cm.turn_container[-1] if cm.turn_container.size() > 0 else null
	var is_stop_card: bool = last_card != null and last_card.force_ends_turn
	if is_stop_card:
		ui_locked = true
		ui_lock_changed.emit(true)
		return
	if _is_multiplayer() and multiplayer.is_server():
		call_deferred("_execute_force_settle_and_next")
	else:
		cm.settle_turn(current_player_index)
		_transition_to(State.PLAYER_TURN)
		next_turn()


## 供 battle_test 调用：见好就收特效播放结束后立刻结算
func complete_stop_card_effect() -> void:
	ui_locked = false
	ui_lock_changed.emit(false)
	_do_force_settle_after_stop_delay()


## 供 battle_test 调用：收牌动画完成后执行回合切换（阻塞）
func collection_animation_finished() -> void:
	if _awaiting_collection_next_index < 0:
		return
	var next_index: int = _awaiting_collection_next_index
	_awaiting_collection_next_index = -1
	_apply_turn_switch(next_index)


## 供 battle_test 调用：矛盾淡出特效结束后执行 next_turn（阻塞）
func contradiction_effect_complete() -> void:
	if current_state != State.CONTRADICTION:
		return
	_pending_contradiction = {}
	set_effect_playing(false)
	next_turn()


## 供 battle_test 调用：九牛一毛飞牌动画完成后，先判断矛盾，无矛盾再触发被夺取牌效果
func complete_jiuniuyimao_steal_animation() -> void:
	if _pending_stolen_card_deferred.is_empty():
		return
	var card: CardResource = _pending_stolen_card_deferred.get("card", null)
	var steal_player_index: int = _pending_stolen_card_deferred.get("steal_player_index", 0)
	_pending_stolen_card_deferred = {}
	if card == null:
		return
	var cm: Node = _card_manager
	# 飞牌动画完成后先判断矛盾
	var dup: CardResource = cm.check_name_contradiction()
	if dup != null:
		cm.trigger_contradiction(dup, steal_player_index)
		mod_pause_settlement = false
		_log_record("BattleManager", "jiuniuyimao_contradiction_after_fly", {"dup": dup.card_name})
		return
	# 无矛盾：触发被夺取牌的效果
	_log_record("BattleManager", "jiuniuyimao_trigger_stolen_after_fly", {"card": card.card_name, "ability_id": card.ability_id, "player": steal_player_index})
	var consumed: bool = _trigger_stolen_card_effect(card, steal_player_index)
	if not consumed:
		mod_resume_without_settle()


## 供 battle_test 调用：九牛一毛夺取见好就收时，飞牌动画完成后执行 settle（阻塞）
func complete_jiuniuyimao_stolen_stop_settle() -> void:
	if _pending_jiuniuyimao_stolen_stop_settle < 0:
		return
	var steal_player_index: int = _pending_jiuniuyimao_stolen_stop_settle
	_pending_jiuniuyimao_stolen_stop_settle = -1
	var cm: Node = _card_manager
	if _is_multiplayer() and multiplayer.is_server():
		call_deferred("_execute_force_settle_and_next")
	else:
		cm.settle_turn(steal_player_index)
		_awaiting_collection_next_index = (steal_player_index + 1) % player_count
		hand_collection_requested.emit(steal_player_index)
		## 等收牌动画完成后再切换，由 collection_animation_finished 执行


func _do_force_settle_after_stop_delay() -> void:
	var cm: Node = _card_manager
	if cm.turn_container.is_empty():
		return
	if _is_multiplayer() and multiplayer.is_server():
		call_deferred("_execute_force_settle_and_next")
	else:
		cm.settle_turn(current_player_index)
		_awaiting_collection_next_index = (current_player_index + 1) % player_count
		hand_collection_requested.emit(current_player_index)
		## 等收牌动画完成后再切换，由 collection_animation_finished 执行


## 主机专用：「见好就收」等强制结束时，通过 RPC 广播结算与回合切换
func _execute_force_settle_and_next() -> void:
	var player_who_ended: int = current_player_index
	var cm: Node = _card_manager
	var cards_data: Array = []
	for card in cm.turn_container:
		cards_data.append({
			"card_name": card.card_name,
			"effect_value": card.effect_value,
			"ability_id": card.ability_id,
			"count_towards_contradiction": card.count_towards_contradiction,
			"force_ends_turn": card.force_ends_turn
		})
	cm.settle_turn(player_who_ended)
	var next_index: int = (current_player_index + 1) % player_count
	_rpc_force_settle_and_next.rpc(player_who_ended, cards_data, player_scores[0], player_scores[1], next_index)
	_rpc_sync_hand_collection.rpc(player_who_ended)
	_awaiting_collection_next_index = next_index  # 阻塞：等收牌动画完成再切换


## 客户端专用：应用主机发来的强制结算结果并切换回合
@rpc("authority")
func _rpc_force_settle_and_next(player_who_ended: int, cards_data: Array, score_0: int, score_1: int, next_idx: int) -> void:
	_transition_to(State.PROCESSING)
	var cm: Node = _card_manager
	cm.apply_settlement_result(player_who_ended, cards_data, score_0, score_1)
	player_scores[0] = score_0
	player_scores[1] = score_1
	score_updated.emit(0, score_0)
	score_updated.emit(1, score_1)
	current_player_index = next_idx
	cm.turn_container.clear()
	hand_collection_requested.emit(player_who_ended)  # 客户端必须触发收牌动画，清空回合牌堆显示
	_transition_to(State.PLAYER_TURN)
	_update_ui_state()


func _on_turn_settled(turn_score: int) -> void:
	var args: Array = [current_player_index, turn_score]
	_mod_loader.trigger_hook("pre_turn_settled", args)
	## 分数改为实时手牌+回合，不再累加；同步 player_scores 供 Mod/RPC 使用
	for i in range(player_count):
		player_scores[i] = get_effective_score(i)
	_mod_loader.trigger_hook("post_turn_settled", [current_player_index, player_scores[current_player_index]])
	score_updated.emit(current_player_index, player_scores[current_player_index])
	if _is_multiplayer() and multiplayer.is_server():
		_rpc_sync_scores.rpc(player_scores[0], player_scores[1])


## 由 UI 在抽牌滑入动画结束后调用
## 联机时仅主机执行 Mod 钩子与 AI 逻辑；客户端仅做 UI 过渡，禁止任何计算
## 例外：客户端抽到神来之笔时，主机通过 _rpc_copy_mode_started 通知，客户端在此触发 post_draw_animation
func draw_animation_finished() -> void:
	_log_record("BattleManager", "draw_animation_finished", {"mod_pause": mod_pause_settlement})
	if current_state != State.PROCESSING:
		return
	## 矛盾流程已启动：由 battle_test 淡出特效结束后调用 contradiction_effect_complete，禁止此处切换回合
	if not _pending_contradiction.is_empty():
		return
	if _is_multiplayer() and not multiplayer.is_server():
		if mod_copy_mode_pending:
			_mod_loader.trigger_hook("sync_copy_mode", [mod_copy_mode_player_index])
			_mod_loader.trigger_hook("post_draw_animation", [mod_copy_mode_player_index])
			mod_copy_mode_pending = false
		elif mod_tashanzhishi_pending:
			_mod_loader.trigger_hook("sync_tashanzhishi_mode", [mod_tashanzhishi_player_index])
			_mod_loader.trigger_hook("post_draw_animation", [mod_tashanzhishi_player_index])
			mod_tashanzhishi_pending = false
		elif _try_handle_pending_selection_modes():
			pass
		_transition_to(State.PLAYER_TURN)
		return
	print("[BattleManager] draw_animation_finished: 触发 post_draw_animation current_player_index=%d mod_pause=%s" % [current_player_index, mod_pause_settlement])
	_mod_loader.trigger_hook("post_draw_animation", [current_player_index])
	_try_handle_pending_selection_modes()
	if mod_pause_settlement:
		return
	## 特效阻塞：任何特效播放中不推进游戏逻辑，等 battle_test 特效结束后再继续
	if effect_playing:
		return
	_transition_to(State.PLAYER_TURN)
	if _is_current_player_ai():
		_start_ai_turn()


## 主机在进入神来之笔复制模式且为客户端回合时调用，通知客户端触发 post_draw_animation
func request_sync_copy_mode_to_client(player_index: int) -> void:
	if not _is_multiplayer() or not multiplayer.is_server():
		return
	_rpc_copy_mode_started.rpc_id(_get_opponent_peer_id(), player_index)


@rpc("authority")
func _rpc_copy_mode_started(player_index: int) -> void:
	mod_copy_mode_pending = true
	mod_copy_mode_player_index = player_index


## 他山之石 Mod：客户端抽到时，主机在 post_draw_card 中调用，通知客户端在 draw_animation_finished 触发 sync+post_draw_animation
func request_mod_tashanzhishi_to_client(player_index: int) -> void:
	if not _is_multiplayer() or not multiplayer.is_server():
		return
	var opp_id: int = _get_opponent_peer_id()
	_log_record("BattleManager", "request_mod_tashanzhishi_to_client", {"player_index": player_index, "opp_id": opp_id})
	_rpc_tashanzhishi_mode_started.rpc_id(opp_id, player_index)


@rpc("authority")
func _rpc_tashanzhishi_mode_started(player_index: int) -> void:
	_log_record("BattleManager", "_rpc_tashanzhishi_mode_started", {"player_index": player_index})
	mod_tashanzhishi_pending = true
	mod_tashanzhishi_player_index = player_index


## 九牛一毛：选择完成后调用，selection: {card_name: String}
func request_jiuniuyimao_selection(selection: Dictionary) -> void:
	if _is_multiplayer() and not multiplayer.is_server():
		_rpc_jiuniuyimao_selection.rpc_id(1, selection)
	else:
		_apply_jiuniuyimao_selection(selection)


@rpc("any_peer")
func _rpc_jiuniuyimao_selection(selection: Dictionary) -> void:
	if multiplayer.is_server():
		_apply_jiuniuyimao_selection(selection)


func _apply_jiuniuyimao_selection(selection: Dictionary) -> void:
	mod_jiuniuyimao_pending = false
	var cm: Node = _card_manager
	var drawer_index: int = mod_jiuniuyimao_player_index
	var pc: int = clampi(player_count, 2, 8)
	var opponent_index: int = selection.get("opponent_index", 1 - drawer_index)
	if opponent_index < 0 or opponent_index >= pc or opponent_index == drawer_index:
		opponent_index = (drawer_index + 1) % pc if pc > 1 else 0
	var card_name: String = str(selection.get("card_name", ""))
	if card_name.is_empty():
		mod_resume_without_settle()
		return
	var hands: Array = cm.player_hands.get(opponent_index, [])
	var lowest: CardResource = null
	for c in hands:
		if not (c is CardResource):
			continue
		if c.card_name != card_name:
			continue
		if lowest == null or c.effect_value < lowest.effect_value:
			lowest = c
	if lowest == null:
		mod_resume_without_settle()
		return
	var hand_idx: int = hands.find(lowest)
	jiuniuyimao_steal_animation_started.emit(lowest, opponent_index, hand_idx, drawer_index)
	if not cm.transfer_card_from_hand_to_turn(opponent_index, lowest):
		mod_resume_without_settle()
		return
	jiuniuyimao_card_added_to_turn.emit(lowest)
	# 联机：同步夺取结果到客户端
	if _is_multiplayer() and multiplayer.is_server():
		var card_data: Dictionary = {
			"card_name": lowest.card_name,
			"effect_value": lowest.effect_value,
			"ability_id": lowest.ability_id,
			"count_towards_contradiction": lowest.count_towards_contradiction,
			"force_ends_turn": lowest.force_ends_turn
		}
		_rpc_jiuniuyimao_steal_result.rpc(opponent_index, hand_idx, card_data)
	# 阻塞：矛盾、被夺取牌效果全部延后到飞牌动画完成后再执行（由 complete_jiuniuyimao_steal_animation 调用）
	_pending_stolen_card_deferred = {"card": lowest, "steal_player_index": drawer_index}
	_log_record("BattleManager", "jiuniuyimao_post_fly_pending", {"card": lowest.card_name, "ability_id": lowest.ability_id, "player": drawer_index})


## 触发被夺取牌的效果，返回 true 表示已处理结束（如见好就收），无需 mod_resume
func _auto_jiuniuyimao_select() -> void:
	var cm: Node = _card_manager
	var drawer_index: int = mod_jiuniuyimao_player_index
	var pc: int = clampi(player_count, 2, 8)
	var opponents_with_cards: Array = []
	for pi in range(pc):
		if pi == drawer_index:
			continue
		var h: Array = cm.player_hands.get(pi, [])
		if not h.is_empty():
			opponents_with_cards.append(pi)
	if opponents_with_cards.is_empty():
		mod_jiuniuyimao_pending = false
		mod_resume_without_settle()
		return
	var chosen_opponent: int = opponents_with_cards[randi() % opponents_with_cards.size()]
	var chosen_hands: Array = cm.player_hands.get(chosen_opponent, [])
	var types_seen: Dictionary = {}
	for c in chosen_hands:
		if c is CardResource:
			types_seen[c.card_name] = true
	var types: Array = types_seen.keys()
	var pick: String = types[randi() % types.size()]
	_apply_jiuniuyimao_selection({"card_name": pick, "opponent_index": chosen_opponent})


## 出奇制胜：选择完成后调用，selection: {card_name: String}
func request_chuqizhisheng_selection(selection: Dictionary) -> void:
	if _is_multiplayer() and not multiplayer.is_server():
		_rpc_chuqizhisheng_selection.rpc_id(1, selection)
	else:
		_apply_chuqizhisheng_selection(selection)


@rpc("any_peer")
func _rpc_chuqizhisheng_selection(selection: Dictionary) -> void:
	if multiplayer.is_server():
		_apply_chuqizhisheng_selection(selection)


func _apply_chuqizhisheng_selection(selection: Dictionary) -> void:
	mod_chuqizhisheng_pending = false
	var cm: Node = _card_manager
	var drawer_index: int = mod_chuqizhisheng_player_index
	var pc: int = clampi(player_count, 2, 8)
	var opponent_index: int = selection.get("opponent_index", 1 - drawer_index)
	if opponent_index < 0 or opponent_index >= pc or opponent_index == drawer_index:
		opponent_index = (drawer_index + 1) % pc if pc > 1 else 0
	var card_name: String = str(selection.get("card_name", ""))
	if card_name.is_empty():
		mod_resume_without_settle()
		return
	var hands: Array = cm.player_hands.get(opponent_index, [])
	var highest: CardResource = null
	for c in hands:
		if not (c is CardResource):
			continue
		if c.card_name != card_name:
			continue
		if highest == null or c.effect_value > highest.effect_value:
			highest = c
	if highest == null:
		mod_resume_without_settle()
		return
	var cards_for_effect: Array = [{"card": highest, "player_index": opponent_index}]
	chuqizhisheng_discard_effect_requested.emit(cards_for_effect)
	if _is_multiplayer() and multiplayer.is_server():
		var card_data: Dictionary = {
			"card_name": highest.card_name,
			"effect_value": highest.effect_value
		}
		_rpc_chuqizhisheng_discard_effect.rpc_id(_get_opponent_peer_id(), opponent_index, card_data)


func _auto_chuqizhisheng_select() -> void:
	var cm: Node = _card_manager
	var drawer_index: int = mod_chuqizhisheng_player_index
	var pc: int = clampi(player_count, 2, 8)
	var opponents_with_cards: Array = []
	for pi in range(pc):
		if pi == drawer_index:
			continue
		var h: Array = cm.player_hands.get(pi, [])
		if not h.is_empty():
			opponents_with_cards.append(pi)
	if opponents_with_cards.is_empty():
		mod_chuqizhisheng_pending = false
		mod_resume_without_settle()
		return
	var chosen_opponent: int = opponents_with_cards[randi() % opponents_with_cards.size()]
	var chosen_hands: Array = cm.player_hands.get(chosen_opponent, [])
	var types_seen: Dictionary = {}
	for c in chosen_hands:
		if c is CardResource:
			types_seen[c.card_name] = true
	var types: Array = types_seen.keys()
	var pick: String = types[randi() % types.size()]
	_apply_chuqizhisheng_selection({"card_name": pick, "opponent_index": chosen_opponent})


## 偷梁换柱：选择完成后调用，selection: {turn_index: int}，-1 表示放弃
func request_toulianghuanzhu_selection(selection: Dictionary) -> void:
	if _is_multiplayer() and not multiplayer.is_server():
		_rpc_toulianghuanzhu_selection.rpc_id(1, selection)
	else:
		_apply_toulianghuanzhu_selection(selection)


@rpc("any_peer")
func _rpc_toulianghuanzhu_selection(selection: Dictionary) -> void:
	if multiplayer.is_server():
		_apply_toulianghuanzhu_selection(selection)


func _apply_toulianghuanzhu_selection(selection: Dictionary) -> void:
	mod_toulianghuanzhu_pending = false
	var cm: Node = _card_manager
	var drawer_index: int = mod_toulianghuanzhu_drawer_index
	var turn_index: int = int(selection.get("turn_index", -1))
	if turn_index < 0 or turn_index >= cm.turn_container.size():
		mod_resume_without_settle()
		return
	var toulianghuanzhu_index: int = cm.turn_container.size() - 1
	if turn_index == toulianghuanzhu_index:
		mod_resume_without_settle()
		return
	if cm.turn_container[turn_index] == null:
		mod_resume_without_settle()
		return
	cm.swap_cards_in_turn(toulianghuanzhu_index, turn_index)
	## 交换后末位为原被选牌（与抽到偷梁换柱互换），在此取引用避免与联机/时序下交换前索引不一致
	var effect_card: CardResource = cm.turn_container[cm.turn_container.size() - 1] as CardResource
	if effect_card == null:
		mod_resume_without_settle()
		return
	_pending_toulianghuanzhu_effect = {"card": effect_card, "player_index": drawer_index}
	toulianghuanzhu_swap_requested.emit(toulianghuanzhu_index, turn_index)
	if _is_multiplayer() and multiplayer.is_server():
		_rpc_toulianghuanzhu_swap.rpc(toulianghuanzhu_index, turn_index)


@rpc("authority")
func _rpc_toulianghuanzhu_swap(toulianghuanzhu_index: int, turn_index: int) -> void:
	if _is_multiplayer() and not multiplayer.is_server():
		var cm: Node = _card_manager
		if turn_index >= 0 and turn_index < cm.turn_container.size() and toulianghuanzhu_index >= 0 and toulianghuanzhu_index < cm.turn_container.size():
			cm.swap_cards_in_turn(toulianghuanzhu_index, turn_index)
			mod_toulianghuanzhu_pending = false
			var effect_card: CardResource = cm.turn_container[cm.turn_container.size() - 1] as CardResource
			if effect_card == null:
				mod_resume_without_settle()
				return
			_pending_toulianghuanzhu_effect = {"card": effect_card, "player_index": mod_toulianghuanzhu_drawer_index}
			toulianghuanzhu_swap_requested.emit(toulianghuanzhu_index, turn_index)


func _auto_toulianghuanzhu_select() -> void:
	var cm: Node = _card_manager
	var tc: Array = cm.turn_container
	if tc.size() < 2:
		mod_toulianghuanzhu_pending = false
		mod_resume_without_settle()
		return
	var last_idx: int = tc.size() - 1
	var candidates: Array = []
	for i in range(last_idx):
		candidates.append(i)
	if candidates.is_empty():
		mod_toulianghuanzhu_pending = false
		mod_resume_without_settle()
		return
	var pick: int = candidates[randi() % candidates.size()]
	_apply_toulianghuanzhu_selection({"turn_index": pick})


## 偷梁换柱：交换动画完成后由 battle_test 调用，触发被选牌效果
## 主机与客户端均需触发，以便显示出奇制胜/九牛一毛等选择 UI
func complete_toulianghuanzhu_swap() -> void:
	if _pending_toulianghuanzhu_effect.is_empty():
		return
	var card: CardResource = _pending_toulianghuanzhu_effect.get("card") as CardResource
	var player_index: int = int(_pending_toulianghuanzhu_effect.get("player_index", 0))
	_pending_toulianghuanzhu_effect = {}
	request_trigger_card_effect(card, player_index, false, true)


## 构建与 request_trigger_card_effect 一致的 ctx（不含 effect_phase），供 battle_test 抽牌动画阶段调用 effect 使用
func get_effect_context_base(_player_index: int) -> Dictionary:
	var ctx: Dictionary = {
		"battle_manager": self,
		"card_manager": _card_manager,
		"is_stolen": false,
		"need_immediate_emit": false,
		"player_count": clampi(player_count, 2, 8)
	}
	var local_idx: int = 0
	if not is_lunce_mode:
		var nm: Node = _network_manager
		if nm != null and nm.has_method("get_local_player_index"):
			local_idx = nm.call("get_local_player_index")
	ctx["local_player_index"] = local_idx
	return ctx


## 根据 ability_id 触发卡牌效果（抽牌、偷梁换柱交换后、九牛一毛夺取后）
## is_stolen: true 表示九牛一毛夺取后触发，未知卡牌走 stolen_card_effect 钩子
## need_immediate_emit: true 表示无 draw_animation_finished 流程（如偷梁换柱交换后），需立即发出选择信号
func request_trigger_card_effect(card: CardResource, player_index: int, is_stolen: bool = false, need_immediate_emit: bool = false) -> void:
	if card == null:
		mod_resume_without_settle()
		return
	var ctx: Dictionary = get_effect_context_base(player_index)
	ctx["is_stolen"] = is_stolen
	ctx["need_immediate_emit"] = need_immediate_emit
	var registry_script: GDScript = load("res://scripts/cards/card_registry.gd") as GDScript
	if registry_script != null:
		var registry: RefCounted = registry_script.new()
		if registry != null and registry.has_method("trigger_card_effect"):
			if registry.call("trigger_card_effect", card, player_index, ctx):
				return
	# 核心卡牌未处理或未知 ability_id：交由 Mod 钩子处理
	var _aid: String = str(card.ability_id)
	var _cm: Node = _card_manager
	var _pc: int = clampi(player_count, 2, 8)
	if is_stolen:
		var opts: Dictionary = {"skip_mod_resume": false}
		_mod_loader.trigger_hook("stolen_card_effect", [card, player_index, opts])
		if not opts.get("skip_mod_resume", false):
			mod_resume_without_settle()
	else:
		var opts: Dictionary = {"handled": false}
		_mod_loader.trigger_hook("trigger_card_effect", [card, player_index, opts])
		if not opts.get("handled", false):
			if need_immediate_emit:
				mod_resume_without_settle()


## 供卡牌 effect() 调用：察言观色效果
func _effect_chayanguanse(player_index: int, ctx: Dictionary) -> void:
	var cm: Node = _card_manager
	var next: CardResource = cm.peek_next_card() if cm.has_method("peek_next_card") else null
	if next != null:
		_log_record("BattleManager", "chayanguanse_peek", {"peeked": "%s(分值%d)" % [next.card_name, next.effect_value], "player": player_index, "deck_remain": cm.global_deck.size() if "global_deck" in cm else 0})
	var is_stolen: bool = ctx.get("is_stolen", false)
	if is_stolen:
		if next != null:
			_log_record("BattleManager", "jiuniuyimao_stolen_chayanguanse_peek", {"peeked": "%s(分值%d)" % [next.card_name, next.effect_value], "steal_player": player_index})
		else:
			_log_record("BattleManager", "jiuniuyimao_stolen_chayanguanse_peek", {"reason": "deck_empty"})
	if next != null:
		var local_idx: int = int(ctx.get("local_player_index", 0))
		var show_to_local: bool = (player_index == local_idx)
		if _is_multiplayer() and multiplayer.is_server() and player_index != local_idx:
			var card_data: Dictionary = {
				"card_name": next.card_name,
				"effect_value": next.effect_value,
				"ability_id": next.ability_id,
				"count_towards_contradiction": next.count_towards_contradiction,
				"force_ends_turn": next.force_ends_turn
			}
			_rpc_peek_card_to_client.rpc_id(_get_opponent_peer_id(), card_data)
		request_peek_display(next, show_to_local)
	mod_resume_without_settle()


## 供卡牌 effect() 调用：九牛一毛效果
func _effect_jiuniuyimao(player_index: int, ctx: Dictionary) -> void:
	var cm: Node = _card_manager
	var pc: int = int(ctx.get("player_count", 2))
	var is_stolen: bool = ctx.get("is_stolen", false)
	var need_immediate_emit: bool = ctx.get("need_immediate_emit", false)
	var any_opp_has: bool = false
	for pi in range(pc):
		if pi != player_index and not cm.player_hands.get(pi, []).is_empty():
			any_opp_has = true
			break
	if is_stolen and not any_opp_has:
		_log_record("BattleManager", "jiuniuyimao_stolen_jiuniuyimao", {"reason": "opponent_empty", "steal_player": player_index})
	if any_opp_has:
		mod_pause_settlement = true
		mod_jiuniuyimao_pending = true
		mod_jiuniuyimao_player_index = player_index
		if _is_multiplayer() and multiplayer.is_server() and player_index != 0:
			_rpc_jiuniuyimao_mode_started.rpc_id(_get_opponent_peer_id(), player_index)
		if is_stolen or need_immediate_emit:
			if _is_player_index_ai(player_index):
				_auto_jiuniuyimao_select()
			else:
				jiuniuyimao_selection_requested.emit(player_index)
	else:
		mod_resume_without_settle()


## 供卡牌 effect() 调用：出奇制胜效果
func _effect_chuqizhisheng(player_index: int, ctx: Dictionary) -> void:
	var cm: Node = _card_manager
	var pc: int = int(ctx.get("player_count", 2))
	var is_stolen: bool = ctx.get("is_stolen", false)
	var need_immediate_emit: bool = ctx.get("need_immediate_emit", false)
	var any_opp_has: bool = false
	for pi in range(pc):
		if pi != player_index and not cm.player_hands.get(pi, []).is_empty():
			any_opp_has = true
			break
	if is_stolen and not any_opp_has:
		_log_record("BattleManager", "jiuniuyimao_stolen_chuqizhisheng", {"reason": "opponent_empty", "steal_player": player_index})
	if any_opp_has:
		mod_pause_settlement = true
		mod_chuqizhisheng_pending = true
		mod_chuqizhisheng_player_index = player_index
		if _is_multiplayer() and multiplayer.is_server() and player_index != 0:
			_rpc_chuqizhisheng_mode_started.rpc_id(_get_opponent_peer_id(), player_index)
		if is_stolen or need_immediate_emit:
			if _is_player_index_ai(player_index):
				_auto_chuqizhisheng_select()
			else:
				chuqizhisheng_selection_requested.emit(player_index)
	else:
		mod_resume_without_settle()


## 供卡牌 effect() 调用：见好就收效果
func _effect_stop(_ctx: Dictionary) -> void:
	if has_method("complete_stop_card_effect"):
		complete_stop_card_effect()
	else:
		mod_resume_without_settle()


## 供卡牌 effect() 调用：箭在弦上 — 正常抽到由 battle_test 抽牌动画内处理；偷梁换柱交换后 / 九牛一毛夺取后需由此启动特效与强制抽牌
func _effect_jianzaixianshang(card: CardResource, player_index: int, ctx: Dictionary) -> void:
	var need_immediate: bool = ctx.get("need_immediate_emit", false)
	var stolen: bool = ctx.get("is_stolen", false)
	if not need_immediate and not stolen:
		return
	set_effect_playing(true)
	mod_resume_without_settle()
	jianzaixianshang_play_effect_requested.emit(card, player_index)


## 供卡牌 effect() 调用：偷梁换柱效果
func _effect_toulianghuanzhu(player_index: int, ctx: Dictionary) -> void:
	var cm: Node = _card_manager
	if cm.turn_container.size() < 2:
		mod_resume_without_settle()
		return
	var is_stolen: bool = ctx.get("is_stolen", false)
	var need_immediate_emit: bool = ctx.get("need_immediate_emit", false)
	if is_stolen:
		_log_record("BattleManager", "jiuniuyimao_stolen_toulianghuanzhu", {"steal_player": player_index})
	mod_pause_settlement = true
	mod_toulianghuanzhu_pending = true
	mod_toulianghuanzhu_drawer_index = player_index
	if _is_multiplayer() and multiplayer.is_server() and player_index != 0:
		_rpc_toulianghuanzhu_mode_started.rpc_id(_get_opponent_peer_id(), player_index)
	if is_stolen or need_immediate_emit:
		if _is_player_index_ai(player_index):
			_auto_toulianghuanzhu_select()
		else:
			toulianghuanzhu_selection_requested.emit(player_index)


@rpc("authority")
func _rpc_chuqizhisheng_discard_effect(opponent_index: int, card_data: Dictionary) -> void:
	chuqizhisheng_discard_effect_requested.emit([{"card": _card_manager.create_card_from_data(card_data), "player_index": opponent_index}])


func _trigger_stolen_card_effect(stolen_card: CardResource, steal_player_index: int) -> bool:
	if stolen_card.force_ends_turn:
		mod_pause_settlement = false
		# 阻塞：等 battle_test 飞牌动画完成后再 settle
		_pending_jiuniuyimao_stolen_stop_settle = steal_player_index
		return true
	# 统一委托给 request_trigger_card_effect，is_stolen=true 时未知卡牌走 stolen_card_effect 钩子
	request_trigger_card_effect(stolen_card, steal_player_index, true)
	# request_trigger_card_effect 内部已处理 mod_resume 或 mod_pause，调用方无需再 mod_resume
	return true


## 他山之石 Mod：请求弹窗选择 UI，battle_test 监听信号后显示两阶段选择弹窗
func request_tashanzhishi_selection_ui(drawer_index: int) -> void:
	tashanzhishi_selection_requested.emit(drawer_index)


## 他山之石 Mod：客户端选择完成后调用，将选择发送给主机执行；主机直接处理
## selection: {double_from, double_idx, opp_idx, opp_hand_idx}
func request_tashanzhishi_selection(selection: Dictionary) -> void:
	if _is_multiplayer() and not multiplayer.is_server():
		_rpc_tashanzhishi_selection.rpc_id(1, selection)
	else:
		_apply_tashanzhishi_selection(selection)


@rpc("any_peer")
func _rpc_tashanzhishi_selection(selection: Dictionary) -> void:
	if multiplayer.is_server():
		_log_record("BattleManager", "_rpc_tashanzhishi_selection", selection)
		_apply_tashanzhishi_selection(selection)


func _apply_tashanzhishi_selection(selection: Dictionary) -> void:
	var cm: Node = _card_manager
	var hands: Dictionary = cm.get("player_hands")
	var double_from: int = int(selection.get("double_from", 0))
	var double_idx: int = int(selection.get("double_idx", 0))
	var opp_idx: int = int(selection.get("opp_idx", 1))
	var opp_hand_idx: int = int(selection.get("opp_hand_idx", 0))
	var double_hand: Array = hands.get(double_from, [])
	var opp_hand: Array = hands.get(opp_idx, [])
	var double_card: Variant = double_hand[double_idx] if double_idx < double_hand.size() else null
	var opp_card: Variant = opp_hand[opp_hand_idx] if opp_hand_idx < opp_hand.size() else null
	if double_card == null or opp_card == null:
		mod_resume_without_settle()
		return
	var cards_for_effect: Array = [
		{"card": double_card, "player_index": double_from},
		{"card": opp_card, "player_index": opp_idx}
	]
	request_mod_soft_remove_effect(cards_for_effect)
	if _is_multiplayer() and multiplayer.is_server():
		var client_effect: Array = [
			{"player_index": double_from, "hand_index": double_idx},
			{"player_index": opp_idx, "hand_index": opp_hand_idx}
		]
		_log_record("BattleManager", "_rpc_mod_soft_remove_effect", {"client_effect": client_effect})
		_rpc_mod_soft_remove_effect.rpc(client_effect)
	_mod_loader.trigger_hook("tashanzhishi_selection_finished", [])
	## 阻塞：mod_resume 由 battle_test 在删牌特效完成后调用


## 客户端专用：收到主机发来的九牛一毛夺取结果，同步手牌与回合区
@rpc("authority")
func _rpc_jiuniuyimao_steal_result(opponent_index: int, hand_index: int, _card_data: Dictionary) -> void:
	var cm: Node = _card_manager
	var hands: Array = cm.player_hands.get(opponent_index, [])
	if hand_index >= 0 and hand_index < hands.size():
		var card: CardResource = hands[hand_index]
		hands.remove_at(hand_index)
		cm.turn_container.append(card)
		cm.hand_updated.emit(opponent_index)
		jiuniuyimao_card_added_to_turn.emit(card)


## 客户端专用：收到主机发来的他山之石删牌特效，按 hand_index 定位卡牌并播放
@rpc("authority")
func _rpc_mod_soft_remove_effect(cards_by_index: Array) -> void:
	var cm: Node = _card_manager
	var hands: Dictionary = cm.get("player_hands")
	var cards: Array = []
	for item in cards_by_index:
		var pi: int = int(item.get("player_index", 0))
		var hi: int = int(item.get("hand_index", 0))
		var hand: Array = hands.get(pi, [])
		if hi >= 0 and hi < hand.size():
			cards.append({"card": hand[hi], "player_index": pi})
	if not cards.is_empty():
		mod_soft_remove_effect_requested.emit(cards)


## 供 Mod 调用：恢复流程（放弃等）；联机时客户端需 RPC 到主机
func request_mod_resume_without_settle() -> void:
	if _is_multiplayer() and not multiplayer.is_server():
		_rpc_mod_resume_without_settle.rpc_id(1)
	else:
		mod_resume_without_settle()


@rpc("any_peer")
func _rpc_mod_resume_without_settle() -> void:
	if multiplayer.is_server():
		mod_resume_without_settle()


## 客户端选择神来之笔目标后调用，将选择发送给主机执行
func request_copy_selection(card_data: Dictionary) -> void:
	if not _is_multiplayer() or multiplayer.is_server():
		return
	_rpc_copy_selection.rpc_id(1, card_data)


@rpc("any_peer")
func _rpc_copy_selection(card_data: Dictionary) -> void:
	if not multiplayer.is_server() or current_state != State.PROCESSING:
		return
	_mod_loader.trigger_hook("apply_copy_selection", [card_data])


## 供 Mod 调用：触发矛盾同款特效（仅视觉，不结束回合）
func request_mod_contradiction_effect(cards: Array) -> void:
	_log_record("BattleManager", "request_mod_contradiction_effect", {"count": cards.size()})
	mod_contradiction_effect_requested.emit(cards)


## 供 Mod（察言观色）调用：请求展示下一张牌给本地玩家
## show_to_local: 仅当抽牌者为本地玩家时显示（AI/对手抽到则不展示）
func request_peek_display(card: CardResource, show_to_local: bool) -> void:
	peek_card_display_requested.emit(card, show_to_local)


## 供 Mod 调用：触发软特效（他山之石删牌等），柔和发光+淡出，无震动闪红
func request_mod_soft_remove_effect(cards: Array) -> void:
	_log_record("BattleManager", "request_mod_soft_remove_effect", {"count": cards.size()})
	mod_soft_remove_effect_requested.emit(cards)


## 供 Mod（神来之笔等）调用：选择时锁定对手 UI，选择完成后解锁
func request_lock_opponent_ui(locked: bool) -> void:
	if _is_multiplayer():
		_rpc_lock_ui.rpc(locked)


@rpc("any_peer")
func _rpc_lock_ui(locked: bool) -> void:
	ui_locked = locked
	ui_lock_changed.emit(locked)


## 供 Mod 调用：实时返回当前 turn_container 是否已触发同名矛盾
func is_turn_invalid() -> bool:
	var cm: Node = _card_manager
	return cm.call("is_turn_invalid")


## 供 CardManager 等调用：检查当前玩家总分是否超过上限（效果执行后的最终值，实时手牌+回合）
func check_score_contradiction(player_index: int) -> bool:
	return get_effective_score(player_index) >= SCORE_LIMIT


## 供 Mod 在劫持流程结束后调用：仅恢复流程，不结算本回合（默认规则：触发效果后不结算）
## 卡牌留在 turn_container，玩家可继续抽牌
func mod_resume_without_settle() -> void:
	_log_record("BattleManager", "mod_resume_without_settle", {"current_player": current_player_index})
	if _is_multiplayer() and not multiplayer.is_server():
		return
	mod_pause_settlement = false
	_transition_to(State.PLAYER_TURN)
	_update_ui_state()
	if _is_multiplayer() and multiplayer.is_server():
		_rpc_update_ui_state.rpc(current_player_index)
	if _is_current_player_ai():
		_start_ai_turn()


## 供 Mod 在劫持流程结束后调用：结算回合并恢复流程（仅主机执行，客户端禁止）
## skip_switch: true 时只结算得分、不切换玩家，允许继续抽牌（无额外回合特效）
func mod_settle_and_continue(skip_switch: bool = false) -> void:
	_log_record("BattleManager", "mod_settle_and_continue", {"skip_switch": skip_switch})
	if _is_multiplayer() and not multiplayer.is_server():
		return
	mod_pause_settlement = false
	var cm: Node = _card_manager
	var player_who_ended: int = current_player_index
	var cards_data: Array = []
	for card in cm.turn_container:
		cards_data.append({
			"card_name": card.card_name,
			"effect_value": card.effect_value,
			"ability_id": card.ability_id,
			"count_towards_contradiction": card.count_towards_contradiction,
			"force_ends_turn": card.force_ends_turn
		})
	cm.settle_turn(current_player_index)
	if skip_switch:
		_transition_to(State.PLAYER_TURN)
		hand_collection_requested.emit(player_who_ended)  # 收牌动画
		_update_ui_state()
		if _is_multiplayer() and multiplayer.is_server():
			_rpc_apply_mod_settlement.rpc(player_who_ended, cards_data, player_scores[0], player_scores[1])
			_rpc_update_ui_state.rpc(current_player_index)
		if _is_current_player_ai():
			_start_ai_turn()
	else:
		_on_turn_settled_manual()
