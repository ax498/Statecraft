## 主菜单逻辑
extends Control

enum View { MAIN_MENU, MODE_SELECT }

const LegalDocuments = preload("res://scripts/data/legal_documents.gd")
const USER_AGREEMENT_KEY: String = "user_agreement"
const PRIVACY_POLICY_KEY: String = "privacy_policy"
const USER_AGREEMENT_PATH: String = "res://resources/legal/user_agreement.txt"
const PRIVACY_POLICY_PATH: String = "res://resources/legal/privacy_policy.txt"
const TAPTAP_LOGIN_SUCCESS_CODE: int = 200
const COMPLIANCE_LOGIN_SUCCESS: int = 500
const COMPLIANCE_EXITED: int = 1000
const COMPLIANCE_SWITCH_ACCOUNT: int = 1001
const COMPLIANCE_PERIOD_RESTRICT: int = 1030
const COMPLIANCE_DURATION_LIMIT: int = 1050
const COMPLIANCE_OPEN_ALERT_TIP: int = 1095
const COMPLIANCE_AGE_LIMIT: int = 1100
const COMPLIANCE_TOKEN_EXPIRED: int = 9001
const COMPLIANCE_REAL_NAME_STOP: int = 9002
const COMPLIANCE_INVALID_CLIENT_OR_NETWORK_ERROR: int = 1200
const TAPTAP_LOGIN_TIMEOUT_SECONDS: float = 15.0
const TAPTAP_COMPLIANCE_TIMEOUT_SECONDS: float = 15.0

var _current_view: View = View.MAIN_MENU
var _button_style: StyleBoxFlat
var _legal_documents: Dictionary = {}
var _taptap_login_in_progress: bool = false
var _anti_addiction_check_in_progress: bool = false
var _taptap_login_request_id: int = 0
var _anti_addiction_request_id: int = 0

@onready var main_menu_container: Control = $UILayer/MainMenuContainer
@onready var mode_select_container: Control = $UILayer/ModeSelectContainer
@onready var start_game_btn: Button = $UILayer/MainMenuContainer/VBox/StartGameBtn
@onready var agreement_notice: RichTextLabel = $UILayer/MainMenuContainer/VBox/AgreementNotice/MarginContainer/AgreementNoticeText
@onready var lunce_btn: Button = $UILayer/ModeSelectContainer/VBox/LunceBtn
@onready var yanbing_btn: Button = $UILayer/ModeSelectContainer/VBox/YanbingBtn
@onready var setting_btn: Button = $UILayer/SettingBtn
@onready var setting_panel: PopupPanel = $UILayer/SettingPanel
@onready var setting_button_container: VBoxContainer = $UILayer/SettingPanel/MarginContainer/VBox/ButtonContainer
@onready var legal_dialog: Control = $UILayer/AgreementDialog
@onready var legal_title_label: Label = $UILayer/AgreementDialog/MarginContainer/Panel/MarginContainer/VBox/TitleLabel
@onready var legal_content_label: RichTextLabel = $UILayer/AgreementDialog/MarginContainer/Panel/MarginContainer/VBox/ContentLabel
@onready var legal_confirm_btn: Button = $UILayer/AgreementDialog/MarginContainer/Panel/MarginContainer/VBox/ConfirmBtn
@onready var mod_detail_panel: Control = $ModLayer/ModDetailPanel
@onready var mod_list: VBoxContainer = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/ScrollContainer/ModList
@onready var mod_detail_label: Label = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/DetailLabel
@onready var mod_override_label: Label = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/OverrideLabel
@onready var mod_restart_hint: Label = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/RestartHintLabel
@onready var mod_close_btn: Button = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/CloseBtn
@onready var mod_gen_template_btn: Button = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/GenTemplateBtn
@onready var mod_browse_dir_btn: Button = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/BrowseDirBtn
@onready var mod_refresh_btn: Button = $ModLayer/ModDetailPanel/CenterContainer/Panel/VBox/RefreshModsBtn

var mod_manager: Node


func _ready() -> void:
	mod_manager = get_node("/root/ModManager")
	_button_style = _make_btn_style()
	_load_legal_documents()
	_setup_agreement_notice()
	_apply_clean_agreement_notice()
	_connect_signals()
	## Release focus when the settings popup closes.
	if is_instance_valid(setting_panel):
		if not setting_panel.popup_hide.is_connected(_on_setting_popup_hide):
			setting_panel.popup_hide.connect(_on_setting_popup_hide)
	mod_detail_panel.process_mode = Node.PROCESS_MODE_DISABLED
	# Restore mode-select state when returning from battle.
	var bm: Node = get_node("/root/BattleManager")
	if bm.get("return_to_mode_select"):
		bm.set("return_to_mode_select", false)
		main_menu_container.visible = false
		mode_select_container.visible = true
		_current_view = View.MODE_SELECT
		setting_btn.visible = true


