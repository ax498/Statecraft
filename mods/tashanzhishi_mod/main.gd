extends RefCounted

## 他山之石 Mod：抽到此牌时，若任意一方手牌有一石二鸟，分两次选择：
## 第一次选择一石二鸟，第二次选择对手手牌中除第一次以外的任意一张
## 被选卡牌播放特效后移入弃牌堆；他山之石正常加入回合区，结束回合时正常结算

const OPPONENT_HAND_PATH: String = "ShakeLayer/Root/MainMargin/MainVBox/FixedBottom/PlayerHandScroll/PlayerHandDisplay"
const PLAYER_HAND_PATH: String = "ShakeLayer/Root/MainMargin/MainVBox/FixedBottom/PlayerHandScroll/PlayerHandDisplay"
const BTN_ROW_PATH: String = "ShakeLayer/Root/MainMargin/MainVBox/FixedBottom/BtnRow"
const DOUBLE_CARD_NAME: String = "一石二鸟"
const HIGHLIGHT_MODULATE: Color = Color(0.9, 0.95, 1.0)

var _pending: bool = false
var _player_index: int = 0
var _double_selected: Variant = null  # CardResource，第一次选择的一石二鸟
var _double_from_player: int = -1    # 0 or 1，一石二鸟所属玩家
var _abandon_btn: Button = null
var _hijack_uis: Array = []  # [{ui, callable}]


## Mod 脚本无 autoload 作用域，运行时从场景树获取 GameLogger
func _log(tag: String, action: String, data: Variant = "") -> void:
	var gl: Node = Engine.get_main_loop().root.get_node_or_null("GameLogger")
	if gl != null and gl.has_method("record"):
		gl.call("record", tag, action, data)


func _mod_init() -> void:
	var mod_loader: Node = Engine.get_main_loop().root.get_node_or_null("ModLoader")
	if mod_loader == null:
		push_warning("[他山之石] ModLoader 未找到")
		return
	# 4 张他山之石，分值 1、2、3、4，参与矛盾判定（默认）
	mod_loader.api_call("CardManager", "register_card", [
		{"name": "他山之石", "ability_id": "tashanzhishi", "scores": [1, 2, 3, 4], "count_towards_contradiction": true}
	])
	print("[他山之石] 已注册卡牌：他山之石")


func _on_hook_triggered(hook_name: String, args: Array) -> void:
	if hook_name == "post_draw_card":
		_handle_post_draw_card(args)
	elif hook_name == "sync_tashanzhishi_mode":
		_handle_sync_tashanzhishi_mode(args)
	elif hook_name == "post_draw_animation":
		_handle_post_draw_animation(args)
	elif hook_name == "stolen_card_effect":
		_handle_stolen_card_effect(args)
	elif hook_name == "trigger_card_effect":
		_handle_trigger_card_effect(args)
	elif hook_name == "tashanzhishi_selection_finished":
		_finish_pending()


func _handle_post_draw_card(args: Array) -> void:
	if args.size() < 2:
		return
	var card_data = args[0]
	_log("他山之石", "_handle_post_draw_card", {"card": card_data.card_name if card_data is CardResource else card_data.get("card_name", ""), "args_size": args.size()})
	var player_index: int = int(args[1])
	var aid: String = card_data.ability_id if card_data is CardResource else str(card_data.get("ability_id", ""))

	if aid != "tashanzhishi":
		return

	var mod_loader: Node = Engine.get_main_loop().root.get_node_or_null("ModLoader")
	if mod_loader == null:
		return
	var cm: Node = mod_loader.get_card_manager()
	var hands: Dictionary = cm.get("player_hands")
	var bm: Node = mod_loader.get_battle_manager()
	var pc: int = int(bm.get("player_count")) if bm != null else 2
	## 仅当至少一名玩家手牌有一石二鸟时触发；回合区的一石二鸟不计入（与 mod 描述「手牌有一石二鸟」一致）
	var has_double: bool = false
	for pi in range(pc):
		for c in hands.get(pi, []):
			var cname: String = c.card_name if c is CardResource else str(c.get("card_name", ""))
			if cname == DOUBLE_CARD_NAME:
				has_double = true
				break
		if has_double:
			break
	if not has_double:
		_log("他山之石", "_handle_post_draw_card", {"action": "skip_no_double"})
		print("[他山之石] post_draw_card: 无一石二鸟，跳过 player_index=%d" % player_index)
		return

	## 他山之石加入回合区正常结算，仅劫持流程进入选择（选择一石二鸟+对手牌移除）
	if bm != null:
		bm.set("mod_pause_settlement", true)
	_pending = true
	_player_index = player_index
	_double_selected = null
	_double_from_player = -1
	print("[他山之石] post_draw_card: 进入选择流程 player_index=%d" % player_index)

	## 联机：客户端抽到时，主机通知客户端在 draw_animation_finished 触发 sync_tashanzhishi_mode + post_draw_animation
	var nm: Node = Engine.get_main_loop().root.get_node_or_null("NetworkManager")
	if nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer"):
		var local_idx: int = nm.call("get_local_player_index")
		if player_index != local_idx and bm.has_method("request_mod_tashanzhishi_to_client"):
			bm.call("request_mod_tashanzhishi_to_client", player_index)


