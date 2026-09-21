# 可复现故障夹具

`samples/incidents/` 保存仓库随附的三组固定输入。它们用于人工查看和回归测试，主机名、
服务名、进程号和指标值均为虚构数据；时间、事件 ID 和资源名在每次运行中保持不变。

## 场景与可观察结果

| 场景 | 输入文件 | 预期观察 |
| --- | --- | --- |
| `config-change` | `changes.jsonl`、`health.log` | `config-001` 在 `09:00:00Z` 将连接池从 40 调为 4；`09:00:40Z` 健康检查失败，`config-002` 回滚后 `09:02:30Z` 恢复。 |
| `service-crash` | `app.log`、`process-events.jsonl` | `fatal_allocation_failure` 后，`proc-001` 记录退出码 137，随后 `proc-002`、`proc-003` 记录重启和新进程。 |
| `performance-degradation` | `metrics.jsonl`、`gateway.log` | `metric-002` 的 P95 从 180ms 升到 1450ms，随后网关记录超时，`14:27:05Z` 恢复。 |

这里的“预期观察”只描述文件中直接出现的事实。分析图可以生成候选关系，但不会把时间先后写成根因结论。

## 文件约定

- `case.json` 提供 `case_id`、标题、固定 UTC 的 `collected_at` 和证据文件索引。`evidence` 是目录索引，不是完整性清单。
- JSONL 每行是一个完整对象，使用 `event_id`、`timestamp`、`source`、`severity`、`kind`、`resource`、`message` 和 `attributes`。
- 纯文本日志使用 `<timestamp> <severity> <message>` 布局；消息中的 `key=value` 保留在原始文本中。
- 缺失字段不会被夹具说明或适配器自动猜测。旧版直接导入测试使用 `JsonlEventMapping`，当前跨 Schema 测试使用 `JsonlMappingProfile` 生成 `CanonicalEvent`。

## 如何复核

根目录的 `e2e_test.mbt` 和 `cross_schema_test.mbt` 使用与这里一致的固定数据；
测试刻意内联输入，避免核心库引入主机文件 I/O，而这些文件保留为人可读的复核材料。
在仓库根目录运行 `moon test` 可执行完整测试套件。

## 边界

夹具不代表真实生产数据，也不包含采集凭据。修改输入后，应重新执行完整性校验并检查证据引用；
报告中的来源、时间窗口和资源关系都应回到这些原始行复核。
