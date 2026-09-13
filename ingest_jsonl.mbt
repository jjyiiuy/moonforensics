///|
/// One JSON object parsed from a physical line in a JSONL stream.
pub(all) struct JsonlRecord {
  line_number : Int
  value : Json
} derive(Debug, Eq, ToJson)

///|
/// A JSONL syntax or record-shape error with its physical source line.
pub(all) suberror JsonlParseError {
  InvalidJson(line_number~ : Int, line~ : String)
  ExpectedObject(line_number~ : Int, line~ : String)
} derive(Debug, Eq)

///|
/// Parses JSONL text into ordered object records while preserving line numbers.
/// Empty and whitespace-only lines are ignored. Every non-empty line must be a
/// complete JSON object.
///
/// # Example
/// ```mbt check
/// test {
///   let records = parse_jsonl("{\"event_id\":\"evt-1\"}\n")
///   assert_eq(records.length(), 1)
///   assert_eq(records[0].line_number, 1)
/// }
/// ```
pub fn parse_jsonl(source : String) -> Array[JsonlRecord] raise JsonlParseError {
  let records : Array[JsonlRecord] = []
  for index, physical_line in source.split("\n") {
    let line = physical_line.trim().to_owned()
    if line != "" {
      let value = @json.parse(line) catch {
        _ => raise JsonlParseError::InvalidJson(line_number=index + 1, line~)
      }
      guard value is { .. } else {
        raise JsonlParseError::ExpectedObject(line_number=index + 1, line~)
      }
      records.push({ line_number: index + 1, value, })
    }
  }
  records
}
