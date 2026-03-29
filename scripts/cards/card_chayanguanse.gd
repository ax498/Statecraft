## 察言观色：抽到此牌时可查看下一张牌
## 分值 1、2、3、4 各一张，参与矛盾判定
## 玩家抽到展示下一张牌；AI 抽到不展示，AI 根据下一张是否矛盾决定是否继续；联机对手抽到不展示
extends RefCounted

const CARD_NAME: String = "察言观色"
const ABILITY_ID: String = "chayanguanse"


func get_registration_data() -> Dictionary:
	return {
		"name": CARD_NAME,
		"ability_id": ABILITY_ID,
		"scores": [1, 2, 3, 4],
		"count_towards_contradiction": true,
		"force_ends_turn": false
	}


func get_log_format(card: CardResource) -> String:
	return "[color=#c0a0ff]抽到「察言观色」(分值 %d) (可查看下一张牌)[/color]" % card.effect_value


## 效果：查看牌堆顶下一张牌并展示给本地玩家
func effect(card: CardResource, player_index: int, ctx: Dictionary) -> void:
	if str(ctx.get("effect_phase", "logic")) == "draw_animation":
		_effect_draw_animation(card, player_index, ctx)
		return
	var bm: Node = ctx.get("battle_manager")
	if bm == null:
		return
	if bm.has_method("_effect_chayanguanse"):
		bm.call("_effect_chayanguanse", player_index, ctx)


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
	tween.tween_property(card_ui, "modulate", Color(1.15, 0.95, 1.25), 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card_ui, "modulate", Color.WHITE, 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		if is_instance_valid(card_ui):
			card_ui.pivot_offset = Vector2.ZERO
		if on_complete.is_valid():
			on_complete.call()
	)
