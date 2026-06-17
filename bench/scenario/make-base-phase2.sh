#!/usr/bin/env bash
#
# make-base-phase2.sh
#
# Builds bench/base-phase2 from bench/base with layered defects that fail real
# gates in this repo's ESLint/Jest setup (see verify-phase2-seed.sh).
#
# Expected outer-loop sequence (milestone workflow):
#   Push 1 — Payments milestone: lint fail (unused vars)
#   Push 2 — Payments clean, Transfers not done: transfers test fail
#   Push 3 — green (or Push 2 if agent batches Transfers with Payments fixes)
#
# Prerequisite: bench/base must exist (run make-base.sh first).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
restore_branch() { git checkout -q "$START_BRANCH" 2>/dev/null || true; }
trap restore_branch EXIT

git rev-parse --verify -q bench/base >/dev/null || {
  echo "ERROR: bench/base missing — run: bash bench/scenario/make-base.sh" >&2
  exit 1
}

git checkout -q -B bench/base-phase2 bench/base
git reset -q --hard bench/base

cat > miniapps/payments/src/App.js <<'JS'
import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

const App = () => {
  const handleSend = () => {};
  const pendingTransfers = 2;
  const draftMemo = 'update tests after lint';

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

cat > miniapps/payments/__tests__/App.test.js <<'JS'
import React from 'react';
import { render } from '@testing-library/react-native';
import App from '../src/App';

const expectedButtonLabel = 'Send money';

test('renders Payments welcome and send button', () => {
  const { getByText } = render(<App />);
  expect(getByText('Welcome to Payments')).toBeTruthy();
  expect(getByText('Send Money')).toBeTruthy();
});
JS

cat > miniapps/transfers/__tests__/App.test.js <<'JS'
import React from 'react';
import { render } from '@testing-library/react-native';
import App from '../src/App';

test('renders Transfers title and welcome subtitle', () => {
  const { getByText } = render(<App />);
  expect(getByText('Transfers')).toBeTruthy();
  expect(getByText('Welcome back, Alex')).toBeTruthy();
});
JS

git add \
  miniapps/payments/src/App.js \
  miniapps/payments/__tests__/App.test.js \
  miniapps/transfers/__tests__/App.test.js
git commit -q -m "bench: phase2 layered seed (lint + payments test + transfers test) [skip ci]"

echo "bench/base-phase2 ready at $(git rev-parse --short HEAD)"
echo "  payments lint:  unused pendingTransfers, draftMemo (+ unused in test file)"
echo "  payments test:  expects 'Send Money' (wrong casing)"
echo "  transfers test: expects subtitle (App.js still title-only)"
