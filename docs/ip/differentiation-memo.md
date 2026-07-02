# Differentiation Memo — Point-by-Point vs Each Kill-Shot

**Purpose.** For each kill-shot identified in `patent-prior-art.md`, this memo: (1) explains what they do, (2) what they explicitly do NOT do, (3) where OUR daylight sits, with exact quotes from primary sources.

**Anchor.** The three inventive pillars of simple_model (a.k.a. "Project Intelligence"):
- (A) Architectural intent predicates (`select_one_of`, `select_subset_of`, `optional`, `phase`, `cross_cutting`, `blocks`, `invariant`) used as a **scheduling-pruning primitive**.
- (B) A **provable soundness guarantee** w.r.t. those predicates on the decomposed wave plan.
- (C) A **content-addressed CBOM** (Context Bill of Materials) for bit-reproducible agent orchestration.

---

## 1. Microsoft Conductor (opensource.microsoft.com/blog/2026/05/14, github.com/microsoft/conductor)

### What they do
> *"Conductor is an open-source CLI (MIT license, Microsoft org) that takes a different approach: you define your multi-agent workflows in YAML, and the routing between agents is deterministic. Jinja2 templates and expression evaluation handle conditions and branching. The orchestration layer consumes zero tokens. The structure is fixed at definition time—and that's the point."*

- Hand-authored YAML graph of agents.
- Routing via Jinja2 conditionals, "first matching condition wins."
- Three context modes: `accumulate` / `last_only` / `explicit`.
- Static parallel groups with `failure_mode: continue_on_error | fail_fast | all_or_nothing`.
- Web dashboard visualizes DAG, clickable nodes.
- Supports GitHub Copilot and Anthropic Claude as providers, per-agent model overrides.

### What they explicitly do NOT do
- **No architectural intent predicate algebra.** Conditional edges are one-shot Jinja2 branches, not first-class predicates.
- **No soundness proof.** `conductor validate` is a schema lint, not a proof.
- **No content addressing.** The graph itself is not hash-addressed; outputs of stochastic LLM calls (claude-opus-4.6-1m, claude-haiku-4.5, gpt-5.2 etc., not pinned to temperature=0) are not bit-identical.
- **No scheduling-pruning from declared intent.** Routing topology is hand-authored.

### Our daylight
- (A) Our `struct.json` carries a *typed* predicate algebra (`select_one_of`, `select_subset_of`, `optional`, `phase`, `cross_cutting`, `blocks`, `invariant`) that is consumed by the *scheduler* (the `decompose` algorithm) before any agent is invoked. Conductor has no analogous schema; the user writes YAML by hand.
- (B) Our scheduler emits a soundness proof w.r.t. the declared predicate set. Conductor has no proof machinery.
- (C) Our CBOM bit-addresses (declaration, plan, context-slice, code). Conductor has no CBOM concept; stochastic LLM outputs are explicitly retained as stochastic.

### Verdict
**Disjoint lane.** Conductor is "deterministic control flow over stochastic agents." Ours is "deterministic decomposition from declared intent, with soundness proof, over bit-reproducible artifacts." Both share the word "deterministic" but mean different things by it.

---

## 2. Praetorian Development Platform (praetorian.com, Nathan Sportsman blog Nov 2025)

### What they do
> *"This paper details the architecture of the Praetorian Development Platform, which solves these problems by treating the Large Language Model (LLM) not as a chatbot, but as a nondeterministic kernel process wrapped in a deterministic runtime environment."*
> *"The architecture is defined by one hard constraint in the Claude Code runtime: Sub-agents cannot spawn other sub-agents."*
> *"Agents are reduced to stateless, ephemeral workers (<150 lines)."*
> *"This implements Intent-Based Context Loading, ensuring agents only load the specific patterns relevant to their current task rather than the entire domain knowledge base."*

- 5-layer enforcement: CLAUDE.md → Skills → Agent defs → UserPromptSubmit hooks → PreToolUse hooks → PostToolUse hooks → SubagentStop hooks → Stop hooks.
- 16-phase state machine (Setup, Triage, Codebase Discovery, Skill Discovery, Complexity, Brainstorming, Architecting Plan, Implementation, Design Verification, Domain Compliance, Code Quality, Test Planning, Testing, Coverage Verification, Test Quality, Completion).
- 39 specialized agents (`*-lead`, `*-developer`, `*-reviewer`, `*-tester`), 350+ prompts, 530k-line codebase, 32 modules.
- Dual state: ephemeral hooks (`feedback-loop-state.json`) + persistent `MANIFEST.yaml`.
- Gateway Skills for Intent-Based Context Loading (e.g., `gateway-frontend`).

### What they explicitly do NOT do
- **No declarative predicate algebra.** "Intent" in Praetorian = *semantic intent classification* by an LLM-mediated Gateway router — not a *declared, typed* predicate consumed by a deterministic scheduler.
- **No formal soundness proof.** "Loop detection" is a string-similarity heuristic (3 consecutive iterations with >90% similarity = stuck). Enforcement is by hooks, not proofs.
- **No content-addressed CBOM.** State is persisted as `MANIFEST.yaml` and Claude Code session JSONL transcripts; not hash-addressed.
- **Claude Code runtime dependency.** Hard-coupled to Claude Code's tool restriction boundary (Sub-agents cannot spawn sub-agents) and to `claude` as the inference runtime. Not portable to other LLMs.

