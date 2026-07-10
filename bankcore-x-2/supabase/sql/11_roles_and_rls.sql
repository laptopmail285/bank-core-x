-- =====================================================================
-- BANKCORE X — 11_roles_and_rls.sql
-- Database roles + Row Level Security (secure-by-default).
-- Depends on: all prior files (01-10)
--
-- ⚠️ IMPORTANT POSTGRES BEHAVIOR THIS FILE DELIBERATELY ACCOUNTS FOR:
-- The role that OWNS a table bypasses Row Level Security by default,
-- regardless of any policy defined on it. Since the migration role
-- (POSTGRES_USER, e.g. "bankcore_admin") owns every table it created,
-- any function or view ALSO owned by that same role would silently
-- bypass every RLS policy below — making RLS look like it works while
-- actually doing nothing for that access path.
--
-- The fix used throughout this project:
--   - Read access from the frontend goes through "api" schema VIEWS
--     created WITH (security_invoker = true) — a PostgreSQL 15+ option
--     that makes the view run as the CALLING role (web_customer /
--     web_staff / web_admin) rather than the view owner, so RLS policies
--     are evaluated against the real, restricted role.
--   - Write access goes through SECURITY DEFINER functions, which are
--     INTENTIONALLY allowed to bypass RLS (they contain their own
--     explicit authorization checks in code, e.g. core.prevent_self_approval,
--     ownership checks, and permission checks) — this is the one place
--     RLS bypass is correct and expected.
-- =====================================================================

-- =====================================================================
-- ROLES
-- SUPABASE NOTE: Supabase's hosted PostgREST is pre-wired to the
-- "authenticator" login role and switches every request into either
-- "anon" (no session) or "authenticated" (valid Supabase Auth JWT) —
-- both already exist on every Supabase project and cannot be swapped
-- for custom per-tier roles the way self-hosted PostgREST allowed.
-- We no longer create web_anon/web_customer/web_staff/web_admin/
-- authenticator. The customer/staff/admin distinction that used to
-- live at the GRANT/role level now lives entirely inside the RLS
-- policies below via core.is_staff() / core.is_admin(), which look the
-- caller up in core.employees/core.employee_roles — this was already
-- how those functions worked, so no policy logic below actually
-- changes, only who has permission to reach it in the first place.
--
-- SECURITY NOTE / TRADEOFF: previously, e.g. core.audit_logs was
-- GRANTed only to web_admin, so a customer session couldn't read a
-- single row even if a policy had a bug. Now every authenticated user
-- gets the table-level GRANT, and core.is_admin() in the policy is the
-- only thing standing between a customer and that table. Test the
-- is_staff()/is_admin() policies directly (as different user tiers)
-- before trusting this in front of real data.
-- =====================================================================

GRANT USAGE ON SCHEMA api TO anon, authenticated;
GRANT USAGE ON SCHEMA core TO anon, authenticated;

-- =====================================================================
-- JWT / SESSION HELPER FUNCTIONS
-- auth.uid() is Supabase's built-in helper — it reads the "sub" claim
-- out of the caller's verified JWT the same way the old manual
-- current_setting('request.jwt.claims', ...) parsing did. Kept the same
-- function name/signature so nothing else in 01-10/12-14 needs to change.
-- =====================================================================

CREATE OR REPLACE FUNCTION core.current_auth_subject_id()
RETURNS UUID
LANGUAGE sql STABLE AS $$
    SELECT auth.uid();
$$;

CREATE OR REPLACE FUNCTION core.current_employee_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT id FROM core.employees WHERE auth_subject_id = core.current_auth_subject_id();
$$;

CREATE OR REPLACE FUNCTION core.current_customer_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT id FROM core.customers WHERE auth_subject_id = core.current_auth_subject_id();
$$;

