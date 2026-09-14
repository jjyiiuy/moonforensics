///|
fn correlation_test_event(
  second : Int,
  source_id : String,
  raw_content : String,
) -> @moonforensics.NormalizedEvent {
  @moonforensics.NormalizedEvent::{
    timestamp: Some(@moonforensics.NormalizedTimestamp::{
      epoch_day: 1,
      second_of_day: second,
      nanosecond: 0,
      raw: "test-time",
    }),
    severity: None,
    source_id,
    raw_content,
  }
}

///|
fn correlation_test_item(
  second : Int,
  source_id : String,
  resource_id : String,
  kind : @moonforensics.CorrelationKind,
  raw_content : String,
) -> @moonforensics.CorrelationEvent {
  @moonforensics.CorrelationEvent::{
    event: correlation_test_event(second, source_id, raw_content),
    resource_id,
    kind,
  }
}

///|
test "correlates changes alerts and crashes across sources for one resource" {
  let events = [
    correlation_test_item(
      140,
      "process/supervisor",
      "checkout-api-01",
      @moonforensics.CorrelationKind::Crash,
      "Process exited with a non-zero status",
    ),
    correlation_test_item(
      100,
      "config/controller",
      "checkout-api-01",
      @moonforensics.CorrelationKind::Change,
      "Configuration value applied",
    ),
    correlation_test_item(
      120,
      "health/checker",
      "checkout-api-01",
      @moonforensics.CorrelationKind::Alert,
      "health check failed",
    ),
  ]
  let groups = @moonforensics.correlate_events(events, 60)

  assert_eq(groups.length(), 1)
  assert_eq(groups[0].resource_id, "checkout-api-01")
  assert_eq(groups[0].events.length(), 3)
  assert_eq(groups[0].events[0].kind, @moonforensics.CorrelationKind::Change)
  assert_eq(groups[0].events[1].kind, @moonforensics.CorrelationKind::Alert)
  assert_eq(groups[0].events[2].kind, @moonforensics.CorrelationKind::Crash)
  assert_eq(
    groups[0].events[0].event.raw_content,
    "Configuration value applied",
  )
}

///|
test "correlation requires a shared resource and distinct sources in the window" {
  let groups = @moonforensics.correlate_events(
    [
      correlation_test_item(
        100,
        "config/controller",
        "orders-api",
        @moonforensics.CorrelationKind::Change,
        "change",
      ),
      correlation_test_item(
        105,
        "config/controller",
        "orders-api",
        @moonforensics.CorrelationKind::Change,
        "same source",
      ),
      correlation_test_item(
        110,
        "health/checker",
        "orders-api",
        @moonforensics.CorrelationKind::Alert,
        "inclusive boundary",
      ),
      correlation_test_item(
        108,
        "health/checker",
        "catalog-api",
        @moonforensics.CorrelationKind::Alert,
        "other resource",
      ),
      correlation_test_item(
        111,
        "process/supervisor",
        "orders-api",
        @moonforensics.CorrelationKind::Crash,
        "outside window",
      ),
    ],
    10,
  )

  assert_eq(groups.length(), 1)
  assert_eq(groups[0].resource_id, "orders-api")
  assert_eq(groups[0].events.length(), 3)
  assert_eq(groups[0].events[0].event.raw_content, "change")
  assert_eq(groups[0].events[1].event.raw_content, "same source")
  assert_eq(groups[0].events[2].event.raw_content, "inclusive boundary")
}

///|
test "correlation results are deterministic and retain equal-time input order" {
  let events = [
    correlation_test_item(
      100,
      "config/controller",
      "orders-api",
      @moonforensics.CorrelationKind::Change,
      "first tie",
    ),
    correlation_test_item(
      100,
      "health/checker",
      "orders-api",
      @moonforensics.CorrelationKind::Alert,
      "second tie",
    ),
    correlation_test_item(
      110,
      "process/supervisor",
      "orders-api",
      @moonforensics.CorrelationKind::Crash,
      "later",
    ),
  ]
  let first = @moonforensics.correlate_events(events, 10)
  let second = @moonforensics.correlate_events(events, 10)

  assert_eq(first, second)
  assert_eq(first[0].events[0].event.raw_content, "first tie")
  assert_eq(first[0].events[1].event.raw_content, "second tie")
}

///|
test "correlation rejects a negative time window" {
  try @moonforensics.correlate_events([], -1) catch {
    @moonforensics.CorrelationError::InvalidWindow => ()
  } noraise {
    _ => fail("expected a negative correlation window to fail")
  }
}
