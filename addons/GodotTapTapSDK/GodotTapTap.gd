extends Node

const TAPTAP_CLIENT_ID: String = "5ta8ndc6wuwregs5uy"
const TAPTAP_CLIENT_TOKEN: String = "jWzyYROXSCSPgIy1Q0WvfuFqFXbnBgl0yUIwnxzr"

var singleton: Object = null
var _initialized: bool = false
var _signals_connected: bool = false
var _last_error: String = ""

signal onLoginResult(code, json)
signal onAntiAddictionCallback(code)
signal onTapMomentCallBack(code, msg)
signal onRewardVideoAdCallBack(code)


func _get_game_logger() -> Node:
	return get_node_or_null("/root/GameLogger")


func _log_record(action: String, data: Variant = "") -> void:
	var gl: Node = _get_game_logger()
	if gl and gl.has_method("record"):
		gl.record("GodotTapTap", action, data)
	else:
		print("[GodotTapTap] %s %s" % [action, str(data)])


func _log_warn(action: String, data: Variant = "") -> void:
	var gl: Node = _get_game_logger()
	if gl and gl.has_method("warn"):
		gl.warn("GodotTapTap", action, data)
	else:
		push_warning("[GodotTapTap] %s %s" % [action, str(data)])


func _ready() -> void:
	if Engine.has_singleton("GodotTapTapSDK"):
		singleton = Engine.get_singleton("GodotTapTapSDK")
		_log_record("runtime_singleton_found")
	else:
		_log_warn("runtime_singleton_missing")
	call_deferred("_ensure_singleton_ready")


func _ensure_singleton_ready() -> bool:
	if singleton == null:
		if not Engine.has_singleton("GodotTapTapSDK"):
			return _fail("Engine singleton GodotTapTapSDK is unavailable.")
		singleton = Engine.get_singleton("GodotTapTapSDK")
		if singleton == null:
			return _fail("Engine singleton GodotTapTapSDK could not be acquired.")
	if not _initialized:
		_log_record("init_begin", {"client_id": TAPTAP_CLIENT_ID})
		singleton.call("init", TAPTAP_CLIENT_ID, TAPTAP_CLIENT_TOKEN)
		_initialized = true
		_log_record("init_called")
	_connect_singleton_signals()
	_last_error = ""
	return true


func _connect_singleton_signals() -> void:
	if singleton == null or _signals_connected:
		return
	_connect_singleton_signal("onLoginResult", Callable(self, "_onLoginResult"))
	_connect_singleton_signal("onAntiAddictionCallback", Callable(self, "_onAntiAddictionCallback"))
	_connect_singleton_signal("onTapMomentCallBack", Callable(self, "_onTapMomentCallBack"))
	_connect_singleton_signal("onRewardVideoAdCallBack", Callable(self, "_onRewardVideoAdCallBack"))
	_signals_connected = true


func _connect_singleton_signal(signal_name: StringName, callable: Callable) -> void:
	if not singleton.has_signal(signal_name):
		_log_warn("missing_signal", {"signal": str(signal_name)})
		return
	if singleton.is_connected(signal_name, callable):
		_log_record("signal_already_connected", {"signal": str(signal_name)})
		return
	singleton.connect(signal_name, callable)
	_log_record("signal_connected", {"signal": str(signal_name)})


func _fail(message: String) -> bool:
	_last_error = message
	_log_warn("runtime_error", {"message": message})
	return false


func get_last_error() -> String:
	return _last_error


func is_runtime_ready() -> bool:
	return _ensure_singleton_ready()


func _call_runtime(method_name: StringName, args: Array = []) -> bool:
	if not _ensure_singleton_ready():
		return false
	_log_record("call_runtime", {"method": str(method_name), "args": args})
	singleton.callv(method_name, args)
	return true


func _onLoginResult(code: int, json: Variant) -> void:
	_log_record("on_login_result", {"code": code, "payload": str(json)})
	emit_signal("onLoginResult", code, json)


func _onAntiAddictionCallback(code: int) -> void:
	_log_record("on_anti_addiction_callback", {"code": code})
	emit_signal("onAntiAddictionCallback", code)


func _onTapMomentCallBack(code: int, msg: Variant) -> void:
	_log_record("on_tap_moment_callback", {"code": code, "message": str(msg)})
	emit_signal("onTapMomentCallBack", code, msg)


func _onRewardVideoAdCallBack(code: int) -> void:
	_log_record("on_reward_video_callback", {"code": code})
	emit_signal("onRewardVideoAdCallBack", code)


func tap_login() -> bool:
	var already_initialized: bool = _initialized
	if not _ensure_singleton_ready():
		return false
	_log_record("tap_login_requested", {"already_initialized": already_initialized})
	if already_initialized:
		singleton.call("login")
	else:
		call_deferred("_deferred_taptap_login")
	return true


func isLogin() -> bool:
	if not _ensure_singleton_ready():
		return false
	return bool(singleton.call("isLogin"))


func getCurrentProfile() -> Variant:
	if not _ensure_singleton_ready():
		return null
	return singleton.call("getCurrentProfile")


func logOut() -> bool:
	return _call_runtime("logOut")


func quickCheck(id: Variant = null) -> bool:
	var already_initialized: bool = _initialized
	if not _ensure_singleton_ready():
		return false
	if id == null:
		id = OS.get_unique_id()
	_log_record("quick_check_requested", {"already_initialized": already_initialized, "device_id": str(id)})
	if already_initialized:
		singleton.call("quickCheck", id)
	else:
		call_deferred("_deferred_quick_check", id)
	return true


func _deferred_taptap_login() -> void:
	if _ensure_singleton_ready():
		_log_record("tap_login_deferred_call")
		singleton.call("login")


func _deferred_quick_check(id: Variant) -> void:
	if _ensure_singleton_ready():
		_log_record("quick_check_deferred_call", {"device_id": str(id)})
		singleton.call("quickCheck", id)


func antiExit() -> bool:
	return _call_runtime("antiExit")


func setTestEnvironment(enable: bool) -> bool:
	return _call_runtime("setTestEnvironment", [enable])


func setEntryVisible(enable: bool) -> bool:
	return _call_runtime("setEntryVisible", [enable])


func momentOpen() -> bool:
	return _call_runtime("momentOpen")


func initAd(mediaId: Variant, mediaName: Variant, mediaKey: Variant) -> bool:
	return _call_runtime("adnInit", [mediaId, mediaName, mediaKey])


func initRewardVideoAd(spaceId: Variant, rewardName: Variant, extraInfo: Variant, userId: Variant) -> bool:
	return _call_runtime("initRewardVideoAd", [spaceId, rewardName, extraInfo, userId])


func showRewardVideoAd() -> bool:
	return _call_runtime("showRewardVideoAd")
