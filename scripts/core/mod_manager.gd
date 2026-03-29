## Mod 管理器（单例）
## 负责加载外部 Mod、读取 mod_info.json、检测资源覆盖、启用状态持久化
extends Node

const MOD_CONFIG_PATH: String = "user://mod_config.json"

## 当前 Mod 存放路径（由 get_mod_storage_path 决定）
var _mod_storage_path: String = ""

## 常见可被覆盖的资源路径（仅包含实际存在的资源，避免 load 报错）
const COMMON_OVERRIDE_PATHS: Array[String] = [
	"res://resources/pictures/card.png",
	"res://resources/pictures/card_copy.png",
	"res://resources/pictures/card_jade.png",
	"res://resources/pictures/GameScene.png",
]

## 已加载的 Mod 详情列表，每项为 Dictionary：
## { id, file_name, name, author, description, version, is_valid, is_enabled, mod_type }
var mod_details: Array[Dictionary] = []

## 被 Mod 覆盖的资源路径列表
var overridden_resources: Array[String] = []

## 兼容旧接口：已成功加载的 Mod 文件名列表
var loaded_mods: Array[String] = []


## 联机校验：返回已启用 Mod 列表 [{id, version}, ...]，供主机与客户端比对
func get_mod_list_for_verification() -> Array:
	var list: Array = []
	for info: Dictionary in mod_details:
		if not info.get("is_enabled", true):
			continue
		list.append({
			"id": info.get("id", ""),
			"version": str(info.get("version", "1.0"))
		})
	return list


## 校验本地 Mod 是否包含对方全部 Mod（id+version 一致）
## 返回 {ok: bool, message: String}
func verify_mod_list_contains(required: Array) -> Dictionary:
	var local_map: Dictionary = {}
	for item: Dictionary in get_mod_list_for_verification():
		local_map[item.get("id", "")] = item.get("version", "")
	var missing: Array[String] = []
	for item: Dictionary in required:
		var rid: String = item.get("id", "")
		var rver: String = str(item.get("version", "1.0"))
		if not local_map.has(rid):
			missing.append("%s (v%s)" % [rid, rver])
		elif local_map[rid] != rver:
			missing.append("%s (需要 v%s，本地 v%s)" % [rid, rver, local_map[rid]])
	if missing.is_empty():
		return {"ok": true, "message": ""}
	return {"ok": false, "message": "缺少或版本不匹配的 Mod：\n" + "\n".join(missing)}


