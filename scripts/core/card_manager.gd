## 卡牌管理器（单例）
## 负责抽牌、矛盾检测、回合结算
extends Node

# ---- Mod 钩子 ----
const MOD_LOADER_PATH: String = "/root/ModLoader"
const BATTLE_MANAGER_PATH: String = "/root/BattleManager"

# ---- 卡牌注册表（每张卡牌独立文件） ----
const CARD_REGISTRY_SCRIPT: String = "res://scripts/cards/card_registry.gd"

## 缓存 Autoload 引用
var _battle_manager: Node
var _mod_loader: Node

## 通过场景树获取 GameLogger（避免 autoload 解析问题）
func _log_record(tag: String, action: String, data: Variant = "") -> void:
	var gl: Node = get_node_or_null("/root/GameLogger")
	if gl and gl.has_method("record"):
		gl.record(tag, action, data)

# ---- 信号 ----
signal card_drawn(card: CardResource)
## 抽到的卡牌被 Mod 消费（不加入回合区）：参数为卡牌，用于在牌堆原地显示特效后移除
signal card_drawn_consumed(card: CardResource)
## 矛盾触发：involved=回合区全部卡牌，protected_indices=被自圆其说保护的索引，player_index=回合玩家
signal contradiction_triggered(involved_cards: Array, protected_indices: Array, player_index: int)
## 总分超限矛盾（效果执行后 player_scores 超过上限）
## 参数：player_index, card, scores_before{0,1} 用于回滚
signal score_contradiction_triggered(player_index: int, card: CardResource, scores_before: Dictionary)
signal hand_updated(player_index: int)
signal force_end_turn
signal turn_settled(turn_score: int)
signal deck_count_changed(count: int)
## 察言观色等：抽到可窥牌时请求展示下一张牌，drawer_index 为抽牌者
signal chayanguanse_peek_requested(next_card: CardResource, drawer_index: int)
## 九牛一毛：抽到且对手有牌时请求选择夺取，drawer_index 为抽牌者
signal jiuniuyimao_mode_requested(drawer_index: int)
## 出奇制胜：抽到且对手有牌时请求选择弃牌类型，drawer_index 为抽牌者
signal chuqizhisheng_mode_requested(drawer_index: int)
## 偷梁换柱：抽到且回合区至少 2 张牌时请求选择交换目标，drawer_index 为抽牌者
signal toulianghuanzhu_selection_requested(drawer_index: int)

# ---- 牌堆 ----
## Mod 注册的卡牌数据，_build_deck 时会并入牌堆
var mod_registered_cards: Array[Dictionary] = []
## 总牌堆（全局可用卡池）
var global_deck: Array[CardResource] = []
## 回合临时牌堆（本回合抽到的牌，用于矛盾检测）
var turn_container: Array[CardResource] = []
## 玩家手牌：0=玩家，1=对手
var player_hands: Dictionary = {0: [], 1: []}
## 弃牌堆（他山之石等效果移除的卡牌）
var discard_pile: Array[CardResource] = []
## 本回合抽到的卡牌是否被 Mod 消费（不加入回合区）
var _consumed_drawn_card: CardResource = null


func _ready() -> void:
	_battle_manager = get_node_or_null(BATTLE_MANAGER_PATH)
	_mod_loader = get_node(MOD_LOADER_PATH)
	_build_deck()


## 根据卡牌数据字典向目标数组追加卡牌
func _append_cards_from_dict(card_dict: Dictionary, target: Array) -> void:
	var base_score: int = int(card_dict.get("score", 0))
	var scores: Array = card_dict.get("scores", [])
	var copies: int = int(card_dict.get("count", 4))
	if scores.is_empty() and not card_dict.has("score"):
		scores = [1, 2, 3, 4]
	var count_contradiction: bool = card_dict.get("count_towards_contradiction", true)
	var force_ends: bool = card_dict.get("force_ends_turn", false)
	if scores.size() > 0:
		for s in scores:
			var card: CardResource = CardResource.new()
			card.card_name = card_dict.get("name", "")
			card.effect_value = int(s)
			card.ability_id = card_dict.get("ability_id", "")
			card.count_towards_contradiction = count_contradiction
			card.force_ends_turn = force_ends
			target.append(card)
	else:
		var card: CardResource = CardResource.new()
		card.card_name = card_dict.get("name", "")
		card.effect_value = base_score
		card.ability_id = card_dict.get("ability_id", "")
		card.count_towards_contradiction = count_contradiction
		card.force_ends_turn = force_ends
		for _i in range(copies):
			target.append(card.duplicate())


