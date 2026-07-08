# Agent Quickstart — Project Intelligence

A 5-minute orientation for any AI agent picking up simple_model cold. Read
top to bottom; if you only have 60 seconds, read "The mental model" + "The
commands".

## 1. Read first

Read these four files in order. Each one removes a different source of confusion.

1. **CLAUDE.md** — the project's own self-description (commands, architecture,
   schema, AI agent workflow). This is the universal map; everything else is detail.
2. **specs/intent-model.json** — the formal predicate algebra. Six predicates
   (`select_one_of`, `optional`, `phase_membership`, `cross_cutting_injection`,
   `blocks`, `invariant`) with per-predicate satisfaction + decidability
   arguments. If you ever wonder "what counts as intent?", this file is the answer.
3. **docs/orchestration/decompose.md** — the first of the three deterministic
   orchestration sub-algorithms. It defines the wave-plan output format and the
   soundness argument by which every later artifact is judged.
4. **examples/dnc-demo/README.md** — the end-to-end demo on a fixture
   (and `--self-test` on real `struct.json`). Shows the four-act story
   (prune → parallel → gate → reproduce) without requiring you to read code.

## 2. The mental model

- **schema is source of truth.** `struct.json` describes the entire project.
  Generated code, AI context, and docs all derive from it; the schema is the only
  thing that survives a cold restart.
- **intent predicates are scheduling primitives.** The six predicates in
  `specs/intent-model.json` are not metadata — they prune the wave-plan. If a
  predicate can decide, the algorithm decides; LLM never guesses intent.
- **the bash+jq runtime is the algorithm.** The orchestrator is a small set of
  bash + jq scripts, not a Python service. Determinism is the first-class
  property; LLM leaves are invokable but never make structural decisions.
- **decompose / bound / gate are the three algorithms.** They are
  *deterministic*: same input → same output, no LLM, no randomness, no
  timestamps in the decision. Soundness is provable per wave.
- **CBOM is the memory.** Every orchestration run emits a Content Bill of
  Materials (`generated/.ai/cbom.json`) with five hash fields
  (`intent_hash`, `plan_hash`, `slice_hash`, `code_hash`, `gate_hash`). Two runs
  over identical inputs produce bit-identical CBOMs.
- **LLM is the leaf worker.** LLMs are invoked only at leaf tasks to generate
  code artifacts; they never make structural decisions. This is the
  "Algorithm is LLM's strict father" principle — algorithms are the
  disciplinarian, not LLM prompts.

## 3. The commands

All commands assume CWD = repo root. Use `/opt/homebrew/bin/bash` for any
script (macOS `/bin/bash` is 3.2 and lacks needed features).

| Command | Purpose |
|---|---|
| `./bootstrap.sh --validate` | Schema + reference integrity validation. Run first. |
| `./bootstrap.sh --target all` | Regenerate safe no-argument outputs: agent docs, context, queue, viz, and four language skeletons. |
| `./bootstrap.sh --target queue` | Emit `.ai/dev_queue.md` (parallel waves for human / agent consumption). |
| `./bootstrap.sh --claim <todo_id>` | Mark a todo as `in_progress` (atomic lock + audit trail). |
| `./bootstrap.sh --complete <todo_id>` | Mark a todo as `done`. |
| `./bootstrap.sh --status` | Project progress dashboard. |
| `bash generators/intent_validate.sh struct.json` | Run the 6-predicate intent validator; emits soundness report. |
| `bash generators/orchestrate_decompose.sh struct.json` | Emit intent-sound wave-plan to `generated/.ai/plan.json`. |
| `bash generators/orchestrate_bound.sh plan.json struct.json` | Emit per-leaf context slices to `generated/.ai/slices/`. |
| `bash generators/orchestrate_gate.sh merged.json` | Run intent-conformance + contract gate before merge. |
| `bash generators/cbom_emit.sh` | Emit CBOM (`generated/.ai/cbom.json`) and drift-detect against `cbom.prev.json`. |
| `bash examples/dnc-demo/run.sh` | Run Project Intelligence end-to-end on demo fixture. |
| `bash examples/dnc-demo/run.sh --self-test` | Run Project Intelligence end-to-end on real `struct.json`. |

There are two todo surfaces. `todo.json` is the product/roadmap backlog for
the orchestrator itself. `struct.json` component todos are the generated project
work queue consumed by `--status`, `--next`, `--claim`, and `--complete`.

## 4. The test surface

All tests use `/opt/homebrew/bin/bash`. Each is standalone; run individually
or together via `for t in tests/test_*.sh; do bash "$t" || exit 1; done`.

| Test file | Assertions | What it proves |
|---|---|---|
| `tests/test_intent_validate.sh` | 16 | The 6-predicate validator passes on real `struct.json` and fails correctly on fixtures with each predicate violated. |
| `tests/test_decompose_sound.sh` | 25 | Decompose produces sound wave-plans; `select_one_of` pruning is exact; checker is a sound safety net. |
| `tests/test_cbom.sh` | 17 | CBOM is content-addressed; two runs over identical inputs produce bit-identical CBOMs; drift-detect finds divergence. |
| `tests/test_dnc_demo.sh` | 43 | End-to-end Project Intelligence demo (`examples/dnc-demo/run.sh`): sound plan → slices → gate → CBOM, on both the demo fixture and `--self-test`. |
| `tests/test_orchestration_e2e.sh` | 10 | Quantitative orchestration smoke test: soundness, gate, CBOM, dispatch plan, summary collection, depcheck, cold-start benchmark. |
| `tests/test_chimeric_e2e.sh` | 26 | The chimeric verify modes (contract/golden/invariants/round-trip) still pass — Gate reuses these. Zero regression. |
| `tests/test_animations.sh` | 23 | Animation library regression: single-line overwrite, no `\033[2J`, color reset, TTY fallback. |

Total: **160 green assertions** across 7 suites as of v0.3.

## 5. Shipped roadmap surface

The v0.3 roadmap items in `todo.json` are implemented. Use these entry points:

- `./bootstrap.sh --target dispatch --plan` — worktree-isolated dispatch plan.
- `bash generators/orchestrate_collect.sh` — bounded leaf summary collector.
- `bash tools/depcheck.sh --json` — dependency audit.
- `bash tests/bench_coldstart.sh --json` — cold-start benchmark.
- `bash tests/test_orchestration_e2e.sh` — quantitative orchestration smoke test.
- `docs/ip/provisional-draft.md` — provisional patent draft for attorney review.
