---
name: jules-task-controller
description: >-
  Orchestrate Google Jules (EULIS) coding tasks with mandatory sub-agent execution, automated task splitting,
  multi-modal delegation (features, code reviews, tests, research spikes), zero-token polling, and gated verification (Version 2.7.0).
  Use whenever planning, splitting, delegating, or verifying tasks assigned to Jules / EULIS across any programming language.
---

# Jules Task Controller (Version 2.7.0)

An enterprise orchestrator for **Google Jules (EULIS)**. Designed to maximize delegation across all software engineering workflows while strictly enforcing **sub-agent isolation** to eliminate token bloat (empirically proven to save **>99.5% of main-thread tokens** through Dynamic Multi-Tier Model Routing).

---

## ⚡ Core Operational Law: Forking Tasks in the Most Token-Sparing Way Possible

> [!IMPORTANT]
> **TOKEN CONSERVATION LAW: We are forking execution in the most efficient and token-sparing way possible.**
> 
> * **Zero Local Generation:** We fork all heavy coding, test fixtures, and refactoring to Google Jules in remote cloud VMs so that the local LLM generates 0 code tokens.
> * **Dynamic Efficiency Threshold (Economic Local Override):** We delegate to Jules as much as possible to eliminate code generation tokens. However, if delegating becomes inefficient and we expect more tokens in orchestration/dispatch overhead than a direct local execution (such as a 1-line syntax/import fix, single version bump, or quick regex tweak), we choose the local option.
> * **Zero Main-Thread Polling:** We fork all dispatch and waiting tasks to `flash_lite` sub-agents running native `jules-gate wait` background processes. The primary agent makes **zero tool calls** and remains completely suspended (0 tokens consumed while waiting).
> * **Isolated Workspace Forking:** We fork test verification, merge conflict rebasing, and markdown report authoring into ephemeral `flash` sub-agents using isolated Git review branches / worktrees (`Workspace: 'share'` or `Workspace: 'inherit'`).
> * **Pre-Dispatch Research Forking:** We fork broad codebase inspections to read-only `research` sub-agents before the primary context touches a single file, keeping the primary thread under 10k tokens.
> * **Empirical Proof:** Spares **>99.5% of primary tokens** across real-world multi-task production sessions (from >10.2M tokens down to <30k tokens).

---

## Dynamic Multi-Tier Model Routing

To maximize token efficiency (<0.8% relative compute cost), the system employs a 3-Tier Model Execution Mandate. You must select the appropriate tier based on the decision matrix below:

| Tier | Model | Role | Execution Scope | Token Cost Profile |
| :--- | :--- | :--- | :--- | :--- |
| **Tier 1** | `flash_lite` | **Mechanical Worker** | Pure shell dispatch (`jules remote new`), zero-token polling (`jules-gate wait`), and git branch merges. | Ultra-low (<0.1%) |
| **Tier 2** | `flash` | **Analytic Verifier** | Gated testing (`jules-gate verify`), test runner triage, and lightweight patch hotfixes. | Low (<0.8%) |
| **Tier 3** | `pro` | **Cognitive Architect** | Step 0 triage, contract-first prompt formulation, escalated merge conflicts. NEVER run shell commands directly. | High (Primary Thread) |

---

## ⚡ Quick Reference Cheat Sheet

| Command | Action | Key Benefit |
| :--- | :--- | :--- |
| `jules-gate lint <repo> [prompt_file]` | Pre-flight contract linter & complexity checker | **Validates connection, bounds, and flags trivial micro-tasks** |
| `jules-gate tokens [--json] [--reset]` | Token economy telemetry | **Reports cumulative tokens and dollars spared across sessions** |
| `jules-gate wait <id...> --timeout 30` | Polls sessions in terminal background | **Consumes 0 LLM input tokens while waiting** |
| `jules-gate verify <id> [base_branch]` | Pulls patch to clean branch & runs tests | **Auto-detects pytest, npm, cargo, go, mvn** |
| `jules-gate merge <id> [base] [--delete-remote]` | Auto-rebases and merges review branch | **Serialized auto-rebase prevents semantic conflicts** |
| `jules-gate pr <id> [base_branch]` | Pushes verified branch & opens GitHub PR | **Guaranteed green CI, zero wasted runner hours** |
| `jules-gate ps` | Lists remote Jules sessions and statuses | **Multi-session process monitoring** |
| `jules-gate status` | Checks health of plugin, CLI, and scripts | **Immediate environment diagnostic** |

