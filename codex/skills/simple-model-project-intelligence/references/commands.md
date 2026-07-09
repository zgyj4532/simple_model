# Command Reference

Use these commands from the `simple_model` repository root unless a wrapper command is shown.

## Model Lifecycle

- Diagnose plugin/toolchain readiness:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh doctor --json`
- List wrapper command metadata:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh commands --json`
- Run the plugin lifecycle gate:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh self-check --json`
- Run release validation without publishing:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh self-release --version 0.6.0 --dry-run --json`
- List deterministic optimizer macros:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macros --json`
- Generate declarative macro specs from target repo facts:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json macro-suggest --json`
- Compile generated specs into an executable plan:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-compile --suggestions generated/optimization/macro-suggestions.json --json`
- Score architecture health:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json score --json`
- Plan and dry-run macro optimization for a target repo:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json optimize --dry-run`
- Run the score-driven generate/compile/execute loop:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json optimize-loop --budget 3 --dry-run`
- Execute a saved optimization plan:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-run --plan generated/optimization/plan.json --dry-run --json`
- Validate source model:
  `./bootstrap.sh --validate`
- Resolve multi-file model:
  `./bootstrap.sh --resolve --json`
- Regenerate safe no-argument outputs:
  `./bootstrap.sh --target all`
- Check generated implementation drift:
  `./bootstrap.sh --check-all`
- Lint and drift summaries:
  `./bootstrap.sh --lint --json | jq '.summary'`
  `./bootstrap.sh --drift --json | jq '.summary'`

## Large Repo Adoption

- Draft a model from an existing repo:
  `./bootstrap.sh --ingest-repo <repo-root> --json`
- Audit unmanaged source files:
  `./bootstrap.sh --adoption-audit <repo-root> --json`
- Scan public interfaces:
  `./bootstrap.sh --interface-scan <repo-root> --json`
- Suggest struct patch operations from findings:
  `generators/struct_suggest.sh --findings <findings.json> --json`

## Macro Optimization

- Validate the macro registry:
  `generators/macro_registry.sh --json`
- Build a deterministic optimization plan from repo facts:
  `generators/optimization_plan.sh --root <repo-root> --struct <struct.json> --json`
- Generate declarative macro specs:
  `generators/macro_suggest.sh --root <repo-root> --struct <struct.json> --json`
- Compile generated macro specs:
  `generators/macro_compile.sh --suggestions generated/optimization/macro-suggestions.json --json`
- Compute architecture health score:
  `generators/optimization_score.sh --root <repo-root> --struct <struct.json> --json`
- Execute the plan without changing files:
  `generators/macro_exec.sh --plan generated/optimization/plan.json --dry-run --json`
- Apply low-risk automatic macros with rollback metadata:
  `generators/macro_exec.sh --plan generated/optimization/plan.json --apply --json`
- Run a score-gated optimization loop:
  `generators/optimization_loop.sh --root <repo-root> --struct <struct.json> --budget 3 --dry-run --json`

## Code Facts And Gates

- Emit strict code facts with cache:
  `generators/code_facts.sh --root <repo-root> --struct <struct.json> --json`
- Compare interface scan reports:
  `generators/interface_diff.sh --before <before.json> --after <after.json> --json`
- Gate interface drift:
  `generators/interface_drift_gate.sh --root <repo-root> --struct <struct.json> --json`
- Gate dependency drift:
  `generators/dependency_drift_gate.sh --root <repo-root> --struct <struct.json> --json`
- Apply waiver checks:
  `generators/waiver_check.sh --waivers specs/waiver.json --json`

## PR And Release

- Compute PR impact:
  `./bootstrap.sh --pr-impact <repo-root> --json`
- Run PR gate:
  `./bootstrap.sh --pr-gate <repo-root> --json`
- Run PR gate and write Markdown:
  `generators/pr_gate.sh --root <repo-root> --struct <struct.json> --markdown generated/pr-comment.md --json`
- Produce a release contract from interface diff:
  `generators/release_contract.sh --diff <interface-diff.json> --json`
- Generate static dashboard:
  `generators/dashboard.sh generated/dashboard.html`

## Multi-Repo And Agent Evaluation

- Resolve federation:
  `generators/federation_resolve.sh --json`
- Plan deterministic batches:
  `generators/batch_plan.sh --json`
- Run evolution harness:
  `examples/evolution-bench/run.sh`
- Run agent eval smoke:
  `bash tests/test_agent_eval_harness.sh`
