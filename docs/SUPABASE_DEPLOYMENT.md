# BankCore X — Supabase Deployment Guide

Supersedes the old DEPLOYMENT.md / BOOTSTRAP_SEQUENCE.md / MAC_SETUP_GUIDE.md /
STEP_BY_STEP_MAC.md (all removed — they described the self-hosted
Docker + Keycloak + MinIO stack this project no longer uses).

Everything below is free and requires no credit card.

## 1. Create the Supabase project

1. supabase.com → sign up (GitHub/Google) → New project.
2. Pick a region close to your users. Set a DB password — save it, you need it for `DATABASE_URL`.
3. Wait for provisioning (~2 min).

## 2. Push the schema

Dashboard → SQL Editor → run each file in `supabase/sql/` **in order**:

```
01_schema.sql
02_...  (through however many numbered files exist)
...
11_roles_and_rls.sql
12_api_layer.sql
13_eod_procedure.sql
14_admin_views.sql
```

`11_roles_and_rls.sql` and `12_api_layer.sql` already target Supabase's
`anon`/`authenticated` roles — no edits needed, just run them as-is.

## 3. Expose the `api` schema to the REST API

Dashboard → Project Settings → API → **Exposed schemas** → add `api`
(alongside the default `public`). Without this step every request from
the frontends 404s — PostgREST only serves schemas you explicitly expose.

## 4. Enable email/password auth

Dashboard → Authentication → Providers → confirm **Email** is enabled
(it is by default). No SMTP setup needed for this project — the backend
creates users directly via the Admin API with `email_confirm: true`, so
no verification email round-trip is required for staff-created accounts.

## 5. Create the Storage bucket

You don't have to do this by hand — the backend's `ensureBucketsExist()`
creates `kyc-documents` (and `statements`) automatically on first
startup, using the service-role key. If you'd rather do it manually:
Dashboard → Storage → New bucket → name it `kyc-documents` → **Private**.

## 6. Collect your keys

Dashboard → Project Settings → API, note down:
- Project URL
- `anon` `public` key
- `service_role` `secret` key (backend only — never put this in a frontend `.env`)

Dashboard → Project Settings → Database, note down:
- Connection string (URI) — this is `DATABASE_URL` for the backend

## 7. Deploy the backend (Render, free, no card)

1. render.com → sign up → New → Web Service → connect your GitHub repo, root directory `backend/`.
2. Build command: `npm install`. Start command: `npm start`.
3. Environment tab → add everything from `backend/.env.example` with real values.
4. Deploy. Note the `https://your-service.onrender.com` URL — this is `VITE_BACKEND_URL` for the frontends.

Free-tier note: the service sleeps after ~15 min idle and takes a few
seconds to wake on the next request. Only onboarding/KYC-upload hit it,
so this is fine — login and everyday banking calls go straight to
Supabase and are never affected by this sleep.

## 8. Deploy the three frontends (Vercel or Netlify, free, no card)

For each of `customer-portal/`, `staff-portal/`, `admin-panel/`:

1. New Project → import the repo → set root directory to that folder.
2. Framework preset: Vite. Build command `npm run build`, output dir `dist`.
3. Environment variables → copy everything from that folder's `.env.example` with real values (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_SUPABASE_STORAGE_KEY`, `VITE_BACKEND_URL`).
4. Deploy. Each gets its own free subdomain (e.g. `bankcore-customer.vercel.app`).

## 9. Create your first admin user

There's no signup form (this is an internal banking system, not a public
sign-up app), so the very first admin has to be created directly:

```sql
-- Run in Supabase SQL Editor, AFTER creating the user in
-- Authentication → Users → Add user (set email + password there first,
-- then run this to tag them as admin and link the employee record):
update auth.users
set raw_app_meta_data = raw_app_meta_data || '{"app_role": "web_admin"}'::jsonb
where email = 'your-admin@email.com';

insert into core.employees (employee_code, auth_subject_id, full_name, email, primary_branch_id, status)
values ('EMP-0001', (select id from auth.users where email = 'your-admin@email.com'), 'Your Name', 'your-admin@email.com', (select id from core.branches limit 1), 'ACTIVE');

insert into core.employee_roles (employee_id, role_id, assigned_by)
select e.id, r.id, e.id
from core.employees e, core.roles r
where e.email = 'your-admin@email.com' and r.role_code = 'SYSTEM_ADMIN';
```

From there, log into the admin panel and use the Employees page to
onboard everyone else — the backend's `/onboarding/employees` route
handles the Supabase Auth + `core.employees` + role assignment together.

## What changed from the old Docker architecture

| Old (self-hosted) | New (Supabase) |
|---|---|
| Postgres in a container | Supabase-managed Postgres |
| Keycloak | Supabase Auth (`app_metadata.app_role` tags customer/staff/admin) |
| Self-hosted PostgREST | Supabase's built-in Data API |
| MinIO | Supabase Storage |
| pgAdmin, Metabase | Supabase's own dashboard / SQL Editor (Metabase can still be pointed at the Supabase connection string later if you want proper BI) |
| docker-compose + Caddy + DuckDNS on Oracle Cloud | Render (backend) + Vercel/Netlify (3 frontends), no VM, no card |