## 抽到他山之石时：若 post_draw_card 已劫持流程（_pending），标记为已处理避免重复 mod_resume
## 偷梁换柱交换后：他山之石由 trigger_card_effect 触发，_pending 为 false，需在此启动选择流程
func _handle_trigger_card_effect(args: Array) -> void:
	if args.size() < 3:
		return
	var card_data = args[0]
	var opts: Dictionary = args[2] if args[2] is Dictionary else {}
	var aid: String = card_data.ability_id if card_data is CardResource else str(card_data.get("ability_id", ""))
	if aid != "tashanzhishi":
		return
	if _pending:
		opts["handled"] = true
		return
	## 偷梁换柱交换后触发：与九牛一毛夺取同理，需启动选择流程
	var player_index: int = int(args[1]) if args.size() >= 2 else 0
	var mod_loader: Node = Engine.get_main_loop().root.get_node_or_null("ModLoader")
	if mod_loader == null:
		return
	var cm: Node = mod_loader.get_card_manager()
	var hands: Dictionary = cm.get("player_hands")
	var bm: Node = mod_loader.get_battle_manager()
	var pc: int = int(bm.get("player_count")) if bm != null else 2
	var has_double: bool = false
	for pi in range(pc):
		for c in hands.get(pi, []):
			var cname: String = c.card_name if c is CardResource else str(c.get("card_name", ""))
			if cname == DOUBLE_CARD_NAME:
				has_double = true
				break
		if has_double:
			break
	if not has_double:
		_log("他山之石", "_handle_trigger_card_effect", {"action": "skip_no_double"})
		return
	if bm != null:
		bm.set("mod_pause_settlement", true)
	_pending = true
	_player_index = player_index
	_double_selected = null
	_double_from_player = -1
	opts["handled"] = true
	_log("他山之石", "_handle_trigger_card_effect", {"player_index": player_index, "source": "toulianghuanzhu_swap"})
	if mod_loader != null and mod_loader.get_tree() != null:
		mod_loader.get_tree().create_timer(0.0).timeout.connect(Callable(self, "_handle_post_draw_animation"))
	else:
		_handle_post_draw_animation([player_index])


## 九牛一毛夺取他山之石时：触发与抽到相同的选择流程
func _handle_stolen_card_effect(args: Array) -> void:
	if args.size() < 3:
		return
	var stolen_card = args[0]
	var steal_player_index: int = int(args[1])
	var opts: Dictionary = args[2] if args[2] is Dictionary else {}
	var aid: String = stolen_card.ability_id if stolen_card is CardResource else str(stolen_card.get("ability_id", ""))
	if aid != "tashanzhishi":
		return
	var mod_loader: Node = Engine.get_main_loop().root.get_node_or_null("ModLoader")
	if mod_loader == null:
		return
	var cm: Node = mod_loader.get_card_manager()
	var hands: Dictionary = cm.get("player_hands")
	var bm: Node = mod_loader.get_battle_manager()
	var pc: int = int(bm.get("player_count")) if bm != null else 2
	## 仅当至少一名玩家手牌有一石二鸟时触发
	var has_double: bool = false
	for pi in range(pc):
		for c in hands.get(pi, []):
			var cname: String = c.card_name if c is CardResource else str(c.get("card_name", ""))
			if cname == DOUBLE_CARD_NAME:
				has_double = true
				break
		if has_double:
			break
	if not has_double:
		_log("他山之石", "_handle_stolen_card_effect", {"action": "skip_no_double"})
		return
	if bm != null:
		bm.set("mod_pause_settlement", true)
	_pending = true
	_player_index = steal_player_index
	_double_selected = null
	_double_from_player = -1
	opts["skip_mod_resume"] = true
	_log("他山之石", "_handle_stolen_card_effect", {"player_index": steal_player_index})
	## 延迟一帧再显示选择 UI，确保 battle_test 的 _refresh_hand_displays 已完成（queue_free 旧卡牌、添加新卡牌）
	var ml: Node = Engine.get_main_loop().root.get_node_or_null("ModLoader")
	if ml != null and ml.get_tree() != null:
		ml.get_tree().create_timer(0.0).timeout.connect(Callable(self, "_handle_post_draw_animation"))
	else:
		_handle_post_draw_animation()


