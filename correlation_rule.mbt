///|
/// Declarative predicates for the two sides of a temporal relation.
pub(all) struct EventPattern {
  category : EventCategory?
  event_type : String?
  action : String?
  outcome : EventOutcome?
  severity : Severity?
  source_system : String?
  source_component : String?
  resource_kind : ResourceKind?
} derive(Debug, Eq, ToJson)

///|
/// A rule that relates a matching earlier event to a matching later event.
pub(all) struct CorrelationRule {
  rule_id : String
  from : EventPattern
  to : EventPattern
  within_seconds : Int
  same_resource : Bool
  relation_type : RelationType
  explanation : String
} derive(Debug, Eq, ToJson)

///|
/// The outcome of evaluating one rule against one event pair.
pub(all) enum MatchTraceStatus {
  Matched
  Rejected
} derive(Debug, Eq, ToJson)

///|
/// One explainable check performed while evaluating a rule match.
pub(all) struct MatchTraceStep {
  check : String
  passed : Bool
  detail : String
} derive(Debug, Eq, ToJson)

///|
/// A structured explanation for a rule and event pair.
pub(all) struct RuleMatchTrace {
  rule_id : String
  from_event_id : String
  to_event_id : String
  status : MatchTraceStatus
  steps : Array[MatchTraceStep]
  evidence_refs : Array[EventProvenance]
} derive(Debug, Eq, ToJson)

///|
/// A declarative rule cannot be evaluated safely.
pub(all) suberror CorrelationRuleError {
  InvalidRule(rule_id~ : String, reason~ : String)
} derive(Debug, Eq)

///|
fn validate_pattern(
  rule_id : String,
  pattern_name : String,
  pattern : EventPattern,
) -> Unit raise CorrelationRuleError {
  validate_pattern_string(
    rule_id,
    pattern_name,
    "event_type",
    pattern.event_type,
  )
  validate_pattern_string(rule_id, pattern_name, "action", pattern.action)
  validate_pattern_string(
    rule_id,
    pattern_name,
    "source_system",
    pattern.source_system,
  )
  validate_pattern_string(
    rule_id,
    pattern_name,
    "source_component",
    pattern.source_component,
  )
}

///|
fn validate_pattern_string(
  rule_id : String,
  pattern_name : String,
  field_name : String,
  value : String?,
) -> Unit raise CorrelationRuleError {
  match value {
    Some(value) =>
      if value.trim() == "" {
        raise CorrelationRuleError::InvalidRule(
          rule_id~,
          reason="\{pattern_name}.\{field_name} must not be empty",
        )
      }
    None => ()
  }
}

///|
/// Validates rule identifiers, patterns, and non-negative temporal windows.
pub fn validate_correlation_rules(
  rules : Array[CorrelationRule],
) -> Unit raise CorrelationRuleError {
  for index, rule in rules {
    if rule.rule_id.trim() == "" {
      raise CorrelationRuleError::InvalidRule(
        rule_id=rule.rule_id,
        reason="rule id must not be empty",
      )
    }
    if rule.explanation.trim() == "" {
      raise CorrelationRuleError::InvalidRule(
        rule_id=rule.rule_id,
        reason="explanation must not be empty",
      )
    }
    if rule.within_seconds < 0 {
      raise CorrelationRuleError::InvalidRule(
        rule_id=rule.rule_id,
        reason="within_seconds must not be negative",
      )
    }
    validate_pattern(rule.rule_id, "from", rule.from)
    validate_pattern(rule.rule_id, "to", rule.to)
    for previous in 0..<index {
      if rules[previous].rule_id == rule.rule_id {
        raise CorrelationRuleError::InvalidRule(
          rule_id=rule.rule_id,
          reason="rule id must be unique",
        )
      }
    }
  }
}

///|
fn category_label(category : EventCategory) -> String {
  match category {
    EventCategory::Change => "Change"
    EventCategory::Availability => "Availability"
    EventCategory::Performance => "Performance"
    EventCategory::Process => "Process"
    EventCategory::Other(value) => "Other(\{value})"
  }
}

///|
fn outcome_label(outcome : EventOutcome) -> String {
  match outcome {
    EventOutcome::Success => "Success"
    EventOutcome::Failure => "Failure"
    EventOutcome::Unknown => "Unknown"
    EventOutcome::Other(value) => "Other(\{value})"
  }
}

///|
fn severity_label(severity : Severity) -> String {
  match severity {
    Severity::Trace => "Trace"
    Severity::Debug => "Debug"
    Severity::Info => "Info"
    Severity::Warning => "Warning"
    Severity::Error => "Error"
    Severity::Fatal => "Fatal"
    Severity::Unknown(value) => "Unknown(\{value})"
  }
}

