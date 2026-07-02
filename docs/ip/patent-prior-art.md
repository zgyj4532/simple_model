# Patent Prior-Art Research Report

**Project:** simple_model — "Project Intelligence" (intent-sound divide-and-conquer orchestration)
**Inventive thesis under test:** Three inventive pillars (A) intent predicates as scheduling-pruning primitive, (B) provable soundness w.r.t. those predicates, (C) content-addressed CBOM for bit-reproducible orchestration.
**Research date:** 2026-07-02
**Researcher scope:** Open-web patent DBs, arXiv, ACL Anthology, ACM DL, IEEE Xplore (free), IETF drafts, vendor blogs, OSS READMEs. **NOT searched:** USPTO PAIR (full text), CNIPA 公布公告 (Chinese-language), Espacenet CPC classification tree, paid patent DBs (Derwent, PatSnap). All searches were English + Chinese keywords.

---

## 1. Executive Verdict (per claim)

| Claim | Verdict | Residual risk |
|---|---|---|
| **Claim 1** (independent method): intent-sound divide-and-conquer orchestration | **NARROW GO** | Must disclaim explicitly around Lean4Agent / Agentproof (soundness) and around ReSo (DAG-wave decomposition). Must distinguish "architectural intent predicates" from Confucius "operator intent over network topology" and from feature-model scheduling literature. |
| **Claim 2** (independent method/system): content-addressed CBOM for bit-reproducible orchestration | **GO (with carve-outs)** | Must disclaim around ActiveGraph (byte-reproducible agent log replay), SPICE Intent Chain (IETF content provenance), Zhou et al. arXiv 2603.14332 (cryptographic binding for agent tool use), Prompt Provenance (SSRN, prompt-only). Closest adversary = ActiveGraph. Daylight = our four-input tuple (declaration + plan + context-slice + code) hash-addressed to produce a *compact CBOM artifact*, not a replayed full event log. |
| **Claim 3** (article of manufacture / data structure): declarative project model carrying non-code-recoverable intent predicates + self-cognition/self-memory associations | **GO** | Closest competitor = Cursor / Aider / Cody / Conductor project context files. None model a typed predicate algebra (mutual-exclusion / optional / phase / cross-cutting / invariant). Daylight is well-established. |
| **Dependent claim** (invariant predicate) | **GO** | Distinguishable from MetaGPT SOP roles (linear ordering, no formal predicate) and feature-model `requires` / `excludes` constraints (not coupled to LLM agent scheduling). |
| **Dependent claim** (multi-LLM leaf-worker agnostic adapters, zero-dep bash+jq) | **GO** | Nothing in prior art claims the "git-like portable primitive" combination. Distinguishable from Conductor (Python+Jinja2), Praetorian (Claude Code-specific), LangGraph (Python+LangChain). |

**Overall filing posture:** **NARROW GO.** File a provisional around the (intent-sound + CBOM) combination, with explicit disclaimers. Recommend human patent attorney review before non-provisional filing because: (1) the Lean4Agent / Agentproof soundness overlap needs claim-narrowing, (2) the IETF SPICE Intent Chain may converge into RFC-track prior art within 12-24 months, (3) unpublished / pending applications cannot be verified by web search — an attorney search of PAIR/CNIPA is required before non-provisional filing.

---

## 2. The Three Inventive Pillars (anchor for prior-art test)

**Pillar (A) — Intent predicates as scheduling-pruning primitive.** The data structure (a) carries architectural intent predicates — `select_one_of`, `select_subset_of`, `optional`, `phase`, `cross_cutting`, `blocks`, `invariant` — that are *not derivable from the source code* and (b) these predicates are consumed by the scheduler as operands of a topological-wave planning algorithm *before* an agent is invoked, so that the candidate execution space is pruned declaratively.

**Pillar (B) — Provable soundness guarantee w.r.t. those predicates.** Given an intent-predicate set P and a computed schedule S (the wave plan), the system emits a machine-checkable proof that for every wave and every leaf agent, no declared predicate in P is violated. The proof is bound to the resolved schedule, not to a separate hand-written LLM workflow.

**Pillar (C) — Content-addressed CBOM for bit-reproducible orchestration.** The orchestration run is fully content-addressed: given the same four hash-addressed inputs (declaration, plan, context-slice, generated code), the orchestrator emits a *bit-identical* CBOM artifact — without re-execution of the LLM, without semantic-equivalence classifiers. The CBOM compactly encodes the four inputs by hash, the resolved schedule by hash, and the soundness proof by hash.

---

## 3. Per-prior-art deep-read

### 3.1 Microsoft Conductor (2026-05)

- **Primary source:** *Conductor: Deterministic orchestration for multi-agent AI workflows*, Microsoft Open Source Blog, 2026-05-14. https://opensource.microsoft.com/blog/2026/05/14/conductor-deterministic-orchestration-for-multi-agent-ai-workflows/ — repository at https://github.com/microsoft/conductor (MIT-licensed).
- **Author / organization:** Jason Robert, Microsoft.
- **Verbatim claim (key quote):** *"Conductor is an open-source CLI (MIT license, Microsoft org) that takes a different approach: you define your multi-agent workflows in YAML, and the routing between agents is deterministic. Jinja2 templates and expression evaluation handle conditions and branching. The orchestration layer consumes zero tokens. The structure is fixed at definition time—and that's the point."*
- **What it does:** Multi-agent workflows declared in YAML. Each agent has isolated session, system prompt, model, provider, temperature. Three context modes: accumulate / last_only / explicit. Routing via Jinja2 conditionals, "first matching condition wins." Parallel `parallel:` groups with `failure_mode: continue_on_error | fail_fast | all_or_nothing`. Web dashboard with DAG visualization.
- **What it does NOT do:** No intent predicate algebra. No soundness guarantee. No content-addressing. Routing topology is hand-authored (YAML). Stochastic LLM calls remain stochastic (uses claude-opus-4.6-1m, claude-haiku-4.5, gpt-5.2 etc., not pinned to temperature=0). "Determinism" refers to control flow only.
- **Comparison to pillars:**
  - (A) **No** — YAML declares routing topology only; no predicate algebra; the graph is not *derived from* intent predicates; no scheduling pruning.
  - (B) **No** — no soundness proof, no constraint-preservation guarantee; only `conductor validate` schema lint.
  - (C) **No** — no content addressing; outputs of stochastic LLM calls are not bit-identical.
- **Verdict:** Pre-empts nothing. Close-kin only on the "deterministic orchestration" axis — must disclaim.

