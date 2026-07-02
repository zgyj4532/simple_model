# Provisional Patent Claim Architecture — Project Intelligence

**Title (working):** *Intent-Sound Divide-and-Conquer Orchestration with Content-Addressed Context Bill of Materials for LLM Agent Decomposition*

**Application type:** U.S. Provisional Patent Application (35 U.S.C. § 111(b))

**Inventive entity:** simple_model project contributors (final inventor list to be determined with attorney)

**Filing date (proposed):** 2026 Q3 (after attorney review of `docs/ip/patent-prior-art.md` and `docs/ip/differentiation-memo.md`)

**Status of this document:** Draft for human patent attorney review. This is NOT a final claim set; it is the proposed architecture that the attorney should refine for formal filing. Claim numbering, antecedent basis, and 112 written-description / enablement requirements must be finalized by counsel.

---

## I. Title of the Invention

**A method, system, and article of manufacture for intent-sound divide-and-conquer orchestration of language-model agents, comprising:** (a) a declarative project model carrying non-code-recoverable architectural intent predicates; (b) a deterministic decomposition step that consumes said predicates to emit a wave-schedule that is provably sound with respect to said predicates; and (c) a content-addressed Context Bill of Materials (CBOM) that bit-reproducibly commits to the declaration, plan, context-slices, generated code, and soundness proof.

---

## II. Cross-Reference to Related Applications

[To be added by attorney]

---

## III. Background — Field of the Invention

The invention relates to the orchestration of generative-language-model agents performing software development, code modification, or refactoring tasks. More particularly, the invention relates to a deterministic decomposition engine that consumes a typed, human-authored architectural intent predicate set to derive a parallel wave schedule, with a content-addressed Context Bill of Materials enabling bit-reproducible execution and audit.

## IV. Background — Description of Related Art

The following prior-art categories are explicitly NOT claimed over by the present invention. They are listed for the examiner's convenience and to disambiguate claim scope. All references were identified by an open-web prior-art search conducted 2026-07-02 (see companion documents `patent-prior-art.md` and `differentiation-memo.md`).

### A. Generic deterministic multi-agent orchestration

- **Microsoft Conductor** (Microsoft Open Source Blog, 2026-05-14; github.com/microsoft/conductor) — YAML-defined multi-agent workflows with Jinja2-routed deterministic control flow. Workflow topology is hand-authored; no declarative predicate algebra; no soundness proof; no content addressing.
- **Praetorian Development Platform** (Praetorian, 2025-11) — 16-phase state machine with Thin Agent / Fat Platform architecture, hook-based enforcement, "Intent-Based Context Loading" via LLM-mediated Gateway router. "Intent" here is semantic intent classification, not a declarative predicate.

### B. Generic DAG / topological wave scheduling

- **ReSo** (Zhou et al., EMNLP 2025 main 808; arXiv 2503.02390) — task decomposition DAG with UCB-based agent selection. DAG carries only dependency edges; no architectural predicate slots.
- **Confucius** (Wang et al., SIGCOMM 2025) — DAG-based LLM planning for *network* management. "Intent" is operator intent over network topology, not architectural intent predicates over software components.
- **Topological scheduling (Kahn 1962)** — generic topological sort over a DAG; no architectural predicate input.

### C. LLM-orchestrated multi-agent systems

- **AutoGen** (Wu et al., arXiv 2308.08155) — LLM-conversational decomposition; no declarative schema.
- **MetaGPT** (Hong et al., ICLR 2024; arXiv 2308.00352) — Standard Operating Procedures (SOPs) encoded as prompt sequences. SOP is procedural role ordering, not a declarative predicate algebra.
- **ChatDev** (Qian et al., arXiv 2307.07924) — sequential chat chain, no predicates.
- **CN119377360B** (CNIPA granted 2025-05-16, Daguan Data) — LLM + RPA SOP knowledge graph ontology; SOP-based procedural reasoning, not declarative predicate scheduling.
- **LangGraph** (LangChain) — Pregel-inspired super-step execution over a developer-wired graph; no formal soundness, no content addressing.

### D. Workflow / Petri-net soundness and formal verification

