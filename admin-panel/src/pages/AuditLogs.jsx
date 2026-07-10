import { useEffect, useState } from 'react';
import { pgGet } from '../lib/apiClient';
import { PageHeader, Table } from '../components/ui';

export default function AuditLogs() {
    const [logs, setLogs] = useState(null);
    const [error, setError] = useState(null);

    useEffect(() => {
        pgGet('/audit_logs?select=*&order=created_at.desc&limit=100')
            .then(setLogs)
            .catch((err) => setError(err.message));
    }, []);

    const columns = [
        {
            key: 'created_at',
            label: 'When',
            render: (row) => new Date(row.created_at).toLocaleString(),
        },
        { key: 'action', label: 'Action' },
        { key: 'resource_type', label: 'Resource' },
        {
            key: 'actor',
            label: 'Actor',
            render: (row) =>
                row.actor_employee_id ? 'Employee' : row.actor_customer_id ? 'Customer' : 'System',
        },
    ];

    return (
        <div>
            <PageHeader title="Audit Logs" subtitle="Most recent 100 events, newest first (append-only trail)" />
            {error && <p className="text-danger-600 text-sm mb-4">{error}</p>}
            {logs && <Table columns={columns} rows={logs} emptyMessage="No audit events recorded yet." />}
        </div>
    );
}
