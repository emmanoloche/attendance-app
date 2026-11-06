-- Phase 2 · Migration 2 of 3: who can see and change what (Row Level Security).
--
-- Rules of thumb:
--   * Students see only their own data and the courses they're enrolled in.
--   * Lecturers see only their own courses and the students in them.
--   * The admin sees everything.
--   * NOBODY writes attendance, sessions, devices or secrets from the app.
--     Those writes go through Edge Functions, which run on the server with
--     the secret key and do the checking (QR, GPS, device, enrolment).
--   * A table with RLS on and no policy for an action = that action is blocked.

-- ---------------------------------------------------------------------------
-- Helper checks used by the policies.
-- "security definer" lets them read the tables without triggering the same
-- policies again (which would loop). They only ever answer about the
-- signed-in user, so they can't leak anyone else's data.
-- ---------------------------------------------------------------------------
create function private.is_admin() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and role = 'admin' and status = 'approved' and is_active
  );
$$;

create function private.is_approved(p_role public.user_role) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and role = p_role and status = 'approved' and is_active
  );
$$;

-- Signed-in user is the (still active) lecturer of this course.
create function private.teaches_course(p_course_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.courses c
    join public.profiles p on p.id = c.lecturer_id
    where c.id = p_course_id
      and c.lecturer_id = (select auth.uid())
      and p.status = 'approved' and p.is_active
  );
$$;

-- Signed-in user is enrolled in this course.
create function private.is_enrolled(p_course_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.enrollments
    where course_id = p_course_id and student_id = (select auth.uid())
  );
$$;

-- Signed-in lecturer teaches a course this student is enrolled in.
create function private.teaches_student(p_student_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.enrollments e
    join public.courses c on c.id = e.course_id
    join public.profiles p on p.id = c.lecturer_id
    where e.student_id = p_student_id
      and c.lecturer_id = (select auth.uid())
      and p.status = 'approved' and p.is_active
  );
$$;

-- Signed-in student is enrolled in a course taught by this lecturer
-- (so students can see their lecturers' names).
create function private.is_my_lecturer(p_lecturer_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.courses c
    join public.enrollments e on e.course_id = c.id
    where c.lecturer_id = p_lecturer_id
      and e.student_id = (select auth.uid())
  );
$$;

-- Signed-in lecturer runs the course this session belongs to.
create function private.teaches_session(p_session_id uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.sessions s
    where s.id = p_session_id and private.teaches_course(s.course_id)
  );
$$;

-- Only signed-in users may use the helpers (and the join-code default).
revoke all on schema private from public;
grant usage on schema private to authenticated;
revoke execute on all functions in schema private from public;
grant execute on function
  private.is_admin(),
  private.is_approved(public.user_role),
  private.teaches_course(uuid),
  private.is_enrolled(uuid),
  private.teaches_student(uuid),
  private.is_my_lecturer(uuid),
  private.teaches_session(uuid),
  private.generate_join_code()
to authenticated;

-- ---------------------------------------------------------------------------
-- Turn RLS on for every table (blocks everything until a policy allows it)
-- ---------------------------------------------------------------------------
alter table public.profiles                enable row level security;
alter table public.devices                 enable row level security;
alter table public.device_change_requests  enable row level security;
alter table public.courses                 enable row level security;
alter table public.enrollments             enable row level security;
alter table public.sessions                enable row level security;
alter table public.session_secrets         enable row level security;
alter table public.session_location_tokens enable row level security;
alter table public.attendance              enable row level security;
alter table public.scan_attempts           enable row level security;
alter table public.disputes                enable row level security;
alter table public.settings                enable row level security;

-- Extra lock on the most sensitive tables: the app's roles get no access at
-- all, even if a policy were added by mistake later. Edge Functions use the
-- secret key (service_role), which is not affected.
revoke all on public.session_secrets         from anon, authenticated;
revoke all on public.session_location_tokens from anon, authenticated;
revoke insert, update, delete on public.attendance from anon, authenticated;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create policy "profiles: read own"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));

create policy "profiles: lecturers read their students"
  on public.profiles for select to authenticated
  using (private.teaches_student(id));

create policy "profiles: students read their lecturers"
  on public.profiles for select to authenticated
  using (private.is_my_lecturer(id));

create policy "profiles: admin reads all"
  on public.profiles for select to authenticated
  using (private.is_admin());

