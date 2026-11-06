# Lecture Attendance App — v1 Plan

Rule: **no phase starts without the owner's go-ahead.** After each phase the owner pushes to GitHub and gets a CodeRabbit review; review comments are fixed before the next phase. Tick a box only when that item is done and checked.

Legend: `[ ]` not done · `[x]` done

---

## Tech stack — NOT FINAL

Choices picked during the interview, still to be confirmed before Phase 1. Exact versions are checked against current docs at confirmation time.

| Part | Picked so far | Status |
|---|---|---|
| Student app | Expo (React Native), tested with Expo Go on iPhone | to confirm |
| Lecturer/admin dashboard | React + Vite (single-page app) | to confirm |
| Dashboard hosting | Cloudflare Pages (free, commercial use allowed) | confirmed |
| Backend | Supabase (Postgres, Auth, Edge Functions, Realtime) | to confirm |
| Repo layout | Monorepo with npm workspaces | to confirm |
| Language | TypeScript | to confirm |
| Other libraries (UI kit, routing, forms, QR, maps/GPS) | not discussed yet | open |
| Versions (Expo SDK, React, Vite, Supabase JS) | checked 2026-11-06, see below | open — Expo SDK depends on what Expo Go on the iPhone supports |

**Versions found on npm (2026-11-06):**

| Package | Latest | Plan |
|---|---|---|
| Expo SDK | 58 (`expo` 58.0.23, React Native 0.88) | Use 58 **only if** Expo Go on the iPhone supports SDK 58 — otherwise SDK 57 |
| React Native | 0.88.1 | Use whatever the chosen Expo SDK pins (never set by hand) |
| React | 19.3.1 | Dashboard uses the **same React version the Expo SDK pins**, so the monorepo has one React |
| Vite | 8.3.6 (+ `@vitejs/plugin-react` 6.2.1) | Use latest |
| `@supabase/supabase-js` | 2.119.0 | Use latest |
| Supabase CLI | 3.0.0 | Run with `npx` (no global install) |
| TypeScript | 7.0.2 | Use the version the Expo template pins, same everywhere (TS 7 is new — check tool support first) |

- [ ] Tech stack confirmed (every row above marked "confirmed")

### Decide when we get there
Options are brought to the owner at the phase where each one is needed; the owner chooses. Nothing is added before then.

| Decision | Comes up in | Notes so far |
|---|---|---|
| Dashboard UI kit / styling (e.g. Tailwind, shadcn/ui, Mantine) | Phase 1 | — |
| Mobile UI / navigation (e.g. Expo Router) | Phase 1 | — |
| Supabase local dev (Docker on laptop) vs work straight on the cloud project | Phase 1 | Docker on Windows is heavy; cloud-only is simpler for a beginner |
| Form handling + validation library | Phase 3 | — |
| Email sending (Supabase built-in vs free SMTP like Resend/Brevo) | Phase 3 | built-in has low limits / spam risk |
| QR generation (dashboard) + QR scanning (mobile) libraries | Phase 5–6 | — |
| Scheduled jobs (auto-close sessions, token cleanup) | Phase 5 | Supabase pg_cron likely enough; Inngest probably not needed in v1 |
| Excel/CSV handling | v2 (roster) | — |
| Error tracking / logging (e.g. Sentry free tier) | Phase 10 | — |
| Backend hosting outside Supabase (e.g. Render) | only if needed | not expected — Edge Functions cover it; Render free tier sleeps |

---

## Phase 0 — Setup
- [x] Node.js LTS, Git, VS Code installed on laptop (checked: Node 24.18.0, npm 11.16.0, Git 2.55.0, VS Code 1.141.0)
- [x] Expo Go installed on iPhone
- [x] Free accounts: Supabase, Cloudflare, GitHub
- [x] Exact versions checked and written into the stack table
- [x] **Checkpoint:** owner confirms setup (Expo Go supports SDK 58)

## Phase 1 — Project skeleton
> **✅ Phase 1 complete (2026-11-06).** Pushed on branch `phase-1`, CodeRabbit review: no major changes.
>
> Phase 1 choices: Expo SDK 58 · Tailwind + shadcn/ui (base-nova style) · Expo Router · Supabase cloud project (no Docker)
>
> Gotcha: Expo CLI login on Windows only works with `npx expo login --no-browser` (browser login crashes).

- [x] Monorepo created: `apps/mobile`, `apps/web`, `packages/shared`, `supabase/`
- [x] Both apps connected to Supabase via `.env` (keys not committed)
- [x] "Hello" screen runs on iPhone via Expo Go
- [x] "Hello" page runs in the browser
- [x] **Checkpoint:** owner sees both running
- [x] Pushed to GitHub + CodeRabbit review done (comments fixed)

