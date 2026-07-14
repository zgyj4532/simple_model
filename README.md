# simple_model — AI-era Maven

**simple_model** is a schema-driven project orchestrator written in pure bash + jq
with zero external dependencies. A single `struct.json` describes a project's
architecture (modules, components, dependencies, todos with blockers); `bootstrap.sh`
turns it into code, documentation, AI context, and parallel work assignments.
Designed for AI agents first, humans second — but the bash+jq runtime is the
algorithm, and LLMs are leaf workers. **Algorithm is LLM's strict father.** This is
the **dumb tool + smart repo** inversion: the bash+jq runtime is the algorithm, the
project remembers its own architecture, and the LLM never decides structure.

---

## What you get

Project Intelligence has three layers; simple_model ships them all:

- **self_model** = `struct.json` + the six intent predicates in
  `specs/intent-model.json` — declarative knowledge of the project's own
  architecture, non-derivable from source code, build manifests, or runtime traces.
- **self_cognition** = the three deterministic orchestrators — `decompose` (wave-plan),
  `bound` (per-leaf context slice), `gate` (pre-merge intent conformance + contract).
  Pure bash + jq; no LLM in the loop.
- **self_memory** = the **CBOM** (`generated/.ai/cbom.json`) — a content-addressed
  Context Bill of Materials with five hash fields (intent / plan / slice / code /
  gate). Same inputs → bit-identical CBOM without re-running any LLM.

Plus: multi-language code generation (Python / Rust / Go / TypeScript), parallel
wave-based task queue, AI-agent lifecycle (`--next` / `--claim` / `--complete` /
`--explain`), drift detection (`--drift`), anti-pattern lint (`--lint [--fix]`),
multi-file struct resolution (`--resolve`), repo adoption audit, and a single-file
HTML visualization of the architecture (`--target viz`). Existing projects can
also be interface-scanned so discovered public symbols stay aligned with
component `exports`. The Codex plugin also includes a deterministic macro
optimizer that can plan, dry-run, apply, and report architecture improvements for
other half-built repositories without asking an LLM to make structural decisions.

---

## Quickstart

```bash
# 1. Validate the schema + reference integrity
./bootstrap.sh --validate

# 2. Run the end-to-end Project Intelligence demo on the fixture
bash examples/dnc-demo/run.sh

# 3. Inspect the live project status dashboard
./bootstrap.sh --status

# 4. Regenerate all safe no-argument outputs
./bootstrap.sh --target all

# 5. Run the v2 regression suite
for t in tests/test_v20_*.sh; do bash "$t" || exit 1; done

# 6. Run the complete legacy + v2 suite (some repository-scale checks are slower)
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Need bash ≥ 4 (macOS users: `/opt/homebrew/bin/bash`). Pre-existing `struct.json`
describes a 15-module / 90-component ML training platform; `--validate` confirms
it is well-formed before anything else runs.

### Codex Skill And Plugin

This repo ships a Codex skill at
`codex/skills/simple-model-project-intelligence/`. It gives Codex a compact
operational guide plus a wrapper for the Project Intelligence commands:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh validate
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh ingest /path/to/big-repo
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh pr-gate /path/to/big-repo
```

It also ships a local Codex plugin at
`plugins/simple-model-project-intelligence/`, with the same skill bundled under
the plugin's `skills/` directory for plugin-based installation flows.
See `docs/CODEX_PLUGIN.md` for update, packaging, troubleshooting, and version
policy details.

Install it from a local clone:

<!-- simple_model:test-command:start plugin-install -->
```bash
git clone https://github.com/silverenternal/simple_model.git
cd simple_model

# Register this repository's local plugin marketplace.
codex plugin marketplace add "$PWD"

# Install the plugin from the marketplace named in .agents/plugins/marketplace.json.
codex plugin add simple-model-project-intelligence@simple-model
```
<!-- simple_model:test-command:end -->

For a server deployment, use the same flow from the server checkout; no
macOS-specific path is required:

```bash
git clone https://github.com/silverenternal/simple_model.git
cd simple_model
codex plugin marketplace add "$PWD"
codex plugin add simple-model-project-intelligence@simple-model
codex plugin list | grep simple-model-project-intelligence
```

After installation, start a new Codex thread and ask it to use
`$simple-model-project-intelligence`. The skill reads `todo.json`,
`struct.json`, and `docs/AGENT_QUICKSTART.md`, then routes structural decisions
through deterministic generators instead of making them in the model prompt.

Initialize each target repository once so its configuration and generated
artifacts stay local:

```bash
simple_model_pi.sh --target-root /path/to/repo init --json
simple_model_pi.sh --target-root /path/to/repo init --dry-run --json
```

This creates `.projectIntelligence/` with `config.json`, policy contracts,
isolated artifacts/cache/state/backups, and a `.gitignore`. Existing config is
protected unless `--force` is passed; missing models fail explicitly instead of
silently using the simple_model checkout.

Then start a new Codex thread and invoke:

```text
Use $simple-model-project-intelligence to audit this repo.
```

The same plugin is also attached to GitHub Releases as a
`simple-model-project-intelligence-plugin-<version>.zip` asset.

### v2 production evidence

The v2 release gate covers the executable macro, external-corpus, long-horizon,
performance, hermetic replay, supply-chain, interoperability, MCP, and plugin
surfaces:

```bash
bash generators/release_slo_v2.sh --json
bash tests/test_v20_release_gate.sh
```

The release report records the program targets, held-out evidence, cache and
replay policy, signature verification, and plugin compatibility summaries in
`generated/releases/v2-production-readiness.json`.

Check local readiness:

<!-- simple_model:test-command:start plugin-check -->
```bash
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh doctor
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh commands --json
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh self-check --json
```
<!-- simple_model:test-command:end -->

---

## Adopting Existing Large Projects

For a large project that is already half-built, start read-only:

```bash
# Generate a draft model from source files without changing business code.
./bootstrap.sh --ingest-repo /path/to/big-repo --output /tmp/simple-model-adoption

# Split the reviewed model into fragments and resolve it deterministically.
./bootstrap.sh --struct /path/to/big-repo/struct.json --resolve

# Track which source files are still outside the self-model.
./bootstrap.sh --struct /path/to/big-repo/struct.json --adoption-audit /path/to/big-repo --json

# Compare structurally parsed public interfaces against component exports.
./bootstrap.sh --struct /path/to/big-repo/struct.json --interface-scan /path/to/big-repo --json

# Generate PR impact and full deterministic PR gate reports.
./bootstrap.sh --struct /path/to/big-repo/struct.json --pr-impact /path/to/big-repo --json
./bootstrap.sh --struct /path/to/big-repo/struct.json --pr-gate /path/to/big-repo --json
```

Then run deterministic macro optimization in dry-run mode:

```bash
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh \
  --target-root /path/to/big-repo \
  --struct /path/to/big-repo/struct.json \
  optimize --dry-run
```

The terminal report summarizes findings, planned macros, and execution results.
JSON/Markdown artifacts are written to `generated/optimization/`; `--apply`
records backups and rollback metadata before changing the target struct.

For generated macros and score-gated execution:

```bash
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh \
  --target-root /path/to/big-repo \
  --struct /path/to/big-repo/struct.json \
  optimize-loop --budget 3 --dry-run
```

`struct.json` can now be a small root file that references module fragments:

```json
{
  "schema_version": "3.0",
  "description": "large project",
  "includes": [
    "struct.modules/backend.json",
    "struct.modules/frontend.json",
    "struct.shared/phases.json"
  ]
}
```

`bootstrap.sh` automatically resolves includes to
`generated/.bootstrap/resolved.struct.json` before validation, checks, and
generation. Merge conflicts fail deterministically; include paths must be
relative and may not escape the struct root.

Components may declare `path`, `owners`, `checks`, `risk`, and `adoption` fields
so PR gates and agent dispatch can reason about code ownership, validation
commands, unmanaged areas, and high-risk surfaces. `--interface-scan` uses a
structural parser for Python AST plus comment/string-aware top-level parsing for
TypeScript/JavaScript, Go, and Rust, then reports missing declared exports plus
code exports not yet modeled in struct.
The v0.5 surface also includes code facts, import graph scan, test surface scan,
ownership resolution, risk scoring, review routing, work records, architecture
debt reports, GitHub Action generation, a read-only MCP wrapper, federation
resolve, batch planning, and a long-horizon evolution smoke harness.
It now adds stricter fact contracts, interface signatures and hashes, fact-cache
metrics, waiver checks, PR Markdown rendering, route/env scanning, release
contract reporting, dashboard generation, large-repo benchmark smoke coverage,
and an agent work-record harness.
The v0.6 plugin surface adds install smoke coverage, source/bundled skill sync,
cross-repo wrapper mode, `doctor`, structured command metadata, plugin target
fixtures, one-command demo, release packager, plugin CI, MCP command bridge, and
explicit plugin version policy. It also adds deterministic macro optimization:
macro registry validation, optimization planning from scanned facts, dry-run/apply
execution, generated macro specs, macro compilation, architecture health scoring,
score-gated optimization loops, terminal reports, and rollback manifests.