func _connect_signals() -> void:
	start_game_btn.pressed.connect(_on_taptap_login_pressed)
	agreement_notice.meta_clicked.connect(_on_agreement_notice_meta_clicked)
	legal_confirm_btn.pressed.connect(_on_legal_confirm_pressed)
	var taptap: Node = get_node_or_null("/root/GodotTapTap")
	if taptap != null:
		if taptap.has_signal("onLoginResult") and not taptap.onLoginResult.is_connected(_on_taptap_login_result):
			taptap.onLoginResult.connect(_on_taptap_login_result)
		if taptap.has_signal("onAntiAddictionCallback") and not taptap.onAntiAddictionCallback.is_connected(_on_taptap_anti_addiction_result):
			taptap.onAntiAddictionCallback.connect(_on_taptap_anti_addiction_result)
	lunce_btn.pressed.connect(_on_lunce_pressed)
	yanbing_btn.pressed.connect(_on_yanbing_pressed)
	setting_btn.pressed.connect(_on_setting_pressed)
	mod_close_btn.pressed.connect(_on_mod_close_pressed)
	mod_gen_template_btn.pressed.connect(_on_gen_template_pressed)
	mod_browse_dir_btn.pressed.connect(_on_browse_dir_pressed)
	mod_refresh_btn.pressed.connect(_on_mod_refresh_pressed)
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_signal("mod_verify_failed"):
		nm.mod_verify_failed.connect(_on_mod_verify_failed)


func _load_legal_documents() -> void:
	var fallback_documents: Dictionary = LegalDocuments.get_all_documents()
	_legal_documents = {
		USER_AGREEMENT_KEY: {
			"title": "《用户协议》",
			"content": _read_legal_document(
				USER_AGREEMENT_PATH,
				fallback_documents.get(USER_AGREEMENT_KEY, "《用户协议》加载失败。")
			)
		},
		PRIVACY_POLICY_KEY: {
			"title": "《隐私政策》",
			"content": _read_legal_document(
				PRIVACY_POLICY_PATH,
				fallback_documents.get(PRIVACY_POLICY_KEY, "《隐私政策》加载失败。")
			)
		}
	}

func _apply_clean_agreement_notice() -> void:
	agreement_notice.bbcode_enabled = true
	agreement_notice.text = "[center]登录即表示已阅读并同意 [url=%s][color=#7CC7FF]《用户协议》[/color][/url] 和 [url=%s][color=#7CC7FF]《隐私政策》[/color][/url][/center]" % [USER_AGREEMENT_KEY, PRIVACY_POLICY_KEY]

func _read_legal_document(path: String, fallback: String) -> String:
	if not fallback.strip_edges().is_empty():
		return fallback
	var candidate_paths: Array[String] = [path, ProjectSettings.globalize_path(path)]
	for candidate: String in candidate_paths:
		if candidate.is_empty():
			continue
		var file: FileAccess = FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var content: String = file.get_as_text()
		if not content.strip_edges().is_empty():
			return content
	push_warning("[MainMenu] 无法读取协议文档: %s" % path)
	return fallback


func _setup_agreement_notice() -> void:
	agreement_notice.bbcode_enabled = true
	agreement_notice.text = "[center]登录即表示已阅读并同意 [url=%s][color=#7CC7FF]《用户协议》[/color][/url] 和 [url=%s][color=#7CC7FF]《隐私政策》[/color][/url][/center]" % [USER_AGREEMENT_KEY, PRIVACY_POLICY_KEY]


func _on_agreement_notice_meta_clicked(meta: Variant) -> void:
	var doc_key: String = str(meta)
	_show_legal_dialog(doc_key)


func _show_legal_dialog(doc_key: String) -> void:
	var info: Dictionary = _legal_documents.get(doc_key, {})
	if info.is_empty():
		return
	legal_title_label.text = str(info.get("title", "协议文档"))
	legal_content_label.text = str(info.get("content", ""))
	legal_dialog.visible = true
	call_deferred("_reset_legal_scroll")

func _reset_legal_scroll() -> void:
	if is_instance_valid(legal_content_label):
		legal_content_label.scroll_to_line(0)


func _on_legal_confirm_pressed() -> void:
	legal_dialog.visible = false
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.gui_release_focus()


func _get_game_logger() -> Node:
	return get_node_or_null("/root/GameLogger")


