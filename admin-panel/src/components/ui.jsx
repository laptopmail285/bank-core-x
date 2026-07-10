export function Button({ children, variant = 'primary', ...props }) {
    const variants = {
        primary: 'bg-emerald-600 text-white hover:bg-emerald-700',
        secondary: 'bg-white text-ink-900 border border-canvas-line hover:bg-canvas',
        danger: 'bg-danger-600 text-white hover:bg-danger-600/90',
    };
    return (
        <button
            className={`rounded-md px-4 py-2 text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${variants[variant]}`}
            {...props}
        >
            {children}
        </button>
    );
}

export function Card({ children, className = '' }) {
    return (
        <div className={`bg-canvas-raised border border-canvas-line rounded-lg ${className}`}>
            {children}
        </div>
    );
}

export function PageHeader({ title, subtitle, action }) {
    return (
        <div className="flex items-start justify-between mb-6">
            <div>
                <h1 className="font-display text-2xl text-ink-900">{title}</h1>
                {subtitle && <p className="mt-1 text-sm text-ink-600">{subtitle}</p>}
            </div>
            {action}
        </div>
    );
}

export function Table({ columns, rows, emptyMessage = 'No records yet.' }) {
    if (!rows || rows.length === 0) {
        return (
            <Card className="p-8 text-center text-sm text-ink-600">
                {emptyMessage}
            </Card>
        );
    }

    return (
        <Card className="overflow-hidden">
            <table className="w-full text-sm">
                <thead>
                    <tr className="border-b border-canvas-line bg-canvas text-left">
                        {columns.map((col) => (
                            <th key={col.key} className="px-4 py-3 font-medium text-ink-600">
                                {col.label}
                            </th>
                        ))}
                    </tr>
                </thead>
                <tbody>
                    {rows.map((row, i) => (
                        <tr key={row.id || i} className="border-b border-canvas-line last:border-0">
                            {columns.map((col) => (
                                <td key={col.key} className="px-4 py-3">
                                    {col.render ? col.render(row) : row[col.key]}
                                </td>
                            ))}
                        </tr>
                    ))}
                </tbody>
            </table>
        </Card>
    );
}