- **van der Aalst (2011, Springer) and Blondin et al. (2022)** — classical Workflow-net / Petri-net soundness theory; applied to hand-authored WF-nets, not to LLM-agent decomposition under architectural intent predicates.
- **Agentproof** (Xavier et al., arXiv 2603.20356) — static structural verification of authored agent workflow graphs with formal soundness proofs (reachability, dead-end, router shape, human gate, tool declaration). Verifies an already-authored graph; does not couple predicates to a decomposition scheduler.
- **Lean4Agent** (arXiv 2606.06523) — three-layer formal verification (structural / static-semantic / execution-trajectory) using Lean 4 / dependent types. Predicate System + Semantic Workflow Graph; certifier not orchestrator.

### E. Constraint-satisfaction / SAT-solver approaches to agent decomposition

- **ACONIC** (Zhou et al., arXiv 2510.07772, Oct 2025) — closest academic prior art to Pillar (A). Models LLM task as a CSP; uses 3-SAT reduction + formal complexity measures to guide decomposition. Constraints are *task-level* (sub-formulas of a Boolean query / SQL query), not *architectural-level*. Targets single-query reliability, not multi-agent workflow scheduling. No soundness verification of the generated decomposition.
- **Peña, Hinchey, Ruiz-Cortés (NASA GSFC, 2006, NASA/TR-2006-46736)** — feature-model CSP derivation for multi-agent system product lines. Closest published work modeling feature-model predicates over MAS as scheduling-relevant; uses feature models for *architectural derivation at design time*, not for runtime task scheduling under architectural intent predicates.

### F. Software product line / feature-model scheduling

- **Kang et al. (FODA, 1990); Mendonça, Wasowski, Czarnecki (SPLC 2009); Sundermann et al. (VaMoS 2020, 2024); Configurable Job-Shop Scheduling (ACM 2025, dl.acm.org/doi/10.1145/3715340.3715431)** — feature-model constraint solving for product configuration and job-shop scheduling. Generic SAT/CP-SAT theory, not coupled to LLM agent runtime.

### G. Pure retrieval / code-aware RAG

- **Aider repomap** (aider.chat/2023/10/22/repomap.html) — tree-sitter + PageRank symbol graph for context selection into a single LLM call.
- **Cursor codebase indexing** (cursor.com/blog/secure-code-codebase-indexing) — Merkle-tree chunked embeddings for retrieval.
- **Sourcegraph Cody** (sourcegraph.com/blog) — keyword/embedding/graph retrievers over code; no architectural predicate model.
- **Repository Intelligence Graph (RIG)** (arXiv 2601.10112) — build/test-artifact-derived architectural map; no predicate algebra.
- **Codebase-Memory** (arXiv 2603.27277v1) — Tree-Sitter KG via MCP; code-derived.
- **Backstage Software Catalog + AIContext RFC #33575** — typed YAML service catalog with `dependsOn`, `system`, `lifecycle`. At service-organization granularity, not internal component composition; AIContext is proposed for retrieval, not DAG pruning.

### H. Build-system dependency queries

- **Bazel query + LLM agent** (flurrylab Medium, 2025; Bazel Build, bazel.build) — Bazel dependency graph as context for an LLM agent. Build graph models only deps; no architectural intent predicates.
- **Intent Engineering** (arXiv 2603.09619) — encodes organizational goals and trade-offs into agent infrastructure; concept paper, not system.

### I. Content provenance / SBOM / AI-BOM

- **Prompt Provenance** (SSRN 5682942) — prompt-level provenance; no plan / context-slice / generated code in the hash root.
- **SPICE Intent Chain** (IETF draft-mw-spice-intent-chain-00, March 2026; JPMorgan Chase, Oracle, Telefonica, Aryaka) — Merkle-chained signed records; explicitly accommodates non-deterministic entries; content provenance log, not bit-identical CBOM from a four-input tuple.
- **Zhou et al.** (arXiv 2603.14332, March 2026) — cryptographic binding for agent tool use; X.509 v3 + skills-manifest hash + reproducibility commitments via near-determinism (F1=0.876). Does not content-address plan, context-slice, or generated code.
- **ActiveGraph** (Nakajima, arXiv 2605.21997, May 2026) — byte-reproducible agent runs via content-addressed LLM-response cache keyed on the LLM request hash. Achieves byte-reproducibility via replay; CBOM equivalent is the full event log.
- **AI-BOM / CycloneDX ML-BOM / SPDX 3.0 AI Profile** (arXiv 2504.16743) — static supply-chain inventory of AI components; not runtime CBOM.
- **Reproducible Builds ecosystem** (Debian / Nix / Guix; arXiv 2104.06020) — bit-identical build artifacts from source + environment + instructions; applied to compiled binaries, not LLM agent orchestration.

