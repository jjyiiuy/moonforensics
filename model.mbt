///|
/// A timestamp preserved as the original RFC 3339 text.
///
/// Parsing and validation belong to the ingest stage. Keeping the value intact
/// here makes the domain model lossless and deterministic.
pub(all) struct Timestamp {
  value : String
} derive(Debug, Eq, ToJson)

///|
/// The kind of source file represented by an evidence item.
pub(all) enum EvidenceFormat {
  JsonLines
  PlainText
} derive(Debug, Eq, ToJson)

///|
/// Identifies the system component that produced an evidence item.
pub(all) struct EvidenceSource {
  system : String
  component : String
  host : String?
} derive(Debug, Eq, ToJson)

///|
/// A stable key-value metadata entry attached to a case or evidence item.
pub(all) struct MetadataEntry {
  key : String
  value : String
} derive(Debug, Eq, ToJson)

///|
/// Metadata shared by the case and its individual evidence items.
pub(all) struct EvidenceMetadata {
  entries : Array[MetadataEntry]
} derive(Debug, Eq, ToJson)

///|
/// One user-provided source file and its provenance information.
pub(all) struct EvidenceItem {
  id : String
  source : EvidenceSource
  path : String
  format : EvidenceFormat
  captured_at : Timestamp?
  metadata : EvidenceMetadata
} derive(Debug, Eq, ToJson)

///|
/// The top-level container for one incident investigation.
pub(all) struct Case {
  case_id : String
  title : String
  timezone : String
  collected_at : Timestamp
  evidence : Array[EvidenceItem]
  metadata : EvidenceMetadata
} derive(Debug, Eq, ToJson)
