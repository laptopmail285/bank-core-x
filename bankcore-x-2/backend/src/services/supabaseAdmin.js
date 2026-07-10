// src/services/supabaseAdmin.js
// Wraps the Supabase Admin API (service-role key) for the operations
// this backend needs: creating an Auth user with an app_role tag, and
// deleting one for rollback. Replaces keycloakAdmin.js.
const { createClient } = require('@supabase/supabase-js');
const config = require('./../config');

const supabaseAdmin = createClient(config.supabase.url, config.supabase.serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
});

/**
 * Creates a Supabase Auth user tagged with an app_role (customer/staff/
 * admin), and returns the new user's id (the value that becomes
 * auth_subject_id in Postgres — same role this played for Keycloak's
 * user id before).
 */
async function createAuthUser({ email, temporaryPassword, appRole }) {
    const { data, error } = await supabaseAdmin.auth.admin.createUser({
        email,
        password: temporaryPassword,
        email_confirm: true, // skip email verification for staff-created accounts
        app_metadata: { app_role: appRole }, // read by core.is_staff()/is_admin() indirectly via employees table, and directly by the backend's own JWT middleware
        user_metadata: {},
    });

    if (error) throw new Error(`Failed to create Supabase Auth user: ${error.message}`);
    return data.user.id;
}

async function deleteAuthUser(userId) {
    try {
        await supabaseAdmin.auth.admin.deleteUser(userId);
    } catch (cleanupErr) {
        // eslint-disable-next-line no-console
        console.error('WARNING: failed to roll back Supabase Auth user after DB failure:', cleanupErr.message);
    }
}

module.exports = { supabaseAdmin, createAuthUser, deleteAuthUser };
