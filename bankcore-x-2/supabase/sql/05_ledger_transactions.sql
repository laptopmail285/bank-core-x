-- =====================================================================
-- BANKCORE X — 05_ledger_transactions.sql
-- Ledger & Transaction Engine — the financial core of the system.
-- Depends on: 01_schema.sql, 02_product_engines.sql, 04_accounts.sql
--
-- CORE INVARIANTS ENFORCED HERE:
--   1. Every transaction's journal entries must debit = credit (Rule #4).
--   2. Journal entries are APPEND-ONLY — never updated, never deleted.
--   3. Posted transactions are reversed via a new offsetting transaction,
--      never deleted or edited (Non-Negotiable Rule, Decision: "Why are
--      posted transactions reversed instead of deleted?").
--   4. core.accounts.cached_balance is updated ONLY as a side-effect of
--      posting journal entries — never written to directly by any role
--      other than the trigger function itself.
-- =====================================================================

-- ---------------------------------------------------------------------
-- core.gl_accounts — internal General Ledger control accounts
-- (bank-side counterparts for double-entry: e.g. Cash/Vault, Interest
-- Payable, Fee Income, Suspense, Interbank Clearing)
-- ---------------------------------------------------------------------
CREATE TABLE core.gl_accounts (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gl_code                 TEXT NOT NULL UNIQUE,
    gl_name                 TEXT NOT NULL,
    gl_category             TEXT NOT NULL CHECK (gl_category IN ('ASSET', 'LIABILITY', 'INCOME', 'EXPENSE', 'EQUITY', 'SUSPENSE')),
    status                  TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              UUID NOT NULL REFERENCES core.employees(id)
);

COMMENT ON TABLE core.gl_accounts IS
    'Internal bank-side ledger control accounts. Every customer-facing
     transaction (deposit, withdrawal, fee, interest) has a GL counterpart
     so the books always balance in true double-entry fashion.';

-- ---------------------------------------------------------------------
-- core.transactions — transaction header (one row per customer-visible
-- transaction, regardless of how many journal legs it produces)
-- ---------------------------------------------------------------------
CREATE TABLE core.transactions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_reference   TEXT NOT NULL UNIQUE,
    transaction_type        TEXT NOT NULL CHECK (transaction_type IN (
        'DEPOSIT', 'WITHDRAWAL', 'INTERNAL_TRANSFER', 'EXTERNAL_TRANSFER_SIM',
        'FEE', 'INTEREST_CREDIT', 'INTEREST_DEBIT', 'LOAN_DISBURSEMENT',
        'LOAN_REPAYMENT', 'FD_BOOKING', 'FD_MATURITY', 'RD_INSTALLMENT',
        'CARD_TRANSACTION_SIM', 'REVERSAL'
    )),
    channel_id              UUID NOT NULL REFERENCES core.transaction_channels(id),
    business_date            DATE NOT NULL,
    status                    TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'POSTED', 'FAILED', 'REVERSED')),
    description                TEXT,
    initiated_by_employee_id   UUID REFERENCES core.employees(id),  -- NULL if customer self-initiated
    initiated_by_customer_id   UUID REFERENCES core.customers(id),  -- NULL if employee-initiated
    posted_at                   TIMESTAMPTZ,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_exactly_one_initiator CHECK (
        (initiated_by_employee_id IS NOT NULL AND initiated_by_customer_id IS NULL) OR
        (initiated_by_employee_id IS NULL AND initiated_by_customer_id IS NOT NULL)
    ),
    CONSTRAINT chk_posted_at_requires_posted_status CHECK (
        (status <> 'POSTED') OR (posted_at IS NOT NULL)
    )
);

CREATE INDEX idx_transactions_status ON core.transactions(status);
CREATE INDEX idx_transactions_business_date ON core.transactions(business_date);
CREATE INDEX idx_transactions_type ON core.transactions(transaction_type);

-- ---------------------------------------------------------------------
-- core.journal_entries — the immutable double-entry ledger itself.
-- Exactly one of (account_id, gl_account_id) must be set per row.
-- ---------------------------------------------------------------------
CREATE TABLE core.journal_entries (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id           UUID NOT NULL REFERENCES core.transactions(id),
    account_id                UUID REFERENCES core.accounts(id),
    gl_account_id              UUID REFERENCES core.gl_accounts(id),
    entry_type                  TEXT NOT NULL CHECK (entry_type IN ('DEBIT', 'CREDIT')),
    amount                       NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    currency                      TEXT NOT NULL DEFAULT 'INR',
    narration                     TEXT,
    created_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_exactly_one_ledger_target CHECK (
        (account_id IS NOT NULL AND gl_account_id IS NULL) OR
        (account_id IS NULL AND gl_account_id IS NOT NULL)
    )
);

CREATE INDEX idx_journal_entries_transaction ON core.journal_entries(transaction_id);
CREATE INDEX idx_journal_entries_account ON core.journal_entries(account_id);
CREATE INDEX idx_journal_entries_gl_account ON core.journal_entries(gl_account_id);

