-- =====================================================================
-- BANKCORE X — 03_customer_kyc.sql
-- Customer & KYC domain: applications, customers, addresses,
-- relationships, KYC cases/documents/reviews/status history.
-- Depends on: 01_schema.sql (core.employees, core.branches)
-- =====================================================================

-- ---------------------------------------------------------------------
-- core.customer_applications — pre-customer application record
-- (Decision #2: Customer + Employee initiated onboarding)
-- ---------------------------------------------------------------------
CREATE TABLE core.customer_applications (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_reference   TEXT NOT NULL UNIQUE,
    initiated_channel       TEXT NOT NULL CHECK (initiated_channel IN ('ONLINE_SELF', 'BRANCH_EMPLOYEE')),
    initiating_employee_id  UUID REFERENCES core.employees(id), -- NULL if online self-initiated
    branch_id               UUID REFERENCES core.branches(id),  -- NULL if online self-initiated
    full_name               TEXT NOT NULL,
    date_of_birth           DATE NOT NULL,
    email                   TEXT NOT NULL,
    phone                   TEXT NOT NULL,
    is_minor                BOOLEAN NOT NULL DEFAULT FALSE,
    status                  TEXT NOT NULL DEFAULT 'SUBMITTED'
        CHECK (status IN ('SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'WITHDRAWN')),
    rejection_reason        TEXT,
    submitted_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at              TIMESTAMPTZ,
    decided_by              UUID REFERENCES core.employees(id),
    CONSTRAINT chk_branch_required_for_employee_channel
        CHECK (initiated_channel = 'ONLINE_SELF' OR (branch_id IS NOT NULL AND initiating_employee_id IS NOT NULL))
);

CREATE INDEX idx_customer_applications_status ON core.customer_applications(status);

-- ---------------------------------------------------------------------
-- core.customers — the actual customer master record (post-approval)
-- ---------------------------------------------------------------------
CREATE TABLE core.customers (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_reference      TEXT NOT NULL UNIQUE, -- readable ref, generated via core.reference_formats
    application_id          UUID REFERENCES core.customer_applications(id),
    auth_subject_id         UUID UNIQUE, -- Supabase Auth "sub" claim for customer portal login
    full_name               TEXT NOT NULL,
    date_of_birth           DATE NOT NULL,
    email                   TEXT NOT NULL UNIQUE,
    phone                   TEXT NOT NULL UNIQUE,
    is_minor                BOOLEAN NOT NULL DEFAULT FALSE,
    kyc_status              TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (kyc_status IN ('PENDING', 'IN_REVIEW', 'VERIFIED', 'REJECTED')),
    status                  TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'DORMANT', 'SUSPENDED', 'CLOSED')),
    onboarded_branch_id     UUID REFERENCES core.branches(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_minor_dob CHECK (
        (is_minor = FALSE) OR (date_of_birth > (CURRENT_DATE - INTERVAL '18 years'))
    )
);

CREATE TRIGGER trg_customers_updated_at
    BEFORE UPDATE ON core.customers
    FOR EACH ROW EXECUTE FUNCTION core.set_updated_at();

CREATE INDEX idx_customers_kyc_status ON core.customers(kyc_status);
CREATE INDEX idx_customers_status ON core.customers(status);

COMMENT ON COLUMN core.customers.date_of_birth IS
    'No claim of real Aadhaar/PAN verification is made anywhere in this system (Rule #13).';

-- ---------------------------------------------------------------------
-- core.customer_addresses
-- ---------------------------------------------------------------------
CREATE TABLE core.customer_addresses (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id             UUID NOT NULL REFERENCES core.customers(id) ON DELETE CASCADE,
    address_type            TEXT NOT NULL CHECK (address_type IN ('RESIDENTIAL', 'PERMANENT', 'MAILING')),
    address_line1           TEXT NOT NULL,
    address_line2           TEXT,
    city                    TEXT NOT NULL,
    state                   TEXT NOT NULL,
    pincode                 TEXT NOT NULL,
    country                 TEXT NOT NULL DEFAULT 'India',
    is_current              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_customer_addresses_customer ON core.customer_addresses(customer_id);

-- ---------------------------------------------------------------------
-- core.customer_relationships — e.g. guardian-of-minor, joint holders
-- linkage metadata (the actual account-level joint ownership lives in
-- the Accounts domain; this table models the customer-to-customer
-- relationship itself, reusable across products)
-- ---------------------------------------------------------------------
CREATE TABLE core.customer_relationships (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id             UUID NOT NULL REFERENCES core.customers(id) ON DELETE CASCADE,
    related_customer_id     UUID NOT NULL REFERENCES core.customers(id),
    relationship_type       TEXT NOT NULL CHECK (relationship_type IN ('GUARDIAN_OF_MINOR', 'JOINT_APPLICANT', 'NOMINEE')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_relationship_not_self CHECK (customer_id <> related_customer_id)
);

CREATE INDEX idx_customer_relationships_customer ON core.customer_relationships(customer_id);
CREATE INDEX idx_customer_relationships_related ON core.customer_relationships(related_customer_id);

-- ---------------------------------------------------------------------
-- core.kyc_cases — one case per customer, tracks the review lifecycle
-- ---------------------------------------------------------------------
CREATE TABLE core.kyc_cases (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id             UUID NOT NULL REFERENCES core.customers(id) ON DELETE CASCADE,
    case_status             TEXT NOT NULL DEFAULT 'OPEN'
        CHECK (case_status IN ('OPEN', 'DOCUMENTS_SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'RESUBMISSION_REQUIRED')),
    assigned_reviewer_id    UUID REFERENCES core.employees(id),
    opened_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at               TIMESTAMPTZ,
    CONSTRAINT chk_kyc_case_closed_status CHECK (
        (closed_at IS NULL) OR (case_status IN ('APPROVED', 'REJECTED'))
    )
);

CREATE INDEX idx_kyc_cases_customer ON core.kyc_cases(customer_id);
CREATE INDEX idx_kyc_cases_status ON core.kyc_cases(case_status);
CREATE INDEX idx_kyc_cases_reviewer ON core.kyc_cases(assigned_reviewer_id);

-- ---------------------------------------------------------------------
-- core.kyc_documents — document metadata; the actual file lives in
-- Supabase Storage, this table stores only the storage reference
-- ---------------------------------------------------------------------
CREATE TABLE core.kyc_documents (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kyc_case_id             UUID NOT NULL REFERENCES core.kyc_cases(id) ON DELETE CASCADE,
    document_type           TEXT NOT NULL CHECK (document_type IN ('ID_PROOF', 'ADDRESS_PROOF', 'PHOTO', 'SIGNATURE', 'OTHER')),
    storage_bucket          TEXT NOT NULL,
    storage_object_key      TEXT NOT NULL,
    original_filename       TEXT NOT NULL,
    uploaded_by_customer    BOOLEAN NOT NULL DEFAULT TRUE, -- FALSE if uploaded by employee on customer's behalf
    uploaded_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    status                  TEXT NOT NULL DEFAULT 'SUBMITTED'
        CHECK (status IN ('SUBMITTED', 'ACCEPTED', 'REJECTED')),
    rejection_reason        TEXT
);

CREATE INDEX idx_kyc_documents_case ON core.kyc_documents(kyc_case_id);

COMMENT ON TABLE core.kyc_documents IS
    'This is document-based KYC review only. No claim of real Aadhaar/PAN
     verification is made anywhere in this system (Rule #13).';

-- ---------------------------------------------------------------------
-- core.kyc_reviews — individual reviewer decisions on a case
-- ---------------------------------------------------------------------
CREATE TABLE core.kyc_reviews (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kyc_case_id             UUID NOT NULL REFERENCES core.kyc_cases(id) ON DELETE CASCADE,
    reviewer_id             UUID NOT NULL REFERENCES core.employees(id),
    decision                TEXT NOT NULL CHECK (decision IN ('APPROVE', 'REJECT', 'REQUEST_RESUBMISSION')),
    comments                TEXT,
    reviewed_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_kyc_reviews_case ON core.kyc_reviews(kyc_case_id);

-- ---------------------------------------------------------------------
-- core.kyc_status_history — append-oriented status trail (Rule #21)
-- ---------------------------------------------------------------------
CREATE TABLE core.kyc_status_history (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kyc_case_id             UUID NOT NULL REFERENCES core.kyc_cases(id) ON DELETE CASCADE,
    previous_status         TEXT,
    new_status              TEXT NOT NULL,
    changed_by              UUID REFERENCES core.employees(id), -- NULL if system-driven transition
    reason                  TEXT,
    changed_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_kyc_status_history_case ON core.kyc_status_history(kyc_case_id);

-- No UPDATE/DELETE allowed on the append-oriented history table
REVOKE UPDATE, DELETE ON core.kyc_status_history FROM PUBLIC;

-- =====================================================================
-- END OF 03_customer_kyc.sql
-- =====================================================================
