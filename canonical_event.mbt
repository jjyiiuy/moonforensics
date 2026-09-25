///|
/// The stable identity class of a resource observed by an incident event.
pub(all) enum ResourceKind {
  Service
  Instance
  Host
  Container
  Config
  Trace
  Custom(String)
} derive(Debug, Eq, ToJson)

///|
/// A typed resource identity. The kind and identifier stay separate so that
/// an instance is not accidentally treated as a service with a similar name.
pub(all) struct ResourceRef {
  kind : ResourceKind
  id : String
  attributes : Json
} derive(Debug, Eq, ToJson)

///|
/// Structured producer identity for a canonical event.
pub(all) struct TelemetrySource {
  system : String
  component : String
  host : String?
  instrumentation_scope : String?
} derive(Debug, Eq, ToJson)

///|
/// A stable event category independent from severity.
pub(all) enum EventCategory {
  Change
  Availability
  Performance
  Process
  Other(String)
} derive(Debug, Eq, ToJson)

///|
/// The observed outcome of an event, when the source provides one.
pub(all) enum EventOutcome {
  Success
  Failure
  Unknown
  Other(String)
} derive(Debug, Eq, ToJson)

///|
/// Location and transformation information retained for every canonical event.
pub(all) struct EventProvenance {
  evidence_id : String
  path : String
  line_number : Int?
  byte_offset : Int?
  byte_length : Int?
  sha256 : String?
  profile_id : String
  profile_version : String
} derive(Debug, Eq, ToJson)

///|
/// A source event with stable semantics, resource identity, and provenance.
///
/// `raw_content` is never replaced by normalized text. `body` and
/// `attributes` preserve structured values for later rules and reports.
pub(all) struct CanonicalEvent {
  event_id : String
  event_time : NormalizedTimestamp?
  observed_time : NormalizedTimestamp?
  source : TelemetrySource
  resource : ResourceRef?
  category : EventCategory
  event_type : String
  action : String?
  outcome : EventOutcome
  severity : Severity?
  body : Json
  raw_content : String
  attributes : Json
  provenance : EventProvenance
} derive(Debug, Eq, ToJson)

///|
/// Converts a canonical event to the legacy timeline view without losing the
/// original body stored in `raw_content`.
pub fn CanonicalEvent::to_normalized_event(
  self : CanonicalEvent,
) -> NormalizedEvent {
  {
    timestamp: self.event_time,
    severity: self.severity,
    source_id: normalize_source_id(
      self.source.system,
      self.source.component,
      self.source.host,
    ),
    raw_content: self.raw_content,
  }
}

///|
fn legacy_event_semantics(kind : CorrelationKind) -> (EventCategory, String) {
  match kind {
    CorrelationKind::Change => (EventCategory::Change, "legacy.change")
    CorrelationKind::Alert => (EventCategory::Availability, "legacy.alert")
    CorrelationKind::Crash => (EventCategory::Process, "legacy.crash")
    CorrelationKind::Other(value) =>
      (EventCategory::Other(value), "legacy.other")
  }
}

///|
/// Converts a legacy adapter result into the canonical event contract.
///
/// The bridge keeps the legacy source identifier, resource identity,
/// attributes, raw content, and evidence line. It supplies conservative
/// semantics for fields that the legacy mapping does not describe.
pub fn IncidentEvent::to_canonical_event(
  self : IncidentEvent,
) -> CanonicalEvent {
  let (category, event_type) = legacy_event_semantics(self.kind)
  let source : TelemetrySource = {
    system: self.normalized.source_id,
    component: "",
    host: None,
    instrumentation_scope: Some("legacy-adapter"),
  }
  let resource = match self.resource_id {
    Some(resource_id) =>
      Some({
        kind: ResourceKind::Custom("legacy"),
        id: resource_id,
        attributes: {},
      })
    None => None
  }
  canonicalize_incident_event(
    self,
    source,
    resource,
    category,
    event_type,
    None,
    EventOutcome::Unknown,
    None,
    {
      evidence_id: self.evidence.evidence_id,
      path: self.evidence.evidence_id,
      line_number: Some(self.evidence.line_number),
      byte_offset: None,
      byte_length: None,
      sha256: None,
      profile_id: "legacy-adapter",
      profile_version: "1",
    },
  )
}

///|
/// Bridges the existing adapter result into the canonical model. Classification,
/// resource identity, source structure, and provenance are explicit inputs so
/// this bridge never guesses business semantics from a message.
pub fn canonicalize_incident_event(
  event : IncidentEvent,
  source : TelemetrySource,
  resource : ResourceRef?,
  category : EventCategory,
  event_type : String,
  action : String?,
  outcome : EventOutcome,
  observed_time : NormalizedTimestamp?,
  provenance : EventProvenance,
) -> CanonicalEvent {
  {
    event_id: event.event_id,
    event_time: event.normalized.timestamp,
    observed_time,
    source,
    resource,
    category,
    event_type,
    action,
    outcome,
    severity: event.normalized.severity,
    body: ToJson::to_json(event.normalized.raw_content),
    raw_content: event.normalized.raw_content,
    attributes: event.attributes,
    provenance,
  }
}

///|
/// The semantic type of a graph edge produced by a rule or processor.
pub(all) enum RelationType {
  SameResource
  TemporalBefore
  MatchedRule
  AliasOf
  AttributeMatch
  Custom(String)
} derive(Debug, Eq, ToJson)

///|
/// Whether a relation is a directly observed fact or a rule-based hypothesis.
pub(all) enum RelationStatus {
  Observed
  Hypothesis
} derive(Debug, Eq, ToJson)

///|
/// An explainable edge between two canonical events.
pub(all) struct EvidenceRelation {
  relation_id : String
  relation_type : RelationType
  from_event_id : String
  to_event_id : String
  rule_id : String?
  resource_key : ResourceRef?
  delta_seconds : Int?
  evidence_refs : Array[EventProvenance]
  explanation : String
  status : RelationStatus
} derive(Debug, Eq, ToJson)

///|
/// A diagnostic emitted when an event or rule cannot be fully evaluated.
pub(all) struct GraphDiagnostic {
  code : String
  message : String
  event_id : String?
  provenance : EventProvenance?
} derive(Debug, Eq, ToJson)

///|
/// The deterministic graph consumed by timeline, finding, and report views.
pub(all) struct IncidentGraph {
  nodes : Array[CanonicalEvent]
  edges : Array[EvidenceRelation]
  diagnostics : Array[GraphDiagnostic]
} derive(Debug, Eq, ToJson)

///|
/// Creates an empty graph for incremental processors.
pub fn empty_incident_graph() -> IncidentGraph {
  { nodes: [], edges: [], diagnostics: [], }
}
