///|
/// A deterministic path through JSON object keys.
///
/// Array indexes, wildcards, and fuzzy key matching are intentionally excluded
/// so a profile cannot silently change meaning when an input schema changes.
pub(all) struct JsonFieldPath {
  segments : Array[String]
} derive(Debug, Eq)

///|
/// A string supplied by a profile or read from an input record.
pub(all) enum ProfileStringValue {
  Constant(String)
  JsonString(JsonFieldPath)
} derive(Debug, Eq)

///|
/// Exact source-to-canonical resource identity mapping.
pub(all) struct ResourceAlias {
  source_id : String
  canonical_id : String
} derive(Debug, Eq)

///|
/// Mapping rules for one typed resource identity.
pub(all) struct ResourceMappingProfile {
  kind : ResourceKind
  id : ProfileStringValue
  prefix : String
  aliases : Array[ResourceAlias]
  attributes_path : JsonFieldPath?
} derive(Debug, Eq)

///|
/// Mapping rules for the producer of a canonical event.
pub(all) struct SourceMappingProfile {
  system : ProfileStringValue
  component : ProfileStringValue
  host : ProfileStringValue?
  instrumentation_scope : ProfileStringValue?
} derive(Debug, Eq)

///|
/// A versioned, reusable mapping from one JSONL schema to CanonicalEvent.
///
/// Required values fail explicitly. Optional configured values may be absent,
/// but a present non-string value is rejected instead of being coerced.
pub(all) struct JsonlMappingProfile {
  id : String
  version : String
  source : SourceMappingProfile
  event_id : ProfileStringValue
  event_time : JsonFieldPath?
  observed_time : JsonFieldPath?
  severity : JsonFieldPath?
  resource : ResourceMappingProfile?
  category : EventCategory
  event_type : ProfileStringValue
  action : ProfileStringValue?
  outcome : EventOutcome
  body_path : JsonFieldPath?
} derive(Debug, Eq)

///|
/// Evidence identity shared by every event produced from one JSONL stream.
pub(all) struct ProfileEvidence {
  evidence_id : String
  path : String
  sha256 : String?
} derive(Debug, Eq)

///|
/// A profile definition or input record could not be mapped safely.
pub(all) suberror ProfileMapError {
  InvalidProfile(field~ : String, reason~ : String)
  MissingValue(line_number~ : Int, path~ : String)
  InvalidValue(line_number~ : Int, path~ : String, value~ : String)
} derive(Debug, Eq)

///|
fn path_label(path : JsonFieldPath) -> String {
  let mut label = ""
  for index, segment in path.segments {
    label = if index == 0 { segment } else { "\{label}.\{segment}" }
  }
  label
}

///|
fn validate_path(
  field : String,
  path : JsonFieldPath,
) -> Unit raise ProfileMapError {
  if path.segments.is_empty() {
    raise ProfileMapError::InvalidProfile(
      field~,
      reason="path must contain at least one object key",
    )
  }
  for segment in path.segments {
    if segment.trim() == "" {
      raise ProfileMapError::InvalidProfile(
        field~,
        reason="path keys must not be empty",
      )
    }
  }
}

///|
fn validate_string_value(
  field : String,
  value : ProfileStringValue,
) -> Unit raise ProfileMapError {
  match value {
    Constant(value) =>
      if value.trim() == "" {
        raise ProfileMapError::InvalidProfile(
          field~,
          reason="constant must not be empty",
        )
      }
    JsonString(path) => validate_path(field, path)
  }
}

///|
fn validate_optional_string_value(
  field : String,
  value : ProfileStringValue?,
) -> Unit raise ProfileMapError {
  match value {
    Some(value) => validate_string_value(field, value)
    None => ()
  }
}

