import { useState } from 'react';
import { pgRpc } from '../lib/apiClient';
import { PageHeader, Card, Button } from '../components/ui';

const OPERATIONS = ['DEPOSIT', 'WITHDRAWAL', 'TRANSFER'];

export default function Counter() {
    const [operation, setOperation] = useState('DEPOSIT');
    const [submitting, setSubmitting] = useState(false);
    const [result, setResult] = useState(null);
    const [error, setError] = useState(null);
    const [form, setForm] = useState({
        accountId: '', fromAccountId: '', toAccountId: '', amount: '', description: '',
    });

    function updateField(field, value) {
        setForm((f) => ({ ...f, [field]: value }));
    }

    async function handleSubmit(e) {
        e.preventDefault();
        setSubmitting(true);
        setError(null);
        setResult(null);

        try {
            let response;
            const amount = parseFloat(form.amount);

            if (operation === 'DEPOSIT') {
                response = await pgRpc('deposit', {
                    p_account_id: form.accountId,
                    p_amount: amount,
                    p_channel_code: 'BRANCH',
                    p_description: form.description || null,
                });
            } else if (operation === 'WITHDRAWAL') {
                response = await pgRpc('withdraw', {
                    p_account_id: form.accountId,
                    p_amount: amount,
                    p_channel_code: 'BRANCH',
                    p_description: form.description || null,
                });
            } else {
                response = await pgRpc('internal_transfer', {
                    p_from_account_id: form.fromAccountId,
                    p_to_account_id: form.toAccountId,
                    p_amount: amount,
                    p_description: form.description || null,
                });
            }

            setResult(response);
            setForm({ accountId: '', fromAccountId: '', toAccountId: '', amount: '', description: '' });
        } catch (err) {
            setError(err.message);
        } finally {
            setSubmitting(false);
        }
    }

    return (
        <div>
            <PageHeader title="Counter Operations" subtitle="Branch-counter deposit, withdrawal, and internal transfer" />

            <div className="flex gap-2 mb-6">
                {OPERATIONS.map((op) => (
                    <button
                        key={op}
                        onClick={() => { setOperation(op); setResult(null); setError(null); }}
                        className={`text-sm px-4 py-2 rounded-md border ${
                            operation === op
                                ? 'bg-emerald-600 text-white border-emerald-600'
                                : 'border-canvas-line text-ink-600'
                        }`}
                    >
                        {op === 'DEPOSIT' ? 'Deposit' : op === 'WITHDRAWAL' ? 'Withdrawal' : 'Internal Transfer'}
                    </button>
                ))}
            </div>

            <Card className="p-6 max-w-lg">
                <form onSubmit={handleSubmit} className="space-y-4">
                    {operation !== 'TRANSFER' && (
                        <div>
                            <label className="block text-xs text-ink-600 mb-1">Account ID</label>
                            <input
                                required
                                className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm font-mono"
                                placeholder="Account UUID"
                                value={form.accountId}
                                onChange={(e) => updateField('accountId', e.target.value)}
                            />
                        </div>
                    )}

                    {operation === 'TRANSFER' && (
                        <>
                            <div>
                                <label className="block text-xs text-ink-600 mb-1">From account ID</label>
                                <input
                                    required
                                    className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm font-mono"
                                    value={form.fromAccountId}
                                    onChange={(e) => updateField('fromAccountId', e.target.value)}
                                />
                            </div>
                            <div>
                                <label className="block text-xs text-ink-600 mb-1">To account ID</label>
                                <input
                                    required
                                    className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm font-mono"
                                    value={form.toAccountId}
                                    onChange={(e) => updateField('toAccountId', e.target.value)}
                                />
                            </div>
                        </>
                    )}

                    <div>
                        <label className="block text-xs text-ink-600 mb-1">Amount</label>
                        <input
                            required
                            type="number"
                            step="0.01"
                            min="0.01"
                            className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm font-mono"
                            value={form.amount}
                            onChange={(e) => updateField('amount', e.target.value)}
                        />
                    </div>

                    <div>
                        <label className="block text-xs text-ink-600 mb-1">Description (optional)</label>
                        <input
                            className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm"
                            value={form.description}
                            onChange={(e) => updateField('description', e.target.value)}
                        />
                    </div>

                    <Button type="submit" disabled={submitting}>
                        {submitting ? 'Posting…' : 'Post transaction'}
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
