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
