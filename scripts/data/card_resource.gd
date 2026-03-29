## 卡牌资源定义
## 用于 .tres 资源文件，存储单张卡牌的数据
class_name CardResource
extends Resource

@export var card_name: String = ""
@export var effect_value: int = 0
## Mod 技能标识，如 "copy_card" 用于神来之笔
@export var ability_id: String = ""
## 是否计入矛盾判定（同名且均开启时触发矛盾）
@export var count_towards_contradiction: bool = false
## 是否强制结束回合（加入容器后立即结算）
@export var force_ends_turn: bool = false
