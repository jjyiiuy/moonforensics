///|
fn case_source(
  system : String,
  component : String,
) -> @moonforensics.EvidenceSource {
  @moonforensics.EvidenceSource::{ system, component, host: None, }
}

///|
fn case_item(
  id : String,
  path : String,
  source : @moonforensics.EvidenceSource,
) -> @moonforensics.EvidenceItem {
  @moonforensics.EvidenceItem::{
    id,
    source,
    path,
    format: @moonforensics.EvidenceFormat::JsonLines,
    captured_at: None,
    metadata: @moonforensics.EvidenceMetadata::{ entries: [], },
  }
}

///|
fn case_profile(
  id : String,
  component : String,
  category : @moonforensics.EventCategory,
  event_type : String,
) -> @moonforensics.JsonlMappingProfile {
  @moonforensics.JsonlMappingProfile::{
    id,
    version: "1.0.0",
    source: @moonforensics.SourceMappingProfile::{
      system: @moonforensics.ProfileStringValue::Constant("fixture"),
      component: @moonforensics.ProfileStringValue::Constant(component),
      host: None,
      instrumentation_scope: None,
    },
    event_id: @moonforensics.ProfileStringValue::JsonString({
      segments: ["id"],
    }),
    event_time: Some({ segments: ["timestamp"], }),
    observed_time: None,
    severity: Some({ segments: ["severity"], }),
    resource: Some(@moonforensics.ResourceMappingProfile::{
      kind: @moonforensics.ResourceKind::Service,
      id: @moonforensics.ProfileStringValue::JsonString({
        segments: ["resource"],
      }),
      prefix: "service:",
      aliases: [],
      attributes_path: None,
    }),
    category,
    event_type: @moonforensics.ProfileStringValue::Constant(event_type),
    action: None,
    outcome: @moonforensics.EventOutcome::Failure,
    body_path: Some({ segments: ["message"], }),
  }
}

///|
fn case_metadata(
  evidence : Array[@moonforensics.EvidenceItem],
) -> @moonforensics.Case {
  @moonforensics.Case::{
    case_id: "case-multi-source",
    title: "Multi-source fixture case",
    timezone: "UTC",
    collected_at: @moonforensics.Timestamp::{ value: "2026-09-20T00:01:00Z", },
    evidence,
    metadata: @moonforensics.EvidenceMetadata::{ entries: [], },
  }
}

///|
test "case analysis assembles JSONL sources into one report" {
  let config_source = case_source("fixture", "config-controller")
  let health_source = case_source("fixture", "health-monitor")
  let config_content = b"{\"id\":\"config-1\",\"timestamp\":\"2026-09-20T00:00:00Z\",\"severity\":\"INFO\",\"resource\":\"orders\",\"message\":\"updated\"}\n"
  let health_content = b"{\"id\":\"health-1\",\"timestamp\":\"2026-09-20T00:00:30Z\",\"severity\":\"ERROR\",\"resource\":\"orders\",\"message\":\"failed\"}\n"
  let config_document = @moonforensics.EvidenceDocument::{
    id: "config.jsonl",
    path: "fixtures/config.jsonl",
    source: config_source,
    content: config_content,
  }
  let health_document = @moonforensics.EvidenceDocument::{
    id: "health.jsonl",
    path: "fixtures/health.jsonl",
    source: health_source,
    content: health_content,
  }
  let config_input = try! @moonforensics.build_case_jsonl_evidence(
    config_document,
    try! @moonforensics.parse_jsonl(
      "{\"id\":\"config-1\",\"timestamp\":\"2026-09-20T00:00:00Z\",\"severity\":\"INFO\",\"resource\":\"orders\",\"message\":\"updated\"}\n",
    ),
    case_profile(
      "config",
      "config-controller",
      @moonforensics.EventCategory::Change,
      "config.update",
    ),
  )
  let health_input = try! @moonforensics.build_case_jsonl_evidence(
    health_document,
    try! @moonforensics.parse_jsonl(
      "{\"id\":\"health-1\",\"timestamp\":\"2026-09-20T00:00:30Z\",\"severity\":\"ERROR\",\"resource\":\"orders\",\"message\":\"failed\"}\n",
    ),
    case_profile(
      "health",
      "health-monitor",
      @moonforensics.EventCategory::Availability,
      "health.failed",
    ),
  )
  let result = try! @moonforensics.analyze_case(
    case_metadata([
      case_item("config.jsonl", "fixtures/config.jsonl", config_source),
      case_item("health.jsonl", "fixtures/health.jsonl", health_source),
    ]),
    [config_input, health_input],
    None,
    Some(@moonforensics.config_analysis_pack()),
    "A configuration change preceded a health failure.",
    ["Fixture data is intentionally minimal."],
  )
  assert_eq(result.events.map(event => event.event_id), ["config-1", "health-1"])
  assert_eq(result.graph.nodes.map(event => event.event_id), [
    "config-1", "health-1",
  ])
  assert_eq(result.graph.edges.length(), 1)
  assert_eq(result.report.timeline.events.length(), 2)
  assert_eq(result.report.evidence_index.entries.length(), 2)
  assert_true(result.report.evidence_index.entries[0].sha256 != "")
  assert_eq(result.report.limitations, [
    "Fixture data is intentionally minimal.",
  ])
}