### J. Intent-Based Networking terminology (homonym disambiguation)

- **RFC 9315** (Clemm et al., IETF NMRG, October 2022) — Intent-Based Networking. "Intent" here is a declarative *network-behavior* goal, NOT architectural intent over software components.
- **draft-feng-nmrg-ain-architecture-00** (April 2026) — explicitly disambiguates IBN from "Agentic Intent Network" (AIN): *"AIN intents are routable requests for AI-agent capability invocation. IBN intents are declarative goals for network behavior management. The two are complementary."*

The present invention is not in the field of network intent. The term "architectural intent predicate" as used herein means a declarative constraint over software components (`select_one_of`, `select_subset_of`, `optional`, `phase`, `cross_cutting`, `blocks`, `invariant`), used as a scheduling primitive for LLM agent decomposition. See Section IX (Definitions).

---

## V. Summary of the Invention

The invention provides three coupled inventive elements that, in combination, solve the problem of *intent-sound, content-addressed, bit-reproducible LLM agent orchestration*:

**(V.1) Declarative architectural intent predicate set** carried by a typed project model. The predicates are *not derivable* from the source code, build manifest, or runtime traces. The predicate set comprises at least one of: a selection predicate expressing mutual exclusion among a set of components; an optionality predicate expressing on-demand enablement; a phase predicate expressing temporal ordering; a cross-cutting predicate expressing injection of a concern into a set of components; a blocker predicate expressing prerequisite relationships among decomposition tasks; and an invariant predicate expressing a property to be preserved by every wave of the schedule.

**(V.2) Provably intent-sound wave decomposition.** A decomposition engine consumes the project model and emits a wave schedule — a partition of the work into parallel waves such that each wave's leaf agents depend only on completed waves and on declared invariants. The decomposition engine emits a machine-checkable proof that for every emitted wave and every leaf agent, no declared intent predicate is violated. The proof is bound to the resolved schedule and to the predicate set.

**(V.3) Content-addressed Context Bill of Materials (CBOM).** The orchestration run is fully content-addressed: the CBOM compactly commits to (i) a hash of the project model declaration, (ii) a hash of the resolved wave plan, (iii) hashes of the context-slices handed to each leaf agent, (iv) hashes of the generated code artifacts produced by each leaf agent, and (v) a hash of the soundness proof. Given the same five hash-addressed inputs, the orchestrator emits a bit-identical CBOM artifact without re-execution of the language-model inference.

---

## VI. Brief Description of the Drawings

[To be added by attorney. Suggested figures: (FIG. 1) block diagram of the orchestration system; (FIG. 2) example project model with intent predicates; (FIG. 3) example wave schedule with soundness proof; (FIG. 4) example CBOM; (FIG. 5) data flow showing content-addressed inputs → deterministic orchestrator → bit-identical CBOM output.]

---

## VII. Detailed Description of the Invention

[To be drafted by attorney. The detailed description must enable a person of ordinary skill in the art to make and use the invention without undue experimentation, satisfying 35 U.S.C. § 112(a). The detailed description should reference the working artifacts in the simple_model repository: `struct.json`, `bootstrap.sh`, `generators/orchestrate_decompose.sh`, `generators/orchestrate_bound.sh`, `generators/orchestrate_gate.sh`, `generators/git_dispatch.sh`, `generators/cbom_emit.sh`, `specs/cbom-schema.json`, `specs/intent-model.json`.]

---

## VIII. Claims

### Independent Claim 1 — Method for intent-sound divide-and-conquer orchestration

