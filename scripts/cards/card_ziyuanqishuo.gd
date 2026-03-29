## 自圆其说：矛盾时保护排在它及它之前的卡牌不被弃掉并收入手牌
## 当因抽到第二张自圆其说触发矛盾时，只保护到第一张自圆其说的位置
extends RefCounted

const CARD_NAME: String = "自圆其说"
const ABILITY_ID: String = "ziyuanqishuo"


func get_registration_data() -> Dictionary:
	return {
		"name": CARD_NAME,
		"ability_id": ABILITY_ID,
		"scores": [1, 2, 3, 4],
		"count_towards_contradiction": true,
		"force_ends_turn": false
	}


func get_log_format(card: CardResource) -> String:
	return "[color=#5080e0]抽到「自圆其说」(分值 %d) (矛盾时保护前序牌)[/color]" % card.effect_value


## 被动效果：逻辑阶段无操作；抽牌动画阶段仅 UI 闪光
func effect(card: CardResource, _player_index: int, ctx: Dictionary) -> void:
	if str(ctx.get("effect_phase", "logic")) == "draw_animation":
		_effect_draw_animation(card, _player_index, ctx)
		return
	## 逻辑阶段：被动牌（矛盾保护）；九牛一毛夺取入回合 / 偷梁换柱交换后无主动效果，
	## 但注册表仍会 return true，须在此恢复 BattleManager 的 mod 暂停，否则会永久卡住。
	if ctx.get("is_stolen", false) or ctx.get("need_immediate_emit", false):
		var bm: Node = ctx.get("battle_manager") as Node
		if bm != null and bm.has_method("mod_resume_without_settle"):
			bm.call("mod_resume_without_settle")


func _effect_draw_animation(_card: CardResource, _player_index: int, ctx: Dictionary) -> void:
	var card_ui: Control = ctx.get("card_ui") as Control
	var host: Node = ctx.get("effect_host") as Node
	var on_complete: Callable = ctx.get("on_draw_animation_complete", Callable()) as Callable
	if card_ui == null or not is_instance_valid(card_ui) or host == null or not is_instance_valid(host):
		if on_complete.is_valid():
			on_complete.call()
		return
	card_ui.pivot_offset = card_ui.size / 2
	var tween: Tween = host.create_tween()
	tween.tween_property(card_ui, "modulate", Color(0.7, 0.8, 1.2), 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card_ui, "modulate", Color.WHITE, 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		if is_instance_valid(card_ui):
			card_ui.pivot_offset = Vector2.ZERO
		if on_complete.is_valid():
			on_complete.call()
	)
