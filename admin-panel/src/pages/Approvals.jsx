import { useEffect, useState } from 'react';
import { pgGet } from '../lib/apiClient';
import { PageHeader, Table } from '../components/ui';

export default function Approvals() {
    const [approvals, setApprovals] = useState(null);
    const [error, setError] = useState(null);

    useEffect(() => {
        pgGet('/pending_approvals?select=*&order=requested_at')
            .then(setApprovals)
            .catch((err) => setError(err.message));
    }, []);

    const columns = [
        { key: 'workflow_code', label: 'Workflow' },
        { key: 'resource_type', label: 'Resource' },
        { key: 'requested_by_name', label: 'Requested by' },
        {
            key: 'requested_at',
            label: 'Requested at',
            render: (row) => new Date(row.requested_at).toLocaleString(),
        },
    ];

    return (
        <div>
            <PageHeader
                title="Approvals"
                subtitle="Maker-checker requests awaiting a decision. Self-approval is blocked at the database level."
            />
            {error && <p className="text-danger-600 text-sm mb-4">{error}</p>}
            {approvals && (
                <Table columns={columns} rows={approvals} emptyMessage="No pending approvals — you're all caught up." />
            )}
        </div>
    );
}
