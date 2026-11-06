import { APP_NAME, checkSupabaseConnection, type ConnectionResult } from '@attendance/shared';
import { useEffect, useState } from 'react';
import { StyleSheet, Text, View, useColorScheme } from 'react-native';

import { supabasePublishableKey, supabaseUrl } from '@/lib/supabase';

// Phase 1 "Hello" screen: proves the app runs on the phone and can reach Supabase.
export default function HelloScreen() {
  const [result, setResult] = useState<ConnectionResult | null>(null);
  // Set colours ourselves so text stays readable in both light and dark mode.
  const dark = useColorScheme() === 'dark';
  const colors = {
    background: dark ? '#000000' : '#ffffff',
    text: dark ? '#ffffff' : '#000000',
    muted: dark ? '#b0b4ba' : '#60646c',
  };

  useEffect(() => {
    checkSupabaseConnection(supabaseUrl, supabasePublishableKey).then(setResult);
  }, []);

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <Text style={[styles.title, { color: colors.text }]}>Hello from {APP_NAME} 👋</Text>
      <Text style={[styles.subtitle, { color: colors.muted }]}>Student app</Text>
      <Text style={[styles.status, { color: colors.text }]}>
        {result === null && 'Checking Supabase…'}
        {result?.ok && '✅ Connected to Supabase'}
        {result && !result.ok && `❌ ${result.reason}`}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, gap: 12 },
  title: { fontSize: 28, fontWeight: '700' },
  subtitle: { fontSize: 16 },
  status: { fontSize: 16, marginTop: 16, textAlign: 'center' },
});
