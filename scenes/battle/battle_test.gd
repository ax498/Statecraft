## 战斗测试场景脚本
## 手牌与回合牌堆常驻显示、飞牌动画、矛盾淡出
extends Control

const CARD_UI_SCENE: PackedScene = preload("res://scenes/ui/card_ui.tscn")
const CARD_BACK_TEXTURE: String = "res://resources/pictures/card.png"
## 卡牌过多显示：超过此数量开始缩小
const HAND_SCALE_THRESHOLD: int = 10
const HAND_MIN_SCALE: float = 0.35
const TURN_SCALE_THRESHOLD: int = 6
const TURN_MIN_SCALE: float = 0.65
const FADE_OUT_SCALE: float = 0.25  ## 矛盾淡出时统一缩小目标，避免卡牌在淡出时变大
const MAX_PLAYERS: int = 8
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 1.5
## 滚轮/快捷键：每次一档的倍率（乘法比固定 ±0.1 更接近白板/浏览器的顺滑感）
const ZOOM_FACTOR_PER_NOTCH: float = 1.07
## 单指空白处：移动超过此像素才视为拖屏，避免连点被当成平移
const PAN_TOUCH_SLOP_PX: float = 14.0
## 双指初始间距下限（像素，画布全局距离），避免除零；过小仍建立基线以便首帧能捏合
const PINCH_MIN_SEPARATION: float = 0.05
## 设为 true 时向控制台输出触控/捏合/拖屏状态（真机 adb logcat 可见）
const DEBUG_VIEWPORT_TOUCH: bool = true
## 捏合缩放日志节流（秒），避免一帧多条 pinch scale 刷屏
const DEBUG_PINCH_LOG_INTERVAL_SEC: float = 0.12
## 卡牌 UI 基础尺寸（与 card_ui.tscn 的 custom_minimum_size 一致）
const CARD_BASE_W: float = 80.0
const CARD_BASE_H: float = 120.0
## 回合区默认尺寸：至少容纳 5 张完整卡牌 + 间隔
const TURN_CARD_SEP: float = 8.0
const TURN_INITIAL_MIN_W: float = 5.0 * CARD_BASE_W + 4.0 * TURN_CARD_SEP  ## 5 张牌 + 4 个间隔
const TURN_INITIAL_MIN_H: float = CARD_BASE_H + 20.0  ## 卡牌高度 + 上下边距
## 卡牌高度（用于信息色块竖直间隔）
const CARD_HEIGHT: float = 120.0
## 信息色块竖直间隔：1.5 张卡牌高度
const INFO_BLOCK_ROW_GAP: float = 180.0  ## 1.5 * CARD_HEIGHT

@onready var bg_rect: TextureRect = $Background
@onready var shake_layer: CanvasLayer = $ShakeLayer
@onready var flash_rect: ColorRect = $ShakeLayer/FlashRect
@onready var shake_root: Control = $ShakeLayer/Root
@onready var deck_count_label: Label = $ShakeLayer/Root/MainMargin/MainVBox/FixedTop/DeckCountLabel
@onready var current_player_label: Label = $ShakeLayer/Root/MainMargin/MainVBox/FixedTop/StatusRow/CurrentPlayerLabel
@onready var score_label: Label = $ShakeLayer/Root/MainMargin/MainVBox/FixedTop/StatusRow/ScoreLabel
@onready var result_panel: Control = $ResultLayer/ResultPanel
@onready var result_title_label: Label = $ResultLayer/ResultPanel/CenterContainer/Panel/VBox/ResultTitleLabel
@onready var result_score_label: Label = $ResultLayer/ResultPanel/CenterContainer/Panel/VBox/ResultScoreLabel
@onready var restart_btn: Button = $ResultLayer/ResultPanel/CenterContainer/Panel/VBox/BtnRow/RestartBtn
@onready var back_btn: Button = $ResultLayer/ResultPanel/CenterContainer/Panel/VBox/BtnRow/BackBtn
@onready var game_viewport: Control = $ShakeLayer/Root/MainMargin/MainVBox/GameViewport
## 与 GameViewport 同尺寸、置于 ViewportContent 之下：平移后 content 全局矩形偏移时，条带区仍能收到 gui_input（平移/触控）
@onready var viewport_pan_hit: Control = $ShakeLayer/Root/MainMargin/MainVBox/GameViewport/ViewportPanHit
@onready var viewport_content: Control = $ShakeLayer/Root/MainMargin/MainVBox/GameViewport/ViewportContent
@onready var turn_container_wrapper: PanelContainer = $ShakeLayer/Root/MainMargin/MainVBox/GameViewport/ViewportContent/TurnContainerWrapper
@onready var turn_container_display: HBoxContainer = $ShakeLayer/Root/MainMargin/MainVBox/GameViewport/ViewportContent/TurnContainerWrapper/TurnContainerScroll/TurnContainerDisplay
@onready var other_players_area: Control = $ShakeLayer/Root/MainMargin/MainVBox/GameViewport/ViewportContent/OtherPlayersArea
## 色块容器：覆盖全场景，色块可拖到任意位置
var _blocks_layer: Control = null
@onready var player_hand_display: HBoxContainer = $ShakeLayer/Root/MainMargin/MainVBox/FixedBottom/PlayerHandScroll/PlayerHandDisplay
@onready var draw_btn: Button = $ShakeLayer/Root/MainMargin/MainVBox/FixedBottom/BtnRow/DrawBtn
@onready var end_turn_btn: Button = $ShakeLayer/Root/MainMargin/MainVBox/FixedBottom/BtnRow/EndTurnBtn
@onready var log_label: RichTextLabel = $ShakeLayer/Root/MainMargin/MainVBox/FixedBottom/Log
@onready var setting_btn: Button = $ShakeLayer/Root/SettingBtn
@onready var setting_panel: PopupPanel = $ShakeLayer/Root/SettingPanel
@onready var setting_button_container: VBoxContainer = $ShakeLayer/Root/SettingPanel/MarginContainer/VBox/ButtonContainer
@onready var mod_detail_panel: Control = $ModLayer/ModDetailPanel
@onready var mod_list: VBoxContainer = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/ScrollContainer/ModList
@onready var mod_detail_label: Label = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/DetailLabel
@onready var mod_override_label: Label = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/OverrideLabel
@onready var mod_close_btn: Button = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/CloseBtn
@onready var mod_gen_template_btn: Button = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/GenTemplateBtn
@onready var mod_browse_dir_btn: Button = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/BrowseDirBtn
@onready var mod_refresh_btn: Button = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/RefreshModsBtn
@onready var mod_restart_hint: Label = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/RestartHintLabel

## 通过场景树获取 GameLogger（避免 autoload 解析问题）
func _log_record(tag: String, action: String, data: Variant = "") -> void:
	var gl: Node = get_node_or_null("/root/GameLogger")
	if gl and gl.has_method("record"):
		gl.record(tag, action, data)

func _log_flush() -> void:
	var gl: Node = get_node_or_null("/root/GameLogger")
	if gl and gl.has_method("flush"):
		gl.flush()

## 统一获取玩家显示名（论策/联机用 battle_manager，否则「玩家」「对手」或「玩家N」）
func _get_player_display_name(pi: int) -> String:
	if battle_manager != null and battle_manager.has_method("get_player_display_name"):
		return battle_manager.get_player_display_name(pi)
	var pc_val = battle_manager.get("player_count") if battle_manager != null else 2
	var pc: int = clampi(int(pc_val) if pc_val != null else 2, 2, MAX_PLAYERS)
	return "玩家" if (pc == 2 and pi == 0) else ("对手" if (pc == 2 and pi == 1) else ("玩家%d" % (pi + 1)))

## 从 CardResource 或 Dictionary 抽取卡牌名与分值，避免重复类型判断
func _get_card_name_and_value(c: Variant) -> Dictionary:
	if c is CardResource:
		return {"name": c.card_name, "value": c.effect_value}
	return {"name": str(c.get("card_name", "")), "value": int(c.get("effect_value", 0))}

var card_manager: Node
var battle_manager: Node
var mod_manager: Node
var network_manager: Node
var _shake_tween: Tween
var _flash_tween: Tween
var _contradiction_this_turn: bool = false
var _contradiction_protected_indices: Array = []
var _contradiction_player_index: int = 0
var _draw_animation_in_progress: bool = false
var _pending_hand_update: int = -1
var _opponent_exit_popup_shown: bool = false
var _jiuniuyimao_abandon_btn: Button = null
var _jiuniuyimao_animating_steal: bool = false
var _chuqizhisheng_abandon_btn: Button = null
var _toulianghuanzhu_abandon_btn: Button = null
## 多人模式：player_index -> {node, color_rect, info_label, container, cards_hbox}
var _player_info_blocks: Dictionary = {}
## player_index -> HBoxContainer（卡牌容器），非本地玩家
var _player_hand_containers: Dictionary = {}
## 色块拖动：player_index -> 保存的 position
var _other_player_positions: Dictionary = {}
## 色块拖动：当前拖动的 block_row
var _dragging_block: Control = null
var _drag_offset: Vector2 = Vector2.ZERO
## 选择类卡牌：直接点击高亮卡牌选择（九牛一毛、出奇制胜）
var _selection_highlight_uis: Array = []  ## [{ui, callable}]
var _selection_highlight_mode: String = ""  ## "jiuniuyimao" | "chuqizhisheng" | "toulianghuanzhu"
var _selection_highlight_drawer_index: int = -1
## 游戏区域缩放：0.5~1.5
var _game_view_scale: float = 1.0
## 空白处拖动平移：是否正在拖动、起始位置、viewport_content 起始偏移
var _pan_dragging: bool = false
var _pan_start: Vector2 = Vector2.ZERO
var _pan_content_start: Vector2 = Vector2.ZERO
## 安卓多点触控：触点 index -> 全局坐标（与 get_global_mouse_position 一致）
var _touch_positions: Dictionary = {}
## 双指捏合：上一帧两指距离（用于距离比）；非双指时归零
var _pinch_d_prev: float = 0.0
## 单指平移由触控驱动时记录 index（桌面鼠标为 -1）
var _pan_touch_index: int = -1
## 触控：仅在空白层按下，超过 PAN_TOUCH_SLOP_PX 后才置 _pan_dragging（区分点击与拖屏）
var _pan_touch_pending: bool = false
var _pan_pending_index: int = -1
var _pan_pending_start_global: Vector2 = Vector2.ZERO
var _pan_pending_content_start: Vector2 = Vector2.ZERO
var _debug_pinch_last_log_time: float = -1.0
## 双指平移：两指中点上一帧的全局坐标（用于增量平移）
var _pinch_mid_prev_global: Vector2 = Vector2.ZERO
var _pinch_mid_pan_initialized: bool = false


func _vp_touch_dbg(msg: String) -> void:
	if not DEBUG_VIEWPORT_TOUCH:
		return
	print("[ViewportTouch] %s" % msg)


## 与 _is_touch_on_viewport_pan_blank_layer 同义（当前未引用，保留供调试/将来复用）
func _can_start_viewport_pan_at_global(gpos: Vector2) -> bool:
	return _is_touch_on_viewport_pan_blank_layer(gpos)


## viewport_content.position 在 GameViewport 本地空间；触点用画布全局坐标，须换算后再取差，否则缩放后单指拖会「跳」
func _apply_viewport_pan_from_global_points(g_cur: Vector2, g_start: Vector2, content_start: Vector2) -> void:
	if viewport_content == null or not is_instance_valid(viewport_content):
		return
	if game_viewport == null or not is_instance_valid(game_viewport):
		viewport_content.position = content_start + (g_cur - g_start)
		return
	var lp0: Vector2 = _global_to_game_viewport_local(g_start)
	var lp1: Vector2 = _global_to_game_viewport_local(g_cur)
	viewport_content.position = content_start + (lp1 - lp0)


func _ready() -> void:
	_setup_background()
	_setup_managers()
	_connect_signals()
	# 隐藏状态下禁用面板，避免拦截鼠标事件
	mod_detail_panel.process_mode = Node.PROCESS_MODE_DISABLED
	result_panel.process_mode = Node.PROCESS_MODE_DISABLED
	# 论策模式：is_lunce_mode 由 main_menu 点击论策时设置，不受 is_multiplayer 影响
	var nm: Node = network_manager
	var is_lunce: bool = battle_manager.get("is_lunce_mode")
	var just_restarted: bool = false
	if nm != null and nm.has_method("consume_restart_flag"):
		just_restarted = nm.call("consume_restart_flag")
	print("[BattleTest] _ready: is_lunce=%s, just_restarted=%s, current_player_index(before)=%s" % [is_lunce, just_restarted, battle_manager.current_player_index])
	if is_lunce:
		card_manager.reset_for_new_game()
		battle_manager.reset_to_start()
		battle_manager.set("current_player_index", 0)
		_update_ui_state_with_index(0)
		print("[BattleTest] _ready: is_lunce 分支执行后 current_player_index=%s" % battle_manager.current_player_index)
		# 重新开始后确保单机逻辑正确，延迟一帧再刷新 UI 避免时序问题
		if just_restarted:
			call_deferred("_ensure_single_player_ui_after_restart")
	_update_scores(0, 0)
	_update_ui_state()
	print("[BattleTest] _ready: 最终 current_player_index=%s, current_player_label.text=%s" % [battle_manager.current_player_index, current_player_label.text])
	_on_deck_count_changed(card_manager.global_deck.size())
	## 色块全场景容器：需在 _ensure_hand_layout 前创建
	_setup_blocks_layer()
	# 论策模式：若加载时已是对手回合（玩家结束回合后重载等），确保 AI 会行动
	if is_lunce and battle_manager.current_player_index != 0 and battle_manager.current_state == battle_manager.State.PLAYER_TURN:
		call_deferred("_ensure_ai_turn")
	_ensure_hand_layout()
	_refresh_hand_displays()
	_restore_turn_container_initial_size()
	_apply_restart_visibility()
	log_label.scroll_following = true
	if just_restarted:
		log_label.append_text("\n[color=#888]战斗测试已就绪，点击「抽牌」开始[/color]")
		_append_log("[color=green]游戏重新开始[/color]", -2)
	else:
		log_label.append_text("\n[color=#888]战斗测试已就绪，点击「抽牌」开始[/color]")
	_apply_game_view_scale()
	## 空白处拖动：让子控件空白区域穿透，使 ViewportContent 能收到点击
	_setup_pan_input()