### Step 0 Triage Rules:
* 🟢 **Maximize Delegation to Jules:** Default to delegating as much as possible—standalone modules, algorithms, parsers, test suites, refactoring, code reviews, research spikes.
* ⚡ **Efficiency Override (Local Option):** If delegating becomes inefficient and we expect more tokens than local execution (e.g. trivial 1-line syntax/import fixes, single version bumps, quick regex adjustments), choose local execution directly on the IDE thread.
* 🔴 **Keep on Local Agent:** Local Docker daemons, localhost DBs (Mongo/Postgres), uncommitted `.env` secrets, massive local file forensics.
* 🟡 **Split the Task:** Isolate domain logic for Jules; wire local secrets/DB connections locally.

---

## 💰 The 6-Layer Token Sparing Architecture: How Exactly Tokens Are Saved

This toolset is engineered with a single primary directive: **eliminate LLM token waste across the entire software development lifecycle**. Here is how each layer operates:

1. **Layer 1: Zero Local Code Generation (Cloud VM Offloading)**
   * Instead of the local agent generating thousands of lines of boilerplate, algorithms, or unit tests in chat (burning 20k–50k output tokens per turn), tasks are dispatched to Google Jules in dedicated cloud VMs.
   * The local environment only pulls a compact git patch upon completion.

2. **Layer 2: Zero-Token OS Background Polling (`jules-gate wait`)**
   * Active polling in an LLM conversation loop (e.g. running `sleep(30s)` or `schedule` repeatedly over a 100k context window) burns massive tokens: 147 polling loops burned >7M tokens in session `fa8e45b5`, and 42 loops burned 945k tokens in `fe4aa44b`.
   * `jules-gate wait` runs as an asynchronous native OS terminal process. The LLM process stops calling tools and is completely suspended (consuming **0 input/output tokens while waiting**). The OS wakes the LLM automatically upon task conclusion.

3. **Layer 3: Pre-Dispatch Research Delegation (Sub-Agent `Model: 'flash'`)**
   * When a user asks to "inspect", "explore", or "investigate" a repository or workflow, the primary Pro agent does NOT read 30+ files locally (which burned 238k tokens in `fe4aa44b`).
   * A disposable `research` subagent (`flash`) explores the codebase and returns a single concise synthesis (<500 words), keeping the primary context under 10k tokens.

4. **Layer 4: Multi-Tier Sub-Agent Context Firewalls (`flash_lite` & `flash`)**
   * Rote CLI commands (`jules remote new`, git checkout) run on `flash_lite` (~1x cost).
   * Test runs, git worktree gating, and merge conflict resolution run in an ephemeral `flash` subagent (~3x cost).
   * The primary `pro` agent (~15–20x cost) makes **0 tool calls** during execution. All test outputs, diffs, and debugging logs remain sealed inside the throwaway sub-agent context.

5. **Layer 5: Test Failure Diagnostics Sieve & `tail -n 40` Cap**
   * When unit tests fail in large projects, test runners often dump 2,000+ lines of stack traces and stdout into the terminal.
   * `worktree_gate.sh` filters output with an assertion sieve (`grep -E "^(FAILED|ERROR|FAIL:)"`) and caps the output with `tail -n 40`, reducing log bloat by 95%.

6. **Layer 6: Serialized Auto-Rebase & Pre-Dispatch Contract Linter**
   * `jules-gate lint` verifies repo connections and prompt bounds *before* cloud dispatch, eliminating failed runs.
   * `jules-gate merge` automatically detects when target branches have advanced, rebasing parallel review branches sequentially to avoid circular retry loops and merge hallucinations.

---

## 1. Automated Task Separation & Splitting Engine

When an incoming user request contains both delegatable logic and local infrastructure dependencies, automatically split the task:

$$\text{User Request} \longrightarrow \mathbf{\text{Component A (Remote EULIS)}} \;+\; \mathbf{\text{Component B (Local Agent)}}$$

```
                ┌─────────────────────────────────────────────────────────┐
                │                       USER TASK                         │
                │ "Add MongoDB User Caching with Redis & Token Refresh"   │
                └────────────────────────────┬────────────────────────────┘
                                             │
                      ┌──────────────────────┴──────────────────────┐
                      ▼                                             ▼
       ┌─────────────────────────────┐               ┌─────────────────────────────┐
       │   COMPONENT A (Remote Jules)│               │   COMPONENT B (Local Agent) │
       │   [Zero Local Dependencies] │               │   [Local Dependencies Only] │
       │ • Pure CacheKey generation  │               │ • Connect to local MongoDB  │
       │ • In-memory cache interface │               │ • Read uncommitted .env     │
       │ • Token hashing & TTL logic │               │ • Wire Component A to DB    │
       │ • 100% Mock unit test suite │               │ • Run integration test suite│
       └─────────────────────────────┘               └─────────────────────────────┘
```