**1.** A computer-implemented method for orchestrating a plurality of language-model agents performing a software-modification task against a software project, the method comprising:

- **(a)** receiving, at a processor, a declarative project model of the software project, the project model comprising:
  - (i) a plurality of components organized into one or more modules, each component declaring at least one of an export, an import, an optionality flag, and a list of cross-cutting concerns to which the component subscribes;
  - (ii) a typed architectural intent predicate set comprising one or more predicates selected from the group consisting of: a selection predicate expressing mutual exclusion among a set of components; an optionality predicate expressing on-demand enablement of a component; a phase predicate expressing a temporal ordering constraint over components; a cross-cutting predicate expressing injection of a concern into a designated set of components; a blocker predicate expressing a prerequisite relationship between two decomposition tasks; and an invariant predicate expressing a property to be preserved across every wave of a schedule;
  - (iii) a task list comprising a plurality of decomposition tasks each associated with a respective subset of components;
- **(b)** deterministically computing, by a decomposition engine executing on the processor and without invoking any language model of the plurality of language-model agents, a wave schedule that partitions the task list into a sequence of parallel waves, each wave identifying a set of leaf tasks whose dependencies are satisfied by tasks in earlier waves, wherein the decomposition engine:
  - (i) consumes the typed architectural intent predicate set as a pruning operand, such that candidate waves violating any selection, optionality, phase, cross-cutting, blocker, or invariant predicate are eliminated from consideration prior to wave assignment;
  - (ii) emits, as a machine-checkable proof artifact, a soundness certificate establishing that for every emitted wave and for every leaf task in every emitted wave, none of the predicates of the typed architectural intent predicate set is violated;
- **(c)** for each leaf task in each emitted wave, bounding a context slice handed to the language-model agent assigned to that leaf task, the context slice being derived from the project model and comprising at least one of: the exports and imports of the components associated with the leaf task; the cross-cutting concerns subscribed by the components associated with the leaf task; and a hashed identifier of each other leaf task whose outputs the language-model agent is permitted to consume;
- **(d)** receiving, from the language-model agents assigned to the leaf tasks, generated code artifacts;
- **(e)** verifying, by a deterministic gate-merging engine executing on the processor, that each generated code artifact satisfies the contract declared by the leaf task's associated components and that the merge of all generated code artifacts satisfies the invariant predicates of the typed architectural intent predicate set, wherein the gate-merging engine rejects any merge that would violate a contract or invariant predicate;
- **(f)** emitting, by the processor, a content-addressed Context Bill of Materials (CBOM) comprising: a hash of the project model declaration; a hash of the wave schedule; a hash of each context slice handed to a leaf task; a hash of each generated code artifact accepted by the gate-merging engine; and a hash of the soundness certificate; wherein the CBOM is bit-identical when emitted twice from the same five hashes.

### Independent Claim 2 — Method and system for content-addressed Context Bill of Materials for bit-reproducible agent orchestration

**2.** A computer-implemented method for bit-reproducible orchestration of language-model agents, the method comprising:

- **(a)** receiving, at a processor, a tuple of five content-addressed inputs comprising:
  - (i) a project-model hash H_D computed from a typed declarative project model comprising a plurality of components and a typed architectural intent predicate set;
  - (ii) a plan hash H_P computed from a wave schedule partitioning a plurality of decomposition tasks into a sequence of parallel waves;
  - (iii) a context-slice hash H_C computed from a context slice handed to a language-model agent assigned to a leaf task;
  - (iv) a code hash H_K computed from a generated code artifact produced by the language-model agent;
  - (v) a proof hash H_S computed from a soundness certificate establishing that the wave schedule does not violate any predicate of the typed architectural intent predicate set;
- **(b)** deterministically computing, by an orchestrator executing on the processor and without invoking any language model, a Context Bill of Materials (CBOM) artifact whose contents are a function solely of (H_D, H_P, H_C, H_K, H_S);
- **(c)** emitting the CBOM artifact, wherein the CBOM artifact is bit-identical when emitted twice from the same tuple (H_D, H_P, H_C, H_K, H_S).

### Independent Claim 3 — Article of manufacture / non-transitory computer-readable medium

