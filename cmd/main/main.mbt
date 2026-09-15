///|
suberror CliError {
  Usage
  Input
  Verification
} derive(Debug)

///|
fn usage() -> Unit {
  println("MoonForensics CLI")
  println("Usage:")
  println("  moon run cmd/main -- ingest <jsonl-source>")
  println("  moon run cmd/main -- analyze <jsonl-source>")
  println("  moon run cmd/main -- verify <evidence-source>")
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
          println("# Analysis")
          println("")
          println("- records: \{records.length()}")
          println(
            "- limitations: input records are observations; no root cause is inferred",
          )
          println("analyze finished (exit code 0)")
          0
        }
      }
    None => {
      println("analyze failed (exit code 3): empty input")
      3
    }
  }
}

///|
fn verify(source : String) -> Int {
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
      println(
        "verify ok (exit code 0): \{manifest.entries[0].size_bytes} bytes, sha256=\{manifest.entries[0].sha256}",
      )
      0
    }
    None => {
      println("verify failed (exit code 4): empty input")
      4
    }
  }
}

///|
fn main raise CliError {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    raise CliError::Usage
  }
  let command = args[1]
  if command == "--help" || command == "-h" {
    usage()
    return
  }
  if args.length() < 3 {
    usage()
    raise CliError::Usage
  }
  let path = args[2]
  let exit_code = match command {
    "ingest" => ingest(path)
    "analyze" => analyze(path)
    "verify" => verify(path)
    _ => {
      println("unknown command (exit code 2): \{command}")
      usage()
      2
    }
  }
  if exit_code != 0 {
    match exit_code {
      2 => raise CliError::Usage
      3 => raise CliError::Input
      _ => raise CliError::Verification
    }
  }
}