### The 4-Step Splitting Protocol:
1. **Define Abstract Interface:** Create clean protocols or abstract base classes (e.g. `UserRepositoryProtocol`, `CacheProviderInterface`).
2. **Dispatch Component A to Jules (via Sub-Agent):** Spawn a sub-agent to offload pure algorithms, data validation, cache key hashing, and mock unit tests to Jules.
3. **Wait & Verify Component A:** Sub-agent executes `jules-gate wait` and `jules-gate verify`.
4. **Local Integration (Component B):** Once Component A is merged, the local agent writes the minimal bridge connecting the live database and `.env` secrets.

---

## 2. Multi-Modal Delegation Catalog

Jules is not limited to standard feature coding. Use these standardized templates for different engineering needs:

### Mode 1: Feature & Parser Implementation
```markdown
### Task: Implement <Module / Feature Name>
#### 1. Context & Contract:
- Implement `function_name(param: Type) -> ReturnType` in `<path/to/file>`.
#### 2. Strict Guardrails:
- Zero Unauthorized Dependencies: Use only repo dependencies or standard libraries.
- AST / Regex Safety: Use negative lookbehinds `(?<!Server)` to avoid matching generic objects.
#### 3. Testing:
- Add comprehensive unit tests in `tests/test_<module>.<ext>`.
```

### Mode 2: Delegated Code Review & Security Auditing
```bash
# Generate diff of local branch or commit
git diff main...HEAD > .jules/review_target.patch

# Dispatch review to Jules
jules remote new --repo "<owner/repo>" << 'EOF'
### Task: Senior Code Review & Security Audit of .jules/review_target.patch
Please perform an in-depth senior engineering review of the patch.
Analyze:
1. Concurrency & Race Conditions: Thread safety, lock contention, asynchronous leaks.
2. Boundary Conditions & Null Checks: Edge cases, zero values, unicode handling.
3. Security & Injection: Injection vulnerabilities, unvalidated inputs, credential leaks.
4. Test Completeness: What tests are missing in this diff?
Produce a markdown report in `docs/reviews/review_<date>.md`.
EOF
```

### Mode 3: Delegated Exploratory Research & Spikes
```bash
jules remote new --repo "<owner/repo>" << 'EOF'
### Task: Exploratory Spike - Evaluate <Library / Architecture>
Investigate whether we can implement <Goal> using <Technology>.
1. Create an isolated prototype module in `src/experimental/`.
2. Write 3 sample unit tests demonstrating feasibility.
3. Document pros, cons, and performance trade-offs in `docs/spikes/<topic>.md`.
EOF
```

### Mode 4: Delegated Edge-Case & Fuzz Test Synthesis
```bash
jules remote new --repo "<owner/repo>" << 'EOF'
### Task: Synthesize 30+ Stress & Edge-Case Tests for <Module>
Inspect `<target_file>`. Create `tests/test_<target>_stress.<ext>`.
Cover:
- Malformed payloads and unexpected type coercion.
- Max-length strings, empty arrays, null bytes.
- Exception handling on network or IO boundaries.
All tests must execute cleanly with the project test runner.
EOF
```

---

## 3. Sub-Agent Execution Protocol (MANDATORY EXECUTION PATH)

> [!CAUTION]
> **Strict No-Polling Directive for Sub-Agents:**
> Sub-agents (especially `flash_lite`) must **NEVER** invoke `schedule` or `poll` in a loop with `manage_task` or `jules-gate ps` while `jules-gate wait` is running. Once `jules-gate wait` is launched, **stop calling tools** and let the platform wake you up automatically upon task exit.

When orchestrating any Jules task or verification suite:

```
[ Primary Agent (Orchestrator) ]
              │
              ▼ Calls invoke_subagent(...)
[ Background Sub-Agent (`Model: 'flash_lite'` or `'flash'`, `TypeName: 'self'`) ]
              ├── 1. Submits task: `jules remote new --repo <owner/repo>`
              ├── 2. Runs token-free watcher: `jules-gate wait <session_id>`
              ├── 3. Executes gated verification: `jules-gate verify <session_id>`
              ├── 4. Integrates branch: `jules-gate merge <session_id>`
              └── 5. Returns final message to Primary Agent
```

### Pre-Dispatch Research Sub-Agent Pattern:
When the user requests broad codebase exploration or workflow inspection, spawn a research sub-agent (Model: `flash`) to explore files and return a concise synthesis. This keeps the primary Pro context under 10k tokens.