## 联机客户端专用：主机 RPC 后由 BattleManager 触发，在 post_draw_animation 前设置 _pending 与 _player_index
func _handle_sync_tashanzhishi_mode(args: Array) -> void:
	if args.size() < 1:
		return
	_pending = true
	_player_index = int(args[0])
	_double_selected = null
	_double_from_player = -1
	_log("他山之石", "_handle_sync_tashanzhishi_mode", {"player_index": _player_index})


func _handle_post_draw_animation(args: Array = []) -> void:
	print("[他山之石] post_draw_animation: 进入 _pending=%s _player_index=%d" % [_pending, _player_index])
	if not _pending:
		print("[他山之石] post_draw_animation: _pending 为 false，跳过")
		return
	## 若当前抽牌者与 _player_index 不一致，说明他山之石来自上一回合且已因矛盾等失效，清除状态并跳过
	var current_drawer: int = int(args[0]) if args.size() >= 1 else _player_index
	if current_drawer != _player_index:
		print("[他山之石] post_draw_animation: 当前抽牌者 %d != _player_index %d，清除过期状态" % [current_drawer, _player_index])
		_finish_pending()
		return 

	var mod_loader: Node = Engine.get_main_loop().root.get_node_or_null("ModLoader")
	if mod_loader == null:
		print("[他山之石] post_draw_animation: ModLoader 为空，_finish_pending")
		_finish_pending()
		return

	# 论策/单机 AI 抽到：自动选择；联机对手是真人，不自动选择；否则本地玩家需手动选择
	var bm: Node = mod_loader.get_battle_manager()
	var is_lunce: bool = bm.get("is_lunce_mode") if bm != null else false
	var nm: Node = Engine.get_main_loop().root.get_node_or_null("NetworkManager")
	## 论策模式强制视为单机，避免 NetworkManager 残留连接导致 is_multiplayer 误报
	var is_mp: bool = false
	if not is_lunce and nm != null and nm.has_method("is_multiplayer"):
		is_mp = nm.call("is_multiplayer")
	var local_idx: int = 0
	if is_mp:
		local_idx = nm.call("get_local_player_index") if nm != null else 0
	print("[他山之石] post_draw_animation: is_mp=%s local_idx=%d _player_index=%d" % [is_mp, local_idx, _player_index])
	## 非联机且非本地玩家回合 => AI，自动选择（支持 2~8 人论策）
	if not is_mp and _player_index != local_idx:
		print("[他山之石] post_draw_animation: AI 抽到，执行 _auto_select")
		_auto_select(mod_loader)
		return
	if is_mp and _player_index != local_idx:
		print("[他山之石] post_draw_animation: 联机对手回合，本端跳过")
		return  # 联机对手回合：对手是真人，由对方客户端处理，本端不显示选择 UI

	if bm == null:
		print("[他山之石] post_draw_animation: BattleManager 为空，_finish_pending")
		_finish_pending()
		return
	## 本地玩家抽到：直接高亮卡牌供点击选择，不再使用弹窗
	var scene: Node = mod_loader.get_tree().current_scene if mod_loader != null else null
	if scene == null:
		_finish_pending()
		return
	_add_abandon_button(scene)
	_highlight_double_cards(scene, mod_loader)


