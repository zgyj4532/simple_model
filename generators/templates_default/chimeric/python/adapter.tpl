"""Chimeric adapter: bridge={{bridge}} ip={{ip_id}}

Peer: {{peer_name}} {{ip_method}} {{ip_path}}
Owns export: {{self_export}} (module={{self_module}}, component={{self_component}})

Field mapping (reference):
{{field_mappings_json}}

Type map (reference):
{{type_map_json}}

Invariants (reference): {{invariant_names_json}}
Golden fixture: {{golden_response_path}}

Auto-generated stub (v1). Implement {{self_export}}() below to call the peer
endpoint and apply the field mapping above. Enforce listed invariants.
"""

# TODO: implement {{self_export}}() — call peer {{ip_method}} {{ip_path}},
# apply field_mapping to translate request/response, enforce invariants.
def {{self_export}}(payload):
    """Adapter stub for {{ip_id}} ({{ip_method}} {{ip_path}})."""
    raise NotImplementedError(
        "{{self_export}}() not implemented — chimeric adapter stub"
    )