### Post-Verification Reporting Delegation:
Instruct Tier 2 Analytic Verifier sub-agents (Model: `flash`) to generate and commit markdown reports directly under `docs/reports/` before returning their final summary.

### Invocation Parameters:

**Mechanical CLI Runner (flash_lite):**
```json
{
  "Subagents": [
    {
      "TypeName": "self",
      "Model": "flash_lite",
      "Workspace": "inherit",
      "Role": "Mechanical Worker",
      "Prompt": "Execute the following rote operations:\n1. jules remote new --repo <owner/repo> < .jules/task_prompt.md\n2. jules-gate wait <session_id> --timeout 30\n3. Return session completion status to parent."
    }
  ]
}
```

**Test Verifier (flash):**
```json
{
  "Subagents": [
    {
      "TypeName": "self",
      "Model": "flash",
      "Workspace": "inherit",
      "Role": "Analytic Verifier",
      "Prompt": "Execute the following verification lifecycle:\n1. jules-gate verify <session_id>\n2. If tests pass, jules-gate merge <session_id>\n3. Send a single structured summary to the parent agent upon completion."
    }
  ]
}
```

### Rules for the Primary Agent:
1. **Stop Calling Tools Immediately:** Once `invoke_subagent` is called, the primary agent must NOT poll or invoke further tools.
2. **Reactive Wakeup:** The IDE automatically wakes the primary agent when the sub-agent sends its final message.
3. **Zero Main-Thread Context Pollution:** All terminal logs, test outputs, and patch diffs remain in the sub-agent's isolated transcript.

---

## 4. Gated Integration (Merge vs. PR)

### Path A: Solo / Direct Integration
```bash
jules-gate merge <session_id> [base_branch]
```
*Merges the review branch into your target branch with `--no-ff` and cleans up the temporary branch.*

### Path B: Enterprise Gated Pull Request
```bash
jules-gate pr <session_id> [base_branch]
```
*Pushes the review branch to GitHub and opens a Pull Request using `gh pr create`. Guarantees green remote CI runs because local test gates already verified the diff.*

---

## 5. Parallel Merge Conflicts & Serialized Auto-Rebase

### Automated Serialized Rebase Engine:
When multiple parallel Jules branches finish across waves:
1. `jules-gate merge <session_id>` automatically detects if the base branch has advanced since the review branch was created.
2. If advanced, it automatically runs `git rebase <base_branch>` on `jules/review-<session_id>`.
3. If conflicts occur during rebase, it halts safely, aborts the rebase, and alerts with exit code 4.
4. Once rebased, the project test suite is verified before merging into `main`.

### Retry Limit Threshold:
* If review or tests fail: **Max 3 retries**.
* Provide Jules with the exact test failure output and failure diff.
* If 3 attempts fail, halt and escalate to the human developer.

---

## 6. Deploying Artifacts to Repository `docs/`

Capture all generated outputs (security reviews, spikes, benchmark summaries) under `docs/`:

```text
docs/
├── IMPLEMENTATION.md         # Architecture blueprints & release notes
├── reports/                  # Benchmark metrics & invariant verification logs
├── reviews/                  # Delegated Jules PR reviews & security audits
└── spikes/                   # Prototype research notes & RFC evaluations
```

- **Remote Direct:** Include output file in Jules prompt: `docs/reviews/review_<date>.md`. Integrate via `jules-gate merge <id> master`.
- **IDE Artifact Sync:** Copy session artifacts from `.gemini/antigravity/brain/` into `docs/reports/` and commit.
- **Verification History:** Record test suite runs: `./tests/test_invariants.sh > docs/reports/invariants_run_<date>.log 2>&1`.

---

## 7. IDE Onboarding & Pre-Dispatch Contract Linter

### Universal IDE Onboarding:
Works seamlessly across **Antigravity, Gemini CLI, VS Code, JetBrains, Cursor, and Terminal**:

```bash
# Run one-step installer to link binary and register global skill discovery
~/.gemini/config/plugins/jules-plugin/install.sh

# Verify global CLI health
jules-gate status
```

### Pre-Dispatch Contract Linter:
Before submitting expensive tasks to Jules cloud VMs, validate the contract and environment:

```bash
jules-gate lint <owner/repo> [prompt_spec.md]
```
Checks:
- `jules` CLI detected and authenticated in PATH.
- Target repository is connected to Jules (`jules remote list --repo`).
- Prompt file exists and contains bounded file paths or test assertions.
- Project automated test runner is detected (`pytest`, `npm test`, `cargo test`, `go test`).


