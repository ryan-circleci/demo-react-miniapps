Complete the partially started Payments welcome feature and add a matching
personalized subtitle to the Transfers mini-app.

The Payments screen already has a work-in-progress implementation on this branch.
It is **not done** — you must fix whatever is broken and finish the requirements
below before stopping.

## Payments (`miniapps/payments/`)

1. Fix and complete `src/App.js`:
   - Keep the personalized welcome subtitle (e.g. "Welcome back, Alex").
   - Keep a tappable **"Send money"** button using `TouchableOpacity` with an
     `onPress` handler (`handleSend` defined in the component).
   - Code must pass ESLint (no undefined components, no unused variables).
2. Update `__tests__/App.test.js`:
   - Render the screen and assert the **"Send money"** button is present
     (exact text: `Send money`).

## Transfers (`miniapps/transfers/`)

3. In `src/App.js`, add a personalized welcome subtitle below the title
   (e.g. "Welcome back, Alex" — same pattern as Payments).
4. Update `__tests__/App.test.js` to assert the subtitle text is present.

## Gates (both mini-apps)

Everything must pass the project's validation gates: ESLint, Jest, Trivy security
scan, and iOS bundle build for **both** mini-apps. Do not weaken lint rules or
delete tests to make them pass.

When all gates pass, commit with a conventional-commit message and stop.
