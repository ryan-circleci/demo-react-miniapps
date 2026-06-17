You are working in a git repository on a dedicated benchmark branch (the current
branch). The **benchmark harness** runs sidecar validation after each of your
turns and resumes you with the output.

Workflow:
  1. Make the changes from the task.
  2. **Every turn:** `git add` + `git commit` to record your work locally, then
     stop. Do not push until step 4.
  3. The harness validates on the sidecar. If it fails, fix, commit again, stop.
  4. When validation passes: `git push`, then stop. You are done when CI is green.

Do NOT run `chunk validate`, `npm test`, or other local gates — the harness owns
validation.

Your task:
