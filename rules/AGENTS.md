# EULIS (Google Jules) Delegation-First Operational Policy

This rule is permanently active whenever `jules-plugin` is enabled. It governs how the AI assistant handles engineering, research, review, and testing requests.

---

## 🎯 Core Operating Mandate

1. **Default Strategy: Maximize Delegation to EULIS (Google Jules)**  
   Whenever the user requests writing code, adding features, authoring test suites, performing code reviews, refactoring, or conducting exploratory spikes, the agent must **first consider delegating the heavy lifting to Jules**.

2. **Automated Triage & Task Separation (Run on Every Task)**  
   Before writing extensive local code or launching an autonomous local loop, run the **4-Point Triage**:
   * **Full Delegation:** If the task is self-contained (parsers, algorithms, isolated features, unit tests, doc generation) ➔ Dispatch directly to Jules via Sub-Agent.
   * **Partial Delegation (Task Split):** If the task has local dependencies (local Docker, localhost DB, uncommitted `.env` secrets) ➔ **Automatically split the task**:
     * **Component A (Jules):** Pure domain logic, algorithms, abstract interfaces, and mock unit tests (dispatched to Jules via Sub-Agent).
     * **Component B (Local):** Local secret injection, DB connection pool wiring, and environment configuration.
   * **Non-Delegatable:** If the task strictly requires interactive local debugging, local hardware, or ad-hoc uncommitted file forensics ➔ Implement locally on the IDE thread.

3. **Multi-Modal Delegation Modes:**  
   Do not limit Jules to basic feature coding. Actively suggest and use Jules for:
   * **Delegated Code Review:** Offload PR/branch diff reviews and security audits to Jules.
   * **Delegated Research & Spikes:** Have Jules build prototype modules and evaluate third-party libraries in isolated branches.
   * **Delegated Test Synthesis:** Have Jules write 20–50 edge-case and fuzz tests for critical functions.

4. **3-Tier Model Execution Mandate (Dynamic Multi-Tier Model Routing - >99.5% Token Savings):**  
   * **NEVER** run Jules CLI dispatch, long-running test suites, or polling loops directly in the primary LLM context window.
   * **Tier 1: `flash_lite` (Mechanical Worker):** Pure shell dispatch (`jules remote new`), zero-token polling (`jules-gate wait`), and git branch merges. Use for rote CLI operations.
   * **Tier 2: `flash` (Analytic Verifier):** Gated testing (`jules-gate verify`), test runner triage, and lightweight patch hotfixes.
   * **Tier 3: `pro` (Cognitive Architect):** Exclusively for Step 0 triage, contract-first prompt formulation, and escalated merge conflicts. The primary Pro agent must NEVER run shell commands, polling loops, or test runners directly.
   * **Tier 0: OS Background Daemon:** Used for long-running non-blocking wait.
   * The sub-agent executes in its own ephemeral context, absorbing all polling and test output tokens.
   * The primary agent must remain idle with zero tool calls until the sub-agent completes and reports back.
