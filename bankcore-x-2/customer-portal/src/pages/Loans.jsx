import { useEffect, useState } from 'react';
import { pgGet } from '../lib/apiClient';
import { PageHeader, Table } from '../components/ui';
import Amount from '../components/Amount';

export default function Loans() {
    const [loans, setLoans] = useState(null);
    const [error, setError] = useState(null);

    useEffect(() => {
        pgGet('/my_loans?select=*&order=disbursed_at.desc')
            .then(setLoans)
            .catch((err) => setError(err.message));
    }, []);

    const columns = [
        { key: 'loan_reference', label: 'Reference' },
        {
            key: 'principal_amount',
            label: 'Principal',
            render: (row) => <Amount value={row.principal_amount} />,
        },
        {
            key: 'outstanding_principal',
            label: 'Outstanding',
            render: (row) => <Amount value={row.outstanding_principal} tone="debit" />,
        },
        { key: 'interest_rate_annual_locked', label: 'Rate (%)' },
        { key: 'status', label: 'Status' },
    ];

    return (
        <div>
            <PageHeader title="My Loans" />
            {error && <p className="text-danger-600 text-sm mb-4">{error}</p>}
            {loans && <Table columns={columns} rows={loans} emptyMessage="You have no loans." />}
        </div>
    );
}
