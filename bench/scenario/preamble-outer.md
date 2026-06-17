You are working on the current git branch. You CANNOT validate locally: npm,
jest, eslint, the iOS bundler, trivy, snyk, and chunk are all unavailable to
you. The only way to learn whether your change is correct is the traditional
outer loop — commit, push, and let CircleCI run the gates (lint, Trivy, tests,
iOS bundle for both mini-apps).

Workflow:
  1. **Every turn:** make your change, `git add` + `git commit`, then `git push`.
     Then STOP. The harness will not check CI until you have committed and pushed.
  2. CI runs. You will be told the result. If it FAILED, fix, commit, push, stop.
  3. Repeat until CI passes. You are done only when CI is green.

Do NOT poll or wait for CI yourself — the result will be delivered to you.

Your task:
