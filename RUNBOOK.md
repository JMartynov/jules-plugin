# Jules Task Controller: Operational Runbook

**Version:** 2.0.0  
**Target Audience:** Software Engineers, DevOps, Autonomous AI Agents (Antigravity / Gemini IDE, Claude Code, Cursor, JetBrains, VS Code)  
**System Repository:** [`https://github.com/JMartynov/jules-plugin`](https://github.com/JMartynov/jules-plugin)

---

## 📑 Table of Contents
1. [Architecture & Workflow Overview](#1-architecture--workflow-overview)
2. [Pre-flight Checklist & Environment Setup](#2-pre-flight-checklist--environment-setup)
3. [Step 0: Delegation Feasibility Triage](#3-step-0-delegation-feasibility-triage)
4. [Step 1: Formulating Product-Agnostic Tasks](#4-step-1-formulating-product-agnostic-tasks)
5. [Step 2: Sub-Agent Dispatch & Zero-Token Polling](#5-step-2-sub-agent-dispatch--zero-token-polling)
6. [Step 3: Gated Verification & Test Execution](#6-step-3-gated-verification--test-execution)
7. [Step 4: Integration Decisions (Merge vs. PR)](#7-step-4-integration-decisions-merge-vs-pr)
8. [Parallel Execution & Merge Conflict Playbook](#8-parallel-execution--merge-conflict-playbook)
9. [Troubleshooting & Failure Modes](#9-troubleshooting--failure-modes)

---

## 1. Architecture & Workflow Overview

The Jules Task Controller implements a **tri-tier hybrid orchestration architecture** designed to maximize developer throughput and minimize token consumption:

```
                      ┌──────────────────────────────────────┐
                      │        Main Orchestrator (IDE)       │
                      │  • Architecture & Plan Decomposition │
                      │  • Step 0 Feasibility Triage         │
                      └──────────────────┬───────────────────┘
                                         │ Spawns isolated worker
                                         ▼
                      ┌──────────────────────────────────────┐
                      │    Sub-Agent (`flash`, Git Worktree) │
                      │  • Dispatches `jules remote new`     │
                      │  • Runs `jules-gate wait` (0 tokens) │
                      └──────────────────┬───────────────────┘
                                         │ Patch ready
                                         ▼
                      ┌──────────────────────────────────────┐
                      │       `jules-gate verify` Gate       │
                      │  • Pulls patch to isolated branch    │
                      │  • Auto-runs local test suite        │
                      └──────────────────┬───────────────────┘
                                         │
                        ┌────────────────┴────────────────┐
                        ▼                                 ▼
         [Tests Passed: Local/Solo]            [Tests Passed: Team/Protected]
           `jules-gate merge <id>`                 `jules-gate pr <id>`
            (Fast-forward / --no-ff)                (Verified GitHub PR via gh)
```

### The "Zero-Token Polling" Innovation
In naive AI agent workflows, monitoring an asynchronous remote agent (like Jules or GitHub Actions) involves sleep loops where the LLM re-reads its full conversation context on every check. In large sessions (100k+ token context), 20 status checks consume **over 2.4 million input tokens**.  
The `jules-gate wait` daemon runs natively in the terminal background, polling the CLI and sleeping with **0 LLM tokens consumed**.

---

## 2. Pre-flight Checklist & Environment Setup

Before executing any orchestration tasks, verify the local prerequisites:

```bash
# 1. Verify Jules CLI is installed and authenticated
which jules || npm install -g @google/jules
jules remote list --repo

# 2. Verify GitHub CLI (gh) authentication (for PR workflows)
gh auth status

# 3. Verify jules-gate CLI is in system PATH
which jules-gate
# If missing, link it:
ln -sfn ~/.gemini/config/plugins/jules-plugin/scripts/worktree_gate.sh ~/.local/bin/jules-gate

# 4. Verify Git repository is in a clean working state
git status -s
```

---

## 3. Step 0: Delegation Feasibility Triage

Not every task should be sent to a remote cloud VM. Run every incoming requirement through this 4-point feasibility matrix:

```
                            [ Incoming Task ]
                                    │
    ┌───────────────────────────────┴───────────────────────────────┐
    ▼                               ▼                               ▼
[Runtime Hardware / DB?]   [Uncommitted Secrets?]        [Massive Uncommitted Context?]
    │                               │                               │
   YES                             YES                             YES
    │                               │                               │
    ▼                               ▼                               ▼
[Keep Local / Mock]        [Keep Secrets Local]           [Run Forensics Locally First]
    │                               │                               │
    └───────────────────────────────┼───────────────────────────────┘
                                    │ NO to all blockers
                                    ▼
                       [Is it Modularity Independent?]
                       (Parsers, algorithms, unit tests,
                        refactors, bugfixes with repro)
                                    │
                                   YES
                                    ▼
                       [100% DELEGATABLE TO JULES]
```

### Triage Categorization Examples:
* **Fully Delegatable:**
  * Implementing a new AST extractor for TypeScript, Go, or Rust.
  * Creating an OpenAPI/Swagger parser with comprehensive unit tests.
  * Refactoring an existing utility class into a clean functional module.
  * Adding unit test coverage for an existing module.
* **Partially Delegatable (Split-Task):**
  * *Part A (Jules):* Write the business logic functions, data validation, and mock tests.
  * *Part B (Local):* Connect the module to local `.env` secrets or local Docker database instances.
* **Non-Delegatable (Keep 100% Local):**
  * Debugging an issue that only reproduces against a local Docker container or localhost database.
  * Ad-hoc exploratory forensics across thousands of local uncommitted files.
  * Tasks requiring interactive browser UI debugging or hardware USB tokens.

---

## 4. Step 1: Formulating Product-Agnostic Tasks

When writing tasks for Jules, provide generous, contract-first instructions. Never assume Jules has implicit context about internal product names.

### High-Yield Prompt Structure:
Save the prompt to `.jules/task_prompt.md`:

```markdown
### Task: <Clear, Descriptive Action Title>

#### 1. Context & Purpose:
Explain what needs to be implemented and why, using standard software engineering terms.

#### 2. Scope & Target Files:
- Files to create or modify:
  * `src/modules/<target_file>.<ext>`
  * `tests/test_<target_file>.<ext>`
- Function / Class Contracts:
  * `def parse_target(data: bytes) -> ParseResult:`
  * Explicitly specify argument types, return structures, and exception types.

#### 3. Strict Guardrails:
- Zero Unauthorized Dependencies: Use only the existing dependencies in the repository or language standard libraries.
- Defensive Pattern Matching: Use negative lookbehinds/lookaheads in regexes to prevent matching constructor declarations or generic object configurations.
- Backward Compatibility: Do not break existing public interfaces or test cases.

#### 4. Testing & Validation:
- Write comprehensive unit tests covering:
  1. Standard happy-path execution.
  2. Edge cases (empty inputs, malformed inputs, oversized inputs).
  3. Error handling and exception expectations.
- Ensure all tests pass using the project's standard test runner.
```

---

## 5. Step 2: Sub-Agent Dispatch & Zero-Token Polling

### 1. Launch Session via Jules CLI:
```bash
# Detect repository in owner/repo format
REPO=$(git config --get remote.origin.url | sed -E 's/.*github\.com[:\/](.*)\.git/\1/')

# Dispatch task to Jules
jules remote new --repo "$REPO" < .jules/task_prompt.md
```
*Take note of the `<session_id>` printed in the terminal output.*

### 2. Zero-Token Polling Wait:
Run `jules-gate wait` in the background or terminal:
```bash
# For a single session:
jules-gate wait 12814125760466192699 --timeout 30

# For multiple parallel sessions:
jules-gate wait 12814125760466192699 16133198684955322528 9266001727424468474 --timeout 45
```
The script will print progress updates every 30 seconds and exit with code `0` when all sessions complete.

---

## 6. Step 3: Gated Verification & Test Execution

Once the session finishes, run the verification gate:
```bash
jules-gate verify <session_id> [base_branch]
```

### Automated Gate Sequence:
1. **Pulls Remote Patch:** Downloads the diff into `.jules/patches/<session_id>.patch`.
2. **Creates Isolated Branch:** Checks out `jules/review-<session_id>` branched from your current working branch.
3. **Applies Diff:** Executes `git apply` with integrity checks.
4. **Auto-Detects Test Runner:**
   * Python (`pytest` / `unittest`)
   * TypeScript / JavaScript (`npm test` / `pnpm` / `yarn`)
   * Rust (`cargo test`)
   * Go (`go test ./...`)
   * Java / Kotlin (`mvn test` / `./gradlew test`)
5. **Execution Verdict:**
   * **Pass:** Commits verified changes to the review branch.
   * **Fail:** Displays test failure log, resets the working tree, and preserves your base branch from corruption.

---

## 7. Step 4: Integration Decisions (Merge vs. PR)

Choose the integration path that fits your project model:

### Option A: Fast-Track Merge (Solo / Internal Projects)
```bash
jules-gate merge <session_id> [base_branch]
```
*Merges the review branch into `<base_branch>` using `--no-ff`, removes the temporary review branch, and leaves your repository ready to push.*

### Option B: Gated Pull Request (Enterprise / Protected Teams)
```bash
jules-gate pr <session_id> [base_branch]
```
*Pushes `jules/review-<session_id>` to GitHub and opens a Pull Request via GitHub CLI (`gh`). Because tests already passed in Step 3, the remote GitHub Actions CI run will succeed without burning wasted runner hours.*

---

## 8. Parallel Execution & Merge Conflict Playbook

When running 2 to 5 Jules tasks simultaneously:

```
               ┌──► Task A ──► `jules/review-A` (Touches parser.py)
main branch ───┤
               └──► Task B ──► `jules/review-B` (Touches parser.py & cli.py)
```

### Resolution Procedure:
1. **Integrate Branch A First:**
   ```bash
   jules-gate merge <session_id_A> main
   ```
2. **Rebase Branch B onto Updated Main:**
   ```bash
   git checkout jules/review-<session_id_B>
   git rebase main
   ```
3. **Resolve Any Conflict Markers:**
   * If both tasks registered new handlers in a dictionary or switch statement, combine both entries.
   * If both tasks added test fixtures, keep both fixtures.
4. **Re-verify:**
   ```bash
   # Run project test suite
   pytest   # or npm test, cargo test
   git rebase --continue
   ```
5. **Integrate Branch B:**
   ```bash
   jules-gate merge <session_id_B> main
   ```

---

## 9. Troubleshooting & Failure Modes

### 1. `jules: command not found`
* **Fix:** Install globally:
  ```bash
  npm install -g @google/jules
  ```

### 2. `Authentication error: not logged in`
* **Fix:** Run the interactive login in terminal:
  ```bash
  jules login
  ```

### 3. Patch Application Fails (`git apply error: patch does not apply`)
* **Root Cause:** The base branch has drifted significantly since Jules started working.
* **Fix:** Use 3-way merge fallback:
  ```bash
  git checkout -b jules/review-<id> main
  git apply --3way .jules/patches/<id>.patch
  ```

### 4. Over-Eager Regex / AST Matches
* **Symptom:** Jules' patch breaks existing tests by matching generic class declarations or constructor calls.
* **Fix:** Add negative lookbehinds in the prompt or hotfix locally:
  ```python
  # Change:
  r'\{[^{}]*name:\s*["\']([^"\']+)["\']'
  # To:
  r'(?<!Server)\{[^{}]*name:\s*["\']([^"\']+)["\']'
  ```

### 5. Excessive Polling Token Consumption
* **Symptom:** LLM agent conversation grows by hundreds of thousands of tokens while waiting for Jules.
* **Fix:** Ensure you are using `jules-gate wait` in the terminal instead of an LLM `schedule` / sleep loop.
