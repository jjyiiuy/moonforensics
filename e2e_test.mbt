///|
fn e2e_case(case_id : String, title : String) -> @moonforensics.Case {
  @moonforensics.Case::{
    case_id,
    title,
    timezone: "UTC",
    collected_at: @moonforensics.Timestamp::{ value: "2026-03-08T09:05:00Z", },
    evidence: [],
    metadata: @moonforensics.EvidenceMetadata::{ entries: [], },
  }
}

///|
test "service crash fixture runs through ingest normalize timeline and correlation" {
  let process_events =
    #|{"event_id":"proc-001","timestamp":"2026-01-15T10:03:14Z","source":"service-manager","severity":"ERROR","kind":"process","resource":"checkout-api-01","message":"Process exited with a non-zero status"}
    #|{"event_id":"proc-002","timestamp":"2026-01-15T10:03:20Z","source":"service-manager","severity":"INFO","kind":"process","resource":"checkout-api-01","message":"Service restart scheduled"}
    #|{"event_id":"proc-003","timestamp":"2026-01-15T10:03:24Z","source":"service-manager","severity":"INFO","kind":"process","resource":"checkout-api-01","message":"Replacement process is running"}
  let records = @moonforensics.parse_jsonl(process_events)
  let app_log =
    #|2026-01-15T10:03:13Z ERROR fatal_allocation_failure service=checkout-api requested_bytes=8388608
  let app_records = @moonforensics.parse_plain_text(app_log)
  assert_eq(records.length(), 3)
  assert_eq(app_records.length(), 1)

  let process_events = @moonforensics.adapt_jsonl_records(records, @moonforensics.JsonlEventMapping::{
    system: "fixture",
    source_field: "source",
    event_id_field: "event_id",
    timestamp_field: "timestamp",
    severity_field: "severity",
    resource_field: Some("resource"),
    resource_override: None,
    kind: @moonforensics.CorrelationKind::Alert,
    evidence_id: "process-events.jsonl",
  })
  let app_events = @moonforensics.adapt_plain_text_records(app_records, @moonforensics.PlainTextEventMapping::{
    system: "fixture",
    component: "checkout-api",
    resource_id: Some("checkout-api-01"),
    kind: @moonforensics.CorrelationKind::Crash,
    evidence_id: "app.log",
  })
  let events = app_events + process_events
  let timeline = @moonforensics.incident_timeline(events)
  assert_eq(timeline.events[0].raw_content, app_log.trim_end().to_owned())
  let groups = @moonforensics.correlate_incident_events(events, 5)
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].events.length(), 2)
}

///|
test "performance degradation fixture joins JSONL metrics with gateway logs" {
  let metrics =
    #|{"event_id":"metric-001","timestamp":"2026-02-03T14:20:00Z","source":"metrics-agent","severity":"INFO","kind":"metric","resource":"catalog-api-02","message":"Resource and latency snapshot"}
    #|{"event_id":"metric-002","timestamp":"2026-02-03T14:22:00Z","source":"metrics-agent","severity":"WARN","kind":"metric","resource":"catalog-api-02","message":"Resource and latency snapshot"}
    #|{"event_id":"metric-003","timestamp":"2026-02-03T14:24:00Z","source":"metrics-agent","severity":"WARN","kind":"metric","resource":"catalog-api-02","message":"Resource and latency snapshot"}
    #|{"event_id":"metric-004","timestamp":"2026-02-03T14:27:00Z","source":"metrics-agent","severity":"INFO","kind":"metric","resource":"catalog-api-02","message":"Resource and latency snapshot"}
  let gateway_log =
    #|2026-02-03T14:21:58Z WARN upstream_slow service=catalog-api instance=catalog-api-02 elapsed_ms=1320
    #|2026-02-03T14:23:17Z ERROR upstream_timeout service=catalog-api instance=catalog-api-02 timeout_ms=2000
    #|2026-02-03T14:24:42Z ERROR upstream_timeout service=catalog-api instance=catalog-api-02 timeout_ms=2000
    #|2026-02-03T14:27:05Z INFO upstream_recovered service=catalog-api instance=catalog-api-02 elapsed_ms=280
  let metric_records = @moonforensics.parse_jsonl(metrics)
  let gateway_records = @moonforensics.parse_plain_text(gateway_log)
  assert_eq(metric_records.length(), 4)
  assert_eq(gateway_records.length(), 4)

  let metric_events = @moonforensics.adapt_jsonl_records(metric_records, @moonforensics.JsonlEventMapping::{
    system: "fixture",
    source_field: "source",
    event_id_field: "event_id",
    timestamp_field: "timestamp",
    severity_field: "severity",
    resource_field: Some("resource"),
    resource_override: None,
    kind: @moonforensics.CorrelationKind::Other("metric"),
    evidence_id: "metrics.jsonl",
  })
  let gateway_events = @moonforensics.adapt_plain_text_records(
    gateway_records,
    @moonforensics.PlainTextEventMapping::{
      system: "fixture",
      component: "edge-gateway",
      resource_id: Some("catalog-api-02"),
      kind: @moonforensics.CorrelationKind::Alert,
      evidence_id: "gateway.log",
    },
  )
  let events = [metric_events[1], gateway_events[1]]
  let timeline = @moonforensics.incident_timeline(events)
  let window = @moonforensics.query_timeline_window(
    timeline,
    try! @moonforensics.normalize_timestamp("2026-02-03T14:22:00Z"),
    try! @moonforensics.normalize_timestamp("2026-02-03T14:24:00Z"),
  )
  assert_eq(window.events.length(), 2)
  let groups = @moonforensics.correlate_incident_events(events, 120)
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].events.length(), 2)
}

