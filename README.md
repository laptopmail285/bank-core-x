# BankCore X

A configurable, database-centric core banking simulation. Academic
project only: no real money, no live payment rails, no real card data.

Runs entirely on free tiers, no credit card required: Supabase
(Postgres + Auth + Storage + auto-generated REST API), Render (backend),
Vercel/Netlify (three frontends).

---

## Build Status — COMPLETE

- [x] Step 1 — Project skeleton, environment config
- [x] Step 2 — Foundation schema (config, org & access)
- [x] Step 3 — Product engines
- [x] Step 4 — Customer/KYC, Accounts, Ledger + Transaction engine
- [x] Step 5 — Approval, Risk/Fraud, Audit engines
- [x] Step 6 — Loans, Term Deposits, Cards, Notification/Scheduling/EOD engines
- [x] Step 7 — RLS policies + PostgREST roles (64 tables, secure by default)
- [x] Step 8 — Supabase Auth wiring (app_metadata.app_role per user)
- [x] Step 9 — Backend (Node.js) + api schema write functions
- [x] Step 10 — Admin panel (React)
- [x] Step 11 — Staff + Customer portals (React)
- [x] Step 12 — Final packaging

**Database layer: 14 SQL files, 64 tables, 17 functions, 12 views.**

**Application layer: backend (Node/Express) + 3 React frontends, each
talking to Supabase's auto-generated REST API and Supabase Storage.**

---

## Full Run Guide

See **`docs/SUPABASE_DEPLOYMENT.md`** for the complete step-by-step —
creating the Supabase project, pushing the schema, deploying the
backend to Render and the three frontends to Vercel/Netlify, and
bootstrapping the first admin. Short version:

```bash
# 1. Create a Supabase project (supabase.com), run supabase/sql/*.sql
#    in order via the SQL Editor, and expose the "api" schema
#    (Project Settings → API → Exposed schemas).

# 2. Backend
cd backend
cp .env.example .env   # fill in SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, DATABASE_URL
npm install
npm start              # or deploy to Render — see docs/SUPABASE_DEPLOYMENT.md

# 3. Frontends (each in its own terminal, or deployed separately to Vercel/Netlify)
cd admin-panel && cp .env.example .env && npm install && npm run dev     # http://localhost:5173
cd staff-portal && cp .env.example .env && npm install && npm run dev    # http://localhost:5174
cd customer-portal && cp .env.example .env && npm install && npm run dev # http://localhost:5175
```

### Log in
- Bootstrap the first SYSTEM_ADMIN per `docs/SUPABASE_DEPLOYMENT.md` step 9.
- From there, use **Employees** to onboard staff, and staff can then
  use the Staff Portal's **Customers** page to onboard customers.
- Seed `GL-CASH` and the `BRANCH`/`INTERNAL_TRANSFER` channels before
  attempting any deposit, withdrawal, or transfer.

---

## Tech Stack (100% Free)

| Layer | Technology |
|---|---|
| Database | Supabase Postgres |
| REST API | Supabase's auto-generated Data API (PostgREST) |
| Auth | Supabase Auth |
| File Storage | Supabase Storage |
| Backend logic | Node.js + Express (Render) |
| Frontend | React + Vite + Tailwind CSS (Vercel/Netlify) |
| DB Admin | Supabase Dashboard / SQL Editor |

---

## Project Structure
```
bankcore-x/
├── supabase/sql/              # 14 SQL files, applied in numeric order via Supabase SQL Editor
├── backend/                   # Node.js: Supabase Auth/Storage orchestration, EOD cron
├── admin-panel/                # React: SYSTEM_ADMIN app
├── staff-portal/                # React: branch staff app
├── customer-portal/              # React: customer self-service app
├── docs/                          # SUPABASE_DEPLOYMENT.md
└── tests/                          # (reserved for future test suites)
```

---

## Non-Negotiable Rules (from project charter)
1. No bulk dummy data — all records created via real workflows.
2. Frontends never write balances directly — only DB functions do.
3. No service-role/superuser key ever ships in frontend code.
4. No real card numbers, CVV, or plain-text PINs stored.
5. Posted journal entries always balance (enforced in DB).
