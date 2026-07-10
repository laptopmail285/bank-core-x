-- =====================================================================
-- BANKCORE X — 08_term_deposits.sql
-- Term Deposit domain: Fixed Deposits (FD) and Recurring Deposits (RD).
-- Depends on: 01_schema.sql, 02_product_engines.sql, 03_customer_kyc.sql,
--             04_accounts.sql, 05_ledger_transactions.sql
-- =====================================================================

CREATE TABLE core.term_deposits (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deposit_reference         TEXT NOT NULL UNIQUE,
    customer_id                 UUID NOT NULL REFERENCES core.customers(id),
    term_deposit_product_id       UUID NOT NULL REFERENCES core.term_deposit_products(id),
    linked_account_id               UUID NOT NULL REFERENCES core.accounts(id), -- source of funding & maturity payout
    principal_amount                  NUMERIC(18,2) NOT NULL CHECK (principal_amount > 0),
    tenure_months                       INTEGER NOT NULL CHECK (tenure_months > 0),
    interest_rate_annual_locked           NUMERIC(6,3) NOT NULL CHECK (interest_rate_annual_locked >= 0),
    maturity_date                           DATE NOT NULL,
    maturity_amount                           NUMERIC(18,2), -- computed at booking time; NULL until calculated
    status                                      TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'MATURED', 'CLOSED_PREMATURE')),
    booked_at                                     TIMESTAMPTZ NOT NULL DEFAULT now(),
    booked_by                                       UUID NOT NULL REFERENCES core.employees(id),
    matured_at                                        TIMESTAMPTZ,
    CONSTRAINT chk_term_deposit_product_is_fd CHECK (TRUE) -- FD-type enforced at application layer against product.deposit_type
);

CREATE INDEX idx_term_deposits_customer ON core.term_deposits(customer_id);
CREATE INDEX idx_term_deposits_status ON core.term_deposits(status);
CREATE INDEX idx_term_deposits_maturity_date ON core.term_deposits(maturity_date);

CREATE TABLE core.recurring_deposits (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rd_reference               TEXT NOT NULL UNIQUE,
    customer_id                  UUID NOT NULL REFERENCES core.customers(id),
    term_deposit_product_id        UUID NOT NULL REFERENCES core.term_deposit_products(id),
    linked_account_id                UUID NOT NULL REFERENCES core.accounts(id),
    installment_amount                 NUMERIC(18,2) NOT NULL CHECK (installment_amount > 0),
    tenure_months                        INTEGER NOT NULL CHECK (tenure_months > 0),
    interest_rate_annual_locked            NUMERIC(6,3) NOT NULL CHECK (interest_rate_annual_locked >= 0),
    start_date                               DATE NOT NULL,
    next_installment_due_date                  DATE NOT NULL,
    status                                        TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'MATURED', 'CLOSED_PREMATURE', 'DEFAULTED')),
    booked_at                                       TIMESTAMPTZ NOT NULL DEFAULT now(),
    booked_by                                         UUID NOT NULL REFERENCES core.employees(id)
);

CREATE INDEX idx_recurring_deposits_customer ON core.recurring_deposits(customer_id);
CREATE INDEX idx_recurring_deposits_status ON core.recurring_deposits(status);
CREATE INDEX idx_recurring_deposits_next_due ON core.recurring_deposits(next_installment_due_date);

CREATE TABLE core.recurring_deposit_installments (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recurring_deposit_id      UUID NOT NULL REFERENCES core.recurring_deposits(id) ON DELETE CASCADE,
    installment_number          INTEGER NOT NULL CHECK (installment_number > 0),
    due_date                       DATE NOT NULL,
    paid_amount                       NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (paid_amount >= 0),
    transaction_id                       UUID REFERENCES core.transactions(id), -- ledger-posting transaction once paid
    paid_at                                 TIMESTAMPTZ,
    status                                     TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'PAID', 'OVERDUE', 'MISSED')),
    UNIQUE (recurring_deposit_id, installment_number)
);

CREATE INDEX idx_rd_installments_rd ON core.recurring_deposit_installments(recurring_deposit_id);
CREATE INDEX idx_rd_installments_status ON core.recurring_deposit_installments(status);

CREATE TABLE core.term_deposit_status_history (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    term_deposit_id            UUID REFERENCES core.term_deposits(id) ON DELETE CASCADE,
    recurring_deposit_id          UUID REFERENCES core.recurring_deposits(id) ON DELETE CASCADE,
    previous_status                  TEXT,
    new_status                          TEXT NOT NULL,
    reason                                 TEXT,
    changed_by                                UUID REFERENCES core.employees(id),
    changed_at                                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_exactly_one_deposit_ref CHECK (
        (term_deposit_id IS NOT NULL AND recurring_deposit_id IS NULL) OR
        (term_deposit_id IS NULL AND recurring_deposit_id IS NOT NULL)
    )
);

CREATE INDEX idx_td_status_history_td ON core.term_deposit_status_history(term_deposit_id);
CREATE INDEX idx_td_status_history_rd ON core.term_deposit_status_history(recurring_deposit_id);

REVOKE UPDATE, DELETE ON core.term_deposit_status_history FROM PUBLIC;

-- =====================================================================
-- END OF 08_term_deposits.sql
-- =====================================================================
