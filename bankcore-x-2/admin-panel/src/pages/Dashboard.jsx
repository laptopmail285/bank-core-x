import { useEffect, useState } from 'react';
import { pgGet } from '../lib/apiClient';
import { PageHeader } from '../components/ui';
import StatCard from '../components/StatCard';
import Amount from '../components/Amount';

export default function Dashboard() {
    const [stats, setStats] = useState(null);
    const [error, setError] = useState(null);

    useEffect(() => {
        Promise.all([
            pgGet('/all_customers?select=id,status'),
            pgGet('/my_accounts?select=id,status,cached_balance'),
            pgGet('/pending_approvals?select=id'),
            pgGet('/open_fraud_alerts?select=id,severity'),
        ])
            .then(([customers, accounts, approvals, alerts]) => {
                const totalBalance = accounts.reduce((sum, a) => sum + Number(a.cached_balance), 0);
                setStats({
                    totalCustomers: customers.length,
                    activeAccounts: accounts.filter((a) => a.status === 'ACTIVE').length,
                    totalBalance,
                    pendingApprovals: approvals.length,
                    openAlerts: alerts.length,
                });
            })
            .catch((err) => setError(err.message));
    }, []);

    return (
        <div>
            <PageHeader title="Dashboard" subtitle="Bank-wide overview" />

            {error && <p className="text-danger-600 text-sm mb-4">{error}</p>}

            {!stats && !error && <p className="text-sm text-ink-600">Loading…</p>}

            {stats && (
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                    <StatCard label="Total Customers" value={stats.totalCustomers} />
                    <StatCard label="Active Accounts" value={stats.activeAccounts} />
                    <StatCard
                        label="Total Deposits"
                        value={<Amount value={stats.totalBalance} tone="credit" />}
                    />
                    <StatCard label="Pending Approvals" value={stats.pendingApprovals} />
                    <StatCard
                        label="Open Fraud Alerts"
                        value={stats.openAlerts}
                        sublabel={stats.openAlerts > 0 ? 'Needs review' : 'All clear'}
                    />
                </div>
            )}
        </div>
    );
}
