///|
/// The source location retained when an input record becomes an incident event.
pub(all) struct EventEvidence {
  evidence_id : String
  line_number : Int
} derive(Debug, Eq, ToJson)

///|
/// A normalized event with the identity needed for cross-source analysis.
///
/// `resource_id` is optional because records without an explicit resource remain
/// useful in a timeline but must not be correlated automatically.
pub(all) struct IncidentEvent {
  event_id : String
  normalized : NormalizedEvent
  resource_id : String?
  kind : CorrelationKind
  attributes : Json
  evidence : EventEvidence
} derive(Debug, Eq, ToJson)

///|
/// Explicit field mapping for JSONL records from one source shape.
pub(all) struct JsonlEventMapping {
  system : String
  source_field : String
  event_id_field : String
  timestamp_field : String
  severity_field : String
  resource_field : String?
  resource_override : String?
  kind : CorrelationKind
  evidence_id : String
} derive(Debug, Eq)

///|
/// Mapping for the fixed `<timestamp> <severity> <message>` text format.
pub(all) struct PlainTextEventMapping {
  system : String
  component : String
  resource_id : String?
  kind : CorrelationKind
  evidence_id : String
} derive(Debug, Eq)

///|
/// A record cannot enter the common event contract until its required fields are valid.
pub(all) suberror EventAdaptError {
  MissingField(line_number~ : Int, field~ : String)
  InvalidField(line_number~ : Int, field~ : String, value~ : String)
  InvalidText(line_number~ : Int, reason~ : String)
} derive(Debug, Eq)

///|
fn json_field(value : Json, field : String) -> Json? {
  if value is Object(object) {
    object.get(field)
  } else {
    None
  }
}

///|
fn required_json_string(
  value : Json,
  line_number : Int,
  field : String,
) -> String raise EventAdaptError {
  match json_field(value, field) {
    Some(String(text)) => text
    Some(other) =>
      raise EventAdaptError::InvalidField(
        line_number~,
        field~,
        value=other.stringify(),
      )
    None => raise EventAdaptError::MissingField(line_number~, field~)
  }
}

///|
fn mapped_resource(
  value : Json,
  line_number : Int,
  mapping : JsonlEventMapping,
) -> String? raise EventAdaptError {
  match mapping.resource_override {
    Some(resource) =>
      if resource.trim() == "" {
        raise EventAdaptError::InvalidField(
          line_number~,
          field="resource_override",
          value=resource,
        )
      } else {
        Some(resource.trim().to_owned())
      }
    None =>
      match mapping.resource_field {
        Some(field) => {
          let resource = required_json_string(value, line_number, field)
          if resource.trim() == "" {
            raise EventAdaptError::InvalidField(
              line_number~,
              field~,
              value=resource,
            )
          }
          Some(resource.trim().to_owned())
        }
        None => None
      }
  }
}

///|
fn normalized_from_fields(
  line_number : Int,
  timestamp : String,
  severity : String,
  system : String,
  component : String,
  raw_content : String,
) -> NormalizedEvent raise EventAdaptError {
  normalize_event(
    Some(timestamp),
    Some(severity),
    system,
    component,
    None,
    raw_content,
  ) catch {
    _ =>
      raise EventAdaptError::InvalidField(
        line_number~,
        field="timestamp_or_severity",
        value=raw_content,
      )
  }
}

///|
/// Converts JSONL objects to events using an explicit field and resource mapping.
/// Unknown JSON attributes are retained as `attributes`; no field names are guessed.
pub fn adapt_jsonl_records(
  records : Array[JsonlRecord],
  mapping : JsonlEventMapping,
) -> Array[IncidentEvent] raise EventAdaptError {
  let events : Array[IncidentEvent] = []
  for record in records {
    let event_id = required_json_string(
      record.value,
      record.line_number,
      mapping.event_id_field,
    )
    let timestamp = required_json_string(
      record.value,
      record.line_number,
      mapping.timestamp_field,
    )
    let severity = required_json_string(
      record.value,
      record.line_number,
      mapping.severity_field,
    )
    let component = required_json_string(
      record.value,
      record.line_number,
      mapping.source_field,
    )
    let normalized = normalized_from_fields(
      record.line_number,
      timestamp,
      severity,
      mapping.system,
      component,
      record.value.stringify(),
    )
    events.push({
      event_id,
      normalized,
      resource_id: mapped_resource(record.value, record.line_number, mapping),
      kind: mapping.kind,
      attributes: record.value,
      evidence: {
        evidence_id: mapping.evidence_id,
        line_number: record.line_number,
      },
    })
  }
  events
}

///|
/// Converts fixed-format text records to events with an explicit source mapping.
pub fn adapt_plain_text_records(
  records : Array[PlainTextRecord],
  mapping : PlainTextEventMapping,
) -> Array[IncidentEvent] raise EventAdaptError {
  let events : Array[IncidentEvent] = []
  for record in records {
    let fields : Array[String] = []
    for field in record.text.split(" ") {
      let field = field.trim()
      if field != "" {
        fields.push(field.to_owned())
      }
    }
    guard fields.length() >= 3 else {
      raise EventAdaptError::InvalidText(
        line_number=record.line_number,
        reason="expected timestamp, severity, and message",
      )
    }
    let timestamp = fields[0]
    let severity = fields[1]
    let normalized = normalized_from_fields(
      record.line_number,
      timestamp,
      severity,
      mapping.system,
      mapping.component,
      record.text,
    )
    let resource_id = match mapping.resource_id {
      Some(resource) =>
        if resource.trim() == "" {
          raise EventAdaptError::InvalidText(
            line_number=record.line_number,
            reason="resource_id must not be empty",
          )
        } else {
          Some(resource.trim().to_owned())
        }
      None => None
    }
    events.push({
      event_id: "\{mapping.evidence_id}:\{record.line_number}",
      normalized,
      resource_id,
      kind: mapping.kind,
      attributes: {},
      evidence: {
        evidence_id: mapping.evidence_id,
        line_number: record.line_number,
      },
    })
  }
  events
}

///|
/// Builds the existing timeline view from adapted events without losing event identity.
pub fn incident_timeline(events : Array[IncidentEvent]) -> Timeline {
  build_timeline(events.map(event => event.normalized))
}

///|
/// Correlates adapted events, excluding only events without an explicit resource.
pub fn correlate_incident_events(
  events : Array[IncidentEvent],
  window_seconds : Int,
) -> Array[CorrelationGroup] raise CorrelationError {
  let correlation_events : Array[CorrelationEvent] = []
  for event in events {
    match event.resource_id {
      Some(resource_id) =>
        correlation_events.push({
          event: event.normalized,
          resource_id,
          kind: event.kind,
        })
      None => ()
    }
  }
  correlate_events(correlation_events, window_seconds)
}
