import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

const App = () => (
  <View style={styles.container}>
    <Text style={styles.welcome}>Welcome back, Alex</Text>
    <Text style={styles.title}>Transfers</Text>
  </View>
);

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  welcome: { fontSize: 14, color: '#666', marginBottom: 4 },
  title: { fontSize: 24, fontWeight: 'bold' },
});

export default App;
