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
  println(
    "  moon run cmd/main -- analyze <jsonl-source> [profile-id] [pack-id]",
  )
  println("  moon run cmd/main -- case <jsonl-source> [profile-id] [pack-id]")
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
fn cli_profile_with_category(
  profile_id : String,
  category : @moonforensics.EventCategory,
) -> @moonforensics.JsonlMappingProfile {
  @moonforensics.JsonlMappingProfile::{
    id: profile_id,
    version: "1.0.0",
    source: @moonforensics.SourceMappingProfile::{
      system: @moonforensics.ProfileStringValue::Constant("cli"),
      component: @moonforensics.ProfileStringValue::JsonString({
        segments: ["source"],
      }),
      host: Some(
        @moonforensics.ProfileStringValue::JsonString({ segments: ["host"], }),
      ),
      instrumentation_scope: None,
    },
    event_id: @moonforensics.ProfileStringValue::JsonString({
      segments: ["event_id"],
    }),
    event_time: Some({ segments: ["timestamp"], }),
    observed_time: None,
    severity: Some({ segments: ["severity"], }),
    resource: Some(@moonforensics.ResourceMappingProfile::{
      kind: @moonforensics.ResourceKind::Service,
      id: @moonforensics.ProfileStringValue::JsonString({
        segments: ["resource"],
      }),
      prefix: "",
      aliases: [],
      attributes_path: None,
    }),
    category,
    event_type: @moonforensics.ProfileStringValue::JsonString({
      segments: ["event_type"],
    }),
    action: Some(
      @moonforensics.ProfileStringValue::JsonString({ segments: ["action"], }),
    ),
    outcome: @moonforensics.EventOutcome::Unknown,
    body_path: None,
  }
}

///|
/// Built-in profiles keep the CLI contract small while making the mapping
/// choice explicit and reproducible. Each profile fixes the semantic category;
/// event fields and resource identity still come from the input object.
fn cli_profile(profile_id : String) -> @moonforensics.JsonlMappingProfile? {
  match profile_id {
    "flat-v1" =>
      Some(
        cli_profile_with_category(
          profile_id,
          @moonforensics.EventCategory::Other("input"),
        ),
      )
    "config-v1" =>
      Some(
        cli_profile_with_category(
          profile_id,
          @moonforensics.EventCategory::Change,
        ),
      )
    "crash-v1" =>
      Some(
        cli_profile_with_category(
          profile_id,
          @moonforensics.EventCategory::Process,
        ),
      )
    "health-v1" =>
      Some(
        cli_profile_with_category(
          profile_id,
          @moonforensics.EventCategory::Availability,
        ),
      )
    "latency-v1" =>
      Some(
        cli_profile_with_category(
          profile_id,
          @moonforensics.EventCategory::Performance,
        ),
      )
    "auto-v1" =>
      Some(
        cli_profile_with_category(
          profile_id,
          @moonforensics.EventCategory::Other("input"),
        ),
      )
    _ => None
  }
}

///|
fn default_pack_for_profile(profile_id : String) -> String {
  match profile_id {
    "config-v1" => "config"
    "crash-v1" => "crash"
    "latency-v1" => "latency"
    _ => "none"
  }
}

///|
fn valid_pack(pack_id : String) -> Bool {
  pack_id == "none" ||
  pack_id == "config" ||
  pack_id == "crash" ||
  pack_id == "latency"
}

///|
fn profile_graph(
  events : Array[@moonforensics.CanonicalEvent],
  pack_id : String,
) -> @moonforensics.IncidentGraph raise @moonforensics.CorrelationRuleError {
  match pack_id {
    "none" => @moonforensics.build_incident_graph(events, [])
    "config" =>
      @moonforensics.analyze_with_pack(
        events,
        @moonforensics.config_analysis_pack(),
      )
    "crash" =>
      @moonforensics.analyze_with_pack(
        events,
        @moonforensics.crash_analysis_pack(),
      )
    "latency" =>
      @moonforensics.analyze_with_pack(
        events,
        @moonforensics.latency_analysis_pack(),
      )
    _ => @moonforensics.build_incident_graph(events, [])
  }
}

///|
fn profile_case_collected_at(
  events : Array[@moonforensics.CanonicalEvent],
) -> @moonforensics.Timestamp {
  for event in events {
    match event.event_time {
      Some(timestamp) =>
        return @moonforensics.Timestamp::{ value: timestamp.raw, }
      None => ()
    }
  }
  @moonforensics.Timestamp::{ value: "unknown", }
}

///|
fn profile_case_timeline(
  events : Array[@moonforensics.CanonicalEvent],
) -> @moonforensics.Timeline {
  let normalized : Array[@moonforensics.NormalizedEvent] = []
  for event in events {
    normalized.push({
      timestamp: event.event_time,
      severity: event.severity,
      source_id: @moonforensics.normalize_source_id(
        event.source.system,
        event.source.component,
        event.source.host,
      ),
      raw_content: event.raw_content,
    })
  }
  @moonforensics.build_timeline(normalized)
}

///|
fn record_profile_id(record : @moonforensics.JsonlRecord) -> String? {
  match record.value {
    Json::Object(fields) =>
      match fields.get("profile") {
        Some(Json::String(value)) =>
          if value.trim() == "" {
            None
          } else {
            Some(value.trim().to_owned())
          }
        _ => None
      }
    _ => None
  }
}

