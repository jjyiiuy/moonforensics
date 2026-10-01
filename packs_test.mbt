///|
fn pack_event(
  event_id : String,
  category : @moonforensics.EventCategory,
  event_type : String,
  timestamp : String,
  resource_id : String,
) -> @moonforensics.CanonicalEvent {
  @moonforensics.CanonicalEvent::{
    event_id,
    event_time: Some(try! @moonforensics.normalize_timestamp(timestamp)),
    observed_time: None,
    source: @moonforensics.TelemetrySource::{
      system: "fixture",
      component: "pack-test",
      host: None,
      instrumentation_scope: None,
    },
    resource: Some(@moonforensics.ResourceRef::{
      kind: @moonforensics.ResourceKind::Service,
      id: resource_id,
      attributes: {},
    }),
    category,
    event_type,
    action: None,
    outcome: @moonforensics.EventOutcome::Unknown,
    severity: None,
    body: ToJson::to_json(event_id),
    raw_content: "\{event_id} raw",
    attributes: {},
    provenance: @moonforensics.EventProvenance::{
      evidence_id: "pack-fixture",
      path: "fixtures/packs.jsonl",
      line_number: None,
      byte_offset: None,
      byte_length: None,
      sha256: None,
      profile_id: "fixture",
      profile_version: "1",
    },
  }
}

///|
test "built-in packs expose stable metadata and valid rules" {
  let packs = @moonforensics.built_in_analysis_packs()
  assert_eq(packs.map(pack => pack.pack_id), ["config", "crash", "latency"])
  for pack in packs {
    assert_true(pack.title.trim() != "")
    assert_true(pack.description.trim() != "")
    assert_eq(pack.rules.length(), 2)
    try! @moonforensics.validate_analysis_pack(pack)
  }
}

///|
test "config pack correlates health failure after a configuration change" {
  let events = [
    pack_event(
      "health-1",
      @moonforensics.EventCategory::Availability,
      "health.failed",
      "2026-09-20T00:00:30Z",
      "orders",
    ),
    pack_event(
      "config-1",
      @moonforensics.EventCategory::Change,
      "config.update",
      "2026-09-20T00:00:00Z",
      "orders",
    ),
  ]
  let graph = try! @moonforensics.analyze_with_pack(
    events,
    @moonforensics.config_analysis_pack(),
  )
  assert_eq(graph.nodes.map(event => event.event_id), ["config-1", "health-1"])
  assert_eq(graph.edges.length(), 1)
  assert_eq(graph.edges[0].rule_id, Some("config-change-then-health-failure"))
}

///|
test "crash pack correlates a process exit with a health failure" {
  let graph = try! @moonforensics.analyze_with_pack(
    [
      pack_event(
        "crash-1",
        @moonforensics.EventCategory::Process,
        "process.exit",
        "2026-09-20T00:00:00Z",
        "payments",
      ),
      pack_event(
        "health-1",
        @moonforensics.EventCategory::Availability,
        "health.failed",
        "2026-09-20T00:01:00Z",
        "payments",
      ),
    ],
    @moonforensics.crash_analysis_pack(),
  )
  assert_eq(graph.edges.length(), 1)
  assert_eq(graph.edges[0].rule_id, Some("crash-then-health-failure"))
}

///|
test "latency pack keeps timeout matching inside its declared window" {
  let in_window = try! @moonforensics.analyze_with_pack(
    [
      pack_event(
        "latency-1",
        @moonforensics.EventCategory::Performance,
        "request.latency",
        "2026-09-20T00:00:00Z",
        "gateway",
      ),
      pack_event(
        "timeout-1",
        @moonforensics.EventCategory::Availability,
        "request.timeout",
        "2026-09-20T00:00:45Z",
        "gateway",
      ),
    ],
    @moonforensics.latency_analysis_pack(),
  )
  assert_eq(in_window.edges.length(), 1)
  assert_eq(in_window.edges[0].rule_id, Some("latency-then-timeout"))

  let outside_window = try! @moonforensics.analyze_with_pack(
    [
      pack_event(
        "latency-1",
        @moonforensics.EventCategory::Performance,
        "request.latency",
        "2026-09-20T00:00:00Z",
        "gateway",
      ),
      pack_event(
        "timeout-1",
        @moonforensics.EventCategory::Availability,
        "request.timeout",
        "2026-09-20T00:01:01Z",
        "gateway",
      ),
    ],
    @moonforensics.latency_analysis_pack(),
  )
  assert_eq(outside_window.edges.length(), 0)
}