///|
test "case analysis applies a processor before graph and report stages" {
  let source = case_source("fixture", "mixed-source")
  let content = b"{\"id\":\"change-1\",\"timestamp\":\"2026-09-20T00:00:00Z\",\"severity\":\"INFO\",\"resource\":\"orders\",\"message\":\"changed\"}\n"
  let document = @moonforensics.EvidenceDocument::{
    id: "mixed.jsonl",
    path: "fixtures/mixed.jsonl",
    source,
    content,
  }
  let input = try! @moonforensics.build_case_jsonl_evidence(
    document,
    try! @moonforensics.parse_jsonl(
      "{\"id\":\"change-1\",\"timestamp\":\"2026-09-20T00:00:00Z\",\"severity\":\"INFO\",\"resource\":\"orders\",\"message\":\"changed\"}\n",
    ),
    case_profile(
      "mixed",
      "mixed-source",
      @moonforensics.EventCategory::Change,
      "config.update",
    ),
  )
  let result = try! @moonforensics.analyze_case(
    case_metadata([case_item("mixed.jsonl", "fixtures/mixed.jsonl", source)]),
    [input],
    Some(@moonforensics.ProcessorPipeline::{
      name: "only-change",
      stages: [
        @moonforensics.ProcessorStage::FilterCategory(
          @moonforensics.EventCategory::Change,
        ),
      ],
    }),
    None,
    "Only change events are retained.",
    [],
  )
  assert_eq(result.events.length(), 1)
  assert_eq(result.report.timeline.events.length(), 1)
  assert_eq(
    result.report.timeline.events[0].raw_content.contains("changed"),
    true,
  )
}

///|
test "case analysis rejects provenance that does not match its document" {
  let source = case_source("fixture", "tampered")
  let document = @moonforensics.EvidenceDocument::{
    id: "tampered.jsonl",
    path: "fixtures/tampered.jsonl",
    source,
    content: b"{\"id\":\"evt-1\",\"timestamp\":\"2026-09-20T00:00:00Z\",\"resource\":\"orders\",\"message\":\"entry\"}\n",
  }
  let input = try! @moonforensics.build_case_jsonl_evidence(
    document,
    try! @moonforensics.parse_jsonl(
      "{\"id\":\"evt-1\",\"timestamp\":\"2026-09-20T00:00:00Z\",\"resource\":\"orders\",\"message\":\"entry\"}\n",
    ),
    case_profile(
      "tampered",
      "tampered",
      @moonforensics.EventCategory::Other("fixture"),
      "fixture.event",
    ),
  )
  let event = {
    ..input.events[0],
    provenance: { ..input.events[0].provenance, path: "fixtures/other.jsonl", },
  }
  try
    @moonforensics.analyze_case(
      case_metadata([
        case_item("tampered.jsonl", "fixtures/tampered.jsonl", source),
      ]),
      [{ document: input.document, events: [event], }],
      None,
      None,
      "should fail",
      [],
    )
  catch {
    @moonforensics.CaseAnalysisError::EvidenceMismatch(id~, reason~) => {
      assert_eq(id, "tampered.jsonl")
      assert_true(reason.contains("provenance"))
    }
    _ => fail("expected provenance mismatch")
  } noraise {
    _ => fail("expected provenance mismatch")
  }
}
