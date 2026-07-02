/**
 * Round-trip test stub for chimeric adapter {{bridge}}/{{ip_id}}.
 *
 * Meant for jest/vitest — wrap runRoundtrip() in `it("{{ip_id}} roundtrip", ...)`
 * when a test runner is configured. Auto-generated (v1); encode/decode are
 * identity stubs so this passes when executed. TODO: import real encode/decode
 * from the adapter.
 */

// Stub encode/decode — identity for v1.
function encode<T>(v: T): T {
  return v; // TODO: real encode from adapter.
}
function decode<T>(v: T): T {
  return v; // TODO: real decode from adapter.
}

function runRoundtrip(): void {
  // TODO: derive sample from type_map.
  const sample: Record<string, unknown> = { id: "1", name: "example" };
  const result = encode(decode(sample));
  if (JSON.stringify(result) !== JSON.stringify(sample)) {
    throw new Error(
      `roundtrip mismatch: got ${JSON.stringify(result)}, want ${JSON.stringify(sample)}`,
    );
  }
  console.log("[ok] {{ip_id}} roundtrip passed");
}

runRoundtrip();
