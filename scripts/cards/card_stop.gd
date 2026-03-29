## 见好就收：抽到后强制结束回合
## 分值 1、2、3、4 各一张，参与矛盾判定
extends RefCounted

const CARD_NAME: String = "见好就收"


func get_registration_data() -> Dictionary:
	return {
		"name": CARD_NAME,
		"scores": [1, 2, 3, 4],
		"count_towards_contradiction": true,
		"force_ends_turn": true,
		"ability_id": "stop"
	}


func get_log_format(card: CardResource) -> String:
	return "[color=yellow][b]抽到「见好就收」(分值 %d) (回合强制结束)[/b][/color]" % card.effect_value


## 效果：立即完成见好就收特效并结算
func effect(card: CardResource, player_index: int, ctx: Dictionary) -> void:
	if str(ctx.get("effect_phase", "logic")) == "draw_animation":
		_effect_draw_animation(card, player_index, ctx)
		return
	var bm: Node = ctx.get("battle_manager")
	if bm != null and bm.has_method("_effect_stop"):
		bm.call("_effect_stop", ctx)


func _effect_draw_animation(_card: CardResource, _player_index: int, ctx: Dictionary) -> void:
	var card_ui: Control = ctx.get("card_ui") as Control
	var host: Node = ctx.get("effect_host") as Node
	var on_complete: Callable = ctx.get("on_draw_animation_complete", Callable()) as Callable
	var bm: Node = ctx.get("battle_manager")
	if card_ui == null or not is_instance_valid(card_ui) or host == null or not is_instance_valid(host):
		if on_complete.is_valid():
			on_complete.call()
		return
	card_ui.pivot_offset = card_ui.size / 2
	var tween: Tween = host.create_tween()
	tween.tween_property(card_ui, "modulate", Color(1.2, 1.15, 0.9), 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card_ui, "scale", Vector2(1.08, 1.08), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_ui, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card_ui, "modulate", Color.WHITE, 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		if is_instance_valid(card_ui):
			card_ui.pivot_offset = Vector2.ZERO
		if bm != null and bm.has_method("set_effect_playing"):
			bm.call("set_effect_playing", false)
		if bm != null and bm.has_method("complete_stop_card_effect"):
			bm.call("complete_stop_card_effect")
		if on_complete.is_valid():
			on_complete.call()
	)
