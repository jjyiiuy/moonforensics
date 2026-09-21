///|
fn cross_path(segments : Array[String]) -> @moonforensics.JsonFieldPath {
  { segments, }
}

///|
fn cross_profile(
  profile_id : String,
  component_path : @moonforensics.JsonFieldPath,
  event_id_path : @moonforensics.JsonFieldPath,
  event_time_path : @moonforensics.JsonFieldPath,
  resource_path : @moonforensics.JsonFieldPath,
  event_type_path : @moonforensics.JsonFieldPath,
  category : @moonforensics.EventCategory,
) -> @moonforensics.JsonlMappingProfile {
  @moonforensics.JsonlMappingProfile::{
    id: profile_id,
    version: "1.0.0",
    source: @moonforensics.SourceMappingProfile::{
      system: @moonforensics.ProfileStringValue::Constant("fixture"),
      component: @moonforensics.ProfileStringValue::JsonString(component_path),
      host: None,
      instrumentation_scope: None,
    },
    event_id: @moonforensics.ProfileStringValue::JsonString(event_id_path),
    event_time: Some(event_time_path),
    observed_time: None,
    severity: None,
    resource: Some(@moonforensics.ResourceMappingProfile::{
      kind: @moonforensics.ResourceKind::Service,
      id: @moonforensics.ProfileStringValue::JsonString(resource_path),
      prefix: "",
      aliases: [],
      attributes_path: None,
    }),
    category,
    event_type: @moonforensics.ProfileStringValue::JsonString(event_type_path),
    action: None,
    outcome: @moonforensics.EventOutcome::Unknown,
    body_path: None,
  }
}

///|
fn cross_evidence(id : String) -> @moonforensics.ProfileEvidence {
  @moonforensics.ProfileEvidence::{
    evidence_id: id,
    path: "fixtures/\{id}.jsonl",
    sha256: None,
  }
}

///|
test "config and health schemas share a reusable config analysis pack" {
  let config_profile = cross_profile(
    "config-controller-v1",
    cross_path(["producer"]),
    cross_path(["change_id"]),
    cross_path(["applied_at"]),
    cross_path(["service"]),
    cross_path(["kind"]),
    @moonforensics.EventCategory::Change,
  )
  let health_profile = cross_profile(
    "health-monitor-v2",
    cross_path(["agent", "name"]),
    cross_path(["check_id"]),
    cross_path(["observed_at"]),
    cross_path(["target", "service"]),
    cross_path(["event_type"]),
    @moonforensics.EventCategory::Availability,
  )
  let config_records = try! @moonforensics.parse_jsonl(
    (
      #|{"change_id":"cfg-1","applied_at":"2026-09-20T00:00:00Z","producer":"config-controller","service":"orders","kind":"config.update"}
      #|
    ),
  )
  let health_records = try! @moonforensics.parse_jsonl(
    (
      #|{"check_id":"health-1","observed_at":"2026-09-20T00:00:30Z","agent":{"name":"health-monitor"},"target":{"service":"orders"},"event_type":"health.failed"}
      #|
    ),
  )
  let config_events = try! @moonforensics.apply_jsonl_profile(
    config_records,
    config_profile,
    cross_evidence("config"),
  )
  let health_events = try! @moonforensics.apply_jsonl_profile(
    health_records,
    health_profile,
    cross_evidence("health"),
  )
  let graph = try! @moonforensics.analyze_with_pack(
    config_events + health_events,
    @moonforensics.config_analysis_pack(),
  )
  assert_eq(graph.edges.length(), 1)
  assert_eq(graph.edges[0].rule_id, Some("config-change-then-health-failure"))
  assert_eq(graph.edges[0].evidence_refs[0].profile_id, "config-controller-v1")
  assert_eq(graph.edges[0].evidence_refs[1].profile_id, "health-monitor-v2")
  assert_eq(graph.edges[0].resource_key.unwrap().id, "orders")
}

///|
test "process and health schemas share a reusable crash analysis pack" {
  let process_profile = cross_profile(
    "service-manager-v1",
    cross_path(["producer"]),
    cross_path(["pid"]),
    cross_path(["exited_at"]),
    cross_path(["service"]),
    cross_path(["event"]),
    @moonforensics.EventCategory::Process,
  )
  let health_profile = cross_profile(
    "probe-result-v1",
    cross_path(["probe"]),
    cross_path(["id"]),
    cross_path(["checked_at"]),
    cross_path(["target", "name"]),
    cross_path(["status"]),
    @moonforensics.EventCategory::Availability,
  )
  let process_records = try! @moonforensics.parse_jsonl(
    (
      #|{"pid":"proc-1","exited_at":"2026-09-20T01:00:00Z","producer":"service-manager","service":"payments","event":"process.exit"}
      #|
    ),
  )
  let health_records = try! @moonforensics.parse_jsonl(
    (
      #|{"id":"probe-1","checked_at":"2026-09-20T01:01:00Z","probe":"health-probe","target":{"name":"payments"},"status":"health.failed"}
      #|
    ),
  )
  let process_events = try! @moonforensics.apply_jsonl_profile(
    process_records,
    process_profile,
    cross_evidence("process"),
  )
  let health_events = try! @moonforensics.apply_jsonl_profile(
    health_records,
    health_profile,
    cross_evidence("probe"),
  )
  let events = process_events + health_events
  let graph = try! @moonforensics.analyze_with_pack(
    events,
    @moonforensics.crash_analysis_pack(),
  )
  assert_eq(graph.edges.length(), 1)
  assert_eq(graph.edges[0].rule_id, Some("crash-then-health-failure"))
  assert_eq(graph.edges[0].delta_seconds, Some(60))
}

///|
test "latency and gateway schemas share a reusable latency analysis pack" {
  let latency_profile = cross_profile(
    "metrics-v3",
    cross_path(["emitter"]),
    cross_path(["span", "id"]),
    cross_path(["recorded_at"]),
    cross_path(["service", "name"]),
    cross_path(["kind"]),
    @moonforensics.EventCategory::Performance,
  )
  let gateway_profile = cross_profile(
    "gateway-v1",
    cross_path(["component"]),
    cross_path(["request_id"]),
    cross_path(["timestamp"]),
    cross_path(["backend"]),
    cross_path(["type"]),
    @moonforensics.EventCategory::Availability,
  )
  let latency_records = try! @moonforensics.parse_jsonl(
    (
      #|{"span":{"id":"span-1"},"recorded_at":"2026-09-20T02:00:00Z","emitter":"metrics-agent","service":{"name":"catalog"},"kind":"request.latency"}
      #|
    ),
  )
  let gateway_records = try! @moonforensics.parse_jsonl(
    (
      #|{"request_id":"req-1","timestamp":"2026-09-20T02:00:45Z","component":"edge-gateway","backend":"catalog","type":"request.timeout"}
      #|
    ),
  )
  let latency_events = try! @moonforensics.apply_jsonl_profile(
    latency_records,
    latency_profile,
    cross_evidence("latency"),
  )
  let gateway_events = try! @moonforensics.apply_jsonl_profile(
    gateway_records,
    gateway_profile,
    cross_evidence("gateway"),
  )
  let events = latency_events + gateway_events
  let graph = try! @moonforensics.analyze_with_pack(
    events,
    @moonforensics.latency_analysis_pack(),
  )
  assert_eq(graph.edges.length(), 1)
  assert_eq(graph.edges[0].rule_id, Some("latency-then-timeout"))
  assert_eq(graph.edges[0].resource_key.unwrap().id, "catalog")
}
