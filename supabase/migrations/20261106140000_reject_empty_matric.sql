-- Phase 2 · Migration 5: a student's matric number can't be empty.
--
-- The original rule only required matric_no to be not null, so '' slipped
-- through (and also passes matric_no_is_normalised, since upper(trim('')) = '').
-- Whitespace-only values are already rejected by matric_no_is_normalised,
-- so checking for '' here covers every blank case.

alter table public.profiles
  drop constraint students_need_matric_and_level,
  add constraint students_need_matric_and_level
    check (role <> 'student' or (matric_no is not null and matric_no <> '' and level is not null));
