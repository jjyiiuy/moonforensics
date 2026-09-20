# 可解释事件关系图架构

> 状态：设计冻结，下一阶段实现契约
>
> 本文对应复审意见中“统一抽象基础、独立复用价值和技术特色不足”的改进项。
> 本次只定义公共概念、边界和验收方式，不宣称这些接口已经全部实现。

## 1. 目标与定位

MoonForensics 的核心不再是把事件按时间窗口分组，而是构建一个**可解释的事件关系图**：
输入经过明确的适配档案和处理器后，形成稳定的统一事件；声明式关系规则再生成带有
证据依据、时间差和匹配原因的关系边。时间线、诊断发现和报告都是关系图的不同视图。

这个内核服务于离线事故复盘：调查者可以回答“哪些观测被连接起来、依据是什么、还有
哪些条件没有满足”，但不会把时序相关性包装成自动根因结论。

### 目标

- 同一个分析核心可消费不同字段命名和编码方式的事件。
- 关系规则由数据声明，而不是散落在调用方的循环和硬编码时间窗中。
- 每条关系都能回指输入证据、规则版本、资源键和计算出的时间差。
- 固定输入、Profile 和规则时，图节点、边和报告保持稳定顺序。

### 不在范围内

- 不自动猜测两个资源是否属于同一服务，也不从名称相似度推断依赖关系。
- 不提供实时采集、日志平台替代、机器学习根因判断或司法鉴定结论。
- 不复制 OpenTelemetry、ECS、Sigma 或 Plaso 的实现代码；它们只作为公开设计参考。

## 2. 分层流水线

```text
EvidenceRecord
    │  Profile：字段路径、类型转换、资源模板、分类
    ▼
CanonicalEvent
    │  Processor：标准化、别名、过滤、属性富化
    ▼
EventSet
    │  CorrelationRule：时序、计数、属性条件、分组键
    ▼
IncidentGraph
    ├── Timeline view
    ├── Findings view
    └── Markdown / JSON report
```

每层有单一责任：Profile 负责“如何读”，Processor 负责“如何整理”，Rule 负责“何时
建立关系”，Graph 负责“如何解释结果”。上层不得绕过 `CanonicalEvent` 直接比较供应商
字段，报告也不得重新执行关联算法。

## 3. 统一事件模型

### 3.1 公共概念

`CanonicalEvent` 是案件内的不可变事件信封，至少包含：

| 字段 | 语义 | 约束 |
| --- | --- | --- |
| `event_id` | 案件内稳定标识 | 不依赖运行时当前时间；缺失时由证据 ID 和行号派生 |
| `event_time` | 事件发生时间 | 可为空；存在时统一为 UTC，可保留原始文本 |
| `observed_time` | 采集器或系统观察时间 | 与发生时间分开，不用观察时间替代发生时间 |
| `source` | 系统、组件、主机和采集范围 | 结构化保存，不能只保留展示字符串 |
| `resource` | 被观察实体及粒度 | 类型和值分开，例如 `service/orders-api`、`instance/orders-api-01` |
| `category` | 事件大类 | `change`、`availability`、`performance`、`process` 等有限枚举 |
| `event_type` | 具体事件类型 | 例如 `config.update`、`health.failed`、`process.exit` |
| `action` | 对资源执行或观察到的动作 | 可为空；不把动作和严重级别混用 |
| `outcome` | 结果 | `success`、`failure`、`unknown` |
| `severity` | 严重级别 | 与事件类型独立；`ERROR` 不自动等于 `Crash` |
| `body` | 原始消息或结构化正文 | 保留原始内容，不改写为推断结论 |
| `attributes` | 事件级附加属性 | 保留未知字段和原始类型 |
| `provenance` | 证据位置 | 证据 ID、路径、行号、字节摘要和 Profile 版本 |

`resource` 表示相对稳定的被观察实体，`attributes` 表示单次事件属性；二者不可混为
一个字符串。一个配置项可以通过 Profile 映射到服务级资源，但该映射必须出现在分析
计划中，不能由关联器自行猜测。

### 3.2 事件角色与关系类型分离

当前 `CorrelationKind` 只描述 `Change / Alert / Crash / Other`。新模型保留角色作为
兼容视图，同时把分类拆成 `category`、`event_type`、`action` 和 `outcome`。这样可以
表达“进程退出是 `process.exit`，结果为 `failure`，严重级别为 `ERROR`”，而不会让
`ERROR` 直接决定它是崩溃。

