/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        sans: [
          'Inter',
          '-apple-system',
          'BlinkMacSystemFont',
          '"SF Pro Display"',
          '"Segoe UI"',
          'Roboto',
          'sans-serif',
        ],
      },
      colors: {
        // Single source of truth for the brand blue. Mobile uses #007AFF;
        // the web design's blue is a touch deeper, so it lives here alone —
        // change these two values to re-tint the whole dashboard.
        brand: {
          50: '#F0F6FF',
          100: '#E3EEFF',
          200: '#C7DDFF',
          500: '#0A6CFF',
          600: '#0057DB',
          700: '#0046B0',
        },
        ink: {
          DEFAULT: '#101828',
          secondary: '#667085',
          muted: '#98A2B3',
        },
        surface: {
          page: '#FFFFFF',
          panel: '#F5F7F9',
          raised: '#FFFFFF',
          header: '#F1F4F7',
          hover: '#FAFBFC',
        },
        line: {
          DEFAULT: '#EDF0F3',
          strong: '#E1E6EB',
        },
        state: {
          good: '#12B76A',
          goodSoft: '#E7F8F0',
          warn: '#F79009',
          warnSoft: '#FEF4E6',
          bad: '#F04438',
          badSoft: '#FEECEB',
          info: '#0A6CFF',
          infoSoft: '#E3EEFF',
        },
      },
      borderRadius: {
        card: '14px',
        control: '10px',
      },
      boxShadow: {
        card: '0 1px 2px 0 rgba(16, 24, 40, 0.04)',
        pop: '0 8px 24px -4px rgba(16, 24, 40, 0.12), 0 2px 6px -2px rgba(16, 24, 40, 0.06)',
      },
      fontSize: {
        '2xs': ['11px', '16px'],
      },
    },
  },
  plugins: [],
};
