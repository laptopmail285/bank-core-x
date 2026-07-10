-- =====================================================================
-- BANKCORE X — 13_eod_procedure.sql
-- End-of-Day orchestration: the procedure that actually runs the steps
-- tracked by core.eod_runs / core.eod_step_log (Step 6 tables).
-- Depends on: 01_schema.sql, 04_accounts.sql, 07_loans.sql,
--             10_notifications_scheduling_eod.sql
-- =====================================================================

CREATE OR REPLACE FUNCTION core.run_eod(p_initiated_by UUID DEFAULT NULL)
RETURNS core.eod_runs
LANGUAGE plpgsql AS $$
DECLARE
    v_current_date DATE;
    v_eod_run core.eod_runs%ROWTYPE;
    v_dormancy_count INTEGER;
    v_overdue_count INTEGER;
BEGIN
    SELECT current_business_date INTO v_current_date FROM core.business_date;

    IF (SELECT is_eod_in_progress FROM core.business_date) THEN
        RAISE EXCEPTION 'EOD is already in progress — cannot start a second run';
    END IF;

    IF EXISTS (SELECT 1 FROM core.eod_runs WHERE business_date = v_current_date) THEN
        RAISE EXCEPTION 'EOD has already been run for business date %', v_current_date;
    END IF;

    UPDATE core.business_date
    SET is_eod_in_progress = TRUE, last_eod_started_at = now();

    INSERT INTO core.eod_runs (business_date, initiated_by, status)
    VALUES (v_current_date, p_initiated_by, 'IN_PROGRESS')
    RETURNING * INTO v_eod_run;

    -- ---------------- STEP 1: DORMANCY_CHECK ----------------
    INSERT INTO core.eod_step_log (eod_run_id, step_name, step_order, status, started_at)
    VALUES (v_eod_run.id, 'DORMANCY_CHECK', 1, 'RUNNING', now());

    WITH newly_dormant AS (
        UPDATE core.accounts a
        SET status = 'DORMANT'
        WHERE a.status = 'ACTIVE'
          AND a.cached_balance_as_of < (v_current_date - INTERVAL '365 days')
        RETURNING a.id
    )
    SELECT count(*) INTO v_dormancy_count FROM newly_dormant;

    RAISE NOTICE 'EOD %: % account(s) marked DORMANT', v_current_date, v_dormancy_count;

    UPDATE core.eod_step_log
    SET status = 'SUCCESS', completed_at = now()
    WHERE eod_run_id = v_eod_run.id AND step_name = 'DORMANCY_CHECK';

    -- ---------------- STEP 2: LOAN_OVERDUE_MARKING ----------------
    INSERT INTO core.eod_step_log (eod_run_id, step_name, step_order, status, started_at)
    VALUES (v_eod_run.id, 'LOAN_OVERDUE_MARKING', 2, 'RUNNING', now());

    WITH newly_overdue AS (
        UPDATE core.loan_repayment_schedule s
        SET status = 'OVERDUE'
        WHERE s.status = 'PENDING'
          AND s.due_date < v_current_date
        RETURNING s.id
    )
    SELECT count(*) INTO v_overdue_count FROM newly_overdue;

    RAISE NOTICE 'EOD %: % loan installment(s) marked OVERDUE', v_current_date, v_overdue_count;

    UPDATE core.eod_step_log
    SET status = 'SUCCESS', completed_at = now()
    WHERE eod_run_id = v_eod_run.id AND step_name = 'LOAN_OVERDUE_MARKING';

    -- ---------------- STEP 3: BUSINESS_DATE_ADVANCE ----------------
    INSERT INTO core.eod_step_log (eod_run_id, step_name, step_order, status, started_at)
    VALUES (v_eod_run.id, 'BUSINESS_DATE_ADVANCE', 3, 'RUNNING', now());

    UPDATE core.business_date
    SET previous_business_date = current_business_date,
        current_business_date = current_business_date + INTERVAL '1 day',
        is_eod_in_progress = FALSE,
        last_eod_completed_at = now();

    UPDATE core.eod_step_log
    SET status = 'SUCCESS', completed_at = now()
    WHERE eod_run_id = v_eod_run.id AND step_name = 'BUSINESS_DATE_ADVANCE';

    -- ---------------- Finalize the run ----------------
    UPDATE core.eod_runs
    SET status = 'COMPLETED', completed_at = now()
    WHERE id = v_eod_run.id
    RETURNING * INTO v_eod_run;

    RETURN v_eod_run;

EXCEPTION WHEN OTHERS THEN
    -- On any failure: mark the run failed, clear the in-progress flag so
    -- a retry is possible, and re-raise so the caller sees the real error.
    UPDATE core.eod_runs SET status = 'FAILED', completed_at = now() WHERE id = v_eod_run.id;
    UPDATE core.business_date SET is_eod_in_progress = FALSE;
    RAISE;
END;
$$;

COMMENT ON FUNCTION core.run_eod IS
    'Not SECURITY DEFINER: this function is intended to be called either
     directly by the trusted backend service (Step 9, using elevated
     credentials for scheduled/automated runs) or via api.trigger_eod()
     below (for an authenticated admin manually triggering EOD from the
     Admin Panel).';

-- ---------------------------------------------------------------------
-- api.trigger_eod — admin-triggerable wrapper (SECURITY DEFINER)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.trigger_eod()
RETURNS core.eod_runs
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF NOT core.is_admin() THEN
        RAISE EXCEPTION 'Only SYSTEM_ADMIN may manually trigger EOD';
    END IF;
    RETURN core.run_eod(core.current_employee_id());
END;
$$;

GRANT EXECUTE ON FUNCTION api.trigger_eod() TO web_admin;

-- =====================================================================
-- END OF 13_eod_procedure.sql
-- =====================================================================
