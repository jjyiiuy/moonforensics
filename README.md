# MoonForensics

MoonForensics 是一个 MoonBit 应用服务离线故障复盘库，以发布或配置变更后的异常调查
为主场景：在已导出的变更、应用日志和告警中，整理同一服务或实例的事件顺序，
生成可复核的时间线、候选关联组与证据报告。它不替代日志平台，不自动宣布根因。

目标用户是需要交接事故材料的值班运维、复核变更的发布负责人和调查错误上下文的开发者。
离线流程适合生产访问受限、材料需脱敏交接，以及同一批证据需要重复复核的情况。
项目价值是固定分析步骤与证据出处，不是未经测量的排障提速或生产采用率。

当前交付为分析库、静态演示数据和最小 CLI。JSONL 与固定格式文本已通过显式映射
适配为统一事件，CLI `analyze` 已贯通适配、时间线和候选关联；它仍不读取主机文件，
也不声称能自动理解任意供应商日志。当前模型层已经提供 `CanonicalEvent`、资源实体、
事件分类、证据来源和关系边类型；版本化 JSONL Profile 与确定性的 Processor 管线已能复用
字段映射、规范化、资源别名和筛选步骤，声明式规则将在此模型上增量实现。

## 统一抽象与关联前提

现有 `NormalizedEvent` 统一时间、级别、来源和原始文本；`CorrelationEvent` 进一步携带
资源键与 `Change / Alert / Crash / Other` 角色。调用方先明确字段映射和资源身份，
核心才按同一资源、至少两个不同来源、最早事件起算的闭区间窗口构建候选组。

配置项、服务和实例不是天然相同的资源；只有显式选择共同分析范围才能关联。
不通过名称相似或日志关键词猜测身份。缺时间的事件不参与关联；适配器拒绝空资源键，
没有资源的事件只保留在时间线中。资源与时间关系不是因果证明。

适配结果包含稳定事件 ID、证据 ID/行号和结构化属性，隔离供应商格式差异。
通用性来自“适配层处理输入差异，分析核心复用事件契约”，而不是自动理解所有格式。

## 可解释事件关系图架构

项目的独立复用内核是可解释事件关系图，而不是某一种日志格式的解析器：

```text
EvidenceRecord → Profile → CanonicalEvent → Processor → CorrelationRule → IncidentGraph
```

- `CanonicalEvent` 分开保存事件时间、观测时间、结构化来源、资源实体、类别、事件类型、
  动作、结果、级别、正文、属性和 `EventProvenance`。
- `Profile` 用版本化配置描述嵌套对象路径、常量/可选值、事件分类、资源前缀和精确别名；
  Profile 身份与版本写入证据溯源，输入格式变化不会污染分析核心。
- `Processor` 由按声明顺序执行的阶段组成，负责结构化标识规范化、资源别名、来源/类别/资源
  过滤和时间窗口筛选；所有处理保持确定性且不修改原始内容与证据溯源。
- `CorrelationRule` 计划支持有序时序、事件计数、属性匹配和分组键；规则只产生可解释关系，
  不把时间相关性冒充根因。
- `IncidentGraph` 保存事件节点、关系边和诊断。边包含规则 ID、资源键、时间差、证据位置、
  匹配原因和 `Observed/Hypothesis` 状态；时间线、发现和报告均从图派生。

当前 `correlate_events` 和 `DiagnosticRule` 仍作为兼容视图，下一阶段会映射到声明式规则。
调用方只应选择 Profile 和规则，不应逐条手工构造关联事件。

