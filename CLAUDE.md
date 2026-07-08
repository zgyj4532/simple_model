# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**simple_model** is a schema-driven project orchestrator — an "AI-era Maven" — written in pure bash + jq with **zero external dependencies**. A single `struct.json` describes a project's architecture (modules, components, dependencies, todos with blockers); `bootstrap.sh` and the `generators/*.sh` family turn it into code skeletons, AI context, drift/lint reports, and (as of v0.3) a fully deterministic **Project Intelligence** pipeline (intent predicates → wave-plan → per-leaf slices → pre-merge gate → content-addressed CBOM).

**The design thesis:** the bash+jq runtime *is* the algorithm. LLMs are leaf workers that may write code artifacts, but they never make structural decisions. Algorithms are LLM's strict father.

> **macOS gotcha:** `/bin/bash` is 3.2 and lacks associative arrays + `[[ ]]` features used throughout. Always use `/opt/homebrew/bin/bash` for any script invocation. Hardcoded paths in `bootstrap.sh:274` rely on this.

## Quick orientation (read first)

| File | Purpose | Lines |
|---|---|---|
| `README.md` | Human-facing project pitch + architecture diagram | 146 |
| `docs/AGENT_QUICKSTART.md` | 5-minute agent orientation; mental model + command table | 102 |
| `specs/intent-model.json` | Formal 6-predicate intent algebra (`select_one_of`, `optional`, `phase_membership`, `cross_cutting_injection`, `blocks`, `invariant`) | — |
| `docs/orchestration/{decompose,bound,gate,cbom}.md` | One doc per orchestration algorithm (the four inventive pillars) | — |
| `docs/ip/provisional-claim-architecture.md` | Patent claim architecture — 3 narrow-GO independent claims | 287 |
| `examples/dnc-demo/README.md` | End-to-end Project Intelligence run on a 6-component fixture | 74 |

For session start, the canonical sequence is `cat AGENTS.md` → `./bootstrap.sh --status` → `./bootstrap.sh --next`.

## Commands

All `./bootstrap.sh` commands accept `--json` for machine-readable output unless noted. Use `/opt/homebrew/bin/bash bootstrap.sh` on macOS.

### Validation / Generation

| Command | Purpose |
|---|---|
| `./bootstrap.sh --validate` | Schema + reference integrity (jq + optional ajv). Run first. |
| `./bootstrap.sh --plan --target all` | Dry-run; show what would be generated without writing. |
| `./bootstrap.sh --target python,rust,viz` | Run named generators (comma list; or `--target all`). |
| `./bootstrap.sh --target agents` | Emit `AGENTS.md` only (AI agent startup entry). |
| `./bootstrap.sh --drift` | Schema ↔ generated-output consistency. |
| `./bootstrap.sh --lint [--fix]` | Anti-pattern scan with optional auto-fix. |
| `./bootstrap.sh --fix` | Shorthand for lint --fix then drift --fix. |
| `./bootstrap.sh --check-imports` / `--check-impl` / `--check-all` | Reference-chain + impl-alignment checks. |
| `./bootstrap.sh --migrate 3.0 3.1 [--dry-run]` | Schema version migration. |

### AI Agent Workflow

| Command | Purpose |
|---|---|
| `./bootstrap.sh --status` | Progress dashboard (todo counts by status). |
| `./bootstrap.sh --next [--json]` | Highest-priority unblocked todo. |
| `./bootstrap.sh --claim <todo_id>` | Lock a todo as `in_progress` (atomic; audit trail). |
| `./bootstrap.sh --complete <todo_id>` | Mark done. |
| `./bootstrap.sh --reset <todo_id>` | Release a stuck claim. |
| `./bootstrap.sh --explain <component>` | Component context dump (saves tokens; `--explain-json` for raw). |

### Project Intelligence (v0.3)

| Command | Purpose |
|---|---|
| `./bootstrap.sh --orchestrate demo` | Run end-to-end on demo fixture (4-act story: prune → parallel → gate → reproduce). |
| `./bootstrap.sh --orchestrate demo --self-test` | Same chain on real `struct.json`. |
| `./bootstrap.sh --orchestrate demo --json` | Final summary as JSON. |
| `./bootstrap.sh --chimeric {init\|verify\|status\|plan}` | Chimeric verify / spec / adapter subcommands (legacy gate primitives). |

You can also invoke the four algorithms directly without `bootstrap.sh`:
```bash
bash generators/intent_validate.sh      struct.json        # 6-predicate soundness report
bash generators/orchestrate_decompose.sh struct.json        # → generated/.ai/plan.json
bash generators/orchestrate_bound.sh     plan.json struct.json # → generated/.ai/slices/<leaf>.json
bash generators/orchestrate_gate.sh      merged.json        # → generated/.ai/gate.json
bash generators/cbom_emit.sh                                # → generated/.ai/cbom.json
```

### Project Initialization

