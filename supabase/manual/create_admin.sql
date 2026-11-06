-- Run ONCE, by hand, in the Supabase dashboard → SQL Editor, to make yourself admin.
-- This is NOT a migration (it contains your personal details, so it isn't run automatically).
--
-- Before running:
--   1. Supabase dashboard → Authentication → Users → "Add user" → "Create new user"
--      Enter your email + a strong password, tick "Auto Confirm User".
--   2. Replace the two placeholders below, then click Run.

insert into public.profiles (id, role, status, full_name, email)
select id, 'admin', 'approved', 'YOUR FULL NAME', email
from auth.users
where email = 'your-admin-email@example.com';

-- Check it worked (should show one row with role = admin):
select id, full_name, email, role, status from public.profiles where role = 'admin';
