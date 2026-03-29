## 九牛一毛：当对方有牌时，可选择对方一张任意类型卡牌
## 在对方该类型中取分值最低的一张，夺取并添加到回合牌堆
## 夺取后先判断矛盾，不矛盾才触发被夺取牌的效果并继续游戏
extends RefCounted

const CARD_NAME: String = "九牛一毛"
const ABILITY_ID: String = "jiuniuyimao"


func get_registration_data() -> Dictionary:
	return {
		"name": CARD_NAME,
		"ability_id": ABILITY_ID,
		"scores": [1, 2, 3, 4],
		"count_towards_contradiction": true,
		"force_ends_turn": false
	}


func get_log_format(card: CardResource) -> String:
	return "[color=#ffa050]抽到「九牛一毛」(分值 %d) (可夺取对手牌)[/color]" % card.effect_value


## 效果：请求选择对手牌类型以夺取
func effect(card: CardResource, player_index: int, ctx: Dictionary) -> void:
	if str(ctx.get("effect_phase", "logic")) == "draw_animation":
		_effect_draw_animation(card, player_index, ctx)
		return
	var bm: Node = ctx.get("battle_manager")
	if bm != null and bm.has_method("_effect_jiuniuyimao"):
		bm.call("_effect_jiuniuyimao", player_index, ctx)


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
	tween.tween_property(card_ui, "modulate", Color(1.2, 1.0, 0.85), 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(card_ui, "modulate", Color.WHITE, 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		if is_instance_valid(card_ui):
			card_ui.pivot_offset = Vector2.ZERO
		if on_complete.is_valid():
			on_complete.call()
	)
