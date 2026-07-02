"""Round-trip test stub for chimeric adapter {{bridge}}/{{ip_id}}.

NOTE: ip_id='{{ip_id}}' may contain '-'; pytest forbids '-' in test names.
The generator should sanitize it (replace '-' -> '_') before substitution.
Auto-generated (v1); encode/decode below are identity stubs so this passes.
TODO: import real encode/decode from the adapter.
"""


def encode(obj):
    # TODO: real encode from adapter (applies field_mapping request side).
    return obj


def decode(obj):
    # TODO: real decode from adapter (applies field_mapping response side).
    return obj


def test_{{ip_id}}_roundtrip():
    """Round-trip identity: encode(decode(sample)) deeply equals sample."""
    sample = {"id": "1", "name": "example"}  # TODO: derive from type_map
    assert encode(decode(sample)) == sample