设计参考公开标准的分层思想，不复制实现代码：
[OpenTelemetry 日志模型](https://opentelemetry.io/docs/specs/otel/logs/data-model/)、
[Collector 组件流水线](https://opentelemetry.io/docs/collector/components/)、
[Sigma 关联规则](https://sigmahq.io/sigma-specification/specification/sigma-correlation-rules-specification.html)、
[Plaso 解析器插件](https://plaso.readthedocs.io/en/latest/sources/developer/How-to-write-a-parser.html)
和 [ECS 事件分类](https://www.elastic.co/docs/reference/ecs/ecs-allowed-values-event-kind)。
它们分别对应本项目的统一事件、处理器、规则、适配器和分类模型。

## 三个完整使用场景

1. **配置变更后的健康故障**：配置控制器记录连接池变更，健康检查记录超时；资源别名把配置项和服务映射到同一分析范围，输出“变更→失败→恢复”的有序关系和证据行号。
2. **应用错误与进程退出**：应用日志记录错误，服务管理器记录非零退出和重启；通过实例资源与 `process.exit` 事件类型关联，保留退出码但不直接断言 OOM 根因。
3. **指标异常与网关超时**：指标记录 CPU、内存和 P95，网关记录请求超时；通过实例和请求属性匹配生成候选关系，展示继续调查的时间段，不把指标升高认定为原因。

三类场景均使用仓库内固定时间的虚构夹具，报告需区分直接观测和待验证假设。

## 能力概览

- **案件与证据模型**：案件、证据文件、来源、采集时间及键值元数据。
- **离线导入**：解析 JSONL 事件流和固定格式的纯文本日志，保留原文及记录顺序。
- **可复用映射 Profile**：以版本化 Profile 将不同 JSONL 对象映射为统一事件，支持嵌套字段、
  可选值、资源前缀和精确别名，并对缺失或类型错误给出证据行号。
- **统一事件信息**：标准化 RFC 3339 时间、严重级别和来源标识，为比较及排序提供稳定字段。
- **证据完整性**：为证据内容生成 SHA-256 摘要、字节大小和来源清单；可用原始内容复核清单。
- **确定性时间线**：按时间稳定排序，按来源过滤，并查询包含边界的 UTC 时间窗口。
- **诊断与关联**：规则结果同时携带证据引用和置信说明；关联相同资源、限定窗口内、来自不同来源的事件。
- **可读报告**：输出 Markdown 摘要、时间线、发现、证据索引和限制说明，也可输出完整 JSON 数据。

关联只表达资源和时间上的关系，不等同于因果证明。报告会保留这一边界，供调查人员结合原始证据复核。

## 项目结构

```text
.
├── cmd/main/                   # 最小 CLI，贯通 JSONL 分析与摘要校验
├── samples/incidents/          # 固定时间的脱敏故障夹具
├── canonical_event.mbt         # 统一事件、资源、证据来源和关系边模型
├── event_adapter.mbt           # JSONL/文本到事件的显式适配
├── correlation.mbt             # 跨来源事件关联
├── integrity.mbt               # 证据摘要及清单校验
├── ingest_jsonl.mbt            # JSONL 导入
├── ingest_plain_text.mbt       # 纯文本日志导入
├── mapping_profile.mbt         # 版本化 JSONL 映射 Profile
├── processor.mbt               # CanonicalEvent 转换与筛选管线
├── normalize.mbt               # 时间、级别和来源标准化
├── report.mbt                  # Markdown 与 JSON 报告
├── rules.mbt                   # 诊断规则和证据引用
├── timeline.mbt                # 稳定时间线与窗口查询
├── moon.mod                    # MoonBit 模块元数据
└── moon.pkg                    # 根库包配置
```

## 开发环境与验证

需要安装 MoonBit 工具链和 Git。在仓库根目录执行：

```sh
moon fmt
moon check --deny-warn
moon build
moon test
```

测试覆盖模型、导入、标准化、完整性、时间线、规则、关联和报告黄金快照。夹具
位于 `samples/incidents/`，其固定时间、字段契约和场景说明见
[`samples/README.md`](samples/README.md)。

发布前至少执行 `moon info` 并检查生成的 `.mbti` 无意外变化；GitHub Actions 会在全新
Ubuntu 环境中安装 MoonBit 最新稳定工具链并记录完整版本，执行格式、类型、构建、测试、
接口文件和文档 CLI 示例检查。

发布检查还应确认 `git status --short` 为空、`moon.mod` 的模块名与 GitHub 账号一致、
`LICENSE` 和 `samples/README.md` 在仓库中存在，并从干净检出重新运行上述命令。

## CLI 工作流

命令行入口接受内联证据内容，便于离线复现和脚本调用。三个命令分别负责导入
JSONL、输出最小分析摘要，以及计算证据大小和 SHA-256 清单：

```sh
moon run cmd/main -- ingest '{"event_id":"evt-1","severity":"INFO"}'
moon run cmd/main -- analyze '{"event_id":"evt-1","timestamp":"2026-03-08T09:00:00Z","source":"cli","severity":"INFO","resource":"demo-service"}'
moon run cmd/main -- verify 'evidence bytes'
moon run cmd/main -- verify 'evidence bytes' 9d11f9a71c12d6194481f5fa5086b0eff7df05a4a228f022f55bd890009a9d16
```

成功输出 `exit code 0`。参数或命令错误为 `exit code 2`，JSONL/输入错误为
`exit code 3`，证据校验失败为 `exit code 4`；失败路径同时返回非零进程状态。
当前入口不直接读取主机文件，调用方可先读取文件内容再将其作为参数传入。
`analyze` 会通过显式 JSONL 字段映射生成统一事件、时间线和候选关联组；`verify` 的可选摘要参数
用于复核已有清单。缺少事件必需字段或摘要不匹配时返回非零退出码。

## 取证边界

- 解析和报告面向已提供的证据内容，不会自行连接主机或采集运行时数据。
- 时间线排序与事件关联是确定性的；缺失或错误时间不会被推断为精确时间。
- 规则只按声明的严重级别和文本条件匹配，不会自动学习或扩展规则。
- 时间接近、来源不同或资源标识相同，不足以单独证明根因。
- 清单校验依赖调用方再次提供的证据字节；校验结果不能替代可信存储或签名机制。

## 许可证

本项目采用 MIT License，详见 [`LICENSE`](LICENSE)。
