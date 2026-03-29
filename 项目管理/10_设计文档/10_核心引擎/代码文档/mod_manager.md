# ModManager 代码说明

**路径**：`scripts/core/mod_manager.gd`  
**类型**：Autoload 单例

---

## 主要逻辑

管理 Mod 存放路径、加载脚本 Mod（Mod 文件夹）、读取 mod_info.json、持久化启用状态到 mod_config.json、检测资源覆盖、联机 Mod 校验。

---

## 核心方法

| 方法 | 功能 | 实现 |
|------|------|------|
| `get_mod_storage_path()` | Mod 存放路径 | 编辑器 res://mods/，安卓 文档/Statecraft/mods/，其他 user://mods/ |
| `get_mod_list_for_verification()` | 联机校验列表 | 返回已启用 Mod 的 [{id, version}] |
| `verify_mod_list_contains(required)` | 校验 Mod 匹配 | 比对本地是否包含对方全部 Mod（id+version） |
| `get_mod_enabled(mod_id)` | 获取启用状态 | 从 mod_details 查找 |
| `set_mod_enabled(mod_id, enabled)` | 设置启用状态 | 修改 mod_details，需 `save_mod_config` 持久化 |
| `refresh_mod_details()` | 刷新 Mod 列表 | 扫描目录，合并新脚本 Mod 到 mod_details |
| `generate_example_mod_template()` | 生成示例模板 | 创建 example_mod 目录、mod_info.json、main.gd、readme.txt |
