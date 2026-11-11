import { useState, type InputHTMLAttributes, type ReactNode } from 'react';
import type { Said } from './useOp';
import * as css from './operator.css';

export function SaidLine({ said }: { said: Said }) {
  if (!said) return null;
  return (
    <p role="status" className={said.refused ? css.refused : css.said}>
      {said.text}
    </p>
  );
}

export function Card({ title, label, children }: { title: string; label: string; children: ReactNode }) {
  return (
    <section className={css.card} aria-label={label}>
      <h2 className={css.heading}>{title}</h2>
      {children}
    </section>
  );
}

export function Field({ label, ...rest }: InputHTMLAttributes<HTMLInputElement> & { label: string }) {
  return (
    <label className={css.field}>
      <span>{label}</span>
      <input className={css.input} {...rest} />
    </label>
  );
}

/**
 * A row's revoke: the first press asks for the note the change records,
 * the second sends it. Nothing is revoked without a note.
 */
export function RevokeWithNote({ what, busy, onRevoke }: { what: string; busy: boolean; onRevoke: (note: string) => void }) {
  const [asking, setAsking] = useState(false);
  const [note, setNote] = useState('');
  if (!asking)
    return (
      <button type="button" className={css.button} disabled={busy} onClick={() => setAsking(true)}>
        Revoke
      </button>
    );
  return (
    <form
      className={css.inline}
      aria-label={`Revoke ${what}`}
      onSubmit={(e) => {
        e.preventDefault();
        if (note.trim()) onRevoke(note.trim());
      }}
    >
      <input className={css.input} aria-label={`Why revoke ${what}`} placeholder="Why (recorded)" value={note} onChange={(e) => setNote(e.target.value)} />
      <button type="submit" className={css.danger} disabled={busy || !note.trim()}>
        Revoke {what}
      </button>
      <button
        type="button"
        className={css.button}
        onClick={() => {
          setAsking(false);
          setNote('');
        }}
      >
        Cancel
      </button>
    </form>
  );
}
