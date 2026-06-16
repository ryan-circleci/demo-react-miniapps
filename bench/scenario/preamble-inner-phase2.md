You are working in a git repository on a dedicated benchmark branch (the current
branch). A chunk-sidecar Stop hook automatically runs the full validation gate
set (install, lint, security scans, tests, iOS bundle for both mini-apps) on
your working tree every time you finish a turn, and injects any failures back to
you to fix. This is your source of truth — you do NOT need to wait for CI, and
you do NOT need to run any validation commands yourself.

Workflow (Phase 2 — push only when sidecar is green):
  1. Make your edits locally, then end your turn.
  2. The sidecar validates automatically. If it reports failures, fix them and
     end another turn — repeat until the sidecar reports **no failures**.
  3. When the sidecar is green, commit your changes and `git push` **once**.
  4. You are done when you have pushed and the sidecar reported no failures on
     your final working tree.

Do NOT push broken code to GitHub. Use the sidecar for fast feedback; push only
after validation passes.

Your task:
