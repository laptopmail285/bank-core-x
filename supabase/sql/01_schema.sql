-- =====================================================================
-- BANKCORE X — 01_schema.sql
-- Foundation: extensions, schemas, Configuration + Organization/Access
-- =====================================================================
-- SCHEMA STRATEGY:
--   core  -> real tables, RLS-protected, NEVER exposed directly to PostgREST
--   api   -> views + functions only, exposed to PostgREST (built in Step 7)
-- This means the frontend can never bypass business logic by writing
-- straight to a table — it can only call what "api" explicitly allows.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS api;

-- ---------------------------------------------------------------------
-- Reusable trigger function: auto-maintain updated_at on every UPDATE
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- CONFIGURATION LAYER
-- =====================================================================

-- ---------------------------------------------------------------------
-- core.bank_settings — singleton row describing the one configured bank
-- ---------------------------------------------------------------------
CREATE TABLE core.bank_settings (
    id                  SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1), -- enforces singleton
    bank_name           TEXT NOT NULL,
    bank_code           TEXT NOT NULL UNIQUE,
    swift_like_code     TEXT,
    base_currency       TEXT NOT NULL DEFAULT 'INR',
    timezone            TEXT NOT NULL DEFAULT 'Asia/Kolkata',
    registered_address  TEXT,
    support_email       TEXT,
    support_phone       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by          UUID -- references core.employees(id), added via FK after that table exists
);