func _log_record(action: String, data: Variant = "") -> void:
	var gl: Node = _get_game_logger()
	if gl and gl.has_method("record"):
		gl.record("TapTapFlow", action, data)
	else:
		print("[TapTapFlow] %s %s" % [action, str(data)])


func _log_warn(action: String, data: Variant = "") -> void:
	var gl: Node = _get_game_logger()
	if gl and gl.has_method("warn"):
		gl.warn("TapTapFlow", action, data)
	else:
		push_warning("[TapTapFlow] %s %s" % [action, str(data)])


func _get_taptap_bridge() -> Node:
	return get_node_or_null("/root/GodotTapTap")


func _get_taptap_runtime_error(bridge: Node = null) -> String:
	var target: Node = bridge
	if target == null:
		target = _get_taptap_bridge()
	if target != null and target.has_method("get_last_error"):
		return str(target.call("get_last_error"))
	return ""


func _get_taptap_issue_message(default_message: String, bridge: Node = null) -> String:
	var reason: String = _get_taptap_runtime_error(bridge).strip_edges()
	if reason.is_empty():
		return default_message
	return "%s\n\nReason: %s" % [default_message, reason]


func _summarize_taptap_payload(payload: Variant) -> String:
	if payload == null:
		return ""
	var text: String = str(payload).replace("\r", " ").replace("\n", " ").strip_edges()
	if text.length() > 280:
		text = "%s..." % text.substr(0, 280)
	return text


func _schedule_taptap_login_timeout(request_id: int) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var timer: SceneTreeTimer = tree.create_timer(TAPTAP_LOGIN_TIMEOUT_SECONDS)
	timer.timeout.connect(_on_taptap_login_timeout.bind(request_id), CONNECT_ONE_SHOT)


func _schedule_taptap_compliance_timeout(request_id: int) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var timer: SceneTreeTimer = tree.create_timer(TAPTAP_COMPLIANCE_TIMEOUT_SECONDS)
	timer.timeout.connect(_on_taptap_compliance_timeout.bind(request_id), CONNECT_ONE_SHOT)


func _start_taptap_login_request() -> bool:
	var bridge: Node = _get_taptap_bridge()
	if bridge == null or not bridge.has_method("tap_login"):
		_log_warn("login_request_bridge_missing")
		return false
	var started: bool = bool(bridge.call("tap_login"))
	if not started:
		_log_warn("login_request_start_failed", {"reason": _get_taptap_runtime_error(bridge)})
		return false
	_taptap_login_in_progress = true
	_taptap_login_request_id += 1
	_log_record("login_request_started", {"request_id": _taptap_login_request_id})
	_refresh_start_game_btn_state()
	_schedule_taptap_login_timeout(_taptap_login_request_id)
	return true


func _on_taptap_login_timeout(request_id: int) -> void:
	if request_id != _taptap_login_request_id or not _taptap_login_in_progress:
		return
	_taptap_login_in_progress = false
	_log_warn("login_timeout", {"request_id": request_id, "seconds": TAPTAP_LOGIN_TIMEOUT_SECONDS, "reason": _get_taptap_runtime_error()})
	_refresh_start_game_btn_state()
	_show_message_dialog(
		"Login timeout",
		_get_taptap_issue_message(
			"TapTap login did not return within %d seconds.\n\nPlease check whether the TapTap app can open normally, whether the network is available, and whether the APK signing certificate MD5 has been added in the TapTap developer console."
			% int(TAPTAP_LOGIN_TIMEOUT_SECONDS)
		)
	)


func _on_taptap_compliance_timeout(request_id: int) -> void:
	if request_id != _anti_addiction_request_id or not _anti_addiction_check_in_progress:
		return
	_anti_addiction_check_in_progress = false
	_log_warn("compliance_timeout", {"request_id": request_id, "seconds": TAPTAP_COMPLIANCE_TIMEOUT_SECONDS, "reason": _get_taptap_runtime_error()})
	_refresh_start_game_btn_state()
	_show_message_dialog(
		"Compliance timeout",
		_get_taptap_issue_message(
			"TapTap anti-addiction verification did not return within %d seconds. Please check the network connection and TapTap runtime status, then try again."
			% int(TAPTAP_COMPLIANCE_TIMEOUT_SECONDS)
		)
	)


