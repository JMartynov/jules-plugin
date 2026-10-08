---
name: jules-task-controller
description: >-
  Orchestrate Google Jules (EULIS) coding tasks with sub-agent concurrency, feasibility triage gates,
  zero-token polling, isolated Git worktrees, and gated review/PR verification (Version 2.0).
  Use whenever starting, managing, monitoring, or reviewing tasks assigned to Jules / EULIS across any programming language.
---

# Jules Task Controller (Version 2.0)

An enterprise, token-efficient orchestrator for Google Jules (EULIS). Governs task triage, product-agnostic prompt generation, background sub-agent execution, zero-token polling, and gated verification.

---

## Architecture Lifecycle

```
[ User Request ]
       │
       ▼
[ Step 0: Delegation Feasibility & Dependency Gate ]
       ├── Non-Delegatable (Local DB, hardware, secrets) ──► Keep on Local Agent
       ├── Partially Delegatable ────────────────────────► Split: Jules (Logic) + Local (Wiring)
       └── Fully Delegatable ─────────────────────────────► Proceed to Step 1
                                                                    │
       ┌────────────────────────────────────────────────────────────┘
       ▼
[ Step 1: Formulate Generous, Product-Agnostic Task Plan ]
       │
       ▼
[ Step 2: Spawn Sub-Agent (`Model: 'flash'`, `Workspace: 'share'`) ]
       ├── Submits task: `jules remote new --repo <owner/repo>`
       └── Waits with ZERO token consumption: `jules-gate wait <session_id>`
               │
               ▼ (Session Completed)
[ Step 3: Gated Verification in Git Worktree ]
       └── Executes: `jules-gate verify <session_id>`
               ├── Auto-detects test runner (pytest, npm, cargo, go, mvn)
               └── Tests Pass?
                     ├── [YES] ──► Proceed to Step 4
                     └── [NO]  ──► Hotfix locally or Retry (Max 3 attempts)
                                           │
       ┌───────────────────────────────────┘
       ▼
[ Step 4: Integration (Local Merge vs. Verified PR) ]
       ├── Solo / Fast-track ──► `jules-gate merge <session_id> <target_branch>`
       └── Team / Protected  ──► `jules-gate pr <session_id> <target_branch>`
```

---

## Step 0: Delegation Feasibility & Dependency Gate

Before sending any task to Jules, run this 4-point triage:

| Criterion | Evaluation Question | Decision |
| :--- | :--- | :--- |
| **1. Runtime / Infrastructure** | Does execution require local Docker daemons, localhost databases (Postgres/Mongo), or physical hardware/WebUSB? | If **YES** ➔ Keep local or mock interface for Jules. |
| **2. Security & Secrets** | Does the task require access to uncommitted `.env` files, production API tokens, or private submodules? | If **YES** ➔ Keep secrets local; delegate only pure logic. |
| **3. Local Context Size** | Does the task require scanning thousands of uncommitted files or exploratory ad-hoc forensics? | If **YES** ➔ Perform data forensics locally first. |
| **4. Modularity & Tests** | Is the task a standalone parser, algorithm, feature module, unit test suite, refactor, or bugfix with clear repro? | If **YES** ➔ **100% Delegatable to Jules.** |

### Triage Outcomes:
* **Full Delegation:** Task is isolated and self-contained ➔ Proceed to Step 1.
* **Partial Delegation:** Split the work:
  1. Have Jules implement the algorithmic logic, data structures, and unit tests in isolation.
  2. Implement the local configuration, secret binding, or DB connection on the IDE main thread.
* **Non-Delegatable:** Implement directly on the local thread without sending to Jules.

---

## Step 1: Generous, Product-Agnostic Prompt Specification

When writing prompts for Jules, provide generous, self-contained notes that are **language- and product-agnostic**.

