///|
test "normalizes timestamps with offsets into comparable UTC keys" {
  let later = @moonforensics.normalize_timestamp("2026-01-15T10:00:00+02:00")
  let earlier = @moonforensics.normalize_timestamp("2026-01-15T08:30:00Z")
  let same = @moonforensics.normalize_timestamp("2026-01-15T08:00:00Z")

  assert_eq(later.raw, "2026-01-15T10:00:00+02:00")
  assert_true(@moonforensics.compare_timestamps(later, earlier) < 0)
  assert_eq(@moonforensics.compare_timestamps(later, same), 0)
}

///|
test "normalizes fractional timestamps and UTC day boundaries" {
  let before = @moonforensics.normalize_timestamp("2026-01-15T00:30:00+01:00")
  let after = @moonforensics.normalize_timestamp("2026-01-14T23:45:00Z")

  assert_true(@moonforensics.compare_timestamps(before, after) < 0)
  let precise = @moonforensics.normalize_timestamp("2026-01-15T00:00:00.12Z")
  let less_precise = @moonforensics.normalize_timestamp(
    "2026-01-15T00:00:00.120000001Z",
  )
  assert_true(@moonforensics.compare_timestamps(precise, less_precise) < 0)
}

///|
test "normalizes severity aliases and source identifiers" {
  assert_eq(
    @moonforensics.normalize_severity(" warning "),
    @moonforensics.Severity::Warning,
  )
  assert_eq(
    @moonforensics.normalize_severity("critical"),
    @moonforensics.Severity::Fatal,
  )
  assert_eq(
    @moonforensics.normalize_source_id(" host-a ", " api ", Some(" node-1 ")),
    "host-a/api/node-1",
  )
}

///|
test "normalized event preserves raw content and handles missing time" {
  let raw = "2026-01-15T10:00:00Z WARN service restarted  "
  let event = @moonforensics.normalize_event(
    None,
    Some("WARN"),
    "platform",
    "systemd",
    Some("node-1"),
    raw,
  )

  assert_eq(event.timestamp, None)
  assert_eq(event.severity, Some(@moonforensics.Severity::Warning))
  assert_eq(event.source_id, "platform/systemd/node-1")
  assert_eq(event.raw_content, raw)
}

///|
test "rejects malformed timestamps" {
  try @moonforensics.normalize_timestamp("2026-02-30T10:00:00Z") catch {
    @moonforensics.NormalizationError::InvalidTimestamp(value) =>
      assert_eq(value, "2026-02-30T10:00:00Z")
  } noraise {
    _ => fail("expected timestamp normalization to fail")
  }
}
