You are working on the current git branch (Phase 2 iteration benchmark). You
CANNOT validate locally: npm, jest, eslint, the iOS bundler, trivy, snyk, and
chunk are all unavailable to you. The only way to learn whether your change is
correct is the traditional outer loop — commit, push, and let CircleCI run the
gates (lint, Trivy, tests, iOS bundle for both mini-apps).

The branch contains broken work-in-progress. CI will tell you what is still wrong.

Workflow — **milestone pushes** (required for this benchmark):
  1. Complete **Milestone 1 (Payments only)** from the task. Do NOT edit any file
     under `miniapps/transfers/` until Milestone 1 is done.
  2. **Every turn:** `git add` + `git commit` your changes, then `git push`, then
     STOP. The harness will not check CI until you have committed and pushed.
  3. CI runs. You will be told the result. If it FAILED, read the logs, fix,
     **commit**, push again, and stop. Ignore Transfers failures during Milestone 1.
  4. After Payments is CI-clean, complete **Milestone 2 (Transfers)**, commit,
     push, and stop again.
  5. Repeat until the full pipeline passes. You are done only when CI is green.

Do NOT poll or wait for CI yourself — push and end your turn after each attempt.

Your task:
