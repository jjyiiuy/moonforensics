///|
fn compare_graph_events(left : CanonicalEvent, right : CanonicalEvent) -> Int {
  match (left.event_time, right.event_time) {
    (Some(left_time), Some(right_time)) =>
      compare_timestamps(left_time, right_time)
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => 0
  }
}

///|
fn merge_graph_events(
  left : Array[CanonicalEvent],
  right : Array[CanonicalEvent],
) -> Array[CanonicalEvent] {
  let merged : Array[CanonicalEvent] = []
  for left_index = 0, right_index = 0; left_index < left.length() &&
     right_index < right.length(); {
    if compare_graph_events(left[left_index], right[right_index]) <= 0 {
      merged.push(left[left_index])
      continue left_index + 1, right_index
    } else {
      merged.push(right[right_index])
      continue left_index, right_index + 1
    }
  } nobreak {
    for index in left_index..<left.length() {
      merged.push(left[index])
    }
    for index in right_index..<right.length() {
      merged.push(right[index])
    }
  }
  merged
}

///|
fn sort_graph_events(events : Array[CanonicalEvent]) -> Array[CanonicalEvent] {
  if events.length() <= 1 {
    events
  } else {
    let midpoint = events.length() / 2
    let left : Array[CanonicalEvent] = []
    let right : Array[CanonicalEvent] = []
    for index, event in events {
      if index < midpoint {
        left.push(event)
      } else {
        right.push(event)
      }
    }
    merge_graph_events(sort_graph_events(left), sort_graph_events(right))
  }
}

///|
fn has_same_resource_rule(rules : Array[CorrelationRule]) -> Bool {
  let mut required = false
  for rule in rules {
    if rule.same_resource {
      required = true
    }
  }
  required
}

///|
fn has_prior_event_id(
  nodes : Array[CanonicalEvent],
  index : Int,
  event_id : String,
) -> Bool {
  let mut duplicate = false
  for previous in 0..<index {
    if nodes[previous].event_id == event_id {
      duplicate = true
    }
  }
  duplicate
}

///|
fn graph_diagnostics(
  nodes : Array[CanonicalEvent],
  rules : Array[CorrelationRule],
) -> Array[GraphDiagnostic] {
  let diagnostics : Array[GraphDiagnostic] = []
  let resource_required = has_same_resource_rule(rules)
  for index, event in nodes {
    if event.event_id.trim() == "" {
      diagnostics.push({
        code: "empty_event_id",
        message: "Event has no stable event ID.",
        event_id: Some(event.event_id),
        provenance: Some(event.provenance),
      })
    } else if has_prior_event_id(nodes, index, event.event_id) {
      diagnostics.push({
        code: "duplicate_event_id",
        message: "Event ID is shared by multiple canonical events.",
        event_id: Some(event.event_id),
        provenance: Some(event.provenance),
      })
    }
    if event.event_time is None {
      diagnostics.push({
        code: "missing_event_time",
        message: "Event has no event time and cannot satisfy temporal rules.",
        event_id: Some(event.event_id),
        provenance: Some(event.provenance),
      })
    }
    if resource_required && event.resource is None {
      diagnostics.push({
        code: "missing_resource",
        message: "Same-resource rules cannot evaluate an event without a resource.",
        event_id: Some(event.event_id),
        provenance: Some(event.provenance),
      })
    }
  }
  diagnostics
}

///|
/// Builds a deterministic, explainable graph from canonical events and rules.
///
/// Nodes are sorted by event time with stable input order for equal timestamps;
/// events without timestamps are placed last. Rule edges retain their evidence
/// references, explanation, rule ID, relation status, and resource key.
/// Diagnostics identify data-quality limits without discarding the source event.
pub fn build_incident_graph(
  events : Array[CanonicalEvent],
  rules : Array[CorrelationRule],
) -> IncidentGraph raise CorrelationRuleError {
  let evaluated = evaluate_correlation_rules(events, rules)
  let nodes = sort_graph_events(evaluated.nodes)
  {
    nodes,
    edges: evaluated.edges,
    diagnostics: graph_diagnostics(nodes, rules),
  }
}
