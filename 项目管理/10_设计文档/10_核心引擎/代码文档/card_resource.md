# CardResource 代码说明

**路径**：`scripts/data/card_resource.gd`  
**类型**：Resource，class_name CardResource

---

## 主要逻辑

卡牌数据定义，用于 .tres 资源与运行时创建的卡牌实例。存储名称、分值、技能 ID、矛盾判定与回合结束标志。

---

## 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| card_name | String | 卡牌名称 |
| effect_value | int | 效果分值 |
| ability_id | String | Mod 技能标识，如 "tashanzhishi" |
| count_towards_contradiction | bool | 是否参与同名矛盾判定 |
| force_ends_turn | bool | 是否强制结束回合 |
