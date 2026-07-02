# CBOM — Content Bill of Materials (self-memory)

## Role

CBOM is the **self-memory** layer of Project Intelligence. Every orchestration run emits a CBOM that records exactly what was orchestrated, on what inputs, with what hashes. Two runs over the same inputs (struct.json + macros + code at the same SHAs) must produce bit-identical CBOMs — this is the definition of reproducibility.

The CBOM ties the three orchestration sub-algorithms together:
- **Decompose** contributes the `intent_hash` + `plan_hash`.
- **Bound** contributes the per-leaf `slice_hash` and the `sources` table.
- **Gate** contributes the gate-decision hash and the intent-conformance verdict.

## Fields

```jsonc
{
  "schema_version": "1.0",
  "project": "simple_model",
  "generated_at": "<iso8601>",
  "intent_hash":  "sha256:<hex of canonical(struct.json)>",
  "plan_hash":    "sha256:<hex of canonical(plan JSON)>",
  "context_slices": [
    {
      "leaf_id": "Trainer",
      "slice_hash": "sha256:<hex of canonical(slice JSON)>",
      "tier": "core",
      "sources": ["<file>", "<file>", ...]
    },
    ...
  ],
  "code_hashes": {
    "<file path>": "sha256:<hex>",
    ...
  },
  "gate": {
    "decision": "PASS" | "FAIL",
    "exit_code": 0 | 16 | ...
  },
  "reproducible": true | false
}
```

## Canonicalization rule

Every hash is over **canonical JSON**:
- Object keys sorted lexicographically (jq `-S`).
- No insignificant whitespace (jq `-c`).
- Stable number formatting (jq defaults).
- No NaN / Infinity (jq rejects them).
- No duplicate keys (jq rejects them).
- Arrays preserve their declared order (we never reorder).

`jq -S -c . <file>` produces canonical JSON deterministically across runs and platforms. We hash the canonical JSON with `sha256sum` to get the hex digest prefixed `sha256:`.

## What gets hashed

| Field | What is hashed |
|-------|----------------|
| `intent_hash` | canonical(struct.json) — the input to Decompose |
| `plan_hash`   | canonical(plan JSON) — the output of Decompose |
| `slice_hash`  | canonical(slice JSON) — the output of Bound per leaf |
| `code_hashes[<file>]` | sha256 of the raw file bytes (not canonical JSON — code is text) |
| `gate.hash`   | canonical(gate decision JSON) |

## Reproducibility

A run is reproducible if and only if:
- `intent_hash` matches a previous run's `intent_hash`.
- `plan_hash` matches a previous run's `plan_hash`.
- All `slice_hash` match (per leaf).
- All `code_hashes` match.
- The `gate.decision` and `gate.exit_code` match.

CBOM drift detection: if any hash differs, the run is not bit-identical, and a `cbom diff <a.json> <b.json>` call lists the differing fields.

The `reproducible` flag is computed by CBOM emission itself: it's `true` iff all per-run hashes in the CBOM match the previous run's CBOM hashes (we read `.ai/cbom.prev.json` if present, else we just record `reproducible: null`).

## How CBOM ties to the three algorithms

```
struct.json
   │ intent_hash
   ▼
Decompose ──► plan.json (plan_hash)
                    │
                    ▼
                Bound ──► slices/<leaf>.json (slice_hash per leaf)
                              │
                              ▼
                          Gate ──► gate.json (gate decision)
                                       │
                                       ▼
                                   CBOM (everything above, content-addressed)
```

## Output location

`generated/.ai/cbom.json` — the canonical CBOM for the most recent run.

`generated/.ai/cbom.prev.json` — the previous run's CBOM (used for reproducibility check).

`generated/.ai/cbom.diff.json` — when two CBOMs differ, this is the symmetric diff.

## Where CBOM fits in Project Intelligence

CBOM is the **self_memory** layer — and the architectural realization of the **dumb tool + smart repo** inversion. Instead of asking the LLM (or a retrieval engine) to re-discover what the project intended at every run, the project keeps its own content-addressed memory of (intent, plan, slices, code, gate-decision) and consults it deterministically.

## Determinism

CBOM emission is pure: same inputs (struct, plan, slices, code, gate) → same hashes → same CBOM. The `generated_at` timestamp is the only timestamp; for reproducibility we hash everything *except* the timestamp, then include the timestamp as the final field. If you need bit-identical CBOMs across runs at different times, hash the CBOM-without-timestamp and use that as the cross-run identity.