import { useEffect, useState } from 'react';
import { pgGet } from '../lib/apiClient';
import { PageHeader, Card } from '../components/ui';

export default function Cards() {
    const [cards, setCards] = useState(null);
    const [error, setError] = useState(null);

    useEffect(() => {
        pgGet('/my_cards?select=*')
            .then(setCards)
            .catch((err) => setError(err.message));
    }, []);

    return (
        <div>
            <PageHeader title="My Cards" />
            {error && <p className="text-danger-600 text-sm mb-4">{error}</p>}

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                {cards && cards.length === 0 && (
                    <Card className="p-6 text-sm text-ink-600 col-span-2">You have no cards yet.</Card>
                )}
                {cards && cards.map((card) => (
                    <Card key={card.id} className="p-5 bg-ink-900 text-white">
                        <div className="text-xs text-white/50 uppercase tracking-wide">
                            {card.status}
                        </div>
                        <div className="mt-4 font-mono text-lg tracking-widest">
                            {card.masked_card_number}
                        </div>
                        <div className="mt-4 flex justify-between text-xs text-white/60">
                            <span>ATM limit: ₹{card.daily_atm_limit}</span>
                            <span>Online limit: ₹{card.daily_online_limit}</span>
                        </div>
                    </Card>
                ))}
            </div>
        </div>
    );
}
