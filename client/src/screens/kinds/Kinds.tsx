import { useState } from 'react';
import type { KindDefinition, KindEntry, KindsData } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

export interface KindsProps {
  name: string;
  data: KindsData;
  busy?: boolean;
  said?: string | null;
  onDefine?: (definition: KindDefinition) => void;
  onGate?: (kind: string, approvable: boolean, note: string) => void;
  onAnswer?: (number: number, agree: boolean, note: string) => void;
}

const muted = { margin: 0, fontSize: 13, color: 'var(--ink-muted)' } as const;
const row = { display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap', alignItems: 'center' } as const;
const list = { margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' } as const;
const kindName = /^[a-z][a-z0-9-]{1,39}$/;

function line(k: KindEntry, name: string): string {
  const where = k.folder ? `${k.folder}/` : 'at the root';
  const gate = k.approvable ? 'waits on you at review' : 'no gate';
  const whose = k.own ? ` · ${name}'s, defined by ${k.created_by === 'witness' ? 'you' : name}` : '';
  return `${where} · ${gate}${whose}`;
}

// Kinds (seshat#51): every kind of document her library holds, the
// system's and her own. A system kind's gate goes on at either word; off
// is a proposal the other answers. A kind of hers is defined here or by
// her, its definition written into its folder as kind.json.
export function Kinds({ name, data, busy = false, said = null, onDefine, onGate, onAnswer }: KindsProps) {
  const [note, setNote] = useState('');
  const [kind, setKind] = useState('');
  const [label, setLabel] = useState('');
  const [approvable, setApprovable] = useState(false);
  const [cites, setCites] = useState(false);
  const [ask, setAsk] = useState('');
  const noted = note.trim() !== '' && !busy;
  const open = data.proposals.filter((p) => p.answered_at === null);
  const answered = data.proposals.filter((p) => p.answered_at !== null).slice(0, 5);
  const waiting = new Set(open.map((p) => p.kind));
  const nameOk = kindName.test(kind) && !data.kinds.some((k) => k.kind === kind && !k.own);
  const define = () => {
    onDefine?.({ kind, label: label.trim() || undefined, cites, approvable, ask: approvable && ask.trim() ? ask.trim() : undefined, note: note.trim() || undefined });
    setKind('');
    setLabel('');
    setApprovable(false);
    setCites(false);
    setAsk('');
  };
  return (
    <Card title="Kinds">
      <p style={muted}>
        The kinds of document {name}'s library holds. A gate means a document of that kind at status: review waits on you. A gate goes on at either word; off is a proposal the other answers.
      </p>
      <Field label="A note for the next change" value={note} onChange={(e) => setNote(e.target.value)} />
      {open.length > 0 ? (
        <section aria-label="Open gate proposals" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
          <strong style={{ fontSize: 15 }}>Open gate proposals</strong>
          <ul style={list}>
            {open.map((p) => (
              <li key={p.number} style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 15 }}>
                <span>
                  #{p.number} the {p.kind} gate {p.approvable ? 'on' : 'off'}, proposed by {p.proposed_by === 'resident' ? name : 'you'}: {p.note}
                </span>
                {p.proposed_by === 'resident' ? (
                  <div style={row}>
                    <Button variant="primary" disabled={!noted} onClick={() => onAnswer?.(p.number, true, note.trim())}>
                      Agree
                    </Button>
                    <Button disabled={!noted} onClick={() => onAnswer?.(p.number, false, note.trim())}>
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
      <ul aria-label="Kinds" style={list}>
        {data.kinds.map((k) => (
          <li key={k.kind} style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 15 }}>
            <span>
              <strong>{k.label}</strong> <span style={{ color: 'var(--ink-muted)' }}>({k.kind})</span>
            </span>
            <span style={muted}>{line(k, name)}</span>
            {k.gated ? (
              waiting.has(k.kind) ? (
                <span style={muted}>A gate proposal is open.</span>
              ) : (
                <div style={row}>
                  {k.approvable ? (
                    <Button variant="quiet" disabled={!noted} onClick={() => onGate?.(k.kind, false, note.trim())}>
                      Propose gate off
                    </Button>
                  ) : (
                    <Button variant="quiet" disabled={busy} onClick={() => onGate?.(k.kind, true, note.trim())}>
                      Gate on
                    </Button>
                  )}
                </div>
              )
            ) : null}
          </li>
        ))}
      </ul>
      <form
        aria-label="Define a kind"
        onSubmit={(e) => {
          e.preventDefault();
          if (nameOk && !busy) define();
        }}
        style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}
      >
        <strong style={{ fontSize: 15 }}>A kind of {name}'s</strong>
        <p style={muted}>Its name is its folder: lowercase letters, digits and -. It is hers to write; to rewrite one, define it again under its name.</p>
        <Field label="Name" value={kind} onChange={(e) => setKind(e.target.value.trim())} />
        <Field label="Label" value={label} onChange={(e) => setLabel(e.target.value)} />
        <label style={{ ...row, fontSize: 15 }}>
          <input type="checkbox" checked={cites} onChange={(e) => setCites(e.target.checked)} /> Its citations make edges
        </label>
        <label style={{ ...row, fontSize: 15 }}>
          <input type="checkbox" checked={approvable} onChange={(e) => setApprovable(e.target.checked)} /> A document at status: review waits on you
        </label>
        {approvable ? <Field label="What you are asked" value={ask} onChange={(e) => setAsk(e.target.value)} /> : null}
        <div style={row}>
          <Button type="submit" variant="primary" disabled={!nameOk || busy}>
            Define the kind
          </Button>
        </div>
      </form>
      {answered.length > 0 ? (
        <section aria-label="Lately answered" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
          <strong style={{ fontSize: 15 }}>Lately answered</strong>
          {answered.map((p) => (
            <p key={p.number} style={muted}>
              #{p.number} the {p.kind} gate {p.approvable ? 'on' : 'off'}: {p.agree ? 'agreed' : 'declined'}
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
