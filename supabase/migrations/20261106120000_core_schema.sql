-- Phase 2 · Migration 1 of 3: core tables.
-- Security rules (Row Level Security) are in the next migration; until it runs,
-- nothing here should hold real data.

-- Helper functions live in a schema the API doesn't expose.
create schema if not exists private;

-- ---------------------------------------------------------------------------
-- Enums (fixed lists of allowed values)
-- ---------------------------------------------------------------------------
create type public.user_role         as enum ('student', 'lecturer', 'admin');
create type public.account_status    as enum ('pending', 'approved', 'rejected');
create type public.session_status    as enum ('awaiting_location', 'open', 'closed');
create type public.attendance_status as enum ('present', 'late', 'manual');
create type public.request_status    as enum ('pending', 'approved', 'rejected');
create type public.location_source   as enum ('phone', 'laptop');
create type public.dispute_status    as enum ('open', 'resolved');

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
create function private.set_updated_at() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- 6-character course join code, e.g. "X7K2QP". Leaves out 0/O and 1/I so
-- students don't mistype it. 256 is a multiple of 32, so every letter is equally likely.
create function private.generate_join_code() returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea := extensions.gen_random_bytes(6);
  result text := '';
begin
  for i in 0..5 loop
    result := result || substr(alphabet, 1 + (get_byte(bytes, i) % 32), 1);
  end loop;
  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles: one row per person (student, lecturer or admin)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id               uuid primary key references auth.users (id) on delete cascade,
  role             public.user_role      not null default 'student',
  status           public.account_status not null default 'pending',
  full_name        text not null check (length(trim(full_name)) between 2 and 120),
  email            text not null,
  matric_no        text,
  staff_id         text,
  level            smallint check (level between 100 and 500 and level % 100 = 0),
  rejection_reason text,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint students_need_matric_and_level
    check (role <> 'student' or (matric_no is not null and level is not null)),
  constraint matric_no_is_normalised
    check (matric_no = upper(trim(matric_no)))
);

create unique index profiles_email_key     on public.profiles (lower(email));
create unique index profiles_matric_no_key on public.profiles (matric_no);
create unique index profiles_staff_id_key  on public.profiles (upper(staff_id));

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- devices: the phone each student is locked to
-- ---------------------------------------------------------------------------
create table public.devices (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  device_id   text not null check (length(device_id) between 16 and 200),
  is_active   boolean not null default true,
  linked_at   timestamptz not null default now(),
  unlinked_at timestamptz
);

-- One active phone per student, and one student per active phone
-- (stops one phone marking attendance for several accounts).
create unique index devices_one_active_per_user
  on public.devices (user_id) where is_active;
create unique index devices_one_user_per_active_device
  on public.devices (device_id) where is_active;

-- ---------------------------------------------------------------------------
-- device_change_requests: "I have a new phone" → admin approves
-- ---------------------------------------------------------------------------
create table public.device_change_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  new_device_id text not null check (length(new_device_id) between 16 and 200),
  reason        text check (length(reason) <= 500),
  status        public.request_status not null default 'pending',
  reviewed_by   uuid references public.profiles (id),
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);

-- Only one open request per student at a time.
create unique index device_change_requests_one_pending
  on public.device_change_requests (user_id) where status = 'pending';

-- ---------------------------------------------------------------------------
-- courses
-- ---------------------------------------------------------------------------
create table public.courses (
  id                 uuid primary key default gen_random_uuid(),
  lecturer_id        uuid not null references public.profiles (id) on delete restrict,
  code               text not null check (code = upper(trim(code)) and length(code) between 3 and 20),
  title              text not null check (length(trim(title)) between 2 and 200),
  join_code          text not null unique default private.generate_join_code(),
  min_attendance_pct smallint not null default 75 check (min_attendance_pct between 0 and 100),
  is_archived        boolean not null default false,
  created_at         timestamptz not null default now(),
  unique (lecturer_id, code)
);

-- ---------------------------------------------------------------------------
-- enrollments: which students are in which course
-- ---------------------------------------------------------------------------
create table public.enrollments (
  course_id   uuid not null references public.courses (id) on delete cascade,
  student_id  uuid not null references public.profiles (id) on delete cascade,
  enrolled_at timestamptz not null default now(),
  primary key (course_id, student_id)
);

create index enrollments_student_idx on public.enrollments (student_id);

