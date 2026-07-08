# Provisional Patent Draft — Project Intelligence

This draft is an engineering-facing provisional outline for attorney review. It
narrows the invention to the combination already implemented in this repository:
intent predicates, intent-sound deterministic decomposition, bounded leaf
context, deterministic gate checks, and content-addressed CBOM provenance.

## Field

The invention relates to software development automation, deterministic
orchestration of language-model workers, and machine-readable project metadata
used to decompose, bound, verify, and reproduce software changes.

## Problem

Existing agent systems often rediscover repository structure at runtime or let a
language model decide decomposition and routing. That creates inconsistent task
boundaries, context drift, non-reproducible agent runs, and weak auditability.

## Summary

A software repository carries a machine-readable self model containing modules,
components, dependencies, tasks, and architectural intent predicates. A
deterministic runtime consumes that self model to emit an intent-sound wave plan,
bounded per-leaf context slices, merge gates, and a content bill of materials.
Language models may operate as leaf workers, but structural decisions remain
deterministic and reproducible.

## Independent Claim Sketch

1. A computer-implemented method comprising:
   receiving a repository self model describing components, dependencies, task
   blockers, and architectural intent predicates;
   evaluating the intent predicates with a deterministic runtime;
   generating a pruned topological wave plan that excludes components or tasks
   inconsistent with the evaluated predicates;
   generating, for each leaf task in the wave plan, a bounded context slice
   derived from the repository self model;
   receiving one or more leaf task outputs;
   applying a deterministic gate that checks the outputs against the repository
   self model and one or more contracts; and
   emitting a content-addressed bill of materials containing hashes for intent,
   plan, context slices, code outputs, and gate results.

## Dependent Claim Sketches

2. The method of claim 1, wherein the architectural intent predicates include
mutual selection, optionality, phase membership, cross-cutting injection, task
blockers, and invariants.

3. The method of claim 1, wherein the wave plan includes a soundness report
identifying whether each predicate category is satisfied.

4. The method of claim 1, wherein each bounded context slice includes component
imports, exports, phase membership, task metadata, and provenance hashes.

5. The method of claim 1, wherein leaf workers are invoked through a uniform
adapter interface supporting multiple language-model tools.

6. The method of claim 1, wherein leaf workers execute in isolated git
worktrees selected from a wave of parallel-safe tasks.

7. The method of claim 1, wherein the deterministic runtime requires no runtime
dependency beyond a shell interpreter, a JSON query tool, and optional version
control operations for worktree dispatch.

8. The method of claim 1, wherein a collector validates bounded leaf summaries
against a schema before returning them to an orchestrator.

## Implemented Artifacts

- `struct.json` is the repository self model.
- `specs/intent-model.json` defines predicate semantics.
- `generators/orchestrate_decompose.sh` emits the wave plan.
- `generators/orchestrate_bound.sh` emits leaf context slices.
- `generators/orchestrate_gate.sh` emits deterministic gate results.
- `generators/cbom_emit.sh` emits the CBOM.
- `generators/orchestrate_dispatch.sh` and `generators/adapters/` implement the
  isolated dispatch and leaf-worker adapter surfaces.

## Attorney Notes

The broad idea of deterministic orchestration is prior art. The filing should
stay narrow: the differentiator is the coupling of repository-carried intent
predicates, sound deterministic decomposition, bounded leaf context, gate checks,
and content-addressed reproducibility.
