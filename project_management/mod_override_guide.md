# Mod 开发指南

**版本**：v0.2.0  
**最后更新**：2025-03-21

## 概述

游戏通过 **Mod 文件夹** 加载 Mod，不再支持 `.pck` 资源包。将包含 `.gd`/`.gdc` 脚本的 Mod 文件夹放入指定目录即可。

## 目录位置

| 平台 | Mod 存放路径 |
|------|--------------|
| 编辑器 | `res://mods/` |
| Android | `Documents/Statecraft/mods/` |
| 其他 | `user://mods/` |

## 加载原理

1. **ModManager** 扫描 Mod 存放路径下的子目录
2. 识别包含 `.gd` 或 `.gdc` 文件的目录为有效 Mod
3. **ModLoader** 递归加载这些脚本并实例化，触发 `_mod_init` 等钩子

## mod_info.json 规范

Mod 开发者应在 Mod 文件夹根目录放置 `mod_info.json`，供游戏读取并显示 Mod 名称、作者等信息。格式示例：

```json
{
  "name": "我的卡牌 Mod",
  "author": "作者名",
  "description": "通过脚本添加新卡牌或扩展玩法",
  "version": "1.0"
}
```

- **name**：Mod 显示名称（必填）
- **author**：作者（可选）
- **description**：详细说明（可选）
- **version**：版本号（可选，默认 "1.0"）

若 Mod 缺少该文件或格式错误，将显示为「未知/损坏的 Mod」。

## 如何制作 Mod

1. **创建文件夹**：在 Mod 存放路径下创建子目录，如 `my_mod/`
2. **添加 mod_info.json**：按上述格式编写
3. **添加脚本**：在文件夹内放置 `.gd` 脚本，实现 `_mod_init` 等钩子，通过 `ModLoader.api_call("CardManager", "register_card", [dict])` 注册新卡牌
4. **可选资源**：Mod 可包含图片等资源，通过 `load("user://mods/my_mod/xxx.png")` 等方式加载

## 注意事项

- Mod 脚本必须继承 `RefCounted`
- 修改 Mod 后需在游戏中刷新 Mod 列表或重启游戏生效
- 不再支持通过 `.pck` 覆盖游戏内置资源
