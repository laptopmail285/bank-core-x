-- =====================================================================
-- BANKCORE X — 04_accounts.sql
-- Accounts domain: accounts, holders (single/joint/minor-guardian),
-- nominees, status history.
-- Depends on: 01_schema.sql, 02_product_engines.sql, 03_customer_kyc.sql
--
-- IMPORTANT: This file defines STRUCTURE only. Opening balance,
-- balance columns are CACHED values maintained exclusively by the
-- Ledger engine (05_ledger_transactions.sql) via SECURITY DEFINER
-- functions — never written to directly (Rule #4, Rule #17).
-- =====================================================================

-- ---------------------------------------------------------------------
-- core.accounts — one row per account. cached_balance is a
-- performance cache; the ledger (journal entries) is the source of truth.
-- ---------------------------------------------------------------------
CREATE TABLE core.accounts (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_reference       TEXT NOT NULL UNIQUE, -- readable account number
    account_product_id      UUID NOT NULL REFERENCES core.account_products(id),
    account_product_version_id UUID NOT NULL REFERENCES core.account_product_versions(id),
    branch_id               UUID NOT NULL REFERENCES core.branches(id),
    ownership_type           TEXT NOT NULL CHECK (ownership_type IN ('SINGLE', 'JOINT', 'MINOR_GUARDIAN')),
    status                   TEXT NOT NULL DEFAULT 'PENDING_APPROVAL'
        CHECK (status IN ('PENDING_APPROVAL', 'ACTIVE', 'DORMANT', 'FROZEN', 'CLOSED', 'REJECTED')),
    cached_balance            NUMERIC(18,2) NOT NULL DEFAULT 0,
    cached_balance_as_of      TIMESTAMPTZ NOT NULL DEFAULT now(),
    opened_date               DATE,
    closed_date                DATE,
    closure_reason             TEXT,
    opened_by_employee_id      UUID REFERENCES core.employees(id),
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_closed_fields CHECK (
        (status <> 'CLOSED') OR (closed_date IS NOT NULL)
    )
);

CREATE TRIGGER trg_accounts_updated_at
    BEFORE UPDATE ON core.accounts
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

CREATE INDEX idx_accounts_status ON core.accounts(status);
CREATE INDEX idx_accounts_branch ON core.accounts(branch_id);
CREATE INDEX idx_accounts_product ON core.accounts(account_product_id);

COMMENT ON COLUMN core.accounts.cached_balance IS
    'Cached/derived value only. Source of truth is SUM(core.journal_entries)
     for this account. Reconciled by scheduled job (Rule #4, Decision on
     "cached balance reconciliation").';

-- ---------------------------------------------------------------------
-- core.account_holders — links customers to accounts (supports joint)
-- ---------------------------------------------------------------------
CREATE TABLE core.account_holders (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id              UUID NOT NULL REFERENCES core.accounts(id) ON DELETE CASCADE,
    customer_id             UUID NOT NULL REFERENCES core.customers(id),
    holder_role              TEXT NOT NULL CHECK (holder_role IN ('PRIMARY', 'JOINT', 'GUARDIAN')),
    operating_mode           TEXT NOT NULL DEFAULT 'EITHER_OR_SURVIVOR'
        CHECK (operating_mode IN ('EITHER_OR_SURVIVOR', 'JOINTLY', 'FORMER_OR_SURVIVOR')),
    added_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    removed_at                 TIMESTAMPTZ,
    UNIQUE (account_id, customer_id)
);

CREATE INDEX idx_account_holders_account ON core.account_holders(account_id);
CREATE INDEX idx_account_holders_customer ON core.account_holders(customer_id);

COMMENT ON TABLE core.account_holders IS
    'Joint accounts are modeled as multiple rows per account_id, one per
     holder, with holder_role and operating_mode governing whether any
     single holder or all holders must authorize a transaction.';

-- ---------------------------------------------------------------------
-- core.account_nominees
-- ---------------------------------------------------------------------
CREATE TABLE core.account_nominees (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id              UUID NOT NULL REFERENCES core.accounts(id) ON DELETE CASCADE,
    nominee_name             TEXT NOT NULL,
    relationship             TEXT NOT NULL,
    date_of_birth             DATE,
    share_percent             NUMERIC(5,2) NOT NULL DEFAULT 100 CHECK (share_percent > 0 AND share_percent <= 100),
    added_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_account_nominees_account ON core.account_nominees(account_id);

-- ---------------------------------------------------------------------
-- core.account_status_history — append-only audit trail (Rule #21)
-- ---------------------------------------------------------------------
CREATE TABLE core.account_status_history (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id              UUID NOT NULL REFERENCES core.accounts(id) ON DELETE CASCADE,
    previous_status           TEXT,
    new_status                 TEXT NOT NULL,
    reason                     TEXT,
    changed_by                 UUID REFERENCES core.employees(id), -- NULL if system-driven (e.g. dormancy job)
    changed_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_account_status_history_account ON core.account_status_history(account_id);

REVOKE UPDATE, DELETE ON core.account_status_history FROM PUBLIC;

-- ---------------------------------------------------------------------
-- core.account_limits — per-account overrides of product-level defaults
-- (e.g. a specific customer granted a higher daily limit after review)
-- ---------------------------------------------------------------------
CREATE TABLE core.account_limits (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id              UUID NOT NULL REFERENCES core.accounts(id) ON DELETE CASCADE,
    limit_type               TEXT NOT NULL, -- e.g. 'DAILY_WITHDRAWAL', 'DAILY_TRANSFER'
    limit_value               NUMERIC(18,2) NOT NULL CHECK (limit_value >= 0),
    effective_from             DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_to                DATE,
    approved_by                 UUID NOT NULL REFERENCES core.employees(id),
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (account_id, limit_type, effective_from)
);

CREATE INDEX idx_account_limits_account ON core.account_limits(account_id);

-- =====================================================================
-- END OF 04_accounts.sql
-- =====================================================================