func _setup_blocks_layer() -> void:
	_blocks_layer = Control.new()
	_blocks_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocks_layer.anchor_left = 0.0
	_blocks_layer.anchor_top = 0.0
	_blocks_layer.anchor_right = 1.0
	_blocks_layer.anchor_bottom = 1.0
	_blocks_layer.offset_left = 0
	_blocks_layer.offset_top = 0
	_blocks_layer.offset_right = 0
	_blocks_layer.offset_bottom = 0
	_blocks_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blocks_layer.clip_contents = false
	## 放入 viewport_content 使色块随游戏区域缩放、平移
	viewport_content.add_child(_blocks_layer)


func _setup_pan_input() -> void:
	if turn_container_wrapper != null:
		turn_container_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var scroll: Control = turn_container_wrapper.get_node_or_null("TurnContainerScroll")
		if scroll != null:
			scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if other_players_area != null:
		other_players_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if viewport_pan_hit != null:
		viewport_pan_hit.mouse_filter = Control.MOUSE_FILTER_STOP
		if not viewport_pan_hit.gui_input.is_connected(_on_viewport_pan_layer_gui_input):
			viewport_pan_hit.gui_input.connect(_on_viewport_pan_layer_gui_input)
	if viewport_content != null:
		## 父级 STOP 会在 scale/position 后与视觉命中错位，导致「只有原来那一块能触控」；
		## IGNORE：空白处穿透到底层 ViewportPanHit 统一拖屏；子控件（卡牌等）仍各自 STOP 先接收
		viewport_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not viewport_content.resized.is_connected(_on_viewport_content_resized):
			viewport_content.resized.connect(_on_viewport_content_resized)
		_update_viewport_content_pivot()
		viewport_content.position = Vector2.ZERO
	set_process_input(true)


func _on_viewport_content_resized() -> void:
	_update_viewport_content_pivot()


func _update_viewport_content_pivot() -> void:
	if viewport_content != null and is_instance_valid(viewport_content):
		## 与缩放锚点一致；布局变化后若不更新，触控命中会与视觉错位
		viewport_content.pivot_offset = viewport_content.size * 0.5


## 安卓上触点不更新「虚拟鼠标」位置，gui_get_hovered_control 仍按旧坐标拾取，空白拖屏会整块误判。
## 在依据 hover 判定前，把视口内鼠标同步到与触点一致（真机无可见光标）。
func _sync_viewport_mouse_to_canvas_global_for_pick(g_canvas_global: Vector2) -> void:
	if OS.get_name() != "Android":
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var xf: Transform2D = vp.get_canvas_transform()
	if absf(xf.determinant()) < 1e-8:
		return
	var vp_local: Vector2 = xf.affine_inverse() * g_canvas_global
	vp.warp_mouse(vp_local)


## 触点是否在「空白拖屏层」：点在 PanHit 矩形内，且悬停不是 viewport_content 子树（卡牌等）即可。
## 若要求 hover==PanHit 或 hover==null，在 hover==GameViewport 等父级时会误判为不可拖（区域死角）。
func _is_touch_on_viewport_pan_blank_layer(gpos: Vector2) -> bool:
	if viewport_pan_hit == null or not is_instance_valid(viewport_pan_hit):
		return false
	if not viewport_pan_hit.get_global_rect().has_point(gpos):
		return false
	var vp: Viewport = get_viewport()
	if vp == null:
		return true
	var hover: Control = vp.gui_get_hovered_control() as Control
	if hover != null and viewport_content != null and is_instance_valid(viewport_content) and viewport_content.is_ancestor_of(hover):
		return false
	return true


func _try_begin_touch_pan_pending(idx: int) -> void:
	if _touch_active_count() != 1 or not _touch_positions.has(idx):
		return
	var g: Vector2 = _touch_positions[idx]
	_sync_viewport_mouse_to_canvas_global_for_pick(g)
	if not _is_touch_on_viewport_pan_blank_layer(g):
		return
	_pan_touch_pending = true
	_pan_pending_index = idx
	_pan_pending_start_global = g
	_pan_pending_content_start = viewport_content.position if viewport_content else Vector2.ZERO


## 平移：桌面用鼠标；触控的待拖屏/拖屏在 _input 里登记（避免 gui_input 与 _input 顺序导致读到旧 _touch_positions）
func _on_viewport_pan_layer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		## 安卓会为触摸合成鼠标左键；若同时处理会与 ScreenTouch 抢状态，导致错位/假拖屏
		if OS.get_name() == "Android":
			return
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pan_dragging = true
				_pan_touch_index = -1
				_pan_start = mb.global_position
				_pan_content_start = viewport_content.position if viewport_content else Vector2.ZERO
				accept_event()
			else:
				_pan_dragging = false
				_pan_touch_index = -1
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if not st.pressed:
			if _pan_touch_index == st.index:
				_pan_dragging = false
				_pan_touch_index = -1
			if _pan_pending_index == st.index:
				_pan_touch_pending = false
				_pan_pending_index = -1


## 仅在「position 为视口坐标」时使用：根节点 _input() 里的 ScreenTouch/ScreenDrag。
## gui_input() 里 ScreenTouch.position 是相对控件的本地坐标，勿传入本函数。
## InputEventScreenTouch 在部分 Godot 版本无 global_position，统一用 viewport 画布变换。
func _viewport_event_pos_to_global(screen_event: InputEvent) -> Vector2:
	var vp: Viewport = get_viewport()
	if vp == null:
		return Vector2.ZERO
	var local_pos: Vector2 = screen_event.position
	return vp.get_canvas_transform() * local_pos


## 部分安卓机双指捏合时 ScreenDrag 的 position 不更新，但 relative 仍有增量；用画布变换积分才能更新间距。
## 仅双指时启用：单指拖屏若误走 relative 分支会导致几乎不动或乱飘。
func _screen_drag_global_canvas(sd: InputEventScreenDrag) -> Vector2:
	var vp: Viewport = get_viewport()
	var from_pos: Vector2 = _viewport_event_pos_to_global(sd)
	if vp == null:
		return from_pos
	if OS.get_name() != "Android":
		return from_pos
	if _touch_active_count() < 2:
		return from_pos
	if not _touch_positions.has(sd.index):
		return from_pos
	var prev: Vector2 = _touch_positions[sd.index]
	var rel: Vector2 = sd.relative
	if rel.length_squared() < 1e-8:
		return from_pos
	var delta_canvas: Vector2 = vp.get_canvas_transform().basis_xform(rel)
	var exp_sq: float = delta_canvas.length_squared()
	var actual_sq: float = from_pos.distance_squared_to(prev)
	## 慢速捏合 exp_sq 也小，用 maxf 避免误判为「走绝对坐标」而继续卡死
	if actual_sq < 0.12 * maxf(exp_sq, 0.25):
		return prev + delta_canvas
	return from_pos


## 第二指落下时立即对齐双指平移基线，避免「先 init 再被 kick/下一帧」导致中点突变、画面猛跳
func _sync_pinch_mid_pan_baseline_after_second_finger() -> void:
	if _touch_active_count() < 2:
		return
	if game_viewport == null or not is_instance_valid(game_viewport):
		return
	var mid_global: Vector2 = _pinch_midpoint_global()
	if not game_viewport.get_global_rect().has_point(mid_global):
		return
	_pinch_mid_prev_global = mid_global
	_pinch_mid_pan_initialized = true


func _global_to_game_viewport_local(global_pt: Vector2) -> Vector2:
	if game_viewport == null or not is_instance_valid(game_viewport):
		return Vector2.ZERO
	return game_viewport.get_global_transform_with_canvas().affine_inverse() * global_pt


func _reset_touch_pinch_pan_state() -> void:
	_touch_positions.clear()
	_pinch_d_prev = 0.0
	_pan_dragging = false
	_pan_touch_index = -1
	_pan_touch_pending = false
	_pan_pending_index = -1
	_pinch_mid_pan_initialized = false
	_pinch_mid_prev_global = Vector2.ZERO


func _cancel_pan_for_second_finger() -> void:
	_pan_dragging = false
	_pan_touch_index = -1
	_pan_touch_pending = false
	_pan_pending_index = -1
	_pinch_mid_pan_initialized = false


func _touch_active_count() -> int:
	return _touch_positions.size()


## 仅取前两枚触点参与捏合（≥3 指时忽略多余指，避免鬼畜）
func _two_finger_keys_sorted() -> Array:
	if _touch_positions.size() < 2:
		return []
	var keys: Array = _touch_positions.keys()
	keys.sort()
	return [keys[0], keys[1]]


func _pinch_midpoint_global() -> Vector2:
	var k2: Array = _two_finger_keys_sorted()
	if k2.is_empty():
		return Vector2.ZERO
	return (_touch_positions[k2[0]] + _touch_positions[k2[1]]) * 0.5


func _init_pinch_d_prev_from_touches() -> void:
	var k2: Array = _two_finger_keys_sorted()
	if k2.is_empty():
		return
	var d: float = _touch_positions[k2[0]].distance_to(_touch_positions[k2[1]])
	if d >= PINCH_MIN_SEPARATION:
		_pinch_d_prev = d
		_vp_touch_dbg("pinch_init d=%.2f keys=%s" % [d, str(k2)])
	else:
		_pinch_d_prev = 0.0
		_vp_touch_dbg("pinch_init wait_drag d=%.2f keys=%s" % [d, str(k2)])


func _apply_pinch_from_two_finger_positions() -> void:
	var k2: Array = _two_finger_keys_sorted()
	if k2.is_empty():
		return
	var p0: Vector2 = _touch_positions[k2[0]]
	var p1: Vector2 = _touch_positions[k2[1]]
	var d: float = p0.distance_to(p1)
	var mid_global: Vector2 = (p0 + p1) * 0.5
	if _pinch_d_prev <= 0.0:
		if d < PINCH_MIN_SEPARATION:
			return
		_pinch_d_prev = d
		return
	if d < PINCH_MIN_SEPARATION:
		return
	var ratio: float = d / _pinch_d_prev
	_pinch_d_prev = d
	var new_s: float = clampf(_game_view_scale * ratio, ZOOM_MIN, ZOOM_MAX)
	if absf(new_s - _game_view_scale) < 1e-5:
		return
	var old_s: float = _game_view_scale
	_game_view_scale = new_s
	var focal: Vector2 = _global_to_game_viewport_local(mid_global)
	if game_viewport != null and is_instance_valid(game_viewport):
		var sz: Vector2 = game_viewport.size
		focal.x = clampf(focal.x, 0.0, sz.x)
		focal.y = clampf(focal.y, 0.0, sz.y)
	_apply_game_view_scale_at(focal)
	var now_sec: float = Time.get_ticks_msec() * 0.001
	if DEBUG_VIEWPORT_TOUCH and (now_sec - _debug_pinch_last_log_time >= DEBUG_PINCH_LOG_INTERVAL_SEC):
		_debug_pinch_last_log_time = now_sec
		_vp_touch_dbg("pinch scale %.3f -> %.3f mid_global=%s" % [old_s, new_s, str(mid_global)])


## 双指拖动：两指中点在 GameViewport 内的位移 → 与单指相同的本地差分平移
func _apply_two_finger_pan_from_midpoint_delta() -> void:
	if viewport_content == null or not is_instance_valid(viewport_content):
		return
	if game_viewport == null or not is_instance_valid(game_viewport):
		return
	if _touch_active_count() < 2:
		_pinch_mid_pan_initialized = false
		return
	var k2: Array = _two_finger_keys_sorted()
	if k2.is_empty():
		return
	var mid_global: Vector2 = (_touch_positions[k2[0]] + _touch_positions[k2[1]]) * 0.5
	if not game_viewport.get_global_rect().has_point(mid_global):
		return
	if not _pinch_mid_pan_initialized:
		_pinch_mid_prev_global = mid_global
		_pinch_mid_pan_initialized = true
		return
	var lp_mid: Vector2 = _global_to_game_viewport_local(mid_global)
	var lp_prev: Vector2 = _global_to_game_viewport_local(_pinch_mid_prev_global)
	viewport_content.position += lp_mid - lp_prev
	_pinch_mid_prev_global = mid_global


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_touch_pinch_pan_state()


