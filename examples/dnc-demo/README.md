# Project Intelligence — End-to-End Demo

## What this is

A self-contained runnable demonstration of the Wave 2–5 orchestration core
(decompose → bound → gate → CBOM). Bundles a tiny 6-component fixture that
exercises every intent predicate, plus a one-script driver that runs the
chain twice and asserts byte-identical CBOMs.

## What it proves

1. **Soundness.** The plan satisfies all six intent predicates:
   `select_one_of`, `optional`, `phase_membership`,
   `cross_cutting_injection`, `blocks`, and one user-declared `invariant`.
2. **Per-leaf context slices.** Each resolved component receives a
   principled-minimum projection (self + direct deps + phase + visible
   invariants) — small enough for an LLM agent to ingest.
3. **Gate verdict.** Intent conformance passes; contract verification is
   safely skipped in demo mode (no chimeric verify-results.json).
4. **Content-addressed CBOM.** Every field is `sha256` over canonical JSON
   (`jq -S -c`), so two runs with the same inputs produce the same hashes.
5. **Reproducibility.** A second invocation of the chain yields a CBOM
   that is byte-identical aside from the `generated_at` timestamp.

## How to run

```bash
bash examples/dnc-demo/run.sh             # demo fixture (6 components, 2 waves)
bash examples/dnc-demo/run.sh --json      # final summary as JSON
bash examples/dnc-demo/run.sh --self-test # prove it works on real repo struct.json

# Or via the bootstrap dispatch:
./bootstrap.sh --orchestrate demo
./bootstrap.sh --orchestrate demo --json
./bootstrap.sh --orchestrate demo --self-test
```

## How to read the output

| Printed line                              | Source algorithm         |
|-------------------------------------------|--------------------------|
| `plan summary` / `waves (ascii)`          | `orchestrate_decompose.sh` (longest-path layering over import DAG) |
| `predicates: [OK] select_one_of ...`      | `intent_validate.sh` soundness check (6 predicates) |
| `context slices: LogWriter ...`           | `orchestrate_bound.sh` (one slice per resolved component) |
| `reproducibility: ... MATCH`              | `cbom_emit.sh` (content-addressed manifest) |
| `Project Intelligence: online` banner     | Aggregated final summary |

## Where it lives in the architecture

```
struct.json ───► orchestrate_decompose.sh ───► .ai/plan.json   (waves + soundness)
                          │
                          ▼
                  orchestrate_bound.sh ───► .ai/slices/<leaf>.json   (per-leaf projection)
                          │
                          ▼
                  orchestrate_gate.sh ───► .ai/gate.json     (intent conformance verdict)
                          │
                          ▼
                  cbom_emit.sh ──────► .ai/cbom.json     (content-addressed manifest)
```

## Extending it

- **Add a predicate.** The demo fixture is `struct.json`; add a phase or
  cross-cutting entry, then re-run.
- **Add an invariant.** Edit `invariants.json` (array of
  `{name, scope, quantifier, predicate, message}`). The predicate is a
  jq pure-sub-language expression evaluated against each resolved component.
- **Add a slice consumer.** Slice files are deterministic JSON written by
  `orchestrate_bound.sh`; the CBOM embeds their `sha256` so a new consumer
  can verify them by recomputing the hash.
- **Wire it into bootstrap.sh.** The chain is just four bash scripts in
  `generators/`; call them sequentially (see `run.sh` for the exact
  invocation order and flags).