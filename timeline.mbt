///|
/// An ordered collection of normalized events for deterministic timeline queries.
pub(all) struct Timeline {
  events : Array[NormalizedEvent]
} derive(Debug, Eq, ToJson)

///|
/// A query window that cannot be evaluated because its start follows its end.
pub(all) suberror TimelineError {
  InvalidWindow
} derive(Debug, Eq)

///|
fn compare_timeline_events(
  left : NormalizedEvent,
  right : NormalizedEvent,
) -> Int {
  match (left.timestamp, right.timestamp) {
    (Some(left_time), Some(right_time)) =>
      compare_timestamps(left_time, right_time)
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => 0
  }
}

///|
fn merge_timeline_events(
  left : Array[NormalizedEvent],
  right : Array[NormalizedEvent],
) -> Array[NormalizedEvent] {
  let merged : Array[NormalizedEvent] = []
  for left_index = 0, right_index = 0; left_index < left.length() &&
     right_index < right.length(); {
    if compare_timeline_events(left[left_index], right[right_index]) <= 0 {
      merged.push(left[left_index])
      continue left_index + 1, right_index
    } else {
      merged.push(right[right_index])
      continue left_index, right_index + 1
    }
  } nobreak {
    for index in left_index..<left.length() {
      merged.push(left[index])
    }
    for index in right_index..<right.length() {
      merged.push(right[index])
    }
  }
  merged
}

///|
fn sort_timeline_events(
  events : Array[NormalizedEvent],
) -> Array[NormalizedEvent] {
  if events.length() <= 1 {
    events
  } else {
    let midpoint = events.length() / 2
    let left : Array[NormalizedEvent] = []
    let right : Array[NormalizedEvent] = []
    for index, event in events {
      if index < midpoint {
        left.push(event)
      } else {
        right.push(event)
      }
    }
    merge_timeline_events(
      sort_timeline_events(left),
      sort_timeline_events(right),
    )
  }
}

///|
/// Builds a stable timeline ordered by UTC time; events without timestamps come last.
/// Equal timestamps retain their input order.
///
/// # Example
/// ```mbt check
/// test {
///   let event = NormalizedEvent::{
///     timestamp: None,
///     severity: None,
///     source_id: "svc/api",
///     raw_content: "timestamp unavailable",
///   }
///   let timeline = build_timeline([event])
///   assert_eq(timeline.events.length(), 1)
/// }
/// ```
pub fn build_timeline(events : Array[NormalizedEvent]) -> Timeline {
  let sorted = sort_timeline_events(events)
  let copy : Array[NormalizedEvent] = []
  for event in sorted {
    copy.push(event)
  }
  { events: copy, }
}

///|
/// Keeps only events whose normalized source identifier matches `source_id`.
///
/// # Example
/// ```mbt check
/// test {
///   let event = NormalizedEvent::{
///     timestamp: None,
///     severity: None,
///     source_id: "svc/api",
///     raw_content: "entry",
///   }
///   let timeline = build_timeline([event])
///   let filtered = filter_timeline_by_source(timeline, "svc/api")
///   assert_eq(filtered.events.length(), 1)
/// }
/// ```
pub fn filter_timeline_by_source(
  timeline : Timeline,
  source_id : String,
) -> Timeline {
  let events : Array[NormalizedEvent] = []
  for event in timeline.events {
    if event.source_id == source_id {
      events.push(event)
    }
  }
  { events, }
}

///|
/// Returns events with timestamps inside the inclusive UTC window, preserving timeline order.
/// Events without timestamps are omitted.
///
/// # Example
/// ```mbt check
/// test {
///   let time = NormalizedTimestamp::{
///     epoch_day: 1,
///     second_of_day: 10,
///     nanosecond: 0,
///     raw: "start",
///   }
///   let event = NormalizedEvent::{
///     timestamp: Some(time),
///     severity: None,
///     source_id: "svc/api",
///     raw_content: "entry",
///   }
///   let timeline = build_timeline([event])
///   let result = query_timeline_window(timeline, time, time)
///   assert_eq(result.events.length(), 1)
/// }
/// ```
pub fn query_timeline_window(
  timeline : Timeline,
  start : NormalizedTimestamp,
  end : NormalizedTimestamp,
) -> Timeline raise TimelineError {
  if compare_timestamps(start, end) > 0 {
    raise TimelineError::InvalidWindow
  }
  let events : Array[NormalizedEvent] = []
  for event in timeline.events {
    match event.timestamp {
      Some(timestamp) =>
        if compare_timestamps(timestamp, start) >= 0 &&
          compare_timestamps(timestamp, end) <= 0 {
          events.push(event)
        }
      None => ()
    }
  }
  { events, }
}