## 手动 QA（真机/桌面）：安卓双指捏合跟手，松手后全区域可点牌；单指空白拖屏；大幅缩放+平移后视口四边/角仍可拖屏与滚轮缩放；桌面滚轮与 +/- 不变
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		var gpos: Vector2 = _viewport_event_pos_to_global(st)
		if st.pressed:
			_touch_positions[st.index] = gpos
			_vp_touch_dbg("touch DOWN index=%d count=%d keys=%s pos=%s" % [st.index, _touch_active_count(), str(_touch_positions.keys()), str(gpos)])
			if _touch_active_count() == 1:
				_try_begin_touch_pan_pending(st.index)
			if _touch_active_count() >= 2:
				_cancel_pan_for_second_finger()
				_pinch_d_prev = 0.0
				_init_pinch_d_prev_from_touches()
				_sync_pinch_mid_pan_baseline_after_second_finger()
				## 捏合+双指平移：均在 _process 用 ScreenDrag 触点距离与中点（与平台无关）
		else:
			if _pan_touch_pending and _pan_pending_index == st.index:
				_pan_touch_pending = false
				_pan_pending_index = -1
			_touch_positions.erase(st.index)
			if _touch_active_count() < 2:
				_pinch_d_prev = 0.0
				_pinch_mid_pan_initialized = false
			if _touch_positions.is_empty():
				_pan_dragging = false
				_pan_touch_index = -1
			_vp_touch_dbg("touch UP index=%d remaining=%s" % [st.index, str(_touch_positions.keys())])
		## 不在此处 set_input_as_handled，避免双指起手吞掉下层控件事件导致「顿挫」
		return
	if event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		var gdrag: Vector2 = _screen_drag_global_canvas(sd)
		## 始终写入：避免极短帧序下 Drag 早于 Touch 登记导致丢指、双指捏合无响应
		_touch_positions[sd.index] = gdrag
		var n_touch: int = _touch_active_count()
		## 双指：捏合与双指平移在 _process 统一处理，避免同一帧重复缩放
		if n_touch == 1:
			if _pan_touch_pending and sd.index == _pan_pending_index:
				if gdrag.distance_to(_pan_pending_start_global) >= PAN_TOUCH_SLOP_PX:
					_pan_dragging = true
					_pan_touch_index = _pan_pending_index
					_pan_start = _pan_pending_start_global
					_pan_content_start = _pan_pending_content_start
					_pan_touch_pending = false
					_vp_touch_dbg("pan START slop index=%d g0=%s g=%s" % [sd.index, str(_pan_start), str(gdrag)])
			if _pan_dragging and sd.index == _pan_touch_index and viewport_content != null and is_instance_valid(viewport_content):
				_apply_viewport_pan_from_global_points(gdrag, _pan_start, _pan_content_start)
		return
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_MINUS or ke.keycode == KEY_KP_SUBTRACT:
				_game_view_scale = clampf(_game_view_scale / ZOOM_FACTOR_PER_NOTCH, ZOOM_MIN, ZOOM_MAX)
				if game_viewport != null:
					_apply_game_view_scale_at(game_viewport.size * 0.5)
				else:
					_apply_game_view_scale_at(Vector2.ZERO)
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_EQUAL or ke.keycode == KEY_KP_ADD:
				_game_view_scale = clampf(_game_view_scale * ZOOM_FACTOR_PER_NOTCH, ZOOM_MIN, ZOOM_MAX)
				if game_viewport != null:
					_apply_game_view_scale_at(game_viewport.size * 0.5)
				else:
					_apply_game_view_scale_at(Vector2.ZERO)
				get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = event as InputEventMagnifyGesture
		if OS.get_name() == "Android":
			## 缩放统一由 _process 内 _apply_pinch_from_two_finger_positions（距离比）；此处再乘会与 Magnify 叠乘导致鬼畜
			return
		if _touch_active_count() >= 2:
			return
		_game_view_scale = clampf(_game_view_scale * mg.factor, ZOOM_MIN, ZOOM_MAX)
		_apply_game_view_scale_at(_get_zoom_focal_viewport_local())
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if game_viewport != null and is_instance_valid(game_viewport):
			var rect: Rect2 = game_viewport.get_global_rect()
			if rect.has_point(mb.global_position):
				if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
					if mb.pressed:
						_game_view_scale = clampf(_game_view_scale * ZOOM_FACTOR_PER_NOTCH, ZOOM_MIN, ZOOM_MAX)
						_apply_game_view_scale_at(_get_zoom_focal_viewport_local())
						get_viewport().set_input_as_handled()
				elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					if mb.pressed:
						_game_view_scale = clampf(_game_view_scale / ZOOM_FACTOR_PER_NOTCH, ZOOM_MIN, ZOOM_MAX)
						_apply_game_view_scale_at(_get_zoom_focal_viewport_local())
						get_viewport().set_input_as_handled()


## 缩放焦点：优先指针在 GameViewport 内坐标；否则用区域中心（避免焦点乱跳）
func _get_zoom_focal_viewport_local() -> Vector2:
	if game_viewport == null or not is_instance_valid(game_viewport):
		return Vector2.ZERO
	var r: Rect2 = game_viewport.get_global_rect()
	if r.has_point(get_global_mouse_position()):
		return game_viewport.get_local_mouse_position()
	return game_viewport.size * 0.5


## 以 focal（GameViewport 本地坐标）下像素为锚缩放，避免「永远绕左上角/中心」的僵硬感
func _apply_game_view_scale_at(focal_in_parent: Vector2) -> void:
	if viewport_content == null or not is_instance_valid(viewport_content):
		return
	var new_s: float = clampf(_game_view_scale, ZOOM_MIN, ZOOM_MAX)
	_update_viewport_content_pivot()
	var old_s: float = viewport_content.scale.x
	if abs(old_s - new_s) < 1e-5:
		return
	var old_xform: Transform2D = viewport_content.get_transform()
	var local_pt: Vector2 = old_xform.affine_inverse() * focal_in_parent
	viewport_content.scale = Vector2(new_s, new_s)
	_game_view_scale = new_s
	var new_xform: Transform2D = viewport_content.get_transform()
	viewport_content.position += focal_in_parent - (new_xform * local_pt)


func _apply_game_view_scale() -> void:
	_apply_game_view_scale_at(_get_zoom_focal_viewport_local())


