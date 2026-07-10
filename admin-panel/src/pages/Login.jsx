import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { signIn } from '../lib/auth';

export default function Login() {
    const navigate = useNavigate();
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [error, setError] = useState(null);
    const [loading, setLoading] = useState(false);

    async function handleSubmit(e) {
        e.preventDefault();
        setError(null);
        setLoading(true);
        try {
            await signIn(email, password);
            navigate('/', { replace: true });
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    }

    return (
        <div className="min-h-screen flex items-center justify-center bg-ink-900">
            <form onSubmit={handleSubmit} className="bg-canvas-raised rounded-lg p-10 w-full max-w-sm">
                <div className="text-center mb-8">
                    <div className="font-display text-2xl text-ink-900">BankCore X</div>
                    <div className="text-sm text-ink-600 mt-1">Admin Panel</div>
                </div>

                <label className="block text-xs text-ink-600 mb-1">Email</label>
                <input
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="w-full rounded-md border border-ink-200 px-3 py-2 text-sm mb-4"
                    autoComplete="email"
                />

                <label className="block text-xs text-ink-600 mb-1">Password</label>
                <input
                    type="password"
                    required
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="w-full rounded-md border border-ink-200 px-3 py-2 text-sm mb-4"
                    autoComplete="current-password"
                />

                {error && <p className="text-danger-600 text-xs mb-4">{error}</p>}

                <button
                    type="submit"
                    disabled={loading}
                    className="w-full rounded-md bg-emerald-600 text-white py-2.5 text-sm font-medium hover:bg-emerald-700 transition-colors disabled:opacity-50"
                >
                    {loading ? 'Signing in…' : 'Sign in'}
                </button>
            </form>
        </div>
    );
}