## 从卡牌注册表与 Mod 注册构建牌堆（每张卡牌独立文件）
func _build_deck() -> void:
	global_deck.clear()

	# 从卡牌注册表加载核心卡牌（空牌、见好就收、一石二鸟）
	var registry_script: Script = load(CARD_REGISTRY_SCRIPT) as Script
	if registry_script != null:
		var registry: Variant = registry_script.new()
		if registry != null and registry.has_method("get_all_core_cards"):
			for card_dict: Dictionary in registry.call("get_all_core_cards"):
				_append_cards_from_dict(card_dict, global_deck)

	# 添加 Mod 注册的卡牌
	for card_dict: Dictionary in mod_registered_cards:
		_append_cards_from_dict(card_dict, global_deck)

	global_deck.shuffle()
	deck_count_changed.emit(global_deck.size())
	print("[CardManager] 牌堆已初始化，共 ", global_deck.size(), " 张")


## 偷梁换柱：交换 turn_container 中两卡牌位置，供 BattleManager 在完成选择后调用
func swap_cards_in_turn(i: int, j: int) -> void:
	if i < 0 or j < 0 or i >= turn_container.size() or j >= turn_container.size():
		return
	var tmp: CardResource = turn_container[i]
	turn_container[i] = turn_container[j]
	turn_container[j] = tmp


## 供 Mod 通过 api_call 注册新卡牌，需在 _mod_init 中调用
func register_card(card_data: Dictionary) -> bool:
	if card_data.is_empty():
		return false
	mod_registered_cards.append(card_data)
	return true


## 清空 Mod 注册的卡牌，供 ModManager 重新浏览时调用，避免重复注册
func clear_mod_registered_cards() -> void:
	mod_registered_cards.clear()


## 重置为新游戏：清空手牌、回合牌堆、弃牌堆，重新构建牌堆
## player_hands 按 BattleManager.player_count 初始化（2~8 人）
func reset_for_new_game() -> void:
	var bm: Node = _battle_manager
	var count: int = 2
	if bm != null and bm.get("player_count"):
		count = clampi(int(bm.player_count), 2, 8)
	for i in range(count):
		if not player_hands.has(i):
			player_hands[i] = []
		player_hands[i].clear()
	var keys_to_remove: Array = []
	for k in player_hands.keys():
		if k >= count:
			keys_to_remove.append(k)
	for k in keys_to_remove:
		player_hands.erase(k)
	turn_container.clear()
	discard_pile.clear()
	_build_deck()


## 从 global_deck 随机抽一张牌，执行矛盾检测后加入 turn_container 或触发矛盾
## player_index: 当前抽牌玩家索引（0=玩家，1=对手），供 Mod 钩子使用
## 返回 [deck_index, card] 供联机同步；矛盾时 card 仍返回以便主机 RPC 卡牌数据
func draw_card(player_index: int = 0) -> Array:
	_log_record("CardManager", "draw_card", {"player": player_index, "deck_size": global_deck.size()})
	if global_deck.is_empty():
		push_warning("CardManager: global_deck 为空，无法抽牌")
		return [-1, null]

	_mod_loader.trigger_hook("pre_draw_card", [player_index])

	# 从牌堆顶抽牌（index 0），与察言观色窥牌一致；随机性来自开局洗牌
	var idx: int = 0
	var card: CardResource = _draw_card_at_index(player_index, idx)
	return [idx, card]


## 联机（已废弃）：客户端不再本地抽牌，改用 apply_draw_from_data 根据主机数据生成
func draw_card_at_index(player_index: int, deck_index: int) -> void:
	if deck_index < 0 or deck_index >= global_deck.size():
		push_warning("CardManager: 无效的抽牌索引 %d" % deck_index)
		return
	_draw_card_at_index(player_index, deck_index)


## 主机权威：客户端根据主机发来的卡牌数据直接生成显示，不触碰本地牌堆
## 不在此 emit card_drawn，避免与 client_draw_received 重复渲染（安卓 is_multiplayer 可能误报）
## card_data: {card_name, effect_value, ability_id, count_towards_contradiction, force_ends_turn}
func apply_draw_from_data(_player_index: int, card_data: Dictionary, deck_count: int) -> void:
	var card: CardResource = _card_from_data(card_data)
	turn_container.append(card)
	deck_count_changed.emit(deck_count)


