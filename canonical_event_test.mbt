///|
fn canonical_source() -> @moonforensics.TelemetrySource {
  @moonforensics.TelemetrySource::{
    system: "checkout",
    component: "api",
    host: Some("node-01"),
    instrumentation_scope: Some("runtime/v1"),
  }
}

///|
fn canonical_provenance() -> @moonforensics.EventProvenance {
  @moonforensics.EventProvenance::{
    evidence_id: "app.log",
    path: "service-crash/app.log",
    line_number: Some(3),
    byte_offset: Some(128),
    byte_length: Some(84),
    sha256: Some("fixture-sha256"),
    profile_id: "timestamp-severity-text",
    profile_version: "v1",
  }
}

///|
fn canonical_resource() -> @moonforensics.ResourceRef {
  @moonforensics.ResourceRef::{
    kind: @moonforensics.ResourceKind::Instance,
    id: "checkout-api-01",
    attributes: { "service.name": "checkout-api", "environment": "fixture" },
  }
}

///|
test "canonical event keeps typed resource and provenance" {
  let timestamp = try! @moonforensics.normalize_timestamp(
    "2026-01-15T10:03:13Z",
  )
  let event = @moonforensics.CanonicalEvent::{
    event_id: "app.log:3",
    event_time: Some(timestamp),
    observed_time: None,
    source: canonical_source(),
    resource: Some(canonical_resource()),
    category: @moonforensics.EventCategory::Process,
    event_type: "process.error",
    action: Some("allocate"),
    outcome: @moonforensics.EventOutcome::Failure,
    severity: Some(@moonforensics.Severity::Error),
    body: "fatal_allocation_failure",
    raw_content: "2026-01-15T10:03:13Z ERROR fatal_allocation_failure",
    attributes: { "requested_bytes": 8388608 },
    provenance: canonical_provenance(),
  }
  assert_eq(event.resource.unwrap().kind, @moonforensics.ResourceKind::Instance)
  assert_eq(event.resource.unwrap().id, "checkout-api-01")
  assert_eq(event.provenance.line_number, Some(3))
  assert_eq(event.provenance.profile_version, "v1")
  assert_true(event.body is String("fatal_allocation_failure"))
}

///|
test "canonical event provides a stable legacy timeline view" {
  let timestamp = try! @moonforensics.normalize_timestamp(
    "2026-01-15T10:03:13Z",
  )
  let event = @moonforensics.CanonicalEvent::{
    event_id: "evt-1",
    event_time: Some(timestamp),
    observed_time: None,
    source: canonical_source(),
    resource: None,
    category: @moonforensics.EventCategory::Availability,
    event_type: "health.failed",
    action: None,
    outcome: @moonforensics.EventOutcome::Failure,
    severity: Some(@moonforensics.Severity::Error),
    body: "health_check_failed",
    raw_content: "raw-health-line",
    attributes: {},
    provenance: canonical_provenance(),
  }
  let normalized = event.to_normalized_event()
  assert_eq(normalized.source_id, "checkout/api/node-01")
  assert_eq(normalized.raw_content, "raw-health-line")
  assert_eq(normalized.severity, Some(@moonforensics.Severity::Error))
  assert_eq(normalized.timestamp, Some(timestamp))
}

///|
test "incident event bridge keeps adapter attributes and explicit classification" {
  let timestamp = try! @moonforensics.normalize_timestamp(
    "2026-03-08T09:00:00Z",
  )
  let incident = @moonforensics.IncidentEvent::{
    event_id: "cfg-1",
    normalized: @moonforensics.NormalizedEvent::{
      timestamp: Some(timestamp),
      severity: Some(@moonforensics.Severity::Info),
      source_id: "config/controller",
      raw_content: "configuration applied",
    },
    resource_id: Some("service:orders-api"),
    kind: @moonforensics.CorrelationKind::Change,
    attributes: { "old_value": 40, "new_value": 4 },
    evidence: @moonforensics.EventEvidence::{
      evidence_id: "changes.jsonl",
      line_number: 1,
    },
  }
  let canonical = @moonforensics.canonicalize_incident_event(
    incident,
    canonical_source(),
    Some(canonical_resource()),
    @moonforensics.EventCategory::Change,
    "config.update",
    Some("apply"),
    @moonforensics.EventOutcome::Success,
    None,
    canonical_provenance(),
  )
  assert_eq(canonical.event_id, "cfg-1")
  assert_eq(canonical.category, @moonforensics.EventCategory::Change)
  assert_eq(canonical.event_type, "config.update")
  assert_eq(canonical.attributes, { "old_value": 40, "new_value": 4 })
}

///|
test "legacy incident event bridge preserves source and evidence" {
  let timestamp = try! @moonforensics.normalize_timestamp(
    "2026-03-08T09:00:40Z",
  )
  let incident = @moonforensics.IncidentEvent::{
    event_id: "health-1",
    normalized: @moonforensics.NormalizedEvent::{
      timestamp: Some(timestamp),
      severity: Some(@moonforensics.Severity::Error),
      source_id: "health/checker",
      raw_content: "health check failed",
    },
    resource_id: Some("orders-api"),
    kind: @moonforensics.CorrelationKind::Alert,
    attributes: { "reason": "timeout" },
    evidence: @moonforensics.EventEvidence::{
      evidence_id: "health.log",
      line_number: 4,
    },
  }
  let canonical = incident.to_canonical_event()
  assert_eq(canonical.source.system, "health/checker")
  assert_eq(canonical.source.component, "")
  assert_eq(canonical.to_normalized_event().source_id, "health/checker")
  assert_eq(canonical.resource.unwrap().id, "orders-api")
  assert_eq(
    canonical.resource.unwrap().kind,
    @moonforensics.ResourceKind::Custom("legacy"),
  )
  assert_eq(canonical.category, @moonforensics.EventCategory::Availability)
  assert_eq(canonical.event_type, "legacy.alert")
  assert_eq(canonical.provenance.evidence_id, "health.log")
  assert_eq(canonical.provenance.line_number, Some(4))
  assert_eq(canonical.provenance.profile_id, "legacy-adapter")
}

///|
test "incident graph keeps relation explanation and status" {
  let graph = @moonforensics.IncidentGraph::{
    nodes: [],
    edges: [
      @moonforensics.EvidenceRelation::{
        relation_id: "rel-1",
        relation_type: @moonforensics.RelationType::TemporalBefore,
        from_event_id: "cfg-1",
        to_event_id: "health-1",
        rule_id: Some("change-then-failure"),
        resource_key: Some(canonical_resource()),
        delta_seconds: Some(40),
        evidence_refs: [canonical_provenance()],
        explanation: "The failure followed the configuration change within 60s.",
        status: @moonforensics.RelationStatus::Hypothesis,
      },
    ],
    diagnostics: [],
  }
  assert_eq(graph.edges.length(), 1)
  assert_eq(graph.edges[0].rule_id, Some("change-then-failure"))
  assert_eq(graph.edges[0].delta_seconds, Some(40))
  assert_eq(graph.edges[0].status, @moonforensics.RelationStatus::Hypothesis)
}