### 3.2 Praetorian Development Platform (2025–2026)

- **Primary source:** *Deterministic AI Orchestration: A Platform Architecture for Autonomous Development*, Praetorian, 2025-11. https://www.praetorian.com/blog/deterministic-ai-orchestration-a-platform-architecture-for-autonomous-development/ (companion post: https://medium.com/@praetorianguard/deterministic-ai-orchestration-what-we-learned-building-a-39-agent-development-platform-7a1d66bd523f).
- **Verbatim claim:** *"This paper details the architecture of the Praetorian Development Platform, which solves these problems by treating the Large Language Model (LLM) not as a chatbot, but as a nondeterministic kernel process wrapped in a deterministic runtime environment."* *"The architecture is defined by one hard constraint in the Claude Code runtime: Sub-agents cannot spawn other sub-agents."*
- **Architecture:** 5-layer enforcement (CLAUDE.md → Skills → Agent definitions → UserPromptSubmit hooks → PreToolUse hooks → PostToolUse hooks → SubagentStop hooks → Stop hooks). 16-phase state machine. 39 specialized agents, 350+ managed prompts. 530k-line codebase, 32 modules. Dual state (ephemeral hooks + persistent `MANIFEST.yaml`). Skill library split into tier-1 (49 high-frequency skills) and tier-2 (304+ specialized skills). "Thin Agent / Fat Platform" — workers strictly <150 lines.
- **"Intent-Based Context Loading":** The closest Praetorian analog to intent. *"Agents do not hardcode library paths. They invoke a Gateway Skill (e.g., gateway-frontend), which acts as a dynamic router based on intent detection. This implements Intent-Based Context Loading, ensuring agents only load the specific patterns relevant to their current task rather than the entire domain knowledge base."*
- **Crucial distinction:** Praetorian's "intent" is *semantic intent classification* — a router picks the right skill library based on the LLM's reading of the request. It is **not** a *declared, typed architectural predicate* consumed by a scheduler. The Gateway is itself an LLM-mediated router, not a deterministic predicate algebra.
- **What it does NOT do:** No formal soundness guarantee (the "loop detection" is string-similarity heuristic, not proof). No content-addressed CBOM (state is persisted to `MANIFEST.yaml` and JSONL session transcripts, not hash-addressed). No declarative predicate algebra.
- **Comparison to pillars:**
  - (A) **No** — "intent" is semantic, not declarative; no predicate algebra.
  - (B) **No** — enforcement is by hooks, not proofs.
  - (C) **No** — no content addressing.
- **Verdict:** Pre-empts nothing. Heavy overlap with the "deterministic orchestration / LLM-as-component / contract gate" axis that the project's own `todo.json` already lists as `what_is_NOT_novel_do_not_claim`.

### 3.3 ReSo (EMNLP 2025)

- **Primary source:** Zhou et al., *ReSo: A Reward-driven Self-organizing LLM-based Multi-Agent System for Reasoning Tasks*, EMNLP 2025 main proceedings (pp. 15979–15998). https://aclanthology.org/2025.emnlp-main.808/ — arXiv 2503.02390.
- **Verbatim claim:** *"ReSo builds on prior work in agent selection and task decomposition, ReSo's task decomposition and collaborative reward models."* The DAG G=(V,E) carries only directed dependency edges `vi → vj`; there is no slot for mutual-exclusion, optionality, phase ordering, cross-cutting tags, or invariants.
- **Decomposition:** f_task constructs the decomposition DAG from the input question. Pruning is via UCB on a similarity score `Q(a,v) = sim(a,v) · perform(a)` (Eq. 5) — a *similarity heuristic over agents*, not over the schedule. Cost O((s·N + N log N + k·c)·D).
- **Soundness:** *None.* Reward model emits `r(ai,v) ∈ [0,1]`. Validity is empirical (Math-MAS, SciBench-MAS accuracy tables).
- **Content addressing:** None. Code on GitHub.
- **Comparison to pillars:**
  - (A) **Partial overlap, not pre-emption.** ReSo prunes over agents (not over the schedule). Its DAG is plain dependency edges, no architectural predicate slots.
  - (B) **No** — no proof, only empirical reward.
  - (C) **No** — no content addressing.
- **Verdict:** Pre-empts (A) not at all. Pre-empts nothing on (B) or (C). Must disclaim the topological-wave scheduling framing if not anchored on predicates.

### 3.4 Agentproof (arXiv 2603.20356) — *the formal-soundness kill-shot*

- **Primary source:** Xavier, M A, Jolly, Xavier, *Agentproof: Static Verification of Agent Workflow Graphs*, arXiv 2603.20356v1 [cs.LO], 2026-03-20. https://arxiv.org/html/2603.20356v1
- **Verbatim claim:** *"Agentproof… extracts a unified abstract graph model from four major agent frameworks (LangGraph, CrewAI, AutoGen, Google ADK), applies six structural checks with witness trace generation, and evaluates temporal safety policies via a DSL compiled to deterministic finite automata—both statically through a graph × DFA product construction and at runtime over event traces."*
- **Six structural checks** (with **formal soundness proofs** in Appendix A — Lemmas 1–9): exit reachability, reverse reachability / livelock, dead-end detection, router shape, human-in-the-loop presence/coverage, tool declaration checks.
- **Temporal DSL:** safety fragment of LTL (forbidden, implication-future, until, bounded response, response chain, conjunction, disjunction). Compiled to DFAs; **graph × DFA product construction** gives static verification over all paths.
- **Crucial distinction:** Agentproof verifies an **already-authored graph**. It checks whether the *existing* workflow graph has dead ends, unreachable exits, missing human gates, violated temporal policies. It is a *certifier*, not an *orchestrator*. The graph it consumes is hand-authored; it has **no model of architectural intent predicates** (mutual-exclusion, optional, phase, cross-cutting, invariant) and **no scheduler** that consumes such predicates.
- **Comparison to pillars:**
  - (A) **No** — no architectural predicate algebra. Reads an existing graph; does not generate one from intent.
  - (B) **CRITICAL OVERLAP.** Agentproof proves soundness of structural properties over agent workflow graphs. Our Pillar (B) must be narrowly drawn as: *"soundness w.r.t. declared architectural intent predicates (selection, optionality, phase, cross-cutting, invariant) on the wave plan produced by the decompose step, not on the topology of an already-authored graph."* Must disclaim around Agentproof's structural-soundness framing.
  - (C) **No** — no content addressing; LLM output semantics are explicitly out of scope.