| Command | Purpose |
|---|---|
| `./bootstrap.sh --init --template <name>` | Scaffold from local template (`web_spa` / `backend_api` / `llm_agent`). |
| `./bootstrap.sh --init --from-url <url>` | Pull template from git/https/file URL. |
| `./bootstrap.sh --init --from <path>` | Pull template from local path. |

### Common Options

| Option | Default | Purpose |
|---|---|---|
| `-s, --struct <file>` | `./struct.json` | Override struct path. |
| `-S, --schema <file>` | `./struct.schema.json` | Override schema path. |
| `-o, --output <dir>` | `./generated` | Output root. |
| `--json` | off | Machine-readable output. |
| `--plan` | off | Dry-run (don't write). |
| `--force` | off | Ignore incremental cache; full rebuild. |
| `--include <modules>` | — | Whitelist modules (comma list). |
| `--exclude <modules>` | — | Blacklist modules. |
| `--no-validate` | off | Skip validation step. |

## Architecture

### Big-picture data flow

```
struct.json  (single source of truth)
    │
    ▼
bootstrap.sh  (CLI dispatch + dep checks + struct hash)
    │
    ├─→ generators/intent_validate.sh   ──→ soundness report (6 predicates)
    │       │
    │       ▼
    ├─→ generators/orchestrate_decompose.sh ──→ .ai/plan.json (wave-plan + soundness proof)
    │       │
    │       ▼
    ├─→ generators/orchestrate_bound.sh      ──→ .ai/slices/<leaf>.json (per-leaf context)
    │       │
    │       ▼
    ├─→ generators/orchestrate_gate.sh       ──→ .ai/gate.json (intent conformance + contract)
    │       │
    │       ▼
    ├─→ generators/cbom_emit.sh              ──→ .ai/cbom.json (5 sha256 hashes; bit-reproducible)
    │
    ├─→ generators/{python,rust,go,typescript}.sh ──→ generated/<lang>/<module>/<comp>.<ext>
    ├─→ generators/agents_md.sh              ──→ AGENTS.md
    ├─→ generators/context_json.sh           ──→ .ai/context.json
    ├─→ generators/dev_queue.sh              ──→ .ai/dev_queue.json (parallel waves)
    └─→ generators/visualization.sh          ──→ docs/ARCHITECTURE.md + architecture.html
```

### The three Project Intelligence algorithms

All three are **deterministic on their inputs** (same input → same output, no LLM, no randomness, no timestamps in the decision):

1. **Decompose** (`generators/orchestrate_decompose.sh`) — emits an intent-sound wave-plan. `select_one_of` prunes alternative implementations; `optional` excludes zero-leaves; `blocks` enforces topo order; `phase_membership` clusters into stages. See `docs/orchestration/decompose.md`.
2. **Bound** (`generators/orchestrate_bound.sh`) — emits one context slice per resolved leaf: self + direct deps + phase + visible invariants. Sized for LLM ingest. See `docs/orchestration/bound.md`.
3. **Gate** (`generators/orchestrate_gate.sh`) — pre-merge check: intent conformance (plan still sound after merges) + contract verification (chimeric verify-results). See `docs/orchestration/gate.md`.

### CBOM (self-memory)

`generated/.ai/cbom.json` is content-addressed with five `sha256` fields (`jq -S -c` canonical form):

| Field | Hashes |
|---|---|
| `intent_hash` | struct.json (the intent declarations) |
| `plan_hash` | plan.json (the wave-plan) |
| `slice_hash` | per-leaf slice projections |
| `code_hash` | generated code artifacts |
| `gate_hash` | gate verdict |

Two runs over identical inputs produce bit-identical CBOMs (modulo `generated_at`). See `docs/orchestration/cbom.md`.

### Repository layout (top-level)

```
simple_model/
├── bootstrap.sh                      # CLI orchestrator (~440 lines bash)
├── struct.schema.json                # universal schema (validated against `specs/*.json`)
├── struct.json                       # THIS project's architecture (15 modules / 91 components)
├── generators/                       # 28 pure-bash+jq generators (sourced via _lib.sh)
│   ├── _lib.sh                       # shared library: topo sort, animation library, helpers
│   ├── _templates.sh                 # template rendering (base64-encode values; multi-line fix)
│   ├── orchestrate_{decompose,bound,gate}.sh  # Project Intelligence trio
│   ├── intent_validate.sh            # 6-predicate soundness check
│   ├── cbom_emit.sh                  # content-addressed CBOM
│   ├── chimeric_{spec,adapter,verify}.sh      # chimeric verify primitives (reused by gate)
│   ├── agent.sh                      # status / next / claim / complete / reset
│   ├── check.sh / check_imports.sh / check_impl.sh  # drift + lint + alignment
│   ├── python.sh / rust.sh / go.sh / typescript.sh  # multi-language code gen
│   └── visualization.sh              # Mermaid + single-file HTML
├── specs/                            # 14 JSON Schema specs (intent-model, cbom-schema, lifecycle, …)
├── docs/
│   ├── AGENT_QUICKSTART.md           # 5-minute agent orientation
│   ├── CHANGELOG.md                  # v0.3 release notes
│   ├── orchestration/                # one .md per orchestration algorithm
│   └── ip/                           # patent prior-art + claim architecture + differentiation memo
├── examples/                         # 3 init templates (web_spa, backend_api, llm_agent)
│   └── dnc-demo/                     # end-to-end Project Intelligence demo fixture + run.sh
├── tests/                            # animation + chimeric + intent + decompose + cbom + dnc-demo
├── tools/install-hooks.sh            # git hook installer
└── todo.json                         # live task DAG (waves 1–7)
```

### Schema structure (`struct.json`)

- **modules**: business/technical boundaries; each has `name` (snake_case → directory) and `components[]`.
- **components**: implementable units; `name` is PascalCase. Carry `exports`, `imports`, `todos`.
- **todos**: implementation tasks with a blocker DAG (`blocks` / `blockedBy`) and lifecycle states (`pending` / `in_progress` / `done`).
- **phases**: optional execution stages (e.g., build pipeline stages) — drives `phase_membership` predicate.
- **cross_cutting**: optional cross-cutting concerns (logging, auth, cache) — drives `cross_cutting_injection`.
- **invariants**: optional `[{name, scope, quantifier, predicate, message}]` — the 6th intent predicate. Predicate is a jq pure-sub-language expression.

### Generator pattern

Every generator in `generators/*.sh` follows the same shape:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
LANG="mylang"
LANG_DIR="${OUTPUT_DIR}/${LANG}"
mkdir -p "$LANG_DIR"
# ... generation logic, reading struct.json via jq ...
```

Adding a new generator: drop a script in `generators/` matching that template, then invoke with `./bootstrap.sh --target mylang`. The new generator is automatically picked up by the dispatch loop in `bootstrap.sh` (see the case statement near line 350+ that maps targets → scripts).

## AI agent session pattern

```bash
# 1. Read the project entry point
cat AGENTS.md

# 2. Get the task queue
./bootstrap.sh --status

# 3. Pick the next todo and dump full context
TASK_ID=$(./bootstrap.sh --next --json | jq -r '.id')
./bootstrap.sh --explain "$TASK_ID" --json > /tmp/task-context.json
jq '.hints.files_to_read' /tmp/task-context.json

# 4. Lock and implement
./bootstrap.sh --claim "$TASK_ID"
# ... write code ...

# 5. Mark done; validate; check status
./bootstrap.sh --complete "$TASK_ID"
./bootstrap.sh --validate
./bootstrap.sh --status
```

## Testing

All tests are standalone bash scripts. Run individually or together:

```bash
# Single test
bash tests/test_chimeric_e2e.sh

# Full suite
for t in tests/test_*.sh; do bash "$t" || exit 1; done

# Animation regression (also covered by demo.sh)
bash tests/test_animations.sh
```

Current surface (as of v0.3) — **150 green assertions across 6 suites**:

| Test file | What it asserts |
|---|---|
| `tests/test_intent_validate.sh` | 6-predicate validator passes on real `struct.json`; fails correctly on per-predicate fixtures. |
| `tests/test_decompose_sound.sh` | Wave-plan is sound; `select_one_of` pruning is exact; checker catches violations. |
| `tests/test_cbom.sh` | CBOM is content-addressed; two runs produce bit-identical hashes; drift-detect finds divergence. |
| `tests/test_chimeric_e2e.sh` | Chimeric verify modes (contract / golden / invariants / round-trip) — Gate reuses these. |
| `tests/test_dnc_demo.sh` | End-to-end Project Intelligence demo (`examples/dnc-demo/run.sh`). |
| `tests/test_animations.sh` | Animation library regression (single-line overwrite; no `\033[2J`; color reset; TTY fallback). |

## Git integration

```bash
./tools/install-hooks.sh   # one-time install
```

After installation, every `git commit` runs: (1) `jq empty struct.json` (2) `--validate` (3) `--check-imports` (4) `--check-impl` (5) `--plan --target all` (dry-run).

**Repository convention:** commit schema and tools only; `generated/` is in `.gitignore`. AI agent worktrees (`wt-*/`, `.worktrees/`) are also ignored. The auto-fix backups `*.fix-backup-*` and `.state.tmp` are local-only. The `.gitignore` also excludes the working `CLAUDE.md` itself (intent: regenerate per session).

## Visualization

```bash
./bootstrap.sh --target viz
open generated/docs/architecture.html   # single-file, email-friendly
cat  generated/docs/ARCHITECTURE.md     # GitHub renders Mermaid natively
```

## Animation library

Located in `generators/_lib.sh`: 18 ASCII animation primitives for CLI feedback. All animations:
- Use only single-line overwrite (`\r`) or pure scrolling (`\n`)
- Reset colors with `\033[0m` at end of each frame
- Never use `\033[2J` (clear screen — Ghostty garbling)
- Support `NO_ANIM=1`, `TERM=dumb`, or non-TTY for fallback text

Run `bash demo.sh` for an interactive tour.