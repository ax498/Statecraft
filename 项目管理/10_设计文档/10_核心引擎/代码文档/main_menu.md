# main_menu 代码说明

**版本**：v0.1.1-2  
**最后更新**：2026-03-28  
**路径**：`scenes/main/main_menu.gd`  
**类型**：Control 场景脚本（主菜单）

---

## 主要逻辑

主菜单负责多级入口切换：主界面 → 模式选择（论策/演兵）→ 对决；同时承载设置面板、Mod 管理面板、TapTap 登录结果处理，以及登录页的《用户协议》《隐私政策》提示与弹窗展示。法律文档读取同时兼容 `res://` 与全局路径，并配合导出配置包含 `resources/legal/*.txt`；若移动端导出包仍未带入原始 txt，则回退到 `scripts/data/legal_documents.gd` 的内置文案，避免出现“内容暂时无法加载”。

---

## 核心方法

| 方法 | 功能 | 实现 |
|------|------|------|
| `_load_legal_documents()` | 加载协议文本 | 从 `resources/legal/` 读取用户协议与隐私政策，供弹窗展示 |
| `_setup_agreement_notice()` | 配置登录提示 | 设置开始界面“登录即表示已阅读并同意……”富文本提示，并挂接可点击协议入口 |
| `_show_legal_dialog(doc_key)` | 显示协议弹窗 | 根据点击类型切换标题与正文，展示可滚动内容和底部确认按钮 |
| `_on_lunce_pressed()` | 论策模式 | 断开联机，设置 `is_lunce_mode`，重置 Manager，跳转 battle_test |
| `_on_yanbing_pressed()` | 演兵模式 | 弹出 `_show_yanbing_network_dialog()` |
| `_show_yanbing_network_dialog()` | 演兵对话框 | 动态创建 IP/端口输入、创建/加入按钮，连接成功后主机 peer_connected 跳转、客户端 connection_succeeded 等待 |
| `_populate_setting_buttons()` | 设置按钮 | 根据 ModManager 数据生成 Mod 开关、模板生成、浏览目录等 |
| `_on_mod_verify_failed(message)` | Mod 校验失败 | 客户端收到时显示错误并断开 |

---

## 技术索引

- 核心脚本：`scenes/main/main_menu.gd`
- 协议资源：`resources/legal/user_agreement.txt`、`resources/legal/privacy_policy.txt`
- 移动端兜底：`scripts/data/legal_documents.gd`
- 关键节点：`StartGameBtn`、`AgreementNoticeText`、`AgreementDialog`、`SettingPanel`、`ModDetailPanel`
- 关键方法：`_connect_signals()`、`_show_legal_dialog()`、`_show_lunce_player_count_dialog()`、`_show_yanbing_network_dialog()`、`_populate_mod_panel()`
- 枚举：`View { MAIN_MENU, MODE_SELECT }`