func _setup_background() -> void:
	var tex: Texture2D = load("res://resources/pictures/GameScene.png") as Texture2D
	bg_rect.texture = tex
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	flash_rect.color = Color(1, 0, 0, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


const BTN_ROW_PATH: String = "ShakeLayer/Root/MainMargin/MainVBox/FixedBottom/BtnRow"

func _setup_managers() -> void:
	card_manager = get_node("/root/CardManager")
	battle_manager = get_node("/root/BattleManager")
	mod_manager = get_node("/root/ModManager")
	network_manager = get_node_or_null("/root/NetworkManager")


func _connect_signals() -> void:
	battle_manager.can_draw_changed.connect(_on_can_draw_changed)
	battle_manager.contradiction_started.connect(_on_contradiction_started)
	battle_manager.contradiction_finished.connect(_on_contradiction_finished)
	battle_manager.score_updated.connect(_on_score_updated)
	battle_manager.turn_changed.connect(_on_turn_changed)
	battle_manager.game_ended.connect(_on_game_ended)
	battle_manager.ui_lock_changed.connect(_on_ui_lock_changed)
	battle_manager.hand_collection_requested.connect(_on_hand_collection_requested)
	battle_manager.mod_contradiction_effect_requested.connect(_on_mod_contradiction_effect_requested)
	battle_manager.mod_soft_remove_effect_requested.connect(_on_mod_soft_remove_effect_requested)
	battle_manager.peek_card_display_requested.connect(_on_peek_card_display_requested)
	battle_manager.jiuniuyimao_selection_requested.connect(_on_jiuniuyimao_selection_requested)
	battle_manager.jiuniuyimao_steal_animation_started.connect(_on_jiuniuyimao_steal_animation_started)
	battle_manager.jiuniuyimao_card_added_to_turn.connect(_on_jiuniuyimao_card_added_to_turn)
	battle_manager.chuqizhisheng_selection_requested.connect(_on_chuqizhisheng_selection_requested)
	battle_manager.chuqizhisheng_discard_effect_requested.connect(_on_chuqizhisheng_discard_effect_requested)
	battle_manager.toulianghuanzhu_selection_requested.connect(_on_toulianghuanzhu_selection_requested)
	battle_manager.toulianghuanzhu_swap_requested.connect(_on_toulianghuanzhu_swap_requested)
	battle_manager.jianzaixianshang_play_effect_requested.connect(_on_jianzaixianshang_play_effect_requested)
	battle_manager.client_draw_received.connect(_on_client_draw_received)
	battle_manager.client_consumed_draw_received.connect(_on_client_consumed_draw_received)
	## 他山之石由 Mod 直接高亮卡牌处理，不再通过 battle_test 弹窗
	card_manager.card_drawn.connect(_on_card_drawn)
	card_manager.card_drawn_consumed.connect(_on_card_drawn_consumed)
	card_manager.deck_count_changed.connect(_on_deck_count_changed)
	card_manager.contradiction_triggered.connect(_on_contradiction)
	card_manager.score_contradiction_triggered.connect(_on_score_contradiction)
	card_manager.force_end_turn.connect(_on_force_end_turn)
	card_manager.hand_updated.connect(_on_hand_updated)
	draw_btn.pressed.connect(_on_draw_pressed)
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	setting_btn.pressed.connect(_on_setting_pressed)
	if is_instance_valid(setting_panel):
		setting_panel.transparent = false
		if not setting_panel.popup_hide.is_connected(_on_setting_popup_hide):
			setting_panel.popup_hide.connect(_on_setting_popup_hide)
	if network_manager != null:
		if network_manager.has_method("connect"):
			network_manager.connect("opponent_requested_exit", _on_opponent_requested_exit)
			network_manager.connect("peer_disconnected", _on_peer_disconnected)
	mod_close_btn.pressed.connect(_on_mod_close_pressed)
	mod_gen_template_btn.pressed.connect(_on_gen_template_pressed)
	mod_browse_dir_btn.pressed.connect(_on_browse_dir_pressed)
	mod_refresh_btn.pressed.connect(_on_mod_refresh_pressed)
	restart_btn.connect("pressed", _on_restart_pressed)
	back_btn.pressed.connect(_on_back_to_mode_select_pressed)


func _on_draw_pressed() -> void:
	battle_manager.request_draw()


func _on_end_turn_pressed() -> void:
	battle_manager.request_end_turn()


func _ensure_ai_turn() -> void:
	if battle_manager.has_method("ensure_ai_turn_started"):
		battle_manager.call("ensure_ai_turn_started")


## 单机重新开始后：强制刷新回合 UI，确保显示玩家回合
func _ensure_single_player_ui_after_restart() -> void:
	print("[BattleTest] _ensure_single_player_ui_after_restart: current_player_index(before)=%s" % battle_manager.current_player_index)
	if battle_manager.get("is_lunce_mode"):
		battle_manager.set("current_player_index", 0)
		_update_ui_state_with_index(0)
		print("[BattleTest] _ensure_single_player_ui_after_restart: 已强制 current_player_index=0")


func _on_can_draw_changed(_can_draw: bool) -> void:
	_update_ui_state()


func _on_ui_lock_changed(_locked: bool) -> void:
	_update_ui_state()


func _apply_restart_visibility() -> void:
	if battle_manager.get("is_lunce_mode"):
		restart_btn.disabled = false  # 论策模式：始终可重新开始
		return
	var nm: Node = network_manager
	if nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer"):
		restart_btn.disabled = not multiplayer.is_server()


func _update_ui_state() -> void:
	_update_ui_state_with_index(battle_manager.current_player_index)


func _update_ui_state_with_index(current_index: int) -> void:
	var nm: Node = network_manager
	var is_lunce: bool = battle_manager.get("is_lunce_mode")
	var nm_mp: bool = (nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer"))
	var is_me: bool
	if is_lunce or not nm_mp:
		is_me = (current_index == 0)  # 论策/单机：玩家索引恒为 0
	else:
		var local_idx: int = nm.call("get_local_player_index") if nm != null and nm.has_method("get_local_player_index") else 0
		is_me = (current_index == local_idx)
	var locked: bool = battle_manager.ui_locked
	draw_btn.disabled = not is_me or locked
	end_turn_btn.disabled = not is_me or locked
	## 联机时优先用「我的回合/对手回合」，不依赖 is_lunce（安卓可能残留论策状态）
	if nm != null and nm.has_method("is_multiplayer") and nm_mp:
		current_player_label.text = "我的回合" if is_me else "对手回合"
	else:
		current_player_label.text = "当前轮到：%s" % _get_player_display_name(current_index)
	print("[BattleTest] _update_ui_state_with_index: current_index=%s, is_lunce=%s, nm_mp=%s, is_me=%s -> label=%s" % [current_index, is_lunce, nm_mp, is_me, current_player_label.text])


func _on_turn_changed(player_index: int) -> void:
	_update_ui_state_with_index(player_index)


func _on_score_updated(_player_index: int, _new_score: int) -> void:
	_update_scores(0, 0)
	for pi in _player_info_blocks:
		_update_player_info_block(pi)


func _on_hand_updated(player_index: int) -> void:
	_log_record("BattleTest", "_on_hand_updated", {"player": player_index, "turn_empty": card_manager.turn_container.is_empty()})
	var is_mp: bool = false
	if not battle_manager.get("is_lunce_mode"):
		var nm: Node = network_manager
		is_mp = (nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer"))
	## turn_container 非空时：仅手牌变更（九牛一毛、Mod 移除牌等），只刷新手牌显示，不动画收牌（避免误清回合区）
	if not card_manager.turn_container.is_empty():
		_refresh_hand_displays()
		_update_scores(0, 0)
		for pi in _player_info_blocks:
			_update_player_info_block(pi)
		return
	## Mod 劫持中（如他山之石选择流程）：手牌变更只刷新手牌显示，不触发收牌动画（回合区有他山之石等）
	if battle_manager.get("mod_pause_settlement"):
		_refresh_hand_displays()
		_update_scores(0, 0)
		for pi in _player_info_blocks:
			_update_player_info_block(pi)
		return
	## 联机时收牌动画由 hand_collection_requested 统一触发，跳过本地 hand_updated 的收牌动画
	if is_mp:
		return
	if _draw_animation_in_progress:
		_pending_hand_update = player_index
	else:
		_animate_cards_to_hand(player_index)


func _on_hand_collection_requested(logic_player_index: int) -> void:
	if _draw_animation_in_progress:
		_pending_hand_update = logic_player_index
	else:
		_animate_cards_to_hand(logic_player_index)


func _update_scores(_player_score: int, _opponent_score: int) -> void:
	## 实时分数：各玩家手牌分之和；抽到最后一张牌的玩家额外加回合牌堆分（未触发矛盾时）
	var pc: int = clampi(battle_manager.player_count, 2, MAX_PLAYERS)
	var parts: PackedStringArray = []
	for i in range(pc):
		var name_str: String = _get_player_display_name(i)
		var acc_score: int = battle_manager.get_effective_score(i) if battle_manager.has_method("get_effective_score") else battle_manager.player_scores.get(i, 0)
		parts.append("%s:%d" % [name_str, acc_score])
	score_label.text = " | ".join(parts)


## 计算玩家当前手牌分数总计（effect_value 之和）
func _compute_hand_score(player_index: int) -> int:
	var hands: Array = card_manager.player_hands.get(player_index, [])
	var total: int = 0
	for c in hands:
		if c is CardResource:
			total += c.effect_value
	return total


func _on_deck_count_changed(count: int) -> void:
	deck_count_label.text = "牌堆剩余：%d 张" % count


## 镜像 UI 映射：logic_player_index == 本地索引 -> 底部手牌容器；否则 -> 对手容器
## 所有收牌动画必须调用此函数动态获取目标
func get_target_container(logic_player_index: int) -> HBoxContainer:
	return get_visual_target(logic_player_index)


## 根据逻辑玩家索引返回目标容器（本地=player_hand_display，其他=_player_hand_containers）
func get_visual_target(logic_player_index: int) -> HBoxContainer:
	var local_idx: int = _get_local_player_index()
	if logic_player_index == local_idx:
		return player_hand_display
	return _player_hand_containers.get(logic_player_index, player_hand_display) as HBoxContainer


func _get_local_player_index() -> int:
	if battle_manager.get("is_lunce_mode"):
		return 0
	var nm: Node = network_manager
	if nm == null:
		return 0
	## 联机：is_multiplayer 可能因安卓时序误报，用 is_host 兜底确保客户端 local_idx=1
	if nm.has_method("is_multiplayer") and nm.call("is_multiplayer"):
		return nm.call("get_local_player_index")
	if nm.get("is_host") == false:
		return 1  ## 非主机即客户端
	return 0


## 演兵/局域网联机：非论策，且已建立联机或已与对手连接（终局时 is_multiplayer 偶发不准）
func _is_network_multiplayer_battle() -> bool:
	if battle_manager.get("is_lunce_mode"):
		return false
	var nm: Node = network_manager
	if nm == null:
		return false
	if nm.has_method("is_multiplayer") and nm.call("is_multiplayer"):
		return true
	var oid: Variant = nm.get("opponent_id")
	return oid != null and int(oid) >= 0


## 顶部 + 可缩放区域 + 其他玩家两列布局
func _ensure_hand_layout() -> void:
	var pc: int = clampi(battle_manager.player_count, 2, MAX_PLAYERS)
	var sep: int = _get_player_count_separation(pc)
	player_hand_display.add_theme_constant_override("separation", sep)
	turn_container_display.add_theme_constant_override("separation", sep)
	_ensure_other_players_layout(pc)


## 兼容旧名
func get_visual_container(player_index: int) -> HBoxContainer:
	return get_visual_target(player_index)


## 玩家色块颜色映射
const _PLAYER_COLORS: Array[Color] = [
	Color(0.3, 0.5, 0.9),   # 0 蓝
	Color(0.9, 0.35, 0.35), # 1 红
	Color(0.35, 0.8, 0.4),  # 2 绿
	Color(0.9, 0.75, 0.2),  # 3 黄
	Color(0.7, 0.4, 0.9),   # 4 紫
	Color(0.3, 0.8, 0.9),   # 5 青
	Color(0.95, 0.6, 0.3),  # 6 橙
	Color(0.6, 0.6, 0.6),   # 7 灰
]


## 其他玩家两列布局：色块+卡牌对，可拖动到全场景任意位置，随游戏区域缩放
func _ensure_other_players_layout(pc: int) -> void:
	var local_idx: int = _get_local_player_index()
	var container: Control = _blocks_layer if _blocks_layer != null else other_players_area
	for c in container.get_children():
		c.queue_free()
	_player_info_blocks.clear()
	_player_hand_containers.clear()
	var other_indices: Array = []
	for pi in range(pc):
		if pi != local_idx:
			other_indices.append(pi)
	if other_indices.is_empty():
		return
	var sep: int = _get_player_count_separation(pc)
	## 使用容器尺寸计算布局
	var area_size: Vector2 = container.size
	if area_size.x <= 0 and viewport_content != null:
		area_size = viewport_content.size
	if area_size.x <= 0:
		area_size = get_viewport_rect().size
	var area_w: float = area_size.x - 32
	var col_w: float = max(180, area_w / 2.0 - 8)
	## 竖直间隔：色块高度 + 半张卡牌高度
	var block_row_h: float = 44.0
	var row_h: float = block_row_h + INFO_BLOCK_ROW_GAP
	## 初始位置：_blocks_layer 在 viewport_content 内，与 OtherPlayersArea 对齐（offset_top 160）
	var base_x: float = 8.0
	var base_y: float = 0.0
	if container == _blocks_layer:
		base_y = 160.0
	for i in range(other_indices.size()):
		var pi: int = other_indices[i]
		## 使用纯 Control 作为可定位容器，避免 HBoxContainer 的 layout 导致实际位置与渲染位置不一致
		var block_row: Control = Control.new()
		block_row.set_anchors_preset(Control.PRESET_TOP_LEFT)
		block_row.custom_minimum_size = Vector2(230, 44)
		block_row.mouse_filter = Control.MOUSE_FILTER_STOP
		var saved_pos: Vector2 = _other_player_positions.get(pi, Vector2.ZERO)
		var col: int = i % 2
		var row: int = i >> 1
		if saved_pos != Vector2.ZERO:
			block_row.position = saved_pos
		else:
			block_row.position = Vector2(base_x + col * col_w, base_y + row * row_h)
		var content_hbox: HBoxContainer = HBoxContainer.new()
		content_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		content_hbox.offset_left = 0
		content_hbox.offset_top = 0
		content_hbox.offset_right = 0
		content_hbox.offset_bottom = 0
		## 信息色块与卡牌紧挨，间隔 2
		content_hbox.add_theme_constant_override("separation", 2)
		content_hbox.gui_input.connect(_on_info_block_gui_input.bind(block_row, pi))
		block_row.size = Vector2(250, 44)
		block_row.add_child(content_hbox)
		var info_block: Button = Button.new()
		info_block.flat = true
		info_block.text = ""
		info_block.alignment = HORIZONTAL_ALIGNMENT_LEFT
		info_block.custom_minimum_size = Vector2(120, 36)
		info_block.mouse_filter = Control.MOUSE_FILTER_IGNORE  ## 让点击穿透到 content_hbox，使色块区域可拖动
		info_block.set_meta("player_index", pi)
		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)
		var color_rect: ColorRect = ColorRect.new()
		color_rect.custom_minimum_size = Vector2(6, 24)
		color_rect.color = _PLAYER_COLORS[pi % _PLAYER_COLORS.size()]
		hbox.add_child(color_rect)
		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 0)
		var name_lbl: Label = Label.new()
		name_lbl.text = _get_player_display_name(pi)
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color.BLACK)
		vbox.add_child(name_lbl)
		var info_lbl: Label = Label.new()
		info_lbl.name = "InfoLabel"
		info_lbl.add_theme_font_size_override("font_size", 10)
		info_lbl.add_theme_color_override("font_color", Color.BLACK)
		vbox.add_child(info_lbl)
		hbox.add_child(vbox)
		info_block.add_child(hbox)
		content_hbox.add_child(info_block)
		var cards_hbox: HBoxContainer = HBoxContainer.new()
		cards_hbox.add_theme_constant_override("separation", sep)
		cards_hbox.custom_minimum_size = Vector2(100, 36)
		cards_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE  ## 空白区域穿透，使整行可拖动；卡牌自身仍可接收点击
		content_hbox.add_child(cards_hbox)
		_player_hand_containers[pi] = cards_hbox
		_player_info_blocks[pi] = {"node": info_block, "color_rect": color_rect, "info_label": info_lbl, "block_row": block_row, "cards_hbox": cards_hbox}
		_update_player_info_block(pi)
		container.add_child(block_row)


func _update_player_info_block(pi: int) -> void:
	if not _player_info_blocks.has(pi):
		return
	var block_data: Dictionary = _player_info_blocks[pi]
	var info_lbl: Label = block_data.get("info_label") as Label
	if info_lbl == null:
		return
	var hand_score: int = _compute_hand_score(pi)
	var hand_count: int = card_manager.player_hands.get(pi, []).size()
	info_lbl.text = "分:%d 牌:%d" % [hand_score, hand_count]


func _update_player_info_highlight() -> void:
	pass  ## 所有玩家同时显示，无需高亮选中


