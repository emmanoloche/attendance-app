-- Phase 2 · Migration 3 of 3: create a profile automatically when a student signs up.
--
-- Who gets a profile, and how:
--   * Student sign-up (from the app, with a matric number) → this trigger
--     creates a 'student' profile with status 'pending' (admin must approve).
--   * Lecturer → created by the invite-lecturer Edge Function (Phase 3).
--   * Admin → created by hand once (see supabase/manual/create_admin.sql).
--
-- SECURITY: sign-up details ("user metadata") are typed by the person signing
-- up, so role and status are NEVER read from them — every self sign-up is a
-- pending student, no matter what they send.

create function private.handle_new_user() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Only student sign-ups carry a matric number. Anything else (e.g. an
  -- admin invite) gets no profile here, so it has no access until a profile
  -- is created for it on purpose.
  if new.raw_user_meta_data ? 'matric_no' then
    insert into public.profiles (id, role, status, full_name, email, matric_no, level)
    values (
      new.id,
      'student',
      'pending',
      trim(new.raw_user_meta_data ->> 'full_name'),
      new.email,
      upper(trim(new.raw_user_meta_data ->> 'matric_no')),
      (new.raw_user_meta_data ->> 'level')::smallint
    );
  end if;
  return new;
end;
$$;

-- Only the database itself runs this, never the app.
revoke execute on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();
