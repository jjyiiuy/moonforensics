///|
#cfg(any(target="native", target="llvm"))
extern "c" fn moonforensics_process_exit_native(code : Int) = "exit"

///|
#cfg(target="wasm")
fn moonforensics_process_exit_wasm(code : Int) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
#cfg(target="wasm-gc")
fn moonforensics_process_exit_wasm_gc(code : Int) -> Unit = "__moonbit_sys_unstable" "exit"

///|
#cfg(target="js")
extern "js" fn moonforensics_process_exit_js(code : Int) -> Bool =
  #| function(code) {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|     return true;
  #|   }
  #|   return false;
  #| }

///|
#cfg(any(target="native", target="llvm"))
fn process_exit(code : Int) -> Unit {
  moonforensics_process_exit_native(code)
}

///|
#cfg(target="wasm")
fn process_exit(code : Int) -> Unit {
  moonforensics_process_exit_wasm(code)
}

///|
#cfg(target="wasm-gc")
fn process_exit(code : Int) -> Unit {
  moonforensics_process_exit_wasm_gc(code)
}

///|
#cfg(target="js")
fn process_exit(code : Int) -> Unit {
  if !moonforensics_process_exit_js(code) {
    panic()
  }
}

///|
fn usage() -> Unit {
  println("MoonForensics CLI")
  println("Usage:")
  println("  moon run cmd/main -- ingest <jsonl-source>")
  println("  moon run cmd/main -- analyze <jsonl-source>")
  println("  moon run cmd/main -- verify <evidence-source> [expected-sha256]")
  println(
    "Exit codes: 0 success, 2 usage, 3 input error, 4 verification failure",
  )
}

///|
fn read_input(source : String) -> String? {
  if source == "" {
    None
  } else {
    Some(source)
  }
}

///|
fn ingest(source : String) -> Int {
  match read_input(source) {
    Some(source) =>
      try @moonforensics.parse_jsonl(source) catch {
        _ => {
          println("ingest failed (exit code 3): invalid JSONL input")
          return 3
        }
      } noraise {
        records => {
          println("ingest ok (exit code 0): \{records.length()} records")
          0
        }
      }
    None => {
      println("ingest failed (exit code 3): empty input")
      3
    }
  }
}

///|
fn analyze(source : String) -> Int {
  match read_input(source) {
    Some(source) =>
      try @moonforensics.parse_jsonl(source) catch {
        _ => {
          println("analyze failed (exit code 3): invalid JSONL input")
          return 3
        }
      } noraise {
        records => {
          let mapping = @moonforensics.JsonlEventMapping::{
            system: "cli",
            source_field: "source",
            event_id_field: "event_id",
            timestamp_field: "timestamp",
            severity_field: "severity",
            resource_field: Some("resource"),
            resource_override: None,
            kind: @moonforensics.CorrelationKind::Other("input"),
            evidence_id: "cli-jsonl",
          }
          try @moonforensics.adapt_jsonl_records(records, mapping) catch {
            _ => {
              println(
                "analyze failed (exit code 3): required event fields are invalid",
              )
              return 3
            }
          } noraise {
            events =>
              try @moonforensics.correlate_incident_events(events, 60) catch {
                _ => {
                  println(
                    "analyze failed (exit code 3): invalid correlation window",
                  )
                  return 3
                }
              } noraise {
                groups => {
                  let timeline = @moonforensics.incident_timeline(events)
                  println("# Analysis")
                  println("")
                  println("- records: \{records.length()}")
                  println("- events: \{events.length()}")
                  println("- timeline events: \{timeline.events.length()}")
                  println("- correlation groups: \{groups.length()}")
                  println(
                    "- limitations: associations are resource/time observations; no root cause is inferred",
                  )
                  println("analyze finished (exit code 0)")
                  0
                }
              }
          }
        }
      }
    None => {
      println("analyze failed (exit code 3): empty input")
      3
    }
  }
}

///|
fn verify(source : String, expected_sha256 : String?) -> Int {
  match read_input(source) {
    Some(source) => {
      let document = @moonforensics.EvidenceDocument::{
        id: "cli-input",
        path: "<argument>",
        source: @moonforensics.EvidenceSource::{
          system: "cli",
          component: "verify",
          host: None,
        },
        content: @utf8.encode(source),
      }
      let manifest = @moonforensics.build_evidence_manifest([document])
      let entry = manifest.entries[0]
      match expected_sha256 {
        Some(expected) =>
          if entry.sha256 != expected {
            println(
              "verify failed (exit code 4): expected sha256=\{expected}, actual=\{entry.sha256}",
            )
            4
          } else {
            println(
              "verify ok (exit code 0): manifest matches \{entry.size_bytes} bytes, sha256=\{entry.sha256}",
            )
            0
          }
        None => {
          println(
            "verify ok (exit code 0): \{entry.size_bytes} bytes, sha256=\{entry.sha256}",
          )
          0
        }
      }
    }
    None => {
      println("verify failed (exit code 4): empty input")
      4
    }
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    process_exit(2)
    return
  }
  let command = args[1]
  if command == "--help" || command == "-h" {
    usage()
    return
  }
  if args.length() < 3 {
    usage()
    process_exit(2)
    return
  }
  let path = args[2]
  let expected_sha256 = if args.length() >= 4 { Some(args[3]) } else { None }
  let exit_code = match command {
    "ingest" => ingest(path)
    "analyze" => analyze(path)
    "verify" => verify(path, expected_sha256)
    _ => {
      println("unknown command (exit code 2): \{command}")
      usage()
      2
    }
  }
  if exit_code != 0 {
    process_exit(exit_code)
  }
}
