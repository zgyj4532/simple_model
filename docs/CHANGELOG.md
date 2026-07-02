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

### Next (W4-W7)

- `dispatch_isolate` (Wave 4) — worktree-isolated parallel leaf dispatch.
- `summary_return` (Wave 4) — bounded-token leaf → orchestrator summary.
- `zero_dep_primitive` (Wave 4) — formal dep audit + cold-start benchmark.
- `agent_agnostic_adapters` (Wave 4) — Claude / Codex / Cursor / generic leaf adapters.
- `metrics_correctness` (Wave 6) — quantitative soundness / reproducibility / speedup.
- `patent_draft` (Wave 6) — full provisional draft (the architecture memo is the input).
- `docs_claudemd` (Wave 7) — final onboarding polish + AGENTS.md generation.

See `todo.json` for live status.