### Our daylight
- (A) Praetorian's Gateway is an LLM-mediated *semantic intent router*. Our intent predicates are *declared, typed, deterministic*. Praetorian's "intent" is what the LLM thinks; ours is what the architect said.
- (B) Praetorian's enforcement is hooks + string similarity. Ours is a *machine-checkable soundness proof* over the wave plan.
- (C) Praetorian persists state in YAML + JSONL. Ours emits a *bit-identical CBOM* from a four-input hash tuple.
- **Portability:** Praetorian is hard-coupled to Claude Code. Ours is `bash + jq`, agent-agnostic (Claude, Codex, Cursor, generic CLI).

### Verdict
**Disjoint lane.** Praetorian is "Thin Agent / Fat Platform" with hook-based enforcement. Ours is "Project carries its own self-model + soundness + memory; algorithm is the father."

---

## 3. ReSo (EMNLP 2025 main 808; arXiv 2503.02390)

### What they do
> *"ReSo addresses these limitations by decomposing tasks, dynamically routing them, assigning subtasks to the most appropriate agents, and using…"*
> *"ReSo builds on prior work in agent selection and task decomposition, ReSo's task decomposition and collaborative reward models."*

- Decomposition DAG `G = (V,E)` where each node vi has dependency edges `vi → vj` over the *input question*.
- Pruning is via UCB on a *similarity score* `Q(a,v) = sim(a,v) · perform(a)` (Eq. 5) — over *agents*, not over the schedule. Cost `O((s·N + N log N + k·c)·D)`.
- Reward model `r(ai,v) ∈ [0,1]` from a Collaborative Reward Model.
- Empirically validated on Math-MAS and SciBench-MAS.

### What they explicitly do NOT do
- **No architectural predicate slots in the DAG.** The DAG is a textbook dependency graph — no `select_one_of` / `optional` / `phase` / `cross_cutting` / `invariant` fields.
- **No soundness proof.** Validity is empirical accuracy tables.
- **No content addressing.**
- **No declarative intent model.** Pruning is over agent selection, not over the schedule.

### Our daylight
- (A) ReSo's DAG carries only data-dependency edges. Our `struct.json` carries a typed predicate algebra on top of the dependency edges. The schedule is *derived* from the predicates, not the other way around.
- (B) We prove soundness of the derived schedule w.r.t. the predicates. ReSo validates empirically.
- (C) We content-address the entire orchestration run. ReSo has no CBOM.

### Verdict
**Disjoint lane.** ReSo is "LLM-mediated UCB agent selection over a dependency DAG." Ours is "declarative predicate-driven wave decomposition with soundness proof + content addressing."

---

## 4. Agentproof (arXiv 2603.20356)

### What they do
> *"Agentproof… extracts a unified abstract graph model from four major agent frameworks (LangGraph, CrewAI, AutoGen, Google ADK), applies six structural checks with witness trace generation, and evaluates temporal safety policies via a DSL compiled to deterministic finite automata—both statically through a graph × DFA product construction and at runtime over event traces."*

- Six structural checks with **formal soundness proofs** (Appendix A, Lemmas 1–9): exit reachability, reverse reachability / livelock, dead-end detection, router shape, human-in-the-loop presence/coverage, tool declaration.
- Temporal DSL: safety fragment of LTL (forbidden, implication-future, until, bounded response, response chain, conjunction, disjunction), compiled to DFAs; graph × DFA product construction gives static verification over all paths.
- Extractors for LangGraph, CrewAI, AutoGen, Google ADK — bridges heterogeneous representations into a unified AgentGraph.

### What they explicitly do NOT do
- **No architectural intent predicate algebra.** The model has node kinds (entry, exit, tool, llm, router, human, subgraph, passthrough) and edge kinds (direct, conditional, parallel, loop) — these are topological, not declarative-predicate.
- **No scheduler.** Agentproof verifies an already-authored graph. The graph is hand-written; Agentproof is a *certifier*, not an *orchestrator*.
- **No content-addressed CBOM.** LLM output semantics are explicitly out of scope.
- **No coupling of predicates to wave-pruning.** Predicates are part of the verification specification, not the input to a decomposition step.

### Our daylight
- (A) Agentproof reads an *authored graph*. We *derive* the graph from a declared predicate set (`struct.json` intent). The derivation step — the `decompose` algorithm — is what Agentproof does not do.
- (B) Agentproof proves soundness of *graph topology* (reachability, dead-ends, temporal policy satisfaction). We prove soundness of the *decomposition* w.r.t. *declared architectural intent predicates* (selection, optionality, phase, cross-cutting, invariant). These are different propositions.
- (C) We emit a CBOM. Agentproof emits a verification report (which passes, which fails, witness traces).

### Where the overlap is critical
Agentproof is the **strongest pre-emption** of Pillar (B) generically. Our independent Claim 1 must be narrowly drawn to: *"a soundness guarantee bound to a declared architectural intent predicate set on the wave plan produced by a declarative decomposition step, not a soundness guarantee over the topology of an already-authored agent workflow graph."* The daylight is the *coupling* of (i) a declarative predicate model with (ii) a decomposition scheduler with (iii) a soundness proof.