**3.** A non-transitory computer-readable medium storing a declarative project model of a software project, the project model comprising:

- **(a)** a schema describing a plurality of components organized into one or more modules, each component declaring at least one of an export, an import, an optionality flag, and a list of cross-cutting concerns to which the component subscribes;
- **(b)** a typed architectural intent predicate set comprising one or more predicates selected from the group consisting of: a selection predicate expressing mutual exclusion among a set of components; an optionality predicate expressing on-demand enablement of a component; a phase predicate expressing a temporal ordering constraint over components; a cross-cutting predicate expressing injection of a concern into a designated set of components; a blocker predicate expressing a prerequisite relationship between two decomposition tasks; and an invariant predicate expressing a property to be preserved across every wave of a schedule;
- **(c)** a task list comprising a plurality of decomposition tasks each associated with a respective subset of components and each having a status selected from {pending, in_progress, done};
- **(d)** a self-cognition association linking each component to one or more orchestration operations that derive from the component, the orchestration operations comprising at least one of: a decomposition of the component into one or more leaf tasks; a bounding of a context slice for a leaf task; and a gate-merging contract for accepting output of a leaf task;
- **(e)** a self-memory association linking the project model to one or more CBOM artifacts, each CBOM artifact comprising a hash of the project model, a hash of a wave schedule, a hash of each context slice handed to a leaf task, a hash of each generated code artifact, and a hash of a soundness certificate;

wherein the predicates of (b) are not derivable from any of the source code, the build manifest, or the runtime traces of the software project.

### Dependent Claims

**4.** (Dependent on Claim 1, 2, or 3) The method / system / medium, wherein the typed architectural intent predicate set comprises an invariant predicate expressing that no emitted wave violates a declared global property selected from the group consisting of: an import-graph acyclicity property; a cross-cutting-injection completeness property; a phase-ordering property; and a blocker-resolution property.

**5.** (Dependent on Claim 1, 2, or 3) The method / system / medium, wherein the language-model agents assigned to leaf tasks are selected from a plurality of heterogeneous language-model workers, the method further comprising: invoking, by the orchestrator, any selected language-model worker via a uniform invocation protocol accepting a context slice and a contract and returning a generated code artifact and a bounded summary; wherein the orchestrator is agnostic to the identity of the selected language-model worker.

**6.** (Dependent on Claim 1, 2, or 3) The method / system / medium, wherein the decomposition engine, the gate-merging engine, and the CBOM emitter collectively require, at runtime, no dependencies other than a POSIX-compatible shell interpreter and a JSON query tool, the system being invokable as a child process by an external language-model agent loop.

**7.** (Dependent on Claim 1) The method, wherein each leaf task of each emitted wave is dispatched to a respective language-model agent in a respective isolated filesystem worktree, and wherein results from the language-model agents are merged by the gate-merging engine only after each language-model agent's worktree is validated against the leaf task's contract.

**8.** (Dependent on Claim 1 or 2) The method, wherein the soundness certificate is a Lean 4, Coq, or Isabelle proof artifact, and wherein the soundness certificate is independently verifiable by a third-party verifier without reference to the orchestrator that emitted it.

**9.** (Dependent on Claim 1 or 3) The method / medium, wherein the typed architectural intent predicate set is expressed in a JSON-Schema-validated syntax, and wherein the predicates are machine-checkable by a deterministic predicate validator that does not invoke any language model.

**10.** (Dependent on Claim 3) The medium, further comprising a dual-audience interface specification, the dual-audience interface specifying, for each component, both a human-developer-facing display format and a language-model-agent-facing context format, the two formats being derived from a single project-model entry.

**11.** (Dependent on Claim 1) The method, wherein the typed architectural intent predicate set comprises a cross-cutting predicate, and wherein the decomposition engine injects, into each leaf task associated with a component subscribed to the cross-cutting concern, a fragment of code derived from the cross-cutting concern, the fragment being determined by the decomposition engine and being identical across all leaf tasks associated with the same cross-cutting concern.

**12.** (Dependent on Claim 2) The method, wherein the orchestrator further emits, for each emitted CBOM artifact, a drift detection report identifying any divergence between the CBOM artifact and a previously emitted CBOM artifact, the drift detection report being derived by deterministic comparison of the respective hashes of the CBOM artifacts.

