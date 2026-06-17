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