### 3.3 证据不可丢失

标准化只产生派生数据。`provenance` 必须贯穿 Profile、Processor、Rule 和 Graph：
即使正文被截断或属性被规范化，报告仍能回到原始证据字节。摘要校验失败时，图可以
被展示为“不可验证”，不能继续宣称证据有效。

## 4. Profile：把输入差异隔离在边界内

Profile 是可复用的声明式输入档案，而不是每次调用 `adapt_*` 时临时拼接字段名。
一个 Profile 包括：

```text
Profile {
  profile_id
  version
  input_format          // jsonl, plain_text, or another registered reader
  fields[]               // path -> canonical field
  transforms[]           // parse time, severity, number, enum, trim
  resource_template
  classification         // category / event_type / action / outcome
  required_fields[]
  aliases[]              // source field aliases with deterministic priority
}
```

Profile 执行结果必须是“事件或带位置的诊断”，不能静默丢弃记录。字段路径支持嵌套对象，
转换失败指出证据 ID、行号、字段路径和原始值；缺失可选字段产生 `unknown`，缺失必填
字段拒绝进入关系分析。

首批内置 Profile 不追求覆盖所有日志格式，只提供三种可复用档案：

1. `incident.jsonl/v1`：配置、进程和指标事件的结构化 JSONL。
2. `timestamp-severity-text/v1`：固定时间、级别和正文的纯文本日志。
3. `otel-log-record/v1`：对齐 OpenTelemetry LogRecord 字段的 JSON 表示。

调用方可以注册新 Profile，但分析核心只依赖 `CanonicalEvent`，因此新增输入格式不会
要求修改时间线、规则和报告代码。

## 5. Processor：可组合的确定性处理

Processor 按声明顺序处理事件，每个处理器记录自己的版本和变更摘要。首批处理器包括：

- `NormalizeTime`：解析时区、保存原始时间并转换为 UTC。
- `NormalizeSeverity`：把供应商级别映射到有限级别，未知值保留原文。
- `ResolveResourceAlias`：依据案件提供的别名表将配置项、服务和实例映射到明确粒度。
- `ClassifyEvent`：根据 Profile 或显式规则填充分类字段，不根据关键词隐式猜测。
- `Filter`：按案件范围、来源或时间窗过滤，并记录过滤理由。
- `AttachProvenance`：补充证据路径、摘要和 Profile 版本。

处理器只能产生新事件或诊断，不能覆盖原始证据。相同输入、配置和处理器顺序必须得到
相同事件 ID、字段值和诊断顺序。

## 6. CorrelationRule：从固定窗口升级为声明式关系

规则由选择器、连接键、关系类型和时间约束组成：

```text
CorrelationRule {
  rule_id
  version
  selectors[]       // 每个阶段匹配 category/type/source/attributes
  relation          // temporal, temporal_ordered, event_count, attribute_match
  group_by[]        // resource.service, resource.instance, trace_id ...
  within            // 最大时间跨度
  condition         // count / attribute / outcome 条件
  explanation       // 命中后展示给调查者的原因
}
```

关系类型的最小语义如下：

| 类型 | 语义 | 典型用途 |
| --- | --- | --- |
| `temporal` | 多个选择器在同一范围内出现 | 变更与告警同窗 |
| `temporal_ordered` | 按阶段顺序出现，阶段间有最大间隔 | 变更→失败→恢复 |
| `event_count` | 同一分组键达到次数阈值 | 五分钟内连续超时 |
| `attribute_match` | 不同来源的指定属性值相同 | 请求 ID、实例 ID、发布版本 |

规则不能直接输出“根因成立”，只能输出关系边和待复核假设。未满足的阶段、超出时间窗
的事件和资源冲突也要作为诊断记录，避免把“没有匹配”误解为“没有发生”。

## 7. IncidentGraph：让关联结果可解释

图由稳定排序的节点和边组成：

```text
IncidentGraph {
  nodes: Array[CanonicalEvent]
  edges: Array[EvidenceRelation]
  diagnostics: Array[AnalysisDiagnostic]
}

EvidenceRelation {
  relation_id
  relation_type       // same_resource, temporal_before, matched_rule, alias_of
  from_event
  to_event
  rule_id?
  resource_key?
  delta_seconds?
  evidence_refs[]
  explanation
  status               // observed or hypothesis
}
```