**13.** (Dependent on Claim 1) The method, wherein the wave schedule further comprises, for each emitted wave, a determinism contract specifying that the wave is reproducible from the project model and the prior wave's generated code artifacts, without requiring re-execution of any language-model inference.

---

## IX. Definitions

For purposes of the claims, the following terms shall have the meanings set forth below.

- **"Architectural intent predicate"** means a declarative constraint over software components that is not derivable from the source code, build manifest, or runtime traces of the software project. Architectural intent predicates include, without limitation: `select_one_of` (mutual exclusion among a set of components — exactly one is selected for any given configuration); `select_subset_of` (a subset of components is selected under a given configuration); `optional` (on-demand enablement of a component); `phase` (temporal ordering constraint over components); `cross_cutting` (injection of a concern into a designated set of components); `blocks` (a prerequisite relationship between two decomposition tasks); and `invariant` (a property to be preserved across every wave of a schedule). The term is distinct from "intent" as used in Intent-Based Networking (RFC 9315), which refers to a network-behavior goal.

- **"Content-addressed"** means that an artifact is identified by the cryptographic hash of its contents, such that two artifacts with identical contents have identical identifiers.

- **"Wave schedule"** means a partition of a plurality of decomposition tasks into a sequence of parallel waves, each wave identifying a set of leaf tasks whose dependencies are satisfied by tasks in earlier waves.

- **"Soundness certificate"** means a machine-checkable proof artifact establishing that a wave schedule does not violate any predicate of a typed architectural intent predicate set.

- **"Context slice"** means the bounded input handed to a language-model agent assigned to a leaf task, the bounded input being derived from the project model and comprising at least the exports and imports of the components associated with the leaf task.

- **"Context Bill of Materials (CBOM)"** means a content-addressed runtime provenance artifact that compactly commits to the hashes of (i) a project-model declaration, (ii) a wave schedule, (iii) one or more context slices, (iv) one or more generated code artifacts, and (v) a soundness certificate, such that the CBOM is bit-identical when emitted twice from the same five hashes.

- **"Bit-identical"** means that two artifacts are byte-for-byte identical when compared at the bit level, without requiring semantic-equivalence classifiers, replay of any language-model inference, or human interpretation.

---

## X. Abstract

A method, system, and article of manufacture for intent-sound divide-and-conquer orchestration of language-model agents. A declarative project model carries a typed architectural intent predicate set that is not derivable from source code, build manifests, or runtime traces. A deterministic decomposition engine consumes the predicate set as a pruning operand to compute a wave schedule, emitting a machine-checkable soundness certificate. Each leaf task is assigned to a language-model agent with a bounded context slice derived from the project model. Generated code artifacts are merged by a deterministic gate-merging engine that rejects any merge violating a contract or invariant. A content-addressed Context Bill of Materials (CBOM) compactly commits to the hashes of the declaration, plan, context slices, generated code, and soundness certificate, enabling bit-reproducible orchestration without re-execution of language-model inference.

---

## XI. Per-claim go / narrow / no-go verdict

This section is intended as input to the patent attorney's claim-construction strategy, not as a substitute for attorney judgment.