func _auto_select(mod_loader: Node) -> void:
	print("[他山之石] _auto_select: 开始 AI 自动选择 drawer=_player_index=%d" % _player_index)
	var cm: Node = mod_loader.get_card_manager()
	var hands: Dictionary = cm.get("player_hands")
	var bm: Node = mod_loader.get_battle_manager()
	var pc: int = int(bm.get("player_count")) if bm != null else 2
	## 一石二鸟候选：遍历所有玩家手牌，收集所有一石二鸟
	var double_candidates: Array = []  ## [{card, player_index}, ...]
	for pi in range(pc):
		for c in hands.get(pi, []):
			var cname: String = c.card_name if c is CardResource else str(c.get("card_name", ""))
			if cname == DOUBLE_CARD_NAME:
				double_candidates.append({"card": c, "player_index": pi})
	## 若手牌无，遍历回合区
	if double_candidates.is_empty():
		var turn_container: Array = cm.get("turn_container") if cm != null else []
		for c in turn_container:
			var cname: String = c.card_name if c is CardResource else str(c.get("card_name", ""))
			if cname == DOUBLE_CARD_NAME:
				double_candidates.append({"card": c, "player_index": -2})  ## 回合区，软特效仅支持手牌
				break
	var double_card: Variant = null
	var double_from: int = -1
	if not double_candidates.is_empty():
		var idx: int = randi() % double_candidates.size()
		double_card = double_candidates[idx].card
		double_from = double_candidates[idx].player_index
	## 对手牌候选：遍历所有玩家（除抽牌者外），收集除一石二鸟以外的所有卡牌
	var opp_candidates: Array = []  ## [{card, player_index}, ...]
	for pi in range(pc):
		if pi == _player_index:
			continue
		for c in hands.get(pi, []):
			if c != double_card:
				opp_candidates.append({"card": c, "player_index": pi})
	## 随机选择对手牌
	var opp_card: Variant = null
	var opponent_index: int = -1
	if not opp_candidates.is_empty():
		var idx: int = randi() % opp_candidates.size()
		opp_card = opp_candidates[idx].card
		opponent_index = opp_candidates[idx].player_index
	## 仅当双牌在手牌且找到对手牌时请求移除；双牌在回合区时只移除对手牌或直接继续
	var to_remove: Array = []
	if double_card != null and double_from >= 0:
		to_remove.append({"card": double_card, "player_index": double_from})
	if opp_card != null:
		to_remove.append({"card": opp_card, "player_index": opponent_index})
	if not to_remove.is_empty():
		print("[他山之石] _auto_select: 请求移除 %d 张牌" % to_remove.size())
		bm.request_mod_soft_remove_effect(to_remove)
		## 阻塞：等 battle_test 删牌特效完成后再 mod_resume，此处仅清理 Mod 状态
		_finish_pending()
	else:
		print("[他山之石] _auto_select: 无牌可移除（双牌在回合区或对手无牌），直接继续")
		_finish_and_continue()


func _add_abandon_button(scene: Node) -> void:
	if _abandon_btn != null and is_instance_valid(_abandon_btn):
		return
	var btn_row: Control = scene.get_node_or_null(BTN_ROW_PATH)
	if btn_row == null:
		return
	_abandon_btn = Button.new()
	_abandon_btn.text = "放弃"
	_abandon_btn.pressed.connect(_on_abandon_pressed)
	btn_row.add_child(_abandon_btn)


func _on_abandon_pressed() -> void:
	_remove_abandon_button()
	_cleanup_hijack()
	_finish_and_continue()


func _remove_abandon_button() -> void:
	if _abandon_btn != null and is_instance_valid(_abandon_btn):
		_abandon_btn.queue_free()
		_abandon_btn = null


func _highlight_double_cards(scene: Node, mod_loader: Node) -> void:
	var bm: Node = mod_loader.get_battle_manager() if mod_loader != null else null
	var pc: int = int(bm.get("player_count")) if bm != null else 2
	for pi in range(pc):
		var hand_container: Control = scene.get_target_container(pi) if scene.has_method("get_target_container") else scene.get_node_or_null(PLAYER_HAND_PATH if pi == 0 else OPPONENT_HAND_PATH)
		if hand_container == null:
			continue
		for child in hand_container.get_children():
			var card_data = child.get("card_data")
			if card_data == null:
				continue
			var cname: String = card_data.card_name if card_data is CardResource else str(card_data.get("card_name", ""))
			if cname == DOUBLE_CARD_NAME:
				child.modulate = HIGHLIGHT_MODULATE
				var cb: Callable = _on_double_clicked.bind(card_data, pi)
				child.gui_input.connect(cb)
				_hijack_uis.append({"ui": child, "callable": cb})