func _on_taptap_login_pressed() -> void:
	_log_record("login_button_pressed", {"android": OS.has_feature("android")})
	if _taptap_login_in_progress or _anti_addiction_check_in_progress:
		_log_warn("login_button_ignored_busy", {"login_in_progress": _taptap_login_in_progress, "compliance_in_progress": _anti_addiction_check_in_progress})
		return
	if not OS.has_feature("android") and not Engine.has_singleton("GodotTapTapSDK"):
		_log_record("login_skipped_non_android_no_sdk")
		_go_to_mode_select()
		return
	if _start_taptap_login_request():
		return
	if OS.has_feature("android"):
		_log_warn("login_unavailable_android", {"reason": _get_taptap_runtime_error()})
		_show_message_dialog(
			"Login unavailable",
			_get_taptap_issue_message("TapTap login could not be started on this Android build.")
		)
		return
	if not Engine.has_singleton("GodotTapTapSDK"):
		_log_record("login_skipped_non_android_no_engine_singleton")
		_go_to_mode_select()
		return
	_log_warn("login_unavailable_runtime", {"reason": _get_taptap_runtime_error()})
	_show_message_dialog(
		"Login unavailable",
		_get_taptap_issue_message("TapTap login could not be started in the current runtime.")
	)


func _on_taptap_login_result(code: int, payload: Variant) -> void:
	_log_record("login_callback", {"code": code, "payload": _summarize_taptap_payload(payload)})
	_taptap_login_in_progress = false
	_refresh_start_game_btn_state()
	if code == TAPTAP_LOGIN_SUCCESS_CODE:
		_log_record("login_success", {"android": OS.has_feature("android")})
		if OS.has_feature("android"):
			_start_anti_addiction_check()
		else:
			_go_to_mode_select()
		return
	_log_warn("login_failed", {"code": code, "payload": _summarize_taptap_payload(payload)})
	var message: String = "TapTap login failed or was cancelled.\n\nCallback code: %d" % code
	var details: String = _summarize_taptap_payload(payload)
	if not details.is_empty():
		message += "\nDetails: %s" % details
	_show_message_dialog("Login failed", message)

func _on_taptap_anti_addiction_result(code: int) -> void:
	_log_record("compliance_callback", {"code": code})
	if code == COMPLIANCE_OPEN_ALERT_TIP:
		_log_record("compliance_alert_tip", {"code": code})
		return
	if not _anti_addiction_check_in_progress:
		_log_warn("compliance_callback_ignored_not_in_progress", {"code": code})
		return
	_anti_addiction_check_in_progress = false
	_refresh_start_game_btn_state()
	match code:
		COMPLIANCE_LOGIN_SUCCESS:
			_log_record("compliance_passed", {"code": code})
			_go_to_mode_select()
		COMPLIANCE_EXITED:
			_log_warn("compliance_exited", {"code": code})
			_show_message_dialog("Compliance incomplete", "The real-name/compliance flow was exited before completion.")
		COMPLIANCE_SWITCH_ACCOUNT:
			_log_warn("compliance_switch_account", {"code": code})
			_show_message_dialog("Account switched", "The TapTap account changed during compliance verification. Please log in again.")
		COMPLIANCE_PERIOD_RESTRICT:
			_log_warn("compliance_period_restrict", {"code": code})
			_show_message_dialog("Playtime restricted", "The current account is outside the allowed play period.")
		COMPLIANCE_DURATION_LIMIT:
			_log_warn("compliance_duration_limit", {"code": code})
			_show_message_dialog("Playtime limit reached", "The current account has reached today's allowed playtime.")
		COMPLIANCE_AGE_LIMIT:
			_log_warn("compliance_age_limit", {"code": code})
			_show_message_dialog("Age restricted", "The current account is not allowed to enter the game due to age restrictions.")
		COMPLIANCE_TOKEN_EXPIRED:
			_log_warn("compliance_token_expired", {"code": code})
			_show_message_dialog("Session expired", "TapTap login or compliance credentials expired. Please log in again.")
		COMPLIANCE_REAL_NAME_STOP:
			_log_warn("compliance_real_name_stop", {"code": code})
			_show_message_dialog("Verification cancelled", "Real-name or compliance verification was cancelled before completion.")
		COMPLIANCE_INVALID_CLIENT_OR_NETWORK_ERROR:
			_log_warn("compliance_invalid_client_or_network", {"code": code})
			_show_message_dialog("Compliance failed", "Compliance verification failed because the build or network is unavailable.")
		_:
			_log_warn("compliance_unknown_code", {"code": code})
			_show_message_dialog("Compliance failed", "Unknown compliance callback code: %d." % code)

