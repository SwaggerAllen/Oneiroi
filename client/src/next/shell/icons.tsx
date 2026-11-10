// The shell's icons: one stroke weight, currentColor, decorative to
// assistive technology (every button carries its own label).

const base = { width: 22, height: 22, viewBox: '0 0 24 24', fill: 'none', 'aria-hidden': true } as const;
const line = { stroke: 'currentColor', strokeWidth: 1.6, strokeLinejoin: 'round', strokeLinecap: 'round' } as const;

export const ChatIcon = () => (
  <svg {...base}>
    <path d="M4 5h16v11H9l-5 4z" {...line} />
  </svg>
);
export const TimeIcon = () => (
  <svg {...base}>
    <path d="M15 4a8 8 0 1 0 5 13A7 7 0 0 1 15 4z" {...line} />
  </svg>
);
export const RecordsIcon = () => (
  <svg {...base}>
    <path d="M3 7h7l2 2h9v10H3z" {...line} />
  </svg>
);
export const SoulIcon = () => (
  <svg {...base}>
    <path d="M12 3c3 4 5 6 5 10a5 5 0 0 1-10 0c0-4 2-6 5-10z" {...line} />
  </svg>
);
export const SearchIcon = () => (
  <svg {...base} width={20} height={20}>
    <circle cx="11" cy="11" r="6.5" {...line} />
    <path d="M16 16l4.5 4.5" {...line} />
  </svg>
);
export const BellIcon = () => (
  <svg {...base}>
    <path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z M10 20a2 2 0 0 0 4 0" {...line} strokeWidth={1.5} />
  </svg>
);
export const GearIcon = () => (
  <svg {...base} width={21} height={21}>
    <circle cx="12" cy="12" r="3" {...line} strokeWidth={1.5} />
    <path
      {...line}
      strokeWidth={1.5}
      d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"
    />
  </svg>
);
export const ChevronIcon = () => (
  <svg width={11} height={11} viewBox="0 0 12 12" aria-hidden>
    <path d="M2 4l4 4 4-4" fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" />
  </svg>
);
