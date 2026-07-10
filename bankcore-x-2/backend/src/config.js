// src/config.js
// Loads and validates environment variables. Fails fast at startup
// (rather than failing confusingly later) if anything required is missing.
require('dotenv').config();

const required = [
    'DATABASE_URL',
    'SUPABASE_URL',
    'SUPABASE_SERVICE_ROLE_KEY',
];

const missing = required.filter((key) => !process.env[key]);
if (missing.length > 0) {
    // eslint-disable-next-line no-console
    console.error(`FATAL: missing required environment variables: ${missing.join(', ')}`);
    process.exit(1);
}

module.exports = {
    port: parseInt(process.env.BACKEND_PORT || '3001', 10),
    nodeEnv: process.env.NODE_ENV || 'development',

    databaseUrl: process.env.DATABASE_URL,

    supabase: {
        url: process.env.SUPABASE_URL,
        // SECRET — server-side only, never ships to any frontend. This is
        // the key that lets this backend call supabase.auth.admin.* and
        // bypass Storage RLS. Rotate immediately if it ever leaks.
        serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
    },

    storage: {
        buckets: {
            kyc: process.env.STORAGE_BUCKET_KYC || 'kyc-documents',
            statements: process.env.STORAGE_BUCKET_STATEMENTS || 'statements',
        },
    },
};
