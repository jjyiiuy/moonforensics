///|
/// One non-empty line parsed from a plain-text log.
pub(all) struct PlainTextRecord {
  line_number : Int
  text : String
} derive(Debug, Eq, ToJson)

///|
/// Parses plain-text logs into ordered records with physical line numbers.
/// Empty and whitespace-only lines are ignored. Leading whitespace is kept,
/// while trailing whitespace and line-ending characters are removed.
///
/// # Example
/// ```mbt check
/// test {
///   let records = parse_plain_text("INFO service started\nservice stopped\n")
///   assert_eq(records.length(), 2)
///   assert_eq(records[1].line_number, 2)
/// }
/// ```
pub fn parse_plain_text(source : String) -> Array[PlainTextRecord] {
  let records : Array[PlainTextRecord] = []
  for index, physical_line in source.split("\n") {
    let text = physical_line.trim_end().to_owned()
    if text.trim() != "" {
      records.push({ line_number: index + 1, text, })
    }
  }
  records
}