- **Verdict:** This is the **closest pre-emption** of Pillar (B) *generically*. The daylight lies in (i) coupling soundness to a *declarative predicate model* rather than to an *authored graph*, and (ii) integrating soundness into the *decomposition scheduler* rather than the *post-hoc verifier*. The combination of (A) + (B) is what survives novelty.

### 3.5 MetaGPT (ICLR 2024 / arXiv 2308.00352)

- **Primary source:** Hong et al., *MetaGPT: Meta Programming for A Multi-Agent Collaborative Framework*, arXiv 2308.00352v7 (2024-11-01). https://arxiv.org/abs/2308.00352 — repo at https://github.com/foundationagents/metagpt.
- **Verbatim claim:** *"MetaGPT encodes Standardized Operating Procedures (SOPs) into prompt sequences for more streamlined workflows, thus allowing agents with human-like domain expertise to verify intermediate results and reduce errors. MetaGPT utilizes an assembly line paradigm to assign diverse roles to various agents, efficiently breaking down complex tasks into subtasks."* Core philosophy on GitHub: *"Code = SOP(Team) is the core philosophy. We materialize SOP and apply it to teams composed of LLMs."*
- **What SOP means here:** Human operating procedure (PM → Architect → ProjectManager → Engineer → QaEngineer) encoded as prompt sequences. The SOP is a *linear ordering of roles* — not a predicate algebra. Phase boundaries exist as labels but are enforced only by sequential order.
- **Soundness:** None. "Verification" is "intermediate result review" by other LLM roles (LLM-as-judge), not proof.
- **Content addressing:** None. `workspace/` of generated files; not hashed.
- **Comparison to pillars:**
  - (A) **Partial overlap, not pre-emption.** SOP captures linear role ordering; our predicates capture mutual-exclusion / optionality / phase / cross-cutting / invariant — a strictly richer model that the SOP machinery does not represent.
  - (B) **No** — no soundness proof.
  - (C) **No** — no content addressing.
- **Verdict:** Pre-empts nothing on any pillar. SOP is procedural, not declarative-predicate. Must disclaim.

### 3.6 AutoGen (arXiv 2308.08155)

- **Primary source:** Wu et al., *AutoGen: Enabling Next-Gen LLM Applications via Multi-Agent Conversation*, arXiv 2308.08155. https://arxiv.org/abs/2308.08155
- **Verbatim claim:** *"AutoGen is an open-source framework that allows developers to build LLM applications via multiple agents that can converse with each other to accomplish tasks."*
- **Decomposition:** LLM-driven conversational decomposition. No `struct.json` analog. No predicate algebra.
- **Comparison to pillars:** No overlap with any of (A)/(B)/(C).
- **Verdict:** Defines the LLM-as-orchestrator lane we explicitly *don't* claim.

### 3.7 LangGraph (LangChain)

- **Primary source:** LangGraph Graph API docs, https://docs.langchain.com/oss/python/langgraph/graph-api. Inspired by Google's Pregel system.
- **Verbatim claim:** *"At its core, LangGraph models agent workflows as graphs. You define the behavior of your agents using three key components: State, Nodes, Edges. … The program proceeds in discrete 'super-steps.' A super-step can be considered a single iteration over the graph nodes. Nodes that run in parallel are part of the same super-step."*
- **Compiling:** *"Compiling is a pretty simple step. It provides a few basic checks on the structure of your graph (no orphaned nodes, etc)."*
- **Soundness:** *None.* Checkpointing + runtime determinism are engineering guarantees, not formal soundness.
- **Content addressing:** None. Graph itself is not content-addressed; thread-scoped checkpointers persist state via `thread_id` only.
- **Predicate algebra:** None. Conditional edges (`add_conditional_edges`) are one-shot branches, not first-class predicates.
- **Comparison to pillars:** None on (A)/(B)/(C). Substrate for execution; not an orchestrator with declared predicates.
- **Verdict:** No pre-emption. The Pregel-style super-step is a useful execution substrate for our wave scheduler; no novelty claim is at risk.

### 3.8 CN119377360B (CNIPA granted patent — LLM + SOP knowledge graph + RPA)

- **Primary source:** Chinese patent CN119377360B, granted. https://patents.google.com/patent/CN119377360B/zh
- **Verbatim claim:** *"在本发明基于大语言模型协同知识图谱的AI Agent智能体中，所述RPA SOP流程知识图谱模块采用本体的方式构建，定义领域内的概念、实体、属性和关系，为知识表示和推理提供基础。"*
- **What it claims:** An AI Agent that combines LLM + a knowledge graph built via RPA SOP (Standard Operating Procedure) — defines concepts, entities, properties, and relations in a domain ontology. Uses SOP as a procedural knowledge base.
- **What it does NOT claim:** No soundness proof. No content-addressed CBOM. No scheduling-pruning via architectural intent predicates. The "SOP" here is the same procedural SOP as MetaGPT, not a typed predicate algebra.
- **Comparison to pillars:**
  - (A) **No** — uses SOP as a knowledge-graph ontology, not as a predicate algebra for the scheduler.
  - (B) **No.**
  - (C) **No.**
- **Verdict:** Pre-empts nothing. Must disclaim SOP-based decomposition explicitly.

### 3.9 Aider repomap (tree-sitter + PageRank)

- **Primary source:** *Building a better repository map with tree sitter*, Aider blog, 2023-10-22. https://aider.chat/2023/10/22/repomap.html
- **Verbatim claim:** *"Aider sends GPT a repo map to GPT along with each request from the user to make a code change. The map contains a list of the files in the repo, along with the key symbols which are defined in each file… Under the hood, aider uses tree sitter to build the map. … Aider solves this problem by sending just the most relevant portions of the repo map. It does this by analyzing the full repo map using a graph ranking algorithm, computed on a graph where each source file is a node and edges connect files which have dependencies."*
- **What it does:** Code-derived symbol graph, ranked by PageRank over the dependency edges between files, used to *select context for a single LLM call*.
- **What it does NOT do:** No architectural intent predicates. No decomposition / scheduler. No soundness. No content addressing. The map is a *retrieval* artifact for a single LLM, not a *declaration* for orchestration.
- **Comparison to pillars:** (A) **No** — code-derived only; no declarative predicates that aren't already in the source. (B) No. (C) No.
- **Verdict:** No pre-emption. Belongs to "dumb repo / smart tool" lane.

### 3.10 Cursor / Cody / Copilot

