// src/lib/apiClient.js
// Thin wrapper around fetch for Supabase's auto-generated REST API
// (PostgREST over the "api" schema) and the small Node backend,
// attaching the Supabase session's bearer token to every request.
//
// SUPABASE SETUP REQUIRED: in the Supabase dashboard, go to
// Project Settings → API → "Exposed schemas" and add "api" (alongside
// the default "public") — otherwise every request below 404s, since
// PostgREST only serves schemas that have been explicitly exposed.
import { supabase } from './supabaseClient';
import { getAccessToken, signOut } from './auth';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;
const POSTGREST_URL = `${SUPABASE_URL}/rest/v1`;
const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || 'http://localhost:3001';

async function request(baseUrl, path, options = {}, extraHeaders = {}) {
    const token = await getAccessToken();
    if (!token) {
        await signOut();
        throw new Error('Not authenticated');
    }

    const response = await fetch(`${baseUrl}${path}`, {
        ...options,
        headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
            ...extraHeaders,
            ...(options.headers || {}),
        },
    });

    if (response.status === 401) {
        await signOut();
        throw new Error('Session expired');
    }

    if (!response.ok) {
        const errorBody = await response.json().catch(() => ({}));
        throw new Error(errorBody.message || errorBody.error || `Request failed: ${response.status}`);
    }

    if (response.status === 204) return null;
    return response.json();
}

// ---------- PostgREST via Supabase (reads via api.* views, writes via api.* RPC) ----------
// "Accept-Profile"/"Content-Profile" tell PostgREST which exposed schema
// to use for this request — required because api.* is not the default
// "public" schema. apikey is Supabase's own gate in front of PostgREST.

const pgHeaders = (profile) => ({
    apikey: SUPABASE_ANON_KEY,
    ...(profile === 'read' ? { 'Accept-Profile': 'api' } : { 'Content-Profile': 'api' }),
});

export function pgGet(path) {
    return request(POSTGREST_URL, path, { method: 'GET' }, pgHeaders('read'));
}

export function pgPost(path, body) {
    return request(POSTGREST_URL, path, { method: 'POST', body: JSON.stringify(body) }, pgHeaders('write'));
}

export function pgPatch(path, body) {
    return request(POSTGREST_URL, path, { method: 'PATCH', body: JSON.stringify(body) }, pgHeaders('write'));
}

export function pgRpc(functionName, args = {}) {
    return request(
        POSTGREST_URL,
        `/rpc/${functionName}`,
        { method: 'POST', body: JSON.stringify(args) },
        pgHeaders('write')
    );
}

// ---------- Backend (onboarding + KYC upload orchestration) ----------

export function backendPost(path, body) {
    return request(BACKEND_URL, path, { method: 'POST', body: JSON.stringify(body) });
}

export function backendGet(path) {
    return request(BACKEND_URL, path, { method: 'GET' });
}

export { supabase };
