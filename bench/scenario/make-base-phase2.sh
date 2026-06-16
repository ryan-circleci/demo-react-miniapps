#!/usr/bin/env bash
#
# make-base-phase2.sh
#
# Builds bench/base-phase2 from bench/base with a seeded WIP on Payments that
# reliably fails lint on the first validation (TouchableOpacity without import).
# Transfers stays clean; the task adds the subtitle + test there.
#
# Prerequisite: bench/base must exist (run make-base.sh first).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

git rev-parse --verify -q bench/base >/dev/null || {
  echo "ERROR: bench/base missing — run: bash bench/scenario/make-base.sh" >&2
  exit 1
}

git checkout -q -B bench/base-phase2 bench/base
git reset -q --hard bench/base

# --- Seeded WIP: lint fail (TouchableOpacity not imported) -------------------
cat > miniapps/payments/src/App.js <<'JS'
import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

const App = () => {
  const handleSend = () => {};

  return (
    <View style={styles.container}>
      <Text style={styles.welcome}>Welcome back, Alex</Text>
      <Text style={styles.title}>Welcome to Payments</Text>
      <TouchableOpacity onPress={handleSend} accessibilityRole="button">
        <Text style={styles.buttonLabel}>Send money</Text>
      </TouchableOpacity>
    </View>
  );
};

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  welcome: { fontSize: 14, color: '#666', marginBottom: 4 },
  title: { fontSize: 24, fontWeight: 'bold', marginBottom: 16 },
  buttonLabel: { fontSize: 16, color: '#007AFF' },
});

export default App;
JS

# Test still only checks title — agent must extend for the button (second fail
# if they fix lint but forget the test update).
# Uncomment the block below after dry-run if outer iterations stay at 1:
#
# cat > miniapps/payments/__tests__/App.test.js <<'JS'
# import React from 'react';
# import { render } from '@testing-library/react-native';
# import App from '../src/App';
#
# test('renders Payments welcome and send button', () => {
#   const { getByText } = render(<App />);
#   expect(getByText('Welcome to Payments')).toBeTruthy();
#   expect(getByText('Send Money')).toBeTruthy(); // wrong casing — fails until fixed
# });
# JS

git add miniapps/payments/src/App.js
git commit -q -m "bench: phase2 seeded WIP (lint fail: TouchableOpacity not imported)"

echo "bench/base-phase2 ready at $(git rev-parse --short HEAD)"
echo "  seeded: payments App.js uses TouchableOpacity without import (lint gate fail)"
echo "  clean:  transfers unchanged — task adds subtitle + test"
