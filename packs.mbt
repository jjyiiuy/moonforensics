///|
/// A reusable bundle of declarative rules for a focused incident pattern.
///
/// Packs describe an analysis vocabulary without changing the canonical event
/// model. Callers can inspect the rules, present the metadata in a UI, or run
/// the pack through `analyze_with_pack`.
pub(all) struct AnalysisPack {
  pack_id : String
  title : String
  description : String
  rules : Array[CorrelationRule]
} derive(Debug, Eq, ToJson)

///|
/// Validates the metadata and rules of a reusable analysis pack.
pub fn validate_analysis_pack(
  pack : AnalysisPack,
) -> Unit raise CorrelationRuleError {
  if pack.pack_id.trim() == "" {
    raise CorrelationRuleError::InvalidRule(
      rule_id=pack.pack_id,
      reason="analysis pack id must not be empty",
    )
  }
  if pack.title.trim() == "" {
    raise CorrelationRuleError::InvalidRule(
      rule_id=pack.pack_id,
      reason="analysis pack title must not be empty",
    )
  }
  if pack.description.trim() == "" {
    raise CorrelationRuleError::InvalidRule(
      rule_id=pack.pack_id,
      reason="analysis pack description must not be empty",
    )
  }
  validate_correlation_rules(pack.rules)
}

///|
/// Runs a reusable pack while preserving the graph builder's deterministic
/// ordering, evidence references, and diagnostics.
pub fn analyze_with_pack(
  events : Array[CanonicalEvent],
  pack : AnalysisPack,
) -> IncidentGraph raise CorrelationRuleError {
  validate_analysis_pack(pack)
  build_incident_graph(events, pack.rules)
}

///|
fn pack_pattern(category : EventCategory, event_type : String) -> EventPattern {
  {
    category: Some(category),
    event_type: Some(event_type),
    action: None,
    outcome: None,
    severity: None,
    source_system: None,
    source_component: None,
    resource_kind: None,
  }
}

///|
fn pack_rule(
  rule_id : String,
  from_category : EventCategory,
  from_type : String,
  to_category : EventCategory,
  to_type : String,
  within_seconds : Int,
  explanation : String,
) -> CorrelationRule {
  {
    rule_id,
    from: pack_pattern(from_category, from_type),
    to: pack_pattern(to_category, to_type),
    within_seconds,
    same_resource: true,
    relation_type: RelationType::MatchedRule,
    explanation,
  }
}

///|
/// Rules for changes followed by health or process failures.
pub fn config_analysis_pack() -> AnalysisPack {
  {
    pack_id: "config",
    title: "Configuration change analysis",
    description: "Relates a configuration update to a nearby health failure or process crash on the same resource.",
    rules: [
      pack_rule(
        "config-change-then-health-failure",
        EventCategory::Change,
        "config.update",
        EventCategory::Availability,
        "health.failed",
        300,
        "A health failure followed a configuration update within five minutes on the same resource.",
      ),
      pack_rule(
        "config-change-then-process-crash",
        EventCategory::Change,
        "config.update",
        EventCategory::Process,
        "process.exit",
        300,
        "A process exit followed a configuration update within five minutes on the same resource.",
      ),
    ],
  }
}

///|
/// Rules for process crashes followed by service failure or recovery.
pub fn crash_analysis_pack() -> AnalysisPack {
  {
    pack_id: "crash",
    title: "Process crash analysis",
    description: "Relates a process exit to a nearby service failure or recovery on the same resource.",
    rules: [
      pack_rule(
        "crash-then-health-failure",
        EventCategory::Process,
        "process.exit",
        EventCategory::Availability,
        "health.failed",
        120,
        "A health failure followed a process exit within two minutes on the same resource.",
      ),
      pack_rule(
        "crash-then-recovery",
        EventCategory::Process,
        "process.exit",
        EventCategory::Availability,
        "health.recovered",
        600,
        "A health recovery followed a process exit within ten minutes on the same resource.",
      ),
    ],
  }
}

///|
/// Rules for latency observations followed by timeout or request errors.
pub fn latency_analysis_pack() -> AnalysisPack {
  {
    pack_id: "latency",
    title: "Request latency analysis",
    description: "Relates a latency observation to a nearby timeout or request error on the same resource.",
    rules: [
      pack_rule(
        "latency-then-timeout",
        EventCategory::Performance,
        "request.latency",
        EventCategory::Availability,
        "request.timeout",
        60,
        "A request timeout followed a latency observation within one minute on the same resource.",
      ),
      pack_rule(
        "latency-then-error",
        EventCategory::Performance,
        "request.latency",
        EventCategory::Availability,
        "request.error",
        60,
        "A request error followed a latency observation within one minute on the same resource.",
      ),
    ],
  }
}

///|
/// Returns the built-in packs in stable display order.
pub fn built_in_analysis_packs() -> Array[AnalysisPack] {
  [config_analysis_pack(), crash_analysis_pack(), latency_analysis_pack()]
}