///|
fn validate_resource_profile(
  resource : ResourceMappingProfile,
) -> Unit raise ProfileMapError {
  validate_string_value("resource.id", resource.id)
  match resource.attributes_path {
    Some(path) => validate_path("resource.attributes_path", path)
    None => ()
  }
  for index, resource_alias in resource.aliases {
    if resource_alias.source_id.trim() == "" ||
      resource_alias.canonical_id.trim() == "" {
      raise ProfileMapError::InvalidProfile(
        field="resource.aliases",
        reason="alias identities must not be empty",
      )
    }
    for previous in 0..<index {
      if resource.aliases[previous].source_id == resource_alias.source_id {
        raise ProfileMapError::InvalidProfile(
          field="resource.aliases",
          reason="duplicate source identity: \{resource_alias.source_id}",
        )
      }
    }
  }
}

///|
/// Checks a profile independently from any evidence records.
pub fn validate_jsonl_profile(
  profile : JsonlMappingProfile,
) -> Unit raise ProfileMapError {
  if profile.id.trim() == "" {
    raise ProfileMapError::InvalidProfile(
      field="id",
      reason="profile id must not be empty",
    )
  }
  if profile.version.trim() == "" {
    raise ProfileMapError::InvalidProfile(
      field="version",
      reason="profile version must not be empty",
    )
  }
  validate_string_value("source.system", profile.source.system)
  validate_string_value("source.component", profile.source.component)
  validate_optional_string_value("source.host", profile.source.host)
  validate_optional_string_value(
    "source.instrumentation_scope",
    profile.source.instrumentation_scope,
  )
  validate_string_value("event_id", profile.event_id)
  validate_string_value("event_type", profile.event_type)
  validate_optional_string_value("action", profile.action)
  match profile.event_time {
    Some(path) => validate_path("event_time", path)
    None => ()
  }
  match profile.observed_time {
    Some(path) => validate_path("observed_time", path)
    None => ()
  }
  match profile.severity {
    Some(path) => validate_path("severity", path)
    None => ()
  }
  match profile.resource {
    Some(resource) => validate_resource_profile(resource)
    None => ()
  }
  match profile.body_path {
    Some(path) => validate_path("body_path", path)
    None => ()
  }
}

///|
fn json_at_path(value : Json, path : JsonFieldPath) -> Json? {
  let mut current = value
  for segment in path.segments {
    match current {
      Object(object) =>
        match object.get(segment) {
          Some(next) => current = next
          None => return None
        }
      _ => return None
    }
  }
  Some(current)
}

///|
fn mapped_required_string(
  record : JsonlRecord,
  mapping : ProfileStringValue,
) -> String raise ProfileMapError {
  match mapping {
    Constant(value) => value.trim().to_owned()
    JsonString(path) =>
      match json_at_path(record.value, path) {
        Some(String(value)) =>
          if value.trim() == "" {
            raise ProfileMapError::InvalidValue(
              line_number=record.line_number,
              path=path_label(path),
              value~,
            )
          } else {
            value.trim().to_owned()
          }
        Some(value) =>
          raise ProfileMapError::InvalidValue(
            line_number=record.line_number,
            path=path_label(path),
            value=value.stringify(),
          )
        None =>
          raise ProfileMapError::MissingValue(
            line_number=record.line_number,
            path=path_label(path),
          )
      }
  }
}

///|
fn mapped_optional_string(
  record : JsonlRecord,
  mapping : ProfileStringValue?,
) -> String? raise ProfileMapError {
  match mapping {
    None => None
    Some(Constant(value)) => Some(value.trim().to_owned())
    Some(JsonString(path)) =>
      match json_at_path(record.value, path) {
        Some(String(value)) =>
          if value.trim() == "" {
            None
          } else {
            Some(value.trim().to_owned())
          }
        Some(value) =>
          raise ProfileMapError::InvalidValue(
            line_number=record.line_number,
            path=path_label(path),
            value=value.stringify(),
          )
        None => None
      }
  }
}

///|
fn mapped_timestamp(
  record : JsonlRecord,
  path : JsonFieldPath?,
) -> NormalizedTimestamp? raise ProfileMapError {
  match path {
    None => None
    Some(path) =>
      match json_at_path(record.value, path) {
        None => None
        Some(String(value)) =>
          Some(normalize_timestamp(value)) catch {
            _ =>
              raise ProfileMapError::InvalidValue(
                line_number=record.line_number,
                path=path_label(path),
                value~,
              )
          }
        Some(value) =>
          raise ProfileMapError::InvalidValue(
            line_number=record.line_number,
            path=path_label(path),
            value=value.stringify(),
          )
      }
  }
}