图的边按 `(from_event_time, to_event_time, relation_type, rule_id, event_id)` 排序，
同一输入重复运行不得依赖 Map 的插入顺序。原来的 `CorrelationGroup` 变为图的一个查询
视图，保留兼容 API，但不再作为唯一的内部结果。

一个配置故障规则的结果应能被人读成：

```text
config.update(service/orders-api, 09:00:00)
  ── matched_rule=change_then_health_failure
  ── temporal_ordered, delta=40s, key=service/orders-api
  ── evidence=changes.jsonl:1 -> health.log:3
  ── status=hypothesis
→ health.failed(service/orders-api, 09:00:40)
```

这里的 `hypothesis` 表示“满足规则定义的时序关系”，不表示配置变更已经被证明为根因。

## 8. 与现有 API 的迁移关系

迁移必须保持增量和可回退：

| 现有 API | 迁移方式 |
| --- | --- |
| `NormalizedEvent` | 作为 `CanonicalEvent` 的轻量兼容视图，保留现有时间线用法 |
| `IncidentEvent` | 转换为完整 `CanonicalEvent`，补充分类和 `provenance` |
| `adapt_jsonl_records` | 变为内置 Profile 的执行入口，保留旧函数包装 |
| `adapt_plain_text_records` | 变为 `timestamp-severity-text/v1` Profile 包装 |
| `correlate_events` | 映射到默认 `temporal` 规则，保留行为兼容测试 |
| `DiagnosticRule` | 扩展为单事件 Selector，旧字段转换为等价选择器 |
| `CorrelationGroup` | 由 `IncidentGraph` 查询生成，不删除旧构造方式 |

公共 API 的新类型优先定义在根包，内部解析器和排序实现保持私有。每次公共接口变化都
必须运行 `moon info` 并审查 `.mbti`，避免设计文档与可发布接口脱节。

## 9. 分阶段实现与验收

1. **模型层**：添加 `CanonicalEvent`、资源实体、分类、证据引用和图边类型；测试 JSON
   序列化及稳定排序。
2. **Profile 层**：实现字段路径、转换、别名和诊断；同一事件的两种字段命名映射到
   相同 canonical 输出。
3. **Processor 层**：实现资源别名和属性富化；验证空资源、粒度冲突和摘要失败。
4. **Rule/Graph 层**：实现 `temporal_ordered`、`event_count`、`attribute_match`，
   输出边的规则、时间差、证据和未满足阶段。
5. **领域包与 CLI**：将配置变更、服务崩溃、性能退化做成三个内置分析包；CLI 从
   Profile 文件运行，报告显示图边和解释。

验收不以代码量作为替代指标，而以以下黑盒行为为准：

- 调用方只选择 Profile 和规则，不逐条手工构造 `CorrelationEvent`。
- 配置变更→健康失败→回滚恢复能命中有序规则，且窗口外事件不进入关系边。
- 不同来源字段别名映射后，输出节点和边的顺序、ID、理由完全一致。
- 同一事件同时满足多个规则时保留多条带不同 `rule_id` 的边，不静默覆盖。
- 每条边都能回指证据位置；修改原始字节后报告标记校验失败。
- 规则不满足时输出结构化诊断，而不是返回空数组让调用方猜测原因。

## 10. 参考设计与许可证边界

本项目借鉴公开设计思想，不复制实现代码：

- [OpenTelemetry Logs Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/)
  提供时间、资源、正文和属性分层的参考。
- [OpenTelemetry Collector Components](https://opentelemetry.io/docs/collector/components/)
  提供 Receiver、Processor、Exporter 组件流水线的参考。
- [Sigma Correlation Specification](https://sigmahq.io/sigma-specification/specification/sigma-correlation-rules-specification.html)
  提供时序、计数、分组键和字段别名的规则表达参考。
- [Plaso parser plugin design](https://plaso.readthedocs.io/en/latest/sources/developer/How-to-write-a-parser.html)
  提供解析器、事件数据和时间线职责分离的参考。
- [Elastic ECS categorization fields](https://www.elastic.co/docs/reference/ecs/ecs-using-categorization-fields)
  提供事件分类层次的参考。

MoonForensics 自身代码继续使用 MIT License。若未来复制任何第三方代码、Schema 或
测试数据，必须在文件级注明来源、版本和许可证；仅参考上述公开文档不构成代码移植。
