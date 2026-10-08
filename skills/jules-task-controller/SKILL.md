---
name: jules-task-controller
description: >-
  Orchestrate Google Jules (EULIS) coding tasks with mandatory sub-agent execution, automated task splitting,
  multi-modal delegation (features, code reviews, tests, research spikes), zero-token polling, and gated verification (Version 2.4.0).
  Use whenever planning, splitting, delegating, or verifying tasks assigned to Jules / EULIS across any programming language.
---

# Jules Task Controller (Version 2.4.0)

An enterprise orchestrator for **Google Jules (EULIS)**. Designed to maximize delegation across all software engineering workflows while strictly enforcing **sub-agent isolation** to eliminate token bloat (empirically proven to save **>99.5% of main-thread tokens** through Dynamic Multi-Tier Model Routing).

---

## ⚡ Core Operational Law: Mandatory Sub-Agent Execution

> [!IMPORTANT]
> **CRITICAL TOKEN RULE: DO NOT execute tests, polling, or verification directly in the primary context window.**
> 
> * **Empirical Evidence:** In benchmark testing, running invariant tests and status checks directly in the primary conversation consumed **1,037,426 tokens**. Offloading the exact same execution loop to a background sub-agent running on `Model: 'flash'` consumed only **~12,000 tokens** on the primary thread, and routing to `flash_lite` reduces this even further—a **>99.5% token reduction**.
> * **Mandatory Architecture:** The primary orchestrator's sole responsibility is **planning, task splitting, and dispatching**. All CLI execution, Jules submission, `jules-gate wait` polling, and `jules-gate verify` testing MUST be delegated to an isolated sub-agent.

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
| `jules-gate wait <id...> --timeout 30` | Polls sessions in terminal background | **Consumes 0 LLM input tokens while waiting** |
| `jules-gate verify <id> [base_branch]` | Pulls patch to clean branch & runs tests | **Auto-detects pytest, npm, cargo, go, mvn** |
| `jules-gate merge <id> [base_branch]` | Merges verified branch with `--no-ff` | **One-step clean integration** |
| `jules-gate pr <id> [base_branch]` | Pushes verified branch & opens GitHub PR | **Guaranteed green CI, zero wasted runner hours** |
| `jules-gate status` | Checks health of plugin, CLI, and scripts | **Immediate environment diagnostic** |

### Step 0 Triage Rules:
* 🟢 **Delegate to Jules:** Standalone modules, algorithms, parsers, test suites, refactoring, code reviews, research spikes.
* 🔴 **Keep on Local Agent:** Local Docker daemons, localhost DBs (Mongo/Postgres), uncommitted `.env` secrets, massive local file forensics.
* 🟡 **Split the Task:** Isolate domain logic for Jules; wire local secrets/DB connections locally.

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

## 5. Parallel Merge Conflicts & Retries

### Parallel Rebase Strategy:
When multiple parallel Jules branches finish:
1. Merge Branch A into `main`.
2. Rebase Branch B onto updated `main`:
   ```bash
   git checkout jules/review-<id_B> && git rebase main
   ```
3. Resolve any semantic or registration conflicts.
4. Run project tests (`pytest`, `npm test`, `cargo test`).
5. Complete rebase (`git rebase --continue`) and merge.

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