| Claim | Verdict | Justification |
|---|---|---|
| **1 (independent)** — intent-sound divide-and-conquer orchestration | **NARROW GO** | Novel combination of (A) + (B) + (c-step) + (e-step). Must disclaim explicitly around Agentproof (§3.4), Lean4Agent (§3.17), ACONIC (§3.20b), Peña 2006 (§3.20c), and the classical WF-net / feature-model literature (§3.18, §3.19). Recommend the predicate-type enumeration in step (a)(ii) be the anchor of the claim, with the soundness certificate in step (b)(ii) being the second anchor. |
| **2 (independent)** — content-addressed CBOM for bit-reproducible orchestration | **GO (with carve-outs)** | Novel combination of four-input hash tuple + compact CBOM artifact + bit-identical without replay. Must disclaim explicitly around ActiveGraph (§3.14), SPICE Intent Chain (§3.15), Zhou et al. (§3.16), and Prompt Provenance (§3.13). Recommend the "five hashes" formulation in step (a) and the "bit-identical without re-execution" formulation in step (c) as the anchor. |
| **3 (independent)** — declarative project model carrying non-code-recoverable intent predicates + self-cognition/self-memory associations | **GO** | Novel combination of declarative schema + non-code-recoverable predicates + dual-audience (self-cognition + self-memory) association. Must disclaim explicitly around Backstage catalog-info.yaml + AIContext RFC (§3.20e), Cursor / Aider / Cody / RIG / Codebase-Memory (§3.9, §3.10, §3.20f), and Intent Engineering (§3.20g). Recommend the "not derivable from any of the source code, the build manifest, or the runtime traces" limitation as the anchor. |
| **4 (dependent)** — invariant predicate | **GO** | Distinguishable from MetaGPT SOP roles (procedural, no predicate algebra) and feature-model `requires` / `excludes` (configuration selection, not LLM agent decomposition). |
| **5 (dependent)** — multi-LLM leaf-worker agnostic adapters | **GO** | Nothing in prior art claims the "agent-agnostic uniform invocation protocol" combination. Distinguishable from Conductor (Python+Jinja2), Praetorian (Claude Code-specific), LangGraph (Python+LangChain). |
| **6 (dependent)** — zero-dep bash+jq lightweight primitive | **GO** | Nothing in prior art claims the "git-like portable primitive" combination. Strongest daylight. |
| **7 (dependent)** — worktree-isolated parallel dispatch | **GO** | Distinguishable from generic CI worktree patterns (git worktree is generic; worktree isolation driven by an intent-sound wave schedule is novel). |
| **8 (dependent)** — Lean 4 / Coq / Isabelle soundness certificate | **GO** | Distinguishable from Agentproof (Appendix A proofs are paper-only, not an emitted artifact), Lean4Agent (Lean 4 verification but of an authored workflow, not a wave schedule). |
| **9 (dependent)** — JSON-Schema-validated predicate syntax | **GO** | Distinguishable from feature-model XML syntax (no JSON Schema; not coupled to LLM agent scheduling). |
| **10 (dependent)** — dual-audience interface | **GO** | Distinguishable from CLAUDE.md (single-audience context file; no machine-checkable predicate). |
| **11 (dependent)** — cross-cutting injection into leaf tasks | **GO** | Distinguishable from generic aspect-oriented programming (no scheduling-pruning role; not coupled to LLM agent decomposition). |
| **12 (dependent)** — CBOM drift detection | **GO** | Distinguishable from generic diff tools (drift is over CBOM hashes, not over source files; no LLM involvement). |
| **13 (dependent)** — per-wave determinism contract | **GO** | Distinguishable from Conductor's "deterministic routing" (control-flow determinism; no bit-identical CBOM). |

---

## XII. Residual risks requiring attorney action

These residual risks cannot be cleared by open-web prior-art search alone and must be addressed before non-provisional filing:

1. **Unpublished / pending patent applications.** The most common mode of preemption not visible on the open web. A professional Freedom-to-Operate (FTO) search of USPTO PAIR, EPO Espacenet, JPO IPDL, and CNIPA 公布公告 is mandatory before non-provisional filing.

2. **CN119645662B (Peking University — "Complex Task Intelligent Planning Execution")** — **MEDIUM risk** identified by the Chinese-patent research; the highest-priority follow-up. Title suggests planning; full claim-text read required before any FTO opinion. Recommend attorney's CNIPA search on Lens.org with the structured query (`"intent" OR "predicate"`) AND (`"agent" OR "智能体"`) AND (`"scheduling" OR "调度" OR "编排"`) filtered to CN jurisdiction 2024–2026.

3. **Continuation filings of US20260017525A1** (*Validating autonomous AI agents*) — assignee should be checked for continuation chain covering agent-orchestration content-addressing.

4. **EigenAI patent filings** — EigenAI claims bit-for-bit deterministic inference on GPUs. If they have a continuation covering "deterministic LLM agent orchestration using deterministic inference," our Pillar (C) daylight narrows.