## 客户端专用：收到被 Mod 消费的抽牌时调用，不加入 turn_container，仅触发消费特效
## 不在此 emit card_drawn_consumed，避免与 client_consumed_draw_received 重复渲染
func apply_consumed_draw_from_data(_player_index: int, _card_data: Dictionary, deck_count: int) -> void:
	deck_count_changed.emit(deck_count)


func _card_from_data(card_data: Dictionary) -> CardResource:
	var card: CardResource = CardResource.new()
	card.card_name = card_data.get("card_name", "")
	card.effect_value = int(card_data.get("effect_value", 0))
	card.ability_id = card_data.get("ability_id", "")
	card.count_towards_contradiction = bool(card_data.get("count_towards_contradiction", false))
	card.force_ends_turn = bool(card_data.get("force_ends_turn", false))
	return card


## 供 BattleManager 等从 dict 创建卡牌，避免重复实现
func create_card_from_data(card_data: Dictionary) -> CardResource:
	return _card_from_data(card_data)


## 返回抽到的卡牌（矛盾时仍返回，供主机 RPC 同步）
func _draw_card_at_index(player_index: int, idx: int) -> CardResource:
	var card: CardResource = global_deck[idx]
	global_deck.remove_at(idx)
	deck_count_changed.emit(global_deck.size())

	## 他山之石等 Mod 卡：先触发 post_draw_card，若被消费则永不加入回合区
	_mod_loader.trigger_hook("post_draw_card", [card, player_index])
	if _consumed_drawn_card == card:
		_consumed_drawn_card = null
		card_drawn_consumed.emit(card)
		_log_record("CardManager", "emit_signal", {"signal": "card_drawn_consumed", "card": card.card_name})
		if card.force_ends_turn:
			force_end_turn.emit()
		return card

	turn_container.append(card)
	var dup_card: CardResource = check_name_contradiction()
	if dup_card != null:
		trigger_contradiction(dup_card, player_index)
		return card

	# 统一触发卡牌效果：核心卡牌与 Mod 卡牌均通过 BattleManager.request_trigger_card_effect 处理
	if not card.force_ends_turn and _battle_manager != null and _battle_manager.has_method("request_trigger_card_effect"):
		_battle_manager.request_trigger_card_effect(card, player_index, false)

	card_drawn.emit(card)
	_log_record("CardManager", "emit_signal", {"signal": "card_drawn", "card": card.card_name})
	if card.force_ends_turn:
		force_end_turn.emit()
	return card


## 触发矛盾：打印日志，处理自圆其说保护，清空 turn_container，发出 force_end_turn 信号
## card 为触发矛盾的牌（可为 null），player_index 为当前回合玩家
## 自圆其说：保护排在它及它之前的卡牌收入手牌；第二张自圆其说触发时只保护到第一张
func trigger_contradiction(card: CardResource = null, player_index: int = 0) -> void:
	_log_record("CardManager", "trigger_contradiction", {"card": card.card_name if card else "null", "player": player_index})
	print("[CardManager] 矛盾爆发！回合牌堆中存在同名卡牌，强制结束回合")
	var involved: Array = turn_container.duplicate()
	if card != null and not involved.has(card):
		involved.append(card)
	var protected_indices: Array = []
	var first_ziyuan_idx: int = -1
	for i: int in range(turn_container.size()):
		var c: CardResource = turn_container[i]
		if c is CardResource and c.ability_id == "ziyuanqishuo":
			first_ziyuan_idx = i
			break
	if first_ziyuan_idx >= 0:
		for i: int in range(first_ziyuan_idx + 1):
			protected_indices.append(i)
		var hands: Array = player_hands.get(player_index, [])
		for i: int in protected_indices:
			if i < turn_container.size():
				hands.append(turn_container[i])
		hand_updated.emit(player_index)
	for i: int in range(turn_container.size() - 1, -1, -1):
		if not protected_indices.has(i):
			discard_pile.append(turn_container[i])
	turn_container.clear()
	contradiction_triggered.emit(involved, protected_indices, player_index)
	force_end_turn.emit()


## 触发分数超限矛盾：效果执行后总分超过上限
func _trigger_score_contradiction(player_index: int, card: CardResource, scores_before: Dictionary) -> void:
	turn_container.clear()
	print("[CardManager] 矛盾爆发！玩家 %d 总分超过上限，本回合分数归零" % player_index)
	score_contradiction_triggered.emit(player_index, card, scores_before)
	force_end_turn.emit()