func _start_anti_addiction_check() -> void:
	var bridge: Node = _get_taptap_bridge()
	if bridge == null or not bridge.has_method("quickCheck"):
		_log_warn("compliance_start_bridge_missing")
		_refresh_start_game_btn_state()
		_show_message_dialog(
			"Compliance unavailable",
			_get_taptap_issue_message("TapTap runtime is missing, so compliance verification cannot start.", bridge)
		)
		return
	var started: bool = bool(bridge.call("quickCheck"))
	if not started:
		_log_warn("compliance_start_failed", {"reason": _get_taptap_runtime_error(bridge)})
		_refresh_start_game_btn_state()
		_show_message_dialog(
			"Compliance unavailable",
			_get_taptap_issue_message("TapTap runtime failed to start anti-addiction verification.", bridge)
		)
		return
	_anti_addiction_check_in_progress = true
	_anti_addiction_request_id += 1
	_log_record("compliance_started", {"request_id": _anti_addiction_request_id})
	_refresh_start_game_btn_state()
	_schedule_taptap_compliance_timeout(_anti_addiction_request_id)

func _is_taptap_runtime_available() -> bool:
	var bridge: Node = _get_taptap_bridge()
	if bridge == null:
		_log_warn("runtime_check_bridge_missing")
		return false
	if bridge.has_method("is_runtime_ready"):
		var ready: bool = bool(bridge.call("is_runtime_ready"))
		_log_record("runtime_check", {"ready": ready, "reason": _get_taptap_runtime_error(bridge)})
		return ready
	var fallback_ready: bool = Engine.has_singleton("GodotTapTapSDK")
	_log_record("runtime_check_fallback", {"ready": fallback_ready})
	return fallback_ready


func _refresh_start_game_btn_state() -> void:
	start_game_btn.disabled = _taptap_login_in_progress or _anti_addiction_check_in_progress


func _show_message_dialog(title: String, message: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	call_deferred("_popup_centered_deferred", dialog)


func _popup_centered_deferred(dialog: AcceptDialog) -> void:
	if is_instance_valid(dialog) and is_inside_tree():
		dialog.popup_centered()


func _go_to_mode_select() -> void:
	_log_record("enter_mode_select")
	main_menu_container.visible = false
	mode_select_container.visible = true
	_current_view = View.MODE_SELECT
	setting_btn.visible = true


func _on_setting_popup_hide() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.gui_release_focus()


func _on_lunce_pressed() -> void:
	if is_instance_valid(setting_panel):
		setting_panel.hide()
	_show_lunce_player_count_dialog()


func _show_lunce_player_count_dialog() -> void:
	var top_layer: CanvasLayer = CanvasLayer.new()
	top_layer.layer = 100
	add_child(top_layer)
	var overlay: Control = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(bg)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 160)
	var ps: StyleBoxFlat = StyleBoxFlat.new()
	ps.bg_color = Color(0.96, 0.96, 0.96, 1)
	ps.border_width_left = 1
	ps.border_width_top = 1
	ps.border_width_right = 1
	ps.border_width_bottom = 1
	ps.border_color = Color(0.3, 0.3, 0.3, 1)
	ps.corner_radius_top_left = 4
	ps.corner_radius_top_right = 4
	ps.corner_radius_bottom_right = 4
	ps.corner_radius_bottom_left = 4
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Lunce - Player Count"
	title.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl: Label = Label.new()
	lbl.text = "Players (2-8):"
	lbl.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	row.add_child(lbl)
	var spin: SpinBox = SpinBox.new()
	spin.custom_minimum_size = Vector2(70, 36)
	spin.min_value = 2
	spin.max_value = 8
	spin.value = 2
	spin.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	row.add_child(spin)
	vbox.add_child(row)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	var confirm_btn: Button = _create_setting_button("Confirm")
	confirm_btn.pressed.connect(func() -> void:
		var cm: Node = get_node("/root/CardManager")
		var bm: Node = get_node("/root/BattleManager")
		var nm: Node = get_node_or_null("/root/NetworkManager")
		if nm != null and nm.has_method("disconnect_peer"):
			nm.call("disconnect_peer")
		bm.set("is_lunce_mode", true)
		var pc: int = clampi(int(spin.value), 2, 8)
		bm.set("player_count", pc)
		if bm.has_method("init_duel"):
			bm.call("init_duel")
		else:
			cm.reset_for_new_game()
			bm.reset_to_start()
		top_layer.queue_free()
		get_tree().change_scene_to_file("res://scenes/battle/battle_test.tscn")
	)
	btn_row.add_child(confirm_btn)
	var cancel_btn: Button = _create_setting_button("Cancel")
	cancel_btn.pressed.connect(top_layer.queue_free)
	btn_row.add_child(cancel_btn)
	vbox.add_child(btn_row)

	top_layer.add_child(overlay)

func _on_yanbing_pressed() -> void:
	if is_instance_valid(setting_panel):
		setting_panel.hide()
	_show_yanbing_network_dialog()