func _on_info_block_gui_input(event: InputEvent, block_row: Control, pi: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var parent_ctrl: Control = block_row.get_parent() as Control
			if parent_ctrl == null:
				parent_ctrl = other_players_area
			if mb.pressed:
				_dragging_block = block_row
				_drag_offset = block_row.position - parent_ctrl.get_local_mouse_position()
			else:
				if _dragging_block == block_row:
					_other_player_positions[pi] = block_row.position
				_dragging_block = null


func _process(_delta: float) -> void:
	## 双指：缩放=距离比；平移=两指中点增量（与单指同一套 lp 差分，可边捏合边拖）
	if _touch_active_count() >= 2:
		_apply_pinch_from_two_finger_positions()
		_apply_two_finger_pan_from_midpoint_delta()
	if _dragging_block != null and is_instance_valid(_dragging_block):
		var parent_ctrl: Control = _dragging_block.get_parent() as Control
		if parent_ctrl == null:
			parent_ctrl = other_players_area
		var new_pos: Vector2 = parent_ctrl.get_local_mouse_position() + _drag_offset
		_dragging_block.position = new_pos
	elif _pan_dragging and viewport_content != null and is_instance_valid(viewport_content):
		if _pan_touch_index >= 0:
			## 触控：仅单指时跟手；双指捏合期间不应用平移（避免与捏合抢状态）
			if _touch_active_count() != 1 or not _touch_positions.has(_pan_touch_index):
				return
			var cur_g: Vector2 = _touch_positions[_pan_touch_index]
			_apply_viewport_pan_from_global_points(cur_g, _pan_start, _pan_content_start)
		else:
			_apply_viewport_pan_from_global_points(get_global_mouse_position(), _pan_start, _pan_content_start)


## 人数缩放已取消，始终返回 1.0
func _get_player_count_scale_factor(_pc: int) -> float:
	return 1.0


## 根据人数返回布局间隔：2人=4，8人=1，防止多人时超出屏幕
func _get_player_count_separation(pc: int) -> int:
	if pc <= 2:
		return 4
	return clampi(5 - pc, 1, 4)


func _compute_hand_scale(count: int, pc: int = 2) -> float:
	var base: float
	if count <= HAND_SCALE_THRESHOLD:
		base = 0.6
	else:
		base = max(HAND_MIN_SCALE, 6.0 / float(count))
	return base * _get_player_count_scale_factor(pc)


func _compute_turn_scale(count: int, pc: int = 2) -> float:
	var base: float
	if count <= TURN_SCALE_THRESHOLD:
		base = 1.0
	else:
		base = max(TURN_MIN_SCALE, float(TURN_SCALE_THRESHOLD) / float(count))
	return base * _get_player_count_scale_factor(pc)


func _restore_turn_container_initial_size() -> void:
	if turn_container_wrapper != null and is_instance_valid(turn_container_wrapper):
		turn_container_wrapper.custom_minimum_size = Vector2(TURN_INITIAL_MIN_W, TURN_INITIAL_MIN_H)
		## 恢复默认 offset，使回合结束后宽度回到 400
		turn_container_wrapper.offset_left = -TURN_INITIAL_MIN_W / 2.0
		turn_container_wrapper.offset_right = TURN_INITIAL_MIN_W / 2.0


func _apply_turn_card_scales() -> void:
	var pc: int = clampi(battle_manager.player_count, 2, MAX_PLAYERS)
	var count: int = turn_container_display.get_child_count()
	var s: float = _compute_turn_scale(count, pc)
	for c in turn_container_display.get_children():
		if c.has_method("set_compact"):
			c.set_compact(false, s)
	if turn_container_wrapper != null and is_instance_valid(turn_container_wrapper):
		var sep: float = turn_container_display.get_theme_constant("separation")
		if sep <= 0:
			sep = TURN_CARD_SEP
		## 布局按卡牌原始尺寸分配，scale 只影响视觉不改变布局占用
		var req_w: float = maxf(TURN_INITIAL_MIN_W, count * CARD_BASE_W + maxf(0, count - 1) * sep)
		turn_container_wrapper.custom_minimum_size = Vector2(req_w, TURN_INITIAL_MIN_H)
		## 牌过多时扩展 offset 使容器变宽，保持居中
		turn_container_wrapper.offset_left = -req_w / 2.0
		turn_container_wrapper.offset_right = req_w / 2.0


func _refresh_hand_displays() -> void:
	var pc: int = clampi(battle_manager.player_count, 2, MAX_PLAYERS)
	for c in player_hand_display.get_children():
		c.queue_free()
	for pi in _player_hand_containers:
		var hbox: HBoxContainer = _player_hand_containers[pi] as HBoxContainer
		if hbox != null:
			for c in hbox.get_children():
				c.queue_free()
	var hands: Dictionary = card_manager.player_hands
	var local_idx: int = _get_local_player_index()
	for player_idx in range(pc):
		var count: int = hands.get(player_idx, []).size()
		var hand_scale: float = _compute_hand_scale(count, pc)
		if player_idx == local_idx:
			for card_res in hands.get(player_idx, []):
				var card_ui: Control = CARD_UI_SCENE.instantiate()
				player_hand_display.add_child(card_ui)
				card_ui.setup(card_res)
				card_ui.set_compact(true, hand_scale)
		else:
			var cards_hbox: HBoxContainer = _player_hand_containers.get(player_idx) as HBoxContainer
			if cards_hbox != null:
				for card_res in hands.get(player_idx, []):
					var card_ui: Control = CARD_UI_SCENE.instantiate()
					cards_hbox.add_child(card_ui)
					card_ui.setup(card_res)
					card_ui.set_meta("player_index", player_idx)
					card_ui.set_compact(true, hand_scale)
	for pi in _player_info_blocks:
		_update_player_info_block(pi)
	_update_scores(0, 0)


## 联机客户端专用：收到主机抽牌 RPC 后由 BattleManager 发出，确保回合牌堆实时渲染
func _on_client_draw_received(card: CardResource) -> void:
	if card == null:
		return
	_add_card_to_turn_display(card)


## 联机客户端专用：收到主机消费抽牌 RPC 后由 BattleManager 发出
func _on_client_consumed_draw_received(card: CardResource) -> void:
	if card == null:
		return
	_add_consumed_card_to_turn_display(card)


func _on_card_drawn(card: Resource) -> void:
	## 论策模式：始终本地显示；联机客户端：抽牌由 client_draw_received 处理
	if not battle_manager.get("is_lunce_mode") and network_manager != null and network_manager.has_method("is_multiplayer") and network_manager.call("is_multiplayer") and not network_manager.get("is_host"):
		return
	var card_res: CardResource = card as CardResource
	if card_res == null:
		return
	_add_card_to_turn_display(card_res)


func _add_card_to_turn_display(card_res: CardResource) -> void:
	_draw_animation_in_progress = true
	var card_ui: Control = CARD_UI_SCENE.instantiate()
	## 确保有最小尺寸，以便 HBoxContainer 正确分配空间
	card_ui.custom_minimum_size = Vector2(CARD_BASE_W, CARD_BASE_H)
	turn_container_display.add_child(card_ui)
	card_ui.setup(card_res)
	# 延迟一帧确保布局完成，再执行缩放+淡入动画（含卡牌专属特效）
	call_deferred("_play_card_draw_animation", card_ui, card_res)
	_append_log(_format_card_log(card_res))
	_update_scores(0, 0)  ## 回合牌堆变化，实时刷新分数


## 卡牌被 Mod 消费（他山之石）：在回合区显示卡牌，不播放特效，直接进入选择流程
func _on_card_drawn_consumed(card: Resource) -> void:
	## 论策模式：始终本地显示；联机客户端：消费抽牌由 client_consumed_draw_received 处理
	if not battle_manager.get("is_lunce_mode") and network_manager != null and network_manager.has_method("is_multiplayer") and network_manager.call("is_multiplayer") and not network_manager.get("is_host"):
		return
	var card_res: CardResource = card as CardResource
	if card_res == null:
		return
	_add_consumed_card_to_turn_display(card_res)


func _add_consumed_card_to_turn_display(card_res: CardResource) -> void:
	_draw_animation_in_progress = true
	_append_log(_format_card_log(card_res))
	_log_record("BattleTest", "_on_card_drawn_consumed", {"card": card_res.card_name})
	var card_ui: Control = CARD_UI_SCENE.instantiate()
	turn_container_display.add_child(card_ui)
	card_ui.setup(card_res)
	_apply_turn_card_scales()
	_draw_animation_in_progress = false
	_update_scores(0, 0)  ## 消费牌加入回合区，实时刷新分数
	battle_manager.draw_animation_finished()


func _play_card_draw_animation(card_ui: Control, card_res: CardResource = null) -> void:
	if not is_instance_valid(card_ui):
		_draw_animation_in_progress = false
		return
	## 抽牌时立即扩展回合区，避免牌过多时被裁剪
	_apply_turn_card_scales()
	battle_manager.set_effect_playing(true)
	## 仅动画 scale 与 modulate，避免 HBoxContainer 每帧覆盖子节点 position 导致卡牌不可见
	var sz: Vector2 = card_ui.size
	if sz.x <= 0 or sz.y <= 0:
		sz = Vector2(CARD_BASE_W, CARD_BASE_H)
	card_ui.pivot_offset = sz / 2
	card_ui.scale = Vector2(0.3, 0.3)
	card_ui.modulate.a = 0.0
	var pc: int = clampi(battle_manager.player_count, 2, MAX_PLAYERS)
	var turn_count: int = turn_container_display.get_child_count()
	var turn_scale: float = _compute_turn_scale(turn_count, pc)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card_ui, "scale", Vector2(turn_scale, turn_scale), 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_ui, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		_apply_turn_card_scales()
		var on_done: Callable = func() -> void:
			_draw_animation_in_progress = false
			battle_manager.set_effect_playing(false)
			battle_manager.draw_animation_finished()
			if _pending_hand_update >= 0:
				var idx: int = _pending_hand_update
				_pending_hand_update = -1
				_animate_cards_to_hand(idx)
		if is_instance_valid(card_ui) and card_res != null:
			_play_card_specific_effect(card_ui, card_res, on_done)
		else:
			on_done.call()
	)


func _animate_cards_to_hand(player_index: int) -> void:
	battle_manager.set_effect_playing(true)
	_refresh_hand_displays()
	var target_hand: HBoxContainer = get_target_container(player_index)
	var cards: Array = turn_container_display.get_children().duplicate()
	if cards.is_empty():
		battle_manager.set_effect_playing(false)
		_refresh_hand_displays()
		_restore_turn_container_initial_size()
		if battle_manager.has_method("collection_animation_finished"):
			battle_manager.collection_animation_finished()
		return
	var target_center: Vector2 = target_hand.global_position + target_hand.size / 2
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	for card_ui in cards:
		if not is_instance_valid(card_ui):
			continue
		var card_center: Vector2 = card_ui.size / 2
		var target_pos: Vector2 = target_center - card_center
		tween.tween_property(card_ui, "global_position", target_pos, 0.4).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		for c in cards:
			if is_instance_valid(c):
				c.queue_free()
		_refresh_hand_displays()
		_restore_turn_container_initial_size()
		battle_manager.set_effect_playing(false)
		if battle_manager.has_method("collection_animation_finished"):
			battle_manager.collection_animation_finished()
	)


func _on_contradiction(involved_cards: Array, protected_indices: Array, player_index: int) -> void:
	_contradiction_this_turn = true
	_contradiction_protected_indices = protected_indices.duplicate()
	_contradiction_player_index = player_index
	# 确保显示区有全部 involved 卡牌（抽牌矛盾时最后一张可能未加入）
	while turn_container_display.get_child_count() < involved_cards.size():
		var idx: int = turn_container_display.get_child_count()
		var card_res: CardResource = involved_cards[idx] as CardResource
		if card_res != null:
			var card_ui: Control = CARD_UI_SCENE.instantiate()
			turn_container_display.add_child(card_ui)
			card_ui.setup(card_res)
	_apply_turn_card_scales()
	for i: int in range(turn_container_display.get_child_count()):
		var child: Control = turn_container_display.get_child(i)
		if child.has_method("set_protected_style") and child.has_method("set_contradiction_style"):
			if protected_indices.has(i):
				child.set_protected_style(true)  # 被保护：蓝光
			else:
				child.set_contradiction_style(true)  # 未保护：红光
	if not protected_indices.is_empty():
		_append_log("[color=#5080e0][b]【矛盾触发】自圆其说保护前序牌收入手牌！[/b][/color]", -2)
	else:
		_append_log("[color=red][b]【矛盾触发】回合牌堆已清空！[/b][/color]", -2)


func _on_score_contradiction(_player_index: int, card: Resource, _scores_before: Dictionary) -> void:
	_contradiction_this_turn = true
	_contradiction_protected_indices = []
	_contradiction_player_index = battle_manager.current_player_index
	for child in turn_container_display.get_children():
		if child.has_method("set_contradiction_style"):
			child.set_contradiction_style(true)
	var conflict_card: CardResource = card as CardResource
	if conflict_card != null:
		var card_ui: Control = CARD_UI_SCENE.instantiate()
		turn_container_display.add_child(card_ui)
		card_ui.setup(conflict_card)
		card_ui.set_contradiction_style(true)
		_apply_turn_card_scales()
	_append_log("[color=red][b]【矛盾爆发！】总分超过上限，本回合分数归零！[/b][/color]", -2)


func _on_contradiction_started() -> void:
	if not _contradiction_protected_indices.is_empty():
		_play_light_shake()
	else:
		_play_shake()
	_play_flash()


func _on_contradiction_finished() -> void:
	_contradiction_this_turn = false
	_play_contradiction_fade_out()


func _on_mod_contradiction_effect_requested(cards: Array) -> void:
	battle_manager.set_effect_playing(true)
	_refresh_hand_displays()
	_play_shake()
	_play_flash()
	var mod_card_uis: Array = []
	for card_res in cards:
		if card_res is CardResource:
			var card_ui: Control = CARD_UI_SCENE.instantiate()
			turn_container_display.add_child(card_ui)
			card_ui.setup(card_res)
			card_ui.set_contradiction_style(true)
			mod_card_uis.append(card_ui)
	_apply_turn_card_scales()
	get_tree().create_timer(1.1).timeout.connect(func() -> void:
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		for card_ui in mod_card_uis:
			if is_instance_valid(card_ui):
				var col: Color = card_ui.modulate
				tween.tween_property(card_ui, "modulate", Color(col.r, col.g, col.b, 0.0), 0.38)
				tween.tween_property(card_ui, "scale", Vector2(FADE_OUT_SCALE, FADE_OUT_SCALE), 0.38)
		tween.tween_callback(func() -> void:
			for card_ui in mod_card_uis:
				if is_instance_valid(card_ui) and card_ui.is_inside_tree():
					card_ui.queue_free()
			_refresh_hand_displays()
			battle_manager.set_effect_playing(false)
		)
	)


## 察言观色：在回合区旁显示小标签，2.5 秒后自动淡出，不挡视野；同时写入日志
func _on_peek_card_display_requested(card: CardResource, show_to_local: bool) -> void:
	if not show_to_local or card == null:
		return
	_append_log("[color=#c0a0ff]察言观色：下一张 %s（分值 %d）[/color]" % [card.card_name, card.effect_value])
	var label: Label = Label.new()
	label.text = "下一张：%s（分值 %d）" % [card.card_name, card.effect_value]
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.2, 0.15, 0.3))
	label.add_theme_constant_override("outline_size", 4)
	shake_layer.add_child(label)
	call_deferred("_position_peek_label", label)
	var tween: Tween = create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(label.queue_free)


func _position_peek_label(label: Label) -> void:
	if not is_instance_valid(label) or not label.is_inside_tree():
		return
	# 放在回合区上方居中，确保在屏幕内
	var rect: Rect2 = turn_container_display.get_global_rect()
	var label_w: float = label.get_combined_minimum_size().x
	if label_w <= 0:
		label_w = 120
	label.global_position = Vector2(rect.position.x + max(0, (rect.size.x - label_w) / 2), rect.position.y - 28)


func _on_jiuniuyimao_selection_requested(drawer_index: int) -> void:
	var local_idx: int = 0
	if not battle_manager.get("is_lunce_mode"):
		var nm: Node = network_manager
		if nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer"):
			local_idx = nm.call("get_local_player_index")
	if drawer_index != local_idx:
		return
	_remove_chuqizhisheng_abandon_button()
	_add_jiuniuyimao_abandon_button()
	_highlight_opponent_cards_for_selection("jiuniuyimao", drawer_index)


func _on_chuqizhisheng_selection_requested(drawer_index: int) -> void:
	var local_idx: int = 0
	if not battle_manager.get("is_lunce_mode"):
		var nm: Node = network_manager
		if nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer"):
			local_idx = nm.call("get_local_player_index")
	if drawer_index != local_idx:
		return
	_remove_jiuniuyimao_abandon_button()
	_add_chuqizhisheng_abandon_button()
	_highlight_opponent_cards_for_selection("chuqizhisheng", drawer_index)


func _add_jiuniuyimao_abandon_button() -> void:
	if _jiuniuyimao_abandon_btn != null and is_instance_valid(_jiuniuyimao_abandon_btn):
		return
	var btn_row: Control = get_node_or_null(BTN_ROW_PATH)
	if btn_row == null:
		return
	_jiuniuyimao_abandon_btn = Button.new()
	_jiuniuyimao_abandon_btn.text = "放弃"
	_jiuniuyimao_abandon_btn.pressed.connect(_on_jiuniuyimao_abandon_pressed)
	btn_row.add_child(_jiuniuyimao_abandon_btn)


func _on_jiuniuyimao_abandon_pressed() -> void:
	_remove_jiuniuyimao_abandon_button()
	_cleanup_selection_highlights()
	battle_manager.request_jiuniuyimao_selection({"card_name": ""})


func _add_chuqizhisheng_abandon_button() -> void:
	if _chuqizhisheng_abandon_btn != null and is_instance_valid(_chuqizhisheng_abandon_btn):
		return
	var btn_row: Control = get_node_or_null(BTN_ROW_PATH)
	if btn_row == null:
		return
	_chuqizhisheng_abandon_btn = Button.new()
	_chuqizhisheng_abandon_btn.text = "放弃"
	_chuqizhisheng_abandon_btn.pressed.connect(_on_chuqizhisheng_abandon_pressed)
	btn_row.add_child(_chuqizhisheng_abandon_btn)


