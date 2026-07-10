-- =====================================================================
-- BANKCORE X — 07_loans.sql
-- Loans domain: applications, loans, repayment schedule, repayments.
-- Depends on: 01_schema.sql, 02_product_engines.sql, 03_customer_kyc.sql,
--             04_accounts.sql, 05_ledger_transactions.sql
-- =====================================================================

CREATE TABLE core.loan_applications (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_reference    TEXT NOT NULL UNIQUE,
    customer_id                UUID NOT NULL REFERENCES core.customers(id),
    loan_product_id              UUID NOT NULL REFERENCES core.loan_products(id),
    branch_id                      UUID NOT NULL REFERENCES core.branches(id),
    requested_principal              NUMERIC(18,2) NOT NULL CHECK (requested_principal > 0),
    requested_tenure_months            INTEGER NOT NULL CHECK (requested_tenure_months > 0),
    purpose                              TEXT,
    assigned_officer_id                    UUID REFERENCES core.employees(id),
    status                                    TEXT NOT NULL DEFAULT 'SUBMITTED'
        CHECK (status IN ('SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'DISBURSED', 'WITHDRAWN')),
    rejection_reason                            TEXT,
    submitted_at                                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at                                      TIMESTAMPTZ,
    decided_by                                        UUID REFERENCES core.employees(id)
);

CREATE INDEX idx_loan_applications_customer ON core.loan_applications(customer_id);
CREATE INDEX idx_loan_applications_status ON core.loan_applications(status);

CREATE TABLE core.loans (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_reference            TEXT NOT NULL UNIQUE,
    application_id              UUID NOT NULL REFERENCES core.loan_applications(id),
    customer_id                    UUID NOT NULL REFERENCES core.customers(id),
    loan_product_id                  UUID NOT NULL REFERENCES core.loan_products(id),
    loan_product_version_id            UUID NOT NULL REFERENCES core.loan_product_versions(id),
    disbursement_account_id              UUID NOT NULL REFERENCES core.accounts(id),
    principal_amount                       NUMERIC(18,2) NOT NULL CHECK (principal_amount > 0),
    tenure_months                            INTEGER NOT NULL CHECK (tenure_months > 0),
    interest_rate_annual_locked                NUMERIC(6,3) NOT NULL CHECK (interest_rate_annual_locked >= 0),
    outstanding_principal                        NUMERIC(18,2) NOT NULL, -- cached; derived from schedule + repayments
    status                                          TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'CLOSED', 'DEFAULTED', 'WRITTEN_OFF')),
    disbursed_at                                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    disbursed_by                                        UUID NOT NULL REFERENCES core.employees(id),
    closed_at                                             TIMESTAMPTZ,
    CONSTRAINT chk_loan_outstanding_non_negative CHECK (outstanding_principal >= 0)
);

CREATE INDEX idx_loans_customer ON core.loans(customer_id);
CREATE INDEX idx_loans_status ON core.loans(status);

COMMENT ON COLUMN core.loans.outstanding_principal IS
    'Cached/derived value, reconciled against core.loan_repayment_schedule
     and core.loan_repayments — same cached-value pattern as
     core.accounts.cached_balance (Rule #4).';

CREATE TABLE core.loan_repayment_schedule (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id                   UUID NOT NULL REFERENCES core.loans(id) ON DELETE CASCADE,
    installment_number          INTEGER NOT NULL CHECK (installment_number > 0),
    due_date                      DATE NOT NULL,
    principal_component             NUMERIC(18,2) NOT NULL CHECK (principal_component >= 0),
    interest_component                NUMERIC(18,2) NOT NULL CHECK (interest_component >= 0),
    total_due                           NUMERIC(18,2) NOT NULL CHECK (total_due >= 0),
    paid_amount                           NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (paid_amount >= 0),
    status                                   TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'PAID', 'OVERDUE', 'PARTIALLY_PAID')),
    UNIQUE (loan_id, installment_number)
);

CREATE INDEX idx_loan_schedule_loan ON core.loan_repayment_schedule(loan_id);
CREATE INDEX idx_loan_schedule_status ON core.loan_repayment_schedule(status);
CREATE INDEX idx_loan_schedule_due_date ON core.loan_repayment_schedule(due_date);

CREATE TABLE core.loan_repayments (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id                   UUID NOT NULL REFERENCES core.loans(id),
    schedule_id                 UUID REFERENCES core.loan_repayment_schedule(id),
    transaction_id                 UUID NOT NULL REFERENCES core.transactions(id), -- the ledger-posting transaction
    amount                           NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    paid_via_channel_id                UUID NOT NULL REFERENCES core.transaction_channels(id),
    paid_at                              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_loan_repayments_loan ON core.loan_repayments(loan_id);
CREATE INDEX idx_loan_repayments_transaction ON core.loan_repayments(transaction_id);

CREATE TABLE core.loan_status_history (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id                   UUID NOT NULL REFERENCES core.loans(id) ON DELETE CASCADE,
    previous_status              TEXT,
    new_status                     TEXT NOT NULL,
    reason                            TEXT,
    changed_by                          UUID REFERENCES core.employees(id),
    changed_at                            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_loan_status_history_loan ON core.loan_status_history(loan_id);

REVOKE UPDATE, DELETE ON core.loan_status_history FROM PUBLIC;

-- =====================================================================
-- END OF 07_loans.sql
-- =====================================================================
