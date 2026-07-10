-- =====================================================================
-- BANKCORE X — 09_cards.sql
-- Cards domain (SIMULATED — no real card network integration).
-- No real card numbers, CVV, or plain-text PIN are ever stored (Rule #12).
-- Depends on: 01_schema.sql, 02_product_engines.sql, 03_customer_kyc.sql,
--             04_accounts.sql, 05_ledger_transactions.sql
-- =====================================================================

CREATE TABLE core.cards (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_reference             TEXT NOT NULL UNIQUE,
    account_id                   UUID NOT NULL REFERENCES core.accounts(id),
    customer_id                    UUID NOT NULL REFERENCES core.customers(id),
    card_product_id                  UUID NOT NULL REFERENCES core.card_products(id),
    masked_card_number                 TEXT NOT NULL, -- e.g. "XXXX-XXXX-XXXX-4821" — simulated, never a real PAN
    status                                TEXT NOT NULL DEFAULT 'REQUESTED'
        CHECK (status IN ('REQUESTED', 'ACTIVE', 'BLOCKED', 'EXPIRED', 'CANCELLED')),
    daily_atm_limit                         NUMERIC(18,2) NOT NULL,
    daily_pos_limit                           NUMERIC(18,2) NOT NULL,
    daily_online_limit                          NUMERIC(18,2) NOT NULL,
    issued_at                                     TIMESTAMPTZ,
    expiry_date                                     DATE,
    issued_by                                         UUID REFERENCES core.employees(id),
    created_at                                          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_cards_account ON core.cards(account_id);
CREATE INDEX idx_cards_customer ON core.cards(customer_id);
CREATE INDEX idx_cards_status ON core.cards(status);

COMMENT ON COLUMN core.cards.masked_card_number IS
    'Simulated display value only (e.g. XXXX-XXXX-XXXX-4821). This system
     never generates, stores, or transmits a real 16-digit PAN (Rule #12).';

-- ---------------------------------------------------------------------
-- core.card_pin_hashes — PIN is ALWAYS stored as a salted hash, 1:1
-- with a card, never in plain text anywhere (Rule #12).
-- ---------------------------------------------------------------------
CREATE TABLE core.card_pin_hashes (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id                    UUID NOT NULL UNIQUE REFERENCES core.cards(id) ON DELETE CASCADE,
    pin_hash                     TEXT NOT NULL, -- bcrypt/argon2 hash, set via backend using pgcrypto or app-side hashing
    updated_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_card_pin_hashes_updated_at
    BEFORE UPDATE ON core.card_pin_hashes
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

COMMENT ON TABLE core.card_pin_hashes IS
    'Stores only a one-way hash of the PIN. No function or view in this
     system ever exposes a plain-text PIN (Rule #12).';

CREATE TABLE core.card_transactions_sim (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id                    UUID NOT NULL REFERENCES core.cards(id),
    transaction_id                UUID REFERENCES core.transactions(id), -- ledger-posting txn, NULL if declined
    merchant_name_sim               TEXT NOT NULL,
    channel_sim                       TEXT NOT NULL CHECK (channel_sim IN ('ATM', 'POS', 'ONLINE')),
    amount                               NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    status                                 TEXT NOT NULL CHECK (status IN ('APPROVED', 'DECLINED')),
    declined_reason                          TEXT,
    created_at                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_declined_has_reason CHECK (
        (status = 'APPROVED') OR (status = 'DECLINED' AND declined_reason IS NOT NULL)
    ),
    CONSTRAINT chk_approved_has_transaction CHECK (
        (status = 'DECLINED') OR (status = 'APPROVED' AND transaction_id IS NOT NULL)
    )
);

CREATE INDEX idx_card_transactions_sim_card ON core.card_transactions_sim(card_id);
CREATE INDEX idx_card_transactions_sim_status ON core.card_transactions_sim(status);

COMMENT ON TABLE core.card_transactions_sim IS
    'Fully simulated card-present/card-not-present transactions for
     demonstration only. No real card network (Visa/Mastercard/RuPay)
     is contacted (Rule #15).';

CREATE TABLE core.card_status_history (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id                    UUID NOT NULL REFERENCES core.cards(id) ON DELETE CASCADE,
    previous_status               TEXT,
    new_status                      TEXT NOT NULL,
    reason                             TEXT,
    changed_by                            UUID REFERENCES core.employees(id),
    changed_at                               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_card_status_history_card ON core.card_status_history(card_id);

REVOKE UPDATE, DELETE ON core.card_status_history FROM PUBLIC;

-- =====================================================================
-- END OF 09_cards.sql
-- =====================================================================
