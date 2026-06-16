import React from 'react';
import { render } from '@testing-library/react-native';
import App from '../src/App';

const expectedButtonLabel = 'Send money';

test('renders Payments welcome and send button', () => {
  const { getByText } = render(<App />);
  expect(getByText('Welcome back, Alex')).toBeTruthy();
  expect(getByText('Welcome to Payments')).toBeTruthy();
  expect(getByText(expectedButtonLabel)).toBeTruthy();
});
