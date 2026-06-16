import React from 'react';
import { render } from '@testing-library/react-native';
import App from '../src/App';

const expectedButtonLabel = 'Send money';

test('renders Payments welcome and send button', () => {
  const { getByText } = render(<App />);
  expect(getByText('Welcome to Payments')).toBeTruthy();
  expect(getByText('Send Money')).toBeTruthy();
});