COMMENT ON TABLE core.journal_entries IS
    'APPEND-ONLY. Never UPDATE or DELETE a posted journal entry. To
     correct a mistake, post a new reversing transaction (see
     core.transaction_reversals).';

-- Enforce true immutability at the grant level (defense in depth;
-- role-level grants are finalized in 06_rls_policies.sql)
REVOKE UPDATE, DELETE ON core.journal_entries FROM PUBLIC;

-- ---------------------------------------------------------------------
-- BALANCE ENFORCEMENT: sum(DEBIT) must equal sum(CREDIT) per transaction.
-- Implemented as a deferred constraint trigger so multiple journal_entry
-- rows can be inserted within one transaction and checked once at commit.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.check_transaction_balance()
RETURNS TRIGGER AS $$
DECLARE
    v_transaction_id UUID;
    v_debit_total NUMERIC(18,2);
    v_credit_total NUMERIC(18,2);
BEGIN
    v_transaction_id := COALESCE(NEW.transaction_id, OLD.transaction_id);

    SELECT
        COALESCE(SUM(amount) FILTER (WHERE entry_type = 'DEBIT'), 0),
        COALESCE(SUM(amount) FILTER (WHERE entry_type = 'CREDIT'), 0)
    INTO v_debit_total, v_credit_total
    FROM core.journal_entries
    WHERE transaction_id = v_transaction_id;

    IF v_debit_total <> v_credit_total THEN
        RAISE EXCEPTION
            'Unbalanced transaction %: debits=% credits=% — every transaction must balance exactly',
            v_transaction_id, v_debit_total, v_credit_total;
    END IF;

    RETURN NULL; -- constraint triggers ignore return value
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_check_transaction_balance
    AFTER INSERT ON core.journal_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION core.check_transaction_balance();

-- ---------------------------------------------------------------------
-- CACHED BALANCE MAINTENANCE: every journal entry against a customer
-- account updates that account's cached_balance. This trigger is the
-- ONLY path by which cached_balance ever changes.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.apply_journal_entry_to_cached_balance()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.account_id IS NOT NULL THEN
        UPDATE core.accounts
        SET cached_balance = cached_balance +
                CASE WHEN NEW.entry_type = 'CREDIT' THEN NEW.amount ELSE -NEW.amount END,
            cached_balance_as_of = now()
        WHERE id = NEW.account_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_apply_journal_entry_to_cached_balance
    AFTER INSERT ON core.journal_entries
    FOR EACH ROW EXECUTE FUNCTION core.apply_journal_entry_to_cached_balance();

COMMENT ON FUNCTION core.apply_journal_entry_to_cached_balance IS
    'Convention: for customer accounts, CREDIT increases balance
     (deposits, interest earned) and DEBIT decreases balance
     (withdrawals, fees) — standard liability-account accounting from
     the bank''s perspective, matching how a customer expects their
     balance to behave.';

-- ---------------------------------------------------------------------
-- core.transaction_reversals — links an original POSTED transaction to
-- its reversing transaction. Enforces "reverse, never delete."
-- ---------------------------------------------------------------------
CREATE TABLE core.transaction_reversals (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_transaction_id UUID NOT NULL REFERENCES core.transactions(id),
    reversal_transaction_id  UUID NOT NULL REFERENCES core.transactions(id),
    reason                     TEXT NOT NULL,
    initiated_by                UUID NOT NULL REFERENCES core.employees(id),
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (original_transaction_id),
    CONSTRAINT chk_reversal_not_self CHECK (original_transaction_id <> reversal_transaction_id)
);

CREATE INDEX idx_transaction_reversals_original ON core.transaction_reversals(original_transaction_id);

-- =====================================================================
-- BOOTSTRAP DATA — standard GL control accounts
-- (config-only seed; requires the bootstrap admin employee from
-- docs/BOOTSTRAP_SEQUENCE.md to already exist)
-- =====================================================================
-- Deferred seed template (run after bootstrap admin exists):
--
-- INSERT INTO core.gl_accounts (gl_code, gl_name, gl_category, created_by) VALUES
--     ('GL-CASH',      'Cash / Vault',            'ASSET',     :admin_employee_id),
--     ('GL-SUSPENSE',  'Suspense Account',         'SUSPENSE',  :admin_employee_id),
--     ('GL-INT-PAY',   'Interest Payable',         'LIABILITY', :admin_employee_id),
--     ('GL-INT-EXP',   'Interest Expense',         'EXPENSE',   :admin_employee_id),
--     ('GL-FEE-INC',   'Fee Income',               'INCOME',    :admin_employee_id),
--     ('GL-LOAN-ASSET','Loans Receivable',         'ASSET',     :admin_employee_id),
--     ('GL-CLEARING',  'Interbank Clearing (Sim)', 'ASSET',     :admin_employee_id);

-- =====================================================================
-- END OF 05_ledger_transactions.sql
-- =====================================================================
