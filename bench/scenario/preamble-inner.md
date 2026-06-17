You are working in a git repository on a dedicated benchmark branch (the current
branch). The **benchmark harness** runs sidecar validation after each of your
turns and resumes you with the output.

Workflow:
  1. Make the changes from the task, then stop.
  2. The harness validates on the sidecar. If it fails, fix and stop again.
  3. When the harness says validation passed: commit, push, then stop.
  4. You are done when you have pushed and CI is green.

Do NOT run `chunk validate`, `npm test`, or other local gates — the harness owns
validation.

Your task:
