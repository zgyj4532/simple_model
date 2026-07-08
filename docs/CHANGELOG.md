# Changelog

All notable changes to simple_model's Project Intelligence layer are recorded
here. Versions follow semver-ish naming — major version bumps mark a thesis
milestone (e.g., v0.3 = "Project Intelligence core online"). Patches are
not used; we cut a new dated entry instead.

---

## v0.3 — 2026-07-02 — Project Intelligence core online

### Shipped

- **Intent predicate model** (6 predicates, JSON Schema, jq-evaluable,
  decidable). See `specs/intent-model.json` + `specs/intent-model.examples.json`.
- **Three deterministic orchestration algorithms**:
  - `generators/orchestrate_decompose.sh` — intent-sound wave-plan emission.
  - `generators/orchestrate_bound.sh` — intent-consistent context slicing.
  - `generators/orchestrate_gate.sh` — intent-conformance + contract merge gate.
  - See `docs/orchestration/{decompose,bound,gate}.md`.
- **CBOM self-memory** (`specs/cbom-schema.json` + `generators/cbom_emit.sh`).
  Content-addressed, canonical-form, bit-reproducible. See
  `docs/orchestration/cbom.md`.
- **Patent prior-art + claim architecture** in `docs/ip/`:
  - `docs/ip/patent-prior-art.md` — categorized prior art with go/narrow/no-go verdicts.
  - `docs/ip/differentiation-memo.md` — daylight analysis vs Conductor / ReSo / Praetorian / MetaGPT SOP.
  - `docs/ip/provisional-claim-architecture.md` — proposed claims, **NARROW GO on 3 independent claims** + 10 dependent claims (all GO).
- **150 green assertions across 6 suites** (`tests/test_intent_validate.sh` 16,
  `tests/test_decompose_sound.sh` 25, `tests/test_cbom.sh` 17,
  `tests/test_dnc_demo.sh` 43, `tests/test_chimeric_e2e.sh` 26,
  `tests/test_animations.sh` 23). **0 regression on chimeric_e2e**.

### Demonstrated

- `bash examples/dnc-demo/run.sh` — end-to-end on the demo fixture
  (prune → parallel → gate → reproduce four-act story).
- `bash examples/dnc-demo/run.sh --self-test` — end-to-end on real
  `struct.json` (intents validated, waves emitted, slices hashed, gate verdict).

### Roadmap Closure

- `dispatch_isolate` — worktree-isolated dispatch wrapper added.
- `summary_return` — bounded summary schema and collector added.
- `zero_dep_primitive` — dependency audit and cold-start benchmark added.
- `agent_agnostic_adapters` — Claude / Codex / Cursor / generic adapter shims added.
- `metrics_correctness` — quantitative orchestration smoke test added.
- `patent_draft` — provisional draft added for attorney review.

### Large Project Adoption

- `struct_multifile_resolve` — root `struct.json` now supports `includes`; bootstrap
  resolves fragments into `.bootstrap/resolved.struct.json` before validation and
  generation.
- `repo_ingest_adoption` — `./bootstrap.sh --ingest-repo <path>` emits a draft
  adoption model from existing source files.
- `adoption_audit` — `./bootstrap.sh --adoption-audit <path> --json` reports
  managed vs unmanaged source files and supports strict CI failure.
- `interface_scan` — `./bootstrap.sh --interface-scan <path> --json` extracts
  public symbols from Python, TypeScript/JavaScript, Go, and Rust, then compares
  them with component `exports` so half-built projects gain a real interface map.
- v0.4 roadmap closure: code facts, import graph scan, test surface scan,
  ownership resolution, interface/dependency drift gates, PR impact, work
  records, test selection, risk score, review routing, PR gate, GitHub Action
  template, read-only MCP wrapper, federation resolve, batch planning,
  architecture debt, and evolution harness.
- v0.5 hardening: strict fact contract, fact cache metrics, signature/hash
  interface facts, interface diff, route/env surface scan, JSON patch
  suggestions, waiver checks, executable test selection, PR Markdown comments,
  MCP initialize/tools flow, release contract reports, dashboard generation,
  large-repo benchmark smoke, and agent work-record harness.
- Test surface is now **228 assertions across 12 suites**.

See `todo.json` for live status.