func _ready() -> void:
	_mod_storage_path = get_mod_storage_path()
	# 自动初始化目录
	var abs_path: String = ProjectSettings.globalize_path(_mod_storage_path)
	var err: Error = DirAccess.make_dir_recursive_absolute(abs_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("[ModManager] 无法创建 Mod 目录: %s" % abs_path)
	_load_mod_config()
	_load_external_mods()


## 根据运行环境返回 Mod 存放路径
## 编辑器：res://mods/；安卓：Documents/Statecraft/mods/；其他：user://mods/
func get_mod_storage_path() -> String:
	if OS.has_feature("editor"):
		return "res://mods/"
	if OS.has_feature("android"):
		return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("Statecraft/mods/")
	return "user://mods/"


## 返回 Mod 存放路径的系统绝对路径
func get_mod_storage_path_absolute() -> String:
	return ProjectSettings.globalize_path(get_mod_storage_path())


## 加载 mod_config.json 到内存（供 _apply_mod_config 使用）
var _mod_config: Dictionary = {}


func _load_mod_config() -> void:
	_mod_config.clear()
	var f: FileAccess = FileAccess.open(MOD_CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed != null and parsed is Dictionary:
		_mod_config = parsed as Dictionary


## 保存 mod_config.json
func save_mod_config() -> void:
	var to_save: Dictionary = {}
	for info: Dictionary in mod_details:
		to_save[info.get("id", "")] = info.get("is_enabled", true)
	var f: FileAccess = FileAccess.open(MOD_CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[ModManager] 无法写入 mod_config.json")
		return
	f.store_string(JSON.stringify(to_save))
	f.close()


## 完全重新加载 Mod（扫描目录、加载脚本），供「重新浏览」按钮调用
func reload_all_mods() -> void:
	var ml: Node = get_node_or_null("/root/ModLoader")
	if ml != null and ml.has_method("clear_loaded_mods"):
		ml.call("clear_loaded_mods")
	## 清空 Mod 注册的卡牌，避免重复注册
	var cm: Node = get_node_or_null("/root/CardManager")
	if cm != null and cm.has_method("clear_mod_registered_cards"):
		cm.call("clear_mod_registered_cards")
	_load_external_mods()
	if ml != null and ml.has_method("reload_mod_scripts"):
		ml.call("reload_mod_scripts")


## 重新扫描脚本 Mod 并合并到 mod_details（如生成模板后调用）
func refresh_mod_details() -> void:
	var mod_path: String = get_mod_storage_path()
	var dir: DirAccess = DirAccess.open(mod_path)
	if dir == null:
		return
	var existing_ids: Dictionary = {}
	for info: Dictionary in mod_details:
		existing_ids[info.get("id", "")] = true
	var dirs: PackedStringArray = dir.get_directories()
	for dir_name: String in dirs:
		if dir_name.begins_with(".") or existing_ids.get(dir_name, false):
			continue
		var sub_path: String = mod_path.path_join(dir_name)
		if not _dir_has_gd_files(sub_path):
			continue
		var info_path: String = sub_path.path_join("mod_info.json")
		var info: Dictionary = {
			"id": dir_name,
			"file_name": dir_name,
			"name": dir_name,
			"author": "",
			"description": "",
			"version": "1.0",
			"is_valid": true,
			"is_enabled": _mod_config.get(dir_name, true),
			"mod_type": "script"
		}
		var json_text: String = _read_file_as_text(info_path)
		if not json_text.is_empty():
			var parsed: Variant = JSON.parse_string(json_text)
			if parsed != null and parsed is Dictionary:
				var d: Dictionary = parsed as Dictionary
				info["name"] = str(d.get("name", dir_name))
				info["author"] = str(d.get("author", ""))
				info["description"] = str(d.get("description", ""))
				info["version"] = str(d.get("version", "1.0"))
		mod_details.append(info)


## 根据 id 获取/设置启用状态
func get_mod_enabled(mod_id: String) -> bool:
	for info: Dictionary in mod_details:
		if info.get("id", "") == mod_id:
			return info.get("is_enabled", true)
	return true


func set_mod_enabled(mod_id: String, enabled: bool) -> void:
	for info: Dictionary in mod_details:
		if info.get("id", "") == mod_id:
			info["is_enabled"] = enabled
			return


## 加载 Mod 目录下的脚本 Mod（含 .gd/.gdc 的文件夹），读取 mod_info.json，检测覆盖
func _load_external_mods() -> void:
	mod_details.clear()
	loaded_mods.clear()
	overridden_resources.clear()

	# 1. 加载主包资源哈希（用于后续覆盖检测）
	var original_hashes: Dictionary = {}
	for path: String in COMMON_OVERRIDE_PATHS:
		var h: String = _get_texture_hash(path)
		if h != "":
			original_hashes[path] = h

	# 2. 确保目录存在并打开
	var mod_path: String = get_mod_storage_path()
	var dir: DirAccess = DirAccess.open(mod_path)
	if dir == null:
		if OS.has_feature("android"):
			print("[ModManager] 安卓无法打开 Mod 目录: %s" % mod_path)
		_scan_overrides(original_hashes)
		return

	# 3. 扫描脚本 Mod（含 .gd/.gdc 的文件夹），加入 mod_details
	_scan_script_mods(mod_path, dir)
	## 非编辑器或存储路径非 res://mods/ 时，额外扫描项目内 res://mods/（内置 Mod）
	if mod_path != "res://mods/":
		var res_dir: DirAccess = DirAccess.open("res://mods/")
		if res_dir != null:
			_scan_script_mods("res://mods/", res_dir)

	# 4. 应用持久化配置
	_apply_mod_config()

	# 5. 检测覆盖
	_scan_overrides(original_hashes)


func _scan_script_mods(mod_path: String, dir: DirAccess) -> void:
	var existing_ids: Dictionary = {}
	for info: Dictionary in mod_details:
		existing_ids[info.get("id", "")] = true
	var dirs: PackedStringArray = dir.get_directories()
	for dir_name: String in dirs:
		if dir_name.begins_with(".") or existing_ids.get(dir_name, false):
			continue
		var sub_path: String = mod_path.path_join(dir_name)
		if not _dir_has_gd_files(sub_path):
			continue
		var info_path: String = sub_path.path_join("mod_info.json")
		var info: Dictionary = {
			"id": dir_name,
			"file_name": dir_name,
			"name": dir_name,
			"author": "",
			"description": "",
			"version": "1.0",
			"is_valid": true,
			"is_enabled": _mod_config.get(dir_name, true),
			"mod_type": "script"
		}
		var json_text: String = _read_file_as_text(info_path)
		if not json_text.is_empty():
			var parsed: Variant = JSON.parse_string(json_text)
			if parsed != null and parsed is Dictionary:
				var d: Dictionary = parsed as Dictionary
				info["name"] = str(d.get("name", dir_name))
				info["author"] = str(d.get("author", ""))
				info["description"] = str(d.get("description", ""))
				info["version"] = str(d.get("version", "1.0"))
		mod_details.append(info)


func _dir_has_gd_files(path: String) -> bool:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return false
	var files: PackedStringArray = d.get_files()
	for f: String in files:
		var lower: String = f.to_lower()
		if lower.ends_with(".gd") or lower.ends_with(".gdc"):
			return true
	var subdirs: PackedStringArray = d.get_directories()
	for sub: String in subdirs:
		if sub.begins_with("."):
			continue
		if _dir_has_gd_files(path.path_join(sub)):
			return true
	return false


func _apply_mod_config() -> void:
	for info: Dictionary in mod_details:
		var mod_id: String = info.get("id", "")
		if _mod_config.has(mod_id):
			info["is_enabled"] = _mod_config[mod_id]


func _read_file_as_text(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


func _get_texture_hash(path: String) -> String:
	var res: Resource = load(path) as Resource
	if res == null:
		return ""
	if res is Texture2D:
		var tex: Texture2D = res as Texture2D
		var img: Image = tex.get_image()
		if img == null:
			return ""
		var data: PackedByteArray = img.get_data()
		var ctx: HashingContext = HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update(data)
		return ctx.finish().hex_encode()
	return ""


func _scan_overrides(original_hashes: Dictionary) -> void:
	overridden_resources.clear()
	for path: String in COMMON_OVERRIDE_PATHS:
		var orig: Variant = original_hashes.get(path)
		if orig == null:
			continue
		var current: String = _get_texture_hash(path)
		if current != "" and current != orig:
			overridden_resources.append(path)


## 在 Mod 存放路径下生成 example_mod 模板
## 返回系统绝对路径，失败返回空字符串
func generate_example_mod_template() -> String:
	var storage: String = get_mod_storage_path()
	var example_dir: String = storage.path_join("example_mod/")
	var abs_path: String = ProjectSettings.globalize_path(example_dir)
	var err: Error = DirAccess.make_dir_recursive_absolute(abs_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("[ModManager] 无法创建目录: %s" % abs_path)
		return ""

	var mod_info: String = "{\n  \"name\": \"示例 Mod\",\n  \"author\": \"你的名字\",\n  \"description\": \"脚本注入示例：拦截抽牌并给当前玩家加 100 分\",\n  \"version\": \"1.0\"\n}"
	var mod_info_path: String = example_dir.path_join("mod_info.json")
	var f_info: FileAccess = FileAccess.open(mod_info_path, FileAccess.WRITE)
	if f_info == null:
		push_warning("[ModManager] 无法写入 mod_info.json")
		return abs_path
	f_info.store_string(mod_info)
	f_info.close()

	# 生成示例 Mod 脚本 main.gd
	var main_gd: String = """extends RefCounted

## 示例 Mod：演示钩子拦截与分数修改
## 游戏启动时打印 Hello Mod World，每次抽牌后给当前玩家加 100 分

func _mod_init() -> void:
	print("Hello Mod World")

func _on_hook_triggered(hook_name: String, args: Array) -> void:
	if hook_name == "post_draw_card":
		var player_index: int = args[1] if args.size() > 1 else 0
		var bm: Node = ModLoader.get_battle_manager()
		bm.player_scores[player_index] += 100
		bm.score_updated.emit(player_index, bm.player_scores[player_index])
"""
	var main_gd_path: String = example_dir.path_join("main.gd")
	var f_gd: FileAccess = FileAccess.open(main_gd_path, FileAccess.WRITE)
	if f_gd != null:
		f_gd.store_string(main_gd)
		f_gd.close()

	var storage_abs: String = ProjectSettings.globalize_path(storage)
	var readme: String = """Statecraft Mod 模板 - 使用说明
=====================================

将含 .gd 脚本的 Mod 文件夹放入 Mod 存放目录即可加载。
- main.gd：示例脚本，演示 _mod_init 与 _on_hook_triggered 钩子。
- 修改 main.gd 后点击「重新浏览」或重启游戏即可生效。

当前平台 Mod 存放路径：%s
"""
	var readme_path: String = example_dir.path_join("readme.txt")
	var f_readme: FileAccess = FileAccess.open(readme_path, FileAccess.WRITE)
	if f_readme != null:
		f_readme.store_string(readme % storage_abs)
		f_readme.close()

	print("[ModManager] 模板已生成: ", abs_path)
	return abs_path
