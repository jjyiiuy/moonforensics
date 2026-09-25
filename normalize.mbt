///|
/// A timestamp represented as a UTC day and time, with the original input kept.
pub(all) struct NormalizedTimestamp {
  epoch_day : Int
  second_of_day : Int
  nanosecond : Int
  raw : String
} derive(Debug, Eq, ToJson)

///|
/// A canonical severity label used by normalized events.
pub(all) enum Severity {
  Trace
  Debug
  Info
  Warning
  Error
  Fatal
  Unknown(String)
} derive(Debug, Eq, ToJson)

///|
/// A normalized event that retains its source line exactly as supplied.
pub(all) struct NormalizedEvent {
  timestamp : NormalizedTimestamp?
  severity : Severity?
  source_id : String
  raw_content : String
} derive(Debug, Eq, ToJson)

///|
/// A normalization failure with the original timestamp that could not be read.
pub(all) suberror NormalizationError {
  InvalidTimestamp(String)
} derive(Debug, Eq)

///|
fn digit_at(value : String, index : Int) -> Int? {
  match value[index] {
    '0' => Some(0)
    '1' => Some(1)
    '2' => Some(2)
    '3' => Some(3)
    '4' => Some(4)
    '5' => Some(5)
    '6' => Some(6)
    '7' => Some(7)
    '8' => Some(8)
    '9' => Some(9)
    _ => None
  }
}

///|
fn number_at(
  value : String,
  start : Int,
  length : Int,
) -> Int raise NormalizationError {
  if start < 0 || start + length > value.length() {
    raise NormalizationError::InvalidTimestamp(value)
  }
  let mut result = 0
  for index in start..<(start + length) {
    match digit_at(value, index) {
      Some(digit) => result = result * 10 + digit
      None => raise NormalizationError::InvalidTimestamp(value)
    }
  }
  result
}

