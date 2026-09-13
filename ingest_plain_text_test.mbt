///|
test "parse_plain_text preserves order and physical line numbers" {
  let source =
    #|2026-01-15T10:00:00Z INFO service_started
    #|
    #|  ERROR indented_detail
  let records = @moonforensics.parse_plain_text(source)

  assert_eq(records.length(), 2)
  assert_eq(records[0].line_number, 1)
  assert_eq(records[0].text, "2026-01-15T10:00:00Z INFO service_started")
  assert_eq(records[1].line_number, 3)
  assert_eq(records[1].text, "  ERROR indented_detail")
}

///|
test "parse_plain_text accepts CRLF input" {
  let records = @moonforensics.parse_plain_text(
    "INFO service_started\r\nWARN service_degraded\r\n",
  )

  assert_eq(records.length(), 2)
  assert_eq(records[1].line_number, 2)
  assert_eq(records[1].text, "WARN service_degraded")
}

///|
test "parse_plain_text accepts records without timestamps" {
  let records = @moonforensics.parse_plain_text(
    "service started\n\t\nERROR connection refused\n",
  )

  assert_eq(records.length(), 2)
  assert_eq(records[0].text, "service started")
  assert_eq(records[1].line_number, 3)
  assert_eq(records[1].text, "ERROR connection refused")
}