///|
test "config change fixture renders a report with a temporal hypothesis" {
  let changes =
    #|{"event_id":"config-001","timestamp":"2026-03-08T09:00:00Z","source":"config-controller","severity":"INFO","kind":"config","resource":"orders-api/database.pool.max","message":"Configuration value applied"}
    #|{"event_id":"config-002","timestamp":"2026-03-08T09:02:00Z","source":"config-controller","severity":"WARN","kind":"config","resource":"orders-api/database.pool.max","message":"Configuration revision rolled back"}
  let health_log =
    #|2026-03-08T08:59:40Z INFO health_check_passed service=orders-api instance=orders-api-01
    #|2026-03-08T09:00:25Z WARN health_check_degraded service=orders-api instance=orders-api-01 latency_ms=1800
    #|2026-03-08T09:00:40Z ERROR health_check_failed service=orders-api instance=orders-api-01 reason=database_pool_timeout
    #|2026-03-08T09:02:30Z INFO health_check_passed service=orders-api instance=orders-api-01
  let change_records = @moonforensics.parse_jsonl(changes)
  let health_records = @moonforensics.parse_plain_text(health_log)
  assert_eq(change_records.length(), 2)
  assert_eq(health_records.length(), 4)

  let change_events = @moonforensics.adapt_jsonl_records(change_records, @moonforensics.JsonlEventMapping::{
    system: "fixture",
    source_field: "source",
    event_id_field: "event_id",
    timestamp_field: "timestamp",
    severity_field: "severity",
    resource_field: None,
    resource_override: Some("orders-api-01"),
    kind: @moonforensics.CorrelationKind::Change,
    evidence_id: "changes.jsonl",
  })
  let health_events = @moonforensics.adapt_plain_text_records(health_records, @moonforensics.PlainTextEventMapping::{
    system: "fixture",
    component: "health-monitor",
    resource_id: Some("orders-api-01"),
    kind: @moonforensics.CorrelationKind::Alert,
    evidence_id: "health.log",
  })
  let change_event = change_events[0]
  let alert_event = health_events[2]
  let correlated = @moonforensics.correlate_incident_events(
    [change_event, alert_event],
    60,
  )
  assert_eq(correlated.length(), 1)

  let timeline = @moonforensics.incident_timeline([change_event, alert_event])
  let report = @moonforensics.ForensicReport::{
    case: e2e_case(
      "incident-config-change", "Orders API health failure after pool change",
    ),
    summary: "A health failure followed a configuration change.",
    timeline,
    findings: @moonforensics.DiagnosticReport::{ findings: [], },
    evidence_index: @moonforensics.EvidenceManifest::{ entries: [], },
    limitations: ["Correlation is temporal evidence, not confirmed causation."],
  }
  let markdown = @moonforensics.render_markdown_report(report)
  let json = @moonforensics.render_json_report(report)
  assert_true(markdown.contains("## 时间线"))
  assert_true(markdown.contains("## 限制说明"))
  assert_true(markdown.contains("health_check_failed"))
  assert_true(json.contains("incident-config-change"))
  assert_true(json.contains("limitations"))
}

///|
test "damaged evidence fails manifest verification" {
  let source = @moonforensics.EvidenceSource::{
    system: "fixture",
    component: "service-crash",
    host: Some("fixture-host"),
  }
  let original = @moonforensics.EvidenceDocument::{
    id: "process-events",
    path: "process-events.jsonl",
    source,
    content: b"original evidence",
  }
  let manifest = @moonforensics.build_evidence_manifest([original])
  let damaged = @moonforensics.EvidenceDocument::{
    id: "process-events",
    path: "process-events.jsonl",
    source,
    content: b"tampered evidence",
  }
  assert_false(@moonforensics.verify_evidence_manifest(manifest, [damaged]))
}