///|
fn mapped_severity(
  record : JsonlRecord,
  path : JsonFieldPath?,
) -> Severity? raise ProfileMapError {
  match path {
    None => None
    Some(path) =>
      match json_at_path(record.value, path) {
        None => None
        Some(String(value)) => Some(normalize_severity(value))
        Some(value) =>
          raise ProfileMapError::InvalidValue(
            line_number=record.line_number,
            path=path_label(path),
            value=value.stringify(),
          )
      }
  }
}

///|
fn canonical_resource_id(
  source_id : String,
  resource : ResourceMappingProfile,
) -> String {
  for resource_alias in resource.aliases {
    if resource_alias.source_id == source_id {
      return resource_alias.canonical_id
    }
  }
  "\{resource.prefix}\{source_id}"
}

///|
fn mapped_resource_ref(
  record : JsonlRecord,
  resource : ResourceMappingProfile?,
) -> ResourceRef? raise ProfileMapError {
  match resource {
    None => None
    Some(resource) => {
      let source_id = mapped_required_string(record, resource.id)
      let attributes : Json = match resource.attributes_path {
        None => {}
        Some(path) =>
          match json_at_path(record.value, path) {
            Some(value) => value
            None =>
              raise ProfileMapError::MissingValue(
                line_number=record.line_number,
                path=path_label(path),
              )
          }
      }
      Some({
        kind: resource.kind,
        id: canonical_resource_id(source_id, resource),
        attributes,
      })
    }
  }
}

///|
fn mapped_body(
  record : JsonlRecord,
  path : JsonFieldPath?,
) -> Json raise ProfileMapError {
  match path {
    None => record.value
    Some(path) =>
      match json_at_path(record.value, path) {
        Some(value) => value
        None =>
          raise ProfileMapError::MissingValue(
            line_number=record.line_number,
            path=path_label(path),
          )
      }
  }
}

///|
/// Applies one validated profile to ordered JSONL records.
///
/// The original object is retained in attributes and raw_content. Every result
/// records the profile id/version and physical evidence line in provenance.
pub fn apply_jsonl_profile(
  records : Array[JsonlRecord],
  profile : JsonlMappingProfile,
  evidence : ProfileEvidence,
) -> Array[CanonicalEvent] raise ProfileMapError {
  validate_jsonl_profile(profile)
  if evidence.evidence_id.trim() == "" {
    raise ProfileMapError::InvalidProfile(
      field="evidence.evidence_id",
      reason="evidence id must not be empty",
    )
  }
  if evidence.path.trim() == "" {
    raise ProfileMapError::InvalidProfile(
      field="evidence.path",
      reason="evidence path must not be empty",
    )
  }
  let events : Array[CanonicalEvent] = []
  for record in records {
    events.push({
      event_id: mapped_required_string(record, profile.event_id),
      event_time: mapped_timestamp(record, profile.event_time),
      observed_time: mapped_timestamp(record, profile.observed_time),
      source: {
        system: mapped_required_string(record, profile.source.system),
        component: mapped_required_string(record, profile.source.component),
        host: mapped_optional_string(record, profile.source.host),
        instrumentation_scope: mapped_optional_string(
          record,
          profile.source.instrumentation_scope,
        ),
      },
      resource: mapped_resource_ref(record, profile.resource),
      category: profile.category,
      event_type: mapped_required_string(record, profile.event_type),
      action: mapped_optional_string(record, profile.action),
      outcome: profile.outcome,
      severity: mapped_severity(record, profile.severity),
      body: mapped_body(record, profile.body_path),
      raw_content: record.value.stringify(),
      attributes: record.value,
      provenance: {
        evidence_id: evidence.evidence_id,
        path: evidence.path,
        line_number: Some(record.line_number),
        byte_offset: None,
        byte_length: None,
        sha256: evidence.sha256,
        profile_id: profile.id,
        profile_version: profile.version,
      },
    })
  }
  events
}
