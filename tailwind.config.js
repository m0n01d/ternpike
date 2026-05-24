/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{elm,js,html}', './index.html'],
  darkMode: 'class',
  theme: {
    extend: {
      fontSize: {
        label:     ['0.625rem',  { letterSpacing: '0.2em',  lineHeight: '1' }],
        'mono-sm': ['0.6875rem', { letterSpacing: '0.15em', lineHeight: '1.4' }],
        'mono-md': ['0.8125rem', { letterSpacing: '0.12em', lineHeight: '1.5' }],
      },
      backgroundImage: {
        topo:   "url(\"data:image/svg+xml,%3Csvg width='100' height='100' viewBox='0 0 100 100' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%234a5e3a' stroke-width='0.5' opacity='0.15'%3E%3Cellipse cx='50' cy='50' rx='15' ry='9'/%3E%3Cellipse cx='50' cy='50' rx='28' ry='17'/%3E%3Cellipse cx='50' cy='50' rx='40' ry='25'/%3E%3C/g%3E%3C/svg%3E\")",
        ruled:  "repeating-linear-gradient(to bottom, transparent 0px, transparent 39px, rgb(74 94 58 / 0.07) 39px, rgb(74 94 58 / 0.07) 40px)",
        margin: "linear-gradient(to right, transparent 71px, rgb(184 92 56 / 0.18) 71px, rgb(184 92 56 / 0.18) 72px, transparent 72px)",
      },
      keyframes: {
        soar: {
          '0%, 100%': { transform: 'translateY(0) rotate(-2deg)' },
          '35%':      { transform: 'translateY(-14px) rotate(1.5deg)' },
          '70%':      { transform: 'translateY(-8px) rotate(-1deg)' },
        },
        'fly-across': {
          '0%':   { transform: 'translateX(-80px) translateY(10px) scaleX(1)' },
          '48%':  { transform: 'translateX(20px) translateY(-24px) scaleX(1)' },
          '52%':  { transform: 'translateX(30px) translateY(-26px) scaleX(-1)' },
          '100%': { transform: 'translateX(-70px) translateY(10px) scaleX(-1)' },
        },
        'fade-up': {
          from: { opacity: '0', transform: 'translateY(20px)' },
          to:   { opacity: '1', transform: 'translateY(0)' },
        },
      },
      animation: {
        soar:           'soar 7s ease-in-out infinite',
        'fly-across':   'fly-across 5s ease-in-out infinite',
        'fade-up':      'fade-up 0.9s ease both',
        'fade-up-slow': 'fade-up 0.9s 0.3s ease both',
      },
    },
  },
  plugins: [],
}
