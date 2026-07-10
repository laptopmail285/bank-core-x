// src/lib/supabaseClient.js
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    // eslint-disable-next-line no-console
    console.error(
        'Missing VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY — copy .env.example to .env ' +
        'and fill in your Supabase project values (Project Settings → API).'
    );
}

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
        // Separate storage key per portal so a customer/staff/admin login on
        // the same browser (e.g. during local dev on the same origin) don't
        // stomp on each other's session.
        storageKey: import.meta.env.VITE_SUPABASE_STORAGE_KEY || 'bankcore-x-auth',
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: false,
    },
});
