## Game logging system.
## Buffers log lines in memory and flushes them to disk per session.
## On Android, prefer app-specific external storage so logs end up under
## Android/data/<package>/files/logs for easier retrieval.
extends Node

const MAX_BUFFER: int = 5000
const MAX_LOG_FILES: int = 10

var _buffer: Array[String] = []
var _session_start: String = ""
var _file_path: String = ""
var _log_dir_global: String = ""
var _log_dir_prefix: String = ""


func _ready() -> void:
	if OS.has_feature("editor"):
		_log_dir_prefix = "res://logs"
		_log_dir_global = ProjectSettings.globalize_path("res://").path_join("logs")
	elif OS.has_feature("android"):
		var ext: String = _get_android_external_data_dir()
		if ext.is_empty():
			ext = ProjectSettings.globalize_path("user://")
		_log_dir_global = ext.path_join("logs")
		_log_dir_prefix = _log_dir_global
	else:
		_log_dir_prefix = "user://logs"
		_log_dir_global = ProjectSettings.globalize_path("user://").path_join("logs")
	print("[GameLogger] log_dir=%s" % _log_dir_global)
	_ensure_logs_dir()
	_start_session()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_session()


func _exit_tree() -> void:
	save_session()


func _get_android_external_data_dir() -> String:
	if not OS.has_feature("android"):
		return ""
	if not Engine.has_singleton("AndroidRuntime"):
		return ""
	var android_runtime: Object = Engine.get_singleton("AndroidRuntime")
	if android_runtime == null:
		return ""
	var context: Variant = android_runtime.getApplicationContext()
	if context == null:
		return ""
	var ext_dir: Variant = context.getExternalFilesDir("")
	if ext_dir == null:
		return ""
	var abs_path: String = str(ext_dir.getAbsolutePath())
	if abs_path.is_empty():
		return ""
	return abs_path


func _ensure_logs_dir() -> void:
	if OS.has_feature("editor"):
		return
	if OS.has_feature("android") and _log_dir_global.length() > 0:
		var err: Error = DirAccess.make_dir_recursive_absolute(_log_dir_global)
		if err != OK and err != ERR_ALREADY_EXISTS:
			push_warning("[GameLogger] Failed to create logs dir: %s" % _log_dir_global)
		return
	var base: DirAccess = DirAccess.open("user://")
	if base == null:
		push_warning("[GameLogger] Failed to open user://")
		return
	if not base.dir_exists("logs"):
		var err: Error = base.make_dir("logs")
		if err != OK:
			push_warning("[GameLogger] Failed to create logs dir: %s" % error_string(err))


func _start_session() -> void:
	_prune_old_logs()
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	_session_start = "%04d%02d%02d_%02d%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	_file_path = "%s/game_%s.log" % [_log_dir_prefix, _session_start]
	record("GameLogger", "session_start", {"path": _file_path})


func _prune_old_logs() -> void:
	var dir: DirAccess = DirAccess.open(_log_dir_prefix)
	if dir == null:
		return
	dir.list_dir_begin()
	var files: Array[Dictionary] = []
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".log"):
			var full: String = _log_dir_prefix.path_join(fname)
			var mtime: int = FileAccess.get_modified_time(full)
			files.append({"path": full, "mtime": mtime})
		fname = dir.get_next()
	dir.list_dir_end()
	if files.size() <= MAX_LOG_FILES:
		return
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.mtime < b.mtime)
	var to_delete: int = files.size() - MAX_LOG_FILES
	for i in range(to_delete):
		var abs_p: String = _to_absolute_path(files[i].path)
		var err: Error = DirAccess.remove_absolute(abs_p)
		if err == OK:
			print("[GameLogger] Deleted old log: %s" % abs_p)


func _to_absolute_path(path: String) -> String:
	if path.contains("://"):
		return ProjectSettings.globalize_path(path)
	return path


func record(tag: String, action: String, data: Variant = "") -> void:
	var ts: String = Time.get_time_string_from_system()
	var line: String
	if data == null or (data is String and data == ""):
		line = "[%s] [%s] %s" % [ts, tag, action]
	else:
		line = "[%s] [%s] %s %s" % [ts, tag, action, str(data)]
	_buffer.append(line)
	if _buffer.size() > MAX_BUFFER:
		_buffer.remove_at(0)
	print(line)


func debug(tag: String, action: String, data: Variant = "") -> void:
	record(tag, "[DEBUG] " + action, data)


func warn(tag: String, action: String, data: Variant = "") -> void:
	record(tag, "[WARN] " + action, data)


func error(tag: String, action: String, data: Variant = "") -> void:
	record(tag, "[ERROR] " + action, data)


func save_session() -> void:
	if _buffer.is_empty():
		return
	var f: FileAccess = FileAccess.open(_file_path, FileAccess.WRITE)
	if f == null:
		push_warning("[GameLogger] Failed to write %s" % _file_path)
		return
	for line in _buffer:
		f.store_line(line)
	f.close()
	var abs_path: String = _to_absolute_path(_file_path)
	print("[GameLogger] Saved log: %s (%d lines)" % [abs_path, _buffer.size()])


func flush() -> void:
	save_session()
