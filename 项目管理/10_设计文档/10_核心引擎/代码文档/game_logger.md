# GameLogger 代码说明

**路径**：`scripts/autoload/game_logger.gd`  
**类型**：Autoload 单例

---

## 主要逻辑

缓冲日志，每局保存到项目根目录 `logs/game_YYYYMMDD_HHMMSS.log`，便于排查 bug。格式：`[时间] [tag] action [data]`。

---

## 核心方法

| 方法 | 功能 | 实现 |
|------|------|------|
| `record(tag, action, data)` | 记录日志 | 拼接行，追加到 `_buffer`，超过 MAX_BUFFER 时移除首项，同时 print |
| `debug/warn/error(tag, action, data)` | 分级日志 | 调用 record，action 前加 [DEBUG]/[WARN]/[ERROR] |
| `save_session()` | 保存到文件 | 创建 logs 目录，写入 `_file_path` |
| `flush()` | 立即保存 | 调用 `save_session`，供游戏结束等关键节点调用 |