- **Primary sources:** Cursor docs (cursor.com), Sourcegraph Cody docs (sourcegraph.com), GitHub Copilot Workspace (docs.github.com).
- **What they do:** Build code-derived context indexes (embeddings, ASTs, dependency graphs) and feed them to a single LLM call. None model a declarative architectural intent predicate set. None decompose into waves. None emit content-addressed artifacts.
- **Verdict:** No pre-emption on any pillar. Pure RAG lane.

### 3.11 flurrylab — *Bazel query + LLM agent*

- **Primary source:** *Architecture and Mechanisms of Repository-Scale AI Coding Agents (2)*, Medium. https://flurrylab.medium.com/architecture-and-mechanisms-of-repository-scale-ai-coding-agents-2-0d8ef71c6ff7
- **Verbatim claim:** *"By executing commands against the Bazel query language, the agent can trace the exact dependency chain mandated by the build system."*
- **What it does:** Uses Bazel's build-dependency graph (a derived artifact from build rules) as context for an LLM agent to query / navigate a monorepo. The dependency graph models only deps, not architectural intent predicates (no mutual-exclusion, no optionality, no phase).
- **Verdict:** Pre-empts (A) not at all. The build dependency graph is a strict subset of our declarative model (deps only, no predicates). Must disclaim Bazel-style dependency-graph-as-context framing.

### 3.12 Confucius (Meta, SIGCOMM 2025) — *the strongest industrial precedent*

- **Primary source:** Wang et al., *Intent-Driven Network Management with Multi-Agent LLMs: The Confucius Framework*, SIGCOMM 2025. https://dl.acm.org/doi/10.1145/3718958.3750537 — author preprint at https://minlanyu.seas.harvard.edu/writeup/sigcomm25.pdf
- **Verbatim claim:** *"We model network management workflows as directed acyclic graphs (DAGs) to aid planning. Our framework integrates LLMs with existing management tools … employs retrieval-augmented generation (RAG) … and establishes a set of primitives to systematically support human/model interaction."* Decomposition: *"a directed acyclic graph (DAG), implemented using a Python-based DSL. Each node in the DAG represents a subtask … Independent subtasks can be executed in parallel, and the runtime environment automatically determines the optimal execution plan based on input/output dependencies."*
- **Validation:** *"Confucius employs three built-in methods to validate the correctness of generated DSLs. … we use a graph validator to check the topology against predefined invariants, such as full connectivity and minimum path requirements."*
- **Crucial distinction:** "Intent" in Confucius is **network operator intent** (e.g., *"update max capacity for all fibers in NA to X"*) over a *network topology*, not **architectural intent predicates** over *software components*. Invariants are hard-coded network rules (full connectivity, min path), not a predicate calculus. Validation is LLM-feedback error correction, not a soundness proof. Production at scale (2 years, 60 apps, 4.16K users at Meta).
- **Comparison to pillars:**
  - (A) **No pre-emption** — intent is *operator intent over network topology*, not architectural predicates over software decomposition.
  - (B) **No** — validation is post-hoc domain-specific; not a soundness proof.
  - (C) **No** — no content addressing.
- **Verdict:** No pre-emption. Defines the strongest *industrial* precedent for DAG-based LLM planning. Any patent examiner reading our application will raise this — distinguish on (i) domain of intent (network vs architecture), (ii) intent type (operator statement vs declarative predicate), (iii) validator type (topology hard-coded vs predicate calculus).

### 3.13 Prompt Provenance (SSRN 2025) — *prompt-only CBOM*

- **Primary source:** *Prompt Provenance: Toward Traceable LLM Interactions*, SSRN abstract id 5682942, 2025. https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5682942 — ResearchGate mirror: https://www.researchgate.net/publication/397604906_Prompt_Provenance_Toward_Traceable_LLM_Interactions
- **Verbatim claim:** *"This paper introduces the Prompt Provenance Model (PPM)… It is posited that capturing prompt-level provenance is essential for auditability, explainability, and regulatory compliance in LLM ecosystems."*
- **Coverage:** Prompt-only. Does NOT bind plan / context-slice / generated code into the same hash root. Does NOT claim bit-identical reproducibility from a four-input tuple.
- **Comparison to Pillar (C):** Prompt Provenance is a subset of our claim — it covers only the prompt leg of the four-input tuple. Daylight = our four-input tuple (declaration + plan + context-slice + code) is content-addressed *together*, and the CBOM is *bit-identical*, not prompt-traceable.
- **Verdict:** Pre-empts the prompt-level subset; does not pre-empt the full claim. Must narrow independent Claim 2 to emphasize that the content-addressed input set is the *four-tuple* and that the CBOM is *bit-identical*, not just *traceable*.

### 3.14 ActiveGraph (arXiv 2605.21997) — *the bit-reproducibility kill-shot*

- **Primary source:** Nakajima, *ActiveGraph: The Log is the Agent*, arXiv 2605.21997v1 (2026-05). https://arxiv.org/html/2605.21997v1 — OSS at https://github.com/yoheinakajima/activegraph (Apache 2.0). Product: https://docs.activegraph.ai
- **Verbatim claim:** *"A determinism contract and replay mechanism that makes any run byte-reproducible from its log, including a content-addressed cache that records model and tool responses so replay performs no new model calls… Two runs produce byte-identical logs."* Model response is *"keyed on a hash of the entire request (system message, user messages, model identifier, tool definitions, and output schema)"*.
- **What it does:** Append-only event log of agent runs. Content-addressed LLM-response cache. Byte-reproducible replay.
- **Crucial distinction:** ActiveGraph achieves byte-reproducibility *by recording all LLM responses* — the CBOM equivalent is the *full event log*. Our claim is that the CBOM is *compact* and *derivable from a four-input hash tuple* without re-execution. ActiveGraph's content-addressing keys on the *LLM request hash*, not on a declarative four-input tuple. The plan and declaration are implicit in the log; we make them first-class content-addressed inputs.
- **Comparison to Pillar (C):**
  - ActiveGraph has content addressing, but only over the LLM request.
  - ActiveGraph has byte-reproducibility, but only via replay (which requires reading back the log).
  - Our CBOM is bit-identical *without re-execution* because the orchestrator is deterministic on the four inputs.
- **Verdict:** ActiveGraph is the **strongest pre-emption** of Pillar (C). Daylight = (i) four-input hash tuple (not just LLM request), (ii) compact CBOM (not full event log), (iii) bit-identical *without replay*. Narrow our claim to these three differentials.

### 3.15 SPICE Intent Chain (IETF draft-mw-spice-intent-chain-00, 2026-03)