---

## Architecture

```
struct.json
   │
   ▼
generators/intent_validate.sh ──► 6-predicate soundness check
   │
   ▼
generators/orchestrate_decompose.sh ──► .ai/plan.json (wave-plan + soundness proof)
   │
   ▼
generators/orchestrate_bound.sh ──► .ai/slices/<leaf>.json (per-leaf context slice)
   │
   ▼
generators/orchestrate_gate.sh ──► .ai/gate.json (intent conformance + contract)
   │
   ▼
generators/cbom_emit.sh ──► .ai/cbom.json (five content-addressed hashes)
```

Each box is one bash script. Each script is deterministic on its inputs. The
LLM is invoked **only** at leaf tasks (in `--target dispatch` waves) to generate
code; the orchestrator never asks the LLM for a structural decision.

`./bootstrap.sh --target all` expands to the safe no-argument generators:
`agents`, `context`, `queue`, `viz`, `python`, `rust`, `go`, and `typescript`.
Subcommands such as `cbom_emit`, `chimeric_*`, and `orchestrate_*` are invoked
through their documented command paths because they need explicit inputs.

---

## Repository layout

```
simple_model/
├── bootstrap.sh                      # main orchestrator (~440 lines bash)
├── struct.schema.json                # universal schema
├── struct.json                       # root self-model; may include fragments
├── README.md                         # this file
├── CLAUDE.md                         # Claude-Code-specific onboarding
├── AGENTS.md                         # agent startup entry point
├── generators/                       # pure-bash+jq generators
│   ├── _lib.sh                       # shared library (topo sort, animations)
│   ├── orchestrate_decompose.sh      # wave-plan (self_cognition)
│   ├── orchestrate_bound.sh          # per-leaf slice (self_cognition)
│   ├── orchestrate_gate.sh           # pre-merge gate (self_cognition)
│   └── cbom_emit.sh                  # content-addressed CBOM (self_memory)
├── specs/                            # 14 JSON Schema specs
│   ├── intent-model.json             # the 6-predicate predicate algebra
│   └── cbom-schema.json              # the CBOM data structure
├── docs/
│   ├── AGENT_QUICKSTART.md           # 5-minute orientation for any agent
│   ├── CHANGELOG.md                  # v0.3 release notes
│   ├── orchestration/                # the four-algorithm design docs
│   └── ip/                           # patent prior-art + claim architecture
├── examples/dnc-demo/                # end-to-end Project Intelligence demo
└── tests/                            # deterministic regression suites
```

---

## Documentation map

| File | Read when | Lines |
|---|---|---|
| `AGENTS.md` | first 60 seconds of any agent session | project rules + command map |
| `CLAUDE.md` | you are Claude Code and need command/architecture detail | 279 |
| `docs/AGENT_QUICKSTART.md` | you have 5 minutes to orient | 102 |
| `docs/orchestration/decompose.md` | you are designing a new decomposition rule | 160 |
| `docs/ip/provisional-claim-architecture.md` | you need to know what is patented | 287 |
| `examples/dnc-demo/README.md` | you want to see Project Intelligence run end-to-end | 74 |
| `docs/CHANGELOG.md` | you want v0.3 release notes | 50 |

---

## Project Intelligence — patent anchor

The three inventive pillars (intent predicates → sound wave plan → content-addressed CBOM)
are documented in [`docs/ip/provisional-claim-architecture.md`](docs/ip/provisional-claim-architecture.md).
All patents disclaim the known prior-art lanes (Conductor / Praetorian / Agentproof /
Lean4Agent / ActiveGraph / SPICE / Confucius / MetaGPT / SOP / Cursor / Aider / feature-model
scheduling). The differentiator lives in the coupling — see the daylight analysis in
[`docs/ip/differentiation-memo.md`](docs/ip/differentiation-memo.md).

---

## License

MIT. See `LICENSE`.

---

Built with bash ≥ 4 and jq. Zero other dependencies.
### Production Optimizer Flow

For large half-built repositories, use the plugin flow:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json adopt --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json semantic-graph --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh production-benchmark --json
```

This builds deep parser facts, Semantic Graph v2, fast validation, adoption
reports, and production readiness evidence before any macro apply workflow.

For v1.1 production adoption, use the confidence-gated flow:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json parser-tiers --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json semantic-graph-incremental --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json macro-preconditions --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json confidence-plan --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json adoption-cockpit --json
```

This separates safe-now, review-first, gather-evidence, and do-not-touch queues.
Low-confidence parser evidence and untrusted dynamic edges cannot produce
automatic apply recommendations.
