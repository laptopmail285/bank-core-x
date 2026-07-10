export default function StatCard({ label, value, sublabel }) {
    return (
        <div className="bg-canvas-raised border border-canvas-line rounded-lg p-5">
            <div className="text-xs uppercase tracking-wide text-ink-600">{label}</div>
            <div className="mt-2 font-display text-3xl text-ink-900">{value}</div>
            {sublabel && <div className="mt-1 text-xs text-ink-600">{sublabel}</div>}
        </div>
    );
}
