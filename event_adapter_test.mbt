///|
fn adapter_json_mapping() -> @moonforensics.JsonlEventMapping {
  @moonforensics.JsonlEventMapping::{
    system: "fixture",
    source_field: "source",
    event_id_field: "event_id",
    timestamp_field: "timestamp",
    severity_field: "severity",
    resource_field: Some("resource"),
    resource_override: None,
    kind: @moonforensics.CorrelationKind::Alert,
    evidence_id: "gateway.jsonl",
  }
}

///|
test "jsonl adapter creates a reusable event contract" {
  let records = @moonforensics.parse_jsonl(
    (
      #|{"event_id":"evt-1","timestamp":"2026-03-08T09:00:00Z","source":"gateway","severity":"WARN","resource":"orders-api-01","attributes":{"latency_ms":1800}}
    ),
  )
  let events = @moonforensics.adapt_jsonl_records(
    records,
    adapter_json_mapping(),
  )
  assert_eq(events.length(), 1)
  assert_eq(events[0].event_id, "evt-1")
  assert_eq(events[0].resource_id, Some("orders-api-01"))
  assert_eq(events[0].kind, @moonforensics.CorrelationKind::Alert)
  assert_eq(events[0].evidence.line_number, 1)
  assert_true(events[0].attributes is { "attributes": Object(_), .. })
}

///|
test "jsonl adapter uses an explicit resource override" {
  let records = @moonforensics.parse_jsonl(
    (
      #|{"event_id":"cfg-1","timestamp":"2026-03-08T09:00:00Z","source":"config-controller","severity":"INFO","resource":"orders-api/database.pool.max"}
    ),
  )
  let mapping = {
    ..adapter_json_mapping(),
    resource_field: None,
    resource_override: Some("service:orders-api"),
    kind: @moonforensics.CorrelationKind::Change,
  }
  let events = @moonforensics.adapt_jsonl_records(records, mapping)
  assert_eq(events[0].resource_id, Some("service:orders-api"))
}

///|
test "jsonl adapter rejects an empty resource identity" {
  let records = @moonforensics.parse_jsonl(
    (
      #|{"event_id":"evt-1","timestamp":"2026-03-08T09:00:00Z","source":"gateway","severity":"WARN","resource":""}
    ),
  )
  try
    @moonforensics.adapt_jsonl_records(records, adapter_json_mapping())
  catch {
    @moonforensics.EventAdaptError::InvalidField(line_number~, field~, ..) => {
      assert_eq(line_number, 1)
      assert_eq(field, "resource")
    }
    _ => fail("expected empty resource to fail")
  } noraise {
    _ => fail("expected empty resource to fail")
  }
}

///|
test "plain text adapter preserves line evidence and rejects malformed text" {
  let records = @moonforensics.parse_plain_text(
    "2026-03-08T09:00:40Z ERROR health_check_failed service=orders-api\n",
  )
  let events = @moonforensics.adapt_plain_text_records(records, @moonforensics.PlainTextEventMapping::{
    system: "fixture",
    component: "health-check",
    resource_id: Some("service:orders-api"),
    kind: @moonforensics.CorrelationKind::Alert,
    evidence_id: "health.log",
  })
  assert_eq(events[0].event_id, "health.log:1")
  assert_eq(events[0].normalized.raw_content, records[0].text)
  assert_eq(events[0].evidence.line_number, 1)

  try
    @moonforensics.adapt_plain_text_records(records, @moonforensics.PlainTextEventMapping::{
      system: "fixture",
      component: "health-check",
      resource_id: Some("  "),
      kind: @moonforensics.CorrelationKind::Alert,
      evidence_id: "broken-resource.log",
    })
  catch {
    @moonforensics.EventAdaptError::InvalidText(line_number~, reason~) => {
      assert_eq(line_number, 1)
      assert_true(reason.contains("resource_id"))
    }
    _ => fail("expected empty text resource to fail")
  } noraise {
    _ => fail("expected empty text resource to fail")
  }

  try
    @moonforensics.adapt_plain_text_records(
      @moonforensics.parse_plain_text("not-a-timestamp\n"),
      @moonforensics.PlainTextEventMapping::{
        system: "fixture",
        component: "health-check",
        resource_id: None,
        kind: @moonforensics.CorrelationKind::Alert,
        evidence_id: "broken.log",
      },
    )
  catch {
    @moonforensics.EventAdaptError::InvalidText(line_number~, reason~) => {
      assert_eq(line_number, 1)
      assert_true(reason.contains("timestamp"))
    }
    _ => fail("expected malformed text to fail")
  } noraise {
    _ => fail("expected malformed text to fail")
  }
}

///|
test "adapted events correlate without hand-built correlation records" {
  let json_events = @moonforensics.adapt_jsonl_records(
    @moonforensics.parse_jsonl(
      (
        #|{"event_id":"change-1","timestamp":"2026-03-08T09:00:00Z","source":"config","severity":"INFO","resource":"orders-api"}
      ),
    ),
    {
      ..adapter_json_mapping(),
      resource_field: Some("resource"),
      kind: @moonforensics.CorrelationKind::Change,
    },
  )
  let text_events = @moonforensics.adapt_plain_text_records(
    @moonforensics.parse_plain_text(
      "2026-03-08T09:00:40Z ERROR health_check_failed service=orders-api\n",
    ),
    @moonforensics.PlainTextEventMapping::{
      system: "fixture",
      component: "health-check",
      resource_id: Some("orders-api"),
      kind: @moonforensics.CorrelationKind::Alert,
      evidence_id: "health.log",
    },
  )
  let events = json_events + text_events
  let groups = @moonforensics.correlate_incident_events(events, 60)
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].events.length(), 2)
}