func _show_yanbing_network_dialog() -> void:
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm == null:
		push_error("[MainMenu] NetworkManager is not available, so Yanbing mode cannot start.")
		return
	var overlay: Control = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(bg)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var dialog: PanelContainer = PanelContainer.new()
	dialog.custom_minimum_size = Vector2(340, 380)
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.96, 0.96, 0.96, 1)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.3, 0.3, 1)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.corner_radius_bottom_left = 4
	dialog.add_theme_stylebox_override("panel", panel_style)
	center.add_child(dialog)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	dialog.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title_label: Label = Label.new()
	title_label.text = "Yanbing - LAN Battle"
	title_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	var player_count_row: HBoxContainer = HBoxContainer.new()
	player_count_row.add_theme_constant_override("separation", 8)
	var pc_label: Label = Label.new()
	pc_label.text = "Players:"
	pc_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	player_count_row.add_child(pc_label)
	var pc_spin: SpinBox = SpinBox.new()
	pc_spin.custom_minimum_size = Vector2(60, 32)
	pc_spin.min_value = 2
	pc_spin.max_value = 8
	pc_spin.value = 2
	pc_spin.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	player_count_row.add_child(pc_spin)
	vbox.add_child(player_count_row)

	var ip_label: Label = Label.new()
	ip_label.text = "Host IP (for join):"
	ip_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	vbox.add_child(ip_label)

	var ip_edit: LineEdit = LineEdit.new()
	ip_edit.placeholder_text = "Host IP, e.g. 192.168.1.100"
	ip_edit.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(ip_edit)

	var port_label: Label = Label.new()
	port_label.text = "Port:"
	port_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	vbox.add_child(port_label)

	var port_edit: LineEdit = LineEdit.new()
	port_edit.text = "9999"
	port_edit.placeholder_text = "9999"
	port_edit.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(port_edit)

	var status_label: Label = Label.new()
	status_label.text = ""
	status_label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 24
	vbox.add_child(status_label)

	var start_btn: Button = _create_setting_button("Start Game")
	start_btn.visible = false
	start_btn.disabled = true
	start_btn.pressed.connect(func() -> void:
		var pc: int = clampi(int(pc_spin.value), 2, 8)
		nm.start_yanbing_game(pc)
		overlay.queue_free()
	)
	vbox.add_child(start_btn)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var create_btn: Button = _create_setting_button("Create Room")
	create_btn.custom_minimum_size.x = 90
	create_btn.pressed.connect(func() -> void:
		var port: int = int(port_edit.text) if port_edit.text.is_valid_int() else 9999
		var err: Error = nm.create_game(port)
		if err == OK:
			var lan_ip: String = nm.get_local_lan_ip() if nm.has_method("get_local_lan_ip") else ""
			if not lan_ip.is_empty():
				status_label.text = "Room created. Peer should join %s:%d" % [lan_ip, port]
			else:
				status_label.text = "Room created. Waiting for peer connection..."
			status_label.add_theme_color_override("font_color", Color(0, 0.6, 0, 1))
			start_btn.visible = true
		else:
			status_label.text = "Failed to create room. The port may already be in use."
			status_label.add_theme_color_override("font_color", Color(0.8, 0, 0, 1))
	)
	btn_row.add_child(create_btn)

	var join_btn: Button = _create_setting_button("Join Room")
	join_btn.custom_minimum_size.x = 90
	join_btn.pressed.connect(func() -> void:
		var ip: String = ip_edit.text.strip_edges()
		if ip.is_empty():
			status_label.text = "Please enter the host IP first."
			status_label.add_theme_color_override("font_color", Color(0.8, 0, 0, 1))
			return
		var port: int = int(port_edit.text) if port_edit.text.is_valid_int() else 9999
		var err: Error = nm.join_game(ip, port)
		if err == OK:
			status_label.text = "Connecting..."
			status_label.add_theme_color_override("font_color", Color(0, 0.6, 0, 1))
		else:
			status_label.text = "Failed to connect. Check the IP, port, and LAN connection."
			status_label.add_theme_color_override("font_color", Color(0.8, 0, 0, 1))
	)
	btn_row.add_child(join_btn)

	var cb_succeeded: Callable = _on_yanbing_connection_succeeded.bind(status_label)
	var cb_failed: Callable = _on_yanbing_connection_failed.bind(status_label)
	var cb_peer: Callable = _on_yanbing_peer_connected.bind(status_label, overlay)
	var cb_host_can_start: Callable = func() -> void:
		if is_instance_valid(start_btn):
			start_btn.disabled = false
			if is_instance_valid(status_label):
				status_label.text = "Peer connected. Tap Start Game to continue."
				status_label.add_theme_color_override("font_color", Color(0, 0.6, 0, 1))
	nm.connection_succeeded.connect(cb_succeeded)
	nm.connection_failed.connect(cb_failed)
	nm.peer_connected.connect(cb_peer)
	nm.host_can_start.connect(cb_host_can_start)

	var close_yanbing: Callable = func() -> void:
		if nm.opponent_id == -1:
			nm.disconnect_peer()
		nm.connection_succeeded.disconnect(cb_succeeded)
		nm.connection_failed.disconnect(cb_failed)
		nm.peer_connected.disconnect(cb_peer)
		if nm.host_can_start.is_connected(cb_host_can_start):
			nm.host_can_start.disconnect(cb_host_can_start)
		overlay.queue_free()

	var close_btn: Button = _create_setting_button("Close")
	close_btn.pressed.connect(close_yanbing)
	btn_row.add_child(close_btn)

	$UILayer.add_child(overlay)

