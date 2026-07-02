# Gate (intent-conformance + contract merge gate)

## Role

Gate is the third deterministic sub-algorithm. Before a merge is accepted, Gate runs two deterministic checks on the merge candidate:

1. **Intent conformance**: every user-declared invariant holds on the merged artifact (struct.json after the candidate is applied).
2. **Contract verification**: the chimeric verify modes (contract, golden, invariants, round_trip) all pass — extended to also cover intent conformance.

Gate is the **chimeric generalization**: the chimeric_verify.sh modes were a special case of Gate for cross-bridge field-mapping; Gate is the universal merge gate over the whole intent model.

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| Merged struct | `struct.json` | yes (post-merge state) |
| Original struct (before merge) | `--base struct.base.json` | no (for diff) |
| Invariant file | `--invariants invariants.json` | no |
| Contract outputs | chimeric `verify-results.json` | no |

## Output

```jsonc
{
  "schema_version": "1.0",
  "decision": "PASS" | "FAIL",
  "gate_id": "merge-gate-<timestamp>",
  "checks": {
    "intent_conformance": {
      "ok": true|false,
      "violations": [{ "predicate": "...", "location": "...", "message": "..." }, ...]
    },
    "contracts": {
      "ok": true|false,
      "modes": {
        "contract":     { "ok": true, "results": [...] },
        "golden":       { "ok": true, "results": [...] },
        "invariants":   { "ok": true, "results": [...] },
        "round_trip":   { "ok": true, "results": [...] }
      }
    }
  },
  "exit_code": 0 | 11..15
}
```

## Exit codes (extended chimeric semantics)

Reuses and extends the chimeric_verify semantics:

| Code | Meaning |
|------|---------|
| 0    | All gates passed (or skipped). |
| 11   | Contract mode failed. |
| 12   | Round-trip mode failed. |
| 13   | Golden mode failed. |
| 14   | Invariant (chimeric) failed. |
| 15   | Multi-mode failed (>= 2 modes failed). |
| 16   | Intent conformance failed (this is the new Gate-level invariant). |
| 17   | Intent conformance failed AND another mode failed (composite). |

## Algorithm

The gate is a thin orchestrator over two subprocesses (`intent_validate.sh`
and `chimeric_verify.sh`), wrapped with exit-code composition and gate.json
emission. There is no in-process intent-plan computation — `gate.sh` always
delegates.

```
INPUT:  merged struct M, optional base B, invariants I, optional chimeric verify-results R
OUTPUT: gate result G (written to generated/.ai/gate.json)

# Step 1: delegate intent-conformance check to the intent_validate subprocess.
set +e
bash generators/intent_validate.sh \
    --struct M \
    [--invariants I] \
    --json > /tmp/intent_report.json
INV_RC=$?
set -e
# Subprocess exits 0 (all 6 predicates pass) or 1 (any predicate failed).
intent_ok = (INV_RC == 0)
intent_violations = jq '.predicates | to_entries
                          | map(select(.value.ok == false))
                          | map({predicate:.key, ok:false, violations:.value.violations})' \
                        /tmp/intent_report.json

# Step 2: if a chimeric verify-results R is supplied, validate R's per-mode status.
if R is provided:
  modes_status = jq '.results[].modes | { contract, round_trip, golden, invariants }' R
  contract_fail_count = modes_status | map(select(.status == "fail")) | length
  contract_ok = (contract_fail_count == 0)
  # Each failing mode contributes its exit code (11/12/13/14).
  # Two or more failures → composite code 15.

# Step 3: decide exit code (precedence):
#   - intent_fail AND contract_fail → 17
#   - multi-mode contract_fail       → 15
#   - single contract mode fail     → 11 | 12 | 13 | 14
#   - intent_fail only              → 16
#   - else                          → 0
exit_code = compose(intent_ok, contract_ok, modes_status)
decision  = (exit_code == 0) ? "PASS" : "FAIL"

# Step 4: emit .ai/gate.json with all checks, gate_id (sha256), and timestamp.
gate_id = sha256(canonical_json(M) [+ canonical_json(I) if I present])
write .ai/gate.json
```

**Subprocess delegation note.** The gate calls `intent_validate.sh` as a
subprocess and parses its `--json` report; it does **not** forward the
gate's own candidate plan back into `intent_validate --plan`. Forwarding
`--plan` would require a protocol design (which struct fields the gate may
rewrite between intent-conformance calls), so the gate currently treats
`intent_validate` as a pure validator over the merged struct, not as a
plan-verifier. This is documented as a future work item in todo.json
(W6 todos).

## Determinism

The Gate is purely a function of the merged struct + invariants + chimeric results. No LLM, no randomness, no timestamps in the decision. The `gate_id` is derived from `sha256(canonical_json(merged_struct + invariants))` for reproducibility. This is the runtime instantiation of the **dumb tool + smart repo** inversion: Gate checks the merged artifact against the declared intent encoded in the project model itself.

## Where Gate fits in Project Intelligence

Gate is the final guard of the orchestration pipeline. It enforces the **Algorithm is LLM's strict father** principle: the LLM produces code artifacts, and Gate decides whether they are accepted into the project. The decision is purely a function of the merged struct + invariants; the LLM never arbitrates.

## Where Gate differs from intent_validate

- `intent_validate` is **static**: it checks the declared intent model is self-consistent.
- `Gate` is **dynamic**: it checks the merged artifact (post-merge state) still satisfies the intent. The merged artifact may include new components / new phase membership, and Gate must re-derive soundness against the new state.

For the skeleton, Gate delegates to `intent_validate`'s resolver on the merged struct — so the two share the soundness-checker code path. A future extension is to make Gate aware of the merge diff (what was added/removed) and re-check only invariants whose scope intersects the diff (incremental Gate).