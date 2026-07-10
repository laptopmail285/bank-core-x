// src/jobs/eodJob.js
// Runs core.run_eod() on a schedule. Uses the backend's direct DB
// connection (trusted, server-side, elevated) rather than going through
// PostgREST — this is a system job, not a user-initiated action.
const cron = require('node-cron');
const { query } = require('./../db');

function scheduleEodJob() {
    // Runs at 23:55 every day (server time). Adjust the cron expression
    // to match core.bank_settings.timezone if it differs from the host.
    cron.schedule('55 23 * * *', async () => {
        // eslint-disable-next-line no-console
        console.log(`[EOD] Starting scheduled EOD run at ${new Date().toISOString()}`);
        try {
            const result = await query('SELECT * FROM core.run_eod(NULL)');
            // eslint-disable-next-line no-console
            console.log('[EOD] Completed:', result.rows[0]);
        } catch (err) {
            // eslint-disable-next-line no-console
            console.error('[EOD] FAILED:', err.message);
        }
    });

    // eslint-disable-next-line no-console
    console.log('[EOD] Scheduled job registered: daily at 23:55');
}

module.exports = { scheduleEodJob };
