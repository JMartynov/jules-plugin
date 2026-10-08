# Jules Task Controller: Operational Runbook

**Version:** 2.4.0  
**Target Audience:** Software Engineers, DevOps, Autonomous AI Agents (Antigravity / Gemini IDE, Claude Code, Cursor, JetBrains, VS Code)  
**System Repository:** [`https://github.com/JMartynov/jules-plugin`](https://github.com/JMartynov/jules-plugin)

---

## 📑 Table of Contents
1. [Architecture & Workflow Overview](#1-architecture--workflow-overview)
2. [Mandatory Sub-Agent Isolation (>99.5% Token Savings)](#2-mandatory-sub-agent-isolation-995-token-savings)
3. [Pre-flight Checklist & Environment Setup](#3-pre-flight-checklist--environment-setup)
4. [Step 0: Delegation Feasibility Triage & Task Splitting](#4-step-0-delegation-feasibility-triage--task-splitting)
5. [Multi-Modal Delegation Playbooks (Code, Review, Spikes, Fuzzing)](#5-multi-modal-delegation-playbooks-code-review-spikes-fuzzing)
6. [Step 1: Formulating Product-Agnostic Tasks](#6-step-1-formulating-product-agnostic-tasks)
7. [Step 2: Sub-Agent Dispatch & Zero-Token Polling](#7-step-2-sub-agent-dispatch--zero-token-polling)
8. [Step 3: Gated Verification & Test Execution](#8-step-3-gated-verification--test-execution)
9. [Step 4: Integration Decisions (Merge vs. PR)](#9-step-4-integration-decisions-merge-vs-pr)
10. [Parallel Execution & Merge Conflict Playbook](#10-parallel-execution--merge-conflict-playbook)
11. [Troubleshooting & Failure Modes](#11-troubleshooting--failure-modes)

---

## 1. Architecture & Workflow Overview

The Jules Task Controller implements a **tri-tier hybrid orchestration architecture** designed to maximize developer throughput and minimize token consumption:

```
                      ┌──────────────────────────────────────┐
                      │        Main Orchestrator (IDE)       │
                      │  • Always-On Policy (rules/AGENTS.md)│
                      │  • Task Splitting & Decomposition    │
                      └──────────────────┬───────────────────┘
                                         │ Spawns isolated worker
                                         ▼
                      ┌──────────────────────────────────────┐
                      │  MANDATORY Sub-Agent (`flash`)       │
                      │  • Dispatches `jules remote new`     │
                      │  • Runs `jules-gate wait` (0 tokens) │
                      │  • Runs `jules-gate verify` & tests  │
                      └──────────────────┬───────────────────┘
                                         │ Single summary report
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

---

## 2. Mandatory Sub-Agent Isolation (>99.5% Token Savings)

> [!IMPORTANT]
> **Empirical Law:** Never execute Jules CLI dispatch, test execution loops, or status checks directly on the primary conversation thread.

### Empirical Benchmarks:
* **Primary Thread Execution:** Polling 20 times in a 100k context burned **~1,000,000 tokens**.
* **Uniform Flash Execution (v2.3):** Delegating the exact same lifecycle to a background sub-agent running on `Model: 'flash'` consumed **~150,000 tokens**.
* **Tiered Routing Execution (v2.4):** Using `flash_lite` mechanical runner + `flash` verifier consumes **~25,000 tokens**—a **>99.5% token reduction**.

### Sub-Agent Invocation Protocol:
The primary agent calls `invoke_subagent` and immediately halts tool calls.

**Tier 1: Mechanical Runner (flash_lite)**
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

**Tier 2: Analytic Verifier (flash)**
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

---

## 3. Pre-flight Checklist & Environment Setup

Before executing any orchestration tasks, verify the local prerequisites:

```bash
# 1. Verify health of plugin, version, and scripts
jules-gate status

# 2. Verify Jules CLI is installed and authenticated
which jules || npm install -g @google/jules
jules-gate ps --repo

# 3. Verify GitHub CLI (gh) authentication (for PR workflows)
gh auth status

# 4. Verify Git repository is in a clean working state
git status -s
```

---

## 4. Step 0: Delegation Feasibility Triage & Task Splitting

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

### The Automated Task Splitting Protocol:
When a task has local dependencies, do **not** abandon delegation. Automatically split the task into two decoupled components:

$$\text{Task} \longrightarrow \mathbf{\text{Component A (Cloud EULIS)}} \;+\; \mathbf{\text{Component B (Local Agent)}}$$

* **Component A (Cloud EULIS):**
  * Core domain algorithms, data validation, AST/regex parsing, and cache key computation.
  * Abstract interfaces and comprehensive mock unit tests (dispatched to Jules via Sub-Agent).
* **Component B (Local IDE):**
  * Uncommitted `.env` secrets, database connection pools, local Docker networking, and integration test execution.

---

## 5. Multi-Modal Delegation Playbooks (Code, Review, Spikes, Fuzzing)

### Playbook 1: Delegated Code Review & Security Auditing
Before merging a large PR or branch, offload the review to Jules:
```bash
git diff main...HEAD > .jules/review_target.patch

jules remote new --repo "$REPO" << 'EOF'
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

### Playbook 2: Delegated Exploratory Research & Spikes
When evaluating an external library or architectural approach, offload the spike:
```bash
jules remote new --repo "$REPO" << 'EOF'
### Task: Exploratory Spike - Evaluate <Library / Architecture>
Investigate whether we can implement <Goal> using <Technology>.
1. Create an isolated prototype module in `src/experimental/`.
2. Write 3 sample unit tests demonstrating feasibility.
3. Document pros, cons, and performance trade-offs in `docs/spikes/<topic>.md`.
EOF
```

### Playbook 3: Delegated Edge-Case & Fuzz Test Synthesis
```bash
jules remote new --repo "$REPO" << 'EOF'
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

## 6. Step 1: Formulating Product-Agnostic Tasks

When writing feature tasks for Jules, provide generous, contract-first instructions. Never assume Jules has implicit context about internal product names.

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

## 7. Step 2: Sub-Agent Dispatch & Zero-Token Polling

### 1. Launch Session via Jules CLI (Run by Sub-Agent):
```bash
REPO=$(git config --get remote.origin.url | sed -E 's/.*github\.com[:\/](.*)\.git/\1/')
jules remote new --repo "$REPO" < .jules/task_prompt.md
```

### 2. Zero-Token Polling Wait:
Run `jules-gate wait` in the background terminal:
```bash
jules-gate wait <session_id> --timeout 30
```
*For parallel tasks:*
```bash
jules-gate wait <id1> <id2> <id3> --timeout 45
```

---

## 8. Step 3: Gated Verification & Test Execution

Once the session finishes, run the verification gate:
```bash
jules-gate verify <session_id> [base_branch]
```

### Automated Gate Sequence:
1. **Pulls Remote Patch:** Downloads the diff into `.jules/patches/<session_id>.patch`.
2. **Creates Isolated Branch:** Checks out `jules/review-<session_id>` branched from your current working branch.
3. **Applies Diff:** Executes `git apply` with integrity checks.
4. **Auto-Detects Test Runner:**
   * Python (`python3 -m pytest` / `unittest`)
   * TypeScript / JavaScript (`npm test` / `pnpm` / `yarn`)
   * Rust (`cargo test`)
   * Go (`go test ./...`)
   * Java / Kotlin (`mvn test` / `./gradlew test`)
5. **Execution Verdict:**
   * **Pass:** Commits verified changes to the review branch.
   * **Fail:** Displays test failure log, resets the working tree, and preserves your base branch from corruption.

---

## 9. Step 4: Integration Decisions (Merge vs. PR)

### Option A: Fast-Track Merge (Solo / Internal Projects)
```bash
jules-gate merge <session_id> [base_branch] [--delete-remote]
```
*Merges the review branch into `<base_branch>` using `--no-ff`, removes the temporary review branch, and leaves your repository ready to push. If `--delete-remote` is passed, it also cleans up any remote tracking branch for the review branch.*

### Option B: Gated Pull Request (Enterprise / Protected Teams)
```bash
jules-gate pr <session_id> [base_branch]
```
*Pushes `jules/review-<session_id>` to GitHub and opens a Pull Request via GitHub CLI (`gh`). Because tests already passed in Step 3, the remote GitHub Actions CI run will succeed without burning wasted runner hours.*

---

## 10. Deploying Artifacts to Repository `docs/`

During development and automated delegation, multiple forms of artifacts are produced (delegated security reviews, research spikes, RFCs, architecture specs, and invariant test/benchmark reports). All artifacts should be systematically preserved and version-controlled under `docs/`.

### Directory Taxonomy:
```text
docs/
├── IMPLEMENTATION.md         # Comprehensive architectural & implementation blueprints
├── reviews/                  # Delegated Jules PR reviews & security audits
├── spikes/                   # Prototype research notes & RFC evaluations
└── reports/                  # Test invariant verification & token benchmark logs
```

### Deployment Strategy 1: Remote Jules Task Direct Deployment (Recommended)
When submitting tasks to Jules, mandate the artifact destination in the prompt so Jules writes it directly to the repository:

```bash
jules remote new --repo "$REPO" --session "### Task: Security Audit
1. Audit authentication flow in src/auth/.
2. Output your completed Markdown review artifact to:
   docs/reviews/review_\$(date +%Y%m%d)_auth.md
"
```
After completion, verify and merge via `jules-gate`:
```bash
jules-gate wait <SESSION_ID> --timeout 30
jules-gate verify <SESSION_ID> master
jules-gate merge <SESSION_ID> master
git push origin master
```

### Deployment Strategy 2: Promoting IDE / Agent Brain Artifacts
When artifacts are generated inside an Antigravity / Gemini IDE pair-programming session (stored in `.gemini/antigravity/brain/<conv_id>/`):

```bash
# 1. Identify generated artifact path
# (e.g., $APPDATA/brain/<conversation-id>/artifact.md)

# 2. Deploy to designated category directory
mkdir -p docs/reports docs/reviews docs/spikes
cp "\$ARTIFACT_PATH" docs/reports/verification_benchmark_\$(date +%Y%m%d).md

# 3. Stage, commit, and push
git add docs/
git commit -m "docs: deploy verification benchmark artifact to docs/reports/"
git push origin master
```

### Deployment Strategy 3: Automated Invariant Test Artifact Archival
To capture an immutable record of test suite runs and token savings benchmarks:
```bash
# Capture invariant test suite run to docs/reports/
./tests/test_invariants.sh > docs/reports/invariants_run_\$(date +%Y%m%d).log 2>&1
git add docs/reports/
git commit -m "docs: archive test invariant suite execution log"
git push origin master
```

---

## 11. Parallel Execution & Merge Conflict Playbook

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
3. **Resolve Any Conflict Markers:** Combine non-colliding declarations, preserve test fixtures.
4. **Re-verify:**
   ```bash
   python3 -m pytest   # or npm test, cargo test
   git rebase --continue
   ```
5. **Integrate Branch B:**
   ```bash
   jules-gate merge <session_id_B> main
   ```

---

## 12. Troubleshooting & Failure Modes

### 1. `jules-gate status` reports errors
* Run `~/.gemini/config/plugins/jules-plugin/install.sh` to refresh executable permissions and PATH symlinks.

### 2. Excessive Polling Token Consumption
* Ensure the primary agent called `invoke_subagent` and stopped calling tools. Do not check status in a loop on the primary thread.

### 3. Patch Application Fails (`git apply error: patch does not apply`)
* Use 3-way merge fallback:
  ```bash
  git checkout -b jules/review-<id> main
  git apply --3way .jules/patches/<id>.patch
  ```
