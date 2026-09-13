///|
/// Evidence content and provenance supplied when building a manifest.
pub(all) struct EvidenceDocument {
  id : String
  path : String
  source : EvidenceSource
  content : Bytes
} derive(Debug, Eq)

///|
/// A manifest entry binds evidence identity and source to its size and SHA-256 digest.
pub(all) struct EvidenceManifestEntry {
  id : String
  path : String
  source_id : String
  size_bytes : Int
  sha256 : String
} derive(Debug, Eq, ToJson)

///|
/// A deterministic manifest for a collection of evidence documents.
pub(all) struct EvidenceManifest {
  entries : Array[EvidenceManifestEntry]
} derive(Debug, Eq, ToJson)

///|
fn rotate_right(value : UInt, shift : Int) -> UInt {
  (value >> shift) | (value << (32 - shift))
}

///|
fn sha256(content : Bytes) -> String {
  let padded : Array[Byte] = []
  for byte in content {
    padded.push(byte)
  }
  padded.push(0x80)
  for index = padded.length(); index % 64 != 56; {
    padded.push(0)
    continue index + 1
  }

  let byte_length = content.length().reinterpret_as_uint()
  let bit_length_high = byte_length >> 29
  let bit_length_low = byte_length << 3
  for shift in [24, 16, 8, 0] {
    padded.push((bit_length_high >> shift).to_byte())
  }
  for shift in [24, 16, 8, 0] {
    padded.push(((bit_length_low >> shift) & 0xffU).to_byte())
  }

  let constants : Array[UInt] = [
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U,
    0x923f82a4U, 0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
    0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U,
    0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U,
    0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
    0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
    0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU,
    0x5b9cca4fU, 0x682e6ff3U, 0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
  ]
  let state : Array[UInt] = [
    0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU,
    0x1f83d9abU, 0x5be0cd19U,
  ]

  for block_start = 0; block_start < padded.length(); {
    let words : Array[UInt] = []
    for index = 0; index < 16; {
      let offset = block_start + index * 4
      words.push(
        (padded[offset].to_uint() << 24) |
        (padded[offset + 1].to_uint() << 16) |
        (padded[offset + 2].to_uint() << 8) |
        padded[offset + 3].to_uint(),
      )
      continue index + 1
    }
    for index = 16; index < 64; {
      let x = words[index - 15]
      let y = words[index - 2]
      let sigma0 = rotate_right(x, 7) ^ rotate_right(x, 18) ^ (x >> 3)
      let sigma1 = rotate_right(y, 17) ^ rotate_right(y, 19) ^ (y >> 10)
      words.push(words[index - 16] + sigma0 + words[index - 7] + sigma1)
      continue index + 1
    }

    let mut a = state[0]
    let mut b = state[1]
    let mut c = state[2]
    let mut d = state[3]
    let mut e = state[4]
    let mut f = state[5]
    let mut g = state[6]
    let mut h = state[7]
    for index = 0; index < 64; {
      let sum1 = rotate_right(e, 6) ^ rotate_right(e, 11) ^ rotate_right(e, 25)
      let choose = (e & f) ^ ((e ^ 0xffffffffU) & g)
      let temp1 = h + sum1 + choose + constants[index] + words[index]
      let sum0 = rotate_right(a, 2) ^ rotate_right(a, 13) ^ rotate_right(a, 22)
      let majority = (a & b) ^ (a & c) ^ (b & c)
      let temp2 = sum0 + majority
      h = g
      g = f
      f = e
      e = d + temp1
      d = c
      c = b
      b = a
      a = temp1 + temp2
      continue index + 1
    }
    state[0] = state[0] + a
    state[1] = state[1] + b
    state[2] = state[2] + c
    state[3] = state[3] + d
    state[4] = state[4] + e
    state[5] = state[5] + f
    state[6] = state[6] + g
    state[7] = state[7] + h
    continue block_start + 64
  }

  let digest_bytes : Array[Byte] = []
  for word in state {
    digest_bytes.push((word >> 24).to_byte())
    digest_bytes.push(((word >> 16) & 0xffU).to_byte())
    digest_bytes.push(((word >> 8) & 0xffU).to_byte())
    digest_bytes.push((word & 0xffU).to_byte())
  }
  let hex = "0123456789abcdef"
  let mut output = ""
  for byte in digest_bytes {
    let value = byte.to_uint()
    let high = (value >> 4).reinterpret_as_int()
    let low = (value & 0xfU).reinterpret_as_int()
    output = output +
      hex[high:high + 1].to_owned() +
      hex[low:low + 1].to_owned()
  }
  output
}

///|
fn manifest_entry(document : EvidenceDocument) -> EvidenceManifestEntry {
  {
    id: document.id,
    path: document.path,
    source_id: normalize_source_id(
      document.source.system,
      document.source.component,
      document.source.host,
    ),
    size_bytes: document.content.length(),
    sha256: sha256(document.content),
  }
}

///|
/// Builds ordered evidence metadata and SHA-256 content digests.
///
/// # Example
/// ```mbt check
/// test {
///   let source = EvidenceSource::{
///     system: "host",
///     component: "service",
///     host: None,
///   }
///   let document = EvidenceDocument::{
///     id: "e-1",
///     path: "service.log",
///     source,
///     content: b"abc",
///   }
///   let manifest = build_evidence_manifest([document])
///   assert_eq(manifest.entries[0].size_bytes, 3)
/// }
/// ```
pub fn build_evidence_manifest(
  documents : Array[EvidenceDocument],
) -> EvidenceManifest {
  let entries : Array[EvidenceManifestEntry] = []
  for document in documents {
    entries.push(manifest_entry(document))
  }
  { entries, }
}

///|
/// Checks evidence identity, source, path, byte size, and digest against a manifest.
///
/// # Example
/// ```mbt check
/// test {
///   let source = EvidenceSource::{
///     system: "host",
///     component: "service",
///     host: None,
///   }
///   let document = EvidenceDocument::{
///     id: "e-1",
///     path: "service.log",
///     source,
///     content: b"abc",
///   }
///   let manifest = build_evidence_manifest([document])
///   let changed = EvidenceDocument::{
///     id: "e-1",
///     path: "service.log",
///     source,
///     content: b"abd",
///   }
///   assert_false(verify_evidence_manifest(manifest, [changed]))
/// }
/// ```
pub fn verify_evidence_manifest(
  manifest : EvidenceManifest,
  documents : Array[EvidenceDocument],
) -> Bool {
  if manifest.entries.length() != documents.length() {
    return false
  }
  for index in 0..<documents.length() {
    if manifest.entries[index] != manifest_entry(documents[index]) {
      return false
    }
  }
  true
}
