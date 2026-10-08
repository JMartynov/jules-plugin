# Jules Task Controller Plugin (Version 2.0)

An enterprise, token-efficient orchestrator for **Google Jules (EULIS)**. Designed for parallel task execution, zero-token background polling, Git worktree isolation, automated multi-language testing, and gated review/PR integration.

---

## 🌟 Key Capabilities

1. **Zero-Token Polling (`jules-gate wait`):**  
   Eliminates the "polling tax" (which burned millions of tokens in naive LLM polling loops) by using a lightweight background daemon that sleeps in the terminal with **0 token consumption**.
2. **Delegation Feasibility Triage (Step 0):**  
   Automatically filters tasks with local hardware/runtime dependencies or uncommitted secrets before dispatching to remote Jules.
3. **Product-Agnostic & Language-Agnostic:**  
   Works universally across Python, TypeScript/JavaScript, Go, Rust, Java, and C# projects with automatic test runner detection (`pytest`, `npm test`, `cargo test`, `go test`, `mvn test`).
4. **Git Worktree Isolation:**  
   Enables multiple parallel Jules tasks to be pulled, built, and tested simultaneously without colliding in the local working tree.
5. **Gated Integration (Solo Merge vs. Verified PR):**  
   Guarantees that no unverified or broken Jules patches ever reach public GitHub PRs or trigger expensive remote CI runner hours.

---

## 🚀 Installation & Universal IDE Availability

### 1. Antigravity / Gemini IDE (Global Plugin)
This plugin is globally installed in:
```bash
~/.gemini/config/plugins/jules-plugin
```
It is automatically active across all projects and workspaces in Antigravity and Gemini.

### 2. Universal CLI (`jules-gate`) for All IDEs (VS Code, JetBrains, Cursor, Terminal)
The orchestrator CLI is installed directly in your system PATH at:
```bash
~/.local/bin/jules-gate
```

You can run `jules-gate` from any terminal or IDE:
```bash
# 1. Wait for one or multiple parallel Jules sessions without LLM token cost:
jules-gate wait <session_id1> <session_id2> --timeout 30

# 2. Pull, checkout review branch, apply patch, and run auto-detected tests:
jules-gate verify <session_id> [base_branch]

# 3. Verify and merge directly into your base branch (fast-forward or no-ff):
jules-gate merge <session_id> [base_branch]

# 4. Verify and push to GitHub, opening a verified Pull Request via `gh`:
jules-gate pr <session_id> [base_branch]
```

---

## 📂 Directory Structure

```text
jules-plugin/
├── plugin.json                              # Plugin Manifest (v2.0.0)
├── README.md                                # Documentation and setup guide
├── scripts/
│   ├── jules_poll_wait.sh                   # Token-free session watcher daemon
│   └── worktree_gate.sh                     # Automated multi-language test gate
└── skills/
    └── jules-task-controller/
        └── SKILL.md                         # Orchestration Skill (v2.0)
```

---

## 📄 License
Apache-2.0
