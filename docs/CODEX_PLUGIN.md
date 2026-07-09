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

For a separate target repository:

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