## Phase 2 — Database & security rules
> Migrations in `supabase/migrations/`, uploaded with `npm run db:push` (Supabase CLI 3 needs `--remote`; scripts use `npm exec` because `npx.cmd` is missing on this laptop). Student levels: 100–500.

- [x] Tables: profiles, devices, device_change_requests, courses, enrollments, sessions, session_secrets, session_location_tokens, attendance, scan_attempts, disputes, settings
- [x] Row Level Security: students see own data, lecturers see own courses, admin sees all, no direct attendance writes (checked: strangers see 0 rows, secrets return 401, attendance writes blocked)
- [x] Admin account created by hand (Emmanuel Ochigbo, emmanueloloche30@gmail.com)
- [x] **Checkpoint:** walkthrough of tables in Supabase dashboard
- [ ] Pushed to GitHub + CodeRabbit review done (comments fixed)

## Phase 3 — Accounts & sign-in
- [ ] Student sign-up (matric no, name, email, level, password) + email code verification
- [ ] "Waiting for approval" screen
- [ ] Student sign-in with matric no + password (rate-limited lookup)
- [ ] Forgot password
- [ ] Stay signed in until logout
- [ ] Admin sign-in + Pending queue (approve / reject with reason / bulk approve)
- [ ] Admin invites and deactivates lecturers
- [ ] Lecturer accepts invite, sets password, signs in
- [ ] Dashboard shows only the screens for the signed-in role
- [ ] **Checkpoint:** sign up as student on iPhone, approve as admin, invite a test lecturer
- [ ] Pushed to GitHub + CodeRabbit review done (comments fixed)

## Phase 4 — Courses & enrollment
- [ ] Lecturer creates a course and gets a join code
- [ ] Student joins with the code
- [ ] Course page lists enrolled students
- [ ] **Checkpoint:** test student enrolled in test course
- [ ] Pushed to GitHub + CodeRabbit review done (comments fixed)

## Phase 5 — Sessions & rotating QR
- [ ] Start session (window + late cutoff)
- [ ] "Set location" one-time QR → lecturer's phone sends GPS
- [ ] Laptop-location fallback (300m radius, recorded as laptop)
- [ ] Rotating QR every 10s, signed on the server
- [ ] Timer, auto-close at end time, "Close session" button
- [ ] **Checkpoint:** session runs on laptop with the QR changing
- [ ] Pushed to GitHub + CodeRabbit review done (comments fixed)

## Phase 6 — Scanning (core loop)
- [ ] Device ID created on first sign-in, stored securely
- [ ] Unregistered phone: can view stats, scanning blocked
- [ ] Scan screen: camera + GPS + accuracy
- [ ] `submit-scan` runs all 7 checks, returns present / late / rejected with reason
- [ ] Automated tests: expired token, wrong device, out of range, already scanned, not enrolled, session closed
- [ ] **Checkpoint:** iPhone scan marks present; old screenshot is rejected
- [ ] Pushed to GitHub + CodeRabbit review done (comments fixed)

## Phase 7 — Live list & manual marking
- [ ] Live list updates instantly (Realtime) with present counter
- [ ] Manual mark-present, saved as `manual` with who marked it
- [ ] **Checkpoint:** own scan appears live; manual mark works
- [ ] Pushed to GitHub + CodeRabbit review done (comments fixed)

## Phase 8 — Stats & history
- [ ] Student: per-course %, red warning below 75%, history for each session
- [ ] Lecturer: each student's total % per course
- [ ] Lecturer: list of all their sessions and who attended each
- [ ] Empty states
- [ ] **Checkpoint:** numbers match test sessions
- [ ] Pushed to GitHub + CodeRabbit review done (comments fixed)

## Phase 9 — Device changes & disputes
- [ ] Student requests device change → admin approves → old device unlinked (max 2 per semester)
- [ ] "Matric already registered? Report it" → admin resolves
- [ ] **Checkpoint:** test account moved to a second phone
- [ ] Pushed to GitHub + CodeRabbit review done (comments fixed)

## Phase 10 — Polish & demo
- [ ] Clear error messages, loading states, slow-network handling
- [ ] Rate limiting on sign-in and scan
- [ ] Dashboard deployed to Cloudflare Pages
- [ ] Real lecture hall test; GPS radius tuned
- [ ] Demo script written
- [ ] **Checkpoint:** full demo with 2–3 phones (= v1 done)
- [ ] Pushed to GitHub + CodeRabbit review done (comments fixed)

---

## Later (v2 ideas — not in v1)
- Roster with CSV/Excel import and auto-matching
- Course rep approver role
- School-email-only sign-up
- CSV export of attendance
- Push notifications
- Native builds with a stronger device lock and fake-GPS detection
