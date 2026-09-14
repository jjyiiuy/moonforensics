///|
/// The complete, deterministic input used to render a case report.
pub(all) struct ForensicReport {
  case : Case
  summary : String
  timeline : Timeline
  findings : DiagnosticReport
  evidence_index : EvidenceManifest
  limitations : Array[String]
} derive(Debug, Eq, ToJson)

///|
fn markdown_cell(value : String) -> String {
  let escaped : Array[String] = []
  for character in value {
    escaped.push(
      match character {
        '\\' => "\\\\"
        '|' => "\\|"
        '\n' => "<br>"
        '\r' => ""
        '<' => "&lt;"
        '>' => "&gt;"
        '&' => "&amp;"
        '`' => "\\`"
        _ => "\{character}"
      },
    )
  }
  escaped.join("")
}

///|
fn report_severity_label(severity : Severity?) -> String {
  match severity {
    Some(Severity::Trace) => "TRACE"
    Some(Severity::Debug) => "DEBUG"
    Some(Severity::Info) => "INFO"
    Some(Severity::Warning) => "WARN"
    Some(Severity::Error) => "ERROR"
    Some(Severity::Fatal) => "FATAL"
    Some(Severity::Unknown(value)) => value
    None => "未知"
  }
}

///|
fn report_timestamp_label(timestamp : NormalizedTimestamp?) -> String {
  match timestamp {
    Some(value) => value.raw
    None => "时间未知"
  }
}

///|
fn report_finding_kind_label(kind : FindingKind) -> String {
  match kind {
    FindingKind::Observation => "观察事实"
    FindingKind::Hypothesis => "待验证假设"
  }
}

///|
/// Renders a Markdown case report with a timeline, findings, evidence index, and limitations.
/// All dynamic table values are escaped so source text cannot add table cells or HTML.
///
/// # Example
/// ```mbt check
/// test {
///   let timeline = build_timeline([])
///   let report = ForensicReport::{
///     case: Case::{
///       case_id: "case-1",
///       title: "Example incident",
///       timezone: "UTC",
///       collected_at: Timestamp::{ value: "2026-01-01T00:00:00Z", },
///       evidence: [],
///       metadata: EvidenceMetadata::{ entries: [], },
///     },
///     summary: "A reproducible sample case.",
///     timeline,
///     findings: DiagnosticReport::{ findings: [], },
///     evidence_index: EvidenceManifest::{ entries: [], },
///     limitations: ["No causal conclusion is asserted."],
///   }
///   let markdown = render_markdown_report(report)
///   assert_true(markdown.contains("## 摘要"))
///   assert_true(markdown.contains("## 限制说明"))
/// }
/// ```
pub fn render_markdown_report(report : ForensicReport) -> String {
  let lines : Array[String] = [
    "# \{markdown_cell(report.case.title)}",
    "",
    "- **案件 ID：** \{markdown_cell(report.case.case_id)}",
    "- **时区：** \{markdown_cell(report.case.timezone)}",
    "- **证据收集完成时间：** \{markdown_cell(report.case.collected_at.value)}",
    "",
    "## 摘要",
    "",
    markdown_cell(report.summary),
    "",
    "## 时间线",
    "",
    "| 序号 | 时间 | 来源 | 级别 | 原始内容 |",
    "| ---: | --- | --- | --- | --- |",
  ]
  if report.timeline.events.length() == 0 {
    lines.push("| — | — | — | — | 无时间线事件 |")
  } else {
    for index, event in report.timeline.events {
      lines.push(
        "| \{index + 1} | \{markdown_cell(report_timestamp_label(event.timestamp))} | \{markdown_cell(event.source_id)} | \{markdown_cell(report_severity_label(event.severity))} | \{markdown_cell(event.raw_content)} |",
      )
    }
  }
  lines.push("")
  lines.push("## 发现")
  lines.push("")
  if report.findings.findings.length() == 0 {
    lines.push("没有规则发现。")
  } else {
    for finding in report.findings.findings {
      lines.push("### \{markdown_cell(finding.title)}")
      lines.push("")
      lines.push("- **分类：** \{report_finding_kind_label(finding.kind)}")
      lines.push("- **规则 ID：** `\{markdown_cell(finding.rule_id)}`")
      lines.push(
        "- **置信度说明：** \{markdown_cell(finding.confidence_note)}",
      )
      lines.push("")
      lines.push(markdown_cell(finding.explanation))
      if finding.evidence.length() > 0 {
        lines.push("")
        lines.push("**支持证据：**")
        for reference in finding.evidence {
          lines.push(
            "- 时间线 #\{reference.event_index + 1} · \{markdown_cell(report_timestamp_label(reference.timestamp))} · \{markdown_cell(reference.source_id)}",
          )
          lines.push("  - 原文：\{markdown_cell(reference.raw_content)}")
        }
      }
      lines.push("")
    }
  }
  lines.push("## 证据索引")
  lines.push("")
  lines.push("| 证据 ID | 路径 | 来源 | 大小（字节） | SHA-256 |")
  lines.push("| --- | --- | --- | ---: | --- |")
  if report.evidence_index.entries.length() == 0 {
    lines.push("| — | — | — | — | — |")
  } else {
    for entry in report.evidence_index.entries {
      lines.push(
        "| \{markdown_cell(entry.id)} | \{markdown_cell(entry.path)} | \{markdown_cell(entry.source_id)} | \{entry.size_bytes} | `\{markdown_cell(entry.sha256)}` |",
      )
    }
  }
  lines.push("")
  lines.push("## 限制说明")
  lines.push("")
  if report.limitations.length() == 0 {
    lines.push(
      "未提供额外限制说明；时间先后和资源相同本身不构成因果结论。",
    )
  } else {
    for limitation in report.limitations {
      lines.push("- \{markdown_cell(limitation)}")
    }
  }
  lines.join("\n") + "\n"
}

///|
/// Renders the complete report as deterministic, two-space-indented JSON.
///
/// # Example
/// ```mbt check
/// test {
///   let timeline = build_timeline([])
///   let report = ForensicReport::{
///     case: Case::{
///       case_id: "case-1",
///       title: "Example incident",
///       timezone: "UTC",
///       collected_at: Timestamp::{ value: "2026-01-01T00:00:00Z", },
///       evidence: [],
///       metadata: EvidenceMetadata::{ entries: [], },
///     },
///     summary: "A reproducible sample case.",
///     timeline,
///     findings: DiagnosticReport::{ findings: [], },
///     evidence_index: EvidenceManifest::{ entries: [], },
///     limitations: [],
///   }
///   let json = render_json_report(report)
///   assert_true(json.contains("\"evidence_index\""))
///   assert_true(json.contains("\"limitations\""))
/// }
/// ```
pub fn render_json_report(report : ForensicReport) -> String {
  ToJson::to_json(report).stringify(indent=2)
}
