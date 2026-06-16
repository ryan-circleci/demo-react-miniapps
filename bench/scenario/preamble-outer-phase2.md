You are working on the current git branch (Phase 2 iteration benchmark). You
CANNOT validate locally: npm, jest, eslint, the iOS bundler, trivy, snyk, and
chunk are all unavailable to you. The only way to learn whether your change is
correct is the traditional outer loop — commit, push, and let CircleCI run the
gates (lint, Trivy, tests, iOS bundle for both mini-apps).

The branch may contain a partial work-in-progress. CI will tell you what is still
broken.

Workflow:
  1. Make your change, commit it, and `git push`. Then STOP and end your turn.
  2. CI runs. You will be told the result. If it FAILED, you will be given the
     failure logs — fix the issue, commit, push again, and stop.
  3. Repeat until CI passes.

Do NOT attempt to poll, watch, or wait for CI yourself, and do not assume any
"scheduled wakeup" — just push and end your turn after each attempt; the CI
result will be delivered to you. You are done when CI passes.

Your task:
