# Google Jules (EULIS) Task Controller Plugin (Version 2.1)

[![Version](https://img.shields.io/badge/version-2.1.0-blue.svg)](plugin.json)
[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](README.md)
[![Status](https://img.shields.io/badge/status-active-success.svg)](https://github.com/JMartynov/jules-plugin)

An enterprise, token-efficient orchestrator for **Google Jules (EULIS)**. Designed to maximize delegation across all software engineering workflows—including feature implementation, automated code reviews, exploratory research spikes, and test suite synthesis—while mathematically eliminating token waste through zero-token polling and automated task splitting.

> 📖 **Looking for step-by-step operational instructions or troubleshooting?**  
> Check the comprehensive [**Operational Runbook (`RUNBOOK.md`)**](RUNBOOK.md).

---

## 🌟 What's New in Version 2.1

* **Always-On Delegation Policy (`rules/AGENTS.md`):** Automatically triages every prompt entering the IDE to maximize Jules delegation without needing manual invocation.
* **Automated Task Separation Engine:** Decouples complex requests into **Component A (Cloud EULIS)** for core domain logic & mock tests, and **Component B (Local Agent)** for local secrets & database wiring.
* **Multi-Modal Delegation:** Standardized workflows to offload **Code Reviews**, **Exploratory Spikes**, and **30+ Fuzz/Stress Tests** directly to Jules.
* **Zero-Token Watcher:** `jules-gate wait` monitors background tasks natively in the terminal with **0 LLM input tokens consumed**.

---

## 🎯 The Core Philosophy: Maximize Delegation

When pairing local IDE agents with Google Jules, the goal is to offload maximum heavy lifting to the cloud:

```
[ User Request in IDE ]
           │
           ▼
[ Step 0: Delegation Feasibility & Task Splitter ]
   ├── Fully Delegatable ────────► Component A: 100% to Jules
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
[ Step 2: Dispatch to Jules Sub-Agent (`Model: 'flash'`, Git Worktree) ]
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
which jules && jules remote list --repo
which jules-gate
```

### 2. Dispatch a Task
Create a prompt file `.jules/task_prompt.md` with your requirements, then dispatch:
```bash
REPO="owner/repository"
jules remote new --repo "$REPO" < .jules/task_prompt.md
```
*Note the returned `<session_id>` (e.g. `12814125760466192699`).*

### 3. Wait Token-Free
```bash
# Monitor single or multiple sessions simultaneously:
jules-gate wait 12814125760466192699 --timeout 30
```

### 4. Verify & Integrate
```bash
# Option A: Fast-track merge directly into your current branch
jules-gate merge 12814125760466192699

# Option B: Push review branch and open a verified GitHub PR
jules-gate pr 12814125760466192699
```

---

## 🛠️ CLI Reference: `jules-gate`

The universal orchestrator CLI is installed in your system PATH at `/Users/ivan/.local/bin/jules-gate`.

| Command | Syntax | Description |
| :--- | :--- | :--- |
| **`wait`** | `jules-gate wait <id...> [--timeout M]` | Polls one or more sessions every 30s. Consumes **0 LLM tokens** while waiting. |
| **`verify`** | `jules-gate verify <id> [base_branch]` | Pulls patch to `jules/review-<id>`, applies diff, runs auto-detected tests, and reports pass/fail. |
| **`merge`** | `jules-gate merge <id> [base_branch]` | Executes `verify`, merges into base branch with `--no-ff`, and deletes the review branch. |
| **`pr`** | `jules-gate pr <id> [base_branch]` | Executes `verify`, pushes branch to origin, and opens a GitHub PR via `gh pr create`. |
| **`help`** | `jules-gate help` | Displays available commands and usage guide. |

---

## 📂 Repository Layout

```text
jules-plugin/
├── .gitignore                               # Clean git tracking (ignores .jules/, *.patch)
├── LICENSE                                  # Apache License 2.0
├── README.md                                # Comprehensive guide & architecture
├── RUNBOOK.md                               # In-Depth Operational Runbook & Playbooks
├── install.sh                               # Global installer script
├── plugin.json                              # Manifest (v2.1.0)
├── bin/
│   └── jules-gate                           # Portable, self-contained orchestrator CLI
├── rules/
│   └── AGENTS.md                            # Always-on EULIS delegation policy
├── scripts/
│   ├── jules_poll_wait.sh                   # Token-free session watcher daemon
│   └── worktree_gate.sh                     # Automated multi-language test gate
└── skills/
    └── jules-task-controller/
        └── SKILL.md                         # Orchestration Skill specification (v2.1)
```

---

## 📄 License
[Apache License 2.0](LICENSE)
