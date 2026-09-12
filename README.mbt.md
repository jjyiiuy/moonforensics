# MoonForensics

MoonForensics（MoonBit 系统故障取证舱）是一个面向系统故障复盘的离线、可复现
证据分析工具。它将逐步支持证据导入与校验、统一时间线、可解释诊断规则以及
Markdown/JSON 报告。

当前仓库只包含第 2 阶段的 MoonBit 模块骨架，尚未实现证据模型或分析功能。
项目范围、使用场景和验收契约见
[`docs/project-brief.md`](docs/project-brief.md)。

## 环境要求

- MoonBit 工具链
- Git

## 验证骨架

在仓库根目录运行：

```text
moon fmt
moon check --deny-warn
moon test
moon run cmd/main
```

最后一条命令应输出：

```text
MoonForensics: scaffold ready
```

## 当前结构

```text
.
├── cmd/main/              # 最小命令行入口
├── docs/project-brief.md  # 项目范围与验收契约
├── moon.mod               # MoonBit 模块元数据
├── moon.pkg               # 根库包
└── moonforensics.mbt      # 根库包占位文件
```

## 许可证

本项目采用 MIT License，详见 `LICENSE`。