- **Primary source:** Krishnan et al., *Cryptographically Verifiable Intent Chain for AI Agent Content Provenance*, IETF Internet-Draft. https://www.ietf.org/archive/id/draft-mw-spice-intent-chain-00.html — contributors: JPMorgan Chase, Oracle, Telefonica, Aryaka.
- **Verbatim claim:** *"This document defines the intent_chain claim… the intent chain addresses content provenance (WHAT was produced and HOW it was transformed). In AI agent workflows, content flows through multiple processing stages including AI agents and filters. The intent chain provides a cryptographically verifiable, tamper-evident record of this content journey… entry[i].output_hash == entry[i+1].input_hash, creating a complete content provenance chain."*
- **Crucial distinction:** SPICE is a *content provenance log* (Merkle-chained signed records). It explicitly distinguishes *deterministic* entries (where output is re-derivable) from *non-deterministic* entries (signed only). It does NOT claim a CBOM is bit-identical from a four-input tuple.
- **Verdict:** Pre-empts the *content provenance* axis generically but NOT the *bit-identical CBOM* axis. Watch for IETF RFC-track progression — could become strong prior art within 12–24 months.

### 3.16 Zhou et al. — *Cryptographic Binding and Reproducibility Verification for AI Agent Tool Use* (arXiv 2603.14332)

- **Primary source:** Zhou et al., arXiv 2603.14332v1 (2026-03). https://arxiv.org/html/2603.14332v1
- **Verbatim claim:** *"We propose three mechanisms. Capability-bound agent certificates extend X.509 v3 with a skills manifest hash; any tool change invalidates the certificate. Reproducibility commitments leverage LLM inference near-determinism for post-hoc replay verification. A verifiable interaction ledger provides hash-linked, signed records for multi-agent forensic reconstruction."* Reproducibility commitment is post-hoc *near-determinism* with F1=0.876 semantic equivalence classifier.
- **Crucial distinction:** Zhou's tuple is (agent capability certificate / skills-manifest hash, model hash, tool-invocation record). Does NOT content-address plan, context-slice, or generated code. Accepts near-determinism (F1=0.876), not bit-identical.
- **Verdict:** Pre-empts the cryptographic-binding axis generically; NOT bit-identical CBOM.

### 3.17 Lean4Agent — *the predicate-system prior art for Pillar (B)*

- **Primary source:** *Lean4Agent: Formal Modeling and Verification for Agent Workflow and Trajectory*, arXiv 2606.06523v2. https://arxiv.org/html/2606.06523v2
- **Verbatim claim:** *"The second layer models and verifies the static semantic soundness of the agent workflow under explicit assumptions about the local LLM's … Predicate System … Semantic Workflow Graph … Verification Procedure."* Uses **Lean 4 / dependent types** as the proof substrate. Three layers: L1 structural verification, L2 static semantic verification with Predicate System + Semantic Workflow Graph, L3 execution-trajectory verification.
- **Crucial distinction:** Lean4Agent verifies an authored workflow with a Predicate System. It is a *certifier*, not an *orchestrator*. The predicates are part of a verification *specification*, not the input to a *scheduling-pruning step*. It does NOT couple the predicates to wave-pruning. It does NOT produce a content-addressed CBOM.
- **Verdict:** Pre-empts the predicate-system-axis of Pillar (B) generically; NOT the *scheduling-pruning coupled* version. Daylight = the predicate set is consumed by a scheduler that prunes the wave plan, not by a verifier that inspects an authored graph.

### 3.18 Classical Petri-net / Workflow-net soundness

- **Primary sources:** van der Aalst, *Process Mining* (2011, Springer), hal-00613137. Blondin et al., *The complexity of soundness of workflow nets*, michaelblondin.com/papers/BMO22a.pdf.
- **Verbatim claim (van der Aalst):** *"The central decision problems concerning workflow nets deal with soundness … the verification of the soundness property boils down to checking whether the extended Petri net is live!"*
- **Crucial distinction:** Classical WF-net soundness is a property of a hand-authored WF-net, computed by reachability analysis over the net. It is a *verification problem*, not an *orchestration problem*. Applied to LLM agent decomposition only by Lean4Agent (which is in turn a certifier, not an orchestrator).
- **Verdict:** Pre-empts the soundness-theory generically (cite van der Aalst 2011 in background). Our claim must be narrowly the *coupling of soundness to a declarative architectural predicate model with wave scheduling*.

### 3.19 Feature-model scheduling (Software Product Line engineering)

- **Primary sources:** Kang et al., FODA (1990). *Constraints: the Core of Product Line Engineering*, RCIS 2011 (HAL hal-00707544). *A Formal Product-Line Engineering Approach for Schedulers*, U. Twente (research.utwente.nl).
- **What it is:** Feature models describe the variability of a software product line (selection, optional, requires, excludes). Constraint solving over feature models (SAT, CSP) is well-established for variant enumeration and configuration.
- **Crucial distinction:** Feature-model scheduling is *static configuration selection*. It has not been applied to LLM agent decomposition — and when it has been (job-shop scheduling, see Modeling and Analysis of Configurable Job-Shop Scheduling, dl.acm.org/doi/10.1145/3715340.3715431), the predicates are scheduling-constraints over job resources, not *architectural intent predicates over software components*. No prior art combines feature-model constraint solving with LLM agent decomposition.
- **Verdict:** Pre-empts (A) generically (predicate algebra exists in SPL engineering); NOT the LLM-agent-decomposition integration. Cite feature-model literature in background; distinguish on (i) domain (architectural decomposition, not product configuration), (ii) integration with LLM orchestration.

### 3.20 Other LLM-orchestration academic systems

- **ChatDev** (arXiv 2307.07924) — sequential chat chain, no predicates, no soundness, no CBOM. Verdict: no pre-emption.
- **AgentPro** (EMNLP 2025) — automated process supervision, probabilistic. Verdict: pre-empts (B) not at all.
- **λ_A: A Typed Lambda Calculus for LLM Agent Composition** (arXiv 2604.11767v2) — type-theory composition, lint correctness via fault injection; certifier not orchestrator. Verdict: pre-empts (B) not at all.
- **CIR+CVN** (arXiv 2604.09318v1) — model-checking + Petri-net for LLM agent analysis. Verdict: pre-empts (B) generically, NOT (A) or (C).
- **Petri Net of Thoughts (PNoT)** — mines workflow-nets from traces. Verdict: pre-empts (A)/(B) not at all.
- **Probabilistic Soundness Guarantees in LLM Reasoning Chains** (EMNLP 2025 main 382) — probabilistic, not predicate-based. Verdict: pre-empts (B) not at all.
- **Unified Plan Verification with Static Rubrics** (OpenReview) — declares verification rules, no scheduling coupling. Verdict: pre-empts (B) not at all.
- **Solver-Aided Verification of Policy Compliance in Tool-Augmented LLM Agents** — SMT for tool-use policy. Verdict: pre-empts (B) generically, NOT (A) or (C).

