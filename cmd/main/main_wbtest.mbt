///|
test "CLI profile catalog exposes explicit semantic profiles" {
  assert_true(cli_profile("flat-v1") is Some(_))
  assert_true(cli_profile("config-v1") is Some(_))
  assert_true(cli_profile("crash-v1") is Some(_))
  assert_true(cli_profile("health-v1") is Some(_))
  assert_true(cli_profile("latency-v1") is Some(_))
  assert_true(cli_profile("auto-v1") is Some(_))
  assert_true(cli_profile("missing-v1") is None)
}

///|
test "auto profile maps mixed records before running a config pack" {
  let source =
    #|{"profile":"config-v1","event_id":"cfg-1","timestamp":"2026-09-20T00:00:00Z","source":"config","resource":"orders","event_type":"config.update"}
    #|{"profile":"health-v1","event_id":"health-1","timestamp":"2026-09-20T00:00:30Z","source":"health","resource":"orders","event_type":"health.failed"}
  let records = try! @moonforensics.parse_jsonl(source)
  let events = try! map_auto_profile_records(records, @moonforensics.ProfileEvidence::{
    evidence_id: "cli-input",
    path: "<argument>",
    sha256: None,
  })
  let graph = try! profile_graph(events, "config")
  assert_eq(events.length(), 2)
  assert_eq(events[0].provenance.profile_id, "config-v1")
  assert_eq(events[1].provenance.profile_id, "health-v1")
  assert_eq(graph.edges.length(), 1)
  assert_eq(graph.edges[0].rule_id, Some("config-change-then-health-failure"))
}
