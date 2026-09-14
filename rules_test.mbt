///|
fn rule_test_event(
  second : Int,
  severity : @moonforensics.Severity?,
  source_id : String,
  raw_content : String,
) -> @moonforensics.NormalizedEvent {
  @moonforensics.NormalizedEvent::{
    timestamp: Some(@moonforensics.NormalizedTimestamp::{
      epoch_day: 1,
      second_of_day: second,
      nanosecond: 0,
      raw: "test-time",
    }),
    severity,
    source_id,
    raw_content,
  }
}

///|
fn rule_test_rule(
  rule_id : String,
  severity : @moonforensics.Severity?,
  text_contains : String?,
  kind : @moonforensics.FindingKind,
) -> @moonforensics.DiagnosticRule {
  @moonforensics.DiagnosticRule::{
    rule_id,
    title: "Matched event",
    explanation: "Rule criteria matched the event.",
    kind,
    confidence_note: "This result is limited to the cited event.",
    severity,
    text_contains,
  }
}

///|
test "diagnostic rules match severity and raw text with evidence references" {
  let timeline = @moonforensics.build_timeline([
    rule_test_event(
      20,
      Some(@moonforensics.Severity::Error),
      "svc/orders",
      "database connection refused",
    ),
    rule_test_event(
      10,
      Some(@moonforensics.Severity::Warning),
      "svc/catalog",
      "database connection slow",
    ),
    rule_test_event(
      30,
      Some(@moonforensics.Severity::Error),
      "svc/orders",
      "request validation failed",
    ),
  ])
  let rule = rule_test_rule(
    "database-error",
    Some(@moonforensics.Severity::Error),
    Some("database connection"),
    @moonforensics.FindingKind::Hypothesis,
  )
  let report = @moonforensics.evaluate_diagnostic_rules(timeline, [rule])

  assert_eq(report.findings.length(), 1)
  assert_eq(report.findings[0].rule_id, "database-error")
  assert_eq(report.findings[0].kind, @moonforensics.FindingKind::Hypothesis)
  assert_eq(report.findings[0].evidence[0].event_index, 1)
  assert_eq(report.findings[0].evidence[0].source_id, "svc/orders")
  assert_eq(
    report.findings[0].evidence[0].raw_content,
    "database connection refused",
  )
}

///|
test "diagnostic rules keep declaration and timeline order deterministic" {
  let timeline = @moonforensics.build_timeline([
    rule_test_event(20, None, "svc/a", "restart complete"),
    rule_test_event(10, None, "svc/b", "restart requested"),
  ])
  let rules = [
    rule_test_rule(
      "restart-rule",
      None,
      Some("restart"),
      @moonforensics.FindingKind::Observation,
    ),
    rule_test_rule(
      "requested-rule",
      None,
      Some("requested"),
      @moonforensics.FindingKind::Hypothesis,
    ),
  ]

  let first = @moonforensics.evaluate_diagnostic_rules(timeline, rules)
  let second = @moonforensics.evaluate_diagnostic_rules(timeline, rules)

  assert_eq(first, second)
  assert_eq(first.findings.length(), 3)
  assert_eq(first.findings[0].rule_id, "restart-rule")
  assert_eq(first.findings[0].evidence[0].raw_content, "restart requested")
  assert_eq(first.findings[1].evidence[0].raw_content, "restart complete")
  assert_eq(first.findings[2].rule_id, "requested-rule")
}

///|
test "diagnostic rules return no findings for unmatched events" {
  let timeline = @moonforensics.build_timeline([
    rule_test_event(
      10,
      Some(@moonforensics.Severity::Info),
      "svc/health",
      "health check passed",
    ),
  ])
  let rule = rule_test_rule(
    "fatal-only",
    Some(@moonforensics.Severity::Fatal),
    None,
    @moonforensics.FindingKind::Observation,
  )
  let report = @moonforensics.evaluate_diagnostic_rules(timeline, [rule])

  assert_eq(report.findings.length(), 0)
}