CREATE TRIGGER trg_bank_settings_updated_at
    BEFORE UPDATE ON core.bank_settings
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- ---------------------------------------------------------------------
-- core.business_date — singleton row tracking the bank business date
-- (distinct from wall-clock timestamps — see Non-Negotiable Rule #19)
-- ---------------------------------------------------------------------
CREATE TABLE core.business_date (
    id                          SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    current_business_date      DATE NOT NULL,
    previous_business_date     DATE,
    is_eod_in_progress         BOOLEAN NOT NULL DEFAULT FALSE,
    last_eod_started_at        TIMESTAMPTZ,
    last_eod_completed_at      TIMESTAMPTZ,
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_business_date_updated_at
    BEFORE UPDATE ON core.business_date
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- ---------------------------------------------------------------------
-- core.reference_formats — configurable readable-reference generators
-- (Rule #3: UUIDs are internal keys; readable references are separate)
-- ---------------------------------------------------------------------
CREATE TABLE core.reference_formats (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type         TEXT NOT NULL UNIQUE, -- e.g. 'ACCOUNT', 'TRANSACTION', 'LOAN', 'CARD', 'FD', 'CUSTOMER'
    prefix              TEXT NOT NULL,
    next_sequence       BIGINT NOT NULL DEFAULT 1,
    sequence_padding    INTEGER NOT NULL DEFAULT 8,
    format_pattern      TEXT NOT NULL DEFAULT '{prefix}{sequence}', -- supports {prefix}, {sequence}, {yyyy}, {branch_code}
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_reference_formats_updated_at
    BEFORE UPDATE ON core.reference_formats
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- ---------------------------------------------------------------------
-- core.system_policies — generic key/value configuration store
-- ---------------------------------------------------------------------
CREATE TABLE core.system_policies (
    policy_key          TEXT PRIMARY KEY,
    policy_value        JSONB NOT NULL,
    description         TEXT,
    updated_by          UUID, -- references core.employees(id), FK added later
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_system_policies_updated_at
    BEFORE UPDATE ON core.system_policies
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

-- =====================================================================
-- ORGANIZATION AND ACCESS LAYER
-- =====================================================================

-- ---------------------------------------------------------------------
-- core.branches
-- ---------------------------------------------------------------------
CREATE TABLE core.branches (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_code         TEXT NOT NULL UNIQUE,
    branch_name         TEXT NOT NULL,
    address_line1       TEXT NOT NULL,
    address_line2       TEXT,
    city                TEXT NOT NULL,
    state               TEXT NOT NULL,
    pincode             TEXT NOT NULL,
    phone               TEXT,
    email               TEXT,
    is_head_office      BOOLEAN NOT NULL DEFAULT FALSE,
    status              TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    opened_date         DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_branches_updated_at
    BEFORE UPDATE ON core.branches
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

CREATE INDEX idx_branches_status ON core.branches(status);

-- ---------------------------------------------------------------------
-- core.roles — fixed initial set per Phase 2 of the plan, extensible
-- ---------------------------------------------------------------------
CREATE TABLE core.roles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_code           TEXT NOT NULL UNIQUE,
    role_name           TEXT NOT NULL,
    description         TEXT,
    is_system_role      BOOLEAN NOT NULL DEFAULT TRUE, -- system roles cannot be deleted, only deactivated
    status              TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- core.permissions — granular permission codes, module-grouped
-- ---------------------------------------------------------------------
CREATE TABLE core.permissions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    permission_code     TEXT NOT NULL UNIQUE, -- e.g. 'ACCOUNT.CREATE', 'TRANSACTION.APPROVE'
    module              TEXT NOT NULL,        -- e.g. 'ACCOUNT', 'TRANSACTION', 'LOAN'
    description         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_permissions_module ON core.permissions(module);

-- ---------------------------------------------------------------------
-- core.role_permissions — role <-> permission matrix
-- ---------------------------------------------------------------------
CREATE TABLE core.role_permissions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id             UUID NOT NULL REFERENCES core.roles(id) ON DELETE CASCADE,
    permission_id       UUID NOT NULL REFERENCES core.permissions(id) ON DELETE CASCADE,
    granted_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (role_id, permission_id)
);

CREATE INDEX idx_role_permissions_role ON core.role_permissions(role_id);
CREATE INDEX idx_role_permissions_permission ON core.role_permissions(permission_id);

-- ---------------------------------------------------------------------
-- core.employees — staff identities, linked to Supabase Auth by auth_subject_id
-- ---------------------------------------------------------------------
CREATE TABLE core.employees (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_code       TEXT NOT NULL UNIQUE,
    auth_subject_id     UUID UNIQUE, -- Supabase Auth "sub" claim; nullable until account is provisioned
    full_name           TEXT NOT NULL,
    email               TEXT NOT NULL UNIQUE,
    phone               TEXT,
    primary_branch_id   UUID NOT NULL REFERENCES core.branches(id),
    status              TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'TERMINATED')),
    hire_date           DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_employees_updated_at
    BEFORE UPDATE ON core.employees
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

CREATE INDEX idx_employees_branch ON core.employees(primary_branch_id);
CREATE INDEX idx_employees_status ON core.employees(status);

-- Now that core.employees exists, attach the deferred FKs from Configuration layer
ALTER TABLE core.bank_settings
    ADD CONSTRAINT fk_bank_settings_updated_by
    FOREIGN KEY (updated_by) REFERENCES core.employees(id);

ALTER TABLE core.system_policies
    ADD CONSTRAINT fk_system_policies_updated_by
    FOREIGN KEY (updated_by) REFERENCES core.employees(id);

-- ---------------------------------------------------------------------
-- core.employee_roles — many-to-many, employee <-> role
-- ---------------------------------------------------------------------
CREATE TABLE core.employee_roles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id         UUID NOT NULL REFERENCES core.employees(id) ON DELETE CASCADE,
    role_id             UUID NOT NULL REFERENCES core.roles(id) ON DELETE CASCADE,
    assigned_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    assigned_by         UUID REFERENCES core.employees(id),
    UNIQUE (employee_id, role_id)
);

CREATE INDEX idx_employee_roles_employee ON core.employee_roles(employee_id);
CREATE INDEX idx_employee_roles_role ON core.employee_roles(role_id);

-- ---------------------------------------------------------------------
-- core.employee_branch_assignments — which branches an employee can act in
-- ---------------------------------------------------------------------
CREATE TABLE core.employee_branch_assignments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id         UUID NOT NULL REFERENCES core.employees(id) ON DELETE CASCADE,
    branch_id           UUID NOT NULL REFERENCES core.branches(id) ON DELETE CASCADE,
    is_primary          BOOLEAN NOT NULL DEFAULT FALSE,
    assigned_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (employee_id, branch_id)
);

CREATE INDEX idx_branch_assignments_employee ON core.employee_branch_assignments(employee_id);
CREATE INDEX idx_branch_assignments_branch ON core.employee_branch_assignments(branch_id);

-- ---------------------------------------------------------------------
-- core.delegations — temporary authority handover between employees
-- ---------------------------------------------------------------------
CREATE TABLE core.delegations (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    delegator_employee_id   UUID NOT NULL REFERENCES core.employees(id),
    delegate_employee_id    UUID NOT NULL REFERENCES core.employees(id),
    role_id                 UUID NOT NULL REFERENCES core.roles(id),
    valid_from              TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until             TIMESTAMPTZ NOT NULL,
    reason                  TEXT NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'REVOKED', 'EXPIRED')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by              UUID NOT NULL REFERENCES core.employees(id),
    CONSTRAINT chk_delegation_not_self CHECK (delegator_employee_id <> delegate_employee_id),
    CONSTRAINT chk_delegation_valid_period CHECK (valid_until > valid_from)
);

CREATE INDEX idx_delegations_delegate ON core.delegations(delegate_employee_id);
CREATE INDEX idx_delegations_status ON core.delegations(status);

-- =====================================================================
-- BOOTSTRAP DATA
-- Per project data policy: exactly one bootstrap admin/config record
-- may be seeded. Everything else is created through application workflows.
-- =====================================================================

-- Seed the fixed initial role set (roles are configuration, not "data")
INSERT INTO core.roles (role_code, role_name, description, is_system_role) VALUES
    ('SYSTEM_ADMIN',    'System Administrator', 'Full organizational and configuration access', TRUE),
    ('BRANCH_MANAGER',  'Branch Manager',       'Manages a single branch, approves escalations', TRUE),
    ('TELLER',          'Teller',               'Front-line customer transaction processing', TRUE),
    ('LOAN_OFFICER',    'Loan Officer',         'Processes and assesses loan applications', TRUE),
    ('KYC_REVIEWER',    'KYC Reviewer',         'Reviews KYC documents and cases', TRUE),
    ('FRAUD_REVIEWER',  'Fraud Reviewer',       'Reviews fraud/risk alerts', TRUE),
    ('AUDITOR',         'Auditor',              'Read-only access to audit trails and reports', TRUE),
    ('CUSTOMER',        'Customer',             'End customer, self-service portal only', TRUE);

-- Seed a head office branch (technically required bootstrap record —
-- an employee cannot exist without a branch, and the system needs at
-- least one branch to exist before any onboarding can happen)
INSERT INTO core.branches (branch_code, branch_name, address_line1, city, state, pincode, is_head_office)
VALUES ('HO001', 'Head Office', 'To be configured by administrator', 'To be configured', 'To be configured', '000000', TRUE);

-- Seed business_date as today (required for any transaction to be dated)
INSERT INTO core.business_date (current_business_date) VALUES (CURRENT_DATE);

-- Seed reference formats for entities that will be created in later steps
INSERT INTO core.reference_formats (entity_type, prefix, sequence_padding, format_pattern) VALUES
    ('CUSTOMER',    'CUS', 8, '{prefix}{sequence}'),
    ('ACCOUNT',     'ACC', 10, '{prefix}{sequence}'),
    ('TRANSACTION', 'TXN', 12, '{prefix}{sequence}'),
    ('LOAN',        'LN',  8, '{prefix}{sequence}'),
    ('FD',          'FD',  8, '{prefix}{sequence}'),
    ('RD',          'RD',  8, '{prefix}{sequence}'),
    ('CARD',        'CRD', 8, '{prefix}{sequence}');

-- =====================================================================
-- END OF 01_schema.sql
-- =====================================================================
