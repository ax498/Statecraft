## 空牌：基础卡牌，无特殊效果，不参与矛盾判定
## 分值 1、2、3、4 各一张
extends RefCounted

const CARD_NAME: String = "空牌"


func get_registration_data() -> Dictionary:
	return {
		"name": CARD_NAME,
		"scores": [1, 2, 3, 4],
		"count_towards_contradiction": false,
		"force_ends_turn": false,
		"ability_id": ""
	}


func get_log_format(card: CardResource) -> String:
	return "[color=#888]抽到「空牌」(分值 %d) (安全)[/color]" % card.effect_value
