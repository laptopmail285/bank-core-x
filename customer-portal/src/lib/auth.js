// src/lib/auth.js
// Session handling via Supabase Auth (email/password). Replaces the
// hand-rolled Keycloak OIDC/PKCE flow — supabase-js manages token
// storage and refresh internally, so this file is mostly a thin,
// familiar-shaped wrapper around it for the rest of the app.
import { supabase } from './supabaseClient';

/** Signs in with email/password. Throws on failure with a readable message. */
export async function signIn(email, password) {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw new Error(error.message);
    return data.session;
}

export async function signOut() {
    await supabase.auth.signOut();
}

/** Returns the current session (or null), reading from local cache first. */
export async function getSession() {
    const { data, error } = await supabase.auth.getSession();
    if (error) return null;
    return data.session;
}

/** Returns a valid access token, or null if not logged in. supabase-js
 *  refreshes it automatically before expiry, so this never needs manual
 *  refresh logic the way the old Keycloak version did. */
export async function getAccessToken() {
    const session = await getSession();
    return session?.access_token || null;
}

/** Basic info about the logged-in user, decoded from the session itself
 *  (no JWT decoding needed — supabase-js already parses it). */
export function userFromSession(session) {
    if (!session?.user) return null;
    return {
        sub: session.user.id,
        email: session.user.email,
        role: session.user.app_metadata?.app_role || null,
    };
}

/** Subscribe to login/logout/token-refresh events. Returns an unsubscribe fn. */
export function onAuthStateChange(callback) {
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
        callback(session);
    });
    return () => data.subscription.unsubscribe();
}
