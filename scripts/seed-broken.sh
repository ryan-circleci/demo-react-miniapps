#!/usr/bin/env bash
#
# seed-broken.sh — apply the deterministic "broken" state for the demo.
#
# The fiction: an AI agent was asked to "make the Payments screen feel more
# welcoming". It added a welcome line and started a refactor by importing
# TouchableOpacity to make it tappable, but never finished.
#
# Result:
#   - ESLint fails: 'TouchableOpacity' is defined but never used
#
# One gate fails in chunk validate. The agent removes the unused import and
# the run goes green. (Single-failure demo — the test is left passing.)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/miniapps/payments/src/App.js"
TEST="$REPO_ROOT/miniapps/payments/__tests__/App.test.js"

cat > "$APP" <<'EOF'
import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';

const App = () => (
  <View style={styles.container}>
    <Text style={styles.welcome}>Welcome back</Text>
    <Text style={styles.title}>Welcome to Payments</Text>
  </View>
);

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  welcome: { fontSize: 14, color: '#666' },
  title: { fontSize: 24, fontWeight: 'bold' },
});

export default App;
EOF

cat > "$TEST" <<'EOF'
import React from 'react';
import { render } from '@testing-library/react-native';
import App from '../src/App';

test('renders Payments title', () => {
  const { getByText } = render(<App />);
  expect(getByText('Welcome to Payments')).toBeTruthy();
});
EOF

echo "Seeded broken state in:"
echo "  $APP"
echo "  $TEST"
echo ""
echo "Run 'chunk validate' (or just let the Stop hook fire) to see lint fail."
