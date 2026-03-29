## UI 工具类：提供主菜单与战斗场景共用的样式创建
## 消除 _make_mod_btn_style 等重复代码
class_name UIHelper
extends RefCounted

## Mod 列表按钮样式：灰底、灰边框、圆角
static func make_mod_btn_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.941, 0.941, 0.941, 1)
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.294, 0.294, 0.29, 1)
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left = 4
	s.content_margin_left = 12.0
	s.content_margin_top = 8.0
	s.content_margin_right = 12.0
	s.content_margin_bottom = 8.0
	return s
