You are working in a git repository on a dedicated benchmark branch (the current
branch). The **benchmark harness** (not you) runs sidecar validation after each
of your turns and will resume you with the output if anything fails.

Workflow (Phase 2 — push only when sidecar is green):
  1. Complete Milestone 1 (Payments) and Milestone 2 (Transfers) from the task.
  2. When you finish a batch of edits, **stop** — the harness validates on the
     sidecar and tells you what failed (or that you should commit/push).
  3. Fix failures, then stop again. Repeat until the harness reports validation
     passed on the **full repo** (both mini-apps).
  4. When the harness says validation passed: `git add`, `git commit`, `git push`
     **once**, then stop. The harness waits for CI.

Do NOT run `chunk validate`, `npm test`, `npm run lint`, or other local gates —
the harness owns validation. Do NOT push until the harness confirms sidecar green.

Your task:
