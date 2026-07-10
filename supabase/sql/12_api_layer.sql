-- =====================================================================
-- BANKCORE X — 12_api_layer.sql
-- The "api" schema: the ONLY thing PostgREST ever exposes
-- (PGRST_DB_SCHEMAS=api). Two access patterns:
--   READS  -> views, created WITH (security_invoker = true) so RLS from
--             11_roles_and_rls.sql is actually enforced per calling role.
--   WRITES -> SECURITY DEFINER functions, called as PostgREST RPC
--             endpoints (POST /rpc/deposit, etc). These intentionally
--             bypass RLS (they're owned by the table owner) because they
--             contain their own explicit, auditable authorization checks.
-- Depends on: all prior files (01-11)
-- =====================================================================

-- =====================================================================
-- SHARED HELPER: atomically generate the next readable reference number
-- for a given entity type, using core.reference_formats (Step 2).
-- =====================================================================

CREATE OR REPLACE FUNCTION core.generate_reference(p_entity_type TEXT)
RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    v_row core.reference_formats%ROWTYPE;
    v_seq_text TEXT;
BEGIN
    UPDATE core.reference_formats
    SET next_sequence = next_sequence + 1
    WHERE entity_type = p_entity_type
    RETURNING * INTO v_row;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No reference format configured for entity_type %', p_entity_type;
    END IF;

    v_seq_text := lpad((v_row.next_sequence - 1)::TEXT, v_row.sequence_padding, '0');
    RETURN replace(replace(v_row.format_pattern, '{prefix}', v_row.prefix), '{sequence}', v_seq_text);
END;
$$;

-- =====================================================================
-- READ VIEWS (security_invoker = true -> RLS enforced per caller)
-- =====================================================================

CREATE VIEW api.my_accounts WITH (security_invoker = true) AS
    SELECT a.*
    FROM core.accounts a
    JOIN core.account_holders ah ON ah.account_id = a.id
    WHERE ah.customer_id = core.current_customer_id()
       OR core.is_staff();

CREATE VIEW api.my_transactions WITH (security_invoker = true) AS
    SELECT DISTINCT t.*
    FROM core.transactions t
    JOIN core.journal_entries je ON je.transaction_id = t.id
    JOIN core.account_holders ah ON ah.account_id = je.account_id
    WHERE ah.customer_id = core.current_customer_id()
       OR core.is_staff();

CREATE VIEW api.my_loans WITH (security_invoker = true) AS
    SELECT * FROM core.loans
    WHERE customer_id = core.current_customer_id() OR core.is_staff();

CREATE VIEW api.my_cards WITH (security_invoker = true) AS
    SELECT id, card_reference, account_id, customer_id, card_product_id,
           masked_card_number, status, daily_atm_limit, daily_pos_limit,
           daily_online_limit, issued_at, expiry_date, created_at
    FROM core.cards
    WHERE customer_id = core.current_customer_id() OR core.is_staff();

CREATE VIEW api.my_notifications WITH (security_invoker = true) AS
    SELECT * FROM core.notifications
    WHERE recipient_customer_id = core.current_customer_id()
       OR recipient_employee_id = core.current_employee_id();

CREATE VIEW api.product_catalog_accounts WITH (security_invoker = true) AS
    SELECT id, product_code, product_name, account_category, minimum_balance,
           monthly_maintenance_fee, status
    FROM core.account_products WHERE status = 'ACTIVE';

GRANT SELECT ON api.my_accounts, api.my_transactions, api.my_loans, api.my_cards,
    api.my_notifications TO authenticated;
GRANT SELECT ON api.product_catalog_accounts TO anon, authenticated;

-- =====================================================================
-- WRITE FUNCTIONS — balance-changing operations
-- =====================================================================

-- ---------------------------------------------------------------------
-- api.deposit — branch-counter cash deposit (staff-initiated)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.deposit(
    p_account_id UUID,
    p_amount NUMERIC,
    p_channel_code TEXT,
    p_description TEXT DEFAULT NULL
)
RETURNS core.transactions
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_account core.accounts%ROWTYPE;
    v_channel_id UUID;
    v_gl_cash_id UUID;
    v_business_date DATE;
    v_txn core.transactions%ROWTYPE;
BEGIN
    IF NOT core.is_staff() THEN
        RAISE EXCEPTION 'Only staff may post a branch-counter deposit';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Deposit amount must be positive';
    END IF;

    SELECT * INTO v_account FROM core.accounts WHERE id = p_account_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account % not found', p_account_id;
    END IF;
    IF v_account.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Account % is not ACTIVE (status=%)', p_account_id, v_account.status;
    END IF;

    SELECT id INTO v_channel_id FROM core.transaction_channels WHERE channel_code = p_channel_code AND status = 'ACTIVE';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown or inactive channel_code %', p_channel_code;
    END IF;

    SELECT id INTO v_gl_cash_id FROM core.gl_accounts WHERE gl_code = 'GL-CASH' AND status = 'ACTIVE';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'GL-CASH control account is not configured — see docs/BOOTSTRAP_SEQUENCE.md';
    END IF;

    SELECT current_business_date INTO v_business_date FROM core.business_date;

    INSERT INTO core.transactions (
        transaction_reference, transaction_type, channel_id, business_date,
        status, description, initiated_by_employee_id, posted_at
    ) VALUES (
        core.generate_reference('TRANSACTION'), 'DEPOSIT', v_channel_id, v_business_date,
        'POSTED', p_description, core.current_employee_id(), now()
    ) RETURNING * INTO v_txn;

    INSERT INTO core.journal_entries (transaction_id, account_id, entry_type, amount, narration)
    VALUES (v_txn.id, p_account_id, 'CREDIT', p_amount, 'Deposit');

    INSERT INTO core.journal_entries (transaction_id, gl_account_id, entry_type, amount, narration)
    VALUES (v_txn.id, v_gl_cash_id, 'DEBIT', p_amount, 'Deposit — cash in');

    RETURN v_txn;
END;
$$;

-- ---------------------------------------------------------------------
-- api.withdraw — branch-counter cash withdrawal (staff-initiated)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.withdraw(
    p_account_id UUID,
    p_amount NUMERIC,
    p_channel_code TEXT,
    p_description TEXT DEFAULT NULL
)
RETURNS core.transactions
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_account core.accounts%ROWTYPE;
    v_channel_id UUID;
    v_gl_cash_id UUID;
    v_business_date DATE;
    v_txn core.transactions%ROWTYPE;
BEGIN
    IF NOT core.is_staff() THEN
        RAISE EXCEPTION 'Only staff may post a branch-counter withdrawal';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Withdrawal amount must be positive';
    END IF;

    SELECT * INTO v_account FROM core.accounts WHERE id = p_account_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account % not found', p_account_id;
    END IF;
    IF v_account.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Account % is not ACTIVE (status=%)', p_account_id, v_account.status;
    END IF;
    IF v_account.cached_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance: available=%, requested=%', v_account.cached_balance, p_amount;
    END IF;

    SELECT id INTO v_channel_id FROM core.transaction_channels WHERE channel_code = p_channel_code AND status = 'ACTIVE';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown or inactive channel_code %', p_channel_code;
    END IF;

    SELECT id INTO v_gl_cash_id FROM core.gl_accounts WHERE gl_code = 'GL-CASH' AND status = 'ACTIVE';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'GL-CASH control account is not configured — see docs/BOOTSTRAP_SEQUENCE.md';
    END IF;

    SELECT current_business_date INTO v_business_date FROM core.business_date;

    INSERT INTO core.transactions (
        transaction_reference, transaction_type, channel_id, business_date,
        status, description, initiated_by_employee_id, posted_at
    ) VALUES (
        core.generate_reference('TRANSACTION'), 'WITHDRAWAL', v_channel_id, v_business_date,
        'POSTED', p_description, core.current_employee_id(), now()
    ) RETURNING * INTO v_txn;

    INSERT INTO core.journal_entries (transaction_id, account_id, entry_type, amount, narration)
    VALUES (v_txn.id, p_account_id, 'DEBIT', p_amount, 'Withdrawal');

    INSERT INTO core.journal_entries (transaction_id, gl_account_id, entry_type, amount, narration)
    VALUES (v_txn.id, v_gl_cash_id, 'CREDIT', p_amount, 'Withdrawal — cash out');

    RETURN v_txn;
END;
$$;

-- ---------------------------------------------------------------------
-- api.internal_transfer — customer self-service OR staff-assisted
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.internal_transfer(
    p_from_account_id UUID,
    p_to_account_id UUID,
    p_amount NUMERIC,
    p_description TEXT DEFAULT NULL
)
RETURNS core.transactions
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_from_account core.accounts%ROWTYPE;
    v_to_account core.accounts%ROWTYPE;
    v_channel_id UUID;
    v_business_date DATE;
    v_txn core.transactions%ROWTYPE;
    v_owns_from BOOLEAN;
BEGIN
    IF p_from_account_id = p_to_account_id THEN
        RAISE EXCEPTION 'Cannot transfer an account to itself';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be positive';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM core.account_holders
        WHERE account_id = p_from_account_id AND customer_id = core.current_customer_id()
    ) INTO v_owns_from;

    IF NOT (core.is_staff() OR v_owns_from) THEN
        RAISE EXCEPTION 'Not authorized to transfer from account %', p_from_account_id;
    END IF;

    SELECT * INTO v_from_account FROM core.accounts WHERE id = p_from_account_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Source account % not found', p_from_account_id; END IF;
    IF v_from_account.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Source account % is not ACTIVE (status=%)', p_from_account_id, v_from_account.status;
    END IF;
    IF v_from_account.cached_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance: available=%, requested=%', v_from_account.cached_balance, p_amount;
    END IF;

    SELECT * INTO v_to_account FROM core.accounts WHERE id = p_to_account_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Destination account % not found', p_to_account_id; END IF;
    IF v_to_account.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Destination account % is not ACTIVE (status=%)', p_to_account_id, v_to_account.status;
    END IF;

    SELECT id INTO v_channel_id FROM core.transaction_channels WHERE channel_code = 'INTERNAL_TRANSFER' AND status = 'ACTIVE';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'INTERNAL_TRANSFER channel is not configured — see docs/BOOTSTRAP_SEQUENCE.md';
    END IF;

    SELECT current_business_date INTO v_business_date FROM core.business_date;

    INSERT INTO core.transactions (
        transaction_reference, transaction_type, channel_id, business_date,
        status, description, initiated_by_employee_id, initiated_by_customer_id, posted_at
    ) VALUES (
        core.generate_reference('TRANSACTION'), 'INTERNAL_TRANSFER', v_channel_id, v_business_date,
        'POSTED', p_description,
        CASE WHEN core.is_staff() THEN core.current_employee_id() ELSE NULL END,
        CASE WHEN core.is_staff() THEN NULL ELSE core.current_customer_id() END,
        now()
    ) RETURNING * INTO v_txn;

    INSERT INTO core.journal_entries (transaction_id, account_id, entry_type, amount, narration)
    VALUES (v_txn.id, p_from_account_id, 'DEBIT', p_amount, 'Internal transfer out');

    INSERT INTO core.journal_entries (transaction_id, account_id, entry_type, amount, narration)
    VALUES (v_txn.id, p_to_account_id, 'CREDIT', p_amount, 'Internal transfer in');

    RETURN v_txn;
