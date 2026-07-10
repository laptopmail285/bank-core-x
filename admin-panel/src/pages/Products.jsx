import { useEffect, useState } from 'react';
import { pgGet } from '../lib/apiClient';
import { PageHeader, Table } from '../components/ui';
import Amount from '../components/Amount';

export default function Products() {
    const [products, setProducts] = useState(null);
    const [error, setError] = useState(null);

    useEffect(() => {
        pgGet('/product_catalog_accounts?select=*&order=product_name')
            .then(setProducts)
            .catch((err) => setError(err.message));
    }, []);

    const columns = [
        { key: 'product_code', label: 'Code' },
        { key: 'product_name', label: 'Name' },
        { key: 'account_category', label: 'Category' },
        {
            key: 'minimum_balance',
            label: 'Minimum balance',
            render: (row) => <Amount value={row.minimum_balance} />,
        },
        {
            key: 'monthly_maintenance_fee',
            label: 'Monthly fee',
            render: (row) => <Amount value={row.monthly_maintenance_fee} tone="debit" />,
        },
    ];

    return (
        <div>
            <PageHeader
                title="Account Products"
                subtitle="Active account products in the catalog. Loan, term deposit, and card products follow the same pattern."
            />
            {error && <p className="text-danger-600 text-sm mb-4">{error}</p>}
            {products && <Table columns={columns} rows={products} emptyMessage="No account products configured yet." />}
        </div>
    );
}