///|
test "caller-defined analysis packs reuse the canonical graph pipeline" {
  let custom_rule = @moonforensics.CorrelationRule::{
    rule_id: "deploy-then-health-failure",
    from: @moonforensics.EventPattern::{
      category: Some(@moonforensics.EventCategory::Change),
      event_type: Some("deploy.completed"),
      action: None,
      outcome: None,
      severity: None,
      source_system: Some("release-controller"),
      source_component: None,
      resource_kind: Some(@moonforensics.ResourceKind::Service),
    },
    to: @moonforensics.EventPattern::{
      category: Some(@moonforensics.EventCategory::Availability),
      event_type: Some("health.failed"),
      action: None,
      outcome: None,
      severity: None,
      source_system: Some("health-monitor"),
      source_component: None,
      resource_kind: Some(@moonforensics.ResourceKind::Service),
    },
    within_seconds: 180,
    same_resource: true,
    relation_type: @moonforensics.RelationType::MatchedRule,
    explanation: "A deployment was followed by a health failure on the same service.",
  }
  let pack = try! @moonforensics.new_analysis_pack(
    "release-health",
    "Release health analysis",
    "Connects release completion events to subsequent health failures.",
    [custom_rule],
  )
  let graph = try! @moonforensics.analyze_with_pack(
    [
      {
        ..pack_event(
          "health-1",
          @moonforensics.EventCategory::Availability,
          "health.failed",
          "2026-09-20T00:01:00Z",
          "checkout",
        ),
        source: @moonforensics.TelemetrySource::{
          system: "health-monitor",
          component: "checks",
          host: None,
          instrumentation_scope: None,
        },
      },
      {
        ..pack_event(
          "deploy-1",
          @moonforensics.EventCategory::Change,
          "deploy.completed",
          "2026-09-20T00:00:00Z",
          "checkout",
        ),
        source: @moonforensics.TelemetrySource::{
          system: "release-controller",
          component: "deploy",
          host: None,
          instrumentation_scope: None,
        },
      },
    ],
    pack,
  )
  assert_eq(graph.edges.length(), 1)
  assert_eq(graph.edges[0].rule_id, Some("deploy-then-health-failure"))
}

///|
test "analysis pack validation rejects missing metadata" {
  let pack = @moonforensics.AnalysisPack::{
    pack_id: "",
    title: "invalid",
    description: "invalid",
    rules: [],
  }
  try @moonforensics.validate_analysis_pack(pack) catch {
    @moonforensics.CorrelationRuleError::InvalidRule(rule_id~, reason~) => {
      assert_eq(rule_id, "")
      assert_eq(reason, "analysis pack id must not be empty")
    }
  } noraise {
    _ => fail("expected analysis pack validation to fail")
  }
}

///|
test "caller-defined analysis packs reject invalid rules at construction" {
  try
    @moonforensics.new_analysis_pack(
      "invalid-pack",
      "Invalid pack",
      "This pack has a negative time window.",
      [
        {
          ..@moonforensics.CorrelationRule::{
            rule_id: "invalid-window",
            from: @moonforensics.EventPattern::{
              category: None,
              event_type: None,
              action: None,
              outcome: None,
              severity: None,
              source_system: None,
              source_component: None,
              resource_kind: None,
            },
            to: @moonforensics.EventPattern::{
              category: None,
              event_type: None,
              action: None,
              outcome: None,
              severity: None,
              source_system: None,
              source_component: None,
              resource_kind: None,
            },
            within_seconds: 0,
            same_resource: false,
            relation_type: @moonforensics.RelationType::MatchedRule,
            explanation: "placeholder",
          },
          within_seconds: -1,
        },
      ],
    )
  catch {
    @moonforensics.CorrelationRuleError::InvalidRule(rule_id~, reason~) => {
      assert_eq(rule_id, "invalid-window")
      assert_eq(reason, "within_seconds must not be negative")
    }
  } noraise {
    _ => fail("expected invalid caller-defined pack")
  }
}
