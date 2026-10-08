# Google Jules (EULIS) Task Controller Plugin (Version 2.5.0)

[![Version](https://img.shields.io/badge/version-2.5.0-blue.svg)](plugin.json)
[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](README.md)
[![Status](https://img.shields.io/badge/status-active-success.svg)](https://github.com/JMartynov/jules-plugin)

An enterprise, token-efficient orchestrator for **Google Jules (EULIS)**. Designed to maximize delegation across all software engineering workflows while strictly enforcing **sub-agent execution** via Dynamic Multi-Tier Model Routing to eliminate token bloat (empirically proven to save **>99.5% of main-thread tokens**).

> 📖 **Looking for step-by-step operational instructions or troubleshooting?**  
> Check the comprehensive [**Operational Runbook (`RUNBOOK.md`)**](RUNBOOK.md).

---

## ⚡ Core Operational Law: Mandatory Sub-Agent Execution

> [!IMPORTANT]
> **CRITICAL TOKEN RULE: DO NOT execute tests, polling, or verification directly in the primary context window.**
> 
> * **Empirical Evidence:** In benchmark testing, running invariant tests and status checks directly in the primary conversation consumed **1,037,426 tokens**. Offloading the exact same execution loop to a background sub-agent running on `Model: 'flash'` consumed only **~12,000 tokens** on the primary thread—a **98.8% token reduction**.
> * **Mandatory Architecture:** The primary orchestrator's sole responsibility is **planning, task splitting, and dispatching**. All CLI execution, Jules submission, `jules-gate wait` polling, and `jules-gate verify` testing MUST be delegated to an isolated sub-agent.

---

## 🌟 What's New in Version 2.5.0

* **Strict No-Polling Directive:** Prevented the 945k token Sub-Agent Polling Tax by strictly prohibiting loop-based tool calls when `jules-gate wait` is running.
* **4-Stage Lifecycle Token Insulation:** Updated routing to a 4-stage lifecycle ensuring the primary thread never runs out of context.
* **Pre-Dispatch Research Sub-Agent Pattern:** Introduced a pattern to spawn a research sub-agent (`flash`) before execution to summarize code context and save tokens.
* **Post-Verification Reporting Delegation:** Verifier sub-agents (`flash`) now generate and commit markdown reports natively before concluding.
* **Version Bump:** Bumped overarching plugin functionality to 2.5.0.

## 🌟 What's New in Version 2.4.0

* **Dynamic Multi-Tier Model Routing:** Introduced 3-tier routing (`flash_lite` mechanical worker, `flash` analytic verifier, `pro` cognitive architect) sparing >99.5% tokens.
* **`jules-gate ps` Command:** Native way to query running, completed, and failed cloud sessions directly through the wrapper.
* **Automated GitHub Actions CI Matrix:** `.github/workflows/ci.yml` running invariants across macOS and Ubuntu runners.
* **Test failure log redaction:** `tail -n 40` cap in `scripts/worktree_gate.sh` to prevent test log bloat.
* **Remote branch cleanup:** `jules-gate merge <session_id> --delete-remote` flag to clean up dangling tracking branches.
* **Portable POSIX Support:** Portable inline replacements in `tests/test_invariants.sh` to ensure compatibility across macOS and Ubuntu.
* **Sub-agent Delegation Architecture:** Empirical >99.5% primary context token savings benchmark.

---

## 🎯 The Core Philosophy: Maximize Delegation

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

### The Sub-Agent Polling Tax Case Study
In prior audits, we found that even when delegating to sub-agents, if a sub-agent attempted to aggressively poll (`jules-gate ps` or `manage_task`) in a tight schedule loop during a background `jules-gate wait`, it could still burn up to **945k tokens**. By introducing a **Strict No-Polling Directive**, once a sub-agent invokes `jules-gate wait`, it must stop calling tools and simply wait to be awoken by the IDE. This prevents the "Polling Tax".

### Pre-Dispatch Research Sub-Agent Pattern:
When the user requests broad codebase exploration or workflow inspection, spawn a research sub-agent (Model: `flash`) to explore files and return a concise synthesis. This keeps the primary Pro context under 10k tokens.

### Post-Verification Reporting Delegation:
Instruct Tier 2 Analytic Verifier sub-agents (Model: `flash`) to generate and commit markdown reports directly under `docs/reports/` before returning their final summary.

---

## ✂️ Automated Task Splitting (Handling Dependencies)

If a task touches local infrastructure (e.g. local Docker, localhost DB, uncommitted `.env` secrets), the orchestrator automatically splits it:

$$\text{User Task} \longrightarrow \mathbf{\text{Component A (Remote EULIS)}} \;+\; \mathbf{\text{Component B (Local Agent)}}$$

* **Component A (Cloud Jules):** Abstract interfaces, core business algorithms, data validation, and comprehensive mock unit test suites.
* **Component B (Local IDE):** Injecting `.env` credentials, setting up local connection pools, and running integration verification.

---

## 🚀 Quickstart Guide (3 Minutes)

### 1. Pre-flight Check
Verify that the CLI tools are authenticated:
```bash
jules-gate status
```

### 2. Dispatch a Task via Sub-Agent
Ask the assistant to dispatch:
> *"Dispatch implementing the Go tool extractor to Jules via sub-agent, supervise it, and verify the branch."*

The assistant spawns isolated sub-agents on appropriate models (`flash_lite` for mechanical routing, `flash` for test verifier) that run:
```bash
REPO="owner/repository"
# Flash Lite Model
jules remote new --repo "$REPO" < .jules/task_prompt.md
jules-gate wait <session_id> --timeout 30
# Flash Model
jules-gate verify <session_id>
jules-gate merge <session_id>
```

---

## 🛠️ CLI Reference: `jules-gate`

The universal orchestrator CLI is installed in your system PATH at `/Users/ivan/.local/bin/jules-gate`.

| Command | Syntax | Description |
| :--- | :--- | :--- |
| **`status`** | `jules-gate status` | Checks health of plugin, version, and script executable permissions. |
| **`wait`** | `jules-gate wait <id...> [--timeout M]` | Polls one or more sessions every 30s. Consumes **0 LLM tokens** while waiting. |
| **`verify`** | `jules-gate verify <id> [base_branch]` | Pulls patch to `jules/review-<id>`, applies diff, runs auto-detected tests, and reports pass/fail. |
| **`merge`** | `jules-gate merge <id> [base] [--delete-remote]` | Executes `verify`, merges into base branch with `--no-ff`, and deletes the review branch (and optionally the remote branch). |
| **`pr`** | `jules-gate pr <id> [base_branch]` | Executes `verify`, pushes branch to origin, and opens a GitHub PR via `gh pr create`. |
| **`ps`** | `jules-gate ps [flags]` | Lists remote Jules sessions, linked repositories, and their execution statuses. |
| **`help`** | `jules-gate help` | Displays available commands and usage guide. |

---

## 📂 Repository Layout

```text
jules-plugin/
├── .gitignore                               # Clean git tracking (ignores .jules/, *.patch)
├── LICENSE                                  # Apache License 2.0
├── README.md                                # Comprehensive guide & architecture (v2.4.0)
├── RUNBOOK.md                               # In-Depth Operational Runbook & Playbooks
├── install.sh                               # Global installer script
├── plugin.json                              # Manifest (v2.4.0)
├── bin/
│   └── jules-gate                           # Portable, self-contained orchestrator CLI
├── docs/                                    # System architecture, reviews, spikes & reports
│   ├── IMPLEMENTATION.md                    # Core v2.3.0 implementation documentation
│   ├── reports/                             # Invariant benchmark & verification logs
│   ├── reviews/                             # Delegated PR reviews & security audits
│   └── spikes/                              # Research spikes & RFC prototype evaluations
├── rules/
│   └── AGENTS.md                            # Always-on EULIS delegation & subagent policy
├── scripts/
│   ├── jules_poll_wait.sh                   # Token-free session watcher daemon
│   └── worktree_gate.sh                     # Automated multi-language test gate
├── skills/
│   └── jules-task-controller/
│       └── SKILL.md                         # Skill specification (v2.2)
└── tests/
    └── test_invariants.sh                   # Automated 24-point invariant test suite
```

---

## 📚 Deploying Artifacts to `docs/`

All generated outputs across the development lifecycle are version-controlled in `docs/`:

1. **Direct Jules Generation:** Instruct Jules to write directly to `docs/<category>/<file>.md` (e.g. `docs/reviews/review_auth.md`). When verified and merged with `jules-gate merge`, artifacts are integrated automatically.
2. **Promoting IDE Session Artifacts:** Copy conversation brain artifacts into `docs/` (`cp "$ARTIFACT_PATH" docs/reports/`) and commit.
3. **Archiving Verification Runs:** Pipe `./tests/test_invariants.sh` into `docs/reports/` to retain an immutable verification history.

---

## 📄 License
[Apache License 2.0](LICENSE)