-- Approving/rejecting accounts. Nobody else can edit profiles in v1, so a
-- student can't promote themselves or approve their own account.
create policy "profiles: admin updates"
  on public.profiles for update to authenticated
  using (private.is_admin())
  with check (private.is_admin());

-- ---------------------------------------------------------------------------
-- devices (linking/unlinking is done by Edge Functions)
-- ---------------------------------------------------------------------------
create policy "devices: read own"
  on public.devices for select to authenticated
  using (user_id = (select auth.uid()));

create policy "devices: admin reads all"
  on public.devices for select to authenticated
  using (private.is_admin());

-- ---------------------------------------------------------------------------
-- device_change_requests
-- ---------------------------------------------------------------------------
create policy "device requests: read own"
  on public.device_change_requests for select to authenticated
  using (user_id = (select auth.uid()));

create policy "device requests: admin reads all"
  on public.device_change_requests for select to authenticated
  using (private.is_admin());

-- An approved student can open a request for themselves, and it must start
-- as pending (they can't submit it already approved).
create policy "device requests: students create own"
  on public.device_change_requests for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and private.is_approved('student')
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
  );

-- ---------------------------------------------------------------------------
-- courses
-- ---------------------------------------------------------------------------
create policy "courses: lecturer reads own"
  on public.courses for select to authenticated
  using (private.teaches_course(id));

create policy "courses: students read enrolled"
  on public.courses for select to authenticated
  using (private.is_enrolled(id));

create policy "courses: admin reads all"
  on public.courses for select to authenticated
  using (private.is_admin());

create policy "courses: approved lecturers create own"
  on public.courses for insert to authenticated
  with check (lecturer_id = (select auth.uid()) and private.is_approved('lecturer'));

create policy "courses: lecturer updates own"
  on public.courses for update to authenticated
  using (private.teaches_course(id))
  with check (lecturer_id = (select auth.uid()));

-- (Joining a course by code is done by a server function in Phase 4, so
-- students never need to search all courses.)

-- ---------------------------------------------------------------------------
-- enrollments
-- ---------------------------------------------------------------------------
create policy "enrollments: students read own"
  on public.enrollments for select to authenticated
  using (student_id = (select auth.uid()));

create policy "enrollments: lecturer reads own courses"
  on public.enrollments for select to authenticated
  using (private.teaches_course(course_id));

create policy "enrollments: admin reads all"
  on public.enrollments for select to authenticated
  using (private.is_admin());

-- ---------------------------------------------------------------------------
-- sessions (starting/opening/closing is done by Edge Functions)
-- ---------------------------------------------------------------------------
create policy "sessions: lecturer reads own courses"
  on public.sessions for select to authenticated
  using (private.teaches_course(course_id));

create policy "sessions: students read enrolled courses"
  on public.sessions for select to authenticated
  using (private.is_enrolled(course_id));

create policy "sessions: admin reads all"
  on public.sessions for select to authenticated
  using (private.is_admin());

-- ---------------------------------------------------------------------------
-- attendance (only Edge Functions write it)
-- ---------------------------------------------------------------------------
create policy "attendance: students read own"
  on public.attendance for select to authenticated
  using (student_id = (select auth.uid()));

create policy "attendance: lecturer reads own sessions"
  on public.attendance for select to authenticated
  using (private.teaches_session(session_id));

create policy "attendance: admin reads all"
  on public.attendance for select to authenticated
  using (private.is_admin());

-- ---------------------------------------------------------------------------
-- scan_attempts and disputes: admin only (written by Edge Functions)
-- ---------------------------------------------------------------------------
create policy "scan attempts: admin reads all"
  on public.scan_attempts for select to authenticated
  using (private.is_admin());

create policy "disputes: admin reads all"
  on public.disputes for select to authenticated
  using (private.is_admin());

create policy "disputes: admin updates"
  on public.disputes for update to authenticated
  using (private.is_admin())
  with check (private.is_admin());

-- ---------------------------------------------------------------------------
-- settings: everyone signed in can read, only the admin changes them
-- ---------------------------------------------------------------------------
create policy "settings: signed-in users read"
  on public.settings for select to authenticated
  using (true);

create policy "settings: admin updates"
  on public.settings for update to authenticated
  using (private.is_admin())
  with check (private.is_admin());

-- session_secrets, session_location_tokens: no policies on purpose.