func _on_chuqizhisheng_abandon_pressed() -> void:
	_remove_chuqizhisheng_abandon_button()
	_cleanup_selection_highlights()
	battle_manager.request_chuqizhisheng_selection({"card_name": ""})


func _remove_chuqizhisheng_abandon_button() -> void:
	if _chuqizhisheng_abandon_btn != null and is_instance_valid(_chuqizhisheng_abandon_btn):
		_chuqizhisheng_abandon_btn.queue_free()
		_chuqizhisheng_abandon_btn = null


const SELECTION_HIGHLIGHT_MODULATE: Color = Color(0.9, 0.95, 1.0)
const SELECTION_HIGHLIGHT_CHUQIZHISHENG: Color = Color(1.0, 0.9, 0.9)
const SELECTION_HIGHLIGHT_TOULIANGHUANZHU: Color = Color(1.15, 1.1, 0.9)


func _on_toulianghuanzhu_selection_requested(drawer_index: int) -> void:
	var local_idx: int = 0
	if not battle_manager.get("is_lunce_mode"):
		var nm: Node = network_manager
		if nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer"):
			local_idx = nm.call("get_local_player_index")
	if drawer_index != local_idx:
		return
	_remove_jiuniuyimao_abandon_button()
	_remove_chuqizhisheng_abandon_button()
	_add_toulianghuanzhu_abandon_button()
	_highlight_turn_cards_for_toulianghuanzhu(drawer_index)


func _highlight_turn_cards_for_toulianghuanzhu(_drawer_index: int) -> void:
	_cleanup_selection_highlights()
	_selection_highlight_mode = "toulianghuanzhu"
	_selection_highlight_drawer_index = _drawer_index
	var children: Array = turn_container_display.get_children()
	var tc: Array = card_manager.turn_container
	if children.size() != tc.size() or children.size() < 2:
		return
	var last_idx: int = children.size() - 1
	for i in range(last_idx):
		var child: Control = children[i]
		if not is_instance_valid(child):
			continue
		child.modulate = SELECTION_HIGHLIGHT_TOULIANGHUANZHU
		var cb: Callable = _on_toulianghuanzhu_turn_card_clicked.bind(i)
		child.gui_input.connect(cb)
		_selection_highlight_uis.append({"ui": child, "callable": cb})


