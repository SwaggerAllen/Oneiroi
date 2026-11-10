import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { derive, type Seeds } from '../theme/derive';
import { readOverride, writeOverride } from '../theme/useResidentTheme';
import * as css from './overlays.css';

const FIELDS: Array<{ key: keyof Seeds; label: (name: string) => string }> = [
  { key: 'ground', label: () => 'The ground' },
  { key: 'resident', label: (name) => `${name}'s colour` },
  { key: 'witness', label: () => 'Your colour' },
];

/**
 * Her theme (seshat#56; theming-notes.md): the witness owns the three
 * seeds, so he sets them here, worn on screen as he picks, with the same
 * readability checks the server runs. Saved to THEME.md for every
 * device, or kept on this device only.
 */
export function ThemeSheet() {
  const { id, name } = useSubject();
  const queries = useQueryClient();
  const setTryOn = useShell((s) => s.setTryOn);
  const theme = useQuery({ queryKey: ['resident', id, 'theme'], queryFn: () => api.theme(id) });
  const [seeds, setSeedsLocal] = useState<Seeds | null>(null);
  const [note, setNote] = useState('');
  const [device, setDevice] = useState(() => readOverride(id) !== null);

  useEffect(() => {
    if (!seeds && theme.data) setSeedsLocal(readOverride(id) ?? theme.data.seeds);
  }, [theme.data, seeds, id]);
  // Worn while the sheet is open; taken off when it closes.
  useEffect(() => {
    if (seeds) setTryOn(seeds);
  }, [seeds, setTryOn]);
  useEffect(() => () => setTryOn(null), [setTryOn]);

  const save = useMutation({
    mutationFn: async () => {
      if (!seeds) return;
      if (device) {
        writeOverride(id, seeds);
      } else {
        writeOverride(id, null);
        await api.setTheme(id, seeds, note.trim() || undefined);
      }
    },
    onSuccess: () => {
      void queries.invalidateQueries({ queryKey: ['device', 'theme-override', id] });
      void queries.invalidateQueries({ queryKey: ['resident', id, 'theme'] });
    },
  });

  if (!seeds) return <p className={css.note}>Reading her theme…</p>;
  const derived = derive(seeds);
  const failing = derived.checks.filter((c) => !c.passed);

  return (
    <div className={css.stack}>
      <p className={css.note}>
        {theme.data?.source === 'file' ? `From ${name}'s THEME.md.` : 'The house colours, until you or she choose others.'} You see it as you pick.
      </p>
      {FIELDS.map((f) => (
        <label key={f.key} className={css.colorRow}>
          <span>{f.label(name)}</span>
          <span className={css.colorPick}>
            <input
              id={`theme-${f.key}`}
              type="color"
              value={seeds[f.key]}
              onChange={(e) => setSeedsLocal({ ...seeds, [f.key]: e.target.value })}
              aria-label={f.label(name)}
            />
            <code className={css.since}>{seeds[f.key]}</code>
          </span>
        </label>
      ))}
      <h3 className={css.heading}>READABLE? {derived.ok ? 'YES' : `NOT YET · ${failing.length}`}</h3>
      <ul className={css.list}>
        {derived.checks.map((c) => (
          <li key={c.name} style={{ opacity: c.passed ? 0.7 : 1 }}>
            {c.passed ? '✓' : '✗'} {c.name}: {c.value.toFixed(2)} (needs {c.needs})
          </li>
        ))}
      </ul>
      <label className={css.colorRow}>
        <span>Just on this device</span>
        <input id="theme-device" type="checkbox" checked={device} onChange={(e) => setDevice(e.target.checked)} />
      </label>
      {!device && (
        <input id="theme-note" className={css.answer} value={note} onChange={(e) => setNote(e.target.value)} placeholder="A note in THEME.md (optional)" aria-label="A note in THEME.md" />
      )}
      <button type="button" className={css.primary} disabled={!derived.ok || save.isPending} onClick={() => save.mutate()}>
        {device ? 'Keep on this device' : `Save to ${name}'s THEME.md`}
      </button>
      {theme.data && (
        <button type="button" className={css.secondary} onClick={() => setSeedsLocal(theme.data.seeds)}>
          Back to THEME.md
        </button>
      )}
      {save.isSuccess && <p className={css.note}>Kept.</p>}
      {save.error && <p className={css.note}>{(save.error as Error).message}</p>}
    </div>
  );
}
