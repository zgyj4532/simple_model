# Orchestration — the Project Intelligence core

This directory holds the four design docs that document the deterministic
Project Intelligence core of simple_model: **decompose**, **bound**, **gate**,
and **CBOM**. Each sub-algorithm is a pure bash + jq script, deterministic on
its inputs, and decoupled from any LLM. The four are coupled at the data
level via five content-addressed hashes (intent, plan, slice, code, gate).

## The four-algorithm stack

```
struct.json ──► decompose ──► bound ──► gate ──► CBOM
                (waves)       (slices)   (verdict)  (memory)
```

decompose is intent-sound partition; bound is per-leaf context slice; gate is
pre-merge contract + intent conformance; CBOM is content-addressed self-memory
that ties the three together. Together they are the **self_cognition + self_memory**
layers of Project Intelligence (the third layer, **self_model**, lives in
`struct.json` + `specs/intent-model.json`).

## Reading order

Read in this order — each doc assumes the prior:

1. **decompose.md** — wave-plan emission, soundness argument, exit codes
2. **bound.md** — per-leaf context slicing from intent + import DAG
3. **gate.md** — pre-merge intent conformance + contract verification
4. **cbom.md** — the five-hash content-addressed manifest that makes it all reproducible

## The four docs

| Doc | 1-line summary | Read when | Key insight | Lines |
|---|---|---|---|---|
| [decompose.md](./decompose.md) | Sound wave-plan from intent predicates | designing a new decomposition rule | soundness is by-construction + checker-time safety net | 168 |
| [bound.md](./bound.md) | Per-leaf context slice derived from intent | extending slice sources, adding a leaf consumer | slice is a pure function of (plan, struct, invariants) — no LLM | 88 |
| [gate.md](./gate.md) | Pre-merge intent conformance + contract gate | adding a new chimeric mode, integrating CI | gate reuses chimeric verify semantics; intent-conformance extends it | 99 |
| [cbom.md](./cbom.md) | Five-hash content-addressed self-memory | debugging non-reproducible runs, integrating drift | canonical JSON (`jq -S -c`) makes bit-identical CBOMs portable | 103 |

Patent anchor for the four-algorithm combination: [`docs/ip/provisional-claim-architecture.md`](../ip/provisional-claim-architecture.md) — Provisional Claim Architecture, NARROW GO verdict on all three independent claims.
