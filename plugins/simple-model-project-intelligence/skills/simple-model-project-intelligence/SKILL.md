---
name: simple-model-project-intelligence
description: Use this skill when the user wants Codex to adopt, analyze, maintain, or gate a large in-progress codebase with the simple_model Project Intelligence toolchain. It applies when working with struct.json, multi-file struct includes, repo ingestion, interface scanning, code facts, PR impact, risk routing, waivers, dashboards, release contracts, or deterministic AI development queues.
---

# Simple Model Project Intelligence

Use this skill to turn a partially built repository into a deterministic Project Intelligence workspace. The source of truth is `struct.json`; scripts make structural decisions, and Codex should treat LLM output as leaf work only.

## Preconditions

- Run from the `simple_model` repo, or from a repo that has `simple_model` available and pass explicit paths to its commands.
- Required local tools: `bash`, `jq`, and standard Unix utilities. Some generated language checks may also use Rust, Go, TypeScript, or Python toolchains.
- Before trusting any changed model, run `./bootstrap.sh --validate`.

## Workflow

0. Initialize a target repository's local control plane before analysis:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> init --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> init --dry-run --json
```

This creates `.projectIntelligence/` with `config.json`, policy files, isolated
artifacts/cache/state/backups, and a `.gitignore`. Existing configuration is
protected unless `--force` is supplied. Model discovery is explicit `--struct`,
then local config, then `<repo-root>/struct.json`; the toolchain model is never
used as a target fallback.

1. For a repo that does not yet have a model, start with:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh ingest <repo-root> <output-struct>
```

2. For an existing model, validate the deterministic state:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh validate
```

Use `doctor` before debugging installation or cross-repo use:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh doctor --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh commands --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh self-check --json
```

3. Analyze a large in-progress repo against `struct.json`:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh facts <repo-root>
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh interfaces <repo-root>
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh audit <repo-root>
```

4. For deterministic project optimization, let macros plan and execute safe structure changes:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json optimize --dry-run
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json macro-suggest --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json optimize-loop --budget 3 --dry-run
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macros --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-run --plan generated/optimization/plan.json --dry-run --json
```

5. For PR or patch review, use deterministic gates before advising:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh pr-gate <repo-root>
```

6. For release or status handoff, generate reports:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh dashboard generated/dashboard.html
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh full-check
```

7. For the v2 production evidence path, run the resumable evolution benchmark,
incremental performance economics, offline macro-pack verification, portable
MCP surface, and final release SLO:

```bash
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh evolution-benchmark --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh performance-v2 --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh interoperability --json
codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh release-slo-v2 --json
```

## Operating Rules

- Keep `todo.json` product-roadmap progress separate from component todos in `struct.json`.
- Prefer generated JSON reports over prose when deciding ownership, impact, tests, risk, or review routing.
- Use macro optimization for architecture and structure changes when possible; Codex should inspect reports and avoid hand-editing structural decisions that a macro can decide.
- Do not edit generated outputs by hand; update source model or generator scripts, then rerun `./bootstrap.sh --target all`.
- Use waivers only as explicit, expiring exceptions. Do not silently ignore gate failures.
- If `struct.json` uses `includes`, resolve it through `./bootstrap.sh --resolve` or normal bootstrap commands instead of ad hoc merging.

## Commands Reference

For exact command surfaces and common report flows, read `references/commands.md`.
For structured command metadata, read `references/command-manifest.json`.

## Validation Before Handoff

Run this sequence after changing the model, generators, or skill resources:

```bash
./bootstrap.sh --validate
./bootstrap.sh --check-all
./bootstrap.sh --lint --json | jq '.summary'
./bootstrap.sh --drift --json | jq '.summary'
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```
