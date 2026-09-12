///|
test "case preserves evidence provenance and metadata" {
  let collected_at = @moonforensics.Timestamp::{
    value: "2026-01-15T10:05:00Z",
  }
  let captured_at = @moonforensics.Timestamp::{ value: "2026-01-15T10:03:14Z", }
  let source = @moonforensics.EvidenceSource::{
    system: "service-manager",
    component: "restart-controller",
    host: Some("checkout-api-01"),
  }
  let evidence_metadata = @moonforensics.EvidenceMetadata::{
    entries: [
      @moonforensics.MetadataEntry::{
        key: "retention",
        value: "incident-review",
      },
    ],
  }
  let evidence = @moonforensics.EvidenceItem::{
    id: "service-manager-events",
    source,
    path: "process-events.jsonl",
    format: @moonforensics.EvidenceFormat::JsonLines,
    captured_at: Some(captured_at),
    metadata: evidence_metadata,
  }
  let incident = @moonforensics.Case::{
    case_id: "incident-service-crash",
    title: "Checkout API unexpected exit",
    timezone: "UTC",
    collected_at,
    evidence: [evidence],
    metadata: @moonforensics.EvidenceMetadata::{
      entries: [
        @moonforensics.MetadataEntry::{ key: "environment", value: "fixture", },
      ],
    },
  }

  assert_eq(incident.case_id, "incident-service-crash")
  assert_eq(incident.collected_at.value, "2026-01-15T10:05:00Z")
  assert_eq(incident.evidence.length(), 1)
  assert_eq(incident.evidence[0].id, "service-manager-events")
  assert_eq(incident.evidence[0].source.host, Some("checkout-api-01"))
  assert_eq(incident.evidence[0].captured_at, Some(captured_at))
  assert_eq(incident.evidence[0].metadata.entries[0].value, "incident-review")
}

///|
test "case supports missing capture time and multiple sources" {
  let incident = @moonforensics.Case::{
    case_id: "incident-performance-degradation",
    title: "Catalog API latency increase",
    timezone: "UTC",
    collected_at: @moonforensics.Timestamp::{ value: "2026-02-03T14:30:00Z", },
    evidence: [
      @moonforensics.EvidenceItem::{
        id: "catalog-metrics",
        source: @moonforensics.EvidenceSource::{
          system: "metrics-agent",
          component: "resource-sampler",
          host: None,
        },
        path: "metrics.jsonl",
        format: @moonforensics.EvidenceFormat::JsonLines,
        captured_at: None,
        metadata: @moonforensics.EvidenceMetadata::{ entries: [], },
      },
      @moonforensics.EvidenceItem::{
        id: "gateway-log",
        source: @moonforensics.EvidenceSource::{
          system: "edge-gateway",
          component: "request-proxy",
          host: Some("edge-01"),
        },
        path: "gateway.log",
        format: @moonforensics.EvidenceFormat::PlainText,
        captured_at: None,
        metadata: @moonforensics.EvidenceMetadata::{ entries: [], },
      },
    ],
    metadata: @moonforensics.EvidenceMetadata::{ entries: [], },
  }

  assert_eq(incident.evidence.length(), 2)
  assert_eq(incident.evidence[0].captured_at, None)
  assert_eq(
    incident.evidence[1].format,
    @moonforensics.EvidenceFormat::PlainText,
  )
  assert_eq(incident.evidence[1].source.system, "edge-gateway")
}
