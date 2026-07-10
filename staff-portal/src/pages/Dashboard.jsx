import { useEffect, useState } from 'react';
import { pgGet } from '../lib/apiClient';
import { PageHeader, Table } from '../components/ui';
import StatCard from '../components/StatCard';

export default function Dashboard() {
    const [stats, setStats] = useState(null);
    const [recentTxns, setRecentTxns] = useState(null);
    const [error, setError] = useState(null);

    useEffect(() => {
        pgGet('/all_customers?select=id,status')
            .then((customers) => setStats({ totalCustomers: customers.length }))
            .catch((err) => setError(err.message));

        pgGet('/my_transactions?select=*&order=posted_at.desc&limit=10')
            .then(setRecentTxns)
            .catch((err) => setError(err.message));
    }, []);

    const columns = [
        { key: 'transaction_reference', label: 'Reference' },
        { key: 'transaction_type', label: 'Type' },
        {
            key: 'posted_at',
            label: 'When',
            render: (row) => (row.posted_at ? new Date(row.posted_at).toLocaleString() : '—'),
        },
        { key: 'status', label: 'Status' },
    ];

    return (
        <div>
            <PageHeader title="Dashboard" subtitle="Branch overview" />
            {error && <p className="text-danger-600 text-sm mb-4">{error}</p>}

            {stats && (
                <div className="grid grid-cols-2 gap-4 mb-8">
                    <StatCard label="Total Customers" value={stats.totalCustomers} />
                </div>
            )}

            <h2 className="font-display text-lg text-ink-900 mb-3">Recent transactions</h2>
            {recentTxns && (
                <Table columns={columns} rows={recentTxns} emptyMessage="No transactions posted yet." />
            )}
        </div>
    );
}
