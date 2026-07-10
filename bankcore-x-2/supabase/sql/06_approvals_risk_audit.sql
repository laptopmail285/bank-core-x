-- =====================================================================
-- BANKCORE X — 06_approvals_risk_audit.sql
-- Approval (maker-checker) engine, Risk/Fraud engine, Audit engine.
-- Depends on: 01_schema.sql, 04_accounts.sql, 05_ledger_transactions.sql
-- =====================================================================

-- =====================================================================
-- APPROVAL ENGINE (maker-checker)
-- =====================================================================

CREATE TABLE core.approval_workflows (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_code            TEXT NOT NULL UNIQUE,
    applies_to_type            TEXT NOT NULL, -- e.g. 'TRANSACTION', 'ACCOUNT_OPENING', 'LOAN_DISBURSEMENT', 'CUSTOMER_LIMIT_CHANGE'
    threshold_amount            NUMERIC(18,2), -- NULL = applies regardless of amount
    required_approval_count      INTEGER NOT NULL DEFAULT 1 CHECK (required_approval_count >= 1),
    required_role_id              UUID REFERENCES core.roles(id), -- role that may approve; NULL = any role above requester
    status                          TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at                       TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                        UUID NOT NULL REFERENCES core.employees(id)
);

CREATE TABLE core.approval_requests (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id              UUID NOT NULL REFERENCES core.approval_workflows(id),
    resource_type              TEXT NOT NULL,
    resource_id                  UUID NOT NULL,
    requested_by                  UUID NOT NULL REFERENCES core.employees(id),
    status                          TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')),
    requested_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at                        TIMESTAMPTZ
);

CREATE INDEX idx_approval_requests_status ON core.approval_requests(status);
CREATE INDEX idx_approval_requests_resource ON core.approval_requests(resource_type, resource_id);

CREATE TABLE core.approval_decisions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    approval_request_id      UUID NOT NULL REFERENCES core.approval_requests(id) ON DELETE CASCADE,
    decided_by                  UUID NOT NULL REFERENCES core.employees(id),
    decision                      TEXT NOT NULL CHECK (decision IN ('APPROVE', 'REJECT')),
    comments                        TEXT,
    decided_at                       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_approval_decisions_request ON core.approval_decisions(approval_request_id);

-- ---------------------------------------------------------------------
-- Self-approval block: a decider can never be the same employee who
-- made the original request (FAQ: "How is self-approval blocked?")
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.prevent_self_approval()
RETURNS TRIGGER AS $$
DECLARE
    v_requested_by UUID;
BEGIN
    SELECT requested_by INTO v_requested_by
    FROM core.approval_requests
    WHERE id = NEW.approval_request_id;

    IF v_requested_by = NEW.decided_by THEN
        RAISE EXCEPTION
            'Self-approval is not permitted: employee % cannot approve their own request %',
            NEW.decided_by, NEW.approval_request_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_self_approval
    BEFORE INSERT ON core.approval_decisions
    FOR EACH ROW EXECUTE FUNCTION core.prevent_self_approval();

-- =====================================================================
-- RISK / FRAUD ENGINE
-- This is a deterministic, rule-based engine (thresholds, velocity
-- checks, pattern matching on configured conditions). It is intentionally
-- NOT machine learning — see FAQ "Why is the fraud engine not called AI?"
-- The answer: transparent, auditable, explainable rules only.
-- =====================================================================

CREATE TABLE core.fraud_rules (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_code                TEXT NOT NULL UNIQUE,
    rule_name                  TEXT NOT NULL,
    rule_type                    TEXT NOT NULL CHECK (rule_type IN ('VELOCITY', 'THRESHOLD', 'PATTERN', 'GEO_MISMATCH_SIM')),
    parameters                     JSONB NOT NULL DEFAULT '{}', -- e.g. { "max_transactions_per_hour": 10, "max_amount": 200000 }
    severity                         TEXT NOT NULL CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    status                             TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at                           TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                             UUID NOT NULL REFERENCES core.employees(id)
);

COMMENT ON TABLE core.fraud_rules IS
    'Rule-based, deterministic, fully explainable. Not machine learning —
     every alert can be traced to exactly one configured rule and its
     parameters (Decision: "Why is the fraud engine not called AI?").';

CREATE TABLE core.fraud_alerts (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id                  UUID NOT NULL REFERENCES core.fraud_rules(id),
    transaction_id             UUID REFERENCES core.transactions(id),
    account_id                   UUID REFERENCES core.accounts(id),
    customer_id                    UUID REFERENCES core.customers(id),
    severity                         TEXT NOT NULL CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    status                             TEXT NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN', 'UNDER_REVIEW', 'CONFIRMED_FRAUD', 'FALSE_POSITIVE', 'DISMISSED')),
    details                               JSONB NOT NULL DEFAULT '{}',
    raised_at                              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_fraud_alerts_status ON core.fraud_alerts(status);
CREATE INDEX idx_fraud_alerts_account ON core.fraud_alerts(account_id);
CREATE INDEX idx_fraud_alerts_customer ON core.fraud_alerts(customer_id);

CREATE TABLE core.fraud_alert_reviews (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fraud_alert_id            UUID NOT NULL REFERENCES core.fraud_alerts(id) ON DELETE CASCADE,
    reviewer_id                 UUID NOT NULL REFERENCES core.employees(id),
    decision                      TEXT NOT NULL CHECK (decision IN ('CONFIRMED_FRAUD', 'FALSE_POSITIVE', 'DISMISSED', 'ESCALATED')),
    comments                        TEXT,
    reviewed_at                       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_fraud_alert_reviews_alert ON core.fraud_alert_reviews(fraud_alert_id);

-- =====================================================================
-- AUDIT ENGINE — append-only, system-wide audit trail (Rule #21)
-- =====================================================================

CREATE TABLE core.audit_logs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_employee_id        UUID REFERENCES core.employees(id),
    actor_customer_id           UUID REFERENCES core.customers(id),
    action                         TEXT NOT NULL, -- e.g. 'ACCOUNT.STATUS_CHANGE', 'EMPLOYEE.ROLE_ASSIGNED'
    resource_type                    TEXT NOT NULL,
    resource_id                        UUID,
    before_state                         JSONB,
    after_state                            JSONB,
    ip_address                               INET,
    user_agent                                 TEXT,
    created_at                                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_not_both_actors CHECK (
        NOT (actor_employee_id IS NOT NULL AND actor_customer_id IS NOT NULL)
    )
);

CREATE INDEX idx_audit_logs_resource ON core.audit_logs(resource_type, resource_id);
CREATE INDEX idx_audit_logs_actor_employee ON core.audit_logs(actor_employee_id);
CREATE INDEX idx_audit_logs_created_at ON core.audit_logs(created_at);

COMMENT ON TABLE core.audit_logs IS
    'APPEND-ONLY system-wide audit trail. NULL actor_employee_id AND
     NULL actor_customer_id together mean a system/scheduled-job action
     (e.g. EOD, dormancy sweep).';

REVOKE UPDATE, DELETE ON core.audit_logs FROM PUBLIC;

-- =====================================================================
-- END OF 06_approvals_risk_audit.sql
-- =====================================================================
