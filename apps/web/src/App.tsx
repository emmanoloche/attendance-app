import { APP_NAME, checkSupabaseConnection, type ConnectionResult } from '@attendance/shared'
import { useEffect, useState } from 'react'

import { supabasePublishableKey, supabaseUrl } from '@/lib/supabase'

// Phase 1 "Hello" page: proves the dashboard runs and can reach Supabase.
export default function App() {
  const [result, setResult] = useState<ConnectionResult | null>(null)

  useEffect(() => {
    checkSupabaseConnection(supabaseUrl, supabasePublishableKey).then(setResult)
  }, [])

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-3 p-6">
      <h1 className="text-3xl font-bold">Hello from {APP_NAME} 👋</h1>
      <p className="text-gray-500">Lecturer & admin dashboard</p>
      <p className="mt-4">
        {result === null && 'Checking Supabase…'}
        {result?.ok && '✅ Connected to Supabase'}
        {result && !result.ok && `❌ ${result.reason}`}
      </p>
    </main>
  )
}
