///|
fn graph_event(
  event_id : String,
  category : @moonforensics.EventCategory,
  event_type : String,
  timestamp : String?,
  resource_id : String?,
) -> @moonforensics.CanonicalEvent {
  @moonforensics.CanonicalEvent::{
    event_id,
    event_time: match timestamp {
      Some(value) => Some(try! @moonforensics.normalize_timestamp(value))
      None => None
    },
    observed_time: None,
    source: @moonforensics.TelemetrySource::{
      system: "fixture",
      component: "source",
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
    severity: None,
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
fn graph_rule() -> @moonforensics.CorrelationRule {
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
      resource_kind: None,
    },
    to: @moonforensics.EventPattern::{
      category: Some(@moonforensics.EventCategory::Availability),
      event_type: Some("health.failed"),
      action: None,
      outcome: None,
      severity: None,
      source_system: None,
      source_component: None,
      resource_kind: None,
    },
    within_seconds: 60,
    same_resource: true,
    relation_type: @moonforensics.RelationType::MatchedRule,
    explanation: "An availability failure followed a change.",
  }
}

///|
fn graph_has_diagnostic(
  graph : @moonforensics.IncidentGraph,
  code : String,
) -> Bool {
  let mut found = false
  for diagnostic in graph.diagnostics {
    if diagnostic.code == code {
      found = true
    }
  }
  found
}

///|
test "graph sorts nodes and retains explainable rule edges" {
  let change = graph_event(
    "change-1",
    @moonforensics.EventCategory::Change,
    "config.update",
    Some("2026-09-20T00:00:00Z"),
    Some("orders"),
  )
  let alert = graph_event(
    "alert-1",
    @moonforensics.EventCategory::Availability,
    "health.failed",
    Some("2026-09-20T00:00:30Z"),
    Some("orders"),
  )
  let graph = try! @moonforensics.build_incident_graph([alert, change], [
    graph_rule(),
  ])
  assert_eq(graph.nodes.map(event => event.event_id), ["change-1", "alert-1"])
  assert_eq(graph.edges.length(), 1)
  assert_eq(graph.edges[0].from_event_id, "change-1")
  assert_eq(graph.edges[0].to_event_id, "alert-1")
  assert_eq(
    graph.edges[0].explanation,
    "An availability failure followed a change.",
  )
  assert_eq(graph.edges[0].evidence_refs.length(), 2)
  assert_eq(graph.edges[0].resource_key.unwrap().id, "orders")
  assert_eq(graph.diagnostics.length(), 0)
}

///|
test "graph diagnostics explain missing and duplicate evidence identity" {
  let duplicate = graph_event(
    "duplicate",
    @moonforensics.EventCategory::Availability,
    "health.failed",
    Some("2026-09-20T00:00:10Z"),
    Some("orders"),
  )
  let missing = graph_event(
    "duplicate",
    @moonforensics.EventCategory::Change,
    "config.update",
    None,
    None,
  )
  let graph = try! @moonforensics.build_incident_graph([missing, duplicate], [
    graph_rule(),
  ])
  assert_true(graph_has_diagnostic(graph, "duplicate_event_id"))
  assert_true(graph_has_diagnostic(graph, "missing_event_time"))
  assert_true(graph_has_diagnostic(graph, "missing_resource"))
  for diagnostic in graph.diagnostics {
    assert_true(diagnostic.provenance is Some(_))
    assert_true(diagnostic.event_id == Some("duplicate"))
  }
}

///|
test "graph construction is repeatable for the same input" {
  let events = [
    graph_event(
      "change",
      @moonforensics.EventCategory::Change,
      "config.update",
      Some("2026-09-20T00:00:00Z"),
      Some("orders"),
    ),
    graph_event(
      "alert",
      @moonforensics.EventCategory::Availability,
      "health.failed",
      Some("2026-09-20T00:00:30Z"),
      Some("orders"),
    ),
  ]
  let first = try! @moonforensics.build_incident_graph(events, [graph_rule()])
  let second = try! @moonforensics.build_incident_graph(events, [graph_rule()])
  assert_eq(first, second)
}
