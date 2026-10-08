# Google Jules (EULIS) Task Controller Plugin (Version 2.0)

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](plugin.json)
[![License](https://img.shields.io/badge/license-Apache--2.0-green.svg)](README.md)
[![Status](https://img.shields.io/badge/status-active-success.svg)](https://github.com/JMartynov/jules-plugin)

An enterprise, token-efficient orchestrator for **Google Jules (EULIS)**. Designed for parallel task execution, zero-token background polling, Git worktree isolation, automated multi-language testing, and gated review/PR integration.

> 📖 **Looking for step-by-step operational instructions or troubleshooting?**  
> Check the comprehensive [**Operational Runbook (`RUNBOOK.md`)**](RUNBOOK.md).

---

## 🎯 Why This Pipeline Exists

Google Jules is an autonomous, asynchronous coding agent that runs in remote cloud VMs to implement features, fix bugs, and refactor repositories. However, in real-world engineering workflows, pairing local IDE agents with Jules introduces several friction points:

1. **The "Polling Tax" (Token Explosion):**  
   Naive AI assistants check Jules' status by looping with timer tools (e.g. `schedule` + `jules remote list`). In large conversations (100k+ tokens context), checking status 20 times burns **over 2.4 million input tokens** purely on waiting!
2. **Broken Patch Pollution:**  
   Jules occasionally makes assumptions (e.g., using unauthorized libraries like `PyYAML` when the project requires zero dependencies, or writing over-eager regexes that match generic classes). Sending these straight to GitHub Pull Requests triggers expensive, lengthy CI runs (e.g. 45-minute workflows) and creates PR spam.
3. **Parallel Filesystem Collisions:**  
   When running 3–5 Jules tasks in parallel, checking out branches and applying patches on a single working tree causes Git checkout conflicts and dirty state.

### How Version 2.0 Solves This:
* **Zero-Token Daemon:** A background watcher (`jules-gate wait`) polls in the terminal and sleeps with **0 LLM tokens consumed**.
* **Delegation Feasibility Triage (Step 0):** Pre-screens tasks to ensure only self-contained, cloud-safe tasks are delegated, keeping local hardware, localhost DBs, and uncommitted secrets local.
* **Git Worktree Isolation:** Runs parallel tasks in isolated directories linked to the same repository.
* **Gated Verification Gate:** Runs local tests in 30 seconds before any code touches `main` or opens a public Pull Request.

---

## 🏛️ System Architecture

```
[ User Request in IDE ]
           │
           ▼
[ Step 0: Delegation Feasibility Gate ]
   ├── Local DB / Hardware / Secrets? ──► Keep on Local Agent
   └── Modular, Testable Code? ────────► Delegate to Jules
                                                │
       ┌────────────────────────────────────────┘
       ▼
[ Step 1: Formulate Generous, Contract-First Prompt ]
       │
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

## 🌐 Universal IDE Availability

This pipeline is engineered to be **editor-agnostic**:

| IDE / Environment | How It's Supported |
| :--- | :--- |
| **Antigravity / Gemini IDE** | Discovered globally as a plugin via [`~/.gemini/config/plugins/jules-plugin`](file:///Users/ivan/.gemini/config/plugins/jules-plugin) and skill [`~/.gemini/config/skills/jules-task-controller`](file:///Users/ivan/.gemini/config/skills/jules-task-controller). |
| **JetBrains (IntelliJ, PyCharm)** | Run `jules-gate` directly from the built-in Terminal or assign an IDE External Tool shortcut. |
| **VS Code / Cursor** | Available in the integrated terminal or via `.vscode/tasks.json`. |
| **Autonomous Sub-Agents** | Dispatched via `invoke_subagent` using `Model: 'flash'` and `Workspace: 'share'` (Git worktree). |

---

## 📋 Step 0 Triage Matrix: What to Delegate

| Category | Delegate to Jules? | Rationale |
| :--- | :---: | :--- |
| **Parsers & Static Extractors** | ✅ **YES** | Pure functions, isolated dependencies, easy to verify with unit tests. |
| **Unit Test Authoring** | ✅ **YES** | High-volume boilerplate, self-contained mock fixtures. |
| **Algorithm Implementation** | ✅ **YES** | Well-defined input/output contracts. |
| **Tasks requiring Local Docker / DB** | ❌ **NO** | Remote cloud VM cannot reach your machine's `localhost` or Docker daemon. |
| **Tasks with Uncommitted Secrets** | ❌ **NO** | Never expose `.env` or private tokens to remote repositories. |
| **Ad-Hoc Data Forensics** | ❌ **NO** | Exploratory queries across thousands of uncommitted files should stay local. |

---

## 📂 Repository Layout

```text
jules-plugin/
├── plugin.json                              # Plugin Manifest (v2.0.0)
├── README.md                                # Comprehensive guide & architecture
├── RUNBOOK.md                               # Operational runbook & troubleshooting
├── scripts/
│   ├── jules_poll_wait.sh                   # Token-free session watcher daemon
│   └── worktree_gate.sh                     # Automated multi-language test gate
└── skills/
    └── jules-task-controller/
        └── SKILL.md                         # Orchestration Skill specification
```

---

## 📄 License
[Apache License 2.0](LICENSE)
