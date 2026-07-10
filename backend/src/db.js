// src/db.js
// Direct Postgres connection for the backend service. This connection
// uses the migration/owner role (POSTGRES_USER) and therefore bypasses
// RLS — appropriate ONLY because this is a trusted, server-side-only
// component that is never exposed to end users directly (see Rule #11:
// no service-role/superuser key ever ships in FRONTEND code — this is
// backend code, not frontend code, and this key never leaves the server).
const { Pool } = require('pg');
const config = require('./config');

const pool = new Pool({
    connectionString: config.databaseUrl,
    max: 10,
    idleTimeoutMillis: 30000,
});

pool.on('error', (err) => {
    // eslint-disable-next-line no-console
    console.error('Unexpected Postgres pool error:', err);
});

async function query(text, params) {
    return pool.query(text, params);
}

/**
 * Run multiple statements inside a single DB transaction.
 * `fn` receives a client and must use it for all queries.
 */
async function withTransaction(fn) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const result = await fn(client);
        await client.query('COMMIT');
        return result;
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

module.exports = { pool, query, withTransaction };