### 3.20b ACONIC — *the closest academic pre-emption of Pillar (A)*

- **Primary source:** Zhou, Xu, Liu, Liu, Wang, Wu, *ACONIC: Systematic Decomposition of Complex LLM Tasks via Constraint-Induced Complexity*, arXiv 2510.07772 (Oct 2025, revised Jan 2026). https://arxiv.org/abs/2510.07772
- **Verbatim claim:** ACONIC frames the LLM task as a **constraint satisfaction problem (CSP)** and uses **3-SAT reduction + formal complexity measures** to *guide decomposition*.
- **Crucial distinction:** ACONIC's constraints are **task-level** (sub-formulas of a Boolean query / SQL query). Our predicates are **architectural-level** (which component may invoke which, in what phase, with what cross-cutting concerns injected). ACONIC targets *single-query reliability* (text-to-SQL); we target *multi-agent workflow scheduling*. ACONIC does NOT claim **soundness verification** of the generated decomposition against the constraint model — only that constraint-driven decomposition improves accuracy. ACONIC does NOT carry a **declarative specification language** for architectural intent.
- **Comparison to pillars:**
  - (A) **Closest academic pre-emption.** Treats constraints as the decomposition driver. Gap: (i) task-level vs architectural-level predicates, (ii) no soundness verification, (iii) no declarative specification language.
  - (B) **No** — no soundness proof.
  - (C) **No** — no content addressing.
- **Verdict:** **The single closest academic prior art** to Pillar (A) generically. Distinguish on three axes: domain (architectural vs task-level), soundness (verified vs not), declarative language (specified vs not). Must cite explicitly in background; must disclaim around in claim language.

### 3.20c Peña, Hinchey, Ruiz-Cortés — *NASA MAS Product Line* (2006)

- **Primary source:** Peña, Hinchey, Ruiz-Cortés, *Building the Core Architecture of a Multiagent System Product Line*, NASA GSFC / University of Seville, NASA/TR-2006-46736. https://ntrs.nasa.gov/api/citations/20060046736/downloads/20060046736.pdf
- **Verbatim claim:** A methodology for deriving a core MAS architecture from a product-line feature model. Feature model is transformed into a **Constraint Satisfaction Problem (CSP)**; "commonality" of feature F = `cardinal(filter(M, F=true)) / cardinal(M)`; features with commonality > threshold enter the core.
- **Crucial distinction:** Peña et al. use feature-model predicates (`optional` / `mandatory` / `alternative` / `requires` / `excludes`) over multiagent systems as **scheduling-relevant predicates** — the **closest published work** in the literature to the architectural-intent scheduling concept. The delta: Peña et al. use feature models for **architectural derivation at design time** (what goes into the product), while our claim is **runtime task scheduling of LLM agents under architectural intent predicates** (what runs in what order given a runtime intent specification). Both share the predicate algebra; the difference is the *scheduling engine* and the *LLM-agent context*.
- **Verdict:** **Must cite in patent background.** Our novelty is the integration with (i) LLM-agent runtime scheduling, (ii) declared typed predicate language, (iii) soundness verification, (iv) content-addressed CBOM.

### 3.20d RFC 9315 / IETF AIN — *Intent terminology disambiguation*

- **Primary source:** Clemm et al., RFC 9315 (informational, IETF NMRG, October 2022). https://www.rfc-editor.org/info/rfc9315/ — disambiguated by draft-feng-nmrg-ain-architecture-00 (April 2026).
- **Verbatim claim (AIN draft):** *"AIN intents are routable requests for AI-agent capability invocation. IBN intents are declarative goals for network behavior management. The two are complementary."*
- **Crucial distinction:** **IBN "intent" = declarative *network-behavior* goal in network operator's vocabulary.** Our "architectural intent" = declarative *software-architecture* constraint set used as a scheduling primitive for LLM agent decomposition. **Homonyms, not synonyms.**
- **Verdict:** No pre-emption. Use the IETF AIN draft's section 5.8 as a template for our own disambiguation in the patent background.

### 3.20e Backstage Software Catalog + AIContext RFC #33575 — *closest pre-emption of Claim 3*

- **Primary sources:** Backstage catalog schema; Backstage issue #33575 (2026 RFC on AIContext kind). https://github.com/backstage/backstage/issues/33575 — Roadie writeup: https://roadie.io/blog/idp-ai-goldmine-context-engineering/
- **What it is:** Backstage is a CNCF-incubating developer-portal framework. `catalog-info.yaml` is a typed YAML schema carrying service-level metadata: `metadata.name`, `spec.owner`, `spec.type` (service / library / website), `spec.dependsOn[]`, `spec.system`, `spec.lifecycle`. The AIContext RFC proposes adding `kind: AIContext` so catalogs are consumable by agents.
- **Crucial distinction:** Backstage's predicates are at *service-organization granularity* (one service per catalog file), not at *internal component composition* granularity. There is no equivalent of `phases`, `todos[].blockedBy[]`, `mutually_exclusive_with`, or `cross_cutting.applies_to`. Backstage's `dependsOn` is a *dependency* predicate; ours include `select_one_of` (mutual exclusion), `optional` (optionality), `phase` (temporal ordering), `cross_cutting` (injection), `invariant` (preservation). AIContext is proposed for **retrieval**, not for **DAG pruning or scheduling**.
- **Verdict:** Closest pre-emption to Claim 3 (declarative project model). Daylight is the *richness of the predicate algebra* (architectural decomposition vs service catalog) and the *consumer* (scheduler + soundness + CBOM vs RAG retrieval).

### 3.20f Repository Intelligence Graph (RIG) and Codebase-Memory — *code/build-derived structural models*

