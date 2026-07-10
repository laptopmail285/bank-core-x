-- =====================================================================
-- BANKCORE X — 14_admin_views.sql
-- Additional read views for the Admin Panel (Step 10).
-- Depends on: 11_roles_and_rls.sql, 12_api_layer.sql
-- =====================================================================

CREATE VIEW api.all_customers WITH (security_invoker = true) AS
    SELECT id, customer_reference, full_name, email, phone, kyc_status, status, created_at
    FROM core.customers;

CREATE VIEW api.pending_approvals WITH (security_invoker = true) AS
    SELECT ar.id, ar.resource_type, ar.resource_id, ar.status, ar.requested_at,
           e.full_name AS requested_by_name, w.workflow_code
    FROM core.approval_requests ar
    JOIN core.employees e ON e.id = ar.requested_by
    JOIN core.approval_workflows w ON w.id = ar.workflow_id
    WHERE ar.status = 'PENDING';

CREATE VIEW api.open_fraud_alerts WITH (security_invoker = true) AS
    SELECT fa.id, fa.severity, fa.status, fa.raised_at, fr.rule_name, fa.details
    FROM core.fraud_alerts fa
    JOIN core.fraud_rules fr ON fr.id = fa.rule_id
    WHERE fa.status IN ('OPEN', 'UNDER_REVIEW');

CREATE VIEW api.all_branches WITH (security_invoker = true) AS
    SELECT id, branch_code, branch_name, city, state, status, is_head_office, opened_date
    FROM core.branches;

CREATE VIEW api.all_employees WITH (security_invoker = true) AS
    SELECT e.id, e.employee_code, e.full_name, e.email, e.status, e.hire_date,
           b.branch_name AS primary_branch_name,
           array_agg(r.role_code) FILTER (WHERE r.role_code IS NOT NULL) AS role_codes
    FROM core.employees e
    JOIN core.branches b ON b.id = e.primary_branch_id
    LEFT JOIN core.employee_roles er ON er.employee_id = e.id
    LEFT JOIN core.roles r ON r.id = er.role_id
    GROUP BY e.id, b.branch_name;

CREATE VIEW api.audit_logs WITH (security_invoker = true) AS
    SELECT id, actor_employee_id, actor_customer_id, action, resource_type,
           resource_id, before_state, after_state, created_at
    FROM core.audit_logs;

GRANT SELECT ON api.all_customers, api.pending_approvals, api.open_fraud_alerts,
    api.all_branches, api.all_employees, api.audit_logs
TO web_staff, web_admin;

-- =====================================================================
-- END OF 14_admin_views.sql
-- =====================================================================