## 供 Mod 调用：消费本回合刚抽到的卡牌（不加入回合区）
## 需在 post_draw_card 钩子内调用，且必须在 turn_container.append 之前（CardManager 已调整抽牌顺序）
func consume_drawn_card(card: CardResource) -> bool:
	if card == null:
		return false
	_consumed_drawn_card = card
	_log_record("CardManager", "consume_drawn_card", {"card": card.card_name})
	return true


## 供九牛一毛等调用：从指定玩家手牌移除卡牌并移入回合牌堆（不进入弃牌堆）
func transfer_card_from_hand_to_turn(player_index: int, card: CardResource) -> bool:
	var hands: Array = player_hands.get(player_index, [])
	var idx: int = hands.find(card)
	if idx >= 0:
		hands.remove_at(idx)
		turn_container.append(card)
		hand_updated.emit(player_index)
		return true
	return false


## 供 Mod 调用：从指定玩家手牌中移除卡牌并移入弃牌堆，返回是否成功
func remove_card_from_hand(player_index: int, card: CardResource) -> bool:
	_log_record("CardManager", "remove_card_from_hand", {"player": player_index, "card": card.card_name})
	var hands: Array = player_hands.get(player_index, [])
	var idx: int = hands.find(card)
	if idx >= 0:
		hands.remove_at(idx)
		discard_pile.append(card)
		hand_updated.emit(player_index)
		return true
	return false


## 供联机客户端调用：按 card_name+effect_value 匹配并移除（用于出奇制胜等 RPC 同步）
func remove_card_from_hand_by_data(player_index: int, card_name: String, effect_value: int) -> bool:
	var hands: Array = player_hands.get(player_index, [])
	for c in hands:
		if c is CardResource and c.card_name == card_name and c.effect_value == effect_value:
			return remove_card_from_hand(player_index, c)
	return false


## 计算指定玩家手牌分数之和（effect_value）
func compute_hand_score(player_index: int) -> int:
	var hands: Array = player_hands.get(player_index, [])
	var total: int = 0
	for c in hands:
		if c is CardResource:
			total += c.effect_value
	return total


## 计算回合牌堆分数之和（effect_value）
func compute_turn_score() -> int:
	var total: int = 0
	for c in turn_container:
		if c is CardResource:
			total += c.effect_value
	return total


## 供 Mod（察言观色等）调用：查看牌堆顶下一张牌，不抽取
func peek_next_card() -> CardResource:
	if global_deck.is_empty():
		return null
	return global_deck[0]


## 供 Mod 调用：实时返回当前 turn_container 是否已触发同名矛盾
func is_turn_invalid() -> bool:
	return check_name_contradiction() != null


## 矛盾检查（伪代码对应）：回合牌堆是否存在同名矛盾，返回触发矛盾的牌，无则 null
func check_contradiction() -> CardResource:
	return check_name_contradiction()


## 检测同名矛盾：遍历 turn_container，若有任意两张卡 card_name 相同则返回触发矛盾的牌
## count_towards_contradiction=false 的卡（如空牌）不参与判定；用于识别 Mod 动态修改后的卡名（如神来之笔变身）
func check_name_contradiction() -> CardResource:
	var names_seen: Dictionary = {}  # card_name -> first CardResource
	for card: CardResource in turn_container:
		if not card.count_towards_contradiction:
			continue
		var n: String = card.card_name
		if n.is_empty():
			continue
		if names_seen.has(n):
			return card
		names_seen[n] = card
	return null


## 客户端专用：根据主机发来的结算结果直接应用，禁止任何计算
## cards_data: Array of {card_name, effect_value, ability_id, ...}
func apply_settlement_result(player_who_ended: int, cards_data: Array, _score_0: int, _score_1: int) -> void:
	for card_dict in cards_data:
		player_hands[player_who_ended].append(_card_from_data(card_dict))
	turn_container.clear()
	hand_updated.emit(player_who_ended)


## 回合结算：计算总分并累加，将 turn_container 移入对应玩家手牌并清空（仅主机执行）
## player_index: 0=玩家，1=对手
func settle_turn(player_index: int) -> void:
	_log_record("CardManager", "settle_turn", {"player": player_index, "turn_size": turn_container.size()})
	# 效果执行完毕后、结算前：检测同名矛盾（含 Mod 变身后的名称）
	var dup_card: CardResource = check_name_contradiction()
	if dup_card != null:
		trigger_contradiction(dup_card, player_index)
		return

	var turn_score: int = 0
	for card: CardResource in turn_container:
		turn_score += card.effect_value
		player_hands[player_index].append(card)
	turn_settled.emit(turn_score)
	turn_container.clear()
	hand_updated.emit(player_index)
