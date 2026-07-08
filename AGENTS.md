# AGENTS.md

Start with `docs/AGENT_QUICKSTART.md` when you have more than a minute. This
file is the short operational contract for agents working in this repo.

## Operating Model

- `struct.json` is the source of truth for architecture, imports, exports,
  phases, and component-level todos.
- The bash+jq runtime is the algorithm. LLMs are leaf workers and must not make
  structural decisions that the deterministic scripts can decide.
- Use `./bootstrap.sh --validate` before trusting a changed model.
- Use `./bootstrap.sh --target all` to regenerate the safe no-argument outputs:
  agent docs, context, queue, visualization, and Python/Rust/Go/TypeScript
  skeletons.
- Use explicit orchestration commands for algorithms that need inputs:
  `generators/orchestrate_decompose.sh`, `generators/orchestrate_bound.sh`,
  `generators/orchestrate_gate.sh`, and `generators/cbom_emit.sh`.

## Todo Surfaces

- `todo.json` is the product roadmap for simple_model itself.
- `struct.json` component todos drive `./bootstrap.sh --status`,
  `--next`, `--claim`, and `--complete`.
- Do not mix these two layers when reporting progress.

## Checks

Run these before handing work back:

```bash
./bootstrap.sh --validate
./bootstrap.sh --check-all
./bootstrap.sh --lint --json | jq '.summary'
./bootstrap.sh --drift --json | jq '.summary'
for t in tests/test_*.sh; do bash "$t" || exit 1; done
```
