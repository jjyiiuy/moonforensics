///|
/// States whether a rule result reports an observed fact or a hypothesis.
pub(all) enum FindingKind {
  Observation
  Hypothesis
} derive(Debug, Eq, ToJson)

///|
/// A configurable single-event rule over normalized severity and raw text.
pub(all) struct DiagnosticRule {
  rule_id : String
  title : String
  explanation : String
  kind : FindingKind
  confidence_note : String
  severity : Severity?
  text_contains : String?
} derive(Debug, Eq, ToJson)

///|
/// A stable reference to an event in the timeline and its untouched raw content.
pub(all) struct EvidenceReference {
  event_index : Int
  source_id : String
  timestamp : NormalizedTimestamp?
  raw_content : String
} derive(Debug, Eq, ToJson)

///|
/// One explained rule match with the supporting timeline event reference.
pub(all) struct DiagnosticFinding {
  rule_id : String
  title : String
  explanation : String
  kind : FindingKind
  confidence_note : String
  evidence : Array[EvidenceReference]
} derive(Debug, Eq, ToJson)

///|
/// The deterministic findings produced by evaluating an ordered rule set.
pub(all) struct DiagnosticReport {
  findings : Array[DiagnosticFinding]
} derive(Debug, Eq, ToJson)

///|
fn rule_matches(rule : DiagnosticRule, event : NormalizedEvent) -> Bool {
  let severity_matches = match rule.severity {
    Some(expected) => event.severity == Some(expected)
    None => true
  }
  let text_matches = match rule.text_contains {
    Some(fragment) => event.raw_content.contains(fragment)
    None => true
  }
  severity_matches && text_matches
}

///|
/// Evaluates rules in declaration order and events in timeline order.
/// Each finding cites its timeline index, normalized source, time, and raw content.
///
/// # Example
/// ```mbt check
/// test {
///   let event = NormalizedEvent::{
///     timestamp: None,
///     severity: Some(Severity::Error),
///     source_id: "svc/api",
///     raw_content: "database connection failed",
///   }
///   let timeline = build_timeline([event])
///   let rule = DiagnosticRule::{
///     rule_id: "db-error",
///     title: "Database error observed",
///     explanation: "The log reports a database connection failure.",
///     kind: FindingKind::Observation,
///     confidence_note: "Directly present in the source log.",
///     severity: Some(Severity::Error),
///     text_contains: Some("database connection"),
///   }
///   let report = evaluate_diagnostic_rules(timeline, [rule])
///   assert_eq(report.findings.length(), 1)
/// }
/// ```
pub fn evaluate_diagnostic_rules(
  timeline : Timeline,
  rules : Array[DiagnosticRule],
) -> DiagnosticReport {
  let findings : Array[DiagnosticFinding] = []
  for rule in rules {
    for event_index, event in timeline.events {
      if rule_matches(rule, event) {
        let evidence : Array[EvidenceReference] = [
          {
            event_index,
            source_id: event.source_id,
            timestamp: event.timestamp,
            raw_content: event.raw_content,
          },
        ]
        findings.push({
          rule_id: rule.rule_id,
          title: rule.title,
          explanation: rule.explanation,
          kind: rule.kind,
          confidence_note: rule.confidence_note,
          evidence,
        })
      }
    }
  }
  { findings, }
}
