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
and a single-file HTML visualization of the architecture (`--target viz`).

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

# 5. Run the full test suite (160 assertions across 7 suites)
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```

Need bash ≥ 4 (macOS users: `/opt/homebrew/bin/bash`). Pre-existing `struct.json`
describes a 15-module / 90-component ML training platform; `--validate` confirms
it is well-formed before anything else runs.

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
├── struct.json                       # single source of truth for THIS project
├── README.md                         # this file
├── CLAUDE.md                         # Claude-Code-specific onboarding
├── AGENTS.md                         # agent startup entry point
├── generators/                       # 28 pure-bash+jq generators
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
└── tests/                            # test_chimeric_e2e + 3 W2-W4 suites
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
