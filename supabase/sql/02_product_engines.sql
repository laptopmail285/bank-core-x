-- =====================================================================
-- BANKCORE X — 02_product_engines.sql
-- Configurable Product Engines: Account, Interest, Loan, Term Deposit,
-- Card products, and Transaction Channels.
-- Depends on: 01_schema.sql (core.employees, core schema)
-- =====================================================================

-- =====================================================================
-- ACCOUNT PRODUCT ENGINE
-- =====================================================================

CREATE TABLE core.account_products (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_code            TEXT NOT NULL UNIQUE,
    product_name            TEXT NOT NULL,
    account_category        TEXT NOT NULL CHECK (account_category IN ('SAVINGS', 'CURRENT', 'SALARY', 'MINOR')),
    allowed_ownership_types TEXT[] NOT NULL DEFAULT ARRAY['SINGLE'], -- subset of SINGLE, JOINT, MINOR_GUARDIAN
    minimum_balance         NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (minimum_balance >= 0),
    monthly_maintenance_fee NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (monthly_maintenance_fee >= 0),
    status                  TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'DEPRECATED')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              UUID NOT NULL REFERENCES core.employees(id)
);

CREATE TRIGGER trg_account_products_updated_at
    BEFORE UPDATE ON core.account_products
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- Versioned rule sets for account products (rules can change over time
-- without altering historical accounts already opened under old rules)
CREATE TABLE core.account_product_versions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_product_id      UUID NOT NULL REFERENCES core.account_products(id) ON DELETE CASCADE,
    version_number          INTEGER NOT NULL,
    effective_from          DATE NOT NULL,
    effective_to            DATE, -- NULL = currently effective
    rules                   JSONB NOT NULL DEFAULT '{}', -- e.g. { "max_withdrawal_per_day": 50000, "free_transactions_per_month": 5 }
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              UUID NOT NULL REFERENCES core.employees(id),
    UNIQUE (account_product_id, version_number),
    CONSTRAINT chk_version_period CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE INDEX idx_account_product_versions_product ON core.account_product_versions(account_product_id);
-- Ensures only one version per product has no end date (i.e. is "current")
CREATE UNIQUE INDEX idx_account_product_versions_one_current
    ON core.account_product_versions(account_product_id)
    WHERE effective_to IS NULL;

