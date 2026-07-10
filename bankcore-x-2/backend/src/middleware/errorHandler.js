// src/middleware/errorHandler.js
// Centralized error handler. Postgres errors from db.js and any thrown
// Error reach here (via express-async-errors, which lets async route
// handlers throw without an explicit try/catch + next(err)).
// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
    // eslint-disable-next-line no-console
    console.error(err);

    // Postgres errors raised via RAISE EXCEPTION in our SQL functions
    // surface here with a human-readable `message` — pass it through.
    if (err.code && err.code.startsWith('P')) {
        return res.status(400).json({ error: err.message });
    }

    const status = err.status || 500;
    const message = status === 500 ? 'Internal server error' : err.message;
    res.status(status).json({ error: message });
}

module.exports = errorHandler;
