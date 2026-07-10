import { useEffect, useState } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { getSession, userFromSession, onAuthStateChange } from './lib/auth';
import Layout from './components/Layout';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Customers from './pages/Customers';
import Counter from './pages/Counter';

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
                <Route index element={<Dashboard />} />
                <Route path="customers" element={<Customers />} />
                <Route path="counter" element={<Counter />} />
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