///|
fn resource_kind_label(kind : ResourceKind) -> String {
  match kind {
    ResourceKind::Service => "Service"
    ResourceKind::Instance => "Instance"
    ResourceKind::Host => "Host"
    ResourceKind::Container => "Container"
    ResourceKind::Config => "Config"
    ResourceKind::Trace => "Trace"
    ResourceKind::Custom(value) => "Custom(\{value})"
  }
}

///|
fn trace_labeled_field(
  check : String,
  expected : String,
  actual : String?,
) -> MatchTraceStep {
  match actual {
    Some(actual) => {
      let passed = actual == expected
      {
        check,
        passed,
        detail: if passed {
          "expected and actual value are '\{expected}'"
        } else {
          "expected '\{expected}', actual '\{actual}'"
        },
      }
    }
    None =>
      {
        check,
        passed: false,
        detail: "expected '\{expected}', actual value is missing",
      }
  }
}

///|
fn trace_pattern(
  pattern : EventPattern,
  event : CanonicalEvent,
  prefix : String,
) -> (Bool, Array[MatchTraceStep]) {
  let steps : Array[MatchTraceStep] = []
  let mut matched = true
  fn add_step(
    steps : Array[MatchTraceStep],
    matched : Bool,
    step : MatchTraceStep,
  ) -> Bool {
    steps.push(step)
    matched && step.passed
  }
  match pattern.category {
    Some(expected) =>
      matched = add_step(
        steps,
        matched,
        trace_labeled_field(
          "\{prefix}category",
          category_label(expected),
          Some(category_label(event.category)),
        ),
      )
    None => ()
  }
  match pattern.event_type {
    Some(expected) =>
      matched = add_step(
        steps,
        matched,
        trace_labeled_field(
          "\{prefix}event_type",
          expected.trim().to_owned(),
          Some(event.event_type),
        ),
      )
    None => ()
  }
  match pattern.action {
    Some(expected) =>
      matched = add_step(
        steps,
        matched,
        trace_labeled_field(
          "\{prefix}action",
          expected.trim().to_owned(),
          event.action,
        ),
      )
    None => ()
  }
  match pattern.outcome {
    Some(expected) =>
      matched = add_step(
        steps,
        matched,
        trace_labeled_field(
          "\{prefix}outcome",
          outcome_label(expected),
          Some(outcome_label(event.outcome)),
        ),
      )
    None => ()
  }
  match pattern.severity {
    Some(expected) =>
      matched = add_step(
        steps,
        matched,
        trace_labeled_field(
          "\{prefix}severity",
          severity_label(expected),
          match event.severity {
            Some(actual) => Some(severity_label(actual))
            None => None
          },
        ),
      )
    None => ()
  }
  match pattern.source_system {
    Some(expected) =>
      matched = add_step(
        steps,
        matched,
        trace_labeled_field(
          "\{prefix}source_system",
          expected.trim().to_owned(),
          Some(event.source.system),
        ),
      )
    None => ()
  }
  match pattern.source_component {
    Some(expected) =>
      matched = add_step(
        steps,
        matched,
        trace_labeled_field(
          "\{prefix}source_component",
          expected.trim().to_owned(),
          Some(event.source.component),
        ),
      )
    None => ()
  }
  match pattern.resource_kind {
    Some(expected) =>
      matched = add_step(
        steps,
        matched,
        trace_labeled_field(
          "\{prefix}resource_kind",
          resource_kind_label(expected),
          match event.resource {
            Some(resource) => Some(resource_kind_label(resource.kind))
            None => None
          },
        ),
      )
    None => ()
  }
  (matched, steps)
}

///|
fn same_resource(left : CanonicalEvent, right : CanonicalEvent) -> Bool {
  match (left.resource, right.resource) {
    (Some(left_resource), Some(right_resource)) =>
      left_resource.kind == right_resource.kind &&
      left_resource.id == right_resource.id
    _ => false
  }
}

///|
fn non_negative_delta_seconds(
  earlier : NormalizedTimestamp,
  later : NormalizedTimestamp,
) -> Int {
  (later.epoch_day - earlier.epoch_day) * 86400 +
  later.second_of_day -
  earlier.second_of_day
}

