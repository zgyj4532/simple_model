# Codex Plugin

The plugin source of truth lives in `plugins/simple-model-project-intelligence/`.
The editable skill source lives in `codex/skills/simple-model-project-intelligence/`.
Before packaging, keep them synchronized:

```bash
tools/sync_codex_plugin.sh --check
tools/sync_codex_plugin.sh --sync
```

## Install From A Clone

```bash
git clone https://github.com/silverenternal/simple_model.git
cd simple_model
codex plugin marketplace add "$PWD"
codex plugin add simple-model-project-intelligence@simple-model
```

Start a new Codex thread after install or update, then invoke:

```text
Use $simple-model-project-intelligence to audit this repo.
```

## Diagnose

```bash
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh doctor
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh doctor --json
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh self-check --json
```

## Initialize A Target Repository

Initialization is project-local and does not require `SIMPLE_MODEL_HOME`:

```bash
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh \
  --target-root /path/to/target-repo init --json
```

This creates `.projectIntelligence/` with configuration, policy contracts,
isolated artifacts/cache/state/backups, and a `.gitignore`. Use
`init --dry-run --json` to preview changes; existing configuration is never
overwritten unless `--force` is supplied. Model discovery is explicit path,
local config, then target-root `struct.json`; the toolchain model is never used
as a target fallback.

## Macro Optimization

The plugin can optimize another in-progress repository through deterministic
macros. The planner reads adoption, interface, import, and architecture-debt
facts, then the executor runs code/structure macros. The default mode is
`--dry-run`; `--apply` writes rollback metadata under `generated/optimization/`.

```bash
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh \
  --target-root /path/to/target-repo \
  --struct /path/to/target-repo/struct.json \
  optimize --dry-run
```

For explicit steps:

```bash
generators/macro_registry.sh --json
generators/macro_suggest.sh --root /path/to/target-repo --struct /path/to/target-repo/struct.json --json
generators/macro_compile.sh --suggestions generated/optimization/macro-suggestions.json --json
generators/optimization_score.sh --root /path/to/target-repo --struct /path/to/target-repo/struct.json --json
generators/optimization_plan.sh --root /path/to/target-repo --struct /path/to/target-repo/struct.json --json
generators/macro_exec.sh --plan generated/optimization/plan.json --dry-run --json
generators/optimization_loop.sh --root /path/to/target-repo --struct /path/to/target-repo/struct.json --budget 3 --dry-run --json
```

Automatic macros currently cover struct include splitting, export normalization,
and import synchronization from scanned code facts. Generated macro specs are
compiled before execution; apply-mode loops rescore the target and roll back if
the score does not improve.

For older installations or commands that need the source toolchain:

```bash
SIMPLE_MODEL_HOME=/path/to/simple_model \
  /path/to/simple_model/plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh \
  --target-root /path/to/target-repo doctor
```

## Package

Plugin version follows the plugin manifest version. Release assets use:

```text
simple-model-project-intelligence-plugin-<plugin-version>.zip
```

Build a package:

```bash
tools/package_codex_plugin.sh --version 0.6.0
```

The script validates skill sync, marketplace JSON, plugin manifest version, command
metadata, and wrapper execution before writing `dist/`.

Run the full plugin lifecycle gate and write a self-audit report:

```bash
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh self-check
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh self-audit
```

Run release validation without publishing:

```bash
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh self-release --version 0.6.0 --dry-run --json
```

## Update Or Remove

For updates, pull the latest repository, rerun `codex plugin add
simple-model-project-intelligence@simple-model`, and start a new Codex thread.

For removal, use your Codex CLI's plugin removal command if available. If the CLI
does not expose one, remove or stop using the repo-local marketplace registration.

## Troubleshooting

- `cannot locate simple_model root`: set `SIMPLE_MODEL_HOME=/path/to/simple_model`.
- `jq` missing: install `jq` and rerun `doctor`.
- Old bash on macOS: run scripts with Homebrew bash 4+.
- Plugin changes not visible: reinstall the plugin and start a new Codex thread.
## v1.0 Production Flow

From any target repository with a `struct.json`, run:

```bash
simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json adopt --json
simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json semantic-graph --json
simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json production-benchmark --json
```

Use `tree-sitter-scan`, `lsp-symbols`, `score-calibrate`,
`optimizer-report`, `framework-resolvers`, and `runtime-contracts` when a repo
needs deeper evidence before macro simulation or apply.

## v1.1 Confidence-Gated Flow

The v1.1 flow is designed for large half-built repositories where automatic
changes need explicit evidence and rollback proof:

```bash
simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json parser-tiers --json
simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json symbol-index --json
simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json semantic-graph-incremental --json
simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json dynamic-edges --json
simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json macro-preconditions --json
simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json macro-drill --json
simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json confidence-plan --json
simple_model_pi.sh --target-root /path/to/repo --struct /path/to/repo/struct.json adoption-cockpit --json
```

`accuracy-scorecard` and `release-slo` gate releases against the labeled messy
repo corpus, false-safe-apply count, macro rollback drills, parser confidence,
and plugin command coverage.