### Verdict
**Partial overlap on (B); disjoint on (A) and (C).** Must disclaim.

---

## 5. MetaGPT (ICLR 2024 / arXiv 2308.00352)

### What they do
> *"MetaGPT encodes Standardized Operating Procedures (SOPs) into prompt sequences for more streamlined workflows, thus allowing agents with human-like domain expertise to verify intermediate results and reduce errors. MetaGPT utilizes an assembly line paradigm to assign diverse roles to various agents, efficiently breaking down complex tasks into subtasks."*
> *"Code = SOP(Team) is the core philosophy. We materialize SOP and apply it to teams composed of LLMs."*

- SOP = human Standard Operating Procedure encoded as prompt sequences.
- Linear role ordering: PM → Architect → ProjectManager → Engineer → QaEngineer.
- Assembly-line paradigm; "intermediate result review" by other LLM roles.

### What they explicitly do NOT do
- **No declarative predicate algebra.** The SOP is a *linear ordering of roles*, not a typed predicate.
- **No soundness proof.** Verification is LLM-as-judge.
- **No content addressing.**
- **No scheduling-pruning.** The role ordering is fixed.

### Our daylight
- (A) MetaGPT's SOP is *procedural* — it captures role handoffs in a human workflow. Our `struct.json` predicates are *declarative architectural constraints* — they capture mutual-exclusion, optionality, phase ordering, cross-cutting injection, invariants. These are categorically different: SOPs answer "who does what next," predicates answer "what configurations of components are valid in the first place."
- (B) We have a soundness proof; MetaGPT does not.
- (C) We have CBOM; MetaGPT does not.

### Verdict
**Disjoint lane.** MetaGPT is "human SOP as prompts"; ours is "architectural predicates as scheduler input."

---

## 6. Confucius / SIGCOMM 2025 (acm.org/doi/10.1145/3718958.3750537)

### What they do
> *"We model network management workflows as directed acyclic graphs (DAGs) to aid planning. Our framework integrates LLMs with existing management tools … employs retrieval-augmented generation (RAG) … and establishes a set of primitives to systematically support human/model interaction."*
> *"We represent the planning logic of network tasks as a directed acyclic graph (DAG), implemented using a Python-based DSL. Each node in the DAG represents a subtask … Independent subtasks can be executed in parallel, and the runtime environment automatically determines the optimal execution plan based on input/output dependencies."*
> *"Confucius employs three built-in methods to validate the correctness of generated DSLs. … we use a graph validator to check the topology against predefined invariants, such as full connectivity and minimum path requirements."*

- Production-deployed at Meta for 2+ years; 60 apps, 4.16K users.
- Python DSL DAG, LLM-augmented planning, post-hoc graph validator against hard-coded network invariants.

### What they explicitly do NOT do
- **"Intent" in Confucius = network operator intent** ("update max capacity for all fibers in NA to X") over a *network topology*, NOT architectural intent predicates over *software components*.
- **No declarative predicate algebra.** "Invariants" are hard-coded network rules (full connectivity, min path).
- **No soundness proof.** Validator is LLM-feedback error correction.
- **No content addressing.**

### Our daylight
- (A) Confucius's intent is **operator intent over a network topology** (a statement of a desired network state). Our intent predicates are **architectural intent over a software component graph** (declarative constraints on which components can coexist, what phases they belong to, what invariants they must satisfy). These are categorically different domains — a network operator's "intent" is a goal; our predicates are constraints on valid decompositions.
- (B) Confucius validates post-hoc against a hard-coded list. Our scheduler emits a proof bound to the resolved schedule.
- (C) Confucius has no CBOM.

### Why this matters most for the patent
Confucius is the **strongest industrial precedent** for DAG-based LLM planning at scale. A patent examiner will raise it. The differentiator must be stated unambiguously:
- **Domain of intent:** Confucius = network operator intent. Ours = architectural intent over software decomposition.
- **Type of intent:** Confucius = operator statement. Ours = declared typed predicate.
- **Validator type:** Confucius = LLM-feedback error correction. Ours = machine-checkable soundness proof.
- **Reproducibility:** Confucius = no CBOM. Ours = bit-identical four-input tuple CBOM.

### Verdict
**Disjoint lane, but the most likely examiner reference.** Must distinguish on all four axes.

---

## 7. LangGraph (docs.langchain.com/oss/python/langgraph)

### What they do
> *"At its core, LangGraph models agent workflows as graphs. You define the behavior of your agents using three key components: State, Nodes, Edges. … The program proceeds in discrete 'super-steps.' A super-step can be considered a single iteration over the graph nodes. Nodes that run in parallel are part of the same super-step."*
> *"Compiling is a pretty simple step. It provides a few basic checks on the structure of your graph (no orphaned nodes, etc)."*

- Pregel-inspired super-step execution.
- `StateGraph`, `add_node`, `add_edge`, `add_conditional_edges`.
- Checkpointers, interrupt_before/interrupt_after for human-in-loop.
- Thread-scoped persistence via `thread_id`.

