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
