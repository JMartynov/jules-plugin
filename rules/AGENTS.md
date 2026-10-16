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

8. **Autonomous 3-Tier Interactive Task Resolution & Auto-Answer Heuristics (v3.4.0):**
   * **Strict No-Merge on Interactive State:** Sub-agents and orchestrators must NEVER merge review branches or consider a task completed while a session is in `Awaiting User Feedback` / interactive state (`jules-gate wait` exits 10). `jules-gate merge` strictly blocks merges with exit code 5.
   * **Auto-Answer Heuristics (`--interactive`):** When running `jules-gate wait --interactive` (or `jules-gate auto-answer <id>`), common boilerplate review follow-ups (e.g. "Should I open a PR or adjust anything?") are automatically recognized and resolved with a standard completion directive, unblocking Jules autonomously without human interruption.
   * **Sub-Agent Autonomous Clarification:** If input is substantive, the sub-agent runs `jules-gate inspect <id>` to retrieve Jules's question. If the sub-agent can answer based on the task contract, it sends the response via `jules-gate interact <id> "<answer>"` and resumes waiting until `Completed`.
   * **Escalation to Main Calling Agent:** If the sub-agent cannot answer the question from the contract, it MUST message the Main Calling Agent (`send_message`).
   * **Escalation to User:** The Main Calling Agent answers from higher-level context or prompts the human user via `ask_question`. Once answered, the response cascades back to Jules via `jules-gate interact`, and execution resumes until reaching clean `Completed` status.
   * **Strict Prohibition on Manual Gate Bypasses:** Sub-agents encountering `jules-gate wait` exit code 1 (timeout) or exit code 10 (interactive) must NEVER bypass the verification gate with manual `jules remote pull --apply` or local branch merges. Sub-agents MUST escalate to the Main Calling Agent (`send_message`) to resolve interactive prompts or timeouts.

9. **Sub-Agent Local Test & EULIS Branch Review Protocol:**
   * **Strict Sub-Agent Delegation for Local Tests (`jules-gate verify`):** Neither the primary orchestrator nor a dispatch worker should run raw test suites in the main context. `jules-gate verify` MUST always be invoked inside an isolated `flash` Verifier Sub-Agent, which executes tests against the worktree's own `PYTHONPATH` (`${WORKTREE_DIR}/src`) and returns only the concise pass/fail digest to the parent agent.
   * **CI/CD Suppression During Iterative Development (`--skip-ci`):** Use `--skip-ci` (or `JULES_GATE_SKIP_CI=1`) in `jules-gate verify`, `jules-gate pr`, and `jules-gate merge` so development commits and PRs include `[skip ci]` and do not trigger redundant GitHub Actions pipelines.
   * **Per-Task Branch, EULIS Code Review & Auto-Merge Workflow:**
     * Every task must update relevant documentation (`README.md`, `docs/*.md`) alongside code changes.
     * After an implementation branch `jules/review-<impl_id>` passes local tests via `jules-gate verify` and opens a PR via `jules-gate pr --skip-ci`, dispatch a **Mode 2 EULIS Code Review task** (`jules-gate review-branch`) against the branch diff (`git diff main...jules/review-<impl_id>`), instructing EULIS to generate a review proposal (`docs/reviews/review_task<N>.md`) and any recommended fixes.
     * Evaluate and apply the review proposal onto the task branch, re-run local tests via the `flash` test sub-agent, and automatically merge the PR into `main` (`jules-gate pr-merge`).

10. **Parallel Wave Sub-Agent Fan-Out & Decoupled Pipelining Protocol:**
    * **Sub-Agent Fan-Out Pattern:** When multiple independent Jules tasks run in parallel, spawn an isolated `flash` sub-agent for each task. Each sub-agent owns its individual lifecycle: `jules remote new` ➔ `jules-gate wait <id> --interactive` ➔ `jules-gate verify <id> <base> --skip-ci` ➔ `jules-gate merge <id> <base> --auto-rebase`.
    * **Decoupled Pipelining (No Convoy Blocking):** As soon as one task in the parallel wave completes, it MUST NOT wait for slower siblings. The completing sub-agent verifies and integrates its patch immediately into the base branch.
    * **Atomic Concurrency Mutex (`with_git_lock`):** All merge and PR-merge operations in `bin/jules-gate` are wrapped in an atomic directory mutex (`.git/jules_merge.lock.d`). Concurrent sub-agents attempting to integrate simultaneously queue safely without `index.lock` collisions or race conditions.
    * **Serialized Auto-Rebase (`--auto-rebase`):** Slower siblings automatically detect if the base branch has advanced (`git merge-base` != `base head`) and rebase their review branch onto the updated base branch prior to merging, ensuring clean linear history.
    * **Isolated Milestone Streaming:** Each sub-agent streams milestone completion reports directly to the orchestrator as tasks land, providing real-time visibility into wave progress without blocking.

