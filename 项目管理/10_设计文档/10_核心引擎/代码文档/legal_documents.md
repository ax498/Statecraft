# legal_documents 代码说明

**版本**：v0.1.1-2  
**最后更新**：2026-03-28  
**路径**：`scripts/data/legal_documents.gd`  
**类型**：RefCounted 文本数据脚本

---

## 主要逻辑

为移动端导出提供《用户协议》《隐私政策》的内置兜底文案。主菜单优先读取 `resources/legal/*.txt`，若导出包未包含原始 txt 或运行时无法读取，则回退到本脚本中的内置文本，保证协议弹窗始终可显示。

---

## 核心方法

| 方法 | 功能 | 实现 |
|------|------|------|
| `get_all_documents()` | 返回全部兜底文案 | 以 `user_agreement`、`privacy_policy` 为 key 返回文本 Dictionary |

---

## 技术索引

- 核心脚本：`scripts/data/legal_documents.gd`
- 关键常量：`USER_AGREEMENT_KEY`、`PRIVACY_POLICY_KEY`
- 文案来源：`USER_AGREEMENT_CONTENT`、`PRIVACY_POLICY_CONTENT`
