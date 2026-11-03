import { useState } from 'react';

// A time of day as "HH:MM", chosen by hour and minute.
//
// Not an <input type="time">: on iPhone Safari a cleared time input shows a
// time on its wheel, and accepting it without scrolling fires no change, so
// the field looks set while its value is empty. The check-in form cleared
// its time after the first add and its button stayed disabled for the
// second (the witness, 2026-11-03). A <select> always reports its choice.
const HOURS = Array.from({ length: 24 }, (_, h) => String(h).padStart(2, '0'));
const STEP = Array.from({ length: 12 }, (_, i) => String(i * 5).padStart(2, '0'));

const select = {
  minHeight: 'var(--control-h)',
  padding: '0 var(--space-2)',
  borderRadius: 'var(--radius-md)',
  border: '1px solid var(--hairline)',
  background: 'var(--surface-raised)',
  color: 'var(--ink)',
  fontFamily: 'var(--font-sans)',
  fontSize: 15,
} as const;

function split(value: string): [string, string] {
  const m = /^(\d\d):(\d\d)$/.exec(value);
  return m ? [m[1], m[2]] : ['', ''];
}

export function TimeField({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  const [hour, setHour] = useState(split(value)[0]);
  const [minute, setMinute] = useState(split(value)[1]);

  // A value set from outside (a reset to '', a saved time) is shown as is:
  // state adjusted while rendering, React's way for a prop that moves.
  const [seen, setSeen] = useState(value);
  if (value !== seen) {
    setSeen(value);
    const [h, m] = split(value);
    if (value === '' || (h && m)) {
      setHour(h);
      setMinute(m);
    }
  }

  // A saved minute off the five-minute steps is kept as an option of its own.
  const minutes = minute && !STEP.includes(minute) ? [...STEP, minute].sort() : STEP;

  const choose = (h: string, m: string) => {
    setHour(h);
    setMinute(m);
    onChange(h && m ? `${h}:${m}` : '');
  };

  return (
    <div
      role="group"
      aria-label={label}
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--space-1)',
        fontSize: 13,
      }}
    >
      <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>{label}</span>
      <span style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-1)' }}>
        <select aria-label={`${label} hour`} value={hour} onChange={(e) => choose(e.target.value, minute || (e.target.value ? '00' : ''))} style={select}>
          <option value="">--</option>
          {HOURS.map((h) => (
            <option key={h} value={h}>
              {h}
            </option>
          ))}
        </select>
        <span aria-hidden="true">:</span>
        <select aria-label={`${label} minute`} value={minute} onChange={(e) => choose(hour, e.target.value)} style={select}>
          <option value="">--</option>
          {minutes.map((m) => (
            <option key={m} value={m}>
              {m}
            </option>
          ))}
        </select>
      </span>
    </div>
  );
}
