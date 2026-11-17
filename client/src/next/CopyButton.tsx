import { useEffect, useState } from 'react';

type State = 'idle' | 'copied' | 'refused';

/**
 * A copy button that says what happened: "Copied" for two seconds after
 * the text reached the clipboard, or that it could not, so the reader
 * selects it by hand (the witness, 2026-11-17: "our copy buttons need
 * feedback"). The label is announced politely as it changes.
 */
export function CopyButton({ text, label = 'Copy', className }: { text: string; label?: string; className?: string }) {
  const [state, setState] = useState<State>('idle');

  useEffect(() => {
    if (state === 'idle') return undefined;
    const t = setTimeout(() => setState('idle'), 2000);
    return () => clearTimeout(t);
  }, [state]);

  const copy = () => {
    const clip = typeof navigator === 'undefined' ? undefined : navigator.clipboard;
    if (!clip) {
      setState('refused');
      return;
    }
    clip.writeText(text).then(
      () => setState('copied'),
      () => setState('refused'),
    );
  };

  return (
    <button type="button" className={className} onClick={copy} aria-live="polite">
      {state === 'copied' ? 'Copied' : state === 'refused' ? "Couldn't copy; select it" : label}
    </button>
  );
}
