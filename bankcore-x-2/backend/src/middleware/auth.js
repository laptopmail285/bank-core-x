// src/middleware/auth.js
// Verifies incoming Supabase-issued JWTs using the project's JWKS
// endpoint (Supabase's asymmetric signing keys, default on projects
// created after mid-2025). jwks-rsa fetches and caches the public key
// directly from Supabase at runtime — same pattern this file used for
// Keycloak, just pointed at a different issuer.
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');
const config = require('./../config');

const client = jwksClient({
    jwksUri: `${config.supabase.url}/auth/v1/.well-known/jwks.json`,
    cache: true,
    cacheMaxAge: 10 * 60 * 1000,
});

function getSigningKey(header, callback) {
    client.getSigningKey(header.kid, (err, key) => {
        if (err) return callback(err);
        callback(null, key.getPublicKey());
    });
}

function requireAuth(req, res, next) {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

    if (!token) {
        return res.status(401).json({ error: 'Missing bearer token' });
    }

    jwt.verify(token, getSigningKey, { algorithms: ['RS256', 'ES256'] }, (err, decoded) => {
        if (err) {
            return res.status(401).json({ error: 'Invalid or expired token' });
        }
        req.user = {
            sub: decoded.sub,
            email: decoded.email,
            // app_metadata is set by supabaseAdmin.createAuthUser() at
            // onboarding time and included in every session JWT by
            // default — no custom Auth Hook needed to read it back here.
            role: decoded.app_metadata?.app_role, // web_admin / web_staff / web_customer
        };
        next();
    });
}

/** Restricts a route to one or more of the coarse "role" claim values. */
function requireRole(...allowedRoles) {
    return (req, res, next) => {
        if (!req.user || !allowedRoles.includes(req.user.role)) {
            return res.status(403).json({ error: 'Forbidden for this role' });
        }
        next();
    };
}

module.exports = { requireAuth, requireRole };