///|
/// Explains every predicate and temporal constraint for one event pair.
///
/// The trace is useful both for successful relations and for rejected
/// candidates. It never infers a cause; it only records which declared checks
/// passed and which one prevented a match.
pub fn trace_correlation_match(
  rule : CorrelationRule,
  from_event : CanonicalEvent,
  to_event : CanonicalEvent,
) -> RuleMatchTrace {
  let (from_matches, from_steps) = trace_pattern(rule.from, from_event, "from.")
  let (to_matches, to_steps) = trace_pattern(rule.to, to_event, "to.")
  let steps : Array[MatchTraceStep] = []
  for step in from_steps {
    steps.push(step)
  }
  for step in to_steps {
    steps.push(step)
  }
  let mut matched = from_matches && to_matches
  match (from_event.event_time, to_event.event_time) {
    (Some(from_time), Some(to_time)) => {
      let order = compare_timestamps(from_time, to_time)
      let ordered = order <= 0
      steps.push({
        check: "time.order",
        passed: ordered,
        detail: if order < 0 {
          "from event precedes to event"
        } else if order == 0 {
          "events share a timestamp; stable node order decides"
        } else {
          "from event occurs after to event"
        },
      })
      let delta_seconds = if ordered {
        non_negative_delta_seconds(from_time, to_time)
      } else {
        0
      }
      let within_window = ordered && delta_seconds <= rule.within_seconds
      steps.push({
        check: "time.window",
        passed: within_window,
        detail: "delta \{delta_seconds}s, allowed \{rule.within_seconds}s",
      })
      matched = matched && ordered && within_window
    }
    _ => {
      steps.push({
        check: "time.order",
        passed: false,
        detail: "both events require an event timestamp",
      })
      matched = false
    }
  }
  if rule.same_resource {
    let resource_matches = same_resource(from_event, to_event)
    let detail = match (from_event.resource, to_event.resource) {
      (Some(from_resource), Some(to_resource)) =>
        if resource_matches {
          "typed resource identities are equal"
        } else {
          "typed resource identities differ: \{from_resource.id} vs \{to_resource.id}"
        }
      _ => "both events require a typed resource identity"
    }
    steps.push({ check: "resource.identity", passed: resource_matches, detail, })
    matched = matched && resource_matches
  } else {
    steps.push({
      check: "resource.identity",
      passed: true,
      detail: "same-resource constraint is disabled",
    })
  }
  {
    rule_id: rule.rule_id,
    from_event_id: from_event.event_id,
    to_event_id: to_event.event_id,
    status: if matched {
      MatchTraceStatus::Matched
    } else {
      MatchTraceStatus::Rejected
    },
    steps,
    evidence_refs: [from_event.provenance, to_event.provenance],
  }
}

///|
fn add_rule_relations(
  nodes : Array[CanonicalEvent],
  rule : CorrelationRule,
  edges : Array[EvidenceRelation],
) -> Unit {
  for from_index, from_event in nodes {
    for to_index, to_event in nodes {
      if from_index != to_index {
        let trace = trace_correlation_match(rule, from_event, to_event)
        match trace.status {
          MatchTraceStatus::Matched =>
            match (from_event.event_time, to_event.event_time) {
              (Some(from_time), Some(to_time)) => {
                let order = compare_timestamps(from_time, to_time)
                if (order < 0 || (order == 0 && from_index < to_index)) &&
                  non_negative_delta_seconds(from_time, to_time) <=
                  rule.within_seconds &&
                  (!rule.same_resource || same_resource(from_event, to_event)) {
                  let resource_key = if rule.same_resource {
                    from_event.resource
                  } else {
                    None
                  }
                  let delta_seconds = non_negative_delta_seconds(
                    from_time, to_time,
                  )
                  edges.push({
                    relation_id: "\{rule.rule_id}:\{from_index}:\{to_index}",
                    relation_type: rule.relation_type,
                    from_event_id: from_event.event_id,
                    to_event_id: to_event.event_id,
                    rule_id: Some(rule.rule_id),
                    resource_key,
                    delta_seconds: Some(delta_seconds),
                    evidence_refs: [from_event.provenance, to_event.provenance],
                    explanation: rule.explanation,
                    status: RelationStatus::Hypothesis,
                    match_trace: trace,
                  })
                }
              }
              _ => ()
            }
          MatchTraceStatus::Rejected => ()
        }
      }
    }
  }
}

///|
/// Evaluates rules in declaration order and returns an explainable incident graph.
///
/// A relation requires an earlier matching event, a later matching event, and
/// an inclusive temporal window. Same-resource rules require equal typed resource
/// identities and never infer a relation when either side lacks a resource.
pub fn evaluate_correlation_rules(
  events : Array[CanonicalEvent],
  rules : Array[CorrelationRule],
) -> IncidentGraph raise CorrelationRuleError {
  validate_correlation_rules(rules)
  let nodes = sort_graph_events(events)
  let edges : Array[EvidenceRelation] = []
  for rule in rules {
    add_rule_relations(nodes, rule, edges)
  }
  { nodes, edges, diagnostics: [], }
}
