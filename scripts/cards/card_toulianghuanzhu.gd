## 偷梁换柱：抽到后选择一张回合牌堆的卡牌，两牌交换位置，被选牌效果触发一次
## 分值 1、2、3、4 各一张，参与矛盾判定
extends RefCounted

const CARD_NAME: String = "偷梁换柱"
const ABILITY_ID: String = "toulianghuanzhu"


func get_registration_data() -> Dictionary:
	return {
		"name": CARD_NAME,
		"ability_id": ABILITY_ID,
		"scores": [1, 2, 3, 4],
		"count_towards_contradiction": true,
		"force_ends_turn": false
	}


func get_log_format(card: CardResource) -> String:
	return "[color=#c0b060]抽到「偷梁换柱」(分值 %d) (可交换并触发被选牌效果)[/color]" % card.effect_value


## 效果：请求选择回合区卡牌交换
func effect(card: CardResource, player_index: int, ctx: Dictionary) -> void:
	if str(ctx.get("effect_phase", "logic")) == "draw_animation":
		_effect_draw_animation(card, player_index, ctx)
		return
	var bm: Node = ctx.get("battle_manager")
	if bm != null and bm.has_method("_effect_toulianghuanzhu"):
		bm.call("_effect_toulianghuanzhu", player_index, ctx)


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
	tween.tween_interval(0.2)
	tween.tween_property(card_ui, "modulate", Color(1.2, 1.1, 0.85), 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card_ui, "scale", Vector2(1.05, 1.05), 0.12).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card_ui, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card_ui, "modulate", Color.WHITE, 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		if is_instance_valid(card_ui):
			card_ui.pivot_offset = Vector2.ZERO
		if on_complete.is_valid():
			on_complete.call()
	)