-- =====================================================================
-- INTEREST POLICY ENGINE (versioned, effective-dated — Rule #18)
-- =====================================================================

CREATE TABLE core.interest_policies (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_code             TEXT NOT NULL UNIQUE,
    policy_name             TEXT NOT NULL,
    applies_to              TEXT NOT NULL CHECK (applies_to IN ('ACCOUNT_PRODUCT', 'LOAN_PRODUCT', 'TERM_DEPOSIT_PRODUCT')),
    calculation_method      TEXT NOT NULL CHECK (calculation_method IN ('SIMPLE', 'COMPOUND_DAILY', 'COMPOUND_MONTHLY', 'COMPOUND_QUARTERLY', 'COMPOUND_ANNUALLY')),
    status                  TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              UUID NOT NULL REFERENCES core.employees(id)
);

CREATE TABLE core.interest_policy_versions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interest_policy_id      UUID NOT NULL REFERENCES core.interest_policies(id) ON DELETE CASCADE,
    version_number          INTEGER NOT NULL,
    annual_rate_percent     NUMERIC(6,3) NOT NULL CHECK (annual_rate_percent >= 0),
    effective_from          DATE NOT NULL,
    effective_to            DATE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              UUID NOT NULL REFERENCES core.employees(id),
    UNIQUE (interest_policy_id, version_number),
    CONSTRAINT chk_interest_version_period CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE INDEX idx_interest_policy_versions_policy ON core.interest_policy_versions(interest_policy_id);
CREATE UNIQUE INDEX idx_interest_policy_versions_one_current
    ON core.interest_policy_versions(interest_policy_id)
    WHERE effective_to IS NULL;

-- Link account products to the interest policy that applies to them
ALTER TABLE core.account_products
    ADD COLUMN interest_policy_id UUID REFERENCES core.interest_policies(id);

-- =====================================================================
-- LOAN PRODUCT ENGINE
-- =====================================================================

CREATE TABLE core.loan_products (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_code                TEXT NOT NULL UNIQUE,
    product_name                TEXT NOT NULL,
    loan_category                TEXT NOT NULL CHECK (loan_category IN ('PERSONAL', 'HOME', 'VEHICLE', 'EDUCATION', 'GOLD', 'OVERDRAFT')),
    interest_policy_id          UUID NOT NULL REFERENCES core.interest_policies(id),
    min_principal                NUMERIC(18,2) NOT NULL CHECK (min_principal > 0),
    max_principal                NUMERIC(18,2) NOT NULL CHECK (max_principal >= min_principal),
    min_tenure_months           INTEGER NOT NULL CHECK (min_tenure_months > 0),
    max_tenure_months           INTEGER NOT NULL CHECK (max_tenure_months >= min_tenure_months),
    processing_fee_percent      NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (processing_fee_percent >= 0),
    penalty_rate_percent        NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (penalty_rate_percent >= 0),
    status                       TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                   UUID NOT NULL REFERENCES core.employees(id)
);

CREATE TABLE core.loan_product_versions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_product_id         UUID NOT NULL REFERENCES core.loan_products(id) ON DELETE CASCADE,
    version_number          INTEGER NOT NULL,
    effective_from          DATE NOT NULL,
    effective_to            DATE,
    rules                   JSONB NOT NULL DEFAULT '{}', -- e.g. { "max_ltv_ratio": 0.8, "required_documents": [...] }
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              UUID NOT NULL REFERENCES core.employees(id),
    UNIQUE (loan_product_id, version_number),
    CONSTRAINT chk_loan_version_period CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE INDEX idx_loan_product_versions_product ON core.loan_product_versions(loan_product_id);
CREATE UNIQUE INDEX idx_loan_product_versions_one_current
    ON core.loan_product_versions(loan_product_id)
    WHERE effective_to IS NULL;

-- =====================================================================
-- TERM DEPOSIT (FD/RD) PRODUCT ENGINE
-- =====================================================================

CREATE TABLE core.term_deposit_products (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_code            TEXT NOT NULL UNIQUE,
    product_name            TEXT NOT NULL,
    deposit_type            TEXT NOT NULL CHECK (deposit_type IN ('FD', 'RD')),
    interest_policy_id      UUID NOT NULL REFERENCES core.interest_policies(id),
    min_amount              NUMERIC(18,2) NOT NULL CHECK (min_amount > 0),
    max_amount              NUMERIC(18,2) CHECK (max_amount IS NULL OR max_amount >= min_amount),
    min_tenure_months       INTEGER NOT NULL CHECK (min_tenure_months > 0),
    max_tenure_months       INTEGER NOT NULL CHECK (max_tenure_months >= min_tenure_months),
    premature_withdrawal_penalty_percent NUMERIC(5,2) NOT NULL DEFAULT 1.0 CHECK (premature_withdrawal_penalty_percent >= 0),
    allows_premature_withdrawal BOOLEAN NOT NULL DEFAULT TRUE,
    status                  TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              UUID NOT NULL REFERENCES core.employees(id)
);

-- =====================================================================
-- CARD PRODUCT ENGINE (simulated — no real card rails)
-- =====================================================================

CREATE TABLE core.card_products (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_code            TEXT NOT NULL UNIQUE,
    product_name            TEXT NOT NULL,
    card_category           TEXT NOT NULL CHECK (card_category IN ('DEBIT', 'CREDIT_SIMULATED')),
    default_daily_atm_limit NUMERIC(18,2) NOT NULL DEFAULT 25000 CHECK (default_daily_atm_limit >= 0),
    default_daily_pos_limit NUMERIC(18,2) NOT NULL DEFAULT 100000 CHECK (default_daily_pos_limit >= 0),
    default_daily_online_limit NUMERIC(18,2) NOT NULL DEFAULT 50000 CHECK (default_daily_online_limit >= 0),
    annual_fee              NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (annual_fee >= 0),
    status                  TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              UUID NOT NULL REFERENCES core.employees(id)
);

COMMENT ON TABLE core.card_products IS
    'Simulated card products only. No real card numbers, CVV, or plain-text PIN are ever stored (Rule #12).';

-- =====================================================================
-- TRANSACTION CHANNELS (fully configurable — Decision #6)
-- =====================================================================

CREATE TABLE core.transaction_channels (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_code            TEXT NOT NULL UNIQUE, -- e.g. 'BRANCH', 'NEFT_SIM', 'RTGS_SIM', 'IMPS_SIM', 'UPI_SIM', 'INTERNAL_TRANSFER'
    channel_name            TEXT NOT NULL,
    requires_step_up_auth   BOOLEAN NOT NULL DEFAULT FALSE, -- TOTP MFA required
    is_simulated_external_rail BOOLEAN NOT NULL DEFAULT FALSE, -- true for NEFT/RTGS/IMPS/UPI sim
    default_daily_limit     NUMERIC(18,2) NOT NULL DEFAULT 100000 CHECK (default_daily_limit >= 0),
    status                  TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              UUID NOT NULL REFERENCES core.employees(id)
);

COMMENT ON TABLE core.transaction_channels IS
    'Simulated NEFT/RTGS/IMPS/UPI channels do not connect to live payment rails (Rule #15).';

-- =====================================================================
-- BOOTSTRAP DATA — configuration seed only, no operational/customer data
-- =====================================================================
-- NOTE: created_by must reference a real employee. Since no employee
-- exists yet at fresh install, this seed is deferred — see
-- docs/BOOTSTRAP_SEQUENCE.md for the exact one-time bootstrap order
-- (create first SYSTEM_ADMIN employee first, then run the seed block
-- below with that employee's id substituted in).
-- =====================================================================

-- Placeholder transaction channel seed template (run AFTER first admin exists):
--
-- INSERT INTO core.transaction_channels (channel_code, channel_name, requires_step_up_auth, is_simulated_external_rail, default_daily_limit, created_by) VALUES
--     ('BRANCH',             'Branch Counter',        FALSE, FALSE, 1000000, :admin_employee_id),
--     ('INTERNAL_TRANSFER',  'Internal Transfer',     FALSE, FALSE, 200000,  :admin_employee_id),
--     ('NEFT_SIM',           'Simulated NEFT',        TRUE,  TRUE,  200000,  :admin_employee_id),
--     ('RTGS_SIM',           'Simulated RTGS',        TRUE,  TRUE,  1000000, :admin_employee_id),
--     ('IMPS_SIM',           'Simulated IMPS',        TRUE,  TRUE,  100000,  :admin_employee_id),
--     ('UPI_SIM',            'Simulated UPI',         FALSE, TRUE,  100000,  :admin_employee_id);

-- =====================================================================
-- END OF 02_product_engines.sql
-- =====================================================================
