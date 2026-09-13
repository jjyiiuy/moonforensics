///|
test "evidence manifest includes known SHA-256 digest, size, and source" {
  let documents = [
    @moonforensics.EvidenceDocument::{
      id: "evidence-1",
      path: "logs/app.log",
      source: @moonforensics.EvidenceSource::{
        system: " checkout ",
        component: " api ",
        host: Some(" node-1 "),
      },
      content: b"abc",
    },
  ]
  let manifest = @moonforensics.build_evidence_manifest(documents)
  let entry = manifest.entries[0]

  assert_eq(entry.id, "evidence-1")
  assert_eq(entry.path, "logs/app.log")
  assert_eq(entry.source_id, "checkout/api/node-1")
  assert_eq(entry.size_bytes, 3)
  assert_eq(
    entry.sha256,
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "evidence manifest validates unchanged content and rejects modifications" {
  let source = @moonforensics.EvidenceSource::{
    system: "platform",
    component: "journal",
    host: None,
  }
  let original = @moonforensics.EvidenceDocument::{
    id: "evidence-2",
    path: "system.log",
    source,
    content: b"original evidence",
  }
  let manifest = @moonforensics.build_evidence_manifest([original])

  assert_true(@moonforensics.verify_evidence_manifest(manifest, [original]))
  let modified = @moonforensics.EvidenceDocument::{
    id: "evidence-2",
    path: "system.log",
    source,
    content: b"modified evidence",
  }
  assert_false(@moonforensics.verify_evidence_manifest(manifest, [modified]))
}

///|
test "evidence manifest verifies empty content and rejects missing evidence" {
  let source = @moonforensics.EvidenceSource::{
    system: "platform",
    component: "journal",
    host: None,
  }
  let document = @moonforensics.EvidenceDocument::{
    id: "empty",
    path: "empty.log",
    source,
    content: b"",
  }
  let manifest = @moonforensics.build_evidence_manifest([document])

  assert_eq(
    manifest.entries[0].sha256,
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_true(@moonforensics.verify_evidence_manifest(manifest, [document]))
  assert_false(@moonforensics.verify_evidence_manifest(manifest, []))
}

///|
test "SHA-256 handles content that requires a second padded block" {
  let source = @moonforensics.EvidenceSource::{
    system: "test",
    component: "vectors",
    host: None,
  }
  let document = @moonforensics.EvidenceDocument::{
    id: "nist-vector",
    path: "vector.txt",
    source,
    content: b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
  }
  let manifest = @moonforensics.build_evidence_manifest([document])

  assert_eq(manifest.entries[0].size_bytes, 56)
  assert_eq(
    manifest.entries[0].sha256,
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
}
