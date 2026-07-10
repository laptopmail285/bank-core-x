import { NavLink, Outlet } from 'react-router-dom';
import { signOut } from '../lib/auth';

const NAV_ITEMS = [
    { to: '/', label: 'Dashboard', end: true },
    { to: '/branches', label: 'Branches' },
    { to: '/employees', label: 'Employees' },
    { to: '/products', label: 'Products' },
    { to: '/approvals', label: 'Approvals' },
    { to: '/audit-logs', label: 'Audit Logs' },
    { to: '/end-of-day', label: 'End of Day' },
];

export default function Layout({ user }) {
    return (
        <div className="flex min-h-screen">
            <aside className="w-64 shrink-0 bg-ink-900 text-white flex flex-col">
                <div className="px-6 py-6 border-b border-ink-700">
                    <div className="font-display text-xl tracking-tight">BankCore X</div>
                    <div className="text-xs text-white/50 mt-1">Admin Panel</div>
                </div>

                <nav className="flex-1 px-3 py-4 space-y-1">
                    {NAV_ITEMS.map((item) => (
                        <NavLink
                            key={item.to}
                            to={item.to}
                            end={item.end}
                            className={({ isActive }) =>
                                `block rounded-md px-3 py-2 text-sm transition-colors ${
                                    isActive
                                        ? 'bg-emerald-600 text-white'
                                        : 'text-white/70 hover:bg-ink-700 hover:text-white'
                                }`
                            }
                        >
                            {item.label}
                        </NavLink>
                    ))}
                </nav>

                <div className="px-6 py-4 border-t border-ink-700 text-sm">
                    <div className="text-white/60 truncate">{user?.email}</div>
                    <button
                        onClick={signOut}
                        className="mt-2 text-white/70 hover:text-white underline underline-offset-2"
                    >
                        Sign out
                    </button>
                </div>
            </aside>

            <main className="flex-1 bg-canvas">
                <div className="max-w-6xl mx-auto px-8 py-8">
                    <Outlet />
                </div>
            </main>
        </div>
    );
}
