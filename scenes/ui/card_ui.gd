## 卡牌 UI 组件
## 统一使用 card.png 底图，通过文字区分牌种
extends Control

const CARD_TEXTURE: String = "res://resources/pictures/card.png"

@onready var texture_rect: TextureRect = $TextureRect
@onready var label: Label = $Label

var card_data: CardResource


func setup(card: CardResource) -> void:
	card_data = card
	## 支持在 add_child 之前调用：@onready 可能未执行，用 get_node 兜底
	var tex_rect: TextureRect = texture_rect
	if tex_rect == null:
		tex_rect = get_node_or_null("TextureRect") as TextureRect
	if tex_rect != null:
		tex_rect.texture = load(CARD_TEXTURE) as Texture2D
	var lbl: Label = label
	if lbl == null:
		lbl = get_node_or_null("Label") as Label
	if lbl != null:
		lbl.text = "%s\n%d" % [card.card_name, card.effect_value]


## 刷新显示（当 card_data 被修改后调用）
func update_ui() -> void:
	if card_data != null:
		label.text = "%s\n%d" % [card_data.card_name, card_data.effect_value]


func set_contradiction_style(is_contradiction: bool) -> void:
	if is_contradiction:
		modulate = Color(1.2, 0.3, 0.3)
	else:
		modulate = Color.WHITE


## 自圆其说保护样式：蓝光（矛盾时被保护的卡牌）
func set_protected_style(is_protected: bool) -> void:
	if is_protected:
		modulate = Color(0.5, 0.6, 1.2)
	else:
		modulate = Color.WHITE


## 播放变身动画，完成后调用 on_complete（用于变身→判定→执行的流程，让玩家看清变身后的卡牌）
func play_transform_animation(on_complete: Callable = Callable()) -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		if on_complete.is_valid():
			on_complete.call()
		return
	var orig_pivot: Vector2 = pivot_offset
	pivot_offset = size / 2
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", Color(1.2, 1.2, 1.0), 0.08)
	tween.tween_property(self, "modulate", Color.WHITE, 0.12)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_callback(func() -> void:
		if is_instance_valid(self) and is_inside_tree():
			pivot_offset = orig_pivot
		if on_complete.is_valid():
			on_complete.call()
	)


## 播放“额外行动”发光动画（神来之笔变身后持续到效果执行完毕）
func play_extra_action_glow() -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var tween: Tween = create_tween()
	tween.set_loops(3)
	tween.tween_property(self, "modulate", Color(1.2, 1.2, 1.0), 0.15)
	tween.tween_property(self, "modulate", Color.WHITE, 0.15)
	tween.tween_interval(0.1)


## 设置为手牌区缩小显示模式
## scale_override: 可选，传入时使用该值；否则 compact=true 用 0.6，false 用 1.0
func set_compact(compact: bool, scale_override: float = -1.0) -> void:
	var s: float
	if scale_override > 0.0:
		s = scale_override
	elif compact:
		s = 0.6
	else:
		s = 1.0
	scale = Vector2(s, s)
