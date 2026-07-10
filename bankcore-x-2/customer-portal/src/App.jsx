import { useEffect, useState } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { getSession, userFromSession, onAuthStateChange } from './lib/auth';
import Layout from './components/Layout';
import Login from './pages/Login';
import MyAccounts from './pages/MyAccounts';
import Transfer from './pages/Transfer';
import Loans from './pages/Loans';
import Cards from './pages/Cards';

function ProtectedApp() {
    const [session, setSession] = useState(undefined); // undefined = still loading

    useEffect(() => {
        getSession().then(setSession);
        const unsubscribe = onAuthStateChange(setSession);
        return unsubscribe;
    }, []);

    if (session === undefined) {
        return <div className="min-h-screen flex items-center justify-center text-sm text-ink-600">Loading…</div>;
    }

    if (!session) {
        return <Navigate to="/login" replace />;
    }

    const user = userFromSession(session);

    return (
        <Routes>
            <Route element={<Layout user={user} />}>
                <Route index element={<MyAccounts />} />
                <Route path="transfer" element={<Transfer />} />
                <Route path="loans" element={<Loans />} />
                <Route path="cards" element={<Cards />} />
            </Route>
        </Routes>
    );
}

export default function App() {
    return (
        <Routes>
            <Route path="/login" element={<Login />} />
            <Route path="/*" element={<ProtectedApp />} />
        </Routes>
    );
}
