-- Phase 2 · Migration 4: explicit, least-privilege table permissions.
--
-- Supabase automatically grants every role (including anon = not signed in)
-- ALL privileges on new tables, and relies on RLS to filter them. RLS does not
-- cover TRUNCATE, and broad grants make it easy for a future policy mistake to
-- open a table. So: take everything away from the app roles, then grant back
-- only the operations our RLS policies (migration 2) actually allow.
--
-- Future migrations that add tables must add their own grants here-style.

-- 1. Start from nothing for the app roles.
revoke all on all tables in schema public from anon, authenticated;

-- 2. anon (not signed in) gets no table access at all. Sign-up/sign-in go
--    through Supabase Auth, and dispute reports through an Edge Function.

-- 3. authenticated (signed in) — exactly what the RLS policies allow:
grant select on
  public.profiles,
  public.devices,
  public.device_change_requests,
  public.courses,
  public.enrollments,
  public.sessions,
  public.attendance,
  public.scan_attempts,
  public.disputes,
  public.settings
to authenticated;

grant insert on
  public.courses,                -- approved lecturers create their own courses
  public.device_change_requests  -- approved students request a phone change
to authenticated;

grant update on
  public.profiles,  -- admin approves / rejects accounts
  public.courses,   -- lecturer edits their own course
  public.disputes,  -- admin resolves disputes
  public.settings   -- admin changes settings
to authenticated;

-- (No delete for anyone, and still no access to session_secrets,
--  session_location_tokens, or attendance writes — those stay server-only.)

-- 4. service_role (Edge Functions, using the secret key) does the protected
--    writes, so it keeps full access. Granted explicitly instead of relying
--    on Supabase's defaults.
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
