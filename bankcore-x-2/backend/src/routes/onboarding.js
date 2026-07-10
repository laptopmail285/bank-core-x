// src/routes/onboarding.js
// Orchestrates the one thing PostgREST RPC functions can't cleanly do
// alone: creating a Supabase Auth login AND the matching Postgres row as
// one logical operation, with compensation if either half fails.
const express = require('express');
const crypto = require('crypto');
const { withTransaction } = require('./../db');
const { createAuthUser, deleteAuthUser } = require('./../services/supabaseAdmin');
const { requireAuth, requireRole } = require('./../middleware/auth');

const router = express.Router();

function generateTempPassword() {
    return crypto.randomBytes(9).toString('base64url');
}

/**
 * POST /onboarding/employees
 * Admin-only. Creates a Supabase Auth login + core.employees row + role
 * assignment(s) as one logical operation.
 *
 * appRole tagged on the Auth user is the coarse tier this backend's own
 * requireRole() checks — 'web_admin' if SYSTEM_ADMIN is among the
 * assigned roleCodes, otherwise 'web_staff'. Fine-grained permissions
 * still come from core.employee_roles/core.role_permissions as before;
 * this only decides which portal-level routes the account can hit.
 */
router.post('/employees', requireAuth, requireRole('web_admin'), async (req, res) => {
    const { employeeCode, fullName, email, phone, branchId, roleCodes } = req.body;

    if (!employeeCode || !fullName || !email || !branchId || !Array.isArray(roleCodes) || roleCodes.length === 0) {
        return res.status(400).json({
            error: 'employeeCode, fullName, email, branchId, and a non-empty roleCodes array are required',
        });
    }

    const tempPassword = generateTempPassword();
    const appRole = roleCodes.includes('SYSTEM_ADMIN') ? 'web_admin' : 'web_staff';

    const authUserId = await createAuthUser({ email, temporaryPassword: tempPassword, appRole });

    try {
        const employee = await withTransaction(async (client) => {
            const empResult = await client.query(
                `INSERT INTO core.employees (employee_code, auth_subject_id, full_name, email, phone, primary_branch_id, status)
                 VALUES ($1, $2, $3, $4, $5, $6, 'ACTIVE')
                 RETURNING id`,
                [employeeCode, authUserId, fullName, email, phone || null, branchId]
            );
            const employeeId = empResult.rows[0].id;

            for (const roleCode of roleCodes) {
                // eslint-disable-next-line no-await-in-loop
                await client.query(
                    `INSERT INTO core.employee_roles (employee_id, role_id, assigned_by)
                     SELECT $1, id, $2 FROM core.roles WHERE role_code = $3`,
                    [employeeId, req.user.sub, roleCode]
                );
            }

            return { id: employeeId, employeeCode, email };
        });

        res.status(201).json({
            employee,
            temporaryPassword: tempPassword,
            note: 'Share this temporary password with the employee through a secure channel. It will not be shown again.',
        });
    } catch (dbErr) {
        await deleteAuthUser(authUserId);
        throw dbErr;
    }
});

/**
 * POST /onboarding/customers
 * Staff/admin-only (branch-assisted onboarding path). Creates a Supabase
 * Auth login + core.customer_applications + core.customers as one
 * logical operation, pre-approved since staff has already vetted the
 * customer in person.
 */
router.post('/customers', requireAuth, requireRole('web_staff', 'web_admin'), async (req, res) => {
    const { fullName, dateOfBirth, email, phone, branchId } = req.body;

    if (!fullName || !dateOfBirth || !email || !phone || !branchId) {
        return res.status(400).json({
            error: 'fullName, dateOfBirth, email, phone, and branchId are required',
        });
    }

    const tempPassword = generateTempPassword();

    const authUserId = await createAuthUser({ email, temporaryPassword: tempPassword, appRole: 'web_customer' });

    try {
        const customer = await withTransaction(async (client) => {
            const employeeResult = await client.query(
                'SELECT id FROM core.employees WHERE auth_subject_id = $1',
                [req.user.sub]
            );
            const initiatingEmployeeId = employeeResult.rows[0]?.id || null;

            const appResult = await client.query(
                `INSERT INTO core.customer_applications
                    (application_reference, initiated_channel, initiating_employee_id, branch_id,
                     full_name, date_of_birth, email, phone, status, decided_at, decided_by)
                 VALUES
                    ($1, 'BRANCH_EMPLOYEE', $2, $3, $4, $5, $6, $7, 'APPROVED', now(), $2)
                 RETURNING id`,
                [
                    `APP-${Date.now()}`,
                    initiatingEmployeeId,
                    branchId,
                    fullName,
                    dateOfBirth,
                    email,
                    phone,
                ]
            );
            const applicationId = appResult.rows[0].id;

            const custResult = await client.query(
                `INSERT INTO core.customers
                    (customer_reference, application_id, auth_subject_id, full_name,
                     date_of_birth, email, phone, onboarded_branch_id)
                 VALUES
                    ($1, $2, $3, $4, $5, $6, $7, $8)
                 RETURNING id`,
                [
                    `CUS-${Date.now()}`,
                    applicationId,
                    authUserId,
                    fullName,
                    dateOfBirth,
                    email,
                    phone,
                    branchId,
                ]
            );

            return { id: custResult.rows[0].id, fullName, email };
        });

        res.status(201).json({
            customer,
            temporaryPassword: tempPassword,
            note: 'Share this temporary password with the customer through a secure channel. It will not be shown again.',
        });
    } catch (dbErr) {
        await deleteAuthUser(authUserId);
        throw dbErr;
    }
});

module.exports = router;
