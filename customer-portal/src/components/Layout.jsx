import { NavLink, Outlet } from 'react-router-dom';
import { signOut } from '../lib/auth';

const NAV_ITEMS = [
    { to: '/', label: 'My Accounts', end: true },
    { to: '/transfer', label: 'Transfer Money' },
    { to: '/loans', label: 'My Loans' },
    { to: '/cards', label: 'My Cards' },
];

export default function Layout({ user }) {
    return (
        <div className="min-h-screen">
            <header className="bg-ink-900 text-white">
                <div className="max-w-4xl mx-auto px-6 py-4 flex items-center justify-between">
                    <div className="font-display text-lg">BankCore X</div>
                    <nav className="flex gap-1">
                        {NAV_ITEMS.map((item) => (
                            <NavLink
                                key={item.to}
                                to={item.to}
                                end={item.end}
                                className={({ isActive }) =>
                                    `text-sm px-3 py-1.5 rounded-md transition-colors ${
                                        isActive ? 'bg-emerald-600 text-white' : 'text-white/70 hover:text-white'
                                    }`
                                }
                            >
                                {item.label}
                            </NavLink>
                        ))}
                    </nav>
                    <div className="flex items-center gap-3 text-sm">
                        <span className="text-white/60 hidden sm:inline">{user?.email}</span>
                        <button onClick={signOut} className="text-white/70 hover:text-white underline underline-offset-2">
                            Sign out
                        </button>
                    </div>
                </div>
            </header>

            <main className="max-w-4xl mx-auto px-6 py-8">
                <Outlet />
            </main>
        </div>
    );
}
