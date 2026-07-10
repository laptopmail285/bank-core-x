import { useEffect, useState } from 'react';
import { pgGet } from '../lib/apiClient';
import { PageHeader, Table } from '../components/ui';

export default function Branches() {
    const [branches, setBranches] = useState(null);
    const [error, setError] = useState(null);

    useEffect(() => {
        pgGet('/all_branches?select=*&order=branch_code')
            .then(setBranches)
            .catch((err) => setError(err.message));
    }, []);

    const columns = [
        { key: 'branch_code', label: 'Code' },
        { key: 'branch_name', label: 'Name' },
        { key: 'city', label: 'City' },
        { key: 'state', label: 'State' },
        {
            key: 'status',
            label: 'Status',
            render: (row) => (
                <span
                    className={`text-xs px-2 py-0.5 rounded-full ${
                        row.status === 'ACTIVE' ? 'bg-emerald-50 text-emerald-700' : 'bg-canvas text-ink-600'
                    }`}
                >
                    {row.status}
                </span>
            ),
        },
        {
            key: 'is_head_office',
            label: 'Head Office',
            render: (row) => (row.is_head_office ? 'Yes' : ''),
        },
    ];

    return (
        <div>
            <PageHeader title="Branches" subtitle="All configured branches" />
            {error && <p className="text-danger-600 text-sm mb-4">{error}</p>}
            {branches && <Table columns={columns} rows={branches} emptyMessage="No branches configured yet." />}
        </div>
    );
}
