## 一石二鸟：双倍分值卡牌
## 分值 2、4、6、8 各一张，参与矛盾判定
extends RefCounted

const CARD_NAME: String = "一石二鸟"


func get_registration_data() -> Dictionary:
	return {
		"name": CARD_NAME,
		"scores": [2, 4, 6, 8],
		"count_towards_contradiction": true,
		"force_ends_turn": false,
		"ability_id": "double"
	}


func get_log_format(card: CardResource) -> String:
	return "[color=cyan]抽到「一石二鸟」(分值 %d)[/color]" % card.effect_value
