# Decompose (intent-sound decomposition)

## Role

Decompose is the first of three deterministic orchestration sub-algorithms. Given a `struct.json` (intent + component DAG) and an optional todo DAG, it produces a **wave-plan** — a partition of components into parallel waves such that:

1. Every component in the plan is reachable from some active phase or enabled cross-cutting concern.
2. The plan respects all six intent predicates (no over-selection, no orphan components, no broken `blocks` edges).
3. Components within a wave are independent (no unresolved `imports` edge stays inside a wave).

If the algorithm cannot produce a sound plan, it **refuses to emit one**: the soundness checker rejects the candidate, the algorithm exits non-zero, and the caller must resolve the violation before re-running.

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| `struct.json` | `./struct.json` or `-s` | yes |
| Selection overrides | `--selection phase=component` (repeatable) | no |
| Enabled-overrides (optional) | `--enable component` / `--disable component` (repeatable) | no |
| Invariant file | `--invariants invariants.json` (array) | no |

If `--selection` is absent, the default for each `select_one` phase is the first element of `select_one_of`. If `--enable`/`--disable` is absent, the default rules are:
- Components with `optional: true` are dropped unless explicitly enabled.
- Cross-cuttings with `default_enabled: false` are dropped unless explicitly enabled.

## Output

```jsonc
{
  "schema_version": "1.0",
  "generated_at": "<iso8601>",
  "project": "simple_model",
  "plan": [
    { "wave": 1, "components": ["ConfigLoader", "TaskRegistry"] },
    { "wave": 2, "components": ["ConfigComposer"] },
    ...
  ],
  "resolved": {
    "selected_components": [...],
    "selections": { "init_distributed": "DDPLauncher" },
    "enabled": { "CanaryDeployer": false }
  },
  "soundness": {
    "ok": true,
    "predicates": {
      "select_one_of":          { "ok": true, "violations": [] },
      "optional":               { "ok": true, "violations": [] },
      "phase_membership":       { "ok": true, "violations": [] },
      "cross_cutting_injection":{ "ok": true, "violations": [] },
      "blocks":                 { "ok": true, "violations": [] },
      "invariant":              { "ok": true, "violations": [] }
    }
  },
  "stats": { "waves": N, "components": M, "parallelism_max": K }
}
```

## Algorithm

```
INPUT:  struct S, optional inv file I, optional overrides E
OUTPUT: plan P or ⊥ (refuse)

1. Materialise resolved set R:
     - start with (core_components ∪ select_subset_of) across all phases
     - add the chosen branch from each select_one phase (default = first)
     - add enabled cross_cutting components
     - drop disabled optionals
     - drop unselected select_one branches

2. Compute the topological import DAG restricted to R.
   (We use topo_sort_components from generators/_lib.sh, then filter to R.)

3. Wave assignment = longest-path layering:
     depth[v] = 1 + max{ depth[u] : u in imports(v) ∩ R }
     wave(v) = depth[v]
   Two components in the same wave are independent w.r.t. R's import edges.

4. Determinism: when ties occur (same depth), break by alphabetic name.

5. SOUNDNESS CHECK on R and the plan:
     - select_one_of:    for each phase with mode=select_one:
                          |R ∩ select_one_of| == 1 AND R ∩ select_one_of == {default_selections[phase]}
     - optional:         for each component with optional=true:
                          enabled  ⇒ component ∈ R
                          disabled ⇒ component ∉ R
     - phase_membership: for each c ∈ R: c appears in some phase's component set
                          OR c ∈ xcut.components for some enabled cross-cutting
     - cross_cutting_injection: xcut.injects_into ⊆ phases[].phase
     - blocks:           for each todo t: plan.wave[t.id] > plan.wave[b] for every b ∈ t.blocks
     - invariant:        for each user-declared invariant i:
                          scope_materialise(i.scope, R, plan) ⊢ i.predicate (per i.quantifier)
     If ANY check fails ⇒ emit ⊥ with the violating predicate + location + message.
     Else ⇒ emit plan P with soundness.ok = true.
```

## Soundness argument

The construction guarantees soundness by **construction** (the plan is built only from `R`, and `R` is built from declared phases + selected branches + enabled cross-cuttings), with the soundness checker as a **safety net** that re-derives each predicate from the candidate plan and refuses if any violation slipped through (e.g., a bug in the algorithm, a new predicate added later, or external overrides that contradict the declarations).

The two-layer guarantee is intentional:
- **Construction-time**: if all input data is correct, the plan is sound by induction on the rules.
- **Checker-time**: if input data is malformed (e.g., a phase references a non-existent component, a `select_one_of` is empty, a todo's `blocks` id is unknown), the checker catches it before the caller wastes resources.

This separation also lets us extend the algorithm with new pruning rules without re-arguing soundness — every new rule ships with its corresponding checker clause.

## Decidability

Every step is decidable on a finite `struct.json`:
- Set operations on R: O(|R|).
- Topological sort: O(|V| + |E|) where |V| ≤ |R|, |E| ≤ |R|² (worst case).
- Wave assignment: O(|R|²) (single linear pass with memoised max).
- Soundness check: conjunction of six finite set-membership / wave-map / jq-predicate evaluations — each polynomial in |R| and |todos|.

The conjunction of decidable predicates is decidable. The algorithm therefore always terminates with either a sound plan or ⊥.

## Exit codes

| Code | Meaning |
|------|---------|
| 0    | Sound plan emitted. |
| 1    | Soundness check failed — see `soundness.predicates[*].violations`. |
| 2    | Usage error (missing struct, malformed --plan, etc.). |
| 3    | Intent inconsistent — e.g., a todo's `blocks` references an unknown id. |

## Project Intelligence — where this fits

Decompose is one of three sub-algorithms inside the **Project Intelligence**
thesis. The three layers of Project Intelligence map to specific artifacts in
this repo:

- **self_model** = `struct.json` + the six intent predicates in
  `specs/intent-model.json`. This is the project's declarative knowledge of
  its own architecture — non-derivable from source code, build manifests, or
  runtime traces.
- **self_cognition** = the three deterministic sub-algorithms:
  Decompose (this document), Bound (`docs/orchestration/bound.md`),
  and Gate (`docs/orchestration/gate.md`). Each is jq+bash; each is
  decidable; together they constitute intent-sound orchestration.
- **self_memory** = the CBOM, defined in `specs/cbom-schema.json` and
  produced by `generators/cbom_emit.sh`. Five content-addressed hashes
  (intent, plan, slice, code, gate) make every run bit-reproducible.

The differentiator versus Cursor / Aider / Conductor / ReSo is the
**dumb tool + smart repo** market-inversion: the project remembers its own
architecture instead of the external tool re-discovering it on every run.

Patent anchor: `docs/ip/provisional-claim-architecture.md` — Provisional Claim
Architecture, with NARROW GO verdict on all three independent claims
(intent-sound orchestration, content-addressed CBOM, declarative project
model with non-code-recoverable predicates). The combination — and only the
combination — is the inventive subject; each pillar individually has known
ancestors that the claim architecture explicitly disclaims around.

The soundness guarantee that ties this all together: **every emitted plan
provably satisfies every intent predicate** (zero `select_one_of` violations,
zero `optional`-leakage, zero broken `blocks` edges, zero invariant violations).
The guarantee is by-construction (the plan is built only from the resolved
set `R`, and `R` is built from declared intent) plus a checker-time safety net
that re-derives each predicate from the candidate plan and refuses if any
violation slipped through.