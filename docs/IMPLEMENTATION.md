# Jules Task Controller v2.6.0 Implementation Details

This document comprehensively outlines the architectural changes, features, and optimizations introduced in **Version 2.6.0** of the Jules Task Controller.

---

## 1. 4-Stage Lifecycle Token Insulation (>99.5% Token Savings)

The v2.6.0 architecture evolves the system into an enterprise **4-stage multi-tier orchestration system** that dynamically routes tasks to the most efficient model, sparing over 99.5% of main-thread tokens.

**Token Comparison Matrix:**
| Architecture Approach | Token Cost | Notes |
| :--- | :--- | :--- |
| Monolithic (No Sub-agents) | ~1,000,000 tokens | Massive bloat from polling and test logs. |
| Uniform Flash (v2.3) | ~150,000 tokens | Sub-agent handles polling but uses heavier model. |
| Tiered Routing (v2.4) | ~25,000 tokens | `flash_lite` mechanical runner + `flash` verifier. |
| 4-Stage Lifecycle (v2.5.0) | <15,000 tokens | Pre-dispatch research + strict no-polling rules. |
| Full 6-Layer Shield (v2.6.0) | <10,000 tokens | Serialized auto-rebase, pre-dispatch linter, strict primary sweep ban. |

### The Sub-Agent Polling Tax Case Study
In prior audits, we found that even when delegating to sub-agents, if a sub-agent attempted to aggressively poll (`jules-gate ps` or `manage_task`) in a tight schedule loop during a background `jules-gate wait`, it could still burn up to **945k tokens**. By introducing a **Strict No-Polling Directive**, once a sub-agent invokes `jules-gate wait`, it must stop calling tools and simply wait to be awoken by the IDE. This prevents the "Polling Tax".

### Architecture Diagram (4-Stage Lifecycle)

```mermaid
sequenceDiagram
    participant Pro as Cognitive Architect (Pro)
    participant Research as Research Sub-Agent (flash)
    participant Lite as Mechanical Worker (flash_lite)
    participant Flash as Analytic Verifier (flash)
    participant OS as Background Daemon (Tier 0)
    
    %% Stage 1: Pre-Dispatch Research
    Pro->>Research: Pre-Dispatch Research Request
    Research-->>Pro: Concise Synthesis Report (Saves context)
    
    %% Stage 3 (Stage 2 is Pro formulating): Mechanical Execution
    Pro->>Lite: Invoke Mechanical Sub-Agent
    Lite->>OS: jules remote new
    Lite->>OS: jules-gate wait (Strict No-Polling loop)
    OS-->>Lite: Wait completes
    Lite-->>Pro: Session ID Status
    
    %% Stage 4: Analytic Verification & Reporting
    Pro->>Flash: Invoke Analytic Sub-Agent
    Flash->>OS: jules-gate verify
    OS-->>Flash: Test Results
    Flash->>OS: jules-gate merge (if pass)
    Flash->>OS: write docs/reports/verification.md
    Flash-->>Pro: Final Summary
```

### Pre-Dispatch Research Sub-Agent Pattern:
When the user requests broad codebase exploration or workflow inspection, spawn a research sub-agent (Model: `flash`) to explore files and return a concise synthesis. This keeps the primary Pro context under 10k tokens.

### Post-Verification Reporting Delegation:
Instruct Tier 2 Analytic Verifier sub-agents (Model: `flash`) to generate and commit markdown reports directly under `docs/reports/` before returning their final summary.

### Sub-Agent Invocation Examples

**Tier 1: flash_lite (Mechanical Worker)**
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

**Tier 2: flash (Analytic Verifier)**
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

**Tier 3: pro (Cognitive Architect)**
```json
{
  "Subagents": [
    {
      "TypeName": "self",
      "Model": "pro",
      "Workspace": "inherit",
      "Role": "Cognitive Architect",
      "Prompt": "Analyze the codebase for edge cases and formulate a step-by-step contract for the Analytic Verifier. NEVER run shell commands directly."
    }
  ]
}
```

---

## 2. Universal CLI Enhancements (`jules-gate`)

### A. The `ps` Command
We introduced a native way to query running, completed, and failed cloud sessions directly through the wrapper.

**Usage:**
```bash
jules-gate ps [flags]
```
- **Description:** Lists remote Jules sessions, linked repositories, and their execution statuses. Pass-through flags are forwarded to `jules remote list --session`.

### B. Remote Branch Cleanup (`--delete-remote`)
When fast-tracking merges for solo projects, dangling remote branches can clutter origin. `jules-gate merge` now includes a flag to wipe remote tracking branches automatically.

**Usage:**
```bash
jules-gate merge <session_id> [base_branch] --delete-remote
```
- **Action:** Merges the verified review branch locally and triggers a `git push origin --delete jules/review-<session_id>`.