///|
fn map_auto_profile_records(
  records : Array[@moonforensics.JsonlRecord],
  evidence : @moonforensics.ProfileEvidence,
) -> Array[@moonforensics.CanonicalEvent] raise @moonforensics.ProfileMapError {
  let events : Array[@moonforensics.CanonicalEvent] = []
  for record in records {
    let profile_id = match record_profile_id(record) {
      Some(value) => value
      None => "flat-v1"
    }
    let profile = match cli_profile(profile_id) {
      Some(profile) => profile
      None =>
        raise @moonforensics.ProfileMapError::InvalidProfile(
          field="profile",
          reason="unknown CLI profile: \{profile_id}",
        )
    }
    let mapped = @moonforensics.apply_jsonl_profile([record], profile, evidence)
    for event in mapped {
      events.push(event)
    }
  }
  events
}

///|
fn profile_case(
  source : String,
  profile_id : String,
  requested_pack : String,
) -> Int {
  let selected_pack = if requested_pack == "" {
    default_pack_for_profile(profile_id)
  } else {
    requested_pack
  }
  if !valid_pack(selected_pack) {
    println("case failed (exit code 2): unknown analysis pack")
    return 2
  }
  let profile = match cli_profile(profile_id) {
    Some(profile) => profile
    None => {
      println("case failed (exit code 2): unknown mapping profile")
      return 2
    }
  }
  match read_input(source) {
    Some(source) =>
      try @moonforensics.parse_jsonl(source) catch {
        _ => {
          println("case failed (exit code 3): invalid JSONL input")
          return 3
        }
      } noraise {
        records => {
          if records.length() == 0 {
            println("case failed (exit code 3): empty input")
            return 3
          }
          let evidence_bytes = @utf8.encode(source)
          let document = @moonforensics.EvidenceDocument::{
            id: "cli-input",
            path: "<argument>",
            source: @moonforensics.EvidenceSource::{
              system: "cli",
              component: "case",
              host: None,
            },
            content: evidence_bytes,
          }
          let manifest = @moonforensics.build_evidence_manifest([document])
          let evidence = @moonforensics.ProfileEvidence::{
            evidence_id: "cli-input",
            path: "<argument>",
            sha256: Some(manifest.entries[0].sha256),
          }
          try {
            if profile_id == "auto-v1" {
              map_auto_profile_records(records, evidence)
            } else {
              @moonforensics.apply_jsonl_profile(records, profile, evidence)
            }
          } catch {
            _ => {
              println("case failed (exit code 3): profile mapping error")
              return 3
            }
          } noraise {
            events =>
              try profile_graph(events, selected_pack) catch {
                _ => {
                  println("case failed (exit code 3): analysis pack error")
                  return 3
                }
              } noraise {
                graph => {
                  let case = @moonforensics.Case::{
                    case_id: "cli-case",
                    title: "Profile-driven case analysis",
                    timezone: "UTC",
                    collected_at: profile_case_collected_at(events),
                    evidence: [
                      @moonforensics.EvidenceItem::{
                        id: "cli-input",
                        source: @moonforensics.EvidenceSource::{
                          system: "cli",
                          component: "case",
                          host: None,
                        },
                        path: "<argument>",
                        format: @moonforensics.EvidenceFormat::JsonLines,
                        captured_at: None,
                        metadata: @moonforensics.EvidenceMetadata::{
                          entries: [
                            @moonforensics.MetadataEntry::{
                              key: "profile_id",
                              value: profile.id,
                            },
                            @moonforensics.MetadataEntry::{
                              key: "profile_version",
                              value: profile.version,
                            },
                          ],
                        },
                      },
                    ],
                    metadata: @moonforensics.EvidenceMetadata::{
                      entries: [
                        @moonforensics.MetadataEntry::{
                          key: "profile_id",
                          value: profile.id,
                        },
                        @moonforensics.MetadataEntry::{
                          key: "analysis_pack",
                          value: selected_pack,
                        },
                      ],
                    },
                  }
                  let report = @moonforensics.ForensicReport::{
                    case,
                    summary: "Canonical events were mapped with an explicit profile and analyzed with a declared pack.",
                    timeline: profile_case_timeline(events),
                    findings: @moonforensics.DiagnosticReport::{ findings: [], },
                    evidence_index: manifest,
                    limitations: [
                      "Profile mapping is explicit; unmapped input fields are not inferred.",
                      "Relations are temporal/resource hypotheses, not confirmed root causes.",
                    ],
                  }
                  println(@moonforensics.render_markdown_report(report))
                  println("## 关系图")
                  println("")
                  println("- profile: \{profile.id}@\{profile.version}")
                  println("- analysis pack: \{selected_pack}")
                  println("- canonical events: \{graph.nodes.length()}")
                  println("- relations: \{graph.edges.length()}")
                  println("- diagnostics: \{graph.diagnostics.length()}")
                  println("case finished (exit code 0)")
                  0
                }
              }
          }
        }
      }
    None => {
      println("case failed (exit code 3): empty input")
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
    "analyze" =>
      if args.length() >= 4 {
        let profile_id = args[3]
        let requested_pack = if args.length() >= 5 { args[4] } else { "" }
        profile_case(path, profile_id, requested_pack)
      } else {
        analyze(path)
      }
    "case" => {
      let profile_id = if args.length() >= 4 { args[3] } else { "flat-v1" }
      let requested_pack = if args.length() >= 5 { args[4] } else { "" }
      profile_case(path, profile_id, requested_pack)
    }
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
