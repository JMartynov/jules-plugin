---
name: jules-task-controller
description: >-
  Orchestrate Google Jules (EULIS) coding tasks with automated task splitting, multi-modal delegation
  (features, code reviews, tests, research spikes), sub-agent concurrency, zero-token polling, and gated verification (Version 2.1).
  Use whenever planning, splitting, delegating, or verifying tasks assigned to Jules / EULIS across any programming language.
---

# Jules Task Controller (Version 2.1)

An enterprise orchestrator for **Google Jules (EULIS)**. Designed to maximize delegation of all software engineering tasks—including feature authoring, code review, test suite synthesis, and exploratory research—while mathematically eliminating token waste through zero-token polling and automated task splitting.

---

## ⚡ Quick Reference Cheat Sheet

| Command | Action | Key Benefit |
| :--- | :--- | :--- |
| `jules-gate wait <id...> --timeout 30` | Polls sessions in terminal background | **Consumes 0 LLM input tokens while waiting** |
| `jules-gate verify <id> [base_branch]` | Pulls patch to clean branch & runs tests | **Auto-detects pytest, npm, cargo, go, mvn** |
| `jules-gate merge <id> [base_branch]` | Merges verified branch with `--no-ff` | **One-step clean integration** |
| `jules-gate pr <id> [base_branch]` | Pushes verified branch & opens GitHub PR | **Guaranteed green CI, zero wasted runner hours** |

### Step 0 Triage Rules:
* 🟢 **Delegate to Jules:** Standalone modules, algorithms, parsers, test suites, refactoring, code reviews, research spikes.
* 🔴 **Keep on Local Agent:** Local Docker daemons, localhost DBs (Mongo/Postgres), uncommitted `.env` secrets, massive local file forensics.
* 🟡 **Split the Task:** Isolate domain logic for Jules; wire local secrets/DB connections locally.

---

## 1. Automated Task Separation & Splitting Engine

When an incoming user request contains both delegatable logic and local infrastructure dependencies, **do not reject delegation**. Automatically split the task:

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
1. **Define Abstract Interface:** Create the clean protocol or abstract base class (e.g. `UserRepositoryProtocol`, `CacheProviderInterface`).
2. **Dispatch Component A (Remote Jules):** Send the pure algorithms, data validation, cache key hashing, and mock unit tests to Jules.
3. **Wait & Verify Component A:** Wait token-free via `jules-gate wait`, then test via `jules-gate verify`.
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
### Task: Rigorous Code Review & Security Audit of .jules/review_target.patch
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

## 3. Sub-Agent Execution Protocol (Zero-Token Main Context)

When orchestrating Jules from Antigravity:

1. **Spawn Sub-Agent:**
   Invoke `invoke_subagent` with:
   * `Model: 'flash'` (fast, token-efficient)
   * `Workspace: 'share'` (provisions an isolated Git worktree so parallel tasks never conflict)
   * `Role: 'Jules Worker'`

2. **Wait Token-Free:**
   In the sub-agent or terminal, run:
   ```bash
   jules-gate wait <session_id> --timeout 30
   ```
   *For parallel tasks:*
   ```bash
   jules-gate wait <id1> <id2> <id3> --timeout 45
   ```

3. **Verify in Worktree:**
   ```bash
   jules-gate verify <session_id>
   ```

4. **Report to Orchestrator:**
   The sub-agent returns a single completion message to the main thread:
   > *"Session <id> completed. All tests passed (38/38). Changes committed to `jules/review-<id>`. Ready to merge."*

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