### What they explicitly do NOT do
- **No formal soundness.** "Determinism" here = runtime determinism (same inputs, same state given same interrupts), not a proof of constraint preservation.
- **No content addressing.** Graph itself is not hash-addressed.
- **No declarative predicate algebra.** Conditional edges are one-shot branches.

### Our daylight
- (A) LangGraph gives the *execution substrate*. Our predicates give the *scheduling input*. We can use LangGraph-style super-step semantics under the hood; our novelty is in the *decomposition step*, not the runtime.
- (B) LangGraph has no soundness proof. We do.
- (C) LangGraph has no CBOM. We do.

### Verdict
**Substrate, not competitor.** LangGraph is to our scheduler as PostgreSQL is to a transaction-processing app.

---

## 8. AutoGen (arXiv 2308.08155)

### What they do
> *"AutoGen is an open-source framework that allows developers to build LLM applications via multiple agents that can converse with each other to accomplish tasks."*

- Conversation programming — agents exchange messages; control flow is emergent.

### What they explicitly do NOT do
- **No `struct.json` analog.** Decomposition surface is an LLM prompt, not a typed schema.
- **No soundness.**
- **No content addressing.**

### Our daylight
- (A) AutoGen is the *opposite* paradigm — emergent conversation vs. declarative architecture.
- (B) (C) AutoGen has none.

### Verdict
**Opposite lane.** AutoGen is "LLM decides decomposition"; ours is "algorithm decides, LLM only generates leaves."

---

## 9. CN119377360B (CNIPA granted — LLM + SOP knowledge graph + RPA)

### What they do
> *"在本发明基于大语言模型协同知识图谱的AI Agent智能体中，所述RPA SOP流程知识图谱模块采用本体的方式构建，定义领域内的概念、实体、属性和关系，为知识表示和推理提供基础。"*

### Translation
"In the AI Agent based on large language model collaborative knowledge graph in the present invention, the RPA SOP workflow knowledge graph module is constructed using ontology, defining concepts, entities, properties, and relations in the domain, providing a foundation for knowledge representation and reasoning."

- LLM + RPA + SOP knowledge graph ontology.
- Procedural SOP encoded as ontology.

### What they explicitly do NOT do
- **No soundness proof.**
- **No content-addressed CBOM.**
- **No architectural intent predicate algebra.** "SOP" here is the same procedural SOP as MetaGPT, not a typed predicate calculus.

### Our daylight
Same as MetaGPT — SOP is procedural, ours is declarative.

### Verdict
**Disjoint lane.** Procedural SOP, not declarative predicates.

---

## 10. Aider repomap (aider.chat/2023/10/22/repomap.html)

### What they do
> *"Aider sends GPT a repo map to GPT along with each request from the user to make a code change. The map contains a list of the files in the repo, along with the key symbols which are defined in each file… Aider solves this problem by sending just the most relevant portions of the repo map. It does this by analyzing the full repo map using a graph ranking algorithm, computed on a graph where each source file is a node and edges connect files which have dependencies."*

- tree-sitter parses to extract symbol definitions and references.
- PageRank-style graph ranking on the symbol graph.
- Renders a compact tag map for the LLM context.

### What they explicitly do NOT do
- **No architectural intent predicates.** Aider's "intent" = graph centrality as a proxy for likely relevance. There is no `select_one_of` / `optional` / `phase` / `cross_cutting` / `invariant` model.
- **No decomposition / scheduler.** repomap is a *retrieval* artifact for a single LLM call.
- **No soundness.**
- **No content addressing.**

### Our daylight
- (A) Aider's repo map is *code-derived* — it cannot express predicates that aren't already in the source. Our `struct.json` carries predicates *not derivable from source* (architectural intent: which components are mutually exclusive, which are optional, which phases they belong to).
- (B) (C) Aider has neither.

### Verdict
**Disjoint lane.** Aider is "smart tool + dumb repo (code-derived context)." Ours is "smart repo + algorithm is the father (declared predicates + soundness + CBOM)."

---

## 11. flurrylab Bazel article (medium.com)

### What they claim
> *"By executing commands against the Bazel query language, the agent can trace the exact dependency chain mandated by the build system."*