func _on_yanbing_connection_succeeded(status_label: Label) -> void:
	if is_instance_valid(status_label):
		status_label.text = "Joined room successfully. Waiting for the host to start the game..."
		status_label.add_theme_color_override("font_color", Color(0, 0.6, 0, 1))


func _on_yanbing_connection_failed(status_label: Label) -> void:
	if is_instance_valid(status_label):
		status_label.text = "Connection failed. Check the host IP and port."
		status_label.add_theme_color_override("font_color", Color(0.8, 0, 0, 1))


func _on_mod_verify_failed(message: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Unable to join"
	dialog.dialog_text = "Mod verification failed and the room cannot be joined.\n\nPlease make sure the same mods and versions are installed on both devices.\n\n%s" % message
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	call_deferred("_popup_mod_verify_failed", dialog)

func _popup_mod_verify_failed(dialog: AcceptDialog) -> void:
	if is_instance_valid(dialog) and is_inside_tree():
		dialog.popup_centered()


func _set_yanbing_connected_status(status_label: Label) -> void:
	if is_instance_valid(status_label):
		status_label.text = "房间连接成功，等待房主开始游戏..."
		status_label.add_theme_color_override("font_color", Color(0, 0.6, 0, 1))


func _on_yanbing_peer_connected(_peer_id: int, status_label: Label, _overlay: Control) -> void:
	if is_instance_valid(status_label):
		call_deferred("_set_yanbing_connected_status", status_label)
	if is_instance_valid(status_label):
		status_label.text = "房间连接成功，等待房主开始游戏..."
		status_label.add_theme_color_override("font_color", Color(0, 0.6, 0, 1))


func _on_setting_pressed() -> void:
	_populate_setting_buttons()
	call_deferred("_show_setting_panel")


func _show_setting_panel() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(setting_panel) and setting_panel.is_inside_tree():
		setting_panel.size = Vector2i(240, 200)
		setting_panel.popup_centered()


func _populate_setting_buttons() -> void:
	var to_clear: Array = setting_button_container.get_children()
	for c in to_clear:
		if is_instance_valid(c):
			c.free()

	var mod_btn: Button = _create_setting_button("Mod Extensions")
	mod_btn.pressed.connect(_on_mod_btn_pressed)
	setting_button_container.add_child(mod_btn)

	match _current_view:
		View.MAIN_MENU:
			var back_btn: Button = _create_setting_button("Back")
			back_btn.pressed.connect(_on_back_pressed)
			setting_button_container.add_child(back_btn)
			var quit_btn: Button = _create_setting_button("Quit Game")
			quit_btn.pressed.connect(_on_quit_pressed)
			setting_button_container.add_child(quit_btn)
		View.MODE_SELECT:
			var quit_btn: Button = _create_setting_button("Quit Game")
			quit_btn.pressed.connect(_on_quit_pressed)
			setting_button_container.add_child(quit_btn)

func _create_setting_button(text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.2, 0.2, 0.2, 1))
	btn.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.6, 1))
	btn.add_theme_stylebox_override("normal", _button_style)
	btn.add_theme_stylebox_override("hover", _button_style)
	btn.add_theme_stylebox_override("disabled", _button_style)
	btn.add_theme_stylebox_override("pressed", _button_style)
	return btn


func _on_mod_btn_pressed() -> void:
	setting_panel.hide()
	_populate_mod_panel()
	mod_detail_panel.visible = true
	mod_detail_panel.process_mode = Node.PROCESS_MODE_INHERIT
	mod_detail_panel.modulate.a = 0.0
	if is_inside_tree() and mod_detail_panel.is_inside_tree():
		var tween: Tween = create_tween()
		tween.tween_property(mod_detail_panel, "modulate:a", 1.0, 0.2)
	else:
		mod_detail_panel.modulate.a = 1.0


