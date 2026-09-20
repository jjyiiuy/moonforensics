///|
fn nested_jsonl_profile() -> @moonforensics.JsonlMappingProfile {
  @moonforensics.JsonlMappingProfile::{
    id: "acme-service-log",
    version: "1.0.0",
    source: @moonforensics.SourceMappingProfile::{
      system: @moonforensics.ProfileStringValue::Constant("acme"),
      component: @moonforensics.ProfileStringValue::JsonString({
        segments: ["service", "name"],
      }),
      host: Some(
        @moonforensics.ProfileStringValue::JsonString({ segments: ["host"], }),
      ),
      instrumentation_scope: None,
    },
    event_id: @moonforensics.ProfileStringValue::JsonString({
      segments: ["event", "id"],
    }),
    event_time: Some({ segments: ["event", "time"], }),
    observed_time: None,
    severity: Some({ segments: ["log", "level"], }),
    resource: Some(@moonforensics.ResourceMappingProfile::{
      kind: @moonforensics.ResourceKind::Service,
      id: @moonforensics.ProfileStringValue::JsonString({
        segments: ["service", "name"],
      }),
      prefix: "service:",
      aliases: [
        @moonforensics.ResourceAlias::{
          source_id: "checkout-v1",
          canonical_id: "service:checkout",
        },
      ],
      attributes_path: Some({ segments: ["service"], }),
    }),
    category: @moonforensics.EventCategory::Availability,
    event_type: @moonforensics.ProfileStringValue::Constant("health.failed"),
    action: Some(
      @moonforensics.ProfileStringValue::JsonString({
        segments: ["event", "action"],
      }),
    ),
    outcome: @moonforensics.EventOutcome::Failure,
    body_path: Some({ segments: ["message"], }),
  }
}

///|
fn profile_evidence(id : String) -> @moonforensics.ProfileEvidence {
  @moonforensics.ProfileEvidence::{
    evidence_id: id,
    path: "fixtures/\{id}",
    sha256: Some("fixture-sha256"),
  }
}

///|
test "profile maps nested JSON and records its identity" {
  let records = try! @moonforensics.parse_jsonl(
    (
      #|{"event":{"id":"evt-1","time":"2026-09-20T08:00:00+08:00","action":"probe"},"service":{"name":"checkout-v1","zone":"cn-east"},"host":"node-01","log":{"level":"ERROR"},"message":"health check failed"}
      #|
    ),
  )
  let events = try! @moonforensics.apply_jsonl_profile(
    records,
    nested_jsonl_profile(),
    profile_evidence("health.jsonl"),
  )
  assert_eq(events.length(), 1)
  assert_eq(events[0].event_id, "evt-1")
  assert_eq(events[0].source.component, "checkout-v1")
  assert_eq(events[0].source.host, Some("node-01"))
  assert_eq(events[0].severity, Some(@moonforensics.Severity::Error))
  assert_eq(events[0].resource.unwrap().id, "service:checkout")
  assert_eq(events[0].resource.unwrap().attributes, {
    "name": "checkout-v1",
    "zone": "cn-east",
  })
  assert_true(events[0].body is String("health check failed"))
  assert_eq(events[0].provenance.line_number, Some(1))
  assert_eq(events[0].provenance.profile_id, "acme-service-log")
  assert_eq(events[0].provenance.profile_version, "1.0.0")
}

///|
test "one profile is reusable across evidence streams" {
  let first = try! @moonforensics.parse_jsonl(
    (
      #|{"event":{"id":"evt-1","time":"2026-09-20T00:00:00Z"},"service":{"name":"orders"},"message":"unhealthy"}
      #|
    ),
  )
  let second = try! @moonforensics.parse_jsonl(
    (
      #|{"event":{"id":"evt-2","time":"2026-09-20T00:01:00Z"},"service":{"name":"orders"},"message":"still unhealthy"}
      #|
    ),
  )
  let first_events = try! @moonforensics.apply_jsonl_profile(
    first,
    nested_jsonl_profile(),
    profile_evidence("first.jsonl"),
  )
  let second_events = try! @moonforensics.apply_jsonl_profile(
    second,
    nested_jsonl_profile(),
    profile_evidence("second.jsonl"),
  )
  assert_eq(first_events[0].resource, second_events[0].resource)
  assert_eq(first_events[0].source.host, None)
  assert_eq(first_events[0].severity, None)
  assert_eq(first_events[0].action, None)
  assert_eq(first_events[0].provenance.evidence_id, "first.jsonl")
  assert_eq(second_events[0].provenance.evidence_id, "second.jsonl")
}

///|
test "profile validation rejects ambiguous aliases" {
  let profile = {
    ..nested_jsonl_profile(),
    resource: Some(@moonforensics.ResourceMappingProfile::{
      kind: @moonforensics.ResourceKind::Service,
      id: @moonforensics.ProfileStringValue::JsonString({
        segments: ["service", "name"],
      }),
      prefix: "service:",
      aliases: [
        @moonforensics.ResourceAlias::{
          source_id: "orders",
          canonical_id: "service:orders",
        },
        @moonforensics.ResourceAlias::{
          source_id: "orders",
          canonical_id: "service:orders-v2",
        },
      ],
      attributes_path: None,
    }),
  }
  try @moonforensics.validate_jsonl_profile(profile) catch {
    @moonforensics.ProfileMapError::InvalidProfile(field~, reason~) => {
      assert_eq(field, "resource.aliases")
      assert_true(reason.contains("duplicate"))
    }
    _ => fail("expected InvalidProfile")
  } noraise {
    _ => fail("expected InvalidProfile")
  }
}

///|
test "profile reports the physical line and missing nested path" {
  let records = try! @moonforensics.parse_jsonl(
    (
      #|{"event":{"id":"evt-1","time":"2026-09-20T00:00:00Z"},"service":{"name":"orders"},"message":"ok"}
      #|{"event":{"time":"2026-09-20T00:01:00Z"},"service":{"name":"orders"},"message":"missing id"}
      #|
    ),
  )
  try
    @moonforensics.apply_jsonl_profile(
      records,
      nested_jsonl_profile(),
      profile_evidence("broken.jsonl"),
    )
  catch {
    @moonforensics.ProfileMapError::MissingValue(line_number~, path~) => {
      assert_eq(line_number, 2)
      assert_eq(path, "event.id")
    }
    _ => fail("expected MissingValue")
  } noraise {
    _ => fail("expected MissingValue")
  }
}