- **Primary sources:** RIG: arXiv 2601.10112 (Cherny-Shahar & Yehudai, 2026). Codebase-Memory: arXiv 2603.27277v1 (Meyer-Eschenbach et al., 2026).
- **Verbatim claim (RIG):** *"A deterministic, evidence-backed architectural map that represents buildable components, aggregators, runners, tests, external packages, and package managers, connected by explicit dependency and coverage edges that trace back to concrete build and test definitions."*
- **Verbatim claim (Codebase-Memory):** *"Constructs a persistent, Tree-Sitter-based knowledge graph via the Model Context Protocol (MCP)… exposing 14 structural query tools (call-path tracing, impact analysis, hub detection) to any MCP-compatible LLM agent."*
- **Crucial distinction:** Both RIG and Codebase-Memory are **code/build-derived** structural models. RIG explicitly says *"edges trace back to concrete build and test definitions."* Codebase-Memory parses Tree-Sitter ASTs. Neither carries predicates about phases of intent, mutual exclusion between top-level architectural variants, or per-agent bounding rules.
- **Verdict:** Closest pre-emption to a "smart repo" claim at the *retrieval* layer. No pre-emption at the *scheduling-pruning* layer. Distinguish on (i) derivation source (code-derived vs architect-declared), (ii) consumer (retrieval vs scheduler), (iii) predicate algebra (deps-only vs selection/optionality/phase/cross-cutting/invariant).

### 3.20g Intent Engineering (arXiv 2603.09619) — *closest conceptual pre-emption*

- **Primary source:** arXiv 2603.09619 (2026).
- **Verbatim claim:** *"Encodes organizational goals, values, and trade-off hierarchies into agent infrastructure."*
- **Crucial distinction:** Concept paper at the *goal/values layer* (organizational) rather than the *project-component layer* (architectural). No working DAG-pruning / per-agent-bounding implementation tied to a typed schema.
- **Verdict:** Closest *conceptual* pre-emption to "non-code-recoverable intent predicates." No pre-emption at the *system-implementation* layer.

### 3.20h CN119645662B (PKU — "Complex Task Intelligent Planning Execution") — *MEDIUM risk, FTO follow-up*

- **Primary source:** Cited by Daguan family; granted 2025-09-19, assignee Beijing University. Title translates to "复杂任务智能规划执行方法, 装置, 电子设备及存储介质" — complex task intelligent planning execution method, apparatus, electronic device, and storage medium.
- **Risk level:** **MEDIUM.** Title suggests planning; CN patent practice typically uses 智能规划 (intelligent planning) for LLM-based task planning, not for declarative predicate scheduling — but **must read full claim text before any FTO opinion**. This is the **highest-priority follow-up** identified by the Chinese-patent research.

### 3.21 AI-BOM / SBOM / CycloneDX / SPDX

- **Primary sources:** Bennett et al., *Implementing AI Bill of Materials (AI BOM) with SPDX 3.0*, arXiv 2504.16743 (2025-04). CycloneDX 1.6 ML-BOM spec.
- **What they are:** Static inventory of AI system components (algorithms, data, frameworks, libraries, licenses). Supply-chain artifact for compliance.
- **Crucial distinction:** AI-BOM inventories what *exists*; it does NOT bind plan / context-slice / generated code, does NOT claim bit-identical reproducibility, is NOT content-addressed.
- **Verdict:** Pre-empts Pillar (C) not at all. Different category (supply-chain inventory vs runtime provenance). Avoid generic "AI bill of materials" wording to prevent collision with SPDX AI-BOM standards work.

### 3.22 Deterministic inference + EigenAI

- **Primary source:** AI Accelerator Institute, *Verifiable execution for AI agents*, April 2026, https://www.aiacceleratorinstitute.com/verifiable-execution-for-ai-agents/
- **Verbatim claim:** *"EigenAI achieves true bit-for-bit deterministic inference on GPUs by carefully controlling the execution environment and removing all sources of non-determinism."* ContextSubstrate: *"documents each agent run as an immutable context package tied to a SHA-256 hash. Every input, parameter, interim step, and output is stored in a single content-addressable bundle with a unique context URI."*
- **Crucial distinction:** EigenAI achieves deterministic inference *at the model call*; ContextSubstrate bundles all inputs/outputs into a content-addressable record. Our claim is at a different layer — the *orchestrator's CBOM output* is bit-identical from a four-input hash tuple. This requires both deterministic inference AND deterministic orchestration over the tuple.
- **Verdict:** Pre-empts (C) not at all if we narrow to the four-input tuple + orchestrator determinism.

---

## 4. Patent database search log

### 4.1 Google Patents (patents.google.com) — English

| Query | Result count (approx) | Notable hits | Verdict |
|---|---|---|---|
| `"intent predicate" AND ("agent" OR "orchestration")` | Low (<10) | None relevant | Negative — no system claims architectural intent predicates as scheduling primitives |
| `"constraint satisfaction" AND "agent decomposition"` | Low | Generic AI planning | No LLM-agent-specific hit |
| `"soundness" AND ("agent" OR "LLM") AND "decomposition"` | Low | Lean4Agent, Agentproof (preprints) | No granted patents |
| `"deterministic orchestration" AND "LLM"` | ~30 | Praetorian blog, Conductor blog, generic scheduler patents | No granted claims that read on (A) or (B) |
| `"content addressed" AND ("agent" OR "LLM") AND "context"` | Very low | None directly relevant | Negative |
| `"context bill of materials"` | <5 | None | Negative |
| `"agent provenance" AND "content address"` | <5 | None | Negative |
| `"CN119377360B"` | 1 | CN119377360B — LLM + SOP knowledge graph + RPA | Pre-empts nothing (see §3.8) |

### 4.2 IETF (datatracker.ietf.org) — English drafts

| Query | Result | Verdict |
|---|---|---|
| `"intent chain" AND "AI agent"` | draft-mw-spice-intent-chain-00 (March 2026) | Pre-empts *content provenance*; not bit-identical CBOM |
| `"AI agent" AND "provenance"` | None with declarative intent predicates | Negative |

### 4.3 CNIPA (Google Patents zh endpoint) — Chinese

| Query | Result | Verdict |
|---|---|---|
| `"智能体 分解 调度 约束"` (agent decomposition scheduling constraint) | Multiple academic papers; no granted patent claims on intent-predicate-scheduling specifically | Negative |
| `"LLM 智能体 编排 确定性"` | CN119377360B (already known); no other pre-empting patent found | Negative |
| `"意图驱动 多智能体"` (intent-driven multi-agent) | Confucius translation papers; no CN patent claim pre-empting us | Negative |
| `"工作流 声明式 调度 剪枝"` (workflow declarative scheduling pruning) | None | Negative |

**Critical limitation:** CNIPA 公布公告 (cnipa.gov.cn) was not accessible directly. **Recommendation:** Human attorney must do a full Chinese-language search before non-provisional filing — particularly in the 2024-2026 window, where Chinese patent filings on agent orchestration are accelerating.