func _on_mod_close_pressed() -> void:
	mod_detail_panel.visible = false
	mod_detail_panel.process_mode = Node.PROCESS_MODE_DISABLED
	# Reopen the settings popup after closing the Mod panel.


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_back_pressed() -> void:
	setting_panel.hide()
	# Return from mode select to the main menu.
	if _current_view == View.MODE_SELECT:
		mode_select_container.visible = false
		main_menu_container.visible = true
		_current_view = View.MAIN_MENU
		setting_btn.visible = false


func _populate_mod_panel() -> void:
	mod_restart_hint.visible = false
	for c in mod_list.get_children():
		c.queue_free()
	var mod_style: StyleBoxFlat = UIHelper.make_mod_btn_style()
	var details: Array = mod_manager.mod_details
	if details.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "No mods are currently loaded."
		empty_label.add_theme_color_override("font_color", Color(0.294, 0.294, 0.29, 1))
		empty_label.add_theme_font_size_override("font_size", 14)
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mod_list.add_child(empty_label)
		mod_detail_label.text = "Place mod folders in the mod storage directory to load them."
	else:
		for i: int in range(details.size()):
			var info: Dictionary = details[i]
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var cb: CheckBox = CheckBox.new()
			cb.button_pressed = info.get("is_enabled", true)
			cb.add_theme_color_override("font_color", Color(0, 0, 0, 1))
			var idx: int = i
			cb.toggled.connect(_on_mod_enabled_toggled.bind(idx))
			row.add_child(cb)
			var btn: Button = Button.new()
			btn.text = "[%s] v%s - %s" % [info.get("name", "?"), info.get("version", "?"), info.get("author", "?")]
			btn.add_theme_color_override("font_color", Color(0.294, 0.294, 0.29, 1))
			btn.add_theme_color_override("font_hover_color", Color(0.2, 0.2, 0.2, 1))
			btn.add_theme_stylebox_override("normal", mod_style)
			btn.add_theme_stylebox_override("hover", mod_style)
			btn.add_theme_stylebox_override("pressed", mod_style)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_on_mod_item_pressed.bind(idx))
			row.add_child(btn)
			mod_list.add_child(row)
		mod_detail_label.text = "Select a mod above to view its details."
	var overrides: Array = mod_manager.overridden_resources
	if overrides.is_empty():
		mod_override_label.text = "Overridden resources: none"
	else:
		var paths: Array[String] = []
		for p: String in overrides:
			paths.append(p.get_file())
		mod_override_label.text = "Overridden resources: %s" % ", ".join(paths)

func _make_btn_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.941, 0.941, 0.941, 1)
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = Color(0, 0, 0, 1)
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left = 4
	s.content_margin_left = 12.0
	s.content_margin_top = 8.0
	s.content_margin_right = 12.0
	s.content_margin_bottom = 8.0
	return s


func _on_mod_enabled_toggled(enabled: bool, index: int) -> void:
	var details: Array = mod_manager.mod_details
	if index < 0 or index >= details.size():
		return
	var info: Dictionary = details[index]
	var mod_id: String = info.get("id", "")
	mod_manager.set_mod_enabled(mod_id, enabled)
	mod_manager.save_mod_config()
	mod_restart_hint.visible = true


func _on_mod_item_pressed(index: int) -> void:
	var details: Array = mod_manager.mod_details
	if index < 0 or index >= details.size():
		return
	var info: Dictionary = details[index]
	var desc: String = info.get("description", "")
	if desc.is_empty():
		desc = "No description provided."
	mod_detail_label.text = desc


func _on_gen_template_pressed() -> void:
	var path: String = mod_manager.generate_example_mod_template()
	if path != "":
		mod_manager.refresh_mod_details()
		_populate_mod_panel()
		mod_detail_label.text = "Template generated at:\n%s" % path


func _on_mod_refresh_pressed() -> void:
	mod_manager.reload_all_mods()
	_populate_mod_panel()
	mod_detail_label.text = "Mod list refreshed."


func _on_browse_dir_pressed() -> void:
	var abs_path: String = mod_manager.get_mod_storage_path_absolute()
	if OS.has_feature("android"):
		var popup: AcceptDialog = AcceptDialog.new()
		popup.title = "Mod Storage Path"
		popup.dialog_text = "Place mod folders in:\n\n%s" % abs_path
		add_child(popup)
		popup.confirmed.connect(popup.queue_free)
		call_deferred("_show_path_popup_deferred", popup)
	else:
		OS.shell_open(abs_path)


func _show_path_popup_deferred(popup: AcceptDialog) -> void:
	if not is_inside_tree():
		if is_instance_valid(popup):
			popup.queue_free()
		return
	if is_instance_valid(popup) and popup.is_inside_tree():
		popup.popup_centered()
