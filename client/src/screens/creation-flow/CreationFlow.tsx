import { useState } from 'react';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

export type Begin =
  | { mode: 'new'; name: string; slug: string; key: string | null }
  | { mode: 'bring'; url: string; name: string | null; slug: string | null; key: string | null };

export interface CreationFlowProps {
  // Whether the account already holds an OpenRouter key; without one the
  // flow asks for it, because nobody can answer until there is one.
  hasKey: boolean;
  busy?: boolean;
  said?: string | null;
  onBegin?: (begin: Begin) => void;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;

// A name's address: lower case, letters, digits and dashes, starting with
// a letter, as the server's slug rule wants.
export function slugOf(name: string): string {
  const s = name
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^[^a-z]+/, '')
    .replace(/-+$/, '')
    .slice(0, 40);
  return s.length >= 2 ? s : '';
}

// A stopgap short door (F3, design/mvp.md item 3): new or brought, a key
// if none, and in. The witness's decision is the full nine-gift flow, with
// a pre-filled head start on the same screens; it replaces this
// (screens/creation-flow.md).
export function CreationFlow({ hasKey, busy = false, said = null, onBegin }: CreationFlowProps) {
  const [mode, setMode] = useState<'new' | 'bring' | null>(null);
  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [key, setKey] = useState('');
  const slug = slugOf(name);
  const keyReady = hasKey || key.trim() !== '';
  const ready = keyReady && (mode === 'new' ? slug !== '' : mode === 'bring' ? url.trim().startsWith('https://') : false);

  return (
    <div style={{ maxWidth: 480, margin: 'var(--space-6) auto', padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
      <h1 style={{ margin: 0, fontSize: 28, lineHeight: '34px', fontWeight: 600 }}>Who's coming in?</h1>
      <div role="group" aria-label="Begin" style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        <Button variant={mode === 'new' ? 'primary' : 'quiet'} aria-pressed={mode === 'new'} onClick={() => setMode('new')}>
          Someone new
        </Button>
        <Button variant={mode === 'bring' ? 'primary' : 'quiet'} aria-pressed={mode === 'bring'} onClick={() => setMode('bring')}>
          Someone I'm bringing
        </Button>
      </div>
      {mode ? (
        <form
          aria-label={mode === 'new' ? 'Someone new' : 'Someone I am bringing'}
          onSubmit={(event) => {
            event.preventDefault();
            if (!ready) return;
            const k = hasKey ? null : key.trim();
            if (mode === 'new') onBegin?.({ mode, name: name.trim(), slug, key: k });
            else onBegin?.({ mode, url: url.trim(), name: name.trim() || null, slug: slug || null, key: k });
          }}
          style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}
        >
          {mode === 'bring' ? (
            <Card title="Their repository">
              <p style={muted}>
                The git repository their life is kept in, as an https address. A private one can carry a token in the address; it's used to read and never kept.
              </p>
              <Field label="Repository address" value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://github.com/you/them" autoComplete="off" />
            </Card>
          ) : null}
          <Card title={mode === 'new' ? 'Their name' : 'Their name, if the repository has none'}>
            <Field label="Name" value={name} onChange={(e) => setName(e.target.value)} autoComplete="off" />
            {slug ? <p style={muted}>Their address here: {slug}</p> : null}
          </Card>
          {hasKey ? null : (
            <Card title="Your OpenRouter key">
              <p style={muted}>Every conversation is paid through your own OpenRouter key. It's stored encrypted and shown to nobody again.</p>
              <Field label="OpenRouter key" type="password" value={key} onChange={(e) => setKey(e.target.value)} autoComplete="off" />
            </Card>
          )}
          <Button variant="primary" type="submit" disabled={busy || !ready}>
            {mode === 'new' ? 'Begin' : 'Bring them in'}
          </Button>
          <p style={muted}>Who they are, your agreement and the rest come after, as you settle in.</p>
        </form>
      ) : null}
      {said ? (
        <p role="status" style={{ margin: 0, fontSize: 15, color: 'var(--danger)' }}>
          {said}
        </p>
      ) : null}
    </div>
  );
}
