# simple_model Adoption Playbook

## 30 minutes

1. Run `./bootstrap.sh --ingest-repo <repo>`.
2. Review generated component names and paths.
3. Run `./bootstrap.sh --adoption-audit <repo> --json`.
4. Run `./bootstrap.sh --interface-scan <repo> --json`.

## 1 day

Split the root model with `includes`, add owners/checks for high-value modules,
and generate architecture debt with `generators/architecture_debt.sh`.

## 1 week

Add waivers for known adoption debt, enable `--pr-impact`, then enable
`--pr-gate` in advisory mode before making it required in CI.

Adoption mode tolerates known debt through explicit waivers. Enforcement mode
fails new unwaived drift.
