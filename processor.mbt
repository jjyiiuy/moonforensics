///|
/// A deterministic transformation or filter applied to canonical events.
pub(all) enum ProcessorStage {
  Normalize
  AliasResource(ResourceAlias)
  FilterSource(String)
  FilterCategory(EventCategory)
  FilterResource(String)
  FilterTimeWindow(NormalizedTimestamp, NormalizedTimestamp)
} derive(Debug, Eq)

///|
/// An ordered, reusable event transformation pipeline.
pub(all) struct ProcessorPipeline {
  name : String
  stages : Array[ProcessorStage]
} derive(Debug, Eq)

///|
/// A pipeline configuration or stage cannot be applied safely.
pub(all) suberror ProcessorError {
  InvalidWindow
  InvalidStage(String)
} derive(Debug, Eq)

///|
fn normalized_optional_string(value : String?) -> String? {
  match value {
    Some(value) => {
      let normalized = value.trim().to_owned()
      if normalized == "" {
        None
      } else {
        Some(normalized)
      }
    }
    None => None
  }
}

///|
fn normalize_canonical_event(event : CanonicalEvent) -> CanonicalEvent {
  let source : TelemetrySource = {
    system: event.source.system.trim().to_owned(),
    component: event.source.component.trim().to_owned(),
    host: normalized_optional_string(event.source.host),
    instrumentation_scope: normalized_optional_string(
      event.source.instrumentation_scope,
    ),
  }
  let resource = match event.resource {
    Some(resource) =>
      Some({
        kind: resource.kind,
        id: resource.id.trim().to_owned(),
        attributes: resource.attributes,
      })
    None => None
  }
  {
    event_id: event.event_id.trim().to_owned(),
    event_time: event.event_time,
    observed_time: event.observed_time,
    source,
    resource,
    category: event.category,
    event_type: event.event_type.trim().to_owned(),
    action: normalized_optional_string(event.action),
    outcome: event.outcome,
    severity: event.severity,
    body: event.body,
    raw_content: event.raw_content,
    attributes: event.attributes,
    provenance: event.provenance,
  }
}

///|
fn alias_canonical_resource(
  event : CanonicalEvent,
  mapping : ResourceAlias,
) -> CanonicalEvent {
  let resource = match event.resource {
    Some(resource) =>
      if resource.id == mapping.source_id {
        Some({
          kind: resource.kind,
          id: mapping.canonical_id,
          attributes: resource.attributes,
        })
      } else {
        Some(resource)
      }
    None => None
  }
  {
    event_id: event.event_id,
    event_time: event.event_time,
    observed_time: event.observed_time,
    source: event.source,
    resource,
    category: event.category,
    event_type: event.event_type,
    action: event.action,
    outcome: event.outcome,
    severity: event.severity,
    body: event.body,
    raw_content: event.raw_content,
    attributes: event.attributes,
    provenance: event.provenance,
  }
}

///|
fn validate_processor_pipeline(
  pipeline : ProcessorPipeline,
) -> Unit raise ProcessorError {
  if pipeline.name.trim() == "" {
    raise ProcessorError::InvalidStage("pipeline name must not be empty")
  }
  for stage in pipeline.stages {
    match stage {
      Normalize => ()
      AliasResource(mapping) =>
        if mapping.source_id.trim() == "" || mapping.canonical_id.trim() == "" {
          raise ProcessorError::InvalidStage(
            "resource aliases must not contain empty identities",
          )
        }
      FilterSource(source_id) =>
        if source_id.trim() == "" {
          raise ProcessorError::InvalidStage("source filters must not be empty")
        }
      FilterCategory(_) => ()
      FilterResource(resource_id) =>
        if resource_id.trim() == "" {
          raise ProcessorError::InvalidStage(
            "resource filters must not be empty",
          )
        }
      FilterTimeWindow(start, end) =>
        if compare_timestamps(start, end) > 0 {
          raise ProcessorError::InvalidWindow
        }
    }
  }
}

///|
fn event_in_time_window(
  event : CanonicalEvent,
  start : NormalizedTimestamp,
  end : NormalizedTimestamp,
) -> Bool {
  match event.event_time {
    Some(timestamp) =>
      compare_timestamps(timestamp, start) >= 0 &&
      compare_timestamps(timestamp, end) <= 0
    None => false
  }
}

///|
fn apply_processor_stage(
  events : Array[CanonicalEvent],
  stage : ProcessorStage,
) -> Array[CanonicalEvent] {
  let transformed : Array[CanonicalEvent] = []
  match stage {
    Normalize =>
      for event in events {
        transformed.push(normalize_canonical_event(event))
      }
    AliasResource(mapping) =>
      for event in events {
        transformed.push(alias_canonical_resource(event, mapping))
      }
    FilterSource(source_id) => {
      let expected = source_id.trim().to_owned()
      for event in events {
        let actual = normalize_source_id(
          event.source.system,
          event.source.component,
          event.source.host,
        )
        if actual == expected {
          transformed.push(event)
        }
      }
    }
    FilterCategory(category) =>
      for event in events {
        if event.category == category {
          transformed.push(event)
        }
      }
    FilterResource(resource_id) => {
      let expected = resource_id.trim().to_owned()
      for event in events {
        match event.resource {
          Some(resource) =>
            if resource.id == expected {
              transformed.push(event)
            }
          None => ()
        }
      }
    }
    FilterTimeWindow(start, end) =>
      for event in events {
        if event_in_time_window(event, start, end) {
          transformed.push(event)
        }
      }
  }
  transformed
}

///|
/// Validates and runs stages in declaration order, preserving event order.
///
/// Filter stages are inclusive and stable. A Normalize stage trims structured
/// identifiers only; raw content, body, attributes, and provenance are retained.
pub fn process_events(
  events : Array[CanonicalEvent],
  pipeline : ProcessorPipeline,
) -> Array[CanonicalEvent] raise ProcessorError {
  validate_processor_pipeline(pipeline)
  let mut processed = events
  for stage in pipeline.stages {
    processed = apply_processor_stage(processed, stage)
  }
  processed
}
