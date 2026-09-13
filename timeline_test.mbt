///|
fn timeline_event(
  day : Int?,
  second : Int,
  source_id : String,
  raw_content : String,
) -> @moonforensics.NormalizedEvent {
  let timestamp = match day {
    Some(epoch_day) =>
      Some(@moonforensics.NormalizedTimestamp::{
        epoch_day,
        second_of_day: second,
        nanosecond: 0,
        raw: "test-time",
      })
    None => None
  }
  @moonforensics.NormalizedEvent::{
    timestamp,
    severity: None,
    source_id,
    raw_content,
  }
}

///|
test "timeline sorting is repeatable and stable for equal timestamps" {
  let input = [
    timeline_event(Some(2), 5, "svc/a", "late"),
    timeline_event(Some(1), 9, "svc/a", "first-tie"),
    timeline_event(Some(1), 9, "svc/b", "second-tie"),
    timeline_event(Some(1), 3, "svc/b", "early"),
    timeline_event(None, 0, "svc/a", "missing-time"),
  ]
  let first = @moonforensics.build_timeline(input)
  let second = @moonforensics.build_timeline(input)

  assert_eq(first, second)
  assert_eq(first.events[0].raw_content, "early")
  assert_eq(first.events[1].raw_content, "first-tie")
  assert_eq(first.events[2].raw_content, "second-tie")
  assert_eq(first.events[3].raw_content, "late")
  assert_eq(first.events[4].raw_content, "missing-time")
}

///|
test "timeline filters by normalized source without changing order" {
  let timeline = @moonforensics.build_timeline([
    timeline_event(Some(1), 20, "svc/a", "a-later"),
    timeline_event(Some(1), 10, "svc/b", "b-event"),
    timeline_event(Some(1), 15, "svc/a", "a-earlier"),
  ])
  let filtered = @moonforensics.filter_timeline_by_source(timeline, "svc/a")

  assert_eq(filtered.events.length(), 2)
  assert_eq(filtered.events[0].raw_content, "a-earlier")
  assert_eq(filtered.events[1].raw_content, "a-later")
}

///|
test "timeline window includes boundaries and omits missing timestamps" {
  let timeline = @moonforensics.build_timeline([
    timeline_event(Some(1), 30, "svc/a", "after"),
    timeline_event(Some(1), 10, "svc/a", "start"),
    timeline_event(None, 0, "svc/a", "unknown"),
    timeline_event(Some(1), 20, "svc/a", "end"),
  ])
  let window = @moonforensics.query_timeline_window(
    timeline,
    @moonforensics.NormalizedTimestamp::{
      epoch_day: 1,
      second_of_day: 10,
      nanosecond: 0,
      raw: "start",
    },
    @moonforensics.NormalizedTimestamp::{
      epoch_day: 1,
      second_of_day: 20,
      nanosecond: 0,
      raw: "end",
    },
  )

  assert_eq(window.events.length(), 2)
  assert_eq(window.events[0].raw_content, "start")
  assert_eq(window.events[1].raw_content, "end")
}

///|
test "timeline rejects a window whose start is after its end" {
  let timeline = @moonforensics.build_timeline([])
  try
    @moonforensics.query_timeline_window(
      timeline,
      @moonforensics.NormalizedTimestamp::{
        epoch_day: 2,
        second_of_day: 0,
        nanosecond: 0,
        raw: "later",
      },
      @moonforensics.NormalizedTimestamp::{
        epoch_day: 1,
        second_of_day: 0,
        nanosecond: 0,
        raw: "earlier",
      },
    )
  catch {
    @moonforensics.TimelineError::InvalidWindow => ()
  } noraise {
    _ => fail("expected an invalid timeline window")
  }
}