-- ---------------------------------------------------------------------------
-- sessions: one lecture's attendance window
-- ---------------------------------------------------------------------------
create table public.sessions (
  id                  uuid primary key default gen_random_uuid(),
  course_id           uuid not null references public.courses (id) on delete cascade,
  started_by          uuid not null references public.profiles (id),
  status              public.session_status not null default 'awaiting_location',
  window_minutes      smallint not null default 15 check (window_minutes between 1 and 240),
  late_after_minutes  smallint not null default 10,
  radius_m            integer  not null default 100 check (radius_m between 10 and 1000),
  lat                 double precision check (lat between -90 and 90),
  lng                 double precision check (lng between -180 and 180),
  location_source     public.location_source,
  location_accuracy_m real check (location_accuracy_m >= 0),
  created_at          timestamptz not null default now(),
  opened_at           timestamptz,
  ends_at             timestamptz,
  closed_at           timestamptz,
  constraint late_within_window
    check (late_after_minutes between 0 and window_minutes),
  -- An open session must know where the hall is and when it ends.
  -- (A session cancelled before opening can be closed without a location.)
  constraint open_needs_location
    check (status <> 'open' or (lat is not null and lng is not null
           and location_source is not null and opened_at is not null and ends_at is not null))
);

create index sessions_course_idx on public.sessions (course_id, created_at desc);

-- At most one live session per course at a time.
create unique index sessions_one_live_per_course
  on public.sessions (course_id) where status in ('awaiting_location', 'open');

-- Secret used to sign the rotating QR codes. Separate table so lecturers and
-- students can never read it — only Edge Functions (server side) can.
create table public.session_secrets (
  session_id uuid primary key references public.sessions (id) on delete cascade,
  qr_secret  text not null default encode(extensions.gen_random_bytes(32), 'hex')
);

-- One-time "set location" links the lecturer opens on their phone.
-- Only a hash of the token is stored, never the token itself.
create table public.session_location_tokens (
  id         uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at    timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- attendance: one row per student per session they were marked in
-- ---------------------------------------------------------------------------
create table public.attendance (
  id             uuid primary key default gen_random_uuid(),
  session_id     uuid not null references public.sessions (id) on delete cascade,
  student_id     uuid not null references public.profiles (id) on delete cascade,
  status         public.attendance_status not null,
  marked_at      timestamptz not null default now(),
  lat            double precision,
  lng            double precision,
  gps_accuracy_m real,
  device_id      text,
  marked_by      uuid references public.profiles (id),
  unique (session_id, student_id),
  constraint manual_needs_marker
    check (status <> 'manual' or marked_by is not null),
  constraint scan_needs_location_and_device
    check (status = 'manual' or (lat is not null and lng is not null and device_id is not null))
);

create index attendance_student_idx on public.attendance (student_id);

-- ---------------------------------------------------------------------------
-- scan_attempts: failed scans (for debugging, spotting abuse and rate limits)
-- ---------------------------------------------------------------------------
create table public.scan_attempts (
  id         bigint generated always as identity primary key,
  student_id uuid references public.profiles (id) on delete cascade,
  session_id uuid references public.sessions (id) on delete set null,
  reason     text not null,
  created_at timestamptz not null default now()
);

create index scan_attempts_student_time_idx on public.scan_attempts (student_id, created_at desc);

-- ---------------------------------------------------------------------------
-- disputes: "this matric number is already registered, but it's mine"
-- ---------------------------------------------------------------------------
create table public.disputes (
  id             uuid primary key default gen_random_uuid(),
  matric_no      text not null,
  reporter_email text not null,
  message        text check (length(message) <= 1000),
  status         public.dispute_status not null default 'open',
  resolved_by    uuid references public.profiles (id),
  resolved_at    timestamptz,
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- settings: a single row of app-wide settings the admin can change
-- ---------------------------------------------------------------------------
create table public.settings (
  id                              boolean primary key default true check (id),
  allowed_email_domain            text,  -- empty = any email allowed
  default_radius_m                integer  not null default 100 check (default_radius_m between 10 and 1000),
  laptop_radius_m                 integer  not null default 300 check (laptop_radius_m between 10 and 2000),
  qr_rotation_seconds             smallint not null default 10  check (qr_rotation_seconds between 5 and 60),
  max_device_changes_per_semester smallint not null default 2   check (max_device_changes_per_semester between 0 and 10),
  default_min_attendance_pct      smallint not null default 75  check (default_min_attendance_pct between 0 and 100),
  updated_at                      timestamptz not null default now()
);

insert into public.settings default values;

create trigger settings_set_updated_at
  before update on public.settings
  for each row execute function private.set_updated_at();
