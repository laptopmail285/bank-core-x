// src/index.js
require('express-async-errors'); // must be required before routes are set up
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');

const config = require('./config');
const errorHandler = require('./middleware/errorHandler');
const onboardingRoutes = require('./routes/onboarding');
const kycRoutes = require('./routes/kyc');
const { ensureBucketsExist } = require('./services/supabaseStorage');
const { scheduleEodJob } = require('./jobs/eodJob');
const { pool } = require('./db');

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan(config.nodeEnv === 'development' ? 'dev' : 'combined'));

app.get('/health', async (req, res) => {
    try {
        await pool.query('SELECT 1');
        res.json({ status: 'ok', database: 'connected' });
    } catch (err) {
        res.status(503).json({ status: 'error', database: 'unreachable' });
    }
});

app.use('/onboarding', onboardingRoutes);
app.use('/kyc', kycRoutes);

app.use((req, res) => {
    res.status(404).json({ error: 'Not found' });
});

app.use(errorHandler);

async function start() {
    try {
        await ensureBucketsExist();
    } catch (err) {
        // eslint-disable-next-line no-console
        console.error('WARNING: could not verify/create Supabase Storage buckets at startup:', err.message);
        // eslint-disable-next-line no-console
        console.error('The server will still start — retry once Supabase is reachable.');
    }

    scheduleEodJob();

    app.listen(config.port, () => {
        // eslint-disable-next-line no-console
        console.log(`BankCore X backend listening on port ${config.port} (${config.nodeEnv})`);
    });
}

start();