---

## 3. Test Failure Log Redaction

Test log output from verification failures previously bloated primary agent contexts, often overflowing context windows when large stacks dumped into the console.

**Implementation Details (`scripts/worktree_gate.sh`):**
- Test runners (pytest, npm test, cargo test, etc.) execute with standard output and error redirected to a temporary log file (`/tmp/jules-test-XXXXXX.log`).
- **Cap Enforcement:** On failure, `tail -n 40` caps the output to only the last 40 lines.
- **Benefit:** Preserves vital stack traces and final assertion summaries while preventing tens of thousands of log lines from being fed back to the LLM.

---

## 4. Automated CI Matrix & Portable Validation

### A. GitHub Actions Matrix
Our invariant test suite is now enforced via an automated CI pipeline running on `.github/workflows/ci.yml`.

| Environment | Runner | Action |
| :--- | :--- | :--- |
| **Linux** | `ubuntu-latest` | Runs 24 invariants against bash/sh |
| **macOS** | `macos-latest` | Ensures compatibility with BSD userland |

### B. Portable POSIX Inline Replacements
To ensure 100% compatibility across both GNU/Linux and macOS BSD systems:
- Scripts like `tests/test_invariants.sh` were refactored to use standard inline POSIX tooling instead of relying on GNU-specific flags (`sed`, `awk`, standard bash loops).
- Resolves previous pathing and symlink resolution discrepancies for `jules-gate` pathing logic on macOS.

## 5. Artifact Deployment & Repository Documentation Taxonomy

All artifacts produced during EULIS delegation and agent orchestration are systematically captured under `docs/`:

```text
docs/
├── IMPLEMENTATION.md         # Comprehensive architectural & implementation blueprints
├── reports/                  # Test invariant runs, token benchmark metrics
├── reviews/                  # Delegated Jules PR reviews & security audits
└── spikes/                   # Prototype research notes & RFC evaluations
```

- **Remote-First Deployment:** When dispatching tasks to Jules, target markdown paths are directly specified in the prompt (`docs/reviews/review_<date>.md`). Upon gated merge (`jules-gate merge`), they become permanent tracked documentation.
- **IDE Artifact Promotion:** Interactive pair-programming artifacts from `.gemini/antigravity/brain/` can be copied directly to `docs/reports/` or `docs/spikes/` and committed to master.

## 6. v2.6.0 Enhancements: Auto-Rebase, Contract Linter & Diagnostic Sieve

### A. Serialized Auto-Rebase Engine
When merging parallel waves of Jules branches (such as the 5 parallel tracks in `fe4aa44b`), earlier merges advance the base branch, causing subsequent branches to diverge. 
- `jules-gate merge` now runs an automatic `git merge-base` comparison.
- If the base branch has advanced, it automatically executes `git rebase <base_branch>` on the review branch.
- If conflicts arise, it cleanly aborts (`git rebase --abort`) and returns exit code 4, preventing corrupted branches.

### B. Pre-Dispatch Contract Linter (`jules-gate lint`)
Prevents wasted cloud runs by verifying prerequisites prior to dispatch:
```bash
jules-gate lint <owner/repo> [prompt_spec.md]
```
- Confirms `jules` CLI is installed and authenticated.
- Queries `jules remote list --repo` to ensure repo authorization.
- Validates that prompt specs define concrete target paths and acceptance tests.
- Auto-detects local test runners (`pytest`, `npm test`, `cargo test`, `go test`).

### C. Test Failure Diagnostic Sieve
In `scripts/worktree_gate.sh`, failure output is parsed with an assertion sieve:
- `grep -E "^(FAILED|ERROR|=== FAIL|FAIL:)"` extracts the exact failing assertions.
- `tail -n 40` provides the immediate stack trace.
- Eliminates 2,000+ line log dumps, protecting sub-agent context windows.

---

## Architecture and Command Table

| Component | Location | Responsibility / Change in v2.6.0 |
| :--- | :--- | :--- |
| **`jules-gate` CLI** | `bin/jules-gate` | Added `lint` pre-flight command, added serialized auto-rebase to `merge`, added `ps` session viewer. |
| **Gated Verification** | `scripts/worktree_gate.sh` | Integrated diagnostic sieve (`grep` assertion filter) + `tail -n 40` log cap. |
| **Invariant Suite** | `tests/test_invariants.sh` | 31 automated assertions validating CLI, rules, no-polling directives, and test runners. |
| **Token Shield** | Architecture Standard | Benchmarked >99.5% token savings across 6-layer shield. |
| **Artifact Taxonomy** | `docs/` | Structured taxonomy for reviews, spikes, implementation, and reports. |

