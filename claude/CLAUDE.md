# EULIS Delegation-First Operational Policy for Claude Code

## 🎯 Core Operating Mandate

1. **Maximize Delegation to Jules-Gate:**
   Whenever possible, delegate heavy coding, codebase explorations, and test suites to `jules-gate`. You must use the `jules_dispatch` MCP tool or direct `jules remote new` command to offload work.

2. **Zero-Token OS Polling / Waiting:**
   After dispatching a task, you MUST wait for it to complete using the `jules_wait` tool or `jules-gate wait <session_id> --interactive` in the shell. **Do not use your own polling loops.** This ensures zero-token waiting. 

3. **Gated Verification Before Merging:**
   Before merging any review branch into the main codebase, you MUST verify the changes using `jules_verify` tool or `jules-gate verify <session_id> [base_branch]`. Only proceed to merge via `jules_merge` tool or `jules-gate merge <session_id> [base_branch]` if the verification is successful.

4. **Handling Interactive State with 3-Tier Escalation:**
   - Tasks may enter an interactive state ("Awaiting User Feedback").
   - **Auto-Answer:** Use `--interactive` with `jules-gate wait` (or the `jules_auto_answer` tool) to resolve standard boilerplate.
   - **Inspect & Clarify:** If auto-answer fails, use `jules_inspect` to read the question. If you can answer it based on instructions, use `jules_interact` to supply the answer.
   - **Escalate:** If you lack context, escalate to the user. Do not attempt to merge an interactive task.

## 🧱 Mandatory Sub-Agent Execution (same model as Antigravity)

Do not run Jules dispatch, waiting, verification or merging in the main thread. Use the Agent tool with these sub-agents (installed in `~/.claude/agents/`):

| Antigravity tier | Claude Code sub-agent | Model | Does |
| :--- | :--- | :--- | :--- |
| research (`flash`) | `jules-researcher` | haiku | Read-only repo exploration before you write the prompt; returns under 400 words |
| Tier 1 (`flash_lite`) | `jules-dispatcher` | haiku | `jules-gate lint`, `jules remote new` (and sending a message you wrote); returns STATUS and session id; never waits |
| Tier 2 (`flash`) | `jules-verifier` | sonnet | `jules-gate verify`, diff check, `jules-gate merge` into the named branch; returns counts and result |
| Tier 3 (`pro`) | you (main thread) | - | Triage, prompt writing, splitting, answering questions, deciding |

Flow: (optional) researcher → you write the prompt file → `jules-dispatcher` (dispatch only: lint, `jules remote new`, returns the session id at once) → **you start the watcher yourself in the background**: Bash with `run_in_background: true` and the command `~/.claude/jules-watch.sh <session_id>` (zero tokens, no 10-minute cap; the harness wakes you when it exits). Never rely on a bounded sub-agent wait: twice it ended minutes before Jules asked a question and nobody was watching. When the watcher exits, read its last line `JULES_RESULT status=...`: `COMPLETED` → start the verifier with the session id, repo directory and target branch, then report to the user; `NEEDS_INPUT` → show the question to the user (answer yourself only if it restates the task contract, and then tell the user the exact text you sent), send the answer (dispatcher "send" mode or `jules-gate interact`), and **re-arm the watcher at once**; `TIMEOUT` (8 hours) or `FAILED` → tell the user. Every session you start must have a watcher running until it is COMPLETED or the user cancels it; if you are unsure, check with `pgrep -fl jules_poll_wait`. Retry limit for failed verification: 3 repair rounds (`jules-gate reply`), then escalate.

Rules: waiting is done only by the background `jules-watch.sh`; you make no polling calls (`jules-gate ps`, `sleep`) and do not paste test logs or diffs into the main thread. Efficiency override: a one-line fix or a trivial change is done locally, without Jules. Never merge into `main` or `master` unless the user named it; use a temporary branch.

## ✍️ Writing Jules prompts (lessons from real sessions)

- One goal per session; split big work by module. Prefer several narrow tasks over one large one (a typing task took 4 hours).
- No contradictory rules. For every hard rule give the fallback: "If it cannot be met, leave that part as it was, say so in the summary, do not ask."
- Name files and exact commands and the expected result (for example the test counts). Limit tool output: affected tests while working, the full suite once, `| tail` / `| cut` on noisy tools.
- Never repair in a Completed session (`jules-gate interact` warns). Start a fresh narrow task, or fix small problems locally: a few lines of typing or config are faster locally than any Jules round.
- Run `jules-gate lint <repo> <prompt_file>` first and act on its tips. Messages sent with `interact` carry the prefix `[sent via jules-gate]`; tell the user what you sent (the text), because Jules shows it as written by them.
- Before answering a Jules question yourself, check it restates the task contract; otherwise show the question to the user first. A question about changing a test expectation always goes to the user.
- Size: a plan of more than about four steps, or a size-L task, is split into separate narrow sessions, each with one command as its gate (a size-L task of nine steps failed twice after 2.5 to 3.7 hours). Files the gate blocks (`.github/workflows/`, `.env*`) are done locally.
- One attempt, then failed: if a session ends `Failed` or stalls, send it **one** continue-and-resolve message. If that also fails or stalls, the Jules task counts as failed: split it into narrower tasks or do it locally, and record the root cause in the task notes. Do not retry unchanged.
- Stale watcher: after you answer a question the session list may still say "Awaiting User Feedback" for a while, so the watcher can report the same question again. Check `jules-gate inspect <session>` (Interactive State NO = answered) before treating it as new, and re-arm only once the list status has changed.
- Tell Jules not to create scratch or helper scripts in the repo and to write each file once; helper-script patching wiped files and looped in earlier sessions.
- Jules' OAuth token expires overnight (HTTP 401 from `jules_api.py`); any `jules remote list` call refreshes it.