### What they explicitly do NOT do
- **No architectural intent predicates.** Bazel's dependency graph models *build dependencies*, not architectural intent.
- **No soundness.**
- **No content-addressed CBOM (only Bazel's own content-addressed build store).**

### Our daylight
- (A) Bazel's dependency graph is a strict subset of our declarative model (deps only, no predicates).
- (B) (C) Bazel does not pre-empt.

### Verdict
**Disjoint lane.** Build-system dependency graphs are code-derived; our predicates are architect-declared.

---

## 12. ActiveGraph (arXiv 2605.21997)

### What they do
> *"A determinism contract and replay mechanism that makes any run byte-reproducible from its log, including a content-addressed cache that records model and tool responses so replay performs no new model calls… Two runs produce byte-identical logs."*
> A model response is *"keyed on a hash of the entire request (system message, user messages, model identifier, tool definitions, and output schema)"*.

- Append-only event log of agent runs.
- Content-addressed LLM-response cache keyed on the **LLM request hash**.
- Byte-reproducible replay (by reading back the log).

### What they explicitly do NOT do
- **No four-input hash tuple.** ActiveGraph keys on the LLM request, not on a `(declaration, plan, context-slice, code)` tuple.
- **No compact CBOM.** The "byte-identical" artifact is the *full event log* — heavy storage, not a derived artifact.
- **Bit-identical only via replay** (re-reading the log). Our CBOM is bit-identical *without replay*.
- **No declarative plan or declaration as content-addressed inputs.** The plan and declaration are implicit in the log.

### Our daylight
- (C) ActiveGraph content-addresses the LLM request; we content-address the **four-input tuple** including the *declaration* and *plan* as first-class inputs.
- (C) ActiveGraph's CBOM is the full log; ours is a *compact artifact* (declaration-hash + plan-hash + context-slice-hashes + code-hashes + soundness-proof-hash).
- (C) ActiveGraph achieves byte-reproducibility via replay; ours via orchestrator determinism on the four inputs.

### Verdict
**Partial overlap on (C); disjoint on (A) and (B).** Strongest pre-emption of Pillar (C). Must disclaim explicitly. Our independent Claim 2 must be narrowly drawn to the four-input tuple + compact CBOM + bit-identical without replay.

---

## 13. SPICE Intent Chain (IETF draft-mw-spice-intent-chain-00)

### What they do
> *"This document defines the intent_chain claim… the intent chain addresses content provenance (WHAT was produced and HOW it was transformed). In AI agent workflows, content flows through multiple processing stages including AI agents and filters. The intent chain provides a cryptographically verifiable, tamper-evident record of this content journey… entry[i].output_hash == entry[i+1].input_hash, creating a complete content provenance chain."*

- Merkle-chained signed records (intent_chain entries).
- OAuth token carries Merkle root.
- Explicit support for **non-deterministic** entries (signed only, not re-derivable).

### What they explicitly do NOT do
- **No four-input hash tuple.** SPICE chains content inputs/outputs; it does not bind a declaration or plan.
- **No claim of bit-identical reproduction.** It explicitly accommodates non-deterministic entries.
- **No declarative intent predicates.**

### Our daylight
- (C) SPICE is a *content provenance log* (Merkle-chained); our CBOM is a *bit-identical artifact from a four-input tuple*. SPICE = log. Ours = derived artifact.

### Verdict
**Disjoint lane but watch the IETF RFC-track.** If SPICE progresses to RFC, it becomes standard-essential prior art for *content provenance* claims within 12-24 months. Our Pillar (C) daylight survives because we claim *bit-identical CBOM*, not just content provenance.

---

## 14. Zhou et al. arXiv 2603.14332 — *Cryptographic Binding and Reproducibility Verification for AI Agent Tool Use*

### What they do
> *"We propose three mechanisms. Capability-bound agent certificates extend X.509 v3 with a skills manifest hash; any tool change invalidates the certificate. Reproducibility commitments leverage LLM inference near-determinism for post-hoc replay verification. A verifiable interaction ledger provides hash-linked, signed records for multi-agent forensic reconstruction."*

- X.509 v3 + skills manifest hash for agent certificates.
- Reproducibility commitments = post-hoc near-determinism (F1=0.876 semantic equivalence).
- Hash-linked signed interaction ledger.

### What they explicitly do NOT do
- **No four-input hash tuple.** Zhou's tuple is (agent capability certificate / skills-manifest hash, model hash, tool-invocation record). Does not content-address plan, context-slice, or generated code.
- **No bit-identical reproduction.** F1=0.876 is semantic-equivalence, not bit-identical.

### Our daylight
- (C) Zhou covers (capabilities, model, tools); we cover (declaration, plan, context-slice, code).
- (C) Zhou accepts near-determinism; we claim bit-identical.

### Verdict
**Partial overlap on (C); disjoint on (A) and (B).** Must disclaim explicitly around cryptographic-binding framing.

---

## 15. Lean4Agent (arXiv 2606.06523)

### What they do
> *"The second layer models and verifies the static semantic soundness of the agent workflow under explicit assumptions about the local LLM's … Predicate System … Semantic Workflow Graph … Verification Procedure."*

- Three layers: L1 structural verification, L2 static semantic verification with Predicate System + Semantic Workflow Graph, L3 execution-trajectory verification.
- Uses Lean 4 / dependent types as proof substrate.

### What they explicitly do NOT do
- **No scheduler.** Lean4Agent verifies an authored workflow. It does not decompose a plan from declared predicates.
- **No content-addressed CBOM.**

### Our daylight
- (B) Lean4Agent has a Predicate System but the predicates are part of a *verification specification* of an *authored workflow*. Our predicates are *input to a decomposition step that derives the wave plan*. Lean4Agent = verifier. Ours = scheduler + verifier + reproducer.
- (A) Lean4Agent does not couple predicates to wave-pruning. We do.

### Verdict
**Partial overlap on (B); disjoint on (A) and (C).** Cite Lean4Agent in background; distinguish on coupling-to-scheduler axis.

---

## 16. Classical Workflow-net / Petri-net soundness (van der Aalst 2011; Blondin 2022)

### What they do
> *"The central decision problems concerning workflow nets deal with soundness … the verification of the soundness property boils down to checking whether the extended Petri net is live!"*

- WF-net soundness is a property of a hand-authored WF-net, computed by reachability analysis.
- Theoretical foundation; not coupled to LLM agents in classical literature.

### What they explicitly do NOT do
- **Not applied to LLM agent decomposition natively.** Only via Lean4Agent/Agentproof as a verifier.
- **No declarative architectural predicate model.**

### Our daylight
- (B) Classical WF-net soundness is generic. Our soundness is specifically bound to a *declarative architectural intent predicate set on a wave plan*.

### Verdict
**Generic theory, cite in background.** Our novelty is in the architectural-predicate-specific application.

---

## 17. Feature-model scheduling (Software Product Line engineering — Kang 1990, Apel, Batory)

### What they do
- Feature models with `requires` / `excludes` / `optional` / `mandatory` predicates.
- Constraint solving (SAT, CSP) for product configuration.
- Recent work: *Modeling and Analysis of Configurable Job-Shop Scheduling* (dl.acm.org/doi/10.1145/3715340.3715431), *Automated Constraint Specification for Job Scheduling* (arXiv 2510.02679).

### What they explicitly do NOT do
- **Not coupled to LLM agent decomposition.** Feature-model scheduling is for *product configuration* and *job-shop scheduling* — different domain.

### Our daylight
- (A) Feature-model constraint solving is a *prior art line* we cite in background. Our novelty is the *integration* with LLM agent decomposition and the *scheduling-pruning role* of architectural predicates.

### Verdict
**Generic theory, cite in background.** Distinguish on (i) domain (architectural decomposition, not product configuration), (ii) integration with LLM orchestration.

---

## 18. AI-BOM / SPDX 3.0 / CycloneDX ML-BOM

### What they do
> *"In this report, we introduce the concept of an AI-BOM, expanding on the SBOM to include the documentation of algorithms, data collection methods, frameworks and libraries, licensing information, and standard compliance."*

- Static inventory of AI system components.
- Supply-chain compliance artifact.

### What they explicitly do NOT do
- **Not content-addressed runtime provenance.** Inventory ≠ CBOM.
- **No four-input hash tuple.**
- **No bit-identical reproducibility claim.**

### Our daylight
- (C) AI-BOM inventories what exists; our CBOM is a runtime artifact.

### Verdict
**Different category.** Avoid generic "AI bill of materials" wording to prevent collision with SPDX AI-BOM standards work.

---

## 19. Prompt Provenance (SSRN 5682942)

### What they do
> *"This paper introduces the Prompt Provenance Model (PPM)… It is posited that capturing prompt-level provenance is essential for auditability, explainability, and regulatory compliance in LLM ecosystems."*

- Prompt-level provenance.

### What they explicitly do NOT do
- **No plan / context-slice / generated code in the hash root.**
- **No bit-identical reproducibility claim.**

### Our daylight
- (C) Prompt Provenance covers only the prompt leg of our four-input tuple. Our CBOM binds all four.

### Verdict
**Subset of our claim.** Must narrow Claim 2 to the four-input tuple to differentiate.

---

## 20. Reproducible Builds ecosystem (Debian / Nix / Guix)

### What they do
> *"A build is reproducible if given the same source code, build environment and build instructions, any party can recreate bit-by-bit identical bytes."*

- Bit-identical build artifacts from source + environment + instructions.

### What they explicitly do NOT do
- **Not applied to LLM agent orchestration.** Reproducible builds covers compiled binaries, not stochastic model inference.
- **No four-input tuple.**

### Our daylight
- We *import* the reproducible-builds principle (bit-identical from same inputs) and apply it to a *new input domain* (declaration, plan, context-slice, code → CBOM, including LLM inference).

### Verdict
**Generic principle, cite in background.** Our novelty is the input domain (LLM agent orchestration).

---

## Cross-cutting summary

For each pillar, the prior-art landscape is **disjoint**, not cumulative. No single prior-art system occupies more than one pillar. The combination of (A) + (B) + (C) is the invention.

| Pillar | Closest adversary | Closest adversary claim (verbatim) | Our daylight |
|---|---|---|---|
| (A) | Confucius | "We model network management workflows as directed acyclic graphs (DAGs) to aid planning." | Domain of intent (network operator vs architectural); type of intent (operator statement vs declared predicate) |
| (A) | ReSo | "task decomposition and collaborative reward models" with UCB over agents | Pruning over schedule vs over agents; DAG carries predicates vs only deps |
| (B) | Agentproof | "six structural checks with witness trace generation" with formal soundness proofs | Soundness bound to authored graph vs declared predicates; verifier vs orchestrator+verifier |
| (B) | Lean4Agent | "Predicate System … Semantic Workflow Graph … Verification Procedure" | Predicates as verification spec vs scheduler input; certifier vs orchestrator |
| (C) | ActiveGraph | "byte-reproducible from its log… content-addressed cache" | LLM request hash vs four-input tuple; full event log vs compact artifact; replay-based vs derivation-based |
| (C) | SPICE Intent Chain | "Merkle-chained signed records" | Content provenance log vs bit-identical CBOM from hash tuple |
| (C) | Zhou et al. | "Capability-bound agent certificates… F1=0.876 near-determinism" | Capabilities+model+tools vs declaration+plan+context-slice+code; near-determinism vs bit-identical |

**The invention lives in the coupling.**

---

## 21. ACONIC — *the closest academic pre-emption of Pillar (A)*

### What they do
> ACONIC frames the LLM task as a **constraint satisfaction problem (CSP)** and uses **3-SAT reduction + formal complexity measures** to *guide decomposition*. Evaluated on SAT-Bench (combinatorial) and Spider (text-to-SQL).

### What they explicitly do NOT do
- **Task-level constraints only.** ACONIC's constraints are sub-formulas of a Boolean query / SQL query. Not architectural-level predicates over software components.
- **No soundness verification.** ACONIC improves accuracy empirically; does not prove the generated decomposition is sound against the constraint model.
- **No declarative specification language.** Constraints are implicit in the task input.
- **Single-query target.** ACONIC targets text-to-SQL reliability; not multi-agent workflow scheduling.

### Our daylight
- (A) ACONIC's constraints are *task-level* (Boolean sub-formulas of a single query). Our predicates are *architectural-level* (which component may invoke which, in what phase, with what cross-cutting concerns). Different domain, different algebra.
- (B) ACONIC has no soundness proof. We do.
- (C) ACONIC has no CBOM. We do.

### Verdict
**Closest academic pre-emption of Pillar (A).** Distinguish on three axes: domain (architectural vs task-level), soundness (verified vs not), declarative language (specified vs not). Must cite ACONIC explicitly in patent background.

---

## 22. Peña, Hinchey, Ruiz-Cortés — *NASA MAS Product Line* (2006)

### What they do
> A methodology for deriving a core MAS architecture from a product-line feature model. Feature model is transformed into a **Constraint Satisfaction Problem (CSP)**; "commonality" of feature F = `cardinal(filter(M, F=true)) / cardinal(M)`; features with commonality > threshold enter the core.

### What they explicitly do NOT do
- **Design-time derivation, not runtime scheduling.** Peña et al. derive the *product architecture* at design time (what features go into the product). They do not schedule LLM agent *tasks* at runtime under architectural intent predicates.
- **No LLM-agent context.**
- **No soundness verification.**
- **No content addressing.**

### Our daylight
- (A) Peña et al. share the predicate algebra vocabulary (`optional` / `mandatory` / `alternative` / `requires` / `excludes`) with us. The delta is the *consumer*: Peña feeds predicates to a design-time product-line derivation engine; we feed predicates to a *runtime LLM agent decomposition scheduler*.
- (B) We have a soundness proof; Peña et al. do not.
- (C) We have CBOM; Peña et al. do not.

### Verdict
**Closest published work in the feature-model-over-MAS literature.** Must cite in patent background. Distinguish on (i) runtime vs design-time, (ii) LLM-agent context vs product derivation, (iii) soundness, (iv) CBOM.

---

## 23. RFC 9315 / IETF AIN — *intent terminology disambiguation*

### What they claim
> *"An 'intent' is a declarative, high-level, network-operation goal."* (RFC 9315)
> *"AIN intents are routable requests for AI-agent capability invocation. IBN intents are declarative goals for network behavior management. The two are complementary."* (draft-feng-nmrg-ain-architecture-00)

### Our daylight
- **Homonyms, not synonyms.** "Intent" in RFC 9315 = network-behavior goal. "Architectural intent" in our claims = software-architecture constraint set. Different technical domain, different consumer.

### Verdict
**No pre-emption.** Use the IETF AIN draft's section 5.8 as a template for our own disambiguation in the patent background.

---

## 24. Backstage Software Catalog + AIContext RFC #33575 — *closest pre-emption of Claim 3*

### What they do
> Backstage is a CNCF-incubating developer-portal framework. `catalog-info.yaml` is a typed YAML schema carrying service-level metadata: `metadata.name`, `spec.owner`, `spec.type` (service / library / website), `spec.dependsOn[]`, `spec.system`, `spec.lifecycle`. The AIContext RFC proposes adding `kind: AIContext` so catalogs are consumable by agents.

### What they explicitly do NOT do
- **Service-organization granularity, not component-composition granularity.** One service per catalog file; no `phases`, `todos[].blockedBy[]`, `mutually_exclusive_with`, or `cross_cutting.applies_to`.
- **`dependsOn` is dependency, not constraint.** No mutual-exclusion, no optionality, no phase, no invariant.
- **AIContext is for retrieval, not DAG pruning or scheduling.** The RFC explicitly proposes the new `kind` for *agent context retrieval*, not for *decomposition scheduling*.

### Our daylight
- (A) Backstage's predicates are service-catalog metadata; ours are architectural-decomposition constraints. Richer algebra, different consumer.
- (B) We have a soundness proof; Backstage has none.
- (C) We have CBOM; Backstage has none.

### Verdict
**Closest pre-emption of Claim 3 (declarative project model).** Distinguish on (i) predicate richness (architectural decomposition vs service catalog), (ii) consumer (scheduler + soundness + CBOM vs RAG retrieval).

---

## 25. RIG and Codebase-Memory — *code/build-derived structural models*

### What they do
> **RIG:** *"A deterministic, evidence-backed architectural map that represents buildable components, aggregators, runners, tests, external packages, and package managers, connected by explicit dependency and coverage edges that trace back to concrete build and test definitions."*
>
> **Codebase-Memory:** *"Constructs a persistent, Tree-Sitter-based knowledge graph via the Model Context Protocol (MCP)… exposing 14 structural query tools (call-path tracing, impact analysis, hub detection) to any MCP-compatible LLM agent."*

### What they explicitly do NOT do
- **Code/build-derived only.** RIG explicitly: *"edges trace back to concrete build and test definitions."* Codebase-Memory: Tree-Sitter ASTs.
- **No predicate algebra.** Both expose query tools (call-path, impact, hub); neither exposes a typed predicate system.
- **No decomposition scheduler.** Both are *retrieval* layers, not *orchestration* layers.

### Our daylight
- (A) RIG / Codebase-Memory models are *derived* (from code/build artifacts). Our `struct.json` model is *declared* (by the architect). Predicates are non-derivable.
- (B) No soundness in RIG / Codebase-Memory; we have one.
- (C) No CBOM in RIG / Codebase-Memory; we have one.

### Verdict
**Closest pre-emption to "smart repo" claim at the retrieval layer.** No pre-emption at the scheduling-pruning layer. Distinguish on (i) derivation source (code-derived vs architect-declared), (ii) consumer (retrieval vs scheduler), (iii) predicate algebra (deps-only vs selection/optionality/phase/cross-cutting/invariant).

---

## 26. Intent Engineering (arXiv 2603.09619) — *closest conceptual pre-emption*

### What they claim
> *"Encodes organizational goals, values, and trade-off hierarchies into agent infrastructure."*

### What they explicitly do NOT do
- **Concept paper, not system.** No working DAG-pruning / per-agent-bounding implementation tied to a typed schema.
- **Organizational goals, not architectural decomposition.** Wrong layer.

### Our daylight
- (A) Intent Engineering is *conceptual*; we have a working system with a typed predicate schema.
- (B) Intent Engineering has no soundness; we do.
- (C) Intent Engineering has no CBOM; we do.

### Verdict
**Closest conceptual pre-emption.** No pre-emption at the system-implementation layer.

---

## 27. CN119645662B (PKU "intelligent planning") — *MEDIUM risk, FTO follow-up*

### What it might claim
- Title: "复杂任务智能规划执行方法" (complex task intelligent planning execution method).
- Assignee: Beijing University. Granted 2025-09-19.
- 智能规划 in CN patent practice typically denotes LLM-based task planning, not declarative predicate scheduling.

### What it explicitly does NOT do (assumed; full claim text required)
- **No declared typed predicate algebra** (CN practice: LLM-driven planning).
- **No soundness proof** (CN practice: LLM-judge).
- **No CBOM** (CN practice: not a content-addressed concern).

### Our daylight
Same as MetaGPT / AutoGen — LLM-driven planning is the opposite of declarative-predicate scheduling.

### Verdict
**MEDIUM risk; require attorney claim-text read.** Title is suggestive; only full claim analysis will tell.

---

## Updated cross-cutting summary (including late-arriving kill-shots)

| Pillar | Closest adversary | Closest adversary claim (verbatim) | Our daylight |
|---|---|---|---|
| (A) | **ACONIC** | "task modeled as constraint satisfaction problem... 3-SAT reduction" | Architectural-level predicates vs task-level constraints; soundness verification vs none; declarative language vs implicit |
| (A) | Peña 2006 | "feature model transformed into CSP" for MAS | Runtime LLM-agent scheduling vs design-time product derivation |
| (A) | Confucius | "We model network management workflows as directed acyclic graphs" | Domain of intent (network operator vs architectural); type of intent (operator statement vs declared predicate) |
| (A) | ReSo | "task decomposition and collaborative reward models" with UCB over agents | Pruning over schedule vs over agents; DAG carries predicates vs only deps |
| (B) | **Agentproof** | "six structural checks with witness trace generation" with formal soundness proofs | Soundness bound to authored graph vs declared predicates; verifier vs orchestrator+verifier |
| (B) | Lean4Agent | "Predicate System … Semantic Workflow Graph … Verification Procedure" | Predicates as verification spec vs scheduler input; certifier vs orchestrator |
| (C) | **ActiveGraph** | "byte-reproducible from its log… content-addressed cache" | LLM request hash vs five-hash tuple; full event log vs compact artifact; replay-based vs derivation-based |
| (C) | SPICE Intent Chain | "Merkle-chained signed records" | Content provenance log vs bit-identical CBOM from hash tuple |
| (C) | Zhou et al. | "Capability-bound agent certificates… F1=0.876 near-determinism" | Capabilities+model+tools vs declaration+plan+context-slice+code; near-determinism vs bit-identical |
| **Claim 3** | **Backstage + AIContext RFC** | "spec.dependsOn[], spec.system, spec.lifecycle" + AIContext kind | Service-organization granularity vs architectural decomposition; predicate richness; consumer (scheduler+soundness+CBOM vs RAG retrieval) |
| **Claim 3** | RIG / Codebase-Memory | "evidence-backed architectural map… edges trace back to build/test definitions" | Code/build-derived vs architect-declared; retrieval vs scheduling-pruning; deps-only vs predicate algebra |

**The invention lives in the coupling.**