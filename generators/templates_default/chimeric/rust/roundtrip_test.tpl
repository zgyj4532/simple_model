//! Round-trip test stub for chimeric adapter {{bridge}}/{{ip_id}}.
//!
//! NOTE: ip_id='{{ip_id}}' may contain '-'; replace '-' -> '_' in the fn name
//! below (Rust identifiers cannot contain '-'). The generator should sanitize
//! it before substitution.
//! Auto-generated (v1); encode/decode are identity stubs so this passes.
//! TODO: use real encode/decode from the adapter module.

#[test]
fn {{ip_id}}_roundtrip() {
    fn encode(v: Value) -> Value { v } // TODO: real encode from adapter.
    fn decode(v: Value) -> Value { v } // TODO: real decode from adapter.

    // TODO: derive sample from type_map.
    let sample = serde_json::json!({"id": "1", "name": "example"});
    assert_eq!(encode(decode(sample.clone())), sample);
}
