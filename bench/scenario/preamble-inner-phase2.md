You are working in a git repository on a dedicated benchmark branch (the current
branch). The **benchmark harness** runs sidecar validation after each of your
turns and will resume you with the output.

Workflow (Phase 2):
  1. Complete Milestone 1 (Payments) and Milestone 2 (Transfers) from the task.
  2. **Every turn:** make your edits, then `git add` + `git commit` **once** to record
     the work locally, then stop. One commit per turn — do not batch multiple commits.
     Do **not** commit `.claude/` or other harness files. Do **not** push until step 4.
  3. The harness validates on the sidecar. If it fails, fix, **commit again**,
     and stop. Repeat until validation passes on the **full repo** (both mini-apps).
  4. When the harness says validation passed on everything: `git push` **once**,
     then stop. The harness waits for CI — you are done only when CI is green.

Do NOT run `chunk validate`, `npm test`, `npm run lint`, or other local gates —
the harness owns validation.

Your task:
