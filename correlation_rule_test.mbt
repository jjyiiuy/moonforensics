///|
fn rule_event(
  event_id : String,
  category : @moonforensics.EventCategory,
  event_type : String,
  source_component : String,
  timestamp : String,
  resource_id : String?,
) -> @moonforensics.CanonicalEvent {
  @moonforensics.CanonicalEvent::{
    event_id,
    event_time: Some(try! @moonforensics.normalize_timestamp(timestamp)),
    observed_time: None,
    source: @moonforensics.TelemetrySource::{
      system: "fixture",
      component: source_component,
      host: None,
      instrumentation_scope: None,
    },
    resource: match resource_id {
      Some(id) =>
        Some(@moonforensics.ResourceRef::{
          kind: @moonforensics.ResourceKind::Service,
          id,
          attributes: {},
        })
      None => None
    },
    category,
    event_type,
    action: None,
    outcome: @moonforensics.EventOutcome::Unknown,
    severity: Some(@moonforensics.Severity::Warning),
    body: ToJson::to_json(event_id),
    raw_content: "\{event_id} raw",
    attributes: {},
    provenance: @moonforensics.EventProvenance::{
      evidence_id: "\{event_id}.jsonl",
      path: "fixtures/\{event_id}.jsonl",
      line_number: Some(1),
      byte_offset: None,
      byte_length: None,
      sha256: None,
      profile_id: "fixture",
      profile_version: "1",
    },
  }
}

///|
fn change_to_alert_rule() -> @moonforensics.CorrelationRule {
  @moonforensics.CorrelationRule::{
    rule_id: "change-then-alert",
    from: @moonforensics.EventPattern::{
      category: Some(@moonforensics.EventCategory::Change),
      event_type: None,
      action: None,
      outcome: None,
      severity: None,
      source_system: None,
      source_component: None,
      resource_kind: Some(@moonforensics.ResourceKind::Service),
    },
    to: @moonforensics.EventPattern::{
      category: Some(@moonforensics.EventCategory::Availability),
      event_type: Some("health.failed"),
      action: None,
      outcome: None,
      severity: None,
      source_system: None,
      source_component: Some("health"),
      resource_kind: Some(@moonforensics.ResourceKind::Service),
    },
    within_seconds: 60,
    same_resource: true,
    relation_type: @moonforensics.RelationType::MatchedRule,
    explanation: "A health failure followed a configuration change.",
  }
}

///|
test "declarative rule relates change and alert with evidence" {
  let events = [
    rule_event(
      "config-1",
      @moonforensics.EventCategory::Change,
      "config.update",
      "controller",
      "2026-09-20T00:00:00Z",
      Some("orders"),
    ),
    rule_event(
      "alert-1",
      @moonforensics.EventCategory::Availability,
      "health.failed",
      "health",
      "2026-09-20T00:00:30Z",
      Some("orders"),
    ),
  ]
  let graph = try! @moonforensics.evaluate_correlation_rules(events, [
    change_to_alert_rule(),
  ])
  assert_eq(graph.nodes.length(), 2)
  assert_eq(graph.edges.length(), 1)
  assert_eq(graph.edges[0].from_event_id, "config-1")
  assert_eq(graph.edges[0].to_event_id, "alert-1")
  assert_eq(graph.edges[0].delta_seconds, Some(30))
  assert_eq(graph.edges[0].resource_key.unwrap().id, "orders")
  assert_eq(graph.edges[0].evidence_refs.length(), 2)
  assert_eq(graph.edges[0].status, @moonforensics.RelationStatus::Hypothesis)
}

///|
test "rules keep deterministic declaration and input order" {
  let events = [
    rule_event(
      "change-1",
      @moonforensics.EventCategory::Change,
      "config.update",
      "controller",
      "2026-09-20T00:00:00Z",
      Some("orders"),
    ),
    rule_event(
      "alert-1",
      @moonforensics.EventCategory::Availability,
      "health.failed",
      "health",
      "2026-09-20T00:00:10Z",
      Some("orders"),
    ),
    rule_event(
      "crash-1",
      @moonforensics.EventCategory::Process,
      "process.exit",
      "runtime",
      "2026-09-20T00:00:20Z",
      Some("orders"),
    ),
  ]
  let alert_rule = change_to_alert_rule()
  let crash_rule = {
    ..alert_rule,
    rule_id: "change-then-crash",
    to: {
      ..alert_rule.to,
      category: Some(@moonforensics.EventCategory::Process),
      event_type: Some("process.exit"),
      source_component: Some("runtime"),
    },
    explanation: "A process exit followed a configuration change.",
  }
  let graph = try! @moonforensics.evaluate_correlation_rules(events, [
    alert_rule, crash_rule,
  ])
  assert_eq(graph.edges.map(edge => edge.rule_id), [
    Some("change-then-alert"),
    Some("change-then-crash"),
  ])
  assert_eq(graph.edges.map(edge => edge.from_event_id), [
    "change-1", "change-1",
  ])
}

///|
test "same-resource and time-window constraints reject unrelated events" {
  let events = [
    rule_event(
      "change-1",
      @moonforensics.EventCategory::Change,
      "config.update",
      "controller",
      "2026-09-20T00:00:00Z",
      Some("orders"),
    ),
    rule_event(
      "alert-other",
      @moonforensics.EventCategory::Availability,
      "health.failed",
      "health",
      "2026-09-20T00:00:30Z",
      Some("payments"),
    ),
    rule_event(
      "alert-late",
      @moonforensics.EventCategory::Availability,
      "health.failed",
      "health",
      "2026-09-20T00:02:00Z",
      Some("orders"),
    ),
  ]
  let graph = try! @moonforensics.evaluate_correlation_rules(events, [
    change_to_alert_rule(),
  ])
  assert_eq(graph.edges.length(), 0)
}

///|
test "invalid declarative rules fail before graph construction" {
  let rule = { ..change_to_alert_rule(), within_seconds: -1, }
  try @moonforensics.evaluate_correlation_rules([], [rule]) catch {
    @moonforensics.CorrelationRuleError::InvalidRule(rule_id~, reason~) => {
      assert_eq(rule_id, "change-then-alert")
      assert_true(reason.contains("negative"))
    }
  } noraise {
    _ => fail("expected InvalidRule")
  }
}
