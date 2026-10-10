# EULIS (Google Jules) Delegation-First Operational Policy

This rule is permanently active whenever `jules-plugin` is enabled. It governs how the AI assistant handles engineering, research, review, and testing requests.

---

## 🎯 Core Operating Mandate

1. **Default Strategy: Maximize Delegation to EULIS (Google Jules)**  
   Whenever the user requests writing code, adding features, authoring test suites, performing code reviews, refactoring, or conducting exploratory spikes, the agent must **first consider delegating the heavy lifting to Jules**.

2. **Automated Triage & Task Separation (Run on Every Task)**  
   Before writing extensive local code or launching an autonomous local loop, run the **4-Point Triage**:
   * **Full Delegation:** If the task is self-contained (parsers, algorithms, isolated features, unit tests, doc generation) ➔ Dispatch directly to Jules via Sub-Agent. Maximize delegation whenever token-efficient.
   * **Partial Delegation (Task Split):** If the task has local dependencies (local Docker, localhost DB, uncommitted `.env` secrets) ➔ **Automatically split the task**:
     * **Component A (Jules):** Pure domain logic, algorithms, abstract interfaces, and mock unit tests (dispatched to Jules via Sub-Agent).
     * **Component B (Local):** Local secret injection, DB connection pool wiring, and environment configuration.
   * **Efficiency Override (Local Option):** If delegating becomes inefficient and is expected to consume more tokens in orchestration/dispatch overhead than a direct local edit (e.g., trivial 1-line syntax/import fixes, single version bumps, quick regex tweaks) ➔ Choose local execution on the IDE thread.
   * **Non-Delegatable:** If the task strictly requires interactive local debugging, local hardware, or ad-hoc uncommitted file forensics ➔ Implement locally on the IDE thread.

3. **Multi-Modal Delegation Modes:**  
   Do not limit Jules to basic feature coding. Actively suggest and use Jules for:
   * **Delegated Code Review:** Offload PR/branch diff reviews and security audits to Jules.
   * **Delegated Research & Spikes:** Have Jules build prototype modules and evaluate third-party libraries in isolated branches.
   * **Delegated Test Synthesis:** Have Jules write 20–50 edge-case and fuzz tests for critical functions.

4. **4-Stage Lifecycle Token Insulation (Dynamic Multi-Tier Model Routing - >99.5% Token Savings):**  
   * **NEVER** run Jules CLI dispatch, long-running test suites, or polling loops directly in the primary LLM context window.
   * **Stage 1: Pre-Dispatch Research (`flash`):** For broad codebase exploration or workflow inspection, spawn a research sub-agent to explore files and return a concise synthesis.
   * **Stage 2: Cognitive Architecture (`pro`):** Exclusively for Step 0 triage, contract-first prompt formulation, and escalated merge conflicts. The primary Pro agent must NEVER run shell commands, polling loops, or test runners directly. Prompts formulated MUST include the Non-Interactive Completion Directive (instructing Jules to finalize directly without asking open-ended questions so the remote VM cleanly transitions to `Completed`).
   * **Stage 3: Mechanical Execution (`flash_lite`):** Pure shell dispatch (`jules remote new`), zero-token polling (`jules-gate wait`), and git branch merges. Use for rote CLI operations.
   * **Stage 4: Analytic Verification & Reporting (`flash`):** Gated testing (`jules-gate verify`), test runner triage, lightweight patch hotfixes, capturing token savings via `jules-gate tokens --json`, and generating/committing markdown reports directly under `docs/reports/` before returning the final summary.
   * The sub-agent executes in its own ephemeral context, absorbing all polling and test output tokens.
   * The primary agent must remain idle with zero tool calls until the sub-agent completes and reports back.

5. **Strict No-Polling Directive for Sub-Agents:**
   Sub-agents (especially `flash_lite`) must **NEVER** invoke `schedule` or `poll` in a loop with `manage_task` or `jules-gate ps` while `jules-gate wait` is running. Once `jules-gate wait` is launched, **stop calling tools** and let the platform wake you up automatically upon task exit.

6. **Strict Ban on Primary-Context Multi-File Sweeps & Board Enrichment:**
   * **Pre-Dispatch Exploration**: The primary Pro agent is strictly prohibited from running multi-file codebase explorations locally. If the user asks to "inspect", "explore", or "investigate" a repository, the agent MUST immediately spawn a `research` sub-agent (`Model: 'flash'`).
   * **Post-Dispatch Reporting & Boards**: Multi-card GitHub Project Board enrichment (`gh project`) and detailed report authoring MUST be offloaded to an ephemeral `flash` sub-agent. The primary agent only renders the final summary and links.

7. **Cloud Session Lifecycle Transparency & Feedback Protocol:**
   * **Dual Patch-Ready States:** Google Jules sessions yield complete patches in both `Completed` and `Awaiting User Feedback` states. In both cases, patches can be pulled immediately via `jules remote pull --session <id>`.
   * **Zero Feedback on Pass:** If local verification passes, merge changes immediately. No feedback is needed; the operator may accept or dismiss the web session on `https://jules.google.com/task/<id>` or via `jules-gate web <id>`.
   * **In-VM Iteration on Failure:** If local tests fail (`jules-gate verify` fails), utilize the **Cloud VM Repair Protocol**. Run `jules-gate reply <session_id> <failure_log>` to automatically copy the failure trace to the clipboard and launch the web UI, enabling rapid paste-and-repair within the existing Cloud VM.
