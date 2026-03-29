## Mod 注入引擎（单例）
## 扫描 .gd 脚本、运行时实例化、触发钩子、脚本替换
extends Node

## 已加载的 Mod 脚本实例列表
var active_mod_instances: Array[RefCounted] = []
## 已加载路径，避免重复加载
var _loaded_script_paths: Dictionary = {}


func _ready() -> void:
	_load_mod_scripts()


## 清空已加载 Mod，供 ModManager 刷新时调用
func clear_loaded_mods() -> void:
	active_mod_instances.clear()
	_loaded_script_paths.clear()


## 重新扫描并加载所有 Mod 脚本（供 ModManager.reload_all_mods 调用）
func reload_mod_scripts() -> void:
	_load_mod_scripts()


## 递归扫描 Mod 目录下的所有 .gd/.gdc 文件并加载
func _load_mod_scripts() -> void:
	active_mod_instances.clear()
	_loaded_script_paths.clear()
	var mod_path: String = ModManager.get_mod_storage_path()
	var gd_paths: Array[String] = _collect_gd_files(mod_path)
	## 编辑器/内置：也扫描 res://mods/（项目内 Mod 文件夹）
	if mod_path != "res://mods/":
		for p: String in _collect_gd_files("res://mods/"):
			if not gd_paths.has(p):
				gd_paths.append(p)
	for path: String in gd_paths:
		_load_single_script(path)


func _collect_gd_files(base_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir: DirAccess = DirAccess.open(base_path)
	if dir == null:
		return result
	_collect_gd_files_recursive(dir, base_path, result)
	return result


func _collect_gd_files_recursive(dir: DirAccess, current_path: String, out: Array[String]) -> void:
	var dirs: PackedStringArray = dir.get_directories()
	for dir_name: String in dirs:
		if dir_name.begins_with("."):
			continue
		var sub_path: String = current_path.path_join(dir_name)
		var sub_dir: DirAccess = DirAccess.open(sub_path)
		if sub_dir != null:
			_collect_gd_files_recursive(sub_dir, sub_path, out)
	var files: PackedStringArray = dir.get_files()
	for file_name: String in files:
		var lower: String = file_name.to_lower()
		if lower.ends_with(".gd") or lower.ends_with(".gdc"):
			out.append(current_path.path_join(file_name))


func _load_single_script(path: String) -> void:
	if _loaded_script_paths.get(path, false):
		return
	var mod_id: String = _get_mod_id_from_script_path(path)
	if not ModManager.get_mod_enabled(mod_id):
		return
	var script: GDScript = load(path) as GDScript
	if script == null:
		push_warning("[ModLoader] 无法加载脚本: %s" % path)
		return
	var instance: Variant = script.new()
	if instance == null:
		push_warning("[ModLoader] 无法实例化脚本: %s" % path)
		return
	if not (instance is RefCounted):
		push_warning("[ModLoader] Mod 脚本必须继承 RefCounted: %s" % path)
		return
	active_mod_instances.append(instance as RefCounted)
	if instance.has_method("_mod_init"):
		instance.call("_mod_init")
	_loaded_script_paths[path] = true
	print("[ModLoader] 已加载 Mod 脚本: %s" % path)


## 从脚本路径提取 Mod id（父文件夹名）
## 如 res://mods/example_mod/main.gd 或 user://mods/example_mod/main.gd -> example_mod
func _get_mod_id_from_script_path(path: String) -> String:
	for base: String in [ModManager.get_mod_storage_path(), "res://mods/"]:
		if path.begins_with(base):
			var rel: String = path.substr(base.length())
			var parts: PackedStringArray = rel.split("/")
			if parts.size() > 0:
				return parts[0]
	return ""


## 触发生命周期钩子，所有 Mod 的 _on_hook_triggered 会被调用
## args 为数组，Mod 可修改其中元素（引用传递）
func trigger_hook(hook_name: String, args: Array = []) -> void:
	for mod: RefCounted in active_mod_instances:
		if mod.has_method("_on_hook_triggered"):
			mod.call("_on_hook_triggered", hook_name, args)


## 运行时替换节点脚本
## node_path 支持绝对路径（如 /root/BattleTest/...）或相对当前场景路径
func replace_node_script(node_path: String, new_script_path: String) -> bool:
	var target: Node = get_tree().root.get_node_or_null(node_path)
	if target == null and get_tree().current_scene != null:
		target = get_tree().current_scene.get_node_or_null(node_path)
	if target == null:
		push_warning("[ModLoader] 未找到节点: %s" % node_path)
		return false
	var script: Script = load(new_script_path) as Script
	if script == null:
		push_warning("[ModLoader] 无法加载脚本: %s" % new_script_path)
		return false
	target.set_script(script)
	print("[ModLoader] 已替换节点脚本: %s -> %s" % [node_path, new_script_path])
	return true


## 供 Mod 调用核心 API：api_call("CardManager", "register_card", [dict])
func api_call(api_name: String, method: String, args: Array = []) -> Variant:
	match api_name:
		"CardManager":
			var cm: Node = get_card_manager()
			if cm.has_method(method):
				return cm.callv(method, args)
		"BattleManager":
			var bm: Node = get_battle_manager()
			if bm.has_method(method):
				return bm.callv(method, args)
	return null


## 供 Mod 获取 BattleManager
func get_battle_manager() -> Node:
	return get_node("/root/BattleManager")


## 供 Mod 获取 CardManager
func get_card_manager() -> Node:
	return get_node("/root/CardManager")
