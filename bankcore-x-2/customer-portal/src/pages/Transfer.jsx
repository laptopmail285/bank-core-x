import { useEffect, useState } from 'react';
import { pgGet, pgRpc } from '../lib/apiClient';
import { PageHeader, Card, Button } from '../components/ui';

export default function Transfer() {
    const [accounts, setAccounts] = useState([]);
    const [submitting, setSubmitting] = useState(false);
    const [result, setResult] = useState(null);
    const [error, setError] = useState(null);
    const [form, setForm] = useState({ fromAccountId: '', toAccountId: '', amount: '', description: '' });

    useEffect(() => {
        pgGet('/my_accounts?select=id,account_reference,cached_balance').then(setAccounts).catch(() => {});
    }, []);

    async function handleSubmit(e) {
        e.preventDefault();
        setSubmitting(true);
        setError(null);
        setResult(null);
        try {
            const response = await pgRpc('internal_transfer', {
                p_from_account_id: form.fromAccountId,
                p_to_account_id: form.toAccountId,
                p_amount: parseFloat(form.amount),
                p_description: form.description || null,
            });
            setResult(response);
            setForm({ fromAccountId: '', toAccountId: '', amount: '', description: '' });
        } catch (err) {
            setError(err.message);
        } finally {
            setSubmitting(false);
        }
    }

    return (
        <div>
            <PageHeader title="Transfer Money" subtitle="Move money between your accounts, or to another account at this bank" />

            <Card className="p-6 max-w-lg">
                <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                        <label className="block text-xs text-ink-600 mb-1">From account</label>
                        <select
                            required
                            className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm"
                            value={form.fromAccountId}
                            onChange={(e) => setForm({ ...form, fromAccountId: e.target.value })}
                        >
                            <option value="">Select account…</option>
                            {accounts.map((a) => (
                                <option key={a.id} value={a.id}>
                                    {a.account_reference} — ₹{a.cached_balance}
                                </option>
                            ))}
                        </select>
                    </div>

                    <div>
                        <label className="block text-xs text-ink-600 mb-1">To account ID</label>
                        <input
                            required
                            className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm font-mono"
                            placeholder="Recipient account UUID"
                            value={form.toAccountId}
                            onChange={(e) => setForm({ ...form, toAccountId: e.target.value })}
                        />
                    </div>

                    <div>
                        <label className="block text-xs text-ink-600 mb-1">Amount</label>
                        <input
                            required
                            type="number"
                            step="0.01"
                            min="0.01"
                            className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm font-mono"
                            value={form.amount}
                            onChange={(e) => setForm({ ...form, amount: e.target.value })}
                        />
                    </div>

                    <div>
                        <label className="block text-xs text-ink-600 mb-1">Note (optional)</label>
                        <input
                            className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm"
                            value={form.description}
                            onChange={(e) => setForm({ ...form, description: e.target.value })}
                        />
                    </div>

                    <Button type="submit" disabled={submitting}>
                        {submitting ? 'Sending…' : 'Send transfer'}
                    </Button>
                </form>

                {error && <p className="text-danger-600 text-sm mt-4">{error}</p>}

                {result && (
                    <div className="mt-4 text-sm bg-emerald-50 border border-emerald-600/30 rounded-md p-4">
                        <p><strong>Reference:</strong> {result.transaction_reference}</p>
                        <p><strong>Status:</strong> {result.status}</p>
                    </div>
                )}
            </Card>
        </div>
    );
}
