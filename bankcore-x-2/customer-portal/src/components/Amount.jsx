// The signature element of the "Ledger" design system: every monetary
// figure in the app renders the same way — tabular monospace digits,
// a thin left rule, and a color that reflects debit/credit/neutral —
// so numbers read consistently across every screen, like entries in a
// real ledger book.
export default function Amount({ value, currency = 'INR', tone = 'neutral', className = '' }) {
    const formatted = new Intl.NumberFormat('en-IN', {
        style: 'currency',
        currency,
        currencyDisplay: 'narrowSymbol',
        minimumFractionDigits: 2,
    }).format(value ?? 0);

    const toneClasses = {
        neutral: 'border-ink-600 text-ink-900',
        credit: 'border-emerald-600 text-emerald-700',
        debit: 'border-danger-600 text-danger-600',
    };

    return (
        <span
            className={`inline-block border-l-2 pl-2 font-mono text-sm tabular-nums ${toneClasses[tone]} ${className}`}
        >
            {formatted}
        </span>
    );
}
