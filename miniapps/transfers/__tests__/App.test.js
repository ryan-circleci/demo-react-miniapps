import React from 'react';
import { render } from '@testing-library/react-native';
import App from '../src/App';

test('renders Transfers title and welcome subtitle', () => {
  const { getByText } = render(<App />);
  expect(getByText('Transfers')).toBeTruthy();
  expect(getByText('Welcome back, Alex')).toBeTruthy();
});
