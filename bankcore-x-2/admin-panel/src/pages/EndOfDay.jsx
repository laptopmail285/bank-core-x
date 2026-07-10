import { useState } from 'react';
import { pgRpc } from '../lib/apiClient';
import { PageHeader, Card, Button } from '../components/ui';

export default function EndOfDay() {
    const [running, setRunning] = useState(false);
    const [result, setResult] = useState(null);
    const [error, setError] = useState(null);

    async function handleTrigger() {
        setRunning(true);
        setError(null);
        setResult(null);
        try {
            const response = await pgRpc('trigger_eod');
            setResult(response);
        } catch (err) {
            setError(err.message);
        } finally {
            setRunning(false);
        }
    }

    return (
        <div>
            <PageHeader
                title="End of Day"
                subtitle="Runs dormancy checks, marks overdue loan installments, and advances the business date."
            />

            <Card className="p-6 max-w-xl">
                <p className="text-sm text-ink-600 mb-4">
                    This also runs automatically every day at 23:55. Use this only to trigger an
                    out-of-cycle run — for example, after fixing a configuration issue that
                    blocked the scheduled run.
                </p>
                <Button onClick={handleTrigger} disabled={running}>
                    {running ? 'Running…' : 'Run End of Day now'}
                </Button>

                {error && <p className="text-danger-600 text-sm mt-4">{error}</p>}

                {result && (
                    <div className="mt-4 text-sm text-ink-900 bg-emerald-50 border border-emerald-600/30 rounded-md p-4">
                        <p>
                            <strong>Status:</strong> {result.status}
                        </p>
                        <p>
                            <strong>Business date processed:</strong> {result.business_date}
                        </p>
                        <p>
                            <strong>Completed at:</strong>{' '}
                            {result.completed_at ? new Date(result.completed_at).toLocaleString() : '—'}
                        </p>
                    </div>
                )}
            </Card>
        </div>
    );
}