func _on_toulianghuanzhu_turn_card_clicked(event: InputEvent, turn_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_remove_toulianghuanzhu_abandon_button()
	_cleanup_selection_highlights()
	battle_manager.request_toulianghuanzhu_selection({"turn_index": turn_index})


func _add_toulianghuanzhu_abandon_button() -> void:
	if _toulianghuanzhu_abandon_btn != null and is_instance_valid(_toulianghuanzhu_abandon_btn):
		return
	var btn_row: Control = get_node_or_null(BTN_ROW_PATH)
	if btn_row == null:
		return
	_toulianghuanzhu_abandon_btn = Button.new()
	_toulianghuanzhu_abandon_btn.text = "放弃"
	_toulianghuanzhu_abandon_btn.pressed.connect(_on_toulianghuanzhu_abandon_pressed)
	btn_row.add_child(_toulianghuanzhu_abandon_btn)


func _on_toulianghuanzhu_abandon_pressed() -> void:
	_remove_toulianghuanzhu_abandon_button()
	_cleanup_selection_highlights()
	battle_manager.request_toulianghuanzhu_selection({"turn_index": -1})


func _remove_toulianghuanzhu_abandon_button() -> void:
	if _toulianghuanzhu_abandon_btn != null and is_instance_valid(_toulianghuanzhu_abandon_btn):
		_toulianghuanzhu_abandon_btn.queue_free()
		_toulianghuanzhu_abandon_btn = null


func _on_jianzaixianshang_play_effect_requested(card: CardResource, _player_index: int) -> void:
	if card == null:
		battle_manager.set_effect_playing(false)
		_draw_animation_in_progress = false
		if battle_manager.has_method("request_force_draw_after_effect"):
			battle_manager.request_force_draw_after_effect()
		return
	var card_ui: Control = null
	for child in turn_container_display.get_children():
		if child.get("card_data") == card:
			card_ui = child
			break
	if card_ui == null:
		battle_manager.set_effect_playing(false)
		_draw_animation_in_progress = false
		if battle_manager.has_method("request_force_draw_after_effect"):
			battle_manager.request_force_draw_after_effect()
		return
	_draw_animation_in_progress = true
	_play_card_specific_effect(card_ui, card, Callable())


func _on_toulianghuanzhu_swap_requested(idx_a: int, idx_b: int) -> void:
	_play_toulianghuanzhu_swap_animation(idx_a, idx_b, func() -> void:
		_draw_animation_in_progress = false
		battle_manager.set_effect_playing(false)
		if battle_manager.has_method("complete_toulianghuanzhu_swap"):
			battle_manager.complete_toulianghuanzhu_swap()
	)


func _play_toulianghuanzhu_swap_animation(idx_a: int, idx_b: int, on_complete: Callable) -> void:
	var children: Array = turn_container_display.get_children()
	if idx_a < 0 or idx_b < 0 or idx_a >= children.size() or idx_b >= children.size():
		if on_complete.is_valid():
			on_complete.call()
		return
	var ui_a: Control = children[idx_a]
	var ui_b: Control = children[idx_b]
	if not is_instance_valid(ui_a) or not is_instance_valid(ui_b):
		if on_complete.is_valid():
			on_complete.call()
		return
	battle_manager.set_effect_playing(true)
	_draw_animation_in_progress = true
	var tween: Tween = create_tween()
	tween.tween_property(ui_a, "modulate", SELECTION_HIGHLIGHT_TOULIANGHUANZHU, 0.1)
	tween.parallel().tween_property(ui_b, "modulate", SELECTION_HIGHLIGHT_TOULIANGHUANZHU, 0.1)
	tween.tween_callback(func() -> void:
		turn_container_display.move_child(ui_b, idx_a)
		turn_container_display.move_child(ui_a, idx_b)
		_apply_turn_card_scales()
		_restore_turn_container_initial_size()
	)
	tween.tween_property(ui_a, "modulate", Color.WHITE, 0.15)
	tween.parallel().tween_property(ui_b, "modulate", Color.WHITE, 0.15)
	tween.tween_callback(func() -> void:
		if on_complete.is_valid():
			on_complete.call()
	)


func _highlight_opponent_cards_for_selection(mode: String, drawer_index: int) -> void:
	_cleanup_selection_highlights()
	_selection_highlight_mode = mode
	_selection_highlight_drawer_index = drawer_index
	var pc: int = clampi(battle_manager.player_count, 2, MAX_PLAYERS)
	var highlight_color: Color = SELECTION_HIGHLIGHT_MODULATE if mode == "jiuniuyimao" else SELECTION_HIGHLIGHT_CHUQIZHISHENG
	for pi in range(pc):
		if pi == drawer_index:
			continue
		var hand_container: HBoxContainer = get_target_container(pi) as HBoxContainer
		if hand_container == null:
			continue
		for child in hand_container.get_children():
			var card_data = child.get("card_data")
			if card_data == null:
				continue
			child.modulate = highlight_color
			var cb: Callable = _on_selection_card_clicked.bind(card_data, pi)
			child.gui_input.connect(cb)
			_selection_highlight_uis.append({"ui": child, "callable": cb})


func _on_selection_card_clicked(event: InputEvent, card_res: CardResource, opponent_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var mode: String = _selection_highlight_mode
	_remove_jiuniuyimao_abandon_button()
	_remove_chuqizhisheng_abandon_button()
	_remove_toulianghuanzhu_abandon_button()
	_cleanup_selection_highlights()
	if mode == "jiuniuyimao":
		battle_manager.request_jiuniuyimao_selection({"card_name": card_res.card_name, "opponent_index": opponent_index})
	elif mode == "chuqizhisheng":
		battle_manager.request_chuqizhisheng_selection({"card_name": card_res.card_name, "opponent_index": opponent_index})


func _cleanup_selection_highlights() -> void:
	for h in _selection_highlight_uis:
		var ui = h["ui"]
		var cb: Callable = h["callable"]
		if is_instance_valid(ui):
			ui.modulate = Color.WHITE
			if ui.gui_input.is_connected(cb):
				ui.gui_input.disconnect(cb)
	_selection_highlight_uis.clear()
	_selection_highlight_mode = ""
	_selection_highlight_drawer_index = -1
	_remove_toulianghuanzhu_abandon_button()


func _remove_jiuniuyimao_abandon_button() -> void:
	if _jiuniuyimao_abandon_btn != null and is_instance_valid(_jiuniuyimao_abandon_btn):
		_jiuniuyimao_abandon_btn.queue_free()
		_jiuniuyimao_abandon_btn = null


func _on_jiuniuyimao_steal_animation_started(card: CardResource, opponent_index: int, _hand_index: int, drawer_index: int) -> void:
	## 不在此处 refresh，避免刷新导致卡牌引用失效；先查找，找不到再 refresh 重试
	var hand_container: HBoxContainer = get_target_container(opponent_index)
	if hand_container == null:
		_log_record("BattleTest", "jiuniuyimao_steal_anim_skip", {"reason": "hand_container_null", "opponent_index": opponent_index})
		_on_jiuniuyimao_steal_fallback(card, drawer_index)
		return
	## 按卡牌匹配查找（AI 对 AI 时 hand_index 可能因刷新时序不准）
	var card_ui: Control = null
	for child in hand_container.get_children():
		var cd: Variant = child.get("card_data")
		var match_card: bool = (cd == card) or (cd is CardResource and card is CardResource and cd.card_name == card.card_name and cd.effect_value == card.effect_value)
		if match_card:
			card_ui = child
			break
	if card_ui == null:
		## 首次未找到时 refresh 再试（AI 对 AI 时布局可能未就绪）
		_refresh_hand_displays()
		for child in hand_container.get_children():
			var cd: Variant = child.get("card_data")
			var match_card: bool = (cd == card) or (cd is CardResource and card is CardResource and cd.card_name == card.card_name and cd.effect_value == card.effect_value)
			if match_card:
				card_ui = child
				break
	if card_ui == null:
		_log_record("BattleTest", "jiuniuyimao_steal_anim_skip", {"reason": "card_not_found", "card_name": card.card_name, "opponent_index": opponent_index})
		_on_jiuniuyimao_steal_fallback(card, drawer_index)
		return
	_log_record("BattleTest", "jiuniuyimao_steal_anim_start", {"card": card.card_name, "opponent_index": opponent_index})
	battle_manager.set_effect_playing(true)
	var opp_name: String = _get_player_display_name(opponent_index)
	_append_log("[color=#ffa050]九牛一毛：从 %s 夺取了「%s」(分值 %d)[/color]" % [opp_name, card.card_name, card.effect_value], drawer_index)
	_jiuniuyimao_animating_steal = true
	var saved_global_pos: Vector2 = card_ui.global_position
	hand_container.remove_child(card_ui)
	shake_layer.add_child(card_ui)
	card_ui.global_position = saved_global_pos
	## 对手手牌在 viewport_content 内，移入 shake_layer 后失去父级缩放，需补偿以保持视觉大小一致（AI 拿 AI 时尤为明显）
	var vp_scale: float = 1.0
	if viewport_content != null and is_instance_valid(viewport_content) and viewport_content.is_ancestor_of(hand_container):
		vp_scale = viewport_content.scale.x
		card_ui.scale *= vp_scale
	# 阶段1：变色（橙色夺取光晕）
	var tween: Tween = create_tween()
	tween.tween_property(card_ui, "modulate", Color(1.25, 0.95, 0.75), 0.25).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		if not is_instance_valid(card_ui):
			_jiuniuyimao_animating_steal = false
			battle_manager.set_effect_playing(false)
			return
		var pc: int = clampi(battle_manager.player_count, 2, MAX_PLAYERS)
		var turn_count: int = turn_container_display.get_child_count() + 1
		var turn_scale: float = _compute_turn_scale(turn_count, pc)
		var turn_scale_in_layer: float = turn_scale * vp_scale
		var turn_center: Vector2 = turn_container_display.global_position + turn_container_display.size / 2
		## 以卡牌中心为缩放原点，飞入时平滑过渡到回合区缩放；调整位置避免 pivot 变更导致视觉跳动
		var hand_scale: float = card_ui.scale.x
		card_ui.pivot_offset = card_ui.size / 2
		card_ui.global_position = saved_global_pos + card_ui.size / 2 * (hand_scale - 1.0)
		var target_pos: Vector2 = turn_center - card_ui.size / 2
		var fly_tween: Tween = create_tween()
		fly_tween.tween_property(card_ui, "global_position", target_pos, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		fly_tween.parallel().tween_property(card_ui, "scale", Vector2(turn_scale_in_layer, turn_scale_in_layer), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		fly_tween.parallel().tween_property(card_ui, "modulate", Color.WHITE, 0.35)
		fly_tween.tween_callback(func() -> void:
			if is_instance_valid(card_ui):
				shake_layer.remove_child(card_ui)
				# 见好就收等强制结束牌：settle 由 complete_jiuniuyimao_stolen_stop_settle 执行，回合区将清空
				if card_manager.turn_container.is_empty():
					card_ui.queue_free()
				else:
					card_ui.pivot_offset = Vector2.ZERO
					turn_container_display.add_child(card_ui)
					_apply_turn_card_scales()
			## 飞牌完成后刷新对手手牌显示，确保偷牌后界面正确
			_refresh_hand_displays()
			_update_scores(0, 0)
			for pi in _player_info_blocks:
				_update_player_info_block(pi)
			_jiuniuyimao_animating_steal = false
			battle_manager.set_effect_playing(false)
			_append_log("[color=#ffa050]夺取的「%s」(分值 %d) 加入回合区[/color]" % [card.card_name, card.effect_value], drawer_index)
			# 阻塞：出奇制胜/九牛一毛，飞牌动画完成后再触发被夺取牌效果
			if battle_manager.has_method("complete_jiuniuyimao_steal_animation"):
				battle_manager.complete_jiuniuyimao_steal_animation()
			# 阻塞：见好就收等强制结束牌，飞牌动画完成后再 settle
			if card.force_ends_turn and battle_manager.has_method("complete_jiuniuyimao_stolen_stop_settle"):
				battle_manager.complete_jiuniuyimao_stolen_stop_settle()
		)
	)


func _on_jiuniuyimao_steal_fallback(card: CardResource, drawer_index: int) -> void:
	## 飞牌动画无法播放时：直接在回合区显示卡牌并继续流程
	var card_ui: Control = CARD_UI_SCENE.instantiate()
	turn_container_display.add_child(card_ui)
	card_ui.setup(card)
	_apply_turn_card_scales()
	var drawer_name: String = _get_player_display_name_for_log(drawer_index)
	_append_log_with_actor(drawer_name, "[color=#ffa050]九牛一毛：夺取的「%s」(分值 %d) 加入回合区[/color]" % [card.card_name, card.effect_value])
	# 出奇制胜/九牛一毛：无动画时也需触发被夺取牌效果
	if battle_manager.has_method("complete_jiuniuyimao_steal_animation"):
		battle_manager.complete_jiuniuyimao_steal_animation()
	if card.force_ends_turn and battle_manager.has_method("complete_jiuniuyimao_stolen_stop_settle"):
		_log_record("BattleTest", "jiuniuyimao_stolen_stop_no_anim", {"card": card.card_name})
		battle_manager.complete_jiuniuyimao_stolen_stop_settle()


func _on_jiuniuyimao_card_added_to_turn(card: CardResource) -> void:
	if _jiuniuyimao_animating_steal:
		return
	## 联机客户端或 fallback：先刷新对手手牌，再添加卡牌到回合区
	_refresh_hand_displays()
	var card_ui: Control = CARD_UI_SCENE.instantiate()
	turn_container_display.add_child(card_ui)
	card_ui.setup(card)
	_apply_turn_card_scales()
	_update_scores(0, 0)
	for pi in _player_info_blocks:
		_update_player_info_block(pi)
	_append_log("[color=#ffa050]九牛一毛：夺取的「%s」(分值 %d) 加入回合区[/color]" % [card.card_name, card.effect_value])
	# 飞牌动画被跳过时（如手牌索引不匹配）：见好就收等强制结束牌仍需触发 settle
	if card.force_ends_turn and battle_manager.has_method("complete_jiuniuyimao_stolen_stop_settle"):
		_log_record("BattleTest", "jiuniuyimao_stolen_stop_no_anim", {"card": card.card_name})
		battle_manager.complete_jiuniuyimao_stolen_stop_settle()


## 抽牌滑入后：统一经注册表调用各卡牌 effect(..., effect_phase=draw_animation)
func _play_card_specific_effect(card_ui: Control, card_res: CardResource, on_complete: Callable = Callable()) -> void:
	if not is_instance_valid(card_ui) or card_res == null:
		if on_complete.is_valid():
			on_complete.call()
		return
	var bm: Node = battle_manager
	var pi: int = int(bm.get("current_player_index")) if bm != null else 0
	var ctx: Dictionary = bm.get_effect_context_base(pi) if bm != null and bm.has_method("get_effect_context_base") else {}
	ctx["effect_phase"] = "draw_animation"
	ctx["card_ui"] = card_ui
	ctx["effect_host"] = self
	ctx["on_draw_animation_complete"] = on_complete
	ctx["jianzaixianshang_after_visual"] = Callable(self, "_finish_jianzaixianshang_draw_animation_effect")
	var registry_script: GDScript = load("res://scripts/cards/card_registry.gd") as GDScript
	if registry_script != null:
		var registry: RefCounted = registry_script.new()
		if registry != null and registry.has_method("trigger_card_effect"):
			if registry.call("trigger_card_effect", card_res, pi, ctx):
				return
	if on_complete.is_valid():
		on_complete.call()


func _finish_jianzaixianshang_draw_animation_effect() -> void:
	_draw_animation_in_progress = false
	battle_manager.set_effect_playing(false)
	if battle_manager.has_method("request_force_draw_after_effect"):
		battle_manager.request_force_draw_after_effect()


func _on_mod_soft_remove_effect_requested(cards: Array) -> void:
	var mod_card_uis: Array = []
	var to_remove: Array = []  ## [{card, player_index}, ...]，特效结束后移除
	for item in cards:
		var card_res: Variant = item.get("card") if item is Dictionary else item
		var pi: int = item.get("player_index", 0) if item is Dictionary else 0
		if card_res == null:
			continue
		var hand_container: HBoxContainer = get_target_container(pi)
		var found: bool = false
		for child in hand_container.get_children():
			if child.get("card_data") == card_res:
				child.pivot_offset = child.size / 2
				mod_card_uis.append(child)
				to_remove.append({"card": card_res, "player_index": pi})
				found = true
				break
		if not found:
			## AI 自动选择等：UI 可能未刷新，仍从逻辑层移除卡牌，避免卡住
			to_remove.append({"card": card_res, "player_index": pi})
	if to_remove.is_empty():
		return
	if mod_card_uis.is_empty():
		## 未找到任何卡牌 UI（AI 自动选择等），直接移除并刷新，然后恢复流程
		for r in to_remove:
			var c: Variant = r.get("card")
			var pi: int = r.get("player_index", 0)
			if c is CardResource:
				card_manager.remove_card_from_hand(pi, c)
		_refresh_hand_displays()
		if battle_manager.get("mod_pause_settlement"):
			battle_manager.mod_resume_without_settle()
		return
	for r in to_remove:
		var nv: Dictionary = _get_card_name_and_value(r.get("card"))
		_append_log("[color=#a0c0ff]他山之石：移除了 %s 的「%s」(分值 %d)[/color]" % [_get_player_display_name(r.get("player_index", 0)), nv.name, nv.value])
	var uis_copy: Array = mod_card_uis.duplicate()
	var remove_list: Array = to_remove.duplicate()
	battle_manager.set_effect_playing(true)
	## 阶段1：卡牌变亮（0.7s），明显发光
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	for card_ui in uis_copy:
		if is_instance_valid(card_ui):
			tween.tween_property(card_ui, "modulate", Color(1.5, 1.55, 1.5), 0.7).set_trans(Tween.TRANS_SINE)
			tween.tween_property(card_ui, "scale", Vector2(1.12, 1.12), 0.7).set_trans(Tween.TRANS_SINE)
	## 阶段2：保持变亮 0.5s，让玩家看清后触发震动
	var hold_tween: Tween = tween.chain()
	hold_tween.tween_interval(0.5)
	hold_tween.tween_callback(func() -> void:
		_play_light_shake()
	)
	## 阶段3：卡牌消失（0.7s），与震动同步
	var fade_tween: Tween = hold_tween.chain()
	fade_tween.set_parallel(true)
	for card_ui in uis_copy:
		if is_instance_valid(card_ui):
			fade_tween.tween_property(card_ui, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.7).set_trans(Tween.TRANS_SINE)
			fade_tween.tween_property(card_ui, "scale", Vector2(FADE_OUT_SCALE, FADE_OUT_SCALE), 0.7).set_trans(Tween.TRANS_SINE)
	fade_tween.tween_callback(func() -> void:
		for r in remove_list:
			card_manager.remove_card_from_hand(r.player_index, r.card)
		for card_ui in uis_copy:
			if is_instance_valid(card_ui) and card_ui.is_inside_tree():
				card_ui.queue_free()
		_refresh_hand_displays()
		battle_manager.set_effect_playing(false)
		if battle_manager.get("mod_pause_settlement"):
			battle_manager.mod_resume_without_settle()
	)


## 出奇制胜：被选卡牌变红发光然后消失，特效结束后弃入弃牌堆
func _on_chuqizhisheng_discard_effect_requested(cards: Array) -> void:
	var mod_card_uis: Array = []
	var to_remove: Array = []
	for item in cards:
		var card_res: Variant = item.get("card") if item is Dictionary else item
		var pi: int = item.get("player_index", 0) if item is Dictionary else 0
		if card_res == null:
			continue
		var hand_container: HBoxContainer = get_target_container(pi)
		for child in hand_container.get_children():
			var cd: Variant = child.get("card_data")
			var match_card: bool = (cd == card_res) or (cd is CardResource and card_res is CardResource and cd.card_name == card_res.card_name and cd.effect_value == card_res.effect_value)
			if match_card:
				child.pivot_offset = child.size / 2
				mod_card_uis.append(child)
				to_remove.append({"card": card_res, "player_index": pi})
				break
	if mod_card_uis.is_empty():
		battle_manager.set_effect_playing(false)
		battle_manager.mod_resume_without_settle()
		return
	for r in to_remove:
		var nv: Dictionary = _get_card_name_and_value(r.get("card"))
		_append_log("[color=#e05050]出奇制胜：弃掉了 %s 的「%s」(分值 %d)[/color]" % [_get_player_display_name(r.get("player_index", 0)), nv.name, nv.value])
	var uis_copy: Array = mod_card_uis.duplicate()
	var remove_list: Array = to_remove.duplicate()
	battle_manager.set_effect_playing(true)
	## 阶段1：卡牌变红发光（0.6s）
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	for card_ui in uis_copy:
		if is_instance_valid(card_ui):
			tween.tween_property(card_ui, "modulate", Color(1.5, 0.5, 0.5), 0.6).set_trans(Tween.TRANS_SINE)
			tween.tween_property(card_ui, "scale", Vector2(1.12, 1.12), 0.6).set_trans(Tween.TRANS_SINE)
	## 阶段2：保持 0.4s 后消失
	var hold_tween: Tween = tween.chain()
	hold_tween.tween_interval(0.4)
	var fade_tween: Tween = hold_tween.chain()
	fade_tween.set_parallel(true)
	for card_ui in uis_copy:
		if is_instance_valid(card_ui):
			fade_tween.tween_property(card_ui, "modulate", Color(1.0, 0.3, 0.3, 0.0), 0.5).set_trans(Tween.TRANS_SINE)
			fade_tween.tween_property(card_ui, "scale", Vector2(FADE_OUT_SCALE, FADE_OUT_SCALE), 0.5).set_trans(Tween.TRANS_SINE)
	fade_tween.tween_callback(func() -> void:
		for r in remove_list:
			var nv: Dictionary = _get_card_name_and_value(r.get("card"))
			card_manager.remove_card_from_hand_by_data(r.get("player_index", 0), nv.name, nv.value)
		for card_ui in uis_copy:
			if is_instance_valid(card_ui) and card_ui.is_inside_tree():
				card_ui.queue_free()
		_refresh_hand_displays()
		battle_manager.set_effect_playing(false)
		battle_manager.mod_resume_without_settle()
	)


func _play_contradiction_fade_out() -> void:
	var cards: Array = turn_container_display.get_children().duplicate()
	var protected_uis: Array = []
	var unprotected_uis: Array = []
	for i: int in range(cards.size()):
		var card_ui: Control = cards[i]
		if not is_instance_valid(card_ui):
			continue
		if _contradiction_protected_indices.has(i):
			protected_uis.append(card_ui)
		else:
			unprotected_uis.append(card_ui)
	var finish_contradiction: Callable = func() -> void:
		for c in turn_container_display.get_children():
			c.queue_free()
		_refresh_hand_displays()
		_restore_turn_container_initial_size()
		if battle_manager.has_method("contradiction_effect_complete"):
			battle_manager.contradiction_effect_complete()
	if protected_uis.is_empty() and unprotected_uis.is_empty():
		finish_contradiction.call()
		_append_log("[color=orange]>>> 回合强制结束 <<<[/color]", -2)
		return
	var target_hand: HBoxContainer = get_target_container(_contradiction_player_index)
	var target_center: Vector2 = target_hand.global_position + target_hand.size / 2
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	# 保护卡牌：飞入手牌
	for card_ui in protected_uis:
		var card_center: Vector2 = card_ui.size / 2
		var target_pos: Vector2 = target_center - card_center
		tween.tween_property(card_ui, "global_position", target_pos, 0.4).set_ease(Tween.EASE_IN)
	# 未保护卡牌：淡出
	for card_ui in unprotected_uis:
		var c: Color = card_ui.modulate
		tween.tween_property(card_ui, "modulate", Color(c.r, c.g, c.b, 0.0), 0.38)
		tween.tween_property(card_ui, "scale", Vector2(FADE_OUT_SCALE, FADE_OUT_SCALE), 0.38)
	tween.tween_callback(finish_contradiction)
	_append_log("[color=orange]>>> 回合强制结束 <<<[/color]", -2)


func _on_force_end_turn() -> void:
	if not _contradiction_this_turn:
		_append_log("[color=orange]>>> 回合强制结束 <<<[/color]", -2)


func _play_shake() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var root: Control = shake_root
	var orig_pos: Vector2 = root.position
	_shake_tween = create_tween()
	var duration: float = 1.1
	var elapsed: float = 0.0
	while elapsed < duration:
		var amp: float = 8.0 * (1.0 - elapsed / duration)
		_shake_tween.tween_property(root, "position", orig_pos + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)), 0.03)
		_shake_tween.tween_property(root, "position", orig_pos, 0.03)
		elapsed += 0.06
	_shake_tween.tween_property(root, "position", orig_pos, 0.0)


## 轻微震动（他山之石等 Mod 效果用），振幅小于矛盾特效
func _play_light_shake() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var root: Control = shake_root
	var orig_pos: Vector2 = root.position
	_shake_tween = create_tween()
	var duration: float = 0.8
	var elapsed: float = 0.0
	while elapsed < duration:
		var amp: float = 3.5 * (1.0 - elapsed / duration)
		_shake_tween.tween_property(root, "position", orig_pos + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)), 0.03)
		_shake_tween.tween_property(root, "position", orig_pos, 0.03)
		elapsed += 0.06
	_shake_tween.tween_property(root, "position", orig_pos, 0.0)


