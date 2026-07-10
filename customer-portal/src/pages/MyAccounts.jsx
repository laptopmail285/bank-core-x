import { useEffect, useState } from 'react';
import { pgGet } from '../lib/apiClient';
import { PageHeader, Table, Card } from '../components/ui';
import Amount from '../components/Amount';

export default function MyAccounts() {
    const [accounts, setAccounts] = useState(null);
    const [transactions, setTransactions] = useState(null);
    const [error, setError] = useState(null);

    useEffect(() => {
        pgGet('/my_accounts?select=*')
            .then(setAccounts)
            .catch((err) => setError(err.message));

        pgGet('/my_transactions?select=*&order=posted_at.desc&limit=10')
            .then(setTransactions)
            .catch((err) => setError(err.message));
    }, []);

    const txnColumns = [
        { key: 'transaction_reference', label: 'Reference' },
        { key: 'transaction_type', label: 'Type' },
        {
            key: 'posted_at',
            label: 'Date',
            render: (row) => (row.posted_at ? new Date(row.posted_at).toLocaleDateString() : '—'),
        },
        { key: 'status', label: 'Status' },
    ];

    return (
        <div>
            <PageHeader title="My Accounts" />
            {error && <p className="text-danger-600 text-sm mb-4">{error}</p>}

            {accounts && (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-8">
                    {accounts.length === 0 && (
                        <Card className="p-6 text-sm text-ink-600 col-span-2">No accounts yet.</Card>
                    )}
                    {accounts.map((acc) => (
                        <Card key={acc.id} className="p-5">
                            <div className="text-xs uppercase tracking-wide text-ink-600">{acc.account_reference}</div>
                            <div className="mt-2">
                                <Amount value={acc.cached_balance} tone="credit" className="text-lg" />
                            </div>
                            <div className="mt-2 text-xs text-ink-600">{acc.status}</div>
                        </Card>
                    ))}
                </div>
            )}

            <h2 className="font-display text-lg text-ink-900 mb-3">Recent transactions</h2>
            {transactions && (
                <Table columns={txnColumns} rows={transactions} emptyMessage="No transactions yet." />
            )}
        </div>
    );
}
