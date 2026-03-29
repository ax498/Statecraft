# ModLoader 代码说明

**路径**：`scripts/core/mod_loader.gd`  
**类型**：Autoload 单例

---

## 主要逻辑

扫描 Mod 目录下的 .gd 脚本，实例化并调用 `_mod_init`；通过 `trigger_hook` 触发生命周期钩子，供 Mod 的 `_on_hook_triggered` 响应；提供 `api_call` 供 Mod 调用 CardManager/BattleManager。

---

## 核心方法

| 方法 | 功能 | 实现 |
|------|------|------|
| `_load_mod_scripts()` | 加载 Mod | 递归扫描 `get_mod_storage_path()` 下 .gd，实例化并调用 `_mod_init` |
| `trigger_hook(hook_name, args)` | 触发钩子 | 遍历 `active_mod_instances`，调用 `_on_hook_triggered(hook_name, args)` |
| `api_call(api_name, method, args)` | Mod 调用 API | 匹配 CardManager/BattleManager，`callv(method, args)` |
| `get_battle_manager()` | 获取 BattleManager | `get_node("/root/BattleManager")` |
| `get_card_manager()` | 获取 CardManager | `get_node("/root/CardManager")` |
| `replace_node_script(path, script_path)` | 替换节点脚本 | 加载脚本并 `target.set_script(script)` |