5. **IETF SPICE Intent Chain RFC-track progression** — draft-mw-spice-intent-chain-00 is on the IETF agenda. If it progresses to RFC status (within 12–24 months), it becomes standard-essential prior art for *content provenance* claims. Our Pillar (C) daylight survives because we claim *bit-identical CBOM from a four-input tuple*, not just content provenance.

6. **Unpublished Microsoft, Anthropic, Cognition/Devin, and Google work** — Conductor is open-source MIT, but Microsoft has a substantial patent portfolio on agent orchestration. Devin's planning architecture and Anthropic's Claude Code sub-agent architecture may be patented. Cannot be cleared by web search alone.

7. **Academic preprint → patent pipeline** — Lean4Agent (arXiv 2606.06523) and ACONIC (arXiv 2510.07772) are recent preprints by groups with industry ties. If continuation patents are filed on predicate-system + scheduling integration, our Pillar (A)/(B) daylight could narrow.

8. **The "agent" terminology is contested** in patent law post-2024 USPTO guidance (per Baker Botts / Greenberg Traurig commentary, Nov 2025). Recommend attorney review of USPTO Patent Subject Matter Eligibility guidance (2024 Revisions) before claim finalization, especially for any "AI agent" claim language.

---

## XIII. Recommendations to the patent attorney

1. **File a provisional application immediately.** The provisional establishes priority date and gives 12 months to convert. Given the fast-moving 2024-2026 prior art landscape (Conductor 2026-05, Praetorian 2025-11, Agentproof 2026-03, ActiveGraph 2026-05, Lean4Agent 2026-06, ACONIC 2025-10), waiting risks prior art catching up.

2. **Lead with the (A)+(B)+(C) combination.** Each pillar individually has known ancestors; the combination is novel. Do not draft three separate independent claims that read independently on (A), (B), (C) — draft the combination, then narrow with dependent claims.

3. **Anchor Claim 1 on the predicate-type enumeration in step (a)(ii).** The seven predicate types (`select_one_of`, `select_subset_of`, `optional`, `phase`, `cross_cutting`, `blocks`, `invariant`) are the closest thing to a load-bearing novelty element. ACONIC's task-level constraints are the closest competitor; distinguish on (i) architectural-level vs task-level, (ii) soundness verification vs not, (iii) declarative specification language vs not.

4. **Anchor Claim 2 on the five-hash tuple.** ActiveGraph's LLM-request hash is the closest competitor; distinguish on (i) five-hash tuple vs LLM-request-only, (ii) compact artifact vs full event log, (iii) bit-identical without replay vs replay-based.

5. **Anchor Claim 3 on the "not derivable from source code, build manifest, or runtime traces" limitation.** Backstage's catalog-info.yaml is the closest competitor; distinguish on (i) architectural decomposition granularity vs service-organization granularity, (ii) predicate richness, (iii) consumer (scheduler + soundness + CBOM vs RAG retrieval).

6. **Include the working artifacts in the provisional.** Reference `struct.json`, `bootstrap.sh`, the `generators/orchestrate_*.sh` files, `specs/cbom-schema.json`, `specs/intent-model.json`, `tests/test_chimeric_e2e.sh`, `tests/test_intent_validate.sh`, `tests/test_decompose_sound.sh`, `tests/test_cbom.sh`, `tests/test_dnc_demo.sh`, `examples/dnc-demo/`. The working artifacts are the strongest evidence of enablement and reduction to practice.

7. **Reserve the dependent claims.** The 13 dependent claims listed in Section VIII are written defensively; the attorney should select those that narrow the broadest interpretation of the independent claims most tightly, and drop the rest to avoid claim-fee bloat.

8. **Convert to non-provisional before 12 months elapse.** Plan the conversion around 2027 Q3, after (i) the attorney's FTO search is complete, (ii) the demo (`examples/dnc-demo/`) has been demonstrated publicly, (iii) any post-filing prior art discovered during the priority year has been analyzed.

---

## XIV. Inventor's declaration

[To be added by attorney. Each named inventor must declare (a) citizenship, (b) residence, (c) review of the application, (d) belief in the originality of the claimed invention, (e) acknowledgment of the duty to disclose prior art known to the inventor.]

---

*— end of provisional claim architecture draft —*