func _play_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	flash_rect.color = Color(1, 0, 0, 0.4)
	_flash_tween.tween_property(flash_rect, "color", Color(1, 0, 0, 0), 1.1)


func _on_setting_pressed() -> void:
	_populate_battle_setting_buttons()
	# 延迟一帧确保 SettingPanel 已在场景树中，避免 !is_inside_tree() 错误
	call_deferred("_show_setting_panel")


func _on_setting_popup_hide() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.gui_release_focus()


func _show_setting_panel() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(setting_panel) and setting_panel.is_inside_tree():
		setting_panel.size = Vector2i(240, 200)
		setting_panel.popup_centered()


func _populate_battle_setting_buttons() -> void:
	var to_clear: Array = setting_button_container.get_children()
	for c in to_clear:
		if is_instance_valid(c):
			c.free()
	var style: StyleBoxFlat = _make_setting_btn_style()
	var mod_btn: Button = _create_setting_btn("模组扩展", style)
	mod_btn.pressed.connect(_on_mod_pressed)
	setting_button_container.add_child(mod_btn)
	var restart_btn_inner: Button = _create_setting_btn("重新开始", style)
	restart_btn_inner.pressed.connect(_on_setting_restart_pressed)
	setting_button_container.add_child(restart_btn_inner)
	var nm: Node = network_manager
	if nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer"):
		restart_btn_inner.disabled = not multiplayer.is_server()
	var setting_back_btn: Button = _create_setting_btn("返回", style)
	setting_back_btn.pressed.connect(_on_back_to_menu_pressed)
	setting_button_container.add_child(setting_back_btn)


func _create_setting_btn(text: String, style: StyleBoxFlat) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.2, 0.2, 0.2, 1))
	btn.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.6, 1))
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.add_theme_stylebox_override("pressed", style)
	return btn


func _make_setting_btn_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.941, 0.941, 0.941, 1)
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = Color(0, 0, 0, 1)
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left = 4
	s.content_margin_left = 12.0
	s.content_margin_top = 8.0
	s.content_margin_right = 12.0
	s.content_margin_bottom = 8.0
	return s


func _on_setting_restart_pressed() -> void:
	setting_panel.hide()
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.dialog_text = "确定要重新开始吗？当前进度将丢失。"
	dialog.title = "重新开始"
	add_child(dialog)
	# 延迟一帧确保 dialog 已加入场景树
	call_deferred("_show_restart_confirm", dialog)


func _show_restart_confirm(dialog: ConfirmationDialog) -> void:
	if not is_inside_tree():
		if is_instance_valid(dialog):
			dialog.queue_free()
		return
	if is_instance_valid(dialog) and dialog.is_inside_tree():
		dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		if is_instance_valid(dialog):
			dialog.queue_free()
		_do_restart()
	)
	dialog.canceled.connect(func() -> void:
		if is_instance_valid(dialog):
			dialog.queue_free()
	)


func _on_opponent_requested_exit() -> void:
	if _opponent_exit_popup_shown:
		return
	_opponent_exit_popup_shown = true
	_show_opponent_exit_popup()


func _on_peer_disconnected(_peer_id: int) -> void:
	## 2 人对战下任意 peer 断开即对手退出
	if _opponent_exit_popup_shown:
		return
	_opponent_exit_popup_shown = true
	_show_opponent_exit_popup()


func _show_opponent_exit_popup() -> void:
	setting_panel.hide()
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "对手已退出"
	dialog.dialog_text = "对手已退出游戏，点击确定返回主菜单。"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		if is_instance_valid(dialog):
			dialog.queue_free()
		var nm: Node = network_manager
		if nm != null and nm.has_method("force_exit_to_main"):
			nm.call("force_exit_to_main")
	)
	dialog.close_requested.connect(func() -> void:
		if is_instance_valid(dialog):
			dialog.queue_free()
		var nm: Node = network_manager
		if nm != null and nm.has_method("force_exit_to_main"):
			nm.call("force_exit_to_main")
	)
	call_deferred("_popup_opponent_exit_deferred", dialog)


func _popup_opponent_exit_deferred(dialog: AcceptDialog) -> void:
	if not is_instance_valid(dialog) or not is_inside_tree():
		return
	dialog.popup_centered()


func _on_back_to_menu_pressed() -> void:
	setting_panel.hide()
	_go_back_to_mode_select()


func _on_back_to_mode_select_pressed() -> void:
	_manual_reset_ui()
	_go_back_to_mode_select()


func _go_back_to_mode_select() -> void:
	var nm: Node = network_manager
	if nm != null and nm.has_method("is_multiplayer") and nm.call("is_multiplayer"):
		nm.call("request_exit_game")
	else:
		card_manager.reset_for_new_game()
		battle_manager.reset_to_start()
		battle_manager.set("return_to_mode_select", true)
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


func _on_mod_pressed() -> void:
	setting_panel.hide()
	_populate_mod_panel()
	mod_detail_panel.visible = true
	mod_detail_panel.process_mode = Node.PROCESS_MODE_INHERIT
	mod_detail_panel.modulate.a = 0.0
	if is_inside_tree() and mod_detail_panel.is_inside_tree():
		var tween: Tween = create_tween()
		tween.tween_property(mod_detail_panel, "modulate:a", 1.0, 0.2)
	else:
		mod_detail_panel.modulate.a = 1.0


func _on_mod_close_pressed() -> void:
	mod_detail_panel.visible = false
	mod_detail_panel.process_mode = Node.PROCESS_MODE_DISABLED
	call_deferred("_show_setting_panel")


func _on_gen_template_pressed() -> void:
	var path: String = mod_manager.generate_example_mod_template()
	if path != "":
		mod_manager.refresh_mod_details()
		_populate_mod_panel()
		mod_detail_label.text = "模板已生成！\n路径已输出到控制台：\n%s" % path
		_append_log("[color=green]模组模板已生成：%s[/color]" % path, -2)


func _on_mod_refresh_pressed() -> void:
	mod_manager.reload_all_mods()
	_populate_mod_panel()
	mod_detail_label.text = "已刷新模组列表"


func _on_browse_dir_pressed() -> void:
	var abs_path: String = mod_manager.get_mod_storage_path_absolute()
	if OS.has_feature("android"):
		_show_path_popup(abs_path)
	else:
		OS.shell_open(abs_path)


func _show_path_popup(path: String) -> void:
	var popup: AcceptDialog = AcceptDialog.new()
	popup.title = "模组存放路径"
	popup.dialog_text = "请将模组文件夹放入以下目录：\n\n%s\n\n可使用文件管理器复制此路径查找。" % path
	add_child(popup)
	popup.confirmed.connect(popup.queue_free)
	call_deferred("_show_path_popup_deferred", popup)


func _show_path_popup_deferred(popup: AcceptDialog) -> void:
	if not is_inside_tree():
		if is_instance_valid(popup):
			popup.queue_free()
		return
	if is_instance_valid(popup) and popup.is_inside_tree():
		popup.popup_centered()


func _populate_mod_panel() -> void:
	mod_restart_hint.visible = false
	for c in mod_list.get_children():
		c.queue_free()
	var details: Array = mod_manager.mod_details
	if details.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "当前未加载任何扩展内容"
		empty_label.add_theme_color_override("font_color", Color(0.294, 0.294, 0.29, 1))
		empty_label.add_theme_font_size_override("font_size", 14)
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mod_list.add_child(empty_label)
		mod_detail_label.text = "将模组文件夹放入模组存放目录即可加载\n点击「浏览目录」查看路径"
	else:
		for i: int in range(details.size()):
			var info: Dictionary = details[i]
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var cb: CheckBox = CheckBox.new()
			cb.button_pressed = info.get("is_enabled", true)
			cb.add_theme_color_override("font_color", Color(0, 0, 0, 1))
			var idx: int = i
			cb.toggled.connect(_on_mod_enabled_toggled.bind(idx))
			row.add_child(cb)
			var btn: Button = Button.new()
			btn.text = "[%s] v%s - %s" % [info.get("name", "?"), info.get("version", "?"), info.get("author", "?")]
			btn.add_theme_color_override("font_color", Color(0.294, 0.294, 0.29, 1))
			btn.add_theme_color_override("font_hover_color", Color(0.2, 0.2, 0.2, 1))
			var mod_style: StyleBoxFlat = UIHelper.make_mod_btn_style()
			btn.add_theme_stylebox_override("normal", mod_style)
			btn.add_theme_stylebox_override("hover", mod_style)
			btn.add_theme_stylebox_override("pressed", mod_style)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_on_mod_item_pressed.bind(idx))
			row.add_child(btn)
			mod_list.add_child(row)
		mod_detail_label.text = "点击上方条目查看详情"
	# 覆盖资源
	var overrides: Array = mod_manager.overridden_resources
	if overrides.is_empty():
		mod_override_label.text = "覆盖资源：无"
	else:
		var paths: Array[String] = []
		for p: String in overrides:
			paths.append(p.get_file())
		mod_override_label.text = "覆盖资源：%s" % ", ".join(paths)


func _on_mod_enabled_toggled(enabled: bool, index: int) -> void:
	var details: Array = mod_manager.mod_details
	if index < 0 or index >= details.size():
		return
	var info: Dictionary = details[index]
	var mod_id: String = info.get("id", "")
	mod_manager.set_mod_enabled(mod_id, enabled)
	mod_manager.save_mod_config()
	mod_restart_hint.visible = true


func _on_mod_item_pressed(index: int) -> void:
	var details: Array = mod_manager.mod_details
	if index < 0 or index >= details.size():
		return
	var info: Dictionary = details[index]
	var desc: String = info.get("description", "")
	if desc.is_empty():
		desc = "（无说明）"
	mod_detail_label.text = desc


func _format_card_log(card: CardResource) -> String:
	# Mod 卡牌特殊格式
	if card.card_name == "他山之石":
		return "[color=#a0c0ff]抽到「他山之石」[/color]"
	# 核心卡牌从注册表获取（每张独立文件，含察言观色）
	var registry_script: Script = load("res://scripts/cards/card_registry.gd") as Script
	if registry_script != null:
		var registry: Variant = registry_script.new()
		if registry != null and registry.has_method("get_log_format_for_card"):
			var fmt: String = registry.call("get_log_format_for_card", card)
			if not fmt.is_empty():
				return fmt
	return "抽到「%s」(分值 %d)" % [card.card_name, card.effect_value]


func _get_player_display_name_for_log(pi: int) -> String:
	return _get_player_display_name(pi)


func _append_log(text: String, actor_index: int = -1) -> void:
	## actor_index: -2=无操作者(系统), -1=当前回合玩家, >=0=指定玩家
	var prefix: String = ""
	if actor_index >= 0:
		prefix = "[%s] " % _get_player_display_name_for_log(actor_index)
	elif actor_index == -1 and battle_manager != null:
		prefix = "[%s] " % _get_player_display_name_for_log(battle_manager.current_player_index)
	log_label.append_text("\n" + prefix + text)


func _append_log_with_actor(actor_name: String, text: String) -> void:
	log_label.append_text("\n[%s] %s" % [actor_name, text])


func _on_game_ended(result_text: String, player_score: int, opponent_score: int, all_scores: Dictionary = {}) -> void:
	_log_record("BattleTest", "_on_game_ended", {"result": result_text, "score": "%d:%d" % [player_score, opponent_score], "all": all_scores})
	_log_flush()
	result_title_label.text = result_text
	var is_mp: bool = _is_network_multiplayer_battle()
	var pc: int = clampi(battle_manager.player_count, 2, 8)
	var local_idx: int = _get_local_player_index()
	result_score_label.visible = true
	## 局域网联机任意人数，或 3 人及以上（论策/演兵单机）：只显示本地分数，不显示「15:35」式双方比
	if is_mp or pc > 2:
		var my_score: int
		if not all_scores.is_empty():
			my_score = int(all_scores.get(local_idx, 0))
		else:
			my_score = player_score if local_idx == 0 else opponent_score
		result_score_label.text = "你的分数：%d" % my_score
	else:
		result_score_label.text = "最终比分 %d : %d" % [player_score, opponent_score]
	result_panel.visible = true
	result_panel.process_mode = Node.PROCESS_MODE_INHERIT
	result_panel.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(result_panel, "modulate:a", 1.0, 0.2)


func _on_restart_pressed() -> void:
	_do_restart()


func _do_restart() -> void:
	_log_record("BattleTest", "_do_restart", {})
	_log_flush()
	_manual_reset_ui()
	var nm: Node = network_manager
	if nm != null and nm.has_method("request_restart_game"):
		nm.call("request_restart_game")
	else:
		card_manager.reset_for_new_game()
		battle_manager.reset_to_start()
		get_tree().reload_current_scene()


func _manual_reset_ui() -> void:
	result_panel.visible = false
	result_panel.process_mode = Node.PROCESS_MODE_DISABLED
	result_score_label.visible = true
	mod_detail_panel.visible = false
	mod_detail_panel.process_mode = Node.PROCESS_MODE_DISABLED
	for c in turn_container_display.get_children():
		c.queue_free()
	_ensure_hand_layout()
	_refresh_hand_displays()
	_restore_turn_container_initial_size()
	_on_deck_count_changed(card_manager.global_deck.size())
	_update_scores(0, 0)
	_update_ui_state()