func _on_double_clicked(event: InputEvent, card_data: Variant, from_player: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var mod_loader: Node = Engine.get_main_loop().root.get_node_or_null("ModLoader")
	if mod_loader != null:
		var bm: Node = mod_loader.get_battle_manager()
		if bm != null and not bm.call("is_my_turn"):
			return
	_select_double(card_data, from_player, mod_loader)


func _select_double(card_data: Variant, from_player: int, mod_loader: Node) -> void:
	_double_selected = card_data
	_double_from_player = from_player
	_cleanup_hijack()
	_highlight_opponent_cards(mod_loader)


func _highlight_opponent_cards(mod_loader: Node) -> void:
	var scene: Node = mod_loader.get_tree().current_scene if mod_loader != null else null
	if scene == null:
		_finish_pending()
		return
	var bm: Node = mod_loader.get_battle_manager() if mod_loader != null else null
	var pc: int = int(bm.get("player_count")) if bm != null else 2
	## 第二次选择：从对手手牌中选（对手=非抽牌者），排除已选的一石二鸟由内层 card_data==_double_selected 处理
	for opponent_index in range(pc):
		if opponent_index == _player_index:
			continue
		var hand_container: Control = scene.get_target_container(opponent_index) if scene.has_method("get_target_container") else scene.get_node_or_null(OPPONENT_HAND_PATH if opponent_index == 1 else PLAYER_HAND_PATH)
		if hand_container == null:
			continue
		for child in hand_container.get_children():
			var card_data = child.get("card_data")
			if card_data == null:
				continue
			## 第二次选择：仅对手卡牌，排除第一次已选的一石二鸟
			if _double_selected != null and card_data == _double_selected:
				continue
			child.modulate = HIGHLIGHT_MODULATE
			var cb: Callable = _on_opponent_clicked.bind(card_data, opponent_index)
			child.gui_input.connect(cb)
			_hijack_uis.append({"ui": child, "callable": cb})


func _on_opponent_clicked(event: InputEvent, card_data: Variant, opponent_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var mod_loader: Node = Engine.get_main_loop().root.get_node_or_null("ModLoader")
	if mod_loader != null:
		var bm: Node = mod_loader.get_battle_manager()
		if bm != null and not bm.call("is_my_turn"):
			return
	_execute_remove(card_data, opponent_index, mod_loader)


func _execute_remove(opponent_card: Variant, opponent_index: int, mod_loader: Node) -> void:
	if _double_selected == null:
		return
	var bm: Node = mod_loader.get_battle_manager()
	var cm: Node = mod_loader.get_card_manager()

	var nm: Node = Engine.get_main_loop().root.get_node_or_null("NetworkManager")
	var is_mp: bool = nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer")
	## multiplayer 在 Node 上，mod_loader 是 Node；SceneTree 无 multiplayer 属性
	var is_server: bool = not is_mp or (mod_loader is Node and mod_loader.multiplayer != null and mod_loader.multiplayer.is_server())

	if is_mp and not is_server:
		## 联机客户端：发送选择索引给主机执行
		var hands: Dictionary = cm.get("player_hands")
		var double_idx: int = hands.get(_double_from_player, []).find(_double_selected)
		var opp_hand_idx: int = hands.get(opponent_index, []).find(opponent_card)
		if double_idx >= 0 and opp_hand_idx >= 0 and bm.has_method("request_tashanzhishi_selection"):
			bm.call("request_tashanzhishi_selection", {
				"double_from": _double_from_player,
				"double_idx": double_idx,
				"opp_idx": opponent_index,
				"opp_hand_idx": opp_hand_idx
			})
	else:
		## 主机或单机：直接请求特效
		bm.request_mod_soft_remove_effect([
			{"card": _double_selected, "player_index": _double_from_player},
			{"card": opponent_card, "player_index": opponent_index}
		])
		## 阻塞：等 battle_test 删牌特效完成后再 mod_resume，此处仅清理 UI 状态
		_remove_abandon_button()
		_cleanup_hijack()
		_finish_pending()
		return

	_remove_abandon_button()
	_cleanup_hijack()
	_finish_and_continue()


func _cleanup_hijack() -> void:
	for h in _hijack_uis:
		var ui = h["ui"]
		var cb: Callable = h["callable"]
		if is_instance_valid(ui):
			ui.modulate = Color.WHITE
			if ui.gui_input.is_connected(cb):
				ui.gui_input.disconnect(cb)
	_hijack_uis.clear()


func _finish_and_continue() -> void:
	var mod_loader: Node = Engine.get_main_loop().root.get_node_or_null("ModLoader")
	_log("他山之石", "_finish_and_continue", {"mod_loader": mod_loader != null})
	print("[他山之石] _finish_and_continue: mod_loader=%s" % (mod_loader != null))
	if mod_loader != null:
		var bm: Node = mod_loader.get_battle_manager()
		# 不结算本回合，卡牌留在回合区，继续抽牌（符合默认规则）；联机客户端需 RPC 到主机
		if bm.has_method("request_mod_resume_without_settle"):
			bm.request_mod_resume_without_settle()
		else:
			bm.mod_resume_without_settle()
	_finish_pending()


func _finish_pending() -> void:
	_pending = false
	_double_selected = null
	_double_from_player = -1
	_cleanup_hijack()
	_remove_abandon_button()
