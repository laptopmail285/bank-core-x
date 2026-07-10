import { useEffect, useState } from 'react';
import { pgGet, backendPost } from '../lib/apiClient';
import { PageHeader, Table, Button, Card } from '../components/ui';

export default function Customers() {
    const [customers, setCustomers] = useState(null);
    const [branches, setBranches] = useState([]);
    const [error, setError] = useState(null);
    const [showForm, setShowForm] = useState(false);
    const [submitting, setSubmitting] = useState(false);
    const [result, setResult] = useState(null);
    const [form, setForm] = useState({
        fullName: '', dateOfBirth: '', email: '', phone: '', branchId: '',
    });

    function loadCustomers() {
        pgGet('/all_customers?select=*&order=created_at.desc')
            .then(setCustomers)
            .catch((err) => setError(err.message));
    }

    useEffect(() => {
        loadCustomers();
        pgGet('/all_branches?select=id,branch_name&status=eq.ACTIVE').then(setBranches).catch(() => {});
    }, []);

    async function handleSubmit(e) {
        e.preventDefault();
        setSubmitting(true);
        setError(null);
        try {
            const response = await backendPost('/onboarding/customers', form);
            setResult(response);
            setShowForm(false);
            setForm({ fullName: '', dateOfBirth: '', email: '', phone: '', branchId: '' });
            loadCustomers();
        } catch (err) {
            setError(err.message);
        } finally {
            setSubmitting(false);
        }
    }

    const columns = [
        { key: 'customer_reference', label: 'Reference' },
        { key: 'full_name', label: 'Name' },
        { key: 'email', label: 'Email' },
        {
            key: 'kyc_status',
            label: 'KYC',
            render: (row) => (
                <span
                    className={`text-xs px-2 py-0.5 rounded-full ${
                        row.kyc_status === 'VERIFIED' ? 'bg-emerald-50 text-emerald-700' : 'bg-canvas text-ink-600'
                    }`}
                >
                    {row.kyc_status}
                </span>
            ),
        },
        { key: 'status', label: 'Status' },
    ];

    return (
        <div>
            <PageHeader
                title="Customers"
                subtitle="Branch-assisted onboarding and customer directory"
                action={<Button onClick={() => setShowForm((s) => !s)}>{showForm ? 'Cancel' : 'Onboard customer'}</Button>}
            />

            {error && <p className="text-danger-600 text-sm mb-4">{error}</p>}

            {result && (
                <Card className="p-4 mb-6 bg-emerald-50 border-emerald-600">
                    <p className="text-sm text-emerald-700">
                        Customer created. Temporary password: <strong className="font-mono">{result.temporaryPassword}</strong>
                    </p>
                    <p className="text-xs text-emerald-700/80 mt-1">{result.note}</p>
                </Card>
            )}

            {showForm && (
                <Card className="p-6 mb-6">
                    <form onSubmit={handleSubmit} className="space-y-4">
                        <div className="grid grid-cols-2 gap-4">
                            <div>
                                <label className="block text-xs text-ink-600 mb-1">Full name</label>
                                <input
                                    required
                                    className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm"
                                    value={form.fullName}
                                    onChange={(e) => setForm({ ...form, fullName: e.target.value })}
                                />
                            </div>
                            <div>
                                <label className="block text-xs text-ink-600 mb-1">Date of birth</label>
                                <input
                                    required
                                    type="date"
                                    className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm"
                                    value={form.dateOfBirth}
                                    onChange={(e) => setForm({ ...form, dateOfBirth: e.target.value })}
                                />
                            </div>
                            <div>
                                <label className="block text-xs text-ink-600 mb-1">Email</label>
                                <input
                                    required
                                    type="email"
                                    className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm"
                                    value={form.email}
                                    onChange={(e) => setForm({ ...form, email: e.target.value })}
                                />
                            </div>
                            <div>
                                <label className="block text-xs text-ink-600 mb-1">Phone</label>
                                <input
                                    required
                                    className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm"
                                    value={form.phone}
                                    onChange={(e) => setForm({ ...form, phone: e.target.value })}
                                />
                            </div>
                            <div>
                                <label className="block text-xs text-ink-600 mb-1">Branch</label>
                                <select
                                    required
                                    className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm"
                                    value={form.branchId}
                                    onChange={(e) => setForm({ ...form, branchId: e.target.value })}
                                >
                                    <option value="">Select branch…</option>
                                    {branches.map((b) => (
                                        <option key={b.id} value={b.id}>{b.branch_name}</option>
                                    ))}
                                </select>
                            </div>
                        </div>
                        <Button type="submit" disabled={submitting}>
                            {submitting ? 'Creating…' : 'Onboard customer'}
                        </Button>
                    </form>
                </Card>
            )}

            {customers && <Table columns={columns} rows={customers} emptyMessage="No customers yet." />}
        </div>
    );
}