END;
$$;

-- ---------------------------------------------------------------------
-- api.reverse_transaction — reverse a POSTED transaction (never delete)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.reverse_transaction(
    p_transaction_id UUID,
    p_reason TEXT
)
RETURNS core.transactions
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_original core.transactions%ROWTYPE;
    v_reversal core.transactions%ROWTYPE;
    v_business_date DATE;
    v_je RECORD;
BEGIN
    IF NOT (core.is_admin() OR core.employee_has_permission('TRANSACTION.REVERSE')) THEN
        RAISE EXCEPTION 'Not authorized to reverse transactions';
    END IF;

    IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'A reason is required to reverse a transaction';
    END IF;

    SELECT * INTO v_original FROM core.transactions WHERE id = p_transaction_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transaction % not found', p_transaction_id;
    END IF;
    IF v_original.status <> 'POSTED' THEN
        RAISE EXCEPTION 'Only POSTED transactions can be reversed (current status=%)', v_original.status;
    END IF;
    IF EXISTS (SELECT 1 FROM core.transaction_reversals WHERE original_transaction_id = p_transaction_id) THEN
        RAISE EXCEPTION 'Transaction % has already been reversed', p_transaction_id;
    END IF;

    SELECT current_business_date INTO v_business_date FROM core.business_date;

    INSERT INTO core.transactions (
        transaction_reference, transaction_type, channel_id, business_date,
        status, description, initiated_by_employee_id, posted_at
    ) VALUES (
        core.generate_reference('TRANSACTION'), 'REVERSAL', v_original.channel_id, v_business_date,
        'POSTED', 'Reversal of ' || v_original.transaction_reference || ': ' || p_reason,
        core.current_employee_id(), now()
    ) RETURNING * INTO v_reversal;

    -- Mirror every original journal entry with entry_type flipped
    FOR v_je IN SELECT * FROM core.journal_entries WHERE transaction_id = v_original.id
    LOOP
        INSERT INTO core.journal_entries (transaction_id, account_id, gl_account_id, entry_type, amount, narration)
        VALUES (
            v_reversal.id, v_je.account_id, v_je.gl_account_id,
            CASE WHEN v_je.entry_type = 'DEBIT' THEN 'CREDIT' ELSE 'DEBIT' END,
            v_je.amount, 'Reversal of: ' || COALESCE(v_je.narration, '')
        );
    END LOOP;

    INSERT INTO core.transaction_reversals (original_transaction_id, reversal_transaction_id, reason, initiated_by)
    VALUES (v_original.id, v_reversal.id, p_reason, core.current_employee_id());

    UPDATE core.transactions SET status = 'REVERSED' WHERE id = v_original.id;

    RETURN v_reversal;
END;
$$;

-- =====================================================================
-- GRANTS on functions (EXECUTE only — this is the actual write access)
-- =====================================================================

-- SUPABASE NOTE: deposit/withdraw/reverse_transaction used to be
-- restricted to web_staff/web_admin at the GRANT level too. Under
-- Supabase's anon/authenticated model that outer gate is gone, but each
-- function above already RAISE EXCEPTIONs internally if
-- core.is_staff()/core.is_admin()/employee_has_permission() fails, so
-- authorization still holds — just enforced one layer deeper than before.
GRANT EXECUTE ON FUNCTION api.deposit(UUID, NUMERIC, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION api.withdraw(UUID, NUMERIC, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION api.internal_transfer(UUID, UUID, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION api.reverse_transaction(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION api.internal_transfer IS
    'Callable by a customer for their own account, or by staff on behalf
     of a customer. Authorization is checked explicitly in the function
     body via core.is_staff() / account_holders ownership — this is the
     pattern every future write function in this project follows.';

-- =====================================================================
-- END OF 12_api_layer.sql
-- =====================================================================
