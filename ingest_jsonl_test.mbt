///|
test "parse_jsonl preserves order and physical line numbers" {
  let source =
    #|{"event_id":"proc-001","severity":"ERROR"}
    #|
    #|  {"event_id":"proc-002","severity":"INFO"}
  let records = @moonforensics.parse_jsonl(source)

  assert_eq(records.length(), 2)
  assert_eq(records[0].line_number, 1)
  assert_eq(records[1].line_number, 3)
  assert_true(records[0].value is { "event_id": String("proc-001"), .. })
  assert_true(records[1].value is { "severity": String("INFO"), .. })
}

///|
test "parse_jsonl accepts CRLF input" {
  let records = @moonforensics.parse_jsonl(
    "{\"event_id\":\"evt-1\"}\r\n{\"event_id\":\"evt-2\"}\r\n",
  )

  assert_eq(records.length(), 2)
  assert_eq(records[1].line_number, 2)
}

///|
test "parse_jsonl reports malformed JSON line" {
  try @moonforensics.parse_jsonl("{\"event_id\":\"evt-1\"}\nnot-json\n") catch {
    @moonforensics.JsonlParseError::InvalidJson(line_number~, line~) => {
      assert_eq(line_number, 2)
      assert_eq(line, "not-json")
    }
    _ => fail("expected InvalidJson")
  } noraise {
    _ => fail("expected JSONL parsing to fail")
  }
}

///|
test "parse_jsonl rejects non-object records" {
  try @moonforensics.parse_jsonl("{\"event_id\":\"evt-1\"}\n[]\n") catch {
    @moonforensics.JsonlParseError::ExpectedObject(line_number~, line~) => {
      assert_eq(line_number, 2)
      assert_eq(line, "[]")
    }
    _ => fail("expected ExpectedObject")
  } noraise {
    _ => fail("expected JSONL parsing to fail")
  }
}
