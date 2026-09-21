///|
fn processor_event(
  event_id : String,
  source_system : String,
  source_component : String,
  timestamp : String?,
  resource_id : String?,
) -> @moonforensics.CanonicalEvent {
  let event_time = match timestamp {
    Some(value) => Some(try! @moonforensics.normalize_timestamp(value))
    None => None
  }
  @moonforensics.CanonicalEvent::{
    event_id,
    event_time,
    observed_time: None,
    source: @moonforensics.TelemetrySource::{
      system: source_system,
      component: source_component,
      host: None,
      instrumentation_scope: None,
    },
    resource: match resource_id {
      Some(id) =>
        Some(@moonforensics.ResourceRef::{
          kind: @moonforensics.ResourceKind::Service,
          id,
          attributes: { "fixture": true },
        })
      None => None
    },
    category: @moonforensics.EventCategory::Availability,
    event_type: "health.failed",
    action: Some(" probe "),
    outcome: @moonforensics.EventOutcome::Failure,
    severity: Some(@moonforensics.Severity::Error),
    body: "fixture body",
    raw_content: "raw fixture content",
    attributes: { "keep": "original" },
    provenance: @moonforensics.EventProvenance::{
      evidence_id: "fixture.jsonl",
      path: "fixtures/fixture.jsonl",
      line_number: Some(1),
      byte_offset: None,
      byte_length: None,
      sha256: Some("fixture-sha256"),
      profile_id: "fixture-profile",
      profile_version: "1",
    },
  }
}

///|
test "processor stages transform and filter deterministically" {
  let event = processor_event(
    " evt-1 ",
    " svc ",
    " api ",
    Some("2026-09-20T00:00:00Z"),
    Some("orders-v1"),
  )
  let pipeline = @moonforensics.ProcessorPipeline::{
    name: "normalize-and-alias",
    stages: [
      @moonforensics.ProcessorStage::Normalize,
      @moonforensics.ProcessorStage::AliasResource(@moonforensics.ResourceAlias::{
        source_id: "orders-v1",
        canonical_id: "orders",
      }),
      @moonforensics.ProcessorStage::FilterSource("svc/api"),
      @moonforensics.ProcessorStage::FilterResource("orders"),
    ],
  }
  let result = try! @moonforensics.process_events([event], pipeline)
  assert_eq(result.length(), 1)
  assert_eq(result[0].event_id, "evt-1")
  assert_eq(result[0].source.system, "svc")
  assert_eq(result[0].source.component, "api")
  assert_eq(result[0].resource.unwrap().id, "orders")
  assert_eq(result[0].action, Some("probe"))
  assert_eq(result[0].raw_content, "raw fixture content")
  assert_eq(result[0].provenance.evidence_id, "fixture.jsonl")
}

///|
test "time window is inclusive and keeps input order" {
  let start = "2026-09-20T00:00:00Z"
  let end = "2026-09-20T00:02:00Z"
  let pipeline = @moonforensics.ProcessorPipeline::{
    name: "window",
    stages: [
      @moonforensics.ProcessorStage::FilterTimeWindow(
        try! @moonforensics.normalize_timestamp(start),
        try! @moonforensics.normalize_timestamp(end),
      ),
    ],
  }
  let events = [
    processor_event("middle", "svc", "api", Some("2026-09-20T00:01:00Z"), None),
    processor_event("no-time", "svc", "api", None, None),
    processor_event("end", "svc", "api", Some(end), None),
    processor_event("start", "svc", "api", Some(start), None),
  ]
  let result = try! @moonforensics.process_events(events, pipeline)
  assert_eq(result.map(event => event.event_id), ["middle", "end", "start"])
}

///|
test "invalid processor configuration fails before transformation" {
  let start = try! @moonforensics.normalize_timestamp("2026-09-20T00:02:00Z")
  let end = try! @moonforensics.normalize_timestamp("2026-09-20T00:01:00Z")
  let pipeline = @moonforensics.ProcessorPipeline::{
    name: "invalid-window",
    stages: [@moonforensics.ProcessorStage::FilterTimeWindow(start, end)],
  }
  try @moonforensics.process_events([], pipeline) catch {
    @moonforensics.ProcessorError::InvalidWindow => ()
    _ => fail("expected InvalidWindow")
  } noraise {
    _ => fail("expected InvalidWindow")
  }
}

///|
test "empty stage values are rejected" {
  let pipeline = @moonforensics.ProcessorPipeline::{
    name: "invalid-filter",
    stages: [@moonforensics.ProcessorStage::FilterSource(" ")],
  }
  try @moonforensics.process_events([], pipeline) catch {
    @moonforensics.ProcessorError::InvalidStage(reason) =>
      assert_true(reason.contains("source"))
    _ => fail("expected InvalidStage")
  } noraise {
    _ => fail("expected InvalidStage")
  }
}
