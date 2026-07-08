# Command Reference

Use these commands from the `simple_model` repository root unless a wrapper command is shown.

## Model Lifecycle

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
