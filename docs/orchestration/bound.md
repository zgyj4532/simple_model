# Bound (intent-consistent context slice)

## Role

Bound is the second deterministic sub-algorithm. Given a wave-plan + `struct.json`, it produces a **context slice** for every leaf task (every component in the plan). The slice is the minimal visible projection of the project that the leaf agent needs to do its work, derived **from intent and the import DAG** — never from LLM judgement.

The slice answers four questions for the leaf:

1. **Who am I?** — the component's name, phase, exports, description.
2. **What can I depend on?** — the transitive closure of its direct `imports` (filtered to the resolved set).
3. **What invariants apply to me?** — the user-declared invariants whose scope intersects this component's phase / set.
4. **What code should I read?** — the file paths for the leaf and its direct dependencies (used by `cbom_emit` to hash).

## Design

For the Wave 3 skeleton, we derive slices **principled-minimally** from:

- The leaf's own component object (name, description, exports, imports, optional flag).
- The leaf's phase (which phase the leaf belongs to).
- The leaf's direct imports, restricted to the resolved set.
- The phase's declared `core_components`, `optional_components`, `select_one_of`, `select_subset_of` (for "phase context").
- All invariants whose scope is satisfied by this leaf (e.g., `scope: components_in_phase:<leaf_phase>`).

Future versions may extract a deeper public-surface / symbol table (the user noted this is the spine → bound upgrade path; see todo `bound_context`). The skeleton's sources are derived purely from `struct.json` fields and the wave-plan — no LLM, no symbol parser.

## Output (per leaf)

```jsonc
{
  "leaf_id": "Trainer",
  "phase": "train",
  "tier": "core",
  "sources": {
    "self": {
      "name": "Trainer",
      "description": "...",
      "exports": ["trained_model", "training_state"],
      "imports": ["AutoConfig", "AutoModel", "Optimizer", ...],
      "file": "<generated>/python/train/trainer.py",
      "hash": "sha256:<hex>"
    },
    "deps": {
      "AutoConfig": { "name": "AutoConfig", "exports": [...], "file": "...", "hash": "..." },
      "AutoModel":  { ... },
      ...
    },
    "phase": {
      "phase": "train",
      "core_components": ["Trainer", "MixedPrecision", ...],
      "select_one_of":   []
    },
    "invariants_visible": [
      { "name": "every_train_phase_has_trainer",
        "scope": "components_in_phase:train",
        "quantifier": "exists",
        "predicate": ".name == \"Trainer\"",
        "message": "..." }
    ]
  },
  "token_estimate": 1234
}
```

## Algorithm

```
INPUT:  plan P, struct S, invariants file I (optional)
OUTPUT: slice L per component in P

for each component c in P:
  build sources.self      = component c from S
  build sources.deps      = for each i in c.imports: lookup component in R (resolved set)
  build sources.phase     = phase p in S.phases such that c ∈ p.core_components ∪ p.optional_components ∪ p.select_one_of ∪ p.select_subset_of
  build sources.invariants_visible = filter I to those whose scope intersects c (or c's phase)
  compute token_estimate = sum of (description length + |exports| + |imports| + ...) across sources
  write slice to .ai/slices/<c>.json
```

## Determinism

The slice is purely a function of `(plan, struct, invariants)`. No timestamps, no LLM. Two runs over the same inputs produce bit-identical slices (verified in `tests/test_decompose_sound.sh` and `tests/test_cbom.sh`).

## Where Bound fits in Project Intelligence

Bound is the **self_cognition / bounding** layer. The differentiator versus
"smart tool + dumb repo" agent UIs is the **dumb tool + smart repo** inversion:
the project (via `struct.json`) remembers its own architecture, and the
algorithm (Bound, in this case) carries the memory — the LLM sees only the
minimal slice it needs to do its leaf work, never the whole repo.

## Exit codes

| Code | Meaning |
|------|---------|
| 0    | All slices emitted. |
| 2    | Usage error. |
| 4    | Phase inconsistency — a resolved component has no phase. |