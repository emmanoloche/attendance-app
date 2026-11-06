// Shared between the mobile app, the dashboard and (later) the Edge Functions.
// Real types and validation rules get added here from Phase 2 onwards.

export type Role = 'student' | 'lecturer' | 'admin';

export const APP_NAME = 'Attendance';

export type ConnectionResult = { ok: true } | { ok: false; reason: string };

// Pings Supabase Auth's health endpoint to prove the URL and key are correct
// and the server is reachable. Used by the Phase 1 "Hello" screens.
export async function checkSupabaseConnection(
  url: string | undefined,
  publishableKey: string | undefined,
): Promise<ConnectionResult> {
  if (!url || !publishableKey) {
    return { ok: false, reason: 'Supabase URL or key is missing from the .env file' };
  }
  try {
    const res = await fetch(`${url}/auth/v1/health`, {
      headers: { apikey: publishableKey },
    });
    if (res.ok) return { ok: true };
    if (res.status === 401) return { ok: false, reason: 'Supabase rejected the key (check the publishable key)' };
    return { ok: false, reason: `Supabase answered with status ${res.status}` };
  } catch {
    return { ok: false, reason: 'Could not reach Supabase (check the URL and your internet)' };
  }
}
