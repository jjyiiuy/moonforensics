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
fn pattern_matches(pattern : EventPattern, event : CanonicalEvent) -> Bool {
  let category_matches = match pattern.category {
    Some(expected) => event.category == expected
    None => true
  }
  let event_type_matches = match pattern.event_type {
    Some(expected) => event.event_type == expected.trim().to_owned()
    None => true
  }
  let action_matches = match pattern.action {
    Some(expected) => event.action == Some(expected.trim().to_owned())
    None => true
  }
  let outcome_matches = match pattern.outcome {
    Some(expected) => event.outcome == expected
    None => true
  }
  let severity_matches = match pattern.severity {
    Some(expected) => event.severity == Some(expected)
    None => true
  }
  let source_system_matches = match pattern.source_system {
    Some(expected) => event.source.system == expected.trim().to_owned()
    None => true
  }
  let source_component_matches = match pattern.source_component {
    Some(expected) => event.source.component == expected.trim().to_owned()
    None => true
  }
  let resource_kind_matches = match pattern.resource_kind {
    Some(expected) =>
      match event.resource {
        Some(resource) => resource.kind == expected
        None => false
      }
    None => true
  }
  category_matches &&
  event_type_matches &&
  action_matches &&
  outcome_matches &&
  severity_matches &&
  source_system_matches &&
  source_component_matches &&
  resource_kind_matches
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
fn add_rule_relations(
  nodes : Array[CanonicalEvent],
  rule : CorrelationRule,
  edges : Array[EvidenceRelation],
) -> Unit {
  for from_index, from_event in nodes {
    if pattern_matches(rule.from, from_event) {
      for to_index, to_event in nodes {
        if from_index != to_index && pattern_matches(rule.to, to_event) {
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
                })
              }
            }
            _ => ()
          }
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
  let edges : Array[EvidenceRelation] = []
  for rule in rules {
    add_rule_relations(events, rule, edges)
  }
  { nodes: events, edges, diagnostics: [], }
}
