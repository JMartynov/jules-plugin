# Google Jules (EULIS) Task Controller Plugin (Version 2.4.0)

[![Version](https://img.shields.io/badge/version-2.4.0-blue.svg)](plugin.json)
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

```
[ User Request in IDE ]
           │
           ▼
[ Step 0: Delegation Feasibility & Task Splitter ]
   ├── Fully Delegatable ────────► Component A: 100% to Jules via Sub-Agent
   ├── Partially Delegatable ────► Split: Component A (Jules) + Component B (Local)
   └── Strictly Local ───────────► Execute on Local IDE Thread
                                                │
       ┌────────────────────────────────────────┘
       ▼
[ Step 1: Multi-Modal Delegation Modes ]
   ├── Mode 1: Feature / Parser Implementation
   ├── Mode 2: Delegated Code Review & Security Audit
   ├── Mode 3: Exploratory Research Spike / Prototype
   └── Mode 4: Edge-Case & Fuzz Test Suite Synthesis
                               │
       ┌───────────────────────┘
       ▼
[ Step 2: MANDATORY Sub-Agent Dispatch (`Model: 'flash_lite'`, `TypeName: 'self'`) ]
   ├── Starts session: `jules remote new --repo <owner/repo>`
   └── Sleeps token-free: `jules-gate wait <session_id>`
           │
           ▼ (Remote VM finishes)
[ Step 3: Gated Verification (`jules-gate verify <id>`) ]
   ├── Pulls patch to isolated review branch (`jules/review-<id>`)
   ├── Auto-detects test runner (pytest, npm, cargo, go, mvn, gradle)
   └── Tests pass?
         ├── [NO]  ──► Reverts cleanly without corrupting base branch
         └── [YES] ──► Proceeds to Step 4
                               │
       ┌───────────────────────┘
       ▼
[ Step 4: Integration Strategy ]
   ├── Solo / Internal Project ──► `jules-gate merge <id>` (Fast-track --no-ff merge)
   └── Team / Protected Repo   ──► `jules-gate pr <id>` (Opens verified PR via gh CLI)
```

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
├── rules/
│   └── AGENTS.md                            # Always-on EULIS delegation & subagent policy
├── scripts/
│   ├── jules_poll_wait.sh                   # Token-free session watcher daemon
│   └── worktree_gate.sh                     # Automated multi-language test gate
├── skills/
│   └── jules-task-controller/
│       └── SKILL.md                         # Skill specification (v2.2)
└── tests/
    └── test_invariants.sh                   # Automated 21-point invariant test suite
```

---

## 📄 License
[Apache License 2.0](LICENSE)
