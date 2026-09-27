///|
/// Canonical events and their evidence document as one case input.
pub(all) struct CaseEvidenceInput {
  document : EvidenceDocument
  events : Array[CanonicalEvent]
} derive(Debug, Eq)

///|
/// The result of assembling and analyzing one multi-source case.
pub(all) struct CaseAnalysis {
  events : Array[CanonicalEvent]
  graph : IncidentGraph
  report : ForensicReport
} derive(Debug, Eq, ToJson)

///|
/// Case assembly stops before producing a partial report.
pub(all) suberror CaseAnalysisError {
  InvalidCase(reason~ : String)
  MissingEvidence(id~ : String)
  UnexpectedEvidence(id~ : String)
  EvidenceMismatch(id~ : String, reason~ : String)
  InvalidProcessor(reason~ : String)
  InvalidPack(rule_id~ : String, reason~ : String)
} derive(Debug, Eq)

///|
/// Maps one JSONL evidence document with a profile and binds its digest to
/// every resulting event provenance.
pub fn build_case_jsonl_evidence(
  document : EvidenceDocument,
  records : Array[JsonlRecord],
  profile : JsonlMappingProfile,
) -> CaseEvidenceInput raise ProfileMapError {
  let manifest = build_evidence_manifest([document])
  let entry = manifest.entries[0]
  let events = apply_jsonl_profile(records, profile, {
    evidence_id: document.id,
    path: document.path,
    sha256: Some(entry.sha256),
  })
  { document, events, }
}

///|
fn has_input_evidence(inputs : Array[CaseEvidenceInput], id : String) -> Bool {
  for input in inputs {
    if input.document.id == id {
      return true
    }
  }
  false
}

///|
fn has_duplicate_input_evidence(
  inputs : Array[CaseEvidenceInput],
  id : String,
) -> Bool {
  let mut seen = false
  for input in inputs {
    if input.document.id == id {
      if seen {
        return true
      }
      seen = true
    }
  }
  false
}

///|
fn case_evidence_item(case : Case, id : String) -> EvidenceItem? {
  for item in case.evidence {
    if item.id == id {
      return Some(item)
    }
  }
  None
}

///|
fn validate_case_inputs(
  case : Case,
  inputs : Array[CaseEvidenceInput],
) -> Unit raise CaseAnalysisError {
  if case.case_id.trim() == "" {
    raise CaseAnalysisError::InvalidCase(reason="case id must not be empty")
  }
  if case.title.trim() == "" {
    raise CaseAnalysisError::InvalidCase(reason="case title must not be empty")
  }
  if case.timezone.trim() == "" {
    raise CaseAnalysisError::InvalidCase(
      reason="case timezone must not be empty",
    )
  }
  if case.evidence.length() != inputs.length() {
    raise CaseAnalysisError::InvalidCase(
      reason="case evidence and supplied documents must have the same length",
    )
  }
  for input in inputs {
    let id = input.document.id
    if id.trim() == "" {
      raise CaseAnalysisError::UnexpectedEvidence(id~)
    }
    if has_duplicate_input_evidence(inputs, id) {
      raise CaseAnalysisError::UnexpectedEvidence(id~)
    }
    match case_evidence_item(case, id) {
      None => raise CaseAnalysisError::UnexpectedEvidence(id~)
      Some(item) => {
        if item.path != input.document.path {
          raise CaseAnalysisError::EvidenceMismatch(
            id~,
            reason="document path does not match case metadata",
          )
        }
        if item.source != input.document.source {
          raise CaseAnalysisError::EvidenceMismatch(
            id~,
            reason="document source does not match case metadata",
          )
        }
        for event in input.events {
          if event.provenance.evidence_id != id ||
            event.provenance.path != input.document.path {
            raise CaseAnalysisError::EvidenceMismatch(
              id~,
              reason="event provenance does not match its evidence document",
            )
          }
        }
      }
    }
  }
  for item in case.evidence {
    if !has_input_evidence(inputs, item.id) {
      raise CaseAnalysisError::MissingEvidence(id=item.id)
    }
  }
}

///|
fn process_case_events(
  events : Array[CanonicalEvent],
  pipeline : ProcessorPipeline?,
) -> Array[CanonicalEvent] raise CaseAnalysisError {
  match pipeline {
    None => events
    Some(pipeline) =>
      try process_events(events, pipeline) catch {
        ProcessorError::InvalidWindow =>
          raise CaseAnalysisError::InvalidProcessor(
            reason="processor time window is invalid",
          )
        ProcessorError::InvalidStage(reason) =>
          raise CaseAnalysisError::InvalidProcessor(reason~)
      } noraise {
        processed => processed
      }
  }
}

///|
fn analyze_case_graph(
  events : Array[CanonicalEvent],
  pack : AnalysisPack?,
) -> IncidentGraph raise CaseAnalysisError {
  match pack {
    None =>
      try build_incident_graph(events, []) catch {
        CorrelationRuleError::InvalidRule(rule_id~, reason~) =>
          raise CaseAnalysisError::InvalidPack(rule_id~, reason~)
      } noraise {
        graph => graph
      }
    Some(pack) =>
      try analyze_with_pack(events, pack) catch {
        CorrelationRuleError::InvalidRule(rule_id~, reason~) =>
          raise CaseAnalysisError::InvalidPack(rule_id~, reason~)
      } noraise {
        graph => graph
      }
  }
}

///|
fn case_events(inputs : Array[CaseEvidenceInput]) -> Array[CanonicalEvent] {
  let events : Array[CanonicalEvent] = []
  for input in inputs {
    for event in input.events {
      events.push(event)
    }
  }
  events
}

///|
/// Assembles multiple in-memory evidence streams into one deterministic case.
///
/// The case metadata and document identities are checked before mapping results
/// enter the processor, graph, and report stages. No file-system access occurs.
pub fn analyze_case(
  case : Case,
  inputs : Array[CaseEvidenceInput],
  pipeline : ProcessorPipeline?,
  pack : AnalysisPack?,
  summary : String,
  limitations : Array[String],
) -> CaseAnalysis raise CaseAnalysisError {
  validate_case_inputs(case, inputs)
  let events = process_case_events(case_events(inputs), pipeline)
  let graph = analyze_case_graph(events, pack)
  let timeline_events : Array[NormalizedEvent] = []
  for event in graph.nodes {
    timeline_events.push(event.to_normalized_event())
  }
  let timeline = build_timeline(timeline_events)
  let documents : Array[EvidenceDocument] = []
  for input in inputs {
    documents.push(input.document)
  }
  let report = ForensicReport::{
    case,
    summary,
    timeline,
    findings: DiagnosticReport::{ findings: [], },
    evidence_index: build_evidence_manifest(documents),
    limitations,
  }
  { events, graph, report, }
}
