## 卡牌注册表：提供所有核心卡牌数据供 CardManager 构建牌堆
## 每张卡牌有独立脚本，通过 get_registration_data() 提供注册数据
## 使用静态缓存避免重复加载脚本
extends RefCounted

const CARD_SCRIPTS: Array[String] = [
	"res://scripts/cards/card_null.gd",
	"res://scripts/cards/card_stop.gd",
	"res://scripts/cards/card_double.gd",
	"res://scripts/cards/card_chayanguanse.gd",
	"res://scripts/cards/card_jiuniuyimao.gd",
	"res://scripts/cards/card_chuqizhisheng.gd",
	"res://scripts/cards/card_ziyuanqishuo.gd",
	"res://scripts/cards/card_jianzaixianshang.gd",
	"res://scripts/cards/card_toulianghuanzhu.gd",
]

## 缓存：核心卡牌注册数据（首次调用后填充）
static var _cached_core_cards: Array[Dictionary] = []
## 缓存：ability_id/name -> 卡牌实例（用于 get_log_format），首次调用后填充
static var _cached_card_instances: Array[Variant] = []
static var _cache_initialized: bool = false


func _ensure_cache() -> void:
	if _cache_initialized:
		return
	for path: String in CARD_SCRIPTS:
		var script: Script = load(path) as Script
		if script == null:
			push_warning("[CardRegistry] 无法加载卡牌脚本: %s" % path)
			continue
		var card_class: Variant = script.new()
		if card_class == null or not card_class.has_method("get_registration_data"):
			push_warning("[CardRegistry] 卡牌脚本无 get_registration_data: %s" % path)
			continue
		var data: Dictionary = card_class.call("get_registration_data")
		if not data.is_empty():
			_cached_core_cards.append(data)
			_cached_card_instances.append(card_class)
	_cache_initialized = true


## 返回所有核心卡牌的注册数据数组，供 CardManager._build_deck 使用
func get_all_core_cards() -> Array[Dictionary]:
	_ensure_cache()
	return _cached_core_cards.duplicate()


## 触发卡牌 effect()。ctx 通常含 battle_manager, card_manager, is_stolen, need_immediate_emit, local_player_index
## effect_phase: 缺省或 "logic" 为逻辑效果；"draw_animation" 为抽牌滑入后的仅 UI 特效（需 card_ui、effect_host、on_draw_animation_complete）
## 若核心卡牌处理了效果则返回 true，否则返回 false（交由 Mod 钩子处理）
func trigger_card_effect(card: CardResource, player_index: int, ctx: Dictionary) -> bool:
	if card == null or card.ability_id.is_empty():
		return false
	_ensure_cache()
	for i: int in range(_cached_core_cards.size()):
		var data: Dictionary = _cached_core_cards[i]
		var aid: String = str(data.get("ability_id", ""))
		if aid != card.ability_id:
			continue
		var card_class: Variant = _cached_card_instances[i]
		if card_class == null or not card_class.has_method("effect"):
			return false
		card_class.call("effect", card, player_index, ctx)
		return true
	return false


## 根据卡牌返回日志格式字符串，供 battle_test._format_card_log 使用
func get_log_format_for_card(card: CardResource) -> String:
	if card == null:
		return ""
	_ensure_cache()
	for i: int in range(_cached_core_cards.size()):
		var data: Dictionary = _cached_core_cards[i]
		var aid: String = str(data.get("ability_id", ""))
		var name_str: String = str(data.get("name", ""))
		if aid == card.ability_id or name_str == card.card_name:
			var card_class: Variant = _cached_card_instances[i]
			if card_class != null and card_class.has_method("get_log_format"):
				return card_class.call("get_log_format", card)
			break
	return ""
