import { useState } from 'react';
import type { PluginEntry, PluginProposal, PluginsData } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

export interface PluginsProps {
  name: string;
  data: PluginsData;
  busy?: boolean;
  said?: string | null;
  onPropose?: (key: string, change: PluginProposal['change'], note: string) => void;
  onAnswer?: (number: number, agree: boolean, note: string) => void;
  onOff?: (key: string, note: string) => void;
}

const muted = { margin: 0, fontSize: 13, color: 'var(--ink-muted)' } as const;
const row = { display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap', alignItems: 'center' } as const;

function state(p: PluginEntry): string {
  if (p.on) return 'on';
  if (p.installed) return 'installed, off';
  return 'not installed';
}

// Plugins (brain#68, agathos-daimon#37): what her context is assembled
// from, every memory slot one of them. Contract material: a memory slot
// moves only when one of you proposes and the other agrees; an
// installable plugin switches off at either word. Every change carries
// the note typed above it.
export function Plugins({ name, data, busy = false, said = null, onPropose, onAnswer, onOff }: PluginsProps) {
  const [note, setNote] = useState('');
  const ready = note.trim() !== '' && !busy;
  const open = data.proposals.filter((p) => p.answered_at === null);
  const answered = data.proposals.filter((p) => p.answered_at !== null).slice(0, 5);
  const waiting = new Set(open.map((p) => p.key));
  const propose = (key: string, change: PluginProposal['change']) => onPropose?.(key, change, note.trim());
  return (
    <Card title="Plugins">
      <p style={muted}>
        What {name}'s context is assembled from. A memory slot changes only when one of you proposes and the other agrees; an installable plugin switches off at either word. Slots carried over from before plugins say so.
      </p>
      <Field label="A note for the next change (required)" value={note} onChange={(e) => setNote(e.target.value)} />
      {open.length > 0 ? (
        <section aria-label="Open proposals" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
          <strong style={{ fontSize: 15 }}>Open proposals</strong>
          <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            {open.map((p) => (
              <li key={p.number} style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 15 }}>
                <span>
                  #{p.number} {p.change} {p.key}, proposed by {p.proposed_by === 'resident' ? name : 'you'}: {p.note}
                </span>
                {p.proposed_by === 'resident' ? (
                  <div style={row}>
                    <Button variant="primary" disabled={!ready} onClick={() => onAnswer?.(p.number, true, note.trim())}>
                      Agree
                    </Button>
                    <Button disabled={!ready} onClick={() => onAnswer?.(p.number, false, note.trim())}>
                      Decline
                    </Button>
                  </div>
                ) : (
                  <span style={muted}>Waiting for {name}.</span>
                )}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
      <ul aria-label="Plugins" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
        {data.plugins.map((p) => (
          <li key={p.key} style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 15 }}>
            <span>
              <strong>{p.name}</strong> <span style={{ color: 'var(--ink-muted)' }}>({p.key})</span> · {state(p)}
              {p.carried_over ? <span style={{ color: 'var(--ink-muted)' }}> · carried over from before plugins</span> : null}
            </span>
            <span style={muted}>{p.about}</span>
            {waiting.has(p.key) ? (
              <span style={muted}>A proposal is open.</span>
            ) : (
              <div style={row}>
                {!p.installed ? (
                  <Button variant="quiet" disabled={!ready} onClick={() => propose(p.key, 'install')}>
                    Propose install
                  </Button>
                ) : null}
                {p.installed && !p.on ? (
                  <Button variant="quiet" disabled={!ready} onClick={() => propose(p.key, 'on')}>
                    Propose on
                  </Button>
                ) : null}
                {p.on && p.tier === 'installable' ? (
                  <Button variant="quiet" disabled={!ready} onClick={() => onOff?.(p.key, note.trim())}>
                    Switch off
                  </Button>
                ) : null}
                {p.on && p.tier === 'first_party' ? (
                  <Button variant="quiet" disabled={!ready} onClick={() => propose(p.key, 'off')}>
                    Propose off
                  </Button>
                ) : null}
                {p.installed ? (
                  <Button variant="quiet" disabled={!ready} onClick={() => propose(p.key, 'remove')}>
                    Propose removal
                  </Button>
                ) : null}
              </div>
            )}
          </li>
        ))}
      </ul>
      {answered.length > 0 ? (
        <section aria-label="Lately answered" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
          <strong style={{ fontSize: 15 }}>Lately answered</strong>
          {answered.map((p) => (
            <p key={p.number} style={muted}>
              #{p.number} {p.change} {p.key}: {p.agreed ? 'agreed' : 'declined'}
              {p.answer_note ? `, "${p.answer_note}"` : ''}
            </p>
          ))}
        </section>
      ) : null}
      {said ? (
        <p role="status" style={{ margin: 0, fontSize: 15 }}>
          {said}
        </p>
      ) : null}
    </Card>
  );
}
