import { useEffect, useState } from 'react';
import { pgGet, backendPost } from '../lib/apiClient';
import { PageHeader, Table, Button, Card } from '../components/ui';

const ROLE_OPTIONS = [
    'SYSTEM_ADMIN', 'BRANCH_MANAGER', 'TELLER', 'LOAN_OFFICER',
    'KYC_REVIEWER', 'FRAUD_REVIEWER', 'AUDITOR',
];

export default function Employees() {
    const [employees, setEmployees] = useState(null);
    const [branches, setBranches] = useState([]);
    const [error, setError] = useState(null);
    const [showForm, setShowForm] = useState(false);
    const [submitting, setSubmitting] = useState(false);
    const [result, setResult] = useState(null);
    const [form, setForm] = useState({
        employeeCode: '', fullName: '', email: '', phone: '', branchId: '', roleCodes: [],
    });

    function loadEmployees() {
        pgGet('/all_employees?select=*&order=full_name')
            .then(setEmployees)
            .catch((err) => setError(err.message));
    }

    useEffect(() => {
        loadEmployees();
        pgGet('/all_branches?select=id,branch_name&status=eq.ACTIVE').then(setBranches).catch(() => {});
    }, []);

    function toggleRole(role) {
        setForm((f) => ({
            ...f,
            roleCodes: f.roleCodes.includes(role)
                ? f.roleCodes.filter((r) => r !== role)
                : [...f.roleCodes, role],
        }));
    }

    async function handleSubmit(e) {
        e.preventDefault();
        setSubmitting(true);
        setError(null);
        try {
            const response = await backendPost('/onboarding/employees', form);
            setResult(response);
            setShowForm(false);
            setForm({ employeeCode: '', fullName: '', email: '', phone: '', branchId: '', roleCodes: [] });
            loadEmployees();
        } catch (err) {
            setError(err.message);
        } finally {
            setSubmitting(false);
        }
    }

    const columns = [
        { key: 'employee_code', label: 'Code' },
        { key: 'full_name', label: 'Name' },
        { key: 'email', label: 'Email' },
        { key: 'primary_branch_name', label: 'Branch' },
        {
            key: 'role_codes',
            label: 'Roles',
            render: (row) => (row.role_codes || []).join(', '),
        },
        { key: 'status', label: 'Status' },
    ];

    return (
        <div>
            <PageHeader
                title="Employees"
                subtitle="Staff accounts and role assignments"
                action={<Button onClick={() => setShowForm((s) => !s)}>{showForm ? 'Cancel' : 'Add employee'}</Button>}
            />

            {error && <p className="text-danger-600 text-sm mb-4">{error}</p>}

            {result && (
                <Card className="p-4 mb-6 bg-emerald-50 border-emerald-600">
                    <p className="text-sm text-emerald-700">
                        Employee created. Temporary password: <strong className="font-mono">{result.temporaryPassword}</strong>
                    </p>
                    <p className="text-xs text-emerald-700/80 mt-1">{result.note}</p>
                </Card>
            )}

            {showForm && (
                <Card className="p-6 mb-6">
                    <form onSubmit={handleSubmit} className="space-y-4">
                        <div className="grid grid-cols-2 gap-4">
                            <div>
                                <label className="block text-xs text-ink-600 mb-1">Employee code</label>
                                <input
                                    required
                                    className="w-full rounded-md border border-canvas-line px-3 py-2 text-sm"
                                    value={form.employeeCode}
                                    onChange={(e) => setForm({ ...form, employeeCode: e.target.value })}
                                />
                            </div>
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

                        <div>
                            <label className="block text-xs text-ink-600 mb-2">Roles</label>
                            <div className="flex flex-wrap gap-2">
                                {ROLE_OPTIONS.map((role) => (
                                    <button
                                        type="button"
                                        key={role}
                                        onClick={() => toggleRole(role)}
                                        className={`text-xs px-3 py-1.5 rounded-full border ${
                                            form.roleCodes.includes(role)
                                                ? 'bg-emerald-600 text-white border-emerald-600'
                                                : 'border-canvas-line text-ink-600'
                                        }`}
                                    >
                                        {role}
                                    </button>
                                ))}
                            </div>
                        </div>

                        <Button type="submit" disabled={submitting}>
                            {submitting ? 'Creating…' : 'Create employee'}
                        </Button>
                    </form>
                </Card>
            )}

            {employees && <Table columns={columns} rows={employees} emptyMessage="No employees yet." />}
        </div>
    );
}
