import { useState } from 'react';
import type { Adapter } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';
import { TopBar } from '../../components/TopBar';

export interface ConnectionsProps {
  residentName: string;
  adapters: Adapter[];
  // The token just issued, shown once and never again.
  issued?: { adapter: string; token: string } | null;
  onRegister?: (adapter: string, role: string) => void;
  onRevoke?: (adapter: string) => void;
  onDismissToken?: () => void;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const row = { display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' } as const;

// The roles an adapter's token holds (spec §8, xenia #11), in words.
const roles: Array<{ id: string; words: (name: string) => string }> = [
  { id: 'brain', words: (n) => `speaks as ${n}, with ${n}'s memory (Claude Code)` },
  { id: 'reader', words: (n) => `reads inboxes and sends approved replies, never as ${n}` },
  { id: 'worker', words: (n) => `does work for ${n}, never as ${n}` },
];

// Connections (spec §10's "agreement and custody", the adapters part):
// the runtimes and hands that hold a token for the resident. A token is
// shown once, when it is issued; registering a name again replaces its
// token; revoking stops it at once.
export function Connections({ residentName, adapters, issued = null, onRegister, onRevoke, onDismissToken }: ConnectionsProps) {
  const [name, setName] = useState('');
  const [role, setRole] = useState('reader');
  const live = adapters.filter((a) => !a.revoked_at);
  const gone = adapters.filter((a) => a.revoked_at);
  const valid = /^[a-z0-9][a-z0-9_-]{0,31}$/.test(name);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="Connections" line={`What holds a token for ${residentName}`} />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        {issued ? (
          <Card title={`The token for ${issued.adapter}`}>
            <p style={{ margin: 0, fontSize: 15 }}>
              Copy it now: it is shown this once. Keep it where the runtime reads it (a file only you can read), never in a repository or a chat.
            </p>
            <code
              aria-label="Token"
              style={{ display: 'block', padding: 'var(--space-2)', background: 'var(--surface-sunken)', borderRadius: 'var(--radius-sm)', fontFamily: 'var(--font-mono)', fontSize: 13, overflowWrap: 'anywhere' }}
            >
              {issued.token}
            </code>
            <div style={row}>
              <Button onClick={() => void navigator.clipboard?.writeText(issued.token)}>Copy</Button>
              {onDismissToken ? (
                <Button variant="quiet" onClick={onDismissToken}>
                  I've saved it
                </Button>
              ) : null}
            </div>
          </Card>
        ) : null}
        <Card title="Connected">
          {live.length === 0 ? (
            <p style={muted}>Nothing holds a token yet.</p>
          ) : (
            <ul aria-label="Connected" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              {live.map((a) => (
                <AdapterRow key={a.adapter} residentName={residentName} adapter={a} onRevoke={onRevoke} />
              ))}
            </ul>
          )}
        </Card>
        {onRegister ? (
          <Card title="Connect something new">
            <form
              aria-label="Connect something new"
              onSubmit={(e) => {
                e.preventDefault();
                if (valid) onRegister(name, role);
                setName('');
              }}
              style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}
            >
              <Field label="Name (lowercase, e.g. scrape)" value={name} onChange={(e) => setName(e.target.value.toLowerCase())} />
              <fieldset style={{ border: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
                <legend style={{ fontSize: 13, color: 'var(--ink-muted)', fontWeight: 500 }}>Role</legend>
                {roles.map((r) => (
                  <label key={r.id} style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', fontSize: 15 }}>
                    <input type="radio" name="role" value={r.id} checked={role === r.id} onChange={() => setRole(r.id)} />
                    <span>
                      <strong style={{ fontWeight: 600 }}>{r.id}</strong> <span style={{ color: 'var(--ink-muted)' }}>{r.words(residentName)}</span>
                    </span>
                  </label>
                ))}
              </fieldset>
              <div>
                <Button variant="primary" type="submit" disabled={!valid}>
                  Issue a token
                </Button>
              </div>
            </form>
          </Card>
        ) : null}
        {gone.length > 0 ? (
          <Card title="Revoked">
            <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 14, color: 'var(--ink-muted)' }}>
              {gone.map((a) => (
                <li key={a.adapter}>
                  {a.adapter} ({a.role}) · revoked {a.revoked_at?.slice(0, 10)}
                </li>
              ))}
            </ul>
          </Card>
        ) : null}
      </main>
    </div>
  );
}

function AdapterRow({ residentName, adapter: a, onRevoke }: { residentName: string; adapter: Adapter; onRevoke?: (adapter: string) => void }) {
  const [confirming, setConfirming] = useState(false);
  const words = roles.find((r) => r.id === a.role)?.words(residentName) ?? a.role;
  return (
    <li style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 'var(--space-2)', fontSize: 15 }}>
      <span>
        <strong style={{ fontWeight: 600 }}>{a.adapter}</strong> <span style={{ color: 'var(--ink-muted)' }}>· {a.role}: {words} · since {a.registered_at.slice(0, 10)}</span>
      </span>
      {onRevoke ? (
        <Button variant="quiet" onClick={() => (confirming ? onRevoke(a.adapter) : setConfirming(true))} onBlur={() => setConfirming(false)}>
          {confirming ? `Revoke ${a.adapter}` : 'Revoke'}
        </Button>
      ) : null}
    </li>
  );
}
