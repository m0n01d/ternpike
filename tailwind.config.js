/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{elm,js,html}', './index.html'],
  theme: {
    extend: {
      colors: {
        ink:     '#1e2818',
        forest: {
          DEFAULT: '#2d3a22',
          mid:     '#3d4e2e',
          light:   '#4a5e3a',
        },
        moss:      '#6b7c58',
        rust: {
          DEFAULT: '#b85c38',
          light:   '#cc7050',
        },
        tan:       '#d4c9a8',
        cream:     '#f2ede3',
        parchment: '#faf7f0',
        muted:     '#8a8a78',
      },
      fontFamily: {
        display: ['Playfair Display', 'Georgia', 'serif'],
        mono:    ['DM Mono', 'ui-monospace', 'monospace'],
        body:    ['Crimson Pro', 'Georgia', 'serif'],
      },
      fontSize: {
        label:    ['0.625rem',    { letterSpacing: '0.2em',  lineHeight: '1' }],
        'mono-sm':['0.6875rem',   { letterSpacing: '0.15em', lineHeight: '1.4' }],
        'mono-md':['0.8125rem',   { letterSpacing: '0.12em', lineHeight: '1.5' }],
      },
      backgroundImage: {
        topo:   "url(\"data:image/svg+xml,%3Csvg width='100' height='100' viewBox='0 0 100 100' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' stroke='%234a5e3a' stroke-width='0.5' opacity='0.15'%3E%3Cellipse cx='50' cy='50' rx='15' ry='9'/%3E%3Cellipse cx='50' cy='50' rx='28' ry='17'/%3E%3Cellipse cx='50' cy='50' rx='40' ry='25'/%3E%3C/g%3E%3C/svg%3E\")",
        ruled:  "repeating-linear-gradient(to bottom, transparent 0px, transparent 39px, rgb(74 94 58 / 0.07) 39px, rgb(74 94 58 / 0.07) 40px)",
        margin: "linear-gradient(to right, transparent 71px, rgb(184 92 56 / 0.18) 71px, rgb(184 92 56 / 0.18) 72px, transparent 72px)",
      },
      borderRadius: {
        card:  '16px',
        panel: '20px',
        sheet: '24px',
      },
      boxShadow: {
        card:  '0 4px 24px rgb(45 58 34 / 0.10)',
        panel: '0 8px 40px rgb(45 58 34 / 0.12)',
        lift:  '0 12px 48px rgb(45 58 34 / 0.20)',
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
