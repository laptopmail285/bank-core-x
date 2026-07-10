/** @type {import('tailwindcss').Config} */
export default {
    content: ['./index.html', './src/**/*.{js,jsx}'],
    theme: {
        extend: {
            colors: {
                // "Ledger" design system — deliberately not the cream+terracotta
                // or dark+neon defaults. Ink for structural chrome (sidebar,
                // headers), a cool paper canvas for content, deep emerald as
                // the single confident accent (trust/money without cliché),
                // and a muted gold reserved for ledger-style numeric emphasis.
                ink: {
                    900: '#0B1220',
                    800: '#131C2E',
                    700: '#1D2A42',
                    600: '#2A3B58',
                },
                canvas: {
                    DEFAULT: '#F4F6F8',
                    raised: '#FFFFFF',
                    line: '#E2E6EB',
                },
                emerald: {
                    50: '#EAF6F1',
                    600: '#0F7A5C',
                    700: '#0B5F47',
                },
                gold: {
                    500: '#A9821E',
                },
                danger: {
                    50: '#FDECEC',
                    600: '#B3261E',
                },
            },
            fontFamily: {
                display: ['"Source Serif 4"', 'ui-serif', 'Georgia', 'serif'],
                sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
                mono: ['"IBM Plex Mono"', 'ui-monospace', 'SFMono-Regular', 'monospace'],
            },
        },
    },
    plugins: [],
};
