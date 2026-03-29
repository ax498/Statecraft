## 箭在弦上：抽到后短暂停顿 + 专属特效，然后强制再抽一张牌（无法停止）
## 第二张牌走正常抽牌流程
## 分值 1、2、3、4 各一张，参与矛盾判定
extends RefCounted

const CARD_NAME: String = "箭在弦上"
const ABILITY_ID: String = "jianzaixianshang"


func get_registration_data() -> Dictionary:
	return {
		"name": CARD_NAME,
		"ability_id": ABILITY_ID,
		"scores": [1, 2, 3, 4],
		"count_towards_contradiction": true,
		"force_ends_turn": false
	}


func get_log_format(card: CardResource) -> String:
	return "[color=#a0d0a0]抽到「箭在弦上」(分值 %d) (强制再抽一张)[/color]" % card.effect_value


## 效果：正常抽到由 draw_animation 阶段播蓄力并 request_force_draw_after_effect；
## 偷梁换柱交换后 / 九牛一毛夺取后无滑入动画，由 BattleManager._effect_jianzaixianshang 发信号补播
func effect(card: CardResource, player_index: int, ctx: Dictionary) -> void:
	if str(ctx.get("effect_phase", "logic")) == "draw_animation":
		_effect_draw_animation(card, player_index, ctx)
		return
	var bm: Node = ctx.get("battle_manager")
	if bm != null and bm.has_method("_effect_jianzaixianshang"):
		bm.call("_effect_jianzaixianshang", card, player_index, ctx)


func _effect_draw_animation(_card: CardResource, _player_index: int, ctx: Dictionary) -> void:
	var card_ui: Control = ctx.get("card_ui") as Control
	var host: Node = ctx.get("effect_host") as Node
	var after_visual: Callable = ctx.get("jianzaixianshang_after_visual", Callable()) as Callable
	if card_ui == null or not is_instance_valid(card_ui) or host == null or not is_instance_valid(host):
		if after_visual.is_valid():
			after_visual.call()
		return
	card_ui.pivot_offset = card_ui.size / 2
	var tween: Tween = host.create_tween()
	tween.tween_interval(0.4)
	tween.tween_property(card_ui, "modulate", Color(1.15, 1.0, 0.75), 0.25).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(card_ui, "scale", Vector2(0.97, 0.97), 0.25).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card_ui, "modulate", Color(1.3, 1.3, 1.2), 0.15).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(card_ui, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card_ui, "modulate", Color.WHITE, 0.1).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		if is_instance_valid(card_ui):
			card_ui.pivot_offset = Vector2.ZERO
		if after_visual.is_valid():
			after_visual.call()
	)
