///|
fn report_golden_fixture() -> @moonforensics.ForensicReport {
  let collected_at = @moonforensics.Timestamp::{
    value: "2026-03-08T09:05:00Z",
  }
  let case = @moonforensics.Case::{
    case_id: "case-golden-001",
    title: "连接池配置回归",
    timezone: "UTC",
    collected_at,
    evidence: [
      @moonforensics.EvidenceItem::{
        id: "evidence-config",
        source: @moonforensics.EvidenceSource::{
          system: "control-plane",
          component: "config-controller",
          host: Some("fixture-host"),
        },
        path: "samples/config/changes.jsonl",
        format: @moonforensics.EvidenceFormat::JsonLines,
        captured_at: Some(collected_at),
        metadata: @moonforensics.EvidenceMetadata::{ entries: [], },
      },
    ],
    metadata: @moonforensics.EvidenceMetadata::{ entries: [], },
  }
  let config_event = @moonforensics.NormalizedEvent::{
    timestamp: Some(@moonforensics.NormalizedTimestamp::{
      epoch_day: 20520,
      second_of_day: 32400,
      nanosecond: 0,
      raw: "2026-03-08T09:00:00Z",
    }),
    severity: Some(@moonforensics.Severity::Info),
    source_id: "config/controller",
    raw_content: "pool max changed | new value=4",
  }
  let health_event = @moonforensics.NormalizedEvent::{
    timestamp: Some(@moonforensics.NormalizedTimestamp::{
      epoch_day: 20520,
      second_of_day: 32440,
      nanosecond: 0,
      raw: "2026-03-08T09:00:40Z",
    }),
    severity: Some(@moonforensics.Severity::Error),
    source_id: "health/checker",
    raw_content: "health check failed\nreason=database timeout",
  }
  let timeline = @moonforensics.build_timeline([config_event, health_event])
  let findings = @moonforensics.DiagnosticReport::{
    findings: [
      @moonforensics.DiagnosticFinding::{
        rule_id: "change-followed-by-health-failure",
        title: "变更后健康检查失败",
        explanation: "失败时间晚于连接池配置变更。",
        kind: @moonforensics.FindingKind::Hypothesis,
        confidence_note: "时间关系提示相关性，不足以确认因果。",
        evidence: [
          @moonforensics.EvidenceReference::{
            event_index: 1,
            source_id: "health/checker",
            timestamp: health_event.timestamp,
            raw_content: health_event.raw_content,
          },
        ],
      },
    ],
  }
  let evidence_index = @moonforensics.EvidenceManifest::{
    entries: [
      @moonforensics.EvidenceManifestEntry::{
        id: "evidence-config",
        path: "samples/config/changes.jsonl",
        source_id: "control-plane/config-controller/fixture-host",
        size_bytes: 384,
        sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      },
    ],
  }
  @moonforensics.ForensicReport::{
    case,
    summary: "09:00 的连接池上限变更之后出现健康检查失败，随后配置被回滚。",
    timeline,
    findings,
    evidence_index,
    limitations: [
      "报告只描述证据中的时间关系，不把变更认定为已确认根因。",
      "本报告不代表对夹具证据以外系统状态的验证。",
    ],
  }
}

///|
test "markdown report matches the golden snapshot" {
  inspect(
    @moonforensics.render_markdown_report(report_golden_fixture()),
    content=(
      #|# 连接池配置回归
      #|
      #|- **案件 ID：** case-golden-001
      #|- **时区：** UTC
      #|- **证据收集完成时间：** 2026-03-08T09:05:00Z
      #|
      #|## 摘要
      #|
      #|09:00 的连接池上限变更之后出现健康检查失败，随后配置被回滚。
      #|
      #|## 时间线
      #|
      #|| 序号 | 时间 | 来源 | 级别 | 原始内容 |
      #|| ---: | --- | --- | --- | --- |
      #|| 1 | 2026-03-08T09:00:00Z | config/controller | INFO | pool max changed \| new value=4 |
      #|| 2 | 2026-03-08T09:00:40Z | health/checker | ERROR | health check failed<br>reason=database timeout |
      #|
      #|## 发现
      #|
      #|### 变更后健康检查失败
      #|
      #|- **分类：** 待验证假设
      #|- **规则 ID：** `change-followed-by-health-failure`
      #|- **置信度说明：** 时间关系提示相关性，不足以确认因果。
      #|
      #|失败时间晚于连接池配置变更。
      #|
      #|**支持证据：**
      #|- 时间线 #2 · 2026-03-08T09:00:40Z · health/checker
      #|  - 原文：health check failed<br>reason=database timeout
      #|
      #|## 证据索引
      #|
      #|| 证据 ID | 路径 | 来源 | 大小（字节） | SHA-256 |
      #|| --- | --- | --- | ---: | --- |
      #|| evidence-config | samples/config/changes.jsonl | control-plane/config-controller/fixture-host | 384 | `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` |
      #|
      #|## 限制说明
      #|
      #|- 报告只描述证据中的时间关系，不把变更认定为已确认根因。
      #|- 本报告不代表对夹具证据以外系统状态的验证。
      #|
    ),
  )
}

