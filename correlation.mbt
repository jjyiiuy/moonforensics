///|
/// The observed role of an event in a cross-source correlation.
pub(all) enum CorrelationKind {
  Change
  Alert
  Crash
  Other(String)
} derive(Debug, Eq, ToJson)

///|
/// A normalized event annotated with the resource and event role used for correlation.
pub(all) struct CorrelationEvent {
  event : NormalizedEvent
  resource_id : String
  kind : CorrelationKind
} derive(Debug, Eq, ToJson)

///|
/// Events from distinct sources that refer to one resource inside a time window.
pub(all) struct CorrelationGroup {
  resource_id : String
  events : Array[CorrelationEvent]
} derive(Debug, Eq, ToJson)

///|
/// A correlation request that cannot be evaluated because its window is negative.
pub(all) suberror CorrelationError {
  InvalidWindow
} derive(Debug, Eq)

///|
fn compare_correlation_events(
  left : CorrelationEvent,
  right : CorrelationEvent,
) -> Int {
  match (left.event.timestamp, right.event.timestamp) {
    (Some(left_time), Some(right_time)) =>
      compare_timestamps(left_time, right_time)
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => 0
  }
}

///|
fn merge_correlation_events(
  left : Array[CorrelationEvent],
  right : Array[CorrelationEvent],
) -> Array[CorrelationEvent] {
  let merged : Array[CorrelationEvent] = []
  for left_index = 0, right_index = 0; left_index < left.length() &&
     right_index < right.length(); {
    if compare_correlation_events(left[left_index], right[right_index]) <= 0 {
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
fn sort_correlation_events(
  events : Array[CorrelationEvent],
) -> Array[CorrelationEvent] {
  if events.length() <= 1 {
    events
  } else {
    let midpoint = events.length() / 2
    let left : Array[CorrelationEvent] = []
    let right : Array[CorrelationEvent] = []
    for index, event in events {
      if index < midpoint {
        left.push(event)
      } else {
        right.push(event)
      }
    }
    merge_correlation_events(
      sort_correlation_events(left),
      sort_correlation_events(right),
    )
  }
}

///|
fn timestamp_within_window(
  anchor : NormalizedTimestamp,
  candidate : NormalizedTimestamp,
  window_seconds : Int,
) -> Bool {
  let day_delta = candidate.epoch_day - anchor.epoch_day
  if day_delta < 0 {
    false
  } else {
    let elapsed_seconds = day_delta * 86400 +
      candidate.second_of_day -
      anchor.second_of_day
    elapsed_seconds >= 0 &&
    (
      elapsed_seconds < window_seconds ||
      (
        elapsed_seconds == window_seconds &&
        candidate.nanosecond <= anchor.nanosecond
      )
    )
  }
}

///|
fn has_distinct_sources(events : Array[CorrelationEvent]) -> Bool {
  if events.length() < 2 {
    false
  } else {
    let first_source = events[0].event.source_id
    for event in events {
      if event.event.source_id != first_source {
        return true
      }
    }
    false
  }
}

///|
/// Groups same-resource events when at least two distinct sources fall within the
/// inclusive window from the group's earliest event. Results and group members are
/// ordered chronologically; equal timestamps retain input order. Events without a
/// timestamp are ignored. A group records temporal/resource correlation, not causation.
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
///   let base = NormalizedEvent::{
///     timestamp: Some(time),
///     severity: None,
///     source_id: "config/controller",
///     raw_content: "pool size changed",
///   }
///   let health = NormalizedEvent::{
///     timestamp: Some(time),
///     severity: None,
///     source_id: "health/checker",
///     raw_content: "health check failed",
///   }
///   let groups = correlate_events(
///     [
///       CorrelationEvent::{
///         event: base,
///         resource_id: "orders-api",
///         kind: CorrelationKind::Change,
///       },
///       CorrelationEvent::{
///         event: health,
///         resource_id: "orders-api",
///         kind: CorrelationKind::Alert,
///       },
///     ],
///     30,
///   )
///   assert_eq(groups.length(), 1)
///   assert_eq(groups[0].events.length(), 2)
/// }
/// ```
pub fn correlate_events(
  events : Array[CorrelationEvent],
  window_seconds : Int,
) -> Array[CorrelationGroup] raise CorrelationError {
  if window_seconds < 0 {
    raise CorrelationError::InvalidWindow
  }
  let sorted = sort_correlation_events(events)
  let consumed : Array[Bool] = []
  for _ in sorted {
    consumed.push(false)
  }
  let groups : Array[CorrelationGroup] = []
  for anchor_index, anchor in sorted {
    if consumed[anchor_index] {
      continue
    }
    match anchor.event.timestamp {
      Some(anchor_time) => {
        let candidates : Array[CorrelationEvent] = []
        for index in anchor_index..<sorted.length() {
          let candidate = sorted[index]
          if !consumed[index] && candidate.resource_id == anchor.resource_id {
            match candidate.event.timestamp {
              Some(timestamp) =>
                if timestamp_within_window(
                    anchor_time, timestamp, window_seconds,
                  ) {
                  candidates.push(candidate)
                }
              None => ()
            }
          }
        }
        if has_distinct_sources(candidates) {
          let members : Array[CorrelationEvent] = []
          for index in anchor_index..<sorted.length() {
            let candidate = sorted[index]
            if !consumed[index] && candidate.resource_id == anchor.resource_id {
              match candidate.event.timestamp {
                Some(timestamp) =>
                  if timestamp_within_window(
                      anchor_time, timestamp, window_seconds,
                    ) {
                    consumed[index] = true
                    members.push(candidate)
                  }
                None => ()
              }
            }
          }
          groups.push({ resource_id: anchor.resource_id, events: members, })
        }
      }
      None => ()
    }
  }
  groups
}
