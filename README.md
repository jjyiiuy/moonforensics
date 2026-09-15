# MoonForensics

MoonForensics（MoonBit 系统故障取证舱）是一个面向系统故障复盘的离线、可复现
分析库。它把来源明确的证据整理为可比较的事件时间线，提供完整性校验、规则化
观察和跨来源关联，并可生成 Markdown 与 JSON 报告。项目强调保留原始内容、记录
证据出处，以及把“观察到的事实”和“待验证假设”清楚区分。

当前阶段主要交付 MoonBit 库及静态故障夹具；命令行程序、自动采集、在线遥测和
自动根因判定不在当前实现范围内。

## 能力概览

- **案件与证据模型**：案件、证据文件、来源、采集时间及键值元数据。
- **离线导入**：解析 JSONL 事件流和固定格式的纯文本日志，保留原文及记录顺序。
- **统一事件信息**：标准化 RFC 3339 时间、严重级别和来源标识，为比较及排序提供稳定字段。
- **证据完整性**：为证据内容生成 SHA-256 摘要、字节大小和来源清单；可用原始内容复核清单。
- **确定性时间线**：按时间稳定排序，按来源过滤，并查询包含边界的 UTC 时间窗口。
- **诊断与关联**：规则结果同时携带证据引用和置信说明；关联相同资源、限定窗口内、来自不同来源的事件。
- **可读报告**：输出 Markdown 摘要、时间线、发现、证据索引和限制说明，也可输出完整 JSON 数据。

关联只表达资源和时间上的关系，不等同于因果证明。报告会保留这一边界，供调查人员结合原始证据复核。

## 项目结构

```text
.
├── cmd/main/                   # 当前为最小命令行骨架
├── docs/project-brief.md       # 项目范围和验收契约
├── samples/incidents/          # 固定时间的脱敏故障夹具
├── correlation.mbt             # 跨来源事件关联
├── integrity.mbt               # 证据摘要及清单校验
├── ingest_jsonl.mbt            # JSONL 导入
├── ingest_plain_text.mbt       # 纯文本日志导入
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
moon test
```

测试覆盖模型、导入、标准化、完整性、时间线、规则、关联和报告黄金快照。夹具
位于 `samples/incidents/`，其固定时间、字段契约和场景说明见
[`samples/README.md`](samples/README.md)。项目目标和验收约束见
[`docs/project-brief.md`](docs/project-brief.md)。

发布前检查项见 [`docs/release-checklist.md`](docs/release-checklist.md)；GitHub Actions
会在全新 Ubuntu 环境中安装 MoonBit 最新稳定工具链并记录完整版本，执行格式、类型、
测试、接口文件和文档 CLI 示例检查。

## CLI 工作流

命令行入口接受内联证据内容，便于离线复现和脚本调用。三个命令分别负责导入
JSONL、输出最小分析摘要，以及计算证据大小和 SHA-256 清单：

```sh
moon run cmd/main -- ingest '{"event_id":"evt-1","severity":"INFO"}'
moon run cmd/main -- analyze '{"event_id":"evt-1","severity":"INFO"}'
moon run cmd/main -- verify 'evidence bytes'
```

成功输出 `exit code 0`。参数或命令错误为 `exit code 2`，JSONL/输入错误为
`exit code 3`，证据校验失败为 `exit code 4`；失败路径同时返回非零进程状态。
当前入口不直接读取主机文件，调用方可先读取文件内容再将其作为参数传入。

## 取证边界

- 解析和报告面向已提供的证据内容，不会自行连接主机或采集运行时数据。
- 时间线排序与事件关联是确定性的；缺失或错误时间不会被推断为精确时间。
- 规则只按声明的严重级别和文本条件匹配，不会自动学习或扩展规则。
- 时间接近、来源不同或资源标识相同，不足以单独证明根因。
- 清单校验依赖调用方再次提供的证据字节；校验结果不能替代可信存储或签名机制。

## 许可证

本项目采用 MIT License，详见 [`LICENSE`](LICENSE)。