///|
test "json report matches the golden snapshot" {
  inspect(
    @moonforensics.render_json_report(report_golden_fixture()),
    content=(
      #|{
      #|  "case": {
      #|    "case_id": "case-golden-001",
      #|    "title": "连接池配置回归",
      #|    "timezone": "UTC",
      #|    "collected_at": {
      #|      "value": "2026-03-08T09:05:00Z"
      #|    },
      #|    "evidence": [
      #|      {
      #|        "id": "evidence-config",
      #|        "source": {
      #|          "system": "control-plane",
      #|          "component": "config-controller",
      #|          "host": "fixture-host"
      #|        },
      #|        "path": "samples/config/changes.jsonl",
      #|        "format": "JsonLines",
      #|        "captured_at": {
      #|          "value": "2026-03-08T09:05:00Z"
      #|        },
      #|        "metadata": {
      #|          "entries": []
      #|        }
      #|      }
      #|    ],
      #|    "metadata": {
      #|      "entries": []
      #|    }
      #|  },
      #|  "summary": "09:00 的连接池上限变更之后出现健康检查失败，随后配置被回滚。",
      #|  "timeline": {
      #|    "events": [
      #|      {
      #|        "timestamp": {
      #|          "epoch_day": 20520,
      #|          "second_of_day": 32400,
      #|          "nanosecond": 0,
      #|          "raw": "2026-03-08T09:00:00Z"
      #|        },
      #|        "severity": "Info",
      #|        "source_id": "config/controller",
      #|        "raw_content": "pool max changed | new value=4"
      #|      },
      #|      {
      #|        "timestamp": {
      #|          "epoch_day": 20520,
      #|          "second_of_day": 32440,
      #|          "nanosecond": 0,
      #|          "raw": "2026-03-08T09:00:40Z"
      #|        },
      #|        "severity": "Error",
      #|        "source_id": "health/checker",
      #|        "raw_content": "health check failed\nreason=database timeout"
      #|      }
      #|    ]
      #|  },
      #|  "findings": {
      #|    "findings": [
      #|      {
      #|        "rule_id": "change-followed-by-health-failure",
      #|        "title": "变更后健康检查失败",
      #|        "explanation": "失败时间晚于连接池配置变更。",
      #|        "kind": "Hypothesis",
      #|        "confidence_note": "时间关系提示相关性，不足以确认因果。",
      #|        "evidence": [
      #|          {
      #|            "event_index": 1,
      #|            "source_id": "health/checker",
      #|            "timestamp": {
      #|              "epoch_day": 20520,
      #|              "second_of_day": 32440,
      #|              "nanosecond": 0,
      #|              "raw": "2026-03-08T09:00:40Z"
      #|            },
      #|            "raw_content": "health check failed\nreason=database timeout"
      #|          }
      #|        ]
      #|      }
      #|    ]
      #|  },
      #|  "evidence_index": {
      #|    "entries": [
      #|      {
      #|        "id": "evidence-config",
      #|        "path": "samples/config/changes.jsonl",
      #|        "source_id": "control-plane/config-controller/fixture-host",
      #|        "size_bytes": 384,
      #|        "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      #|      }
      #|    ]
      #|  },
      #|  "limitations": [
      #|    "报告只描述证据中的时间关系，不把变更认定为已确认根因。",
      #|    "本报告不代表对夹具证据以外系统状态的验证。"
      #|  ]
      #|}
    ),
  )
}