### 4.4 Lens.org (free global patent search)

| Query | Result | Verdict |
|---|---|---|
| `"intent" AND "agent" AND "scheduling"` | Generic prior art | No pre-empting grant found |
| `"declarative" AND "LLM" AND "orchestration"` | None | Negative |

### 4.5 Semantic Scholar / ACM / IEEE — academic

| Query | Result | Verdict |
|---|---|---|
| `ReSo EMNLP 2025` | Confirmed (Zhou et al.) | See §3.3 |
| `Conductor Microsoft 2026 deterministic` | Confirmed | See §3.1 |
| `LangGraph soundness constraint` | No academic paper claims formal soundness | See §3.7 |
| `content addressed agent provenance reproducibility LLM` | Zhou et al. 2603.14332; ActiveGraph 2605.21997; SPICE draft | See §3.14, §3.15, §3.16 |
| `feature model software product line scheduling constraint` | Kang 1990; RCIS 2011; U Twente scheduler SPL | See §3.19 |
| `SIGCOMM 2025 intent multi-agent` | Confucius (network intent, not architectural) | See §3.12 |

---

## 5. Residual risks requiring human patent attorney

These risks cannot be cleared by open-web search alone:

1. **Unpublished / pending patent applications** — the most common mode of pre-emption that web search cannot see. We have NOT searched USPTO PAIR full text, EPO Espacenet full text, JPO Industrial Property Digital Library, or CNIPA 公布公告. A professional FTO (freedom-to-operate) search by an attorney is mandatory before non-provisional filing.

2. **Continuation filings of US20260017525A1** (*Validating autonomous AI agents*) — the closest patent we found. Assignee should be checked for continuation chain.

3. **EigenAI patent filings** — EigenAI claims bit-for-bit deterministic inference on GPUs. If they have a continuation covering "deterministic LLM agent orchestration using deterministic inference," that could narrow our Pillar (C) daylight.

4. **IETF SPICE Intent Chain RFC progression** — draft-mw-spice-intent-chain-00 is on the IETF agenda. If it progresses to RFC status (within 12–24 months), it becomes standard-essential prior art for *content provenance* claims. Our Pillar (C) daylight narrows but still survives because we claim *bit-identical CBOM from a four-input tuple*, not just Merkle-chained content provenance.

5. **Chinese patent activity in 2024–2026** — accelerating. Cannot be cleared by English search. Need Chinese-language CNIPA search.

6. **Unpublished Microsoft work on Conductor** — Conductor is open-source MIT, but Microsoft has a substantial patent portfolio on agent orchestration (including Azure Durable Functions). Could be a continuation filing covering specific aspects of Conductor's deterministic routing that we should check.

7. **Unpublished Anthropic / Cognition / Devin work** — Devin's own planning architecture and Anthropic's Claude Code agents-as-sub-agents architecture may be patented.

8. **Academic preprint → patent pipeline** — Lean4Agent (arXiv 2606.06523) is published by what appears to be an academic group with industry ties. If a continuation patent is filed on the predicate-system + scheduling integration, it could pre-empt our Pillar (B).

---

## 6. Summary novelty table

| Pillar | Closest adversary | Daylight |
|---|---|---|
| (A) Intent-predicate scheduling pruning | Confucius (operator intent over network topology); ReSo (DAG with deps only); feature-model literature (config selection, not agent decomposition) | (1) Architectural predicates (selection/optionality/phase/cross-cutting/invariant) consumed by scheduler before agent invocation; (2) declarative, not semantic-intent-classified; (3) integrated with LLM agent decomposition, not product configuration or network topology |
| (B) Provable soundness w.r.t. intent predicates | Agentproof (soundness over authored graph topology); Lean4Agent (predicate system + Lean 4 verification); WF-net soundness (van der Aalst) | (1) Soundness bound to *declarative predicate model*, not to authored graph; (2) integrated with *scheduler that prunes wave plan*, not post-hoc verifier; (3) emitted as machine-checkable proof bound to the schedule |
| (C) Content-addressed CBOM | ActiveGraph (byte-reproducible agent log via replay); SPICE Intent Chain (Merkle-chained content provenance); Zhou et al. (near-determinism F1=0.876); Prompt Provenance (prompt-only) | (1) Four-input hash tuple (declaration + plan + context-slice + code), not just LLM request hash; (2) compact bit-identical CBOM artifact, not full event log; (3) bit-identical *without re-execution*; (4) declaration + plan are first-class content-addressed inputs |

---

## 7. Conclusion

**Verdict: NARROW GO.** File a provisional application immediately, with the claims narrowly drawn around the (A)+(B)+(C) combination, and explicit disclaimers around the (A) Conductor / Praetorian lane (deterministic orchestration), the (B) Agentproof / Lean4Agent lane (soundness over authored graphs), and the (C) ActiveGraph / SPICE / Prompt Provenance lane (content provenance). Before non-provisional filing, commission a paid FTO search covering USPTO PAIR, CNIPA 公布公告, EPO Espacenet, and JPO IPDL.

The combination of intent-predicate scheduling + soundness + content-addressed CBOM has no known prior-art footprint in the 2024-2026 window. Each pillar individually has known ancestors. The invention lives in the coupling.

---

## Search-log summary

- **Databases consulted:** Google Patents (English + Chinese endpoint), Google Scholar, arXiv, ACL Anthology, ACM DL (open), IETF datatracker, IEEE Xplore (open), Lens.org, Semantic Scholar, vendor blogs (Microsoft Open Source, Praetorian, Aider, LangChain, Cursor, Sourcegraph), Medium (flurrylab), SSRN.
- **Primary sources read in depth (≥8 each):** Microsoft Conductor (opensource.microsoft.com), Praetorian (praetorian.com), Agentproof (arXiv 2603.20356), MetaGPT (arXiv 2308.00352), ReSo (aclanthology.org 2025.emnlp-main.808), Confucius (minlanyu.seas.harvard.edu), ActiveGraph (arXiv 2605.21997), Aider repomap (aider.chat), LangGraph docs (docs.langchain.com).
- **Search angles:** English + Chinese keywords, free patent DBs, academic preprints, IETF drafts, vendor blogs, OSS READMEs.
- **Limits:** CNIPA 公布公告 not directly accessed; USPTO PAIR full text not searched; EPO Espacenet full text not searched; JPO IPDL not searched. Unpublished / pending applications not visible.
- **Recommendation:** A paid attorney FTO search before non-provisional filing is mandatory to clear these residuals.