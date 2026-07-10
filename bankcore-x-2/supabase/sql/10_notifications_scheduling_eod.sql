-- =====================================================================
-- BANKCORE X — 10_notifications_scheduling_eod.sql
-- Notification engine, Scheduled Jobs engine, End-of-Day (EOD) engine.
-- Depends on: 01_schema.sql, 03_customer_kyc.sql
-- =====================================================================

-- =====================================================================
-- NOTIFICATION ENGINE
-- =====================================================================

CREATE TABLE core.notification_templates (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_code             TEXT NOT NULL UNIQUE,
    channel                     TEXT NOT NULL CHECK (channel IN ('EMAIL', 'SMS_SIM', 'IN_APP')),
    subject_template               TEXT,
    body_template                     TEXT NOT NULL,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                            UUID NOT NULL REFERENCES core.employees(id)
);

CREATE TABLE core.notifications (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id                UUID REFERENCES core.notification_templates(id),
    recipient_customer_id         UUID REFERENCES core.customers(id),
    recipient_employee_id            UUID REFERENCES core.employees(id),
    channel                            TEXT NOT NULL CHECK (channel IN ('EMAIL', 'SMS_SIM', 'IN_APP')),
    subject                               TEXT,
    body                                    TEXT NOT NULL,
    status                                    TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'SENT', 'FAILED')),
    failure_reason                              TEXT,
    sent_at                                       TIMESTAMPTZ,
    created_at                                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_exactly_one_recipient CHECK (
        (recipient_customer_id IS NOT NULL AND recipient_employee_id IS NULL) OR
        (recipient_customer_id IS NULL AND recipient_employee_id IS NOT NULL)
    )
);

CREATE INDEX idx_notifications_status ON core.notifications(status);
CREATE INDEX idx_notifications_customer ON core.notifications(recipient_customer_id);
CREATE INDEX idx_notifications_employee ON core.notifications(recipient_employee_id);

COMMENT ON TABLE core.notifications IS
    'SMS_SIM means a simulated SMS record only — no real SMS gateway is
     contacted. EMAIL can be wired to a real free-tier provider (e.g.
     Resend) in the backend layer if desired (Rule #15 applies to
     payment rails; email notification is out of that scope).';

-- =====================================================================
-- SCHEDULING ENGINE
-- =====================================================================

CREATE TABLE core.scheduled_jobs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_code                  TEXT NOT NULL UNIQUE, -- e.g. 'EOD_PROCESS', 'INTEREST_ACCRUAL', 'DORMANCY_SWEEP'
    job_name                    TEXT NOT NULL,
    schedule_type                  TEXT NOT NULL CHECK (schedule_type IN ('DAILY', 'WEEKLY', 'MONTHLY', 'CRON')),
    cron_expression                   TEXT, -- used when schedule_type = 'CRON'
    status                               TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    last_run_at                            TIMESTAMPTZ,
    last_run_status                          TEXT CHECK (last_run_status IN ('SUCCESS', 'FAILED') OR last_run_status IS NULL),
    created_at                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                                   UUID NOT NULL REFERENCES core.employees(id)
);

CREATE TABLE core.job_execution_log (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id                     UUID NOT NULL REFERENCES core.scheduled_jobs(id),
    started_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at                     TIMESTAMPTZ,
    status                              TEXT NOT NULL DEFAULT 'RUNNING'
        CHECK (status IN ('RUNNING', 'SUCCESS', 'FAILED')),
    details                                JSONB NOT NULL DEFAULT '{}',
    error_message                             TEXT
);

CREATE INDEX idx_job_execution_log_job ON core.job_execution_log(job_id);
CREATE INDEX idx_job_execution_log_status ON core.job_execution_log(status);

REVOKE UPDATE, DELETE ON core.job_execution_log FROM PUBLIC;

-- =====================================================================
-- END-OF-DAY (EOD) ENGINE
-- Advances core.business_date only after all EOD steps succeed.
-- =====================================================================

CREATE TABLE core.eod_runs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_date              DATE NOT NULL UNIQUE, -- one EOD run per business date
    started_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at                     TIMESTAMPTZ,
    status                              TEXT NOT NULL DEFAULT 'IN_PROGRESS'
        CHECK (status IN ('IN_PROGRESS', 'COMPLETED', 'FAILED')),
    initiated_by                          UUID REFERENCES core.employees(id) -- NULL = fully automated run
);

CREATE TABLE core.eod_step_log (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    eod_run_id                 UUID NOT NULL REFERENCES core.eod_runs(id) ON DELETE CASCADE,
    step_name                     TEXT NOT NULL, -- e.g. 'INTEREST_ACCRUAL', 'DORMANCY_CHECK', 'LOAN_OVERDUE_MARKING', 'BUSINESS_DATE_ADVANCE'
    step_order                       INTEGER NOT NULL,
    status                              TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'RUNNING', 'SUCCESS', 'FAILED', 'SKIPPED')),
    started_at                            TIMESTAMPTZ,
    completed_at                             TIMESTAMPTZ,
    error_message                               TEXT,
    UNIQUE (eod_run_id, step_order)
);

CREATE INDEX idx_eod_step_log_run ON core.eod_step_log(eod_run_id);

REVOKE UPDATE, DELETE ON core.eod_runs FROM PUBLIC;
REVOKE UPDATE, DELETE ON core.eod_step_log FROM PUBLIC;

COMMENT ON TABLE core.eod_runs IS
    'core.business_date.current_business_date only advances once the
     BUSINESS_DATE_ADVANCE step in core.eod_step_log succeeds for the
     current run — this is what makes "business date" distinct from
     wall-clock date (Rule #19).';

-- =====================================================================
-- END OF 10_notifications_scheduling_eod.sql
-- =====================================================================