///|
fn is_leap_year(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    2 => if is_leap_year(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
fn epoch_day(year : Int, month : Int, day : Int) -> Int {
  let adjusted_year = if month <= 2 { year - 1 } else { year }
  let era = adjusted_year / 400
  let year_of_era = adjusted_year - era * 400
  let adjusted_month = if month > 2 { month - 3 } else { month + 9 }
  let day_of_year = (153 * adjusted_month + 2) / 5 + day - 1
  let day_of_era = year_of_era * 365 +
    year_of_era / 4 -
    year_of_era / 100 +
    day_of_year
  era * 146097 + day_of_era - 719468
}

///|
/// Parses an RFC 3339 timestamp and converts it to a UTC comparison key.
pub fn normalize_timestamp(
  value : String,
) -> NormalizedTimestamp raise NormalizationError {
  let length = value.length()
  guard length >= 20 &&
    value[4] == '-' &&
    value[7] == '-' &&
    (value[10] == 'T' || value[10] == 't') &&
    value[13] == ':' &&
    value[16] == ':' else {
    raise NormalizationError::InvalidTimestamp(value)
  }
  let year = number_at(value, 0, 4)
  let month = number_at(value, 5, 2)
  let day = number_at(value, 8, 2)
  let hour = number_at(value, 11, 2)
  let minute = number_at(value, 14, 2)
  let second = number_at(value, 17, 2)

  let zone_start = if value[length - 1] == 'Z' || value[length - 1] == 'z' {
    length - 1
  } else {
    length - 6
  }
  guard zone_start >= 19 else {
    raise NormalizationError::InvalidTimestamp(value)
  }

  let mut nanosecond = 0
  if zone_start > 19 {
    guard value[19] == '.' && zone_start > 20 else {
      raise NormalizationError::InvalidTimestamp(value)
    }
    let mut fraction_digits = 0
    for index in 20..<zone_start {
      match digit_at(value, index) {
        Some(digit) => {
          if fraction_digits < 9 {
            nanosecond = nanosecond * 10 + digit
          }
          fraction_digits += 1
        }
        None => raise NormalizationError::InvalidTimestamp(value)
      }
    }
    for _ in fraction_digits..<9 {
      nanosecond *= 10
    }
  }

  let mut offset_seconds = 0
  if zone_start == length - 6 {
    guard (value[zone_start] == '+' || value[zone_start] == '-') &&
      value[zone_start + 3] == ':' else {
      raise NormalizationError::InvalidTimestamp(value)
    }
    let offset_hour = number_at(value, zone_start + 1, 2)
    let offset_minute = number_at(value, zone_start + 4, 2)
    guard offset_hour <= 23 && offset_minute <= 59 else {
      raise NormalizationError::InvalidTimestamp(value)
    }
    let sign = if value[zone_start] == '+' { 1 } else { -1 }
    offset_seconds = sign * (offset_hour * 3600 + offset_minute * 60)
  } else {
    guard zone_start == length - 1 else {
      raise NormalizationError::InvalidTimestamp(value)
    }
  }

  guard year >= 1 &&
    month >= 1 &&
    month <= 12 &&
    day >= 1 &&
    day <= days_in_month(year, month) &&
    hour <= 23 &&
    minute <= 59 &&
    second <= 59 else {
    raise NormalizationError::InvalidTimestamp(value)
  }

  let local_seconds = hour * 3600 + minute * 60 + second
  let utc_seconds = local_seconds - offset_seconds
  let utc_day = epoch_day(year, month, day) + utc_seconds / 86400
  let second_of_day = (utc_seconds % 86400 + 86400) % 86400
  let adjusted_day = if utc_seconds < 0 && utc_seconds % 86400 != 0 {
    utc_day - 1
  } else {
    utc_day
  }
  { epoch_day: adjusted_day, second_of_day, nanosecond, raw: value, }
}

///|
/// Compares timestamps chronologically, returning a negative, zero, or positive value.
pub fn compare_timestamps(
  left : NormalizedTimestamp,
  right : NormalizedTimestamp,
) -> Int {
  if left.epoch_day != right.epoch_day {
    left.epoch_day - right.epoch_day
  } else if left.second_of_day != right.second_of_day {
    left.second_of_day - right.second_of_day
  } else {
    left.nanosecond - right.nanosecond
  }
}

///|
/// Maps common severity spellings to a stable enum while retaining unknown labels.
pub fn normalize_severity(value : String) -> Severity {
  match value.trim() {
    "TRACE" | "Trace" | "trace" => Severity::Trace
    "DEBUG" | "Debug" | "debug" => Severity::Debug
    "INFO" | "Info" | "info" => Severity::Info
    "WARN" | "Warn" | "warn" | "WARNING" | "Warning" | "warning" =>
      Severity::Warning
    "ERROR" | "Error" | "error" => Severity::Error
    "FATAL" | "Fatal" | "fatal" | "CRITICAL" | "Critical" | "critical" =>
      Severity::Fatal
    other => Severity::Unknown(other.to_owned())
  }
}

///|
/// Creates a stable slash-delimited source identifier from trimmed components.
pub fn normalize_source_id(
  system : String,
  component : String,
  host : String?,
) -> String {
  let system = system.trim().to_owned()
  let component = component.trim().to_owned()
  let parts : Array[String] = []
  if system != "" {
    parts.push(system)
  }
  if component != "" {
    parts.push(component)
  }
  match host {
    Some(host) => {
      let host = host.trim()
      if host != "" {
        parts.push(host.to_owned())
      }
    }
    None => ()
  }
  parts.join("/")
}

///|
/// Normalizes event fields and keeps the original log content unchanged.
pub fn normalize_event(
  timestamp : String?,
  severity : String?,
  system : String,
  component : String,
  host : String?,
  raw_content : String,
) -> NormalizedEvent raise NormalizationError {
  let timestamp = match timestamp {
    Some(value) => Some(normalize_timestamp(value))
    None => None
  }
  let severity = match severity {
    Some(value) => Some(normalize_severity(value))
    None => None
  }
  {
    timestamp,
    severity,
    source_id: normalize_source_id(system, component, host),
    raw_content,
  }
}