CREATE OR REPLACE FUNCTION core.is_staff()
RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT core.current_employee_id() IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION core.is_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT EXISTS (
        SELECT 1
        FROM core.employee_roles er
        JOIN core.roles r ON r.id = er.role_id
        WHERE er.employee_id = core.current_employee_id()
          AND r.role_code = 'SYSTEM_ADMIN'
    );
$$;

CREATE OR REPLACE FUNCTION core.employee_has_permission(p_permission_code TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT EXISTS (
        SELECT 1
        FROM core.employee_roles er
        JOIN core.role_permissions rp ON rp.role_id = er.role_id
        JOIN core.permissions p ON p.id = rp.permission_id
        WHERE er.employee_id = core.current_employee_id()
          AND p.permission_code = p_permission_code
    );
$$;

COMMENT ON FUNCTION core.current_employee_id IS
    'SECURITY DEFINER is safe here: the WHERE clause is hard-coded to the
     caller''s own auth_subject_id — it cannot be used to look up anyone else.';

-- =====================================================================
-- ENABLE ROW LEVEL SECURITY ON EVERY TABLE IN "core" (secure by default:
-- a table with RLS enabled and NO policy denies ALL access to non-owners,
-- including web_anon/web_customer/web_staff/web_admin, until a policy
-- explicitly grants it).
-- =====================================================================

DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'core'
    LOOP
        EXECUTE format('ALTER TABLE core.%I ENABLE ROW LEVEL SECURITY;', t);
    END LOOP;
END $$;

-- =====================================================================
-- POLICIES — grouped by access pattern
-- =====================================================================

-- ---------- Group 1: Public product catalog (readable by anyone) ----------
CREATE POLICY catalog_public_read ON core.account_products FOR SELECT USING (status = 'ACTIVE');
CREATE POLICY catalog_public_read ON core.loan_products FOR SELECT USING (status = 'ACTIVE');
CREATE POLICY catalog_public_read ON core.term_deposit_products FOR SELECT USING (status = 'ACTIVE');
CREATE POLICY catalog_public_read ON core.card_products FOR SELECT USING (status = 'ACTIVE');
CREATE POLICY catalog_public_read ON core.branches FOR SELECT USING (status = 'ACTIVE');

GRANT SELECT ON core.account_products, core.loan_products, core.term_deposit_products,
    core.card_products, core.branches TO anon, authenticated;

-- ---------- Group 2: Customer self-access tables ----------
-- Pattern: customer sees their own rows; any staff member sees all rows
-- (typical internal-visibility model for branch service); admin sees all.

CREATE POLICY customer_self_or_staff ON core.customers FOR SELECT
    USING (auth_subject_id = core.current_auth_subject_id() OR core.is_staff());

CREATE POLICY customer_self_or_staff ON core.customer_addresses FOR SELECT
    USING (customer_id = core.current_customer_id() OR core.is_staff());

CREATE POLICY customer_self_or_staff ON core.customer_relationships FOR SELECT
    USING (customer_id = core.current_customer_id() OR core.is_staff());

CREATE POLICY customer_self_or_staff ON core.account_holders FOR SELECT
    USING (customer_id = core.current_customer_id() OR core.is_staff());

CREATE POLICY customer_self_or_staff ON core.accounts FOR SELECT
    USING (
        id IN (SELECT account_id FROM core.account_holders WHERE customer_id = core.current_customer_id())
        OR core.is_staff()
    );

CREATE POLICY customer_self_or_staff ON core.account_nominees FOR SELECT
    USING (
        account_id IN (SELECT account_id FROM core.account_holders WHERE customer_id = core.current_customer_id())
        OR core.is_staff()
    );

CREATE POLICY customer_self_or_staff ON core.loans FOR SELECT
    USING (customer_id = core.current_customer_id() OR core.is_staff());

CREATE POLICY customer_self_or_staff ON core.loan_applications FOR SELECT
    USING (customer_id = core.current_customer_id() OR core.is_staff());

CREATE POLICY customer_self_or_staff ON core.loan_repayment_schedule FOR SELECT
    USING (
        loan_id IN (SELECT id FROM core.loans WHERE customer_id = core.current_customer_id())
        OR core.is_staff()
    );

CREATE POLICY customer_self_or_staff ON core.loan_repayments FOR SELECT
    USING (
        loan_id IN (SELECT id FROM core.loans WHERE customer_id = core.current_customer_id())
        OR core.is_staff()
    );

CREATE POLICY customer_self_or_staff ON core.term_deposits FOR SELECT
    USING (customer_id = core.current_customer_id() OR core.is_staff());

CREATE POLICY customer_self_or_staff ON core.recurring_deposits FOR SELECT
    USING (customer_id = core.current_customer_id() OR core.is_staff());

CREATE POLICY customer_self_or_staff ON core.recurring_deposit_installments FOR SELECT
    USING (
        recurring_deposit_id IN (SELECT id FROM core.recurring_deposits WHERE customer_id = core.current_customer_id())
        OR core.is_staff()
    );

CREATE POLICY customer_self_or_staff ON core.cards FOR SELECT
    USING (customer_id = core.current_customer_id() OR core.is_staff());

CREATE POLICY customer_self_or_staff ON core.card_transactions_sim FOR SELECT
    USING (
        card_id IN (SELECT id FROM core.cards WHERE customer_id = core.current_customer_id())
        OR core.is_staff()
    );

CREATE POLICY customer_self_or_staff ON core.notifications FOR SELECT
    USING (recipient_customer_id = core.current_customer_id() OR core.is_staff());

CREATE POLICY customer_self_or_staff ON core.kyc_cases FOR SELECT
    USING (customer_id = core.current_customer_id() OR core.is_staff());

CREATE POLICY customer_self_or_staff ON core.kyc_documents FOR SELECT
    USING (
        kyc_case_id IN (SELECT id FROM core.kyc_cases WHERE customer_id = core.current_customer_id())
        OR core.is_staff()
    );

CREATE POLICY customer_self_or_staff ON core.kyc_status_history FOR SELECT
    USING (
        kyc_case_id IN (SELECT id FROM core.kyc_cases WHERE customer_id = core.current_customer_id())
        OR core.is_staff()
    );

-- Ledger visibility: a customer may see journal entries only for
-- accounts they hold (this is effectively their transaction history).
CREATE POLICY customer_self_or_staff ON core.journal_entries FOR SELECT
    USING (
        account_id IN (SELECT account_id FROM core.account_holders WHERE customer_id = core.current_customer_id())
        OR core.is_staff()
    );

CREATE POLICY customer_self_or_staff ON core.transactions FOR SELECT
    USING (
        id IN (
            SELECT transaction_id FROM core.journal_entries
            WHERE account_id IN (SELECT account_id FROM core.account_holders WHERE customer_id = core.current_customer_id())
        )
        OR core.is_staff()
    );

-- ---------- Group 3: Staff/admin-only operational tables ----------
CREATE POLICY staff_only_read ON core.customer_applications FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.kyc_reviews FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.fraud_rules FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.fraud_alerts FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.fraud_alert_reviews FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.approval_workflows FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.approval_requests FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.approval_decisions FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.gl_accounts FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.transaction_channels FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.transaction_reversals FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.loan_status_history FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.term_deposit_status_history FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.card_status_history FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.account_status_history FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.account_limits FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.account_product_versions FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.loan_product_versions FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.interest_policies FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.interest_policy_versions FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.reference_formats FOR SELECT USING (core.is_staff());
CREATE POLICY staff_only_read ON core.notification_templates FOR SELECT USING (core.is_staff());

-- (core.notifications already has its own customer_self_or_staff policy
-- defined in Group 2 above — no additional policy needed here.)

-- ---------- Group 4: Admin-only tables (organization & configuration) ----------
CREATE POLICY admin_only_read ON core.roles FOR SELECT USING (core.is_staff());
CREATE POLICY admin_only_read ON core.permissions FOR SELECT USING (core.is_admin());
CREATE POLICY admin_only_read ON core.role_permissions FOR SELECT USING (core.is_admin());
CREATE POLICY admin_only_read ON core.bank_settings FOR SELECT USING (core.is_staff());
CREATE POLICY admin_only_read ON core.business_date FOR SELECT USING (core.is_staff());
CREATE POLICY admin_only_read ON core.system_policies FOR SELECT USING (core.is_admin());
CREATE POLICY admin_only_read ON core.scheduled_jobs FOR SELECT USING (core.is_admin());
CREATE POLICY admin_only_read ON core.job_execution_log FOR SELECT USING (core.is_admin());
CREATE POLICY admin_only_read ON core.eod_runs FOR SELECT USING (core.is_admin());
CREATE POLICY admin_only_read ON core.eod_step_log FOR SELECT USING (core.is_admin());
CREATE POLICY admin_only_read ON core.audit_logs FOR SELECT USING (core.is_admin());
CREATE POLICY admin_only_read ON core.delegations FOR SELECT USING (core.is_staff());

CREATE POLICY employee_self_or_admin ON core.employees FOR SELECT
    USING (auth_subject_id = core.current_auth_subject_id() OR core.is_admin());
CREATE POLICY employee_self_or_admin ON core.employee_roles FOR SELECT
    USING (employee_id = core.current_employee_id() OR core.is_admin());
CREATE POLICY employee_self_or_admin ON core.employee_branch_assignments FOR SELECT
    USING (employee_id = core.current_employee_id() OR core.is_admin());

-- core.card_pin_hashes: NO SELECT policy for any web_* role, ever.
-- It remains fully inaccessible except to SECURITY DEFINER functions
-- (owned by the table owner, which bypasses RLS) that set/verify a PIN
-- without ever returning its value.

-- =====================================================================
-- GRANTS — table-level SELECT privilege (RLS policies above still
-- filter rows; this grant only makes the columns visible AT ALL)
-- =====================================================================

GRANT SELECT ON
    core.customers, core.customer_addresses, core.customer_relationships,
    core.account_holders, core.accounts, core.account_nominees,
    core.loans, core.loan_applications, core.loan_repayment_schedule, core.loan_repayments,
    core.term_deposits, core.recurring_deposits, core.recurring_deposit_installments,
    core.cards, core.card_transactions_sim, core.notifications,
    core.kyc_cases, core.kyc_documents, core.kyc_status_history,
    core.journal_entries, core.transactions
TO authenticated;

GRANT SELECT ON
    core.customer_applications, core.kyc_reviews, core.fraud_rules, core.fraud_alerts,
    core.fraud_alert_reviews, core.approval_workflows, core.approval_requests,
    core.approval_decisions, core.gl_accounts, core.transaction_channels,
    core.transaction_reversals, core.loan_status_history, core.term_deposit_status_history,
    core.card_status_history, core.account_status_history, core.account_limits,
    core.account_product_versions, core.loan_product_versions, core.interest_policies,
    core.interest_policy_versions, core.reference_formats, core.notification_templates,
    core.roles, core.bank_settings, core.business_date, core.delegations
TO authenticated;

GRANT SELECT ON
    core.permissions, core.role_permissions, core.system_policies,
    core.scheduled_jobs, core.job_execution_log, core.eod_runs, core.eod_step_log,
    core.audit_logs
TO authenticated;

GRANT SELECT ON core.employees, core.employee_roles, core.employee_branch_assignments
    TO authenticated;

-- No INSERT/UPDATE/DELETE grants are given to any web_* role on any
-- core table. All writes happen through SECURITY DEFINER functions in
-- the "api" schema (built out in Step 9/backend), which run as the
-- table owner and therefore bypass RLS by design, while enforcing their
-- own explicit business-rule checks in code.

-- =====================================================================
-- END OF 11_roles_and_rls.sql
-- =====================================================================
