import { useState, type InputHTMLAttributes, type ReactNode, type TextareaHTMLAttributes } from 'react';
import * as css from './settings.css';

export function Said({ said }: { said: { text: string; refused: boolean } | null }) {
  if (!said) return null;
  return (
    <p role="status" className={said.refused ? css.refused : css.said}>
      {said.text}
    </p>
  );
}

export function Card({ title, children, witness = false, label }: { title: string; children: ReactNode; witness?: boolean; label?: string }) {
  return (
    <section className={witness ? css.cardWitness : css.card} aria-label={label ?? title}>
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

export function TextArea({
  label,
  mono = false,
  ...rest
}: TextareaHTMLAttributes<HTMLTextAreaElement> & {
  label: string;
  mono?: boolean;
}) {
  return (
    <label className={css.field}>
      <span>{label}</span>
      <textarea className={mono ? css.textareaMono : css.textarea} rows={3} {...rest} />
    </label>
  );
}

export function Select({ label, value, onChange, children }: { label: string; value: string; onChange: (v: string) => void; children: ReactNode }) {
  return (
    <label className={css.field}>
      <span>{label}</span>
      <select className={css.input} value={value} onChange={(e) => onChange(e.target.value)}>
        {children}
      </select>
    </label>
  );
}

/** A destructive button that asks once more on the second tap, and forgets when focus leaves. */
export function Confirm({ label, confirm, onConfirm, disabled }: { label: string; confirm: string; onConfirm: () => void; disabled?: boolean }) {
  const [asking, setAsking] = useState(false);
  return (
    <button
      type="button"
      className={css.quiet}
      disabled={disabled}
      onClick={() => {
        if (!asking) return setAsking(true);
        setAsking(false);
        onConfirm();
      }}
      onBlur={() => setAsking(false)}
    >
      {asking ? confirm : label}
    </button>
  );
}