### Prompt Template:
```markdown
### Task: <Clear, Descriptive Title>

#### 1. Context & Objectives:
<Briefly explain WHAT needs to be accomplished and WHY, independent of proprietary internal names.>

#### 2. Architecture & File Scope:
- Target files to modify or create:
  * `<path/to/target/file>`
  * `<path/to/test/file>`
- Expected interface / function signatures:
  * `function_name(param: Type) -> ReturnType`

#### 3. Strict Guardrails:
- Zero Unauthorized Dependencies: Use only the existing dependencies in the repo or the language standard library.
- Regex & AST Safety: When matching patterns, use negative lookbehinds/lookaheads to prevent matching constructor declarations or generic object literals.
- Backward Compatibility: Existing behavior and test suites must not be broken.

#### 4. Verification & Testing:
- Add comprehensive, self-contained unit tests covering happy paths, boundary conditions, and invalid inputs.
- Ensure the test suite executes cleanly using standard project test conventions.
```

---

## Step 2: Sub-Agent Concurrency & Zero-Token Polling

To spare tokens on the main thread and enable parallel throughput:

1. **Invoke a Background Sub-Agent:**
   Use `invoke_subagent` with:
   - `Model: 'flash'` (drastically reduces token cost)
   - `Workspace: 'share'` (provisions an isolated Git worktree so parallel tasks never collide)
   - `Role: 'Jules Task Runner'`

2. **Submit Session via CLI:**
   ```bash
   cat << 'EOF' > .jules/task_prompt.md
   <Prompt from Step 1>
   EOF
   jules remote new --repo <owner/repo> < .jules/task_prompt.md
   ```
   *Record the returned `<session_id>`.*

3. **Zero-Token Polling Wait:**
   **DO NOT** poll in an LLM `schedule` loop! Run the universal watcher script:
   ```bash
   jules-gate wait <session_id> --timeout 30
   ```
   *For parallel tasks, pass multiple IDs simultaneously:*
   ```bash
   jules-gate wait <id1> <id2> <id3> --timeout 45
   ```
   *This command sleeps in the background terminal and consumes **0 LLM tokens** while waiting.*

---

## Step 3: Gated Verification in Git Worktree

Once Jules finishes, run the universal verification gate:
```bash
jules-gate verify <session_id> [base_branch]
```

### What `jules-gate verify` handles automatically:
1. Pulls remote patch to `.jules/patches/<session_id>.patch`.
2. Checks out a clean review branch: `jules/review-<session_id>`.
3. Applies the patch with safety checks (`git apply`).
4. **Auto-detects the project test runner:**
   * Python: `pytest` or `python3 -m unittest`
   * Node/TypeScript: `npm test`
   * Rust: `cargo test`
   * Go: `go test ./...`
   * Java: `mvn test` or `./gradlew test`
5. Runs test suite. If tests fail, it reverts cleanly to protect the branch.

---

## Step 4: Integration Decision (Local Merge vs. Verified PR)

Choose the integration strategy based on repository workflow:

### Mode A: Solo / Trunk-Based Repos (Direct Fast Integration)
```bash
jules-gate merge <session_id> <target_branch>
```
*Merges the verified review branch into `<target_branch>` with `--no-ff` and deletes the review branch.*

### Mode B: Team / Protected Repos (Verified Pull Request)
```bash
jules-gate pr <session_id> <target_branch>
```
*Pushes `jules/review-<session_id>` to GitHub and opens a Pull Request via GitHub CLI (`gh`). Because tests already passed in Step 3, the remote CI pipeline is guaranteed to succeed with zero wasted runner hours.*

---

## Step 5: Handling Merge Conflicts & Retries

### Parallel Merge Conflicts:
When merging multiple parallel branches (e.g., Branch A and Branch B):
1. Merge Branch A into `main`.
2. Rebase Branch B onto updated `main`:
   ```bash
   git checkout jules/review-<id2>
   git rebase main
   ```
3. If conflicts occur, inspect diffs, preserve both features' AST/logic registrations, and run the test runner.

### Retry Loop Threshold:
* If code fails review or tests: **Max 3 retries**.
* Provide Jules with the exact test failure output and diff of what went wrong.
* If 3 attempts fail, halt and escalate to the human developer.